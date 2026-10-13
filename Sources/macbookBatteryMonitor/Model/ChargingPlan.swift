import Foundation

/// 智慧充電：使用者指定「幾點前充到幾 %」，平常把 macOS 的充電上限維持在保養上限，
/// 算好需要的時間再把上限提高到目標，讓 macOS 自己充；結束後還原原本的上限。
/// 這個檔案只有排程與判斷邏輯，不讀寫系統（方便測試）

/// 睡眠時的策略
enum ChargingSleepStrategy: String, Codable, CaseIterable, Identifiable {
    /// 睡眠前若還在等待，就先把上限提高到目標，讓 macOS 在睡眠中充好（可能比較早充滿）
    case readinessFirst
    /// 排一個喚醒事件，在該開始充電時叫醒 Mac 調整上限（需要管理員授權一次）
    case preciseWake

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readinessFirst: return "優先準時完成"
        case .preciseWake: return "精準喚醒"
        }
    }
}

enum ChargingSchedule: Codable, Equatable {
    /// 一次性：指定完成時間
    case once(Date)
    /// 每週：weekday 依 Calendar（1 = 星期日 … 7 = 星期六），minuteOfDay 是當天的第幾分鐘
    case weekly(weekdays: Set<Int>, minuteOfDay: Int)

    /// 下一個完成時間（一次性的時間已過就是 nil）
    func nextDeadline(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .once(let deadline):
            return deadline > date ? deadline : nil
        case .weekly(let weekdays, let minuteOfDay):
            guard (0..<(24 * 60)).contains(minuteOfDay) else { return nil }
            return weekdays.filter { (1...7).contains($0) }.compactMap { weekday in
                var parts = DateComponents()
                parts.weekday = weekday
                parts.hour = minuteOfDay / 60
                parts.minute = minuteOfDay % 60
                parts.second = 0
                // 日光節約時間跳過的時刻改用下一個存在的時間
                return calendar.nextDate(after: date, matching: parts, matchingPolicy: .nextTimePreservingSmallerComponents,
                                         repeatedTimePolicy: .first, direction: .forward)
            }.min()
        }
    }

    var isWeekly: Bool {
        if case .weekly = self { return true }
        return false
    }
}

struct ChargingPlan: Codable, Equatable, Identifiable {
    var id = UUID()
    var schedule: ChargingSchedule
    /// 這一輪的完成時間（每週排程完成或過期後換到下一次）
    var deadline: Date
    /// 完成時要充到的電量
    var targetPercent: Int
    /// 等待期間維持的充電上限（保養上限）
    var holdPercent: Int
    /// 建立排程前使用者原本的充電上限，結束時還原
    var restoreLimit: Int
    var sleepStrategy: ChargingSleepStrategy
    var createdAt: Date
    /// 這一輪第一次達到目標的時間
    var completedAt: Date?
    /// 已經通知過「已準備好」／「可能延遲」的那一輪完成時間（重新開 App 不重複通知）
    var readyNotifiedFor: Date?
    var lateNotifiedFor: Date?
    /// 正在還原原本的上限（還原寫入失敗時保留，稍後重試）
    var restoring = false
    /// 排程最後一次成功寫入的上限：系統的上限變成別的值，表示使用者在系統設定改過
    var appliedLimit: Int?
    /// 這一輪（以完成時間區分）已經開始充電：之後估算時間變短也不回到等待，免得充到一半又把上限降回去
    var startedFor: Date?
    /// 這一輪曾把上限提高到目標（包含睡眠前提高）：有提高過才發「已充好」通知
    var raisedFor: Date?

    init(schedule: ChargingSchedule, deadline: Date, targetPercent: Int, holdPercent: Int, restoreLimit: Int,
         sleepStrategy: ChargingSleepStrategy, createdAt: Date) {
        self.schedule = schedule
        self.deadline = deadline
        let target = Self.clamp(targetPercent)
        self.targetPercent = target
        self.holdPercent = min(Self.clamp(holdPercent), target)
        self.restoreLimit = Self.clamp(restoreLimit)
        self.sleepStrategy = sleepStrategy
        self.createdAt = createdAt
    }

    /// macOS 的充電上限只能設 50–100%
    static func clamp(_ percent: Int) -> Int { min(max(percent, 50), 100) }
}

/// 判斷時需要的即時狀態
struct ChargingPlanInput: Equatable {
    var now: Date
    var percent: Int
    var connected: Bool
    var limitSupported: Bool
    var currentLimit: Int
    /// 充到目標還要幾分鐘（系統預估，沒有就用最近七天的充電速度）
    var estimatedMinutes: Int?
    var isCharging: Bool
    /// 接著電源但 macOS 沒在充（到達上限、最佳化充電暫停等）
    var systemPaused: Bool
}

enum ChargingPlanPhase: String, Codable, Equatable {
    /// 這台 Mac 不支援調整充電上限
    case unsupported
    /// 沒接電源
    case unplugged
    /// 維持保養上限，等時間到再開始充
    case waiting
    /// 已把上限提高到目標，等 macOS 開始充
    case starting
    case charging
    /// 該充了但 macOS 暫停充電
    case systemPaused
    /// 已達目標
    case ready
    /// 照目前速度趕不上完成時間（或已經過了）
    case late

    var title: String {
        switch self {
        case .unsupported: return "不支援"
        case .unplugged: return "等待電源"
        case .waiting: return "等待開始"
        case .starting: return "準備充電"
        case .charging: return "充電中"
        case .systemPaused: return "系統暫停"
        case .ready: return "已準備好"
        case .late: return "可能延遲"
        }
    }
}

