import AppKit
import ApplicationServices
import OSLog

/// 綠色按鈕改成放大（計算在 WindowMaximize）。左鍵按下時問「輔助使用」點到的是什麼，是視窗的全螢幕（綠色）按鈕才接手：
/// 攔下按下與放開，把視窗放大到填滿螢幕的可用範圍，再按一次還原。按著 Option 時照系統原本的行為。
/// 查詢在自己的執行緒上做，最多等 15 毫秒，來不及就當作不是綠色按鈕、照常放行，不會拖慢點擊。需要「輔助使用」權限
@MainActor
final class WindowMaximizeController {
    static let shared = WindowMaximizeController()
    nonisolated static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "windowMaximize")

    private let tap = WindowMaximizeTap()
    private var memory = WindowMaximize()
    private var watchdog: Timer?

    var isRunning: Bool { tap.isRunning }

    @discardableResult
    func apply(enabled: Bool) -> Bool {
        guard enabled else {
            watchdog?.invalidate()
            watchdog = nil
            tap.stop()
            return true
        }
        guard AXIsProcessTrusted() else { return false }
        if tap.onButton == nil {
            // 只設定一次：攔截執行緒讀的時候不會讀到改到一半的值
            tap.onButton = { button in
                DispatchQueue.main.async { MainActor.assumeIsolated { WindowMaximizeController.shared.toggle(button) } }
            }
        }
        if !tap.isRunning {
            let started = tap.start()
            Self.log.notice("綠色按鈕放大：\(started ? "開始" : "失敗", privacy: .public)")
        }
        if watchdog == nil {
            watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                MainActor.assumeIsolated { WindowMaximizeController.shared.tap.keepAlive() }
            }
        }
        return tap.isRunning
    }

    private func toggle(_ button: AXUIElement) {
        guard let window = Self.window(of: button), let frame = Self.frame(of: window), let visible = Self.visibleFrame(containing: frame) else { return }
        let id = AX.windowID(of: window) ?? 0
        let target = memory.toggle(window: id, frame: frame, visible: visible)
        // 先移位置再改大小，最後再對一次位置：有些 App 改大小時會自己把視窗推回原位
        Self.set(window, position: target.origin)
        Self.set(window, size: target.size)
        Self.set(window, position: target.origin)
    }

    // MARK: - 「輔助使用」

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func window(of button: AXUIElement) -> AXUIElement? {
        guard let value = attribute(button, kAXWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let position = attribute(window, kAXPositionAttribute), let size = attribute(window, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    private static func set(_ window: AXUIElement, position: CGPoint) {
        var point = position
        if let value = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) }
    }

    private static func set(_ window: AXUIElement, size: CGSize) {
        var extent = size
        if let value = AXValueCreate(.cgSize, &extent) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) }
    }

    /// 視窗中心所在螢幕的可用範圍（不含選單列與 Dock），換成左上角為原點的全域座標
    private static func visibleFrame(containing frame: CGRect) -> CGRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        let height = primary.frame.height
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let converted = NSScreen.screens.map { screen -> (full: CGRect, visible: CGRect) in
            func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: height - r.maxY, width: r.width, height: r.height) }
            return (flip(screen.frame), flip(screen.visibleFrame))
        }
        return (converted.first { $0.full.contains(center) } ?? converted.first)?.visible
    }
}

/// 綠色按鈕的攔截：在自己的高優先執行緒上跑
final class WindowMaximizeTap: @unchecked Sendable {
    private let lock = NSLock()
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    /// 攔下了按下、放開也要攔下（只在攔截執行緒使用）
    private var swallowingUp = false
    private let systemWide: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        // 等點到的 App 回答最多 15 毫秒，來不及就當作不是綠色按鈕
        AXUIElementSetMessagingTimeout(element, 0.015)
        return element
    }()
    /// 只在攔截還沒啟動時設定
    var onButton: ((AXUIElement) -> Void)?

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var isRunning: Bool {
        guard let port = locked({ self.port }) else { return false }
        return CFMachPortIsValid(port) && CGEvent.tapIsEnabled(tap: port)
    }

    func keepAlive() {
        guard let port = locked({ self.port }) else { return }
        if !CFMachPortIsValid(port) {
            stop()
            _ = start()
        } else if !CGEvent.tapIsEnabled(tap: port) {
            CGEvent.tapEnable(tap: port, enable: true)
        }
    }

    func start() -> Bool {
        guard locked({ port }) == nil else { return isRunning }
        let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                               eventsOfInterest: mask, callback: windowMaximizeCallback,
                                               userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
                ready.signal()
                return
            }
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            locked {
                self.port = port
                self.runLoop = loop
            }
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "綠色按鈕"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return isRunning
    }

    func stop() {
        let (port, loop) = locked { () -> (CFMachPort?, CFRunLoop?) in
            defer {
                self.port = nil
                self.runLoop = nil
            }
            return (self.port, self.runLoop)
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let loop { CFRunLoopStop(loop) }
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout:
            if let port = locked({ self.port }) { CGEvent.tapEnable(tap: port, enable: true) }
            return pass
        case .leftMouseDown:
            swallowingUp = false
            // 按著 Option：照系統原本的行為；連點（雙擊標題列等）也不碰
            guard !event.flags.contains(.maskAlternate), event.getIntegerValueField(.mouseEventClickState) <= 1,
                  let onButton else { return pass }
            let point = event.location
            var element: AXUIElement?
            guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success, let element else { return pass }
            var subrole: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success,
                  subrole as? String == kAXFullScreenButtonSubrole as String else { return pass }
            swallowingUp = true
            onButton(element)
            return nil
        case .leftMouseUp:
            guard swallowingUp else { return pass }
            swallowingUp = false
            return nil
        default:
            return pass
        }
    }
}

private func windowMaximizeCallback(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<WindowMaximizeTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}
