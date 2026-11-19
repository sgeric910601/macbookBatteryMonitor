import AppKit
import Observation

/// 剪貼簿歷史（整理在 ClipboardHistory）。macOS 沒有剪貼簿改變的通知，只能定時看變更次數：
/// 啟用時每 0.75 秒讀一個整數，有變才讀內容；停用、鎖定螢幕、睡眠時清空。內容只放在記憶體
@MainActor
@Observable
final class ClipboardHistoryController {
    static let shared = ClipboardHistoryController()

    private(set) var history = ClipboardHistory()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastChange = NSPasteboard.general.changeCount
    /// 背景正在讀內容；讀完前不開始下一次
    @ObservationIgnored private var reading = false
    /// 每次清空加一：讀到一半時鎖定螢幕或睡眠，讀完的內容不能在清空之後才加進去
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var clearObservers: [(NotificationCenter, NSObjectProtocol)] = []

    var isRunning: Bool { timer != nil }

    func apply(enabled: Bool) {
        guard enabled else {
            timer?.invalidate()
            timer = nil
            clear()
            for (center, observer) in clearObservers { center.removeObserver(observer) }
            clearObservers = []
            return
        }
        guard timer == nil else { return }
        // 離開座位（鎖定螢幕）或睡眠時清空，別人打開選單看不到之前複製的內容
        let clear: @Sendable (Notification) -> Void = { _ in MainActor.assumeIsolated { ClipboardHistoryController.shared.clear() } }
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        clearObservers = [
            (distributed, distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main, using: clear)),
            (workspace, workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: clear)),
        ]
        lastChange = NSPasteboard.general.changeCount
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
        // 讀的期間停用或清空了：不記
        guard timer != nil, generation == self.generation, let text else { return }
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
}
