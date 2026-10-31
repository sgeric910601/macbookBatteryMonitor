import AppKit
import Carbon
import OSLog

/// 中文輸入法的兩個困擾：
/// 1. Caps Lock 切換中英有延遲：macOS 為了防誤觸，Caps Lock 要按住一下才算數。用系統內建的 hidutil 把延遲設成 0
///    （只存在記憶體，所以每次啟動與睡眠喚醒都重設一次）。
/// 2. 按住 Shift 打字母變全形英文：按住 Shift 打第一個字母時暫時切到英文鍵盤，放開 Shift 切回原本的輸入法（判斷在 ShiftHalfWidth）。
///    攔截按鍵需要「輔助使用」權限；開關關掉時完全不攔截
@MainActor
final class InputSourceFix {
    static let shared = InputSourceFix()
    static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "inputSource")

    private let tap = ShiftTap()
    /// 切到英文鍵盤前的輸入法，放開 Shift 時切回去
    private var restoreTo: TISInputSource?
    private var sourceObserver: NSObjectProtocol?

    var isRunning: Bool { tap.isRunning }

    // MARK: Caps Lock

    /// 把 Caps Lock 延遲設成 0。參數固定，不經過 shell
    static func removeCapsLockDelay() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", #"{"CapsLockDelayOverride":0}"#]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            log.error("無法執行 hidutil：\(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Shift 半形

    /// 開始或停止攔截；需要攔截但沒有權限時回傳 false
    @discardableResult
    func applyShift(_ enabled: Bool) -> Bool {
        guard enabled else {
            tap.stop()
            if let sourceObserver { DistributedNotificationCenter.default().removeObserver(sourceObserver) }
            sourceObserver = nil
            restore()
            return true
        }
        guard AXIsProcessTrusted() else { return false }
        if sourceObserver == nil {
            // 輸入法改變時更新「目前是不是中文輸入法」，攔截執行緒不用自己呼叫 TIS
            sourceObserver = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
            ) { _ in MainActor.assumeIsolated { InputSourceFix.shared.updateIMEActive() } }
        }
        updateIMEActive()
        if !tap.isRunning {
            // 只在攔截還沒跑的時候設定，攔截執行緒讀它時不會同時被改
            tap.onAction = { action, event in
                DispatchQueue.main.async { MainActor.assumeIsolated { InputSourceFix.shared.perform(action, replay: event) } }
            }
            let started = tap.start()
            Self.log.notice("Shift 半形攔截：\(started ? "開始" : "失敗", privacy: .public)")
        }
        return tap.isRunning
    }

    private func updateIMEActive() {
        tap.setIMEActive(Self.isIME(TISCopyCurrentKeyboardInputSource().takeRetainedValue()))
    }

    /// 不能直接打 ASCII 的輸入法（注音、拼音、日文等）；英文鍵盤與其他拉丁字母鍵盤都不算
    private static func isIME(_ source: TISInputSource) -> Bool {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) else { return false }
        return !CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue())
    }

    /// 切回中文輸入法到真正生效前，後面的按鍵先排隊
    private var holding = false
    private var backlog: [(ShiftHalfWidth.Action, CGEvent?)] = []
    /// 等切回生效最多等這麼久
    private static let restoreTimeout: TimeInterval = 0.6

    /// 依序在主執行緒做：切輸入法、把攔下來的按鍵重新送出（切到英文鍵盤馬上生效，實測不用等）
    private func perform(_ action: ShiftHalfWidth.Action, replay event: CGEvent?) {
        guard !holding else {
            backlog.append((action, event))
            return
        }
        switch action {
        case .switchToASCII:
            let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            let ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
            restoreTo = current
            TISSelectInputSource(ascii)
            if let event { tap.replay(event) }
        case .restore:
            // 放開 Shift：先送出再切回。漏掉放開、由下一個字觸發時：這個字等切回之後才送出，才會打成注音。
            // 切回生效前攔截那邊也要把後面的按鍵交過來排隊
            let typedKey = event?.type == .keyDown
            // 先把攔截那邊設成排隊，再送出放開 Shift，中間不會有按鍵直接放行
            tap.setHolding(true)
            if let event, !typedKey { tap.replay(event) }
            guard let target = restore() else {
                tap.setHolding(false)
                if let event, typedKey { tap.replay(event) }
                return
            }
            if let event, typedKey { backlog.insert((.pass, event), at: 0) }
            holding = true
            waitForSource(target, deadline: CACurrentMediaTime() + Self.restoreTimeout)
        case .pass:
            if let event { tap.replay(event) }
        }
    }

    private func waitForSource(_ id: String, deadline: CFTimeInterval) {
        if Self.id(of: TISCopyCurrentKeyboardInputSource().takeRetainedValue()) == id || CACurrentMediaTime() > deadline {
            drain()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) {
            MainActor.assumeIsolated { InputSourceFix.shared.waitForSource(id, deadline: deadline) }
        }
    }

    private func drain() {
        holding = false
        tap.setHolding(false)
        var items = backlog[...]
        backlog = []
        while let item = items.popFirst() {
            perform(item.0, replay: item.1)
            // 又遇到一次切回：剩下的接在新的排隊前面
            if holding {
                // 切回時插在最前面的那個字要維持第一個
                backlog += Array(items)
                return
            }
        }
    }

    /// 切回原本的輸入法，回傳要等它生效的輸入法 ID。
    /// 呼叫前要先送出放開 Shift：實測在「文字編輯」先切回再送出放開時，選單列是注音、打出來卻是英文（原因未確認）
    @discardableResult
    private func restore() -> String? {
        guard let source = restoreTo else { return nil }
        restoreTo = nil
        TISSelectInputSource(source)
        return Self.id(of: source)
    }

    private static func id(of source: TISInputSource) -> String? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}

