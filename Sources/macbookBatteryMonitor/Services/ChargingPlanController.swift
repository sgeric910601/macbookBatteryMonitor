import Foundation
import Combine

/// 排程存在哪裡（測試時換成記憶體）
protocol ChargingPlanStorage: AnyObject {
    func load() -> ChargingPlan?
    func save(_ plan: ChargingPlan?)
}

final class DefaultsChargingPlanStorage: ChargingPlanStorage {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "chargingPlan") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> ChargingPlan? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ChargingPlan.self, from: $0) }
    }

    func save(_ plan: ChargingPlan?) {
        if let plan, let data = try? JSONEncoder().encode(plan) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

/// 什麼時候重新判斷
enum ChargingPlanEvent: String {
    case refresh
    case willSleep
    case didWake
}

enum ChargingPlanNotification: Equatable {
    case ready
    case late
}

/// 智慧充電的狀態機：決定現在要把充電上限設成多少、何時還原、何時通知。
/// 實際寫入由呼叫的地方做（BatteryStore），寫完回報 writeFinished；同一時間只有一個寫入
final class ChargingPlanController: ObservableObject {
    @Published private(set) var plan: ChargingPlan?
    @Published private(set) var decision: ChargingPlanDecision?
    /// 上一次寫入失敗的說明（下一次成功就清掉）
    @Published private(set) var writeError: String?

    private let storage: ChargingPlanStorage
    private let calendar: Calendar
    private let log: (String) -> Void
    /// 正在寫入的上限
    private var pendingWrite: Int?
    /// 寫入失敗後，這個時間之前不再重試
    private var retryAt: Date?

    /// 一次性排程完成時間過後多久還沒拔電就自動結束、還原上限
    static let expiry: TimeInterval = 2 * 3600
    static let retryDelay: TimeInterval = 60
    /// 提高上限後等 macOS 開始充電的時間
    static let startGrace: TimeInterval = 120

    init(storage: ChargingPlanStorage = DefaultsChargingPlanStorage(), calendar: Calendar = .current,
         log: @escaping (String) -> Void = { ChargingPlanLog.shared.write($0) }) {
        self.storage = storage
        self.calendar = calendar
        self.log = log
        plan = storage.load()
    }

    var isActive: Bool { plan != nil }

    /// 建立（或取代）排程。取代時沿用第一次記下的原本上限，避免把排程設的保養上限當成原本的值
    @discardableResult
    func start(_ schedule: ChargingSchedule, target: Int, hold: Int, currentLimit: Int,
               strategy: ChargingSleepStrategy, now: Date = Date()) -> Bool {
        guard let deadline = schedule.nextDeadline(after: now, calendar: calendar) else { return false }
        let restore = plan?.restoreLimit ?? currentLimit
        let value = ChargingPlan(schedule: schedule, deadline: deadline, targetPercent: target, holdPercent: hold,
                                 restoreLimit: restore, sleepStrategy: strategy, createdAt: now)
        replace(with: value)
        log("建立排程：\(describe(value))，原本上限 \(restore)%")
        return true
    }

    /// 依目前狀態判斷；回傳需要寫入的充電上限（nil 表示不用寫）
    func evaluate(_ input: ChargingPlanInput, event: ChargingPlanEvent = .refresh, preciseWakeReady: Bool = false) -> Int? {
        guard var active = plan else {
            decision = nil
            return nil
        }
        guard input.limitSupported else {
            decision = ChargingPlanEngine.evaluate(active, input: input)
            return nil
        }
        if active.restoring {
            return restore(active, input)
        }
        // 使用者在系統設定改了充電上限：以使用者為準，結束排程、不還原
        if let applied = active.appliedLimit, pendingWrite == nil, input.currentLimit != applied {
            clear("系統的充電上限被改成 \(input.currentLimit)%（排程設的是 \(applied)%），結束排程（不還原）")
            return nil
        }
        if case .once = active.schedule {
            if input.now > active.deadline.addingTimeInterval(Self.expiry) {
                log("完成時間已過 2 小時，結束排程")
                return beginRestore(active, input)
            }
            if !input.connected, active.completedAt != nil || input.percent >= active.targetPercent {
                log("已達目標並拔掉電源，結束排程")
                return beginRestore(active, input)
            }
        }
        if case .weekly = active.schedule {
            let finished = input.now >= active.deadline && input.percent >= active.targetPercent
            let expired = input.now > active.deadline.addingTimeInterval(Self.expiry)
            // 完成或過期就換到下一次；還沒到的完成時間也重新對一次（換時區、日光節約時間）
            if finished || expired || active.deadline > input.now,
               let next = active.schedule.nextDeadline(after: input.now, calendar: calendar),
               abs(next.timeIntervalSince(active.deadline)) >= 60 {
                active.deadline = next
                active.completedAt = nil
                plan = active
                storage.save(active)
                log("每週排程換到下一次：\(format(next))")
            }
        }

        var result = ChargingPlanEngine.evaluate(active, input: input)
        // 剛提高上限、macOS 還沒開始充：仍是「準備充電」，不是系統暫停
        if result.phase == .systemPaused, let raisedAt = active.raisedAt, input.now.timeIntervalSince(raisedAt) < Self.startGrace {
            result.phase = .starting
        }
        if result.phase != decision?.phase {
            log("狀態：\(result.phase.title)（電量 \(input.percent)%，上限 \(input.currentLimit)%，"
                + "\(input.connected ? "接著電源" : "沒接電源")，需要約 \(result.requiredMinutes) 分鐘，"
                + "預計 \(format(result.startAt)) 開始，事件 \(event.rawValue)）")
        }
        if result.phase == .ready, active.completedAt == nil {
            active.completedAt = input.now
        }
        if [.starting, .charging, .systemPaused, .late].contains(result.phase), active.startedFor != active.deadline {
            active.startedFor = active.deadline
        }
        if active != plan {
            plan = active
            storage.save(active)
        }
        decision = result

        var desired = result.desiredLimit
        // 睡著就沒辦法準時提高上限：除非已經排好喚醒，否則睡眠前直接提高到目標，讓 macOS 在睡眠中充
        if event == .willSleep, result.phase == .waiting,
           active.sleepStrategy == .readinessFirst || !preciseWakeReady {
            desired = active.targetPercent
            log("即將睡眠，先把上限提高到 \(active.targetPercent)%")
        }
        guard let desired else { return nil }
        return request(desired, input)
    }

    /// 寫入結束（成功是指系統讀回的上限等於目標）
    func writeFinished(target: Int, success: Bool, readBack: Int?, now: Date = Date()) {
        guard pendingWrite == target else { return }
        pendingWrite = nil
        log("寫入上限 \(target)%：\(success ? "成功" : "失敗")，系統讀回 \(readBack.map { "\($0)%" } ?? "無")")
        if success {
            retryAt = nil
            writeError = nil
            if var active = plan {
                if active.restoring, target == active.restoreLimit {
                    clear("已還原原本的上限 \(target)%，排程結束")
                } else if !active.restoring {
                    active.appliedLimit = target
                    if target == active.targetPercent, target > active.holdPercent {
                        active.raisedFor = active.deadline
                        active.raisedAt = now
                    }
                    plan = active
                    storage.save(active)
                }
            }
        } else {
            retryAt = now.addingTimeInterval(Self.retryDelay)
            writeError = "macOS 沒有套用智慧充電需要的充電上限，1 分鐘後重試"
        }
    }

    /// 這一輪該發的通知（每一輪的完成時間只發一次，重新開 App 也不重複）
    func takeNotification() -> ChargingPlanNotification? {
        guard var active = plan, let decision else { return nil }
        switch decision.phase {
        case .ready where active.readyNotifiedFor != active.deadline:
            active.readyNotifiedFor = active.deadline
            plan = active
            storage.save(active)
            // 這一輪沒有提高過上限（建立時就已經達到目標、或每週排程剛換到下一輪）不必通知
            return active.raisedFor == active.deadline ? .ready : nil
        case .late where active.lateNotifiedFor != active.deadline:
            active.lateNotifiedFor = active.deadline
            plan = active
            storage.save(active)
            return .late
        default:
            return nil
        }
    }

    /// 使用者取消：還原原本的上限
    func cancel(_ input: ChargingPlanInput) -> Int? {
        guard let active = plan else { return nil }
        log("使用者取消排程")
        return beginRestore(active, input)
    }

    /// 改變睡眠策略（設定頁或精準喚醒無法使用時）
    func setSleepStrategy(_ strategy: ChargingSleepStrategy) {
        guard var active = plan, active.sleepStrategy != strategy else { return }
        active.sleepStrategy = strategy
        plan = active
        storage.save(active)
        log("睡眠策略改為 \(strategy.title)")
    }

    /// 使用者在排程進行中自己調整了充電上限：以使用者為準，結束排程、不還原
    func userChangedLimit(to value: Int) {
        guard plan != nil else { return }
        clear("使用者把充電上限改成 \(value)%，結束排程（不還原）")
    }

    /// 截圖用：只放在記憶體，不覆寫使用者的排程
    func loadPreview(_ value: ChargingPlan, decision: ChargingPlanDecision?) {
        plan = value
        self.decision = decision
    }

    private func request(_ target: Int, _ input: ChargingPlanInput) -> Int? {
        guard target != input.currentLimit, pendingWrite == nil else { return nil }
        if let retryAt, input.now < retryAt { return nil }
        pendingWrite = target
        log("要求把上限從 \(input.currentLimit)% 改成 \(target)%")
        return target
    }

    private func beginRestore(_ value: ChargingPlan, _ input: ChargingPlanInput) -> Int? {
        var active = value
        active.restoring = true
        plan = active
        decision = nil
        storage.save(active)
        return restore(active, input)
    }

    private func restore(_ active: ChargingPlan, _ input: ChargingPlanInput) -> Int? {
        if active.restoreLimit == input.currentLimit, pendingWrite == nil {
            clear("上限已是原本的 \(active.restoreLimit)%，排程結束")
            return nil
        }
        return request(active.restoreLimit, input)
    }

    private func replace(with value: ChargingPlan) {
        plan = value
        decision = nil
        pendingWrite = nil
        retryAt = nil
        writeError = nil
        storage.save(value)
    }

    private func clear(_ reason: String) {
        log(reason)
        plan = nil
        decision = nil
        pendingWrite = nil
        retryAt = nil
        writeError = nil
        storage.save(nil)
    }

    private func describe(_ plan: ChargingPlan) -> String {
        let kind: String
        switch plan.schedule {
        case .once: kind = "一次"
        case .weekly(let days, let minute):
            kind = "每週 \(days.sorted().map(String.init).joined(separator: ",")) \(minute / 60):\(String(format: "%02d", minute % 60))"
        }
        return "\(kind)，\(format(plan.deadline)) 前充到 \(plan.targetPercent)%，保養上限 \(plan.holdPercent)%，睡眠策略 \(plan.sleepStrategy.title)"
    }

    private func format(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().hour().minute())
    }
}

