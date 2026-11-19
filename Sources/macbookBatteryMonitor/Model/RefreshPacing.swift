import Foundation

/// 定時更新的間隔：螢幕關著或切換到其他使用者時沒人看得到，拉長間隔並放寬誤差，讓系統能合併喚醒。
/// 充電排程與通知照常判斷，只是比較慢（充電上限由系統在硬體層執行，晚幾十秒調整不影響）。
enum RefreshPacing {
    static let unseenInterval: TimeInterval = 30

    static func interval(base: TimeInterval, unseen: Bool) -> TimeInterval {
        unseen ? max(base, unseenInterval) : base
    }

    /// 平常誤差不超過 0.3 秒，下一次更新才配得到 1 秒前預先讀的變壓器輸入；沒人看時不預讀，誤差放寬到間隔的一成
    static func tolerance(base: TimeInterval, unseen: Bool) -> TimeInterval {
        unseen ? interval(base: base, unseen: true) / 10 : min(base * 0.2, 0.3)
    }
}
