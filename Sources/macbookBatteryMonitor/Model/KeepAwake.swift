import Foundation

/// 防止休眠：選一段時間或直到關閉。時間到、或用電池而且電量到 lowBatteryStop 以下時停止，免得把電池耗光。
/// 只做判斷，實際的電源管理在 KeepAwakeController
struct KeepAwake {
    enum Duration: CaseIterable {
        case minutes30, hour1, hour2, indefinitely

        var seconds: TimeInterval? {
            switch self {
            case .minutes30: return 30 * 60
            case .hour1: return 3600
            case .hour2: return 7200
            case .indefinitely: return nil
            }
        }

        var title: String {
            switch self {
            case .minutes30: return "30 分鐘"
            case .hour1: return "1 小時"
            case .hour2: return "2 小時"
            case .indefinitely: return "直到關閉"
            }
        }
    }

    static let lowBatteryStop = 10

    private(set) var isActive = false
    /// 到期時間；nil 是直到關閉
    private(set) var until: Date?
    /// 目前選的時間，讓畫面標出是哪一個；沒在防止休眠時為 nil
    private(set) var duration: Duration?

    mutating func start(_ duration: Duration, now: Date) {
        isActive = true
        self.duration = duration
        until = duration.seconds.map { now.addingTimeInterval($0) }
    }

    mutating func stop() {
        isActive = false
        until = nil
        duration = nil
    }

    /// batteryPercent 為 nil：沒有電池（桌上型 Mac）
    func shouldStop(now: Date, batteryPercent: Int?, onBattery: Bool) -> Bool {
        guard isActive else { return false }
        if let until, now >= until { return true }
        if onBattery, let batteryPercent, batteryPercent <= Self.lowBatteryStop { return true }
        return false
    }

    /// 指定的 App 執行中時自動防止休眠：清單裡有任何一個在執行就防止；用電池而且電量到 lowBatteryStop 以下時不防止
    static func autoHolds(running: Set<String>, list: Set<String>, batteryPercent: Int?, onBattery: Bool) -> Bool {
        guard !list.isDisjoint(with: running) else { return false }
        if onBattery, let batteryPercent, batteryPercent <= lowBatteryStop { return false }
        return true
    }

    /// 剩下多久，無條件進位到分鐘；直到關閉時為 nil
    func remainingText(now: Date) -> String? {
        guard isActive, let until else { return nil }
        let minutes = Int((max(0, until.timeIntervalSince(now)) / 60).rounded(.up))
        if minutes < 60 { return "\(minutes) 分鐘" }
        return minutes % 60 == 0 ? "\(minutes / 60) 小時" : "\(minutes / 60) 小時 \(minutes % 60) 分"
    }
}
