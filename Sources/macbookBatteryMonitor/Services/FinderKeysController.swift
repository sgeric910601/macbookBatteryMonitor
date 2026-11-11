import AppKit
import ApplicationServices
import Carbon
import OSLog

/// Finder 加強（判斷在 FinderKeys）。攔截在自己的執行緒上跑；只有 X、C、V、F2 而且 Finder 在最前面時才問
/// 「輔助使用」現在是不是在打字（最多等 50 毫秒），其他按鍵直接放行。要改寫的鍵：攔下原本的事件、另外送出新的按鍵
/// （直接改鍵盤送來的事件，Finder 不認），放開時也一樣。
/// 需要「輔助使用」權限；停用時完全不攔截
@MainActor
final class FinderKeysController {
    static let shared = FinderKeysController()
    nonisolated static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "finderKeys")

    private let tap = FinderKeysTap()
    private var watchdog: Timer?
    private var activationObserver: NSObjectProtocol?

    var isRunning: Bool { tap.isRunning }

    @discardableResult
    func apply(enabled: Bool) -> Bool {
        // 沒有權限（包括被收回）時也停掉；重新允許後 AppDelegate 的定時檢查會再呼叫這裡重新開始
        guard enabled, AXIsProcessTrusted() else {
            watchdog?.invalidate()
            watchdog = nil
            tap.stop()
            if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
            activationObserver = nil
            return !enabled
        }
        KeyboardLetters.shared.start()
        if activationObserver == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { _ in MainActor.assumeIsolated { FinderKeysController.shared.updateFrontApp() } }
        }
        updateFrontApp()
        if !tap.isRunning {
            // 被暫停或作廢的攔截先清掉再重建
            tap.stop()
            let started = tap.start()
            Self.log.notice("Finder 加強：\(started ? "開始" : "失敗", privacy: .public)")
        }
        if watchdog == nil {
            watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                MainActor.assumeIsolated { FinderKeysController.shared.tap.keepAlive() }
            }
        }
        return tap.isRunning
    }

    private func updateFrontApp() {
        let front = NSWorkspace.shared.frontmostApplication
        tap.setFinder(front?.bundleIdentifier == "com.apple.finder" ? front?.processIdentifier : nil)
    }
}

final class FinderKeysTap: @unchecked Sendable {
    private let lock = NSLock()
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private var logic = FinderKeys()
    /// Finder 在最前面時是它的「輔助使用」物件（等待上限只設在這個物件上），否則 nil
    private var finder: AXUIElement?
    /// 按下時改寫了的鍵：原本的鍵碼 → 改成的鍵與是否加 Option；放開時跟著改（只在攔截執行緒使用）
    private var remapped: [Int64: (keyCode: Int64, option: Bool, flags: CGEventFlags)] = [:]
    /// 自己送出的按鍵帶這個標記，攔截時直接放行
    private static let postedMark: Int64 = 0x4644_4B45_5953 // "FDKEYS"

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var isRunning: Bool {
        guard let port = locked({ self.port }) else { return false }
        return CFMachPortIsValid(port) && CGEvent.tapIsEnabled(tap: port)
    }

