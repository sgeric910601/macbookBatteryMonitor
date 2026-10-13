import Foundation
import Combine

@MainActor
final class BatteryStore: ObservableObject {
    @Published private(set) var snapshot: BatterySnapshot?
    /// 桌上型 Mac（沒有電池）的整機耗電；有電池的 Mac 一直是 nil
    @Published private(set) var desktop: DesktopPower?
    @Published private(set) var estimates: Estimates?
    @Published private(set) var systemHealth: SystemHealth?
    @Published private(set) var topProcesses: [EnergyProcess] = []
    @Published private(set) var processesLoaded = false
    /// 這次拔掉電源的時間，用來算「已使用電池多久」
    @Published private(set) var unpluggedAt: Date?
    let history = HistoryStore()
    let adminCPU = AdminCPUSampler()
    /// 周邊設備電量（鍵盤、滑鼠、耳機等）
    let peripherals = PeripheralStore()
    /// 一鍵更新
    let updater = Updater()
    /// 主面板的充電上限滑桿（調整 macOS 系統設定裡的充電上限）
    let chargeLimit = SystemChargeLimit()
    /// 智慧充電：指定時間前充到目標，平常維持保養上限
    let chargingPlan = ChargingPlanController()
    /// 智慧充電的精準喚醒（選用，需要管理員授權）
    let chargingWake = ChargingWakeScheduler()
    private let sleepGate = SleepGate()
    /// 智慧充電只在正式執行的 App 裡運作（AppDelegate 呼叫 startChargingPlan 之後）；
    /// --snapshot、--dump 等開發指令也會建立 BatteryStore，絕不能因此寫入充電上限或改動排程
    private var chargingPlanRunning = false
    @Published private(set) var componentPower: ComponentPowerSample?
    @Published private(set) var breakdown = PowerBreakdown(systemWatts: nil, status: .sampling)
    private let hardwareWorker = HardwarePowerWorker()
    private var samplingGate = SamplingGate()
    /// 截圖用的示範數據：不啟動真實的硬體取樣，免得蓋掉示範值
    private var previewing = false

    /// Intel 的 powermetrics 沒有 CPU Power 這一行，而且 SMC 已經直接提供 CPU 功耗，不使用管理員取樣
    private static var adminCPUEnabled: Bool { AppSettings.shared.adminCPUSampling && !ChipInfo.isIntel }

    func setHardwareSampling(active: Bool) {
        guard !previewing else { return }
        adminCPU.update(active: active, enabled: Self.adminCPUEnabled)
        let changed = samplingGate.active != active
        samplingGate.setActive(active)
        if !active {
            if changed {
                componentPower = nil
                breakdown = PowerBreakdown(systemWatts: estimates?.systemWatts ?? desktop?.systemWatts, status: .sampling)
                let generation = samplingGate.generation
                Task { await hardwareWorker.stop(generation: generation) }
            }
            return
        }
        guard let ticket = samplingGate.begin() else { return }
        Task {
            let result = await hardwareWorker.sample(generation: ticket)
            guard samplingGate.finish(ticket), var result else { return }
            if Self.adminCPUEnabled { result.cpuWatts = adminCPU.watts }
            componentPower = result
            breakdown = PowerBreakdown.make(systemWatts: result.systemWatts,
                components: result, now: ProcessInfo.processInfo.systemUptime)
        }
    }


    /// 平滑電流用的時間常數（秒），約等於「近 3 分鐘平均」
    private let tau: Double = 180
    private var avgDischarge: Double?
    private var avgCharge: Double?
    private var lastDate: Date?
    private var lastState: PowerState?
    private var chargingPresentation = ChargingPresentation()
    private var flowPresentation = PowerFlowPresentation()
    /// 這次接上電源的時間（判斷充電上限是否已被關掉用）
    private var pluggedSince: Date?
    private var processStream: ProcessEnergyStream?
    /// 面板開著才允許跑 top，避免關掉後還在背景取樣
    var panelVisible = false

    /// 巢狀物件的變化轉給這個物件（macOS 12 沒有 Observation，主面板只觀察 BatteryStore）
    private var forwarding: [AnyCancellable] = []

