import AppKit
import ApplicationServices
import OSLog

/// 取代 Cmd+Tab 的事件攔截。和捲動方向一樣在自己的高優先執行緒上跑 run loop，
/// 主執行緒忙的時候點擊與按鍵也不用等；只攔按鍵事件，功能關掉時完全不攔截。
/// 判斷用的狀態（Cmd+Tab 進行中）用鎖保護，要做的事交回主執行緒
final class InputTap: @unchecked Sendable {
    struct Config: Equatable {
        var keys = false
    }

    enum Health { case ok, disabled, invalid, stopped }

    static let shared = InputTap()
    static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "input")

    private let lock = NSLock()
    private var config = Config()
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private var keys = SwitcherKeys()

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var isRunning: Bool { locked { port != nil } }
    var currentConfig: Config { locked { config } }

    /// 建立攔截並開一條執行緒跑它；沒有權限時回傳 false
    func start(_ new: Config) -> Bool {
        stop()
        guard new.keys else { return true }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        locked {
            config = new
            keys = SwitcherKeys(shortcuts: keys.shortcuts, vimKeys: keys.vimKeys, releaseCommits: keys.releaseCommits)
        }
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                               eventsOfInterest: mask, callback: inputTapCallback,
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
            // stop() 作廢攔截、停掉 run loop 後，這條執行緒就結束
            CFRunLoopRun()
        }
        thread.name = "視窗切換"
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
                self.config = Config()
            }
            return (self.port, self.runLoop)
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let loop { CFRunLoopStop(loop) }
    }

    /// 設定改變時換上新的快捷鍵（切換中的狀態會結束）
    func setSwitcher(shortcuts: [SwitcherShortcut], vimKeys: Bool, releaseCommits: Bool) {
        locked { keys = SwitcherKeys(shortcuts: shortcuts, vimKeys: vimKeys, releaseCommits: releaseCommits) }
    }

    /// 切換中要按住的修飾鍵；沒在切換時為 nil
    func activeHold() -> SwitcherShortcut.Modifiers? {
        locked { keys.activeSlot.map { keys.shortcuts[$0].hold } }
    }

    /// 切換已經由別處結束（點了某個視窗、沒有視窗可選、補收尾）：按鍵判斷也一起結束
    func cancelSwitching() {
        locked { keys = SwitcherKeys(shortcuts: keys.shortcuts, vimKeys: keys.vimKeys, releaseCommits: keys.releaseCommits) }
    }

    func health() -> Health {
        guard let port = locked({ self.port }) else { return .stopped }
        guard CFMachPortIsValid(port) else { return .invalid }
        return CGEvent.tapIsEnabled(tap: port) ? .ok : .disabled
    }

    func reenable(reason: String) {
        guard let port = locked({ self.port }) else { return }
        Self.log.notice("事件攔截被暫停（\(reason, privacy: .public)），重新打開")
        // 暫停期間可能漏掉放開的事件：結束進行中的切換，免得狀態殘留
        cancelSwitching()
        DispatchQueue.main.async { MainActor.assumeIsolated { WindowSwitcher.shared.handle(.cancel) } }
        CGEvent.tapEnable(tap: port, enable: true)
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            reenable(reason: type == .tapDisabledByTimeout ? "回應逾時" : "使用者輸入")
            return pass
        case .keyDown, .keyUp, .flagsChanged:
            let flags = event.flags
            var modifiers = SwitcherShortcut.Modifiers()
            if flags.contains(.maskCommand) { modifiers.insert(.command) }
            if flags.contains(.maskAlternate) { modifiers.insert(.option) }
            if flags.contains(.maskControl) { modifiers.insert(.control) }
            if flags.contains(.maskShift) { modifiers.insert(.shift) }
            let kind: SwitcherKeys.Event = type == .keyDown ? .keyDown : type == .keyUp ? .keyUp : .flagsChanged
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let result = locked {
                config.keys ? keys.handle(kind, keyCode: code, modifiers: modifiers) : (swallow: false, action: .none)
            }
            if result.action != .none {
                let action = result.action
                DispatchQueue.main.async { MainActor.assumeIsolated { WindowSwitcher.shared.handle(action) } }
            }
            return result.swallow ? nil : pass
        default:
            return pass
        }
    }
}

private func inputTapCallback(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<InputTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}

/// 主執行緒這邊：依設定開始或停止攔截、每 5 秒檢查一次、追蹤最前面的 App
@MainActor
final class InputController {
    static let shared = InputController()

    /// 開始或停止時通知（設定頁的狀態跟著更新）
    var onChange: (() -> Void)?

    private var wanted = InputTap.Config()
    private var watchdog: Timer?

    var isRunning: Bool { InputTap.shared.isRunning }

    func apply(keys: Bool) {
        let new = InputTap.Config(keys: keys)
        guard new != wanted || (new != InputTap.Config() && !isRunning) else { return }
        wanted = new
        guard keys else {
            watchdog?.invalidate()
            watchdog = nil
            InputTap.shared.stop()
            WindowTracker.shared.stop()
            WindowSwitcher.shared.handle(.cancel)
            WindowThumbnails.shared.purge()
            InputTap.log.notice("停止攔截")
            onChange?()
            return
        }
        start(reason: "設定改變或啟動")
        if watchdog == nil {
            // 系統會在回應逾時、睡眠喚醒或權限變動時暫停甚至作廢攔截：每 5 秒檢查一次
            watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                MainActor.assumeIsolated { InputController.shared.check() }
            }
        }
    }

    private func check() {
        if wanted.keys, AXIsProcessTrusted(), !WindowTracker.shared.isRunning { WindowTracker.shared.start() }
        switch InputTap.shared.health() {
        case .ok: return
        case .disabled: InputTap.shared.reenable(reason: "檢查時發現被暫停")
        case .invalid, .stopped: start(reason: "定時檢查")
        }
    }

    private func start(reason: String) {
        guard AXIsProcessTrusted() else {
            onChange?()
            return
        }
        let started = InputTap.shared.start(wanted)
        if wanted.keys { WindowTracker.shared.start() } else { WindowTracker.shared.stop() }
        InputTap.log.notice("開始攔截（\(reason, privacy: .public)）：\(started ? "成功" : "失敗", privacy: .public)")
        onChange?()
    }
}
