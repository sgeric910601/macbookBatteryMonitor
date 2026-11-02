import Foundation

/// 鍵盤清潔模式：擋下所有鍵盤事件，方便擦鍵盤；停手（沒按到鍵）滿設定的秒數才恢復。滑鼠與觸控板照常，才點得到「結束清潔」；
/// 時間到也會自動結束。Touch ID 指紋與電源鍵是硬體層級，不經過這裡。
/// 只做判斷，事件攔截與畫面在 KeyboardCleaningController
struct KeyboardCleaning {
    enum EventKind { case keyDown, keyUp, flagsChanged, systemKey, pointer }

    static let durations: [Int] = [30, 60, 120]
    static let defaultDuration = 60
    /// 不論怎麼按，從開始算最多這麼久一定恢復（鍵卡住、貓趴在鍵盤上時不會一直停用）
    static let hardLimit: TimeInterval = 300

    private(set) var until: Date?
    /// 停手多久後恢復（秒）
    private var idleSeconds: TimeInterval = 0
    private var startedAt: Date?

    var isActive: Bool { until != nil }

    static func validDuration(_ seconds: Int) -> Int { durations.contains(seconds) ? seconds : defaultDuration }

    mutating func start(seconds: Int, now: Date) {
        idleSeconds = TimeInterval(seconds)
        startedAt = now
        until = now.addingTimeInterval(idleSeconds)
    }

    /// 清潔中按到鍵：重新倒數，停手滿設定的秒數才恢復。按住不放的自動重複不算（鍵卡住時不會一直重設），
    /// 而且不會超過從開始算的 hardLimit
    mutating func keyPressed(now: Date, isRepeat: Bool = false) {
        guard isActive, !isRepeat, let startedAt else { return }
        until = min(now.addingTimeInterval(idleSeconds), startedAt.addingTimeInterval(Self.hardLimit))
    }

    mutating func stop() {
        until = nil
        startedAt = nil
    }

    func blocks(_ kind: EventKind) -> Bool { isActive && kind != .pointer }

    func isExpired(now: Date) -> Bool { until.map { now >= $0 } ?? false }

    func remainingSeconds(now: Date) -> Int {
        guard let until else { return 0 }
        return max(0, Int(until.timeIntervalSince(now).rounded(.up)))
    }
}