    init() {
        unpluggedAt = history.lastUnplugged()
        let nested: [AnyPublisher<Void, Never>] = [
            history.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            adminCPU.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            peripherals.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            updater.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            chargeLimit.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            chargingPlan.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            chargingWake.objectWillChange.map { _ in }.eraseToAnyPublisher(),
        ]
        forwarding = nested.map { publisher in
            publisher.sink { [weak self] in self?.objectWillChange.send() }
        }
    }

    func refresh() {
        // 溫度要另外問 SMC，只有面板開著時才需要
        guard var s = BatteryReader.read(includeTemperature: panelVisible) else {
            snapshot = nil
            estimates = nil
            chargingPresentation = ChargingPresentation()
            flowPresentation = PowerFlowPresentation()
            if !BatteryReader.hasBattery { refreshDesktop() }
            return
        }
        if s.externalConnected {
            if pluggedSince == nil { pluggedSince = s.date }
        } else {
            pluggedSince = nil
        }
        s.chargeLimit = ChargeLimitReader.resolve(externalConnected: s.externalConnected, pluggedSince: pluggedSince)
        let state = chargingPresentation.state(s, uptime: ProcessInfo.processInfo.systemUptime)
        let dt = lastDate.map { s.date.timeIntervalSince($0) } ?? 0

        if state != lastState {
            if lastState != nil {
                avgDischarge = nil
                avgCharge = nil
            }
            if state == .discharging {
                if lastState != nil { unpluggedAt = s.date }
            } else {
                unpluggedAt = nil
            }
        }
        let current = Double(abs(s.effectiveAmperage_mA))
        if s.effectiveAmperage_mA < 0 {
            avgDischarge = ema(avgDischarge, current, dt)
        } else if s.effectiveAmperage_mA > 0 {
            avgCharge = ema(avgCharge, current, dt)
        }
        lastDate = s.date
        lastState = state

        snapshot = s
        var computed = Estimator.estimates(s, avgDischarge_mA: avgDischarge, avgCharge_mA: avgCharge, displayState: state)
        // 接著電源但沒在充電（滿電、到達上限、暫停）時，電池功率的小幅波動不改變流向圖，與上方的狀態文字一致
        let holding = [.full, .limitReached, .pluggedIdle].contains(state) && !computed.drainingOnAC && !s.drainingAboveLimit
        computed.displayFlow = flowPresentation.kind(connected: s.externalConnected, watts: computed.batteryWatts,
            holding: holding, uptime: ProcessInfo.processInfo.systemUptime)
        estimates = computed
        evaluateChargingPlan(.refresh)
    }

    /// App 啟動時呼叫（只有 MacBook）：手動調整上限時結束排程、睡眠前先套用排程需要的上限
    func startChargingPlan() {
        guard BatteryReader.hasBattery, !previewing else { return }
        chargingPlanRunning = true
        chargeLimit.onUserCommit = { [weak self] value in self?.chargingPlan.userChangedLimit(to: value) }
        chargingWake.onAuthorized = { [weak self] in self?.evaluateChargingPlan(.refresh) }
        chargingWake.onUnavailable = { [weak self] in
            AppSettings.shared.chargingSleepStrategy = .readinessFirst
            self?.setChargingSleepStrategy(.readinessFirst)
        }
        sleepGate.onWillSleep = { [weak self] allow in
            guard let self, self.chargingPlan.isActive else { allow(); return }
            self.evaluateChargingPlan(.willSleep, completion: allow)
        }
        sleepGate.start()
        if let plan = chargingPlan.plan {
            ChargingPlanLog.shared.write("App 啟動，繼續排程（\(plan.deadline.formatted(date: .abbreviated, time: .shortened)) 前充到 \(plan.targetPercent)%）")
        }
    }

    /// 依目前電量與排程判斷，需要時寫入充電上限；completion 在寫入（或判斷）結束後呼叫
    func evaluateChargingPlan(_ event: ChargingPlanEvent, completion: (() -> Void)? = nil) {
        guard chargingPlanRunning, !previewing, let input = chargingPlanInput() else {
            completion?()
            return
        }
        let target = chargingPlan.evaluate(input, event: event, preciseWakeReady: chargingWake.ready)
        syncChargingWake()
        guard let target else {
            completion?()
            return
        }
        Task {
            let result = await chargeLimit.applyAutomatically(target)
            chargingPlan.writeFinished(target: target, success: result.success, readBack: result.readBack)
            completion?()
        }
    }

