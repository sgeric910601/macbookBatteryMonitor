import AppKit
import OSLog
import notify

/// 會擋住輸入的攔截（.defaultTap）還能不能運作，以及失去權限後的恢復（規則在 TapAccess）。
///
/// 使用者把 App 從「輔助使用」清單「移除」（不是關掉開關）時，AXIsProcessTrusted、IOHIDCheckAccess、
/// CGPreflightPostEventAccess 在這個行程裡會一直回答有權限（macOS 27.2 實測），但 WindowServer 已經不接受我們的攔截：
/// 每個事件都等到逾時才放行，再重新打開就一直重複，整台 Mac 越來越卡，最後只能強制重開機（#25）。
/// 唯一準的判斷是實際試建一個會擋住輸入的攔截：移除後馬上就建不起來。
/// 參考 LinearMouse 的做法（只參考行為）：有攔截在運作時定時試建，系統暫停攔截時也先試建再重新打開。
/// 建不起來就先放掉所有攔截（沒有副作用，Mac 馬上恢復），隔幾秒再試一次，還是建不起來才重新開啟 App；
/// 喚醒後一段時間內不試建。停用期間慢慢繼續試建，建得起來就恢復。
///
/// 規則：會擋住輸入的攔截一律用 createTap 建立、用 reenable 重新打開，才會受到這裡的檢查
final class EventTapAccess: @unchecked Sendable {
    static let shared = EventTapAccess()
    nonisolated static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "tapAccess")
    private static let relaunchKey = "tapAccessRelaunchAt"
    /// 有攔截在運作時多久試建一次；只有攔截開著才檢查，功能都關著時不耗電
    private static let interval = 10
    /// 第一次試建失敗後，隔多久再確認一次
    private static let confirmDelay: TimeInterval = 3
    /// 停用期間多久試建一次
    private static let pausedInterval = 30

    private enum State { case normal, confirming, paused }

    /// 試建與定時檢查都在這裡，不佔用主執行緒和攔截的執行緒
    private let queue = DispatchQueue(label: "com.kuan.batterymonitor.tapAccess", qos: .utility)
    private let lock = NSLock()
    // 以下由 lock 保護
    private var ports: [CFMachPort] = []
    private var state = State.normal
    private var lastWake: Date?
    // 只在 queue 上存取
    private var timer: DispatchSourceTimer?
    private var pausedTimer: DispatchSourceTimer?
    private var tccToken: Int32?
    private var tccCheckPending = false
    private var lastSuccessfulProbe: Date?
    /// 這次執行已經發過「已暫停」通知：暫停、恢復又暫停時不再重複發
    private var announcedPause = false

    /// 停用狀態（剛重開過又偵測到、或無法重開）：會擋住輸入的功能暫停，期間慢慢試建，建得起來就恢復
    var isLost: Bool { locked { state == .paused } }
    /// 進入或離開停用狀態、或誤判後恢復時，在主執行緒呼叫：依 isLost 停止或重新開始按鍵與滑鼠功能
    @MainActor var onStateChange: (() -> Void)?

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            locked { self.lastWake = Date() }
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// 建立會擋住輸入的攔截、掛到 loop 並列入檢查（還沒打開，由呼叫的人打開）。
    /// 正在確認或停用中時不建立
    func createTap(place: CGEventTapPlacement, mask: CGEventMask, callback: CGEventTapCallBack,
                   userInfo: UnsafeMutableRawPointer?, loop: CFRunLoop) -> CFMachPort? {
        guard locked({ state == .normal }),
              let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: place, options: .defaultTap,
                                           eventsOfInterest: mask, callback: callback, userInfo: userInfo) else { return nil }
        // 攔截剛好被作廢時建不出來源；建立途中剛好偵測到失去權限，這個也不能留
        let source: CFRunLoopSource? = CFMachPortCreateRunLoopSource(nil, port, 0)
        let tracked = source != nil && locked { () -> Bool in
            guard state == .normal else { return false }
            ports.append(port)
            return true
        }
        guard tracked, let source else {
            CFMachPortInvalidate(port)
            return nil
        }
        CFRunLoopAddSource(loop, source, .commonModes)
        queue.async { [self] in startTimer() }
        return port
    }

    /// 系統暫停了攔截（回應逾時、或檢查時發現）：先確認還建得起攔截才重新打開，建不起來就是權限被移除
    func reenable(_ port: CFMachPort) {
        queue.async { [self] in
            guard locked({ state == .normal }), CFMachPortIsValid(port) else { return }
            // 剛喚醒時試建可能暫時失敗：等寬限期過了再處理
            if let left = TapAccess.wakeGraceLeft(lastWake: locked({ lastWake }), now: Date()) {
                return queue.asyncAfter(deadline: .now() + left) { [self] in reenable(port) }
            }
            guard probe() else { return handleLoss(reason: "重新打開前試建失敗") }
            CGEvent.tapEnable(tap: port, enable: true)
        }
    }

    /// 啟動時：剛才是因為失去權限而重新開啟的，用通知說明
    @MainActor func announceIfRelaunched() {
        let last = UserDefaults.standard.object(forKey: Self.relaunchKey) as? Date
        guard TapAccess.shouldAnnounce(lastRelaunch: last, now: Date()) else { return }
        Notifier.shared.notifyTapAccessRelaunched()
    }

    private func startTimer() {
        // 權限清單一有變動（包括「移除」，27.2 實測會發）就立刻檢查，不必等下一次定時檢查。
        // 只是提早觸發，收不到也還有定時檢查；稍等一下再試建，讓系統先套用變更；連續收到只檢查一次
        if tccToken == nil {
            var token: Int32 = 0
            if notify_register_dispatch("com.apple.tcc.access.changed", &token, queue, { [weak self] _ in
                guard let self, !self.tccCheckPending else { return }
                self.tccCheckPending = true
                self.queue.asyncAfter(deadline: .now() + 0.3) {
                    self.tccCheckPending = false
                    self.check(reason: "權限清單變動後試建失敗")
                }
            }) == NOTIFY_STATUS_OK { tccToken = token }
        }
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(Self.interval), repeating: .seconds(Self.interval), leeway: .seconds(2))
        timer.setEventHandler { [weak self] in self?.check(reason: "定時檢查試建失敗") }
        timer.resume()
        self.timer = timer
    }

    private func check(reason: String) {
        // 功能自己停掉的攔截已經作廢：不再檢查；都停了就連計時器一起停
        let idle = locked {
            ports.removeAll { !CFMachPortIsValid($0) }
            return ports.isEmpty || state != .normal
        }
        if idle {
            timer?.cancel()
            timer = nil
            return
        }
        if TapAccess.wakeGraceLeft(lastWake: locked({ lastWake }), now: Date()) != nil { return }
        if !probe() { handleLoss(reason: reason) }
    }

    /// 試建一次。攔截一直被系統暫停時 reenable 會一直被呼叫：1 秒內成功過就不再試建
    private func probe() -> Bool {
        if let last = lastSuccessfulProbe, Date().timeIntervalSince(last) < 1 { return true }
        let ok = Self.canCreateTap()
        lastSuccessfulProbe = ok ? Date() : nil
        return ok
    }

    /// 試建一個會擋住輸入的攔截，建好立刻關掉再作廢（不掛到任何 run loop）。
    /// 失敗時每隔 0.5 秒再試，共 3 次：喚醒、鎖定畫面時偶發的失敗不會被當成沒權限
    static func canCreateTap() -> Bool {
        for attempt in 0..<3 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.5) }
            if let probe = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap,
                                             eventsOfInterest: CGEventMask(1) << CGEventType.scrollWheel.rawValue,
                                             callback: { _, _, event, _ in Unmanaged.passUnretained(event) }, userInfo: nil) {
                CGEvent.tapEnable(tap: probe, enable: false)
                CFMachPortInvalidate(probe)
                return true
            }
        }
        return false
    }

    /// 第一次試建失敗：先放掉所有攔截（事件不再等我們，Mac 馬上恢復），之後再決定要不要重開
    private func handleLoss(reason: String) {
        let ports: [CFMachPort]? = locked {
            guard state == .normal else { return nil }
            state = .confirming
            defer { self.ports = [] }
            return self.ports
        }
        guard let ports else { return }
        for port in ports where CFMachPortIsValid(port) {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        timer?.cancel()
        timer = nil
        lastSuccessfulProbe = nil
        Self.log.error("無法建立會擋住輸入的攔截（\(reason, privacy: .public)）：已放掉 \(ports.count) 個攔截")
        // 只是關掉開關：各功能自己的檢查會在重新允許後重新開始，不必再確認
        guard AXIsProcessTrusted() else {
            locked { state = .normal }
            Self.log.notice("輔助使用權限被關閉：等重新允許後各功能自己重新開始")
            return
        }
        queue.asyncAfter(deadline: .now() + Self.confirmDelay) { [self] in confirmLoss() }
    }

    /// 放掉攔截幾秒後再試一次：建得起來就是暫時失敗（恢復各功能），還是建不起來才重開或停用
    private func confirmLoss() {
        if Self.canCreateTap() {
            locked { state = .normal }
            Self.log.notice("再次試建成功，當成暫時失敗，恢復各功能")
            notifyStateChange()
            return
        }
        let recovery = TapAccess.recovery(trustedReported: AXIsProcessTrusted(),
                                          lastRelaunch: UserDefaults.standard.object(forKey: Self.relaunchKey) as? Date,
                                          now: Date(), canRelaunch: AppLocation.problem() == nil)
        switch recovery {
        case .waitForPermission:
            locked { state = .normal }
            Self.log.notice("輔助使用權限被關閉：等重新允許後各功能自己重新開始")
        case .relaunch:
            DispatchQueue.main.async { MainActor.assumeIsolatedCompat { Self.relaunch() } }
        case .disable:
            pause()
        }
    }

    @MainActor private static func relaunch() {
        do {
            try AppLocation.reopenAfterExit(Bundle.main.bundleURL)
            UserDefaults.standard.set(Date(), forKey: relaunchKey)
            log.notice("重新開啟 App，讓權限重新查詢")
            NSApp.terminate(nil)
        } catch {
            log.error("無法重新開啟：\(error.localizedDescription, privacy: .public)")
            shared.queue.async { shared.pause() }
        }
    }

    /// 停用會擋住輸入的功能，每隔一段時間試建，建得起來就恢復
    private func pause() {
        locked { state = .paused }
        Self.log.error("停用會擋住輸入的攔截，之後每 \(Self.pausedInterval) 秒試建，成功就恢復")
        notifyStateChange()
        if !announcedPause {
            announcedPause = true
            DispatchQueue.main.async { MainActor.assumeIsolatedCompat { Notifier.shared.notifyTapAccessDisabled() } }
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(Self.pausedInterval), repeating: .seconds(Self.pausedInterval), leeway: .seconds(5))
        timer.setEventHandler { [weak self] in
            guard let self, Self.canCreateTap() else { return }
            pausedTimer?.cancel()
            pausedTimer = nil
            locked { self.state = .normal }
            Self.log.notice("又建得起攔截了，恢復按鍵與滑鼠功能")
            notifyStateChange()
        }
        pausedTimer?.cancel()
        pausedTimer = timer
        timer.resume()
    }

    private func notifyStateChange() {
        DispatchQueue.main.async { MainActor.assumeIsolatedCompat { Self.shared.onStateChange?() } }
    }
}