/// 智慧充電的事件紀錄（只存在這台 Mac）：每次判斷的狀態變化、寫入上限與系統讀回的結果、喚醒排程，
/// 用來確認排程真的照預期運作。超過 256 KB 時只留後半
final class ChargingPlanLog {
    static let shared = ChargingPlanLog()
    private let queue = DispatchQueue(label: "com.kuan.batterymonitor.charging-log")
    let url: URL
    private static let maxSize = 256 * 1024

    init(url: URL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/macbookBatteryMonitor/charging-plan.log")) {
        self.url = url
    }

    /// 開發用指令與截圖不寫紀錄
    private static let enabled = Bundle.main.bundleIdentifier == "com.kuan.batterymonitor"
        && !CommandLine.arguments.contains { $0.hasPrefix("--snapshot") || $0.hasPrefix("--screenshots") }

    func write(_ message: String) {
        guard Self.enabled else { return }
        let line = "\(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeZone(separator: .omitted))) \(message)\n"
        queue.async { [url] in
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > Self.maxSize,
               let data = try? Data(contentsOf: url) {
                try? data.suffix(Self.maxSize / 2).write(to: url, options: .atomic)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url, options: .atomic)
            }
        }
    }

    /// 最後幾行（`--charging-plan-status` 用）
    func tail(_ count: Int) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Array(text.split(separator: "\n").suffix(count).map(String.init))
    }
}