    /// 建立排程（快速、指定時間或每週）
    func startChargingPlan(_ schedule: ChargingSchedule) {
        guard chargingPlanRunning else { return }
        let settings = AppSettings.shared
        guard chargingPlan.start(schedule, target: settings.chargingTargetPercent, hold: settings.chargingHoldPercent,
                                 currentLimit: chargeLimit.limit, strategy: settings.chargingSleepStrategy) else { return }
        evaluateChargingPlan(.refresh)
    }

    func setChargingSleepStrategy(_ strategy: ChargingSleepStrategy) {
        chargingPlan.setSleepStrategy(strategy)
        syncChargingWake()
    }

    func cancelChargingPlan() {
        guard chargingPlanRunning, let input = chargingPlanInput(), let target = chargingPlan.cancel(input) else { return }
        Task {
            let result = await chargeLimit.applyAutomatically(target)
            chargingPlan.writeFinished(target: target, success: result.success, readBack: result.readBack)
        }
    }

    /// 精準喚醒：選項打開、排程用精準喚醒時排定（或改排）喚醒，其他情況取消
    func syncChargingWake() {
        guard chargingPlanRunning else { return }
        let decision = chargingPlan.decision
        let wakeAt = chargingPlan.plan?.sleepStrategy == .preciseWake ? decision?.wakeAt : nil
        chargingWake.sync(wakeAt: wakeAt, enabled: AppSettings.shared.chargingWakeEnabled)
    }

    private func chargingPlanInput() -> ChargingPlanInput? {
        guard let s = snapshot, let e = estimates else { return nil }
        let target = chargingPlan.plan?.targetPercent ?? 100
        var estimate = Estimator.minutesToCharge(to: target, snapshot: s, estimates: e)
        if estimate == nil, target > s.percent,
           let rate = ChargingRateEstimator.percentPerHour(samples: history.samples, now: s.date) {
            estimate = Int((Double(target - s.percent) / rate * 60).rounded(.up))
        }
        return ChargingPlanInput(now: s.date, percent: s.percent, connected: s.externalConnected,
                                 limitSupported: chargeLimit.supported, currentLimit: chargeLimit.limit,
                                 estimatedMinutes: estimate, isCharging: e.state == .charging,
                                 systemPaused: [.pluggedIdle, .limitReached, .full].contains(e.state))
    }

    /// 桌上型 Mac：只讀一個 SMC 值（整機耗電），平均方式與 MacBook 的平均放電相同
    private func refreshDesktop() {
        let now = Date()
        let watts = BatteryReader.desktopSystemWatts()
        let dt = desktop.map { now.timeIntervalSince($0.date) } ?? 0
        let average = watts.map { ema(desktop?.averageWatts, $0, dt) } ?? desktop?.averageWatts
        desktop = DesktopPower(date: now, systemWatts: watts, averageWatts: average,
                               lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                               processor: ChipInfo.shortName, model: ChipInfo.model,
                               uptime: ProcessInfo.processInfo.systemUptime, hasBuiltInDisplay: ChipInfo.hasBuiltInDisplay)
    }

    func recordHistory() {
        if let desktop {
            // 桌上型 Mac 沒有電量，pct 記為 -1，歷史圖只畫耗電
            guard let watts = desktop.systemWatts else { return }
            history.add(HistorySample(t: desktop.date, pct: -1, watts: watts, plugged: true, charging: false))
            return
        }
        guard let s = snapshot, let e = estimates else { return }
        history.add(HistorySample(
            t: s.date,
            pct: s.percent,
            watts: e.systemWatts ?? max(0, -e.batteryWatts),
            plugged: s.externalConnected,
            charging: e.state == .charging
        ))
    }

    func refreshHealth() {
        Task {
            if let health = await SystemProfiler.read() {
                systemHealth = health
            }
        }
    }