/// 按鍵攔截：在自己的高優先執行緒上跑（和捲動方向一樣），主執行緒忙時打字也不用等。
/// 要切輸入法時把這個按鍵攔下來，交給主執行緒切好再送出；主執行緒還有事沒做完時，後面的按鍵也一起排隊，順序不會亂
final class ShiftTap: @unchecked Sendable {
    /// 自己重新送出的事件帶這個標記，攔截時直接放行
    private static let replayMark: Int64 = 0x5348_4946_5448  // "SHIFTH"

    private let lock = NSLock()
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private var logic = ShiftHalfWidth()
    private var imeActive = false
    /// 交給主執行緒、還沒送出的按鍵數
    private var queued = 0
    /// 開始排隊的時間；主執行緒卡住太久時攔截這邊自己放行，整台 Mac 的鍵盤不會跟著卡死
    private var queuedSince: CFTimeInterval = 0
    private static let stuckAfter: CFTimeInterval = 1.0
    var onAction: ((ShiftHalfWidth.Action, CGEvent?) -> Void)?

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var isRunning: Bool { locked { port != nil } }
    func setIMEActive(_ value: Bool) { locked { imeActive = value } }
    func setHolding(_ on: Bool) { locked { on ? enqueue() : (queued = max(0, queued - 1)) } }

    /// 只在鎖裡呼叫
    private func enqueue() {
        if queued == 0 { queuedSince = CACurrentMediaTime() }
        queued += 1
    }

    func start() -> Bool {
        guard !isRunning else { return true }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                               eventsOfInterest: mask, callback: shiftTapCallback,
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
        thread.name = "Shift 半形"
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
                logic = ShiftHalfWidth()
                queued = 0
            }
            return (self.port, self.runLoop)
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let loop { CFRunLoopStop(loop) }
    }

    /// 主執行緒切好輸入法後，把攔下來的按鍵送出去
    func replay(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.replayMark)
        event.post(tap: .cgSessionEventTap)
        locked { queued = max(0, queued - 1) }
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = locked({ self.port }) { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayMark { return Unmanaged.passUnretained(event) }
        // 密碼欄等安全輸入：完全不碰
        if IsSecureEventInputEnabled() { return Unmanaged.passUnretained(event) }
        let flags = event.flags
        let input: ShiftHalfWidth.Event?
        switch type {
        case .keyDown:
            input = .keyDown(keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                             shift: flags.contains(.maskShift),
                             otherModifiers: !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty)
        case .flagsChanged where !flags.contains(.maskShift):
            input = .shiftReleased
        default:
            input = nil
        }
        guard let copy = event.copy() else { return Unmanaged.passUnretained(event) }
        let (action, deferIt) = locked { () -> (ShiftHalfWidth.Action, Bool) in
            if queued > 0, CACurrentMediaTime() - queuedSince > Self.stuckAfter {
                // 主執行緒沒在處理：放棄排隊、直接放行（排著的按鍵之後可能晚到或重複，總比鍵盤失靈好）
                queued = 0
                logic = ShiftHalfWidth()
            }
            let action = input.map { logic.handle($0, imeActive: imeActive) } ?? .pass
            let deferIt = action != .pass || queued > 0
            if deferIt { enqueue() }
            return (action, deferIt)
        }
        guard deferIt else { return Unmanaged.passUnretained(event) }
        onAction?(action, copy)
        return nil
    }
}

private func shiftTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<ShiftTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}
