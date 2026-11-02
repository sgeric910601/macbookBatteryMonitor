import AppKit

/// 剪貼簿歷史（整理在 ClipboardHistory）。macOS 沒有剪貼簿改變的通知，只能定時看變更次數：
/// 啟用時每 0.75 秒讀一個整數，有變才讀內容；停用時停掉計時器並清空。內容只放在記憶體
@MainActor
final class ClipboardHistoryController {
    static let shared = ClipboardHistoryController()

    private(set) var history = ClipboardHistory()
    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount

    var isRunning: Bool { timer != nil }

    func apply(enabled: Bool) {
        guard enabled else {
            timer?.invalidate()
            timer = nil
            history.clear()
            return
        }
        guard timer == nil else { return }
        lastChange = NSPasteboard.general.changeCount
        let timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { _ in
            MainActor.assumeIsolated { ClipboardHistoryController.shared.check() }
        }
        // 允許系統把喚醒合併，省電
        timer.tolerance = 0.25
        self.timer = timer
    }

    private func check() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount
        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard ClipboardHistory.shouldRecord(types: types), let text = pasteboard.string(forType: .string) else { return }
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

    func clear() { history.clear() }
}