    func backfillHistory() {
        // pmset 的電量紀錄只有 MacBook 才有
        guard BatteryReader.hasBattery else { return }
        Task {
            history.backfill(await PowerLog.chargeHistory())
        }
    }

    /// App 剛啟動且歷史紀錄裡找不到拔電時間時，從 pmset 紀錄補
    func resolveUnpluggedDateIfNeeded() {
        guard unpluggedAt == nil, estimates?.state == .discharging else { return }
        Task {
            if let date = await PowerLog.lastUnpluggedDate(), unpluggedAt == nil, estimates?.state == .discharging {
                unpluggedAt = date
            }
        }
    }

    /// 面板開著且停在耗電排行時，持續以 top 取樣（間隔同設定）；其他時候停掉
    func setProcessSampling(active: Bool) {
        guard active, panelVisible else {
            processStream?.stop()
            return
        }
        let interval = Int(AppSettings.shared.sampleInterval)
        // 切換省電模式後，用新的間隔重新啟動 top
        if let stream = processStream, stream.interval != interval {
            stream.stop()
            processStream = nil
        }
        if processStream == nil {
            processStream = ProcessEnergyStream(interval: interval) { [weak self] result in
                MainActor.assumeIsolatedCompat {
                    self?.topProcesses = result
                    self?.processesLoaded = true
                }
            }
        }
        processStream?.start()
    }

    private func ema(_ previous: Double?, _ value: Double, _ dt: Double) -> Double {
        guard let previous, dt > 0 else { return value }
        let alpha = 1 - exp(-dt / tau)
        return previous + alpha * (value - previous)
    }

    /// 截圖用的示範數據（README、版本說明）：不含任何使用者的真實資料
    func loadPreview(now: Date = Date()) {
        previewing = true
        var s = BatterySnapshot()
        s.date = now
        s.percent = 78
        s.voltage_mV = 12450
        s.amperage_mA = -520
        s.cycleCount = 212
        s.designCycleCount = 1000
        s.remaining_mAh = 3900
        s.fullCharge_mAh = 5000
        s.nominal_mAh = 5080
        s.design_mAh = 5500
        s.psTimeToEmpty = 445
        s.avgTimeToEmpty = 450
        s.temperature_C = 31.4
        s.smcAdapterWatts = 0
        s.smcSystemWatts = 6.5
        s.chargeLimit = ChargeLimit(limit: 80, reason: "manualChargeLimit", active: false)
        chargeLimit.loadPreview(limit: 80)
        snapshot = s
        avgDischarge = 520
        estimates = Estimator.estimates(s, avgDischarge_mA: 520, avgCharge_mA: nil)
        systemHealth = SystemHealth(maxCapacityPercent: 92, condition: "Good", cycleCount: 212)
        unpluggedAt = now.addingTimeInterval(-(2 * 3600 + 15 * 60))
        // 24 小時：前一晚接電充到 80%，早上拔掉後慢慢用到 78%
        var samples: [HistorySample] = []
        for minute in stride(from: 24 * 60, through: 0, by: -10) {
            let t = now.addingTimeInterval(-Double(minute) * 60)
            let plugged = minute > 135
            let pct = plugged ? min(80, 45 + (24 * 60 - minute) / 12) : 80 - (135 - minute) / 60
            let watts = plugged ? 4.5 + 2 * sin(Double(minute) / 37) : 6 + 2.5 * sin(Double(minute) / 9)
            samples.append(HistorySample(t: t, pct: pct, watts: max(1, watts), plugged: plugged, charging: plugged && pct < 80))
        }
        history.loadPreview(samples)
        topProcesses = [
            EnergyProcess(id: "safari", name: "Safari", power: 12.4, appPath: "/Applications/Safari.app"),
            EnergyProcess(id: "music", name: "音樂", power: 6.8, appPath: "/System/Applications/Music.app"),
            EnergyProcess(id: "mail", name: "郵件", power: 3.2, appPath: "/System/Applications/Mail.app"),
            EnergyProcess(id: "photos", name: "照片", power: 2.1, appPath: "/System/Applications/Photos.app"),
            EnergyProcess(id: "finder", name: "Finder", power: 0.9, appPath: "/System/Library/CoreServices/Finder.app"),
        ]
        processesLoaded = true
    }