struct ChargingPlanDecision: Equatable {
    var phase: ChargingPlanPhase
    var targetPercent: Int
    var deadline: Date
    /// 預計開始充電的時間
    var startAt: Date
    /// 精準喚醒要排的時間（開始充電前一分鐘）
    var wakeAt: Date?
    /// 現在應該設定的充電上限；nil 表示不動
    var desiredLimit: Int?
    var requiredMinutes: Int
}

enum ChargingPlanEngine {
    /// 預留的緩衝時間：估算不準、或 macOS 開始充電前的延遲
    static let bufferMinutes = 15
    static let maximumMinutes = 24 * 60

    static func evaluate(_ plan: ChargingPlan, input: ChargingPlanInput) -> ChargingPlanDecision {
        let needed = requiredMinutes(plan, input)
        let start = plan.deadline.addingTimeInterval(-Double(needed + bufferMinutes) * 60)
        let wake = plan.sleepStrategy == .preciseWake && start > input.now ? start.addingTimeInterval(-60) : nil

        func decide(_ phase: ChargingPlanPhase, limit: Int?) -> ChargingPlanDecision {
            ChargingPlanDecision(phase: phase, targetPercent: plan.targetPercent, deadline: plan.deadline, startAt: start,
                                 wakeAt: wake, desiredLimit: limit, requiredMinutes: needed)
        }

        guard input.limitSupported else { return decide(.unsupported, limit: nil) }
        guard input.connected else { return decide(.unplugged, limit: nil) }
        if input.percent >= plan.targetPercent { return decide(.ready, limit: plan.targetPercent) }
        if input.now >= plan.deadline { return decide(.late, limit: plan.targetPercent) }
        if input.now < start, plan.startedFor != plan.deadline { return decide(.waiting, limit: plan.holdPercent) }
        if input.now.addingTimeInterval(Double(needed) * 60) > plan.deadline { return decide(.late, limit: plan.targetPercent) }
        if input.isCharging { return decide(.charging, limit: plan.targetPercent) }
        // 剛提高上限時 macOS 可能還沒開始充：上限還沒是目標就是「準備充電」，已經是目標卻沒在充才算系統暫停
        if input.systemPaused && input.currentLimit == plan.targetPercent { return decide(.systemPaused, limit: plan.targetPercent) }
        return decide(.starting, limit: plan.targetPercent)
    }

    /// 鋰電池充到 80% 以上會變慢（定電壓階段）：線性估算的這一段時間乘上這個倍數
    static let taperFactor = 1.8

    /// 充到目標需要的分鐘數：有預估用預估，沒有就以每小時 20% 估算；80% 以上的部分另外加上變慢的時間
    static func requiredMinutes(_ plan: ChargingPlan, _ input: ChargingPlanInput) -> Int {
        let percent = max(0, input.percent)
        guard percent < plan.targetPercent else { return 0 }
        let linear: Double
        if let estimate = input.estimatedMinutes, estimate > 0 {
            linear = Double(estimate)
        } else {
            linear = Double(plan.targetPercent - percent) / ChargingRateEstimator.fallbackPercentPerHour * 60
        }
        let slowShare = Double(max(0, plan.targetPercent - max(percent, 80))) / Double(plan.targetPercent - percent)
        return min(Int((linear * (1 + (taperFactor - 1) * slowShare)).rounded(.up)), maximumMinutes)
    }
}

/// 最近七天實際的充電速度（每小時幾 %），系統沒有預估時用來推算需要的時間。
/// 電量歷史每分鐘一筆、電量是整數，大部分相鄰兩筆的電量相同，所以不能只看電量有上升的那幾筆
/// （那樣每一段都會算成每分鐘 1%）：以每一段連續充電「總共充了幾 % ÷ 總共花了多久」計算，再取各段的中位數
enum ChargingRateEstimator {
    static let fallbackPercentPerHour = 20.0
    private static let window: TimeInterval = 7 * 24 * 3600
    /// 一段充電至少要這麼久、充這麼多才採用，太短的段落誤差大
    private static let minimumSeconds: TimeInterval = 10 * 60
    private static let minimumPercent = 3

    static func percentPerHour(samples: [HistorySample], now: Date = Date()) -> Double? {
        let ordered = samples.filter { $0.t >= now.addingTimeInterval(-window) && $0.t <= now && $0.pct >= 0 }
            .sorted { $0.t < $1.t }
        var rates: [Double] = []
        var gained = 0
        var seconds: TimeInterval = 0
        func finishSession() {
            if seconds >= minimumSeconds, gained >= minimumPercent {
                rates.append(Double(gained) / seconds * 3600)
            }
            gained = 0
            seconds = 0
        }
        for (left, right) in zip(ordered, ordered.dropFirst()) {
            let dt = right.t.timeIntervalSince(left.t)
            // 中間斷了很久（睡眠、App 沒開）或沒在充電，這一段結束
            guard dt > 0, dt <= 30 * 60, left.plugged, right.plugged, left.charging else {
                finishSession()
                continue
            }
            gained += max(0, right.pct - left.pct)
            seconds += dt
        }
        finishSession()
        guard !rates.isEmpty else { return nil }
        rates.sort()
        let middle = rates.count / 2
        let rate = rates.count.isMultiple(of: 2) ? (rates[middle - 1] + rates[middle]) / 2 : rates[middle]
        return rate.isFinite && (1...100).contains(rate) ? rate : nil
    }
}
