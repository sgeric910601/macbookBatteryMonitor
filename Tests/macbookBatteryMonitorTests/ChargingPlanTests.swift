import Foundation

/// 測試用：排程只存在記憶體
final class MemoryChargingPlanStorage: ChargingPlanStorage {
    var saved: ChargingPlan?
    func load() -> ChargingPlan? { saved }
    func save(_ plan: ChargingPlan?) { saved = plan }
}

final class ChargingPlanTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func input(_ now: Date, percent: Int, connected: Bool = true, limit: Int = 80, estimate: Int? = nil,
                       charging: Bool = false, paused: Bool = false, supported: Bool = true) -> ChargingPlanInput {
        ChargingPlanInput(now: now, percent: percent, connected: connected, limitSupported: supported, currentLimit: limit,
                          estimatedMinutes: estimate, isCharging: charging, systemPaused: paused)
    }

    func testScheduleDeadlines() {
        // 2026-10-13 是星期二
        let now = date("2026-10-13 21:00")
        XCTAssertNil(ChargingSchedule.once(now.addingTimeInterval(-60)).nextDeadline(after: now, calendar: calendar))
        XCTAssertEqual(ChargingSchedule.once(date("2026-10-14 08:00")).nextDeadline(after: now, calendar: calendar), date("2026-10-14 08:00"))
        // 上班日 8:00：星期二晚上的下一次是星期三早上
        let weekdays = ChargingSchedule.weekly(weekdays: [2, 3, 4, 5, 6], minuteOfDay: 8 * 60)
        XCTAssertEqual(weekdays.nextDeadline(after: now, calendar: calendar), date("2026-10-14 08:00"))
        // 只選星期一：跳到下週一
        XCTAssertEqual(ChargingSchedule.weekly(weekdays: [2], minuteOfDay: 7 * 60 + 30).nextDeadline(after: now, calendar: calendar),
                       date("2026-10-19 07:30"))
        XCTAssertNil(ChargingSchedule.weekly(weekdays: [], minuteOfDay: 480).nextDeadline(after: now, calendar: calendar))
        XCTAssertNil(ChargingSchedule.weekly(weekdays: [9], minuteOfDay: 480).nextDeadline(after: now, calendar: calendar))
        XCTAssertNil(ChargingSchedule.weekly(weekdays: [2], minuteOfDay: 24 * 60).nextDeadline(after: now, calendar: calendar))
    }

    func testRequiredMinutesIncludesSlowTopUp() {
        let now = date("2026-10-13 21:00")
        let plan = ChargingPlan(schedule: .once(date("2026-10-14 08:00")), deadline: date("2026-10-14 08:00"), targetPercent: 100,
                                holdPercent: 80, restoreLimit: 80, sleepStrategy: .readinessFirst, createdAt: now)
        // 沒有預估：每小時 20%，70→100 線性 90 分鐘，80% 以上的 2/3 乘 1.8 → 138 分鐘
        XCTAssertEqual(ChargingPlanEngine.requiredMinutes(plan, input(now, percent: 70)), 138)
        // 全部在 80% 以下不加
        var low = plan
        low.targetPercent = 80
        XCTAssertEqual(ChargingPlanEngine.requiredMinutes(low, input(now, percent: 60)), 60)
        // 有預估用預估：80→100 的 30 分鐘全部在 80% 以上 → 54 分鐘
        XCTAssertEqual(ChargingPlanEngine.requiredMinutes(plan, input(now, percent: 80, estimate: 30)), 54)
        XCTAssertEqual(ChargingPlanEngine.requiredMinutes(plan, input(now, percent: 100)), 0)
        // 保養上限不能高於目標，數值限制在 50–100
        let odd = ChargingPlan(schedule: .once(now), deadline: now, targetPercent: 120, holdPercent: 90, restoreLimit: 10,
                               sleepStrategy: .readinessFirst, createdAt: now)
        XCTAssertEqual(odd.targetPercent, 100)
        XCTAssertEqual(odd.restoreLimit, 50)
        let capped = ChargingPlan(schedule: .once(now), deadline: now, targetPercent: 85, holdPercent: 95, restoreLimit: 80,
                                  sleepStrategy: .readinessFirst, createdAt: now)
        XCTAssertEqual(capped.holdPercent, 85)
    }

    func testEnginePhases() {
        let deadline = date("2026-10-14 08:00")
        let plan = ChargingPlan(schedule: .once(deadline), deadline: deadline, targetPercent: 100, holdPercent: 80,
                                restoreLimit: 80, sleepStrategy: .preciseWake, createdAt: date("2026-10-13 21:00"))
        // 80→100 沒有預估：線性 60 分鐘，全部在 80% 以上 → 108 分鐘，加 15 分鐘緩衝 → 5:57 開始
        var decision = ChargingPlanEngine.evaluate(plan, input: input(date("2026-10-13 23:00"), percent: 80))
        XCTAssertEqual(decision.phase, .waiting)
        XCTAssertEqual(decision.desiredLimit, 80)
        XCTAssertEqual(decision.requiredMinutes, 108)
        XCTAssertEqual(decision.startAt, date("2026-10-14 05:57"))
        XCTAssertEqual(decision.wakeAt, date("2026-10-14 05:56"))
        // 到了開始時間：上限提高到目標，macOS 還沒開始充是「準備充電」
        decision = ChargingPlanEngine.evaluate(plan, input: input(date("2026-10-14 06:00"), percent: 80, limit: 80))
        XCTAssertEqual(decision.phase, .starting)
        XCTAssertEqual(decision.desiredLimit, 100)
        XCTAssertNil(decision.wakeAt)
        // 充到 84%、還要 72 分鐘：重新算的開始時間（6:33）比現在晚，但這一輪已經開始，不回到等待
        let charging = input(date("2026-10-14 06:30"), percent: 84, limit: 100, estimate: 40, charging: true)
        XCTAssertEqual(ChargingPlanEngine.evaluate(plan, input: charging).phase, .waiting)
        var started = plan
        started.startedFor = deadline
        decision = ChargingPlanEngine.evaluate(started, input: charging)
        XCTAssertEqual(decision.phase, .charging)
        XCTAssertEqual(decision.desiredLimit, 100)
        // 上限已經是目標卻沒在充：系統暫停
        decision = ChargingPlanEngine.evaluate(started, input: input(date("2026-10-14 06:30"), percent: 84, limit: 100, estimate: 40, paused: true))
        XCTAssertEqual(decision.phase, .systemPaused)
        // 趕不上：剩 30 分鐘還要 72 分鐘
        decision = ChargingPlanEngine.evaluate(plan, input: input(date("2026-10-14 07:30"), percent: 90, limit: 100, estimate: 40, charging: true))
        XCTAssertEqual(decision.phase, .late)
        XCTAssertEqual(decision.desiredLimit, 100)
        decision = ChargingPlanEngine.evaluate(plan, input: input(date("2026-10-14 07:50"), percent: 100, limit: 100))
        XCTAssertEqual(decision.phase, .ready)
        XCTAssertEqual(ChargingPlanEngine.evaluate(plan, input: input(date("2026-10-13 23:00"), percent: 80, connected: false)).phase, .unplugged)
        XCTAssertNil(ChargingPlanEngine.evaluate(plan, input: input(date("2026-10-13 23:00"), percent: 80, connected: false)).desiredLimit)
        XCTAssertEqual(ChargingPlanEngine.evaluate(plan, input: input(date("2026-10-13 23:00"), percent: 80, supported: false)).phase, .unsupported)
    }

    func testFullCycleWritesHoldThenTargetThenRestores() {
        let storage = MemoryChargingPlanStorage()
        var lines: [String] = []
        let controller = ChargingPlanController(storage: storage, calendar: calendar, log: { lines.append($0) })
        let now = date("2026-10-13 21:00")
        // 原本上限 90%：排程 8:00 前充到 100%，等待時維持 80%
        XCTAssertTrue(controller.start(.once(date("2026-10-14 08:00")), target: 100, hold: 80, currentLimit: 90,
                                       strategy: .readinessFirst, now: now))
        XCTAssertEqual(storage.saved?.restoreLimit, 90)
        XCTAssertEqual(controller.evaluate(input(now, percent: 85, limit: 90)), 80)
        // 寫入中不重複要求
        XCTAssertNil(controller.evaluate(input(now, percent: 85, limit: 90)))
        controller.writeFinished(target: 80, success: true, readBack: 80, now: now)
        XCTAssertEqual(storage.saved?.appliedLimit, 80)
        XCTAssertNil(controller.evaluate(input(now.addingTimeInterval(60), percent: 85, limit: 80)))
        XCTAssertEqual(controller.decision?.phase, .waiting)
        // 開始時間到了：提高到 100%
        let start = date("2026-10-14 06:30")
        XCTAssertEqual(controller.evaluate(input(start, percent: 85, limit: 80)), 100)
        controller.writeFinished(target: 100, success: true, readBack: 100, now: start)
        XCTAssertEqual(storage.saved?.startedFor, date("2026-10-14 08:00"))
        XCTAssertNil(controller.evaluate(input(start.addingTimeInterval(60), percent: 86, limit: 100, estimate: 30, charging: true)))
        XCTAssertEqual(controller.decision?.phase, .charging)
        // 充好了：通知一次
        let done = date("2026-10-14 07:40")
        XCTAssertNil(controller.evaluate(input(done, percent: 100, limit: 100)))
        XCTAssertEqual(controller.takeNotification(), .ready)
        XCTAssertNil(controller.takeNotification())
        // 重開 App 也不會再通知
        let reloaded = ChargingPlanController(storage: storage, calendar: calendar, log: { _ in })
        _ = reloaded.evaluate(input(done.addingTimeInterval(60), percent: 100, limit: 100))
        XCTAssertNil(reloaded.takeNotification())
        // 拔掉電源：還原原本的 90%，寫入成功才結束排程
        XCTAssertEqual(controller.evaluate(input(date("2026-10-14 08:10"), percent: 100, connected: false, limit: 100)), 90)
        XCTAssertTrue(storage.saved?.restoring == true)
        controller.writeFinished(target: 90, success: true, readBack: 90)
        XCTAssertNil(controller.plan)
        XCTAssertNil(storage.saved)
        XCTAssertTrue(lines.contains { $0.contains("排程結束") })
    }

    func testFailedWritesRetryAfterAMinute() {
        let controller = ChargingPlanController(storage: MemoryChargingPlanStorage(), calendar: calendar, log: { _ in })
        let now = date("2026-10-13 21:00")
        controller.start(.once(date("2026-10-14 08:00")), target: 100, hold: 80, currentLimit: 100, strategy: .readinessFirst, now: now)
        XCTAssertEqual(controller.evaluate(input(now, percent: 70, limit: 100)), 80)
        controller.writeFinished(target: 80, success: false, readBack: 100, now: now)
        XCTAssertTrue(controller.writeError != nil)
        XCTAssertNil(controller.evaluate(input(now.addingTimeInterval(30), percent: 70, limit: 100)))
        XCTAssertEqual(controller.evaluate(input(now.addingTimeInterval(61), percent: 70, limit: 100)), 80)
        controller.writeFinished(target: 80, success: true, readBack: 80, now: now.addingTimeInterval(61))
        XCTAssertNil(controller.writeError)
        // 還原失敗也保留排程，稍後重試
        XCTAssertEqual(controller.cancel(input(now.addingTimeInterval(120), percent: 70, limit: 80)), 100)
        controller.writeFinished(target: 100, success: false, readBack: 80, now: now.addingTimeInterval(120))
        XCTAssertTrue(controller.plan?.restoring == true)
        XCTAssertNil(controller.evaluate(input(now.addingTimeInterval(150), percent: 70, limit: 80)))
        XCTAssertEqual(controller.evaluate(input(now.addingTimeInterval(181), percent: 70, limit: 80)), 100)
        controller.writeFinished(target: 100, success: true, readBack: 100, now: now.addingTimeInterval(181))
        XCTAssertNil(controller.plan)
    }

    func testUserChangesEndThePlanWithoutRestoring() {
        let storage = MemoryChargingPlanStorage()
        let controller = ChargingPlanController(storage: storage, calendar: calendar, log: { _ in })
        let now = date("2026-10-13 21:00")
        controller.start(.once(date("2026-10-14 08:00")), target: 100, hold: 80, currentLimit: 100, strategy: .readinessFirst, now: now)
        XCTAssertEqual(controller.evaluate(input(now, percent: 70, limit: 100)), 80)
        controller.writeFinished(target: 80, success: true, readBack: 80, now: now)
        // 在系統設定改成 95%：結束排程，不改回去
        XCTAssertNil(controller.evaluate(input(now.addingTimeInterval(60), percent: 70, limit: 95)))
        XCTAssertNil(controller.plan)
        XCTAssertNil(storage.saved)
        // 在面板拖動滑桿：同樣結束
        controller.start(.once(date("2026-10-14 08:00")), target: 100, hold: 80, currentLimit: 95, strategy: .readinessFirst, now: now)
        controller.userChangedLimit(to: 85)
        XCTAssertNil(controller.plan)
        // 取代排程時沿用第一次記下的原本上限
        controller.start(.once(date("2026-10-14 08:00")), target: 100, hold: 80, currentLimit: 95, strategy: .readinessFirst, now: now)
        controller.start(.once(date("2026-10-14 09:00")), target: 100, hold: 80, currentLimit: 80, strategy: .readinessFirst, now: now)
        XCTAssertEqual(controller.plan?.restoreLimit, 95)
    }

    func testSleepStrategies() {
        let now = date("2026-10-13 23:00")
        let controller = ChargingPlanController(storage: MemoryChargingPlanStorage(), calendar: calendar, log: { _ in })
        controller.start(.once(date("2026-10-14 08:00")), target: 100, hold: 80, currentLimit: 80, strategy: .readinessFirst, now: now)
        // 優先準時完成：睡眠前還在等待就先提高到目標
        XCTAssertNil(controller.evaluate(input(now, percent: 80, limit: 80)))
        XCTAssertEqual(controller.evaluate(input(now, percent: 80, limit: 80), event: .willSleep), 100)
        controller.writeFinished(target: 100, success: true, readBack: 100, now: now)
        // 醒來後還在等待：回到保養上限
        XCTAssertEqual(controller.evaluate(input(now.addingTimeInterval(3600), percent: 84, limit: 100), event: .didWake), 80)
        controller.writeFinished(target: 80, success: true, readBack: 80, now: now.addingTimeInterval(3600))
        // 精準喚醒：已經排好喚醒就維持保養上限；喚醒沒排好時退回優先準時完成
        controller.setSleepStrategy(.preciseWake)
        XCTAssertNil(controller.evaluate(input(now.addingTimeInterval(3700), percent: 84, limit: 80), event: .willSleep, preciseWakeReady: true))
        XCTAssertEqual(controller.evaluate(input(now.addingTimeInterval(3700), percent: 84, limit: 80), event: .willSleep, preciseWakeReady: false), 100)
    }

    func testWeeklyPlanMovesToNextDeadline() {
        let storage = MemoryChargingPlanStorage()
        let controller = ChargingPlanController(storage: storage, calendar: calendar, log: { _ in })
        let now = date("2026-10-13 21:00")
        controller.start(.weekly(weekdays: [2, 3, 4, 5, 6], minuteOfDay: 8 * 60), target: 100, hold: 80, currentLimit: 80,
                         strategy: .readinessFirst, now: now)
        XCTAssertEqual(controller.plan?.deadline, date("2026-10-14 08:00"))
        XCTAssertEqual(controller.evaluate(input(date("2026-10-14 06:30"), percent: 85, limit: 80)), 100)
        controller.writeFinished(target: 100, success: true, readBack: 100)
        _ = controller.evaluate(input(date("2026-10-14 07:50"), percent: 100, limit: 100))
        XCTAssertEqual(controller.takeNotification(), .ready)
        // 過了完成時間且已充好：換到星期四；新的一輪還沒提高過上限，不會馬上又通知
        _ = controller.evaluate(input(date("2026-10-14 08:05"), percent: 100, limit: 100))
        XCTAssertEqual(controller.plan?.deadline, date("2026-10-15 08:00"))
        XCTAssertNil(controller.takeNotification())
        // 每週排程拔電不會結束
        _ = controller.evaluate(input(date("2026-10-14 09:00"), percent: 97, connected: false, limit: 100))
        XCTAssertTrue(controller.plan != nil)
        XCTAssertTrue(controller.plan?.restoring == false)
    }

    func testOnceExpiresTwoHoursAfterDeadline() {
        let controller = ChargingPlanController(storage: MemoryChargingPlanStorage(), calendar: calendar, log: { _ in })
        let now = date("2026-10-13 21:00")
        controller.start(.once(date("2026-10-14 08:00")), target: 100, hold: 80, currentLimit: 90, strategy: .readinessFirst, now: now)
        // 95% 還要 27 分鐘，7:18 才開始；之前維持保養上限
        XCTAssertEqual(controller.evaluate(input(date("2026-10-14 07:00"), percent: 95, limit: 90)), 80)
        controller.writeFinished(target: 80, success: true, readBack: 80)
        XCTAssertEqual(controller.evaluate(input(date("2026-10-14 07:30"), percent: 95, limit: 80)), 100)
        controller.writeFinished(target: 100, success: true, readBack: 100)
        // 一直沒拔電：完成時間後 2 小時還原
        XCTAssertNil(controller.evaluate(input(date("2026-10-14 09:30"), percent: 100, limit: 100)))
        XCTAssertEqual(controller.evaluate(input(date("2026-10-14 10:01"), percent: 100, limit: 100)), 90)
    }

    func testLateNotificationAndQuietReadyAtCreation() {
        let controller = ChargingPlanController(storage: MemoryChargingPlanStorage(), calendar: calendar, log: { _ in })
        let now = date("2026-10-13 21:00")
        // 建立時就已經達到目標：不通知
        controller.start(.once(date("2026-10-13 23:00")), target: 80, hold: 80, currentLimit: 80, strategy: .readinessFirst, now: now)
        _ = controller.evaluate(input(now, percent: 85, limit: 80))
        XCTAssertEqual(controller.decision?.phase, .ready)
        XCTAssertNil(controller.takeNotification())
        // 一小時後要從 40% 充到 100%：可能延遲，只通知一次
        controller.start(.once(now.addingTimeInterval(3600)), target: 100, hold: 80, currentLimit: 80, strategy: .readinessFirst, now: now)
        XCTAssertEqual(controller.evaluate(input(now, percent: 40, limit: 80)), 100)
        XCTAssertEqual(controller.decision?.phase, .late)
        XCTAssertEqual(controller.takeNotification(), .late)
        XCTAssertNil(controller.takeNotification())
    }

    func testChargingRateFromHistory() {
        let start = date("2026-10-13 20:00")
        var samples: [HistorySample] = []
        // 每 10 分鐘 +5%（每小時 30%），中間一段斷了 2 小時不算，用電池的時段不算
        for i in 0..<6 {
            samples.append(HistorySample(t: start.addingTimeInterval(Double(i) * 600), pct: 50 + i * 5, watts: nil, plugged: true, charging: true))
        }
        samples.append(HistorySample(t: start.addingTimeInterval(3 * 3600), pct: 90, watts: nil, plugged: true, charging: true))
        samples.append(HistorySample(t: start.addingTimeInterval(3 * 3600 + 600), pct: 85, watts: nil, plugged: false, charging: false))
        let rate = ChargingRateEstimator.percentPerHour(samples: samples, now: start.addingTimeInterval(4 * 3600))
        XCTAssertEqual(rate.map { Int($0.rounded()) }, 30)
        XCTAssertNil(ChargingRateEstimator.percentPerHour(samples: Array(samples.prefix(1)), now: start))
        // 實際的歷史是每分鐘一筆、電量是整數：每 2 分鐘 +1%（每小時 30%），不能只算電量有上升的那幾分鐘（會變成每小時 60%）
        let minute = (0...60).map { i in
            HistorySample(t: start.addingTimeInterval(Double(i) * 60), pct: 50 + i / 2, watts: nil, plugged: true, charging: true)
        }
        XCTAssertEqual(ChargingRateEstimator.percentPerHour(samples: minute, now: start.addingTimeInterval(3600)).map { Int($0.rounded()) }, 30)
        // 太短的充電（不到 10 分鐘或不到 3%）不採用
        XCTAssertNil(ChargingRateEstimator.percentPerHour(samples: Array(minute.prefix(6)), now: start.addingTimeInterval(3600)))
    }

    func testDailyRecap() {
        let midnight = date("2026-10-13 00:00")
        func sample(_ minutes: Int, _ pct: Int, _ plugged: Bool) -> HistorySample {
            HistorySample(t: midnight.addingTimeInterval(Double(minutes) * 60), pct: pct, watts: nil, plugged: plugged, charging: plugged)
        }
        var samples = [sample(-10, 60, true)]
        // 0:00–8:00 接電 60→80（中間在 80 附近 ±1 跳動不重複算）
        samples += stride(from: 0, through: 480, by: 10).map { sample($0, min(80, 60 + $0 / 20), true) }
        samples += [sample(490, 79, true), sample(500, 80, true)]
        // 8:30 拔電，用到 12:00 剩 50%
        samples += stride(from: 510, through: 720, by: 10).map { sample($0, 80 - ($0 - 510) / 7, false) }
        // 12:10 接電 30 分鐘到 60%
        samples += [sample(730, 50, true), sample(760, 60, true)]
        // 13:00 再拔電用到 14:00
        samples += stride(from: 780, through: 840, by: 10).map { sample($0, 60 - ($0 - 780) / 10, false) }
        let recap = DailyBatteryRecap.make(samples: samples, day: midnight.addingTimeInterval(15 * 3600), calendar: calendar)
        XCTAssertEqual(recap.startPercent, 60)
        XCTAssertEqual(recap.endPercent, 54)
        XCTAssertEqual(recap.plugInCount, 1)
        XCTAssertEqual(recap.chargedPercent, 30)
        XCTAssertEqual(recap.usedPercent, 36)
        XCTAssertEqual(recap.netChange, -6)
        // 8:30–12:10 共 220 分鐘、13:00–14:00 共 60 分鐘
        XCTAssertEqual(recap.unpluggedMinutes, 280)
        XCTAssertEqual(recap.longestUnpluggedMinutes, 220)
        // 沒有紀錄、或桌上型 Mac
        XCTAssertNil(DailyBatteryRecap.make(samples: [], day: midnight, calendar: calendar).startPercent)
        XCTAssertNil(DailyBatteryRecap.make(samples: [HistorySample(t: midnight, pct: -1, watts: 30, plugged: true, charging: false)],
                                            day: midnight, calendar: calendar).startPercent)
    }

    func testWakePolicy() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(ChargingWakePolicy.isAllowed(now.timeIntervalSince1970 + 61, now: now))
        XCTAssertTrue(!ChargingWakePolicy.isAllowed(now.timeIntervalSince1970 + 30, now: now))
        XCTAssertTrue(!ChargingWakePolicy.isAllowed(now.timeIntervalSince1970 + 8 * 24 * 3600, now: now))
        XCTAssertTrue(!ChargingWakePolicy.isAllowed(.nan, now: now))
        XCTAssertTrue(!ChargingWakePolicy.isAllowed(.infinity, now: now))
        XCTAssertTrue(ChargingWakePolicy.shouldReplace(existing: nil, with: now))
        XCTAssertTrue(!ChargingWakePolicy.shouldReplace(existing: now, with: now.addingTimeInterval(120)))
        XCTAssertTrue(ChargingWakePolicy.shouldReplace(existing: now, with: now.addingTimeInterval(-600)))
        XCTAssertTrue(ChargingWakePolicy.keepsHelper(cpuSampling: false, chargingWake: true))
        XCTAssertTrue(!ChargingWakePolicy.keepsHelper(cpuSampling: false, chargingWake: false))
    }
}