    func setFinder(_ pid: pid_t?) {
        let element = pid.map { pid -> AXUIElement in
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.05)
            return element
        }
        locked { finder = element }
    }

    func keepAlive() {
        guard let port = locked({ self.port }) else { return }
        // 權限被撤銷：重新打開只會一直被系統逾時暫停，整台 Mac 的輸入跟著卡。停掉，權限回來後由 AppDelegate 每 5 秒的檢查重新開始
        if !AXIsProcessTrusted() {
            stop()
        } else if !CFMachPortIsValid(port) {
            stop()
            _ = start()
        } else if !CGEvent.tapIsEnabled(tap: port) {
            EventTapAccess.shared.reenable(port)
        }
    }

    func start() -> Bool {
        guard locked({ port }) == nil else { return isRunning }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            let loop: CFRunLoop = CFRunLoopGetCurrent()
            guard let port = EventTapAccess.shared.createTap(place: .headInsertEventTap,
                                               mask: mask, callback: finderKeysCallback,
                                               userInfo: Unmanaged.passUnretained(self).toOpaque(), loop: loop) else {
                ready.signal()
                return
            }
            CGEvent.tapEnable(tap: port, enable: true)
            locked {
                self.port = port
                self.runLoop = loop
                logic = FinderKeys()
            }
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "Finder 加強"
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

    /// Finder 現在有焦點的元件是可以打字的欄位（改檔名、搜尋框、路徑列）
    private static func editingText(_ finder: AXUIElement) -> Bool {
        var focused: AnyObject?
        switch AXUIElementCopyAttributeValue(finder, kAXFocusedUIElementAttribute as CFString, &focused) {
        case .success: break
        // 沒有焦點元件：不是在打字
        case .noValue: return false
        // 查詢失敗或逾時：當作在打字，寧可不改寫也不要在改檔名時把 ⌘X、F2 改掉
        default: return true
        }
        guard let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let element = focused as! AXUIElement
        // 逾時是每個元件各自設定的，子元件不會沿用 Finder 的設定，而是用全域預設（約 6 秒），在攔截回呼裡會卡住鍵盤
        AXUIElementSetMessagingTimeout(element, 0.05)
        var role: AnyObject?
        switch AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) {
        case .success: break
        // 這個元件沒有 role：不是輸入欄位
        case .noValue, .attributeUnsupported: return false
        // 查詢失敗或逾時：和上面一樣當作在打字
        default: return true
        }
        return [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"].contains(role as? String ?? "")
    }

    private static let watchedKeys: Set<Int64> = [Int64(FinderKeys.xKey), Int64(FinderKeys.cKey), Int64(FinderKeys.vKey), Int64(FinderKeys.f2Key)]

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if type == .tapDisabledByTimeout, AXIsProcessTrusted(), let port = locked({ self.port }) { EventTapAccess.shared.reenable(port) }
            remapped = [:]
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.postedMark { return pass }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) != 0, remapped[code] != nil {
            // 按住 ⌘X 的自動重複：已經改寫過了，再送一次會重設剪下的狀態
            return nil
        }
        if type == .keyUp {
            // 放開跟著按下時的改寫：攔下原本的放開、送出改寫後的放開
            guard let mapped = remapped.removeValue(forKey: code) else { return pass }
            Self.post(mapped.keyCode, down: false, flags: mapped.flags, option: mapped.option)
            return nil
        }
        // 鍵碼是 US 的位置：字母不在那個位置的配置（Dvorak 等）不改寫
        guard Self.watchedKeys.contains(code), KeyLayout.usKeyCode(Int(code), character: KeyboardLetters.shared.letter(at: Int(code))) != nil,
              !IsSecureEventInputEnabled(), let finder = locked({ finder }) else { return pass }
        let flags = event.flags
        let command = flags.contains(.maskCommand)
        // 只有 ⌘X／⌘C／⌘V 和不按 ⌘ 的 F2 可能改寫：改檔名時打一般的 x、c、v 不做「輔助使用」查詢，打字不會卡
        guard command != (code == Int64(FinderKeys.f2Key)) else { return pass }
        let editing = Self.editingText(finder)
        // 剪貼簿的變更次數要問另一個程序：在鎖外面讀，主執行緒不會等在鎖上
        let change = NSPasteboard.general.changeCount
        let action = locked {
            logic.keyDown(keyCode: Int(code), command: command,
                          otherModifiers: !flags.intersection([.maskShift, .maskControl, .maskAlternate]).isEmpty,
                          finderFront: true, editingText: editing, pasteboardChange: change)
        }
        guard case let .remap(newCode, option) = action else { return pass }
        Self.post(Int64(newCode), down: true, flags: flags, option: option)
        remapped[code] = (Int64(newCode), option, flags)
        if code == Int64(FinderKeys.xKey) {
            // 剪下用的 ⌘C 做完後記下剪貼簿的變更次數，之後換掉了就取消剪下
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) { [self] in
                let change = NSPasteboard.general.changeCount
                locked { logic.copied(pasteboardChange: change) }
            }
        }
        return nil
    }

    /// 送出改寫後的按鍵給最前面的 App（Finder）；帶標記，自己的攔截直接放行
    private static func post(_ keyCode: Int64, down: Bool, flags: CGEventFlags, option: Bool) {
        guard let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: CGKeyCode(keyCode), keyDown: down) else { return }
        var newFlags = flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
        if option { newFlags.insert(.maskAlternate) }
        event.flags = newFlags
        event.setIntegerValueField(.eventSourceUserData, value: postedMark)
        event.post(tap: .cgSessionEventTap)
    }
}

private func finderKeysCallback(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<FinderKeysTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}
