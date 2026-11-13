import AppKit
import ApplicationServices
import OSLog

/// 視窗吸附（判斷在 WindowSnap）。只監聽滑鼠（listenOnly），拖曳本身照系統原本的方式進行：
/// 拖動開始時記下最前面那個視窗的位置，之後位置跟著動才算在拖視窗；拖到螢幕邊緣顯示預覽框，放開才排版。
/// 系統內建的「拖到螢幕邊緣排版」開著時不動作，免得兩邊搶著排。需要「輔助使用」權限
@MainActor
final class WindowSnapController {
    static let shared = WindowSnapController()
    nonisolated static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "windowSnap")

    /// 權限被撤銷或系統讓攔截失效時也會反映出來
    var isRunning: Bool { port.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } ?? false }
    private var port: CFMachPort?
    private var watchdog: Timer?

    private struct Drag {
        var window: AXUIElement?
        var start: CGRect?
        var moving = false
        var lastCheck: CFTimeInterval = 0
        var zone: WindowSnap.Zone?
        var target: CGRect?
    }
    private var drag: Drag?
    /// 系統內建的拖到邊緣排版是 macOS 15 才有的
    private static let systemHasTiling = ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0))
    private var preview: NSPanel?

    @discardableResult
    func apply(enabled: Bool) -> Bool {
        guard enabled else {
            stop()
            return true
        }
        // 權限被收回：舊的攔截已經收不到事件，停掉；重新允許後 AppDelegate 的定時檢查會再呼叫這裡重新開始
        guard AXIsProcessTrusted() else {
            stop()
            return false
        }
        // 作廢的攔截（重建失敗留下的）先清掉再重建
        if let port, !CFMachPortIsValid(port) { stop() }
        guard port == nil else { return isRunning }
        let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                           eventsOfInterest: mask, callback: windowSnapCallback, userInfo: nil) else { return false }
        // 攔截剛好被作廢時建不出來源
        guard let source = CFMachPortCreateRunLoopSource(nil, port, 0) as CFRunLoopSource? else {
            CFMachPortInvalidate(port)
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated {
                WindowSnapController.shared.keepAlive()
            }
        }
        Self.log.notice("開始監聽視窗拖曳")
        return true
    }

    /// 系統暫停攔截時重新打開；失效（例如權限被撤銷又給回）時重建
    private func keepAlive() {
        guard let port else { return }
        // 權限被撤銷：重新打開只會一直被系統逾時暫停，整台 Mac 的輸入跟著卡。停掉，權限回來後由 AppDelegate 每 5 秒的檢查重新開始
        if !AXIsProcessTrusted() {
            stop()
        } else if !CFMachPortIsValid(port) {
            stop()
            apply(enabled: true)
        } else if !CGEvent.tapIsEnabled(tap: port) {
            CGEvent.tapEnable(tap: port, enable: true)
        }
    }

    private func stop() {
        watchdog?.invalidate()
        watchdog = nil
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        port = nil
        drag = nil
        preview?.orderOut(nil)
    }

    fileprivate func reenable() {
        if let port, AXIsProcessTrusted() { CGEvent.tapEnable(tap: port, enable: true) }
    }

    fileprivate func handle(_ type: CGEventType, location: CGPoint) {
        switch type {
        case .leftMouseDown:
            // 系統內建的吸附開著時完全不動作
            let stored = UserDefaults(suiteName: "com.apple.WindowManager")?.object(forKey: "EnableTilingByEdgeDrag") as? Int
            drag = WindowSnap.systemTilingOff(stored: stored, systemHasTiling: Self.systemHasTiling) ? Drag() : nil
        case .leftMouseDragged:
            guard var current = drag else { return }
            let now = CACurrentMediaTime()
            if current.start == nil {
                // 第一次拖動：記下最前面那個視窗的位置
                current.window = Self.focusedWindow()
                current.start = current.window.flatMap(Self.frame(of:))
                current.lastCheck = now
            } else if !current.moving, now - current.lastCheck > 0.08, let window = current.window, let start = current.start {
                // 每 0.08 秒看一次視窗有沒有跟著動，不是每個拖動事件都去問 App
                current.lastCheck = now
                current.moving = Self.frame(of: window).map { WindowSnap.isWindowDrag(from: start, to: $0) } ?? false
            }
            if current.moving, let screen = Self.screen(containing: location) {
                let zone = WindowSnap.zone(at: location, screen: screen.full, others: screen.others)
                if zone != current.zone {
                    current.zone = zone
                    current.target = zone.map { WindowSnap.target($0, visible: screen.visible) }
                    showPreview(current.target)
                }
            }
            drag = current
        case .leftMouseUp:
            guard let finished = drag else { return }
            drag = nil
            showPreview(nil)
            guard finished.moving, let target = finished.target, let window = finished.window else { return }
            // 等系統做完這次拖曳再排版，否則會被最後一個拖動位置蓋過去
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                Self.set(window, position: target.origin)
                Self.set(window, size: target.size)
                Self.set(window, position: target.origin)
            }
        default:
            return
        }
    }

    // MARK: - 預覽框

    private func showPreview(_ rect: CGRect?) {
        guard let rect, let primary = NSScreen.screens.first else {
            preview?.orderOut(nil)
            return
        }
        let panel = preview ?? {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.ignoresMouseEvents = true
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
            view.layer?.borderWidth = 2
            view.layer?.cornerRadius = 10
            panel.contentView = view
            preview = panel
            return panel
        }()
        // 左上角為原點換成 AppKit 的左下角為原點
        let frame = CGRect(x: rect.minX, y: primary.frame.height - rect.maxY, width: rect.width, height: rect.height).insetBy(dx: 4, dy: 4)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    // MARK: - 「輔助使用」與螢幕

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.1)
        guard let value = attribute(element, kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let window = value as! AXUIElement
        // 視窗元素不會沿用 App 元素的等待上限：之後讀寫位置、大小都在主執行緒上
        AXUIElementSetMessagingTimeout(window, 0.1)
        return window
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

    /// 滑鼠所在的螢幕：整個範圍、可用範圍與其他螢幕的範圍，都換成左上角為原點的全域座標
    private static func screen(containing point: CGPoint) -> (full: CGRect, visible: CGRect, others: [CGRect])? {
        guard let primary = NSScreen.screens.first else { return nil }
        let height = primary.frame.height
        func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: height - r.maxY, width: r.width, height: r.height) }
        let screens = NSScreen.screens.map { (full: flip($0.frame), visible: flip($0.visibleFrame)) }
        guard let current = screens.first(where: { $0.full.contains(point) }) else { return nil }
        return (current.full, current.visible, screens.map(\.full).filter { $0 != current.full })
    }
}

private func windowSnapCallback(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo _: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let location = event.location
    MainActor.assumeIsolated {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            WindowSnapController.shared.reenable()
        } else {
            WindowSnapController.shared.handle(type, location: location)
        }
    }
    return Unmanaged.passUnretained(event)
}
