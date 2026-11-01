import Foundation

/// 鍵盤清潔模式：一段時間內擋下所有鍵盤事件，方便擦鍵盤。滑鼠與觸控板照常，才點得到「結束清潔」；
/// 時間到也會自動結束。Touch ID 指紋與電源鍵是硬體層級，不經過這裡。
/// 只做判斷，事件攔截與畫面在 KeyboardCleaningController
struct KeyboardCleaning {
    enum EventKind { case keyDown, keyUp, flagsChanged, systemKey, pointer }

    static let durations: [Int] = [30, 60, 120]
    static let defaultDuration = 60

    private(set) var until: Date?

    var isActive: Bool { until != nil }

    static func validDuration(_ seconds: Int) -> Int { durations.contains(seconds) ? seconds : defaultDuration }

    mutating func start(seconds: Int, now: Date) { until = now.addingTimeInterval(TimeInterval(seconds)) }

    mutating func stop() { until = nil }

    func blocks(_ kind: EventKind) -> Bool { isActive && kind != .pointer }

    func isExpired(now: Date) -> Bool { until.map { now >= $0 } ?? false }

    func remainingSeconds(now: Date) -> Int {
        guard let until else { return 0 }
        return max(0, Int(until.timeIntervalSince(now).rounded(.up)))
    }
}
