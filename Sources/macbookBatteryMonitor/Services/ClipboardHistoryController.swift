import AppKit

/// 剪貼簿歷史（整理在 ClipboardHistory）。macOS 沒有剪貼簿改變的通知，只能定時看變更次數：
/// 啟用時每 0.75 秒讀一個整數，有變才讀內容；停用、鎖定螢幕、睡眠時清空。內容只放在記憶體
@MainActor
final class ClipboardHistoryController {
    static let shared = ClipboardHistoryController()

    private(set) var history = ClipboardHistory()
    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount
    /// 背景正在讀內容；讀完前不開始下一次
    private var reading = false
    /// 每次清空加一：讀到一半時鎖定螢幕或睡眠，讀完的內容不能在清空之後才加進去
    private var generation = 0
    private var clearObservers: [(NotificationCenter, NSObjectProtocol)] = []

    var isRunning: Bool { timer != nil }

    func apply(enabled: Bool) {
        guard enabled else {
            timer?.invalidate()
            timer = nil
            clear()
            for (center, observer) in clearObservers { center.removeObserver(observer) }
            clearObservers = []
            pausedBy = []
            return
        }
        guard clearObservers.isEmpty else { return }
        // 離開座位（鎖定螢幕）或睡眠時清空，別人打開選單看不到之前複製的內容
        let clear: @Sendable (Notification) -> Void = { _ in MainActor.assumeIsolated { ClipboardHistoryController.shared.clear() } }
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        clearObservers = [
            (distributed, distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main, using: clear)),
            (workspace, workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: clear)),
        ]
        // 螢幕鎖定或關掉時沒人能複製：暫停每 0.75 秒的檢查，解鎖、螢幕亮起後再開始（期間的變更在恢復時補讀）
        func on(_ center: NotificationCenter, _ name: Notification.Name, _ body: @escaping @MainActor () -> Void) {
            clearObservers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated(body) }))
        }
        on(distributed, .init("com.apple.screenIsLocked")) { ClipboardHistoryController.shared.pause(.locked) }
        on(distributed, .init("com.apple.screenIsUnlocked")) { ClipboardHistoryController.shared.resume(.locked) }
        on(workspace, NSWorkspace.screensDidSleepNotification) { ClipboardHistoryController.shared.pause(.screenOff) }
        on(workspace, NSWorkspace.screensDidWakeNotification) {
            ClipboardHistoryController.shared.reconcileLock()
            ClipboardHistoryController.shared.resume(.screenOff)
        }
        lastChange = NSPasteboard.general.changeCount
        startTimer()
    }

    private func startTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { _ in
            MainActor.assumeIsolated { ClipboardHistoryController.shared.check() }
        }
        // 允許系統把喚醒合併，省電
        timer.tolerance = 0.25
        self.timer = timer
    }

    private func check() {
        let change = NSPasteboard.general.changeCount
        guard change != lastChange, !reading else { return }
        lastChange = change
        reading = true
        let generation = generation
        // 內容可能很大（例如複製了整份記錄檔），在背景讀，不卡主執行緒
        DispatchQueue.global(qos: .utility).async {
            let pasteboard = NSPasteboard.general
            let types = (pasteboard.types ?? []).map(\.rawValue)
            var text = ClipboardHistory.shouldRecord(types: types) ? pasteboard.string(forType: .string).map { String($0.prefix(ClipboardHistory.maxLength)) } : nil
            // 檢查類型和讀內容之間剪貼簿被換掉（例如密碼工具剛好寫入標成機密的內容）：這次不記，下一輪會重新檢查新的內容
            if pasteboard.changeCount != change { text = nil }
            DispatchQueue.main.async { MainActor.assumeIsolated { ClipboardHistoryController.shared.finishRead(text, generation: generation) } }
        }
    }

    private func finishRead(_ text: String?, generation: Int) {
        reading = false
        // 讀的期間停用或清空了：不記（暫停不算，暫停前讀到的照記）
        guard !clearObservers.isEmpty, generation == self.generation, let text else { return }
        history.add(text)
    }

    /// 選回歷史裡的一筆：放回剪貼簿（會被當成最新的一筆，移到最前面）
    func restore(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        history.add(text)
        lastChange = pasteboard.changeCount
    }

    func clear() {
        generation += 1
        history.clear()
    }

    enum PauseReason { case locked, screenOff }
    /// 暫停檢查的原因；全部解除才恢復
    private var pausedBy: Set<PauseReason> = []

    private func pause(_ reason: PauseReason) {
        pausedBy.insert(reason)
        timer?.invalidate()
        timer = nil
    }

    /// 螢幕亮起時向系統確認是否還鎖著：萬一漏收鎖定或解鎖通知，檢查不會一直停住（或鎖著還在跑）
    private func reconcileLock() {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        if session?["CGSSessionScreenIsLocked"] as? Bool == true {
            pausedBy.insert(.locked)
        } else {
            pausedBy.remove(.locked)
        }
    }

    private func resume(_ reason: PauseReason) {
        pausedBy.remove(reason)
        guard pausedBy.isEmpty, !clearObservers.isEmpty, timer == nil else { return }
        startTimer()
        check()
    }
}
