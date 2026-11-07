import AppKit
import Carbon
import OSLog

/// 中文輸入法的兩個困擾：
/// 1. Caps Lock 切換中英有延遲：macOS 為了防誤觸，Caps Lock 要按住一下才算數。用系統內建的 hidutil 把延遲設成 0
///    （只存在記憶體，所以每次啟動與睡眠喚醒都重設一次）。
/// 2. 按住 Shift 打字母與符號變全形：把這些按鍵換成半形字，輸入法不切換（判斷在 ShiftHalfWidth）。
///    攔截按鍵需要「輔助使用」權限；開關關掉時完全不攔截
@MainActor
final class InputSourceFix {
    static let shared = InputSourceFix()
    nonisolated static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "inputSource")

    private let tap = ShiftTap()
    private var sourceObserver: NSObjectProtocol?
    /// 開關打開；監看攔截有沒有被系統暫停或作廢
    private var wanted = false
    private var watchdog: Timer?

    var isRunning: Bool { tap.health() == .ok }

    // MARK: Caps Lock

    /// 把 Caps Lock 延遲設成 0。參數固定，不經過 shell
    static func removeCapsLockDelay() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", #"{"CapsLockDelayOverride":0}"#]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { process in
            if process.terminationStatus != 0 { log.error("hidutil 結束碼 \(process.terminationStatus, privacy: .public)") }
        }
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
        wanted = enabled
        guard enabled else {
            watchdog?.invalidate()
            watchdog = nil
            // 停止會讓還排在主佇列的按鍵過期：主執行緒拿到時直接丟掉（見 ShiftTap.send）
            tap.stop()
            if let sourceObserver { DistributedNotificationCenter.default().removeObserver(sourceObserver) }
            sourceObserver = nil
            return true
        }
        if watchdog == nil {
            // 和捲動方向一樣：系統會在逾時、睡眠喚醒或權限變動時暫停甚至作廢攔截，每 5 秒檢查一次
            watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                MainActor.assumeIsolated { InputSourceFix.shared.check() }
            }
        }
        guard AXIsProcessTrusted() else { return false }
        if sourceObserver == nil {
            // 輸入法改變時更新「目前是不是中文輸入法」，攔截執行緒不用自己呼叫 TIS
            sourceObserver = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
            ) { _ in MainActor.assumeIsolated { InputSourceFix.shared.updateIMEActive() } }
        }
        updateIMEActive()
        if tap.onDeferred == nil {
            // 只設定一次、之後不再改：舊的攔截執行緒剛好還在讀時也不會讀到改到一半的值
            tap.onDeferred = { event, commit, generation in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { InputSourceFix.shared.send(event, commitFirst: commit, generation: generation) }
                }
            }
        }
        if tap.health() == .stopped {
            let started = tap.start()
            Self.log.notice("Shift 半形攔截：\(started ? "開始" : "失敗", privacy: .public)")
        }
        return isRunning
    }

    private func check() {
        guard wanted else { return }
        switch tap.health() {
        case .ok: return
        case .disabled: tap.reenable()
        case .invalid:
            Self.log.notice("Shift 半形攔截已失效，重建")
            tap.stop()
            applyShift(true)
        case .stopped:
            // 例如剛重新允許「輔助使用」
            applyShift(true)
        }
    }

    private func updateIMEActive() {
        tap.setIMEActive(Self.isChineseIME(TISCopyCurrentKeyboardInputSource().takeRetainedValue()))
    }

    private static func isChineseIME(_ source: TISInputSource) -> Bool {
        let asciiCapable = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable)
            .map { CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque($0).takeUnretainedValue()) } ?? true
        let languages = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)
            .flatMap { Unmanaged<CFArray>.fromOpaque($0).takeUnretainedValue() as? [String] } ?? []
        return ShiftHalfWidth.isChineseInputMethod(languages: languages, asciiCapable: asciiCapable)
    }

    /// 送出排隊的按鍵。commitFirst（按住 Shift 的第一個字）：先送出正在組的字。
    /// 重選同一個輸入法不會送出組字；請焦點 App 切到英文鍵盤再立刻切回會（實測，切回後系統記錄仍是原本的輸入法）
    private func send(_ event: CGEvent, commitFirst: Bool, generation: Int) {
        // 攔截那邊已經放行、停止或重建：不切換，按鍵由 send 丟掉
        if commitFirst, generation == tap.generation {
            let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            let ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
            // 只用焦點 App 的切換：退回 TISSelectInputSource 時焦點 App 常沒跟上，選單列和實際輸入法會不一致。
            // 做不到時不送出組字，代價是正在組字時這個字會被輸入法吃掉
            if FocusedInputSource.selectInFocusedApp(ascii), !FocusedInputSource.selectInFocusedApp(current) {
                Self.log.error("送出組字後切回原本的輸入法失敗")
                FocusedInputSource.select(current)
            }
        }
        tap.send(event, generation: generation)
    }
}

