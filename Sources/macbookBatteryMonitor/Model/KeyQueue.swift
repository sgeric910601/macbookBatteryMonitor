import Foundation

/// 中文輸入法的 Shift 半形：要先送出組字的按鍵交給主執行緒排隊送出。
/// 只放排隊的狀態與判斷，時間由呼叫端傳入；鎖和事件處理留在 InputSourceFix
struct KeyQueue {
    /// 主執行緒超過這麼久沒送出任何排隊的按鍵，就當作卡住：放棄排隊、直接放行，整台 Mac 的鍵盤不會跟著卡死
    static let stuckAfter: Double = 1.0

    /// 交給主執行緒、還沒送出的按鍵數
    private(set) var queued = 0
    /// 開始排隊（或上次送出）的時間
    private(set) var since: Double = 0
    /// 每次放棄、停止、啟動加一；主執行緒拿到舊編號的按鍵就丟掉
    private(set) var generation = 0

    var isQueuing: Bool { queued > 0 }

    /// 放棄目前的排隊；舊編號的按鍵之後送來會被丟掉
    mutating func reset() {
        generation += 1
        queued = 0
    }

    /// 主執行緒卡住太久時放棄排隊；回傳 true 表示放棄了（呼叫端要一併重設按住 Shift 的狀態）
    mutating func dropIfStuck(now: Double) -> Bool {
        guard queued > 0, now - since > Self.stuckAfter else { return false }
        reset()
        return true
    }

    /// 送出組字期間系統自動產生的重複按鍵：之後一次送出會冒出一串，丟掉；沒在排隊時照常重複
    func dropsRepeat(_ isRepeat: Bool) -> Bool { isRepeat && queued > 0 }

    /// 要先送出組字的按鍵要排隊；已經在排隊時後面的按鍵也要排，順序才不會亂。回傳是否排進去
    mutating func enqueueIfNeeded(commitFirst: Bool, now: Double) -> Bool {
        guard commitFirst || queued > 0 else { return false }
        if queued == 0 { since = now }
        queued += 1
        return true
    }

    /// 主執行緒送出一個排隊的按鍵；舊編號的不算。每送出一個就重新計時：主執行緒慢但還在處理時不算卡住
    mutating func sent(generation: Int, now: Double) {
        guard generation == self.generation else { return }
        queued = max(0, queued - 1)
        since = now
    }
}