    /// 桌上型 Mac 的示範數據（截圖用）：整機約 38 W，CPU 21 W、GPU 2 W，一天的耗電歷史
    func loadDesktopPreview(now: Date = Date()) {
        snapshot = nil
        estimates = nil
        previewing = true
        desktop = DesktopPower(date: now, systemWatts: 38.4, averageWatts: 36.2, processor: "Apple M2 Pro", model: "Mac14,12",
                               uptime: (3 * 24 + 4) * 3600, hasBuiltInDisplay: false)
        let uptime = ProcessInfo.processInfo.systemUptime
        // 像 Mac mini：沒有內建螢幕（沒有背光感測器），ANE 閒置
        var sample = ComponentPowerSample(uptime: uptime, interval: 1, backlightWatts: nil, cpuWatts: 21.3, gpuWatts: 2.1,
                                          aneWatts: 0, systemWatts: 38.4, systemWindowAligned: true)
        sample.backlightAvailable = false
        componentPower = sample
        breakdown = PowerBreakdown.make(systemWatts: 38.4, components: sample, now: uptime)
        var samples: [HistorySample] = []
        for minute in stride(from: 24 * 60, through: 0, by: -10) {
            let t = now.addingTimeInterval(-Double(minute) * 60)
            let busy = (9 * 60...18 * 60).contains((24 * 60 - minute + 8 * 60) % (24 * 60))
            let watts = (busy ? 42 : 24) + 6 * sin(Double(minute) / 23)
            samples.append(HistorySample(t: t, pct: -1, watts: watts, plugged: true, charging: false))
        }
        history.loadPreview(samples)
        topProcesses = [
            EnergyProcess(id: "safari", name: "Safari", power: 12.4, appPath: "/Applications/Safari.app"),
            EnergyProcess(id: "music", name: "音樂", power: 6.8, appPath: "/System/Applications/Music.app"),
            EnergyProcess(id: "photos", name: "照片", power: 2.1, appPath: "/System/Applications/Photos.app"),
        ]
        processesLoaded = true
    }

    /// 截圖用的智慧充電示範：明天 7:30 前充到 100%，等待時維持 80%（只放在記憶體，不寫入使用者的排程）
    func loadChargingPlanPreview(now: Date = Date()) {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let deadline = calendar.date(bySettingHour: 7, minute: 30, second: 0, of: tomorrow) ?? now
        let plan = ChargingPlan(schedule: .weekly(weekdays: [2, 3, 4, 5, 6], minuteOfDay: 7 * 60 + 30), deadline: deadline,
                                targetPercent: 100, holdPercent: 80, restoreLimit: 80, sleepStrategy: .preciseWake, createdAt: now)
        let input = ChargingPlanInput(now: now, percent: snapshot?.percent ?? 80, connected: true, limitSupported: true,
                                      currentLimit: 80, estimatedMinutes: nil, isCharging: false, systemPaused: true)
        chargingPlan.loadPreview(plan, decision: ChargingPlanEngine.evaluate(plan, input: input))
    }

    /// 開發用快照：接著電源的示範狀態（檢查充電中、已達充電上限時的版面）
    func loadPluggedPreview(now: Date = Date(), atLimit: Bool) {
        loadPreview(now: now)
        guard var s = snapshot else { return }
        s.externalConnected = true
        s.adapter = AdapterInfo(watts: 30)
        s.chargeLimit = ChargeLimit(limit: 80, reason: "manualChargeLimit", active: true)
        s.psTimeToEmpty = nil
        s.avgTimeToEmpty = nil
        if atLimit {
            s.percent = 80
            s.amperage_mA = 0
            s.smcAdapterWatts = 6.5
        } else {
            s.percent = 62
            s.amperage_mA = 1500
            s.isCharging = true
            s.smcAdapterWatts = 25
        }
        snapshot = s
        unpluggedAt = nil
        avgDischarge = nil
        avgCharge = atLimit ? nil : 1500
        estimates = Estimator.estimates(s, avgDischarge_mA: nil, avgCharge_mA: avgCharge)
    }
}