/// 按鍵攔截：在自己的高優先執行緒上跑（和捲動方向一樣），主執行緒忙時打字也不用等。
/// 半形轉換直接在這裡改事件；只有要先送出組字的按鍵交給主執行緒，那時後面的按鍵也一起排隊，順序不會亂
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
    /// 每次放行、停止、啟動加一；主執行緒拿到舊編號的按鍵就丟掉
    private var currentGeneration = 0
    /// 交給主執行緒的按鍵（已轉換好）、要不要先送出組字、編號。只在攔截還沒啟動時設定
    var onDeferred: ((CGEvent, Bool, Int) -> Void)?

    enum Health { case ok, disabled, invalid, stopped }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var generation: Int { locked { currentGeneration } }
    func setIMEActive(_ value: Bool) { locked { imeActive = value } }

    /// 只在鎖裡呼叫：放棄目前的排隊與狀態
    private func resetLocked() {
        currentGeneration += 1
        queued = 0
        logic = ShiftHalfWidth()
    }

    func health() -> Health {
        guard let port = locked({ self.port }) else { return .stopped }
        guard CFMachPortIsValid(port) else { return .invalid }
        return CGEvent.tapIsEnabled(tap: port) ? .ok : .disabled
    }

    func reenable() {
        if let port = locked({ self.port }) { CGEvent.tapEnable(tap: port, enable: true) }
    }

    func start() -> Bool {
        guard health() == .stopped else { return health() == .ok }
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
                resetLocked()
            }
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "Shift 半形"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return health() == .ok
    }

    func stop() {
        let (port, loop) = locked { () -> (CFMachPort?, CFRunLoop?) in
            defer {
                self.port = nil
                self.runLoop = nil
                resetLocked()
            }
            return (self.port, self.runLoop)
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let loop { CFRunLoopStop(loop) }
    }

    /// 主執行緒把排隊的按鍵送出去。舊編號的（主執行緒卡住超過 1 秒、攔截已停止）丟掉：
    /// 那時焦點可能已經換到別的 App，晚到的按鍵（含 Return）會送錯地方
    func send(_ event: CGEvent, generation: Int) {
        guard generation == self.generation else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.replayMark)
        event.post(tap: .cgSessionEventTap)
        locked {
            guard generation == currentGeneration else { return }
            queued = max(0, queued - 1)
            // 每送出一個就重新計時：主執行緒慢但還在處理時不算卡住
            queuedSince = CACurrentMediaTime()
        }
    }

    /// 改成不按 Shift、文字是半形字的按鍵
    private static func convert(_ event: CGEvent, keyCode: Int) {
        guard let text = ShiftHalfWidth.halfWidthText(keyCode: keyCode) else { return }
        let units = Array(text.utf16)
        event.flags.remove(.maskShift)
        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // 回應逾時被暫停才自己打開；因使用者輸入被系統暫停時尊重系統，交給每 5 秒的檢查
        if type == .tapDisabledByTimeout { reenable() }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // 暫停期間可能漏掉放開 Shift：重新開始算按住
            locked { logic = ShiftHalfWidth() }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayMark { return Unmanaged.passUnretained(event) }
        // 密碼欄等安全輸入：完全不碰
        if IsSecureEventInputEnabled() { return Unmanaged.passUnretained(event) }
        guard let onDeferred else { return Unmanaged.passUnretained(event) }
        let flags = event.flags
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let input: ShiftHalfWidth.Event?
        switch type {
        case .keyDown:
            input = .keyDown(keyCode: keyCode, shift: flags.contains(.maskShift),
                             otherModifiers: !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty)
        case .keyUp:
            input = .keyUp(keyCode: keyCode, shift: flags.contains(.maskShift))
        case .flagsChanged where !flags.contains(.maskShift):
            input = .shiftReleased
        default:
            input = nil
        }
        let isRepeat = type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let (action, deferIt, generation, drop) = locked { () -> (ShiftHalfWidth.Action, Bool, Int, Bool) in
            if queued > 0, CACurrentMediaTime() - queuedSince > Self.stuckAfter {
                // 主執行緒沒在處理：放棄排隊、直接放行，鍵盤不會跟著卡死
                resetLocked()
            }
            // 送出組字期間系統自動產生的重複按鍵：之後一次送出會冒出一串，丟掉；送出後照常重複
            if isRepeat, queued > 0 { return (.pass, false, currentGeneration, true) }
            // 不是中文輸入法、沒在按住、沒在排隊：直接放行
            guard imeActive || logic.holding || queued > 0 else { return (.pass, false, currentGeneration, false) }
            let action = input.map { logic.handle($0, imeActive: imeActive) } ?? .pass
            let deferIt = action == .halfWidth(commitFirst: true) || queued > 0
            if deferIt {
                if queued == 0 { queuedSince = CACurrentMediaTime() }
                queued += 1
            }
            return (action, deferIt, currentGeneration, false)
        }
        if drop { return nil }
        if action != .pass { Self.convert(event, keyCode: keyCode) }
        guard deferIt else { return Unmanaged.passUnretained(event) }
        guard let copy = event.copy() else {
            // 複製失敗：已轉換的原事件直接放行（不送出組字），先扣掉自己那一份
            send(event, generation: generation)
            return nil
        }
        onDeferred(copy, action == .halfWidth(commitFirst: true), generation)
        return nil
    }
}

private func shiftTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<ShiftTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}
