import Foundation

/// 一種監控警示的狀態：條件持續 duration 秒才通知，只通知一次；回到正常（recovered）才會再通知
struct SustainedAlert {
    let duration: TimeInterval
    /// 兩次取樣隔太久（模組關掉、睡眠）就不算持續，重新計時
    static let maxGap: TimeInterval = 60

    private var since: Date?
    private var last: Date?
    private var fired = false

    init(duration: TimeInterval) { self.duration = duration }

    /// 回傳這次要不要通知
    mutating func update(high: Bool, recovered: Bool, at now: Date) -> Bool {
        defer { last = now }
        if recovered { fired = false }
        guard high else {
            since = nil
            return false
        }
        if let last, now.timeIntervalSince(last) > Self.maxGap { since = nil }
        let start = since ?? now
        since = start
        guard !fired, now.timeIntervalSince(start) >= duration else { return false }
        fired = true
        return true
    }
}

/// 各監控警示的門檻。恢復線和門檻之間留一段距離，數值在門檻附近來回時不會一直通知
enum MonitorAlertRules {
    /// CPU 總使用率 90% 以上持續 5 分鐘；降到 70% 以下才算恢復
    static let cpuDuration: TimeInterval = 300
    static func cpu(usage: Double) -> (high: Bool, recovered: Bool) { (usage >= 0.9, usage < 0.7) }

    /// 記憶體壓力「嚴重」持續 30 秒；回到「正常」才算恢復
    static let memoryDuration: TimeInterval = 30
    static func memory(_ pressure: MemoryPressure) -> (high: Bool, recovered: Bool) { (pressure == .critical, pressure == .normal) }

    /// 開機磁碟可用空間低於 10 GB 立即通知；回到 15 GB 以上才算恢復
    static let diskLow: UInt64 = 10_000_000_000
    static let diskRecovered: UInt64 = 15_000_000_000
    static func disk(available: UInt64) -> (high: Bool, recovered: Bool) { (available < diskLow, available >= diskRecovered) }
}
