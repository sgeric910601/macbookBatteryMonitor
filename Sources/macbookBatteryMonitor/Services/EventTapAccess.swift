import AppKit
import OSLog
import notify

/// 會擋住輸入的攔截（.defaultTap）還能不能運作，以及失去權限後的恢復（規則在 TapAccess）。
///
/// 使用者把 App 從「輔助使用」清單「移除」（不是關掉開關）時，AXIsProcessTrusted、IOHIDCheckAccess、
/// CGPreflightPostEventAccess 在這個行程裡會一直回答有權限（macOS 27.2 實測），但 WindowServer 已經不接受我們的攔截：
/// 每個事件都等到逾時才放行，再重新打開就一直重複，整台 Mac 越來越卡，最後只能強制重開機（#25）。
/// 唯一準的判斷是實際試建一個會擋住輸入的攔截：移除後馬上就建不起來。
/// 參考 LinearMouse 的做法（只參考行為）：有攔截在運作時定時試建，系統暫停攔截時也先試建再重新打開；
/// 建不起來就先放掉所有攔截（Mac 馬上恢復），再重新開啟 App。
///
/// 規則：會擋住輸入的攔截一律用 createTap 建立、用 reenable 重新打開，才會受到這裡的檢查
final class EventTapAccess: @unchecked Sendable {
    static let shared = EventTapAccess()
    nonisolated static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "tapAccess")
    private static let relaunchKey = "tapAccessRelaunchAt"
    /// 有攔截在運作時多久試建一次；只有攔截開著才檢查，功能都關著時不耗電
    private static let interval = 10

    /// 試建與定時檢查都在這裡，不佔用主執行緒和攔截的執行緒
    private let queue = DispatchQueue(label: "com.kuan.batterymonitor.tapAccess", qos: .utility)
    private let lock = NSLock()
    // 以下由 lock 保護
    private var ports: [CFMachPort] = []
    private var lost = false
    // 只在 queue 上存取
    private var timer: DispatchSourceTimer?
    private var tccToken: Int32?
    /// 已經排了一次權限變動後的檢查：通知連發（或被其他程式一直送）時只檢查一次
    private var tccCheckPending = false

    /// 停用狀態（剛重開過又偵測到）：等使用者重新開啟 App，期間不再建立攔截
    var isLost: Bool { locked { lost } }
    /// 進入停用狀態時呼叫：停掉所有按鍵與滑鼠功能，免得各功能自己的看門狗一直重建
    @MainActor var onDisabled: (() -> Void)?

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// 建立會擋住輸入的攔截並列入檢查。已經偵測到失去權限時不再建立（等重新開啟 App）
    func createTap(place: CGEventTapPlacement, mask: CGEventMask, callback: CGEventTapCallBack,
                   userInfo: UnsafeMutableRawPointer?) -> CFMachPort? {
        guard !locked({ lost }),
              let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: place, options: .defaultTap,
                                           eventsOfInterest: mask, callback: callback, userInfo: userInfo) else { return nil }
        // 建立途中剛好偵測到失去權限：這個也不能留
        let tracked = locked { () -> Bool in
            guard !lost else { return false }
            ports.append(port)
            return true
        }
        guard tracked else {
            CFMachPortInvalidate(port)
            return nil
        }
        queue.async { [self] in startTimer() }
        return port
    }

    /// 系統暫停了攔截（回應逾時、或檢查時發現）：先確認還建得起攔截才重新打開，建不起來就是權限被移除
    func reenable(_ port: CFMachPort) {
        queue.async { [self] in
            guard !locked({ lost }), CFMachPortIsValid(port) else { return }
            guard Self.canCreateTap() else { return handleLoss(reason: "重新打開前試建失敗") }
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
        // 只是提早觸發，收不到也還有定時檢查；稍等一下再試建，讓系統先套用變更
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
            return ports.isEmpty || lost
        }
        if idle {
            timer?.cancel()
            timer = nil
            return
        }
        if !Self.canCreateTap() { handleLoss(reason: reason) }
    }

    /// 試建一個會擋住輸入的攔截，建好立刻作廢（不掛到任何 run loop）。
    /// 失敗時每隔 0.5 秒再試，共 3 次：喚醒、鎖定畫面時偶發的失敗不會被當成沒權限，真的被移除也只多等 1 秒
    static func canCreateTap() -> Bool {
        for attempt in 0..<3 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.5) }
            if let probe = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap,
                                             eventsOfInterest: CGEventMask(1) << CGEventType.scrollWheel.rawValue,
                                             callback: { _, _, event, _ in Unmanaged.passUnretained(event) }, userInfo: nil) {
                CFMachPortInvalidate(probe)
                return true
            }
        }
        return false
    }

    private func handleLoss(reason: String) {
        let recovery = TapAccess.recovery(trustedReported: AXIsProcessTrusted(),
                                          lastRelaunch: UserDefaults.standard.object(forKey: Self.relaunchKey) as? Date, now: Date())
        let ports: [CFMachPort]? = locked {
            guard !lost else { return nil }
            // 只是關掉開關時，重新允許後還要能再建立攔截
            if recovery != .waitForPermission { lost = true }
            defer { self.ports = [] }
            return self.ports
        }
        guard let ports else { return }
        // 先放掉所有攔截：事件不再等我們，Mac 馬上恢復
        for port in ports where CFMachPortIsValid(port) {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        timer?.cancel()
        timer = nil
        Self.log.error("無法建立會擋住輸入的攔截（\(reason, privacy: .public)）：已放掉 \(ports.count) 個攔截")
        DispatchQueue.main.async { MainActor.assumeIsolated { Self.recover(recovery) } }
    }

    @MainActor private static func recover(_ recovery: TapAccess.Recovery) {
        let defaults = UserDefaults.standard
        let now = Date()
        switch recovery {
        case .waitForPermission:
            log.notice("輔助使用權限被關閉：等重新允許後各功能自己重新開始")
        case .relaunch:
            do {
                try AppLocation.reopenAfterExit(Bundle.main.bundleURL)
                defaults.set(now, forKey: relaunchKey)
                log.notice("重新開啟 App，讓權限重新查詢")
                NSApp.terminate(nil)
            } catch {
                log.error("無法重新開啟：\(error.localizedDescription, privacy: .public)")
                shared.onDisabled?()
                Notifier.shared.notifyTapAccessDisabled()
            }
        case .disable:
            // 剛重開過又偵測到：可能是誤判，不再重開；攔截維持停用，請使用者確認權限後自己重新開啟
            log.error("重新開啟後又偵測到，停用會擋住輸入的攔截，不再自動重開")
            shared.onDisabled?()
            Notifier.shared.notifyTapAccessDisabled()
        }
    }
}
