import SwiftUI

/// 智慧充電頁：目前的排程、快速設定、每週排程、目標與保養上限、睡眠時的策略。
/// 面板（點充電夥伴打開）與設定視窗的「充電」各一份，用同一份設定
struct ChargingPlanView: View {
    @ObservedObject var store: BatteryStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: PanelState
    /// 放在設定視窗裡：不要返回按鈕與外觀（設定視窗另有「充電夥伴」），建立排程後留在原地
    var embedded = false

    /// 星期一排到星期日（Calendar 的 weekday：1 = 星期日）
    private let weekdays = [(2, "一"), (3, "二"), (4, "三"), (5, "四"), (6, "五"), (7, "六"), (1, "日")]

    private var controller: ChargingPlanController { store.chargingPlan }
    private var supported: Bool { store.chargeLimit.supported }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if embedded {
                CardTitle("智慧充電", systemImage: SymbolCompat.name("bolt.badge.clock"))
            } else {
                ZStack {
                    Text("智慧充電").font(.headline)
                    HStack {
                        Button { ui.page = .main } label: { Label("返回", systemImage: "chevron.left") }
                            .buttonStyle(.borderless)
                        Spacer()
                    }
                }
            }

            Text("在你要用之前充好，平常維持保養上限。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 點貓咪進來的人最常想換外觀：直接放在最上面（不支援智慧充電的 Mac 也能換）
            if !embedded {
                HStack(spacing: 8) {
                    Text(supported ? "滑桿旁顯示" : "面板上方顯示").font(.callout)
                    Picker("外觀", selection: Binding(get: { settings.chargingAppearance },
                                                    set: { settings.selectAppearance($0) })) {
                        ForEach(ChargingAppearance.allCases) { Text($0.shortTitle).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if settings.chargingAppearance == .customPhoto {
                    Button("換照片…") { settings.chooseCompanionPhoto() }
                        .help("換一張自己的照片；貓咪大頭照會保留")
                }
            }

            if !supported {
                Card {
                    Label("這台 Mac 無法調整充電上限，不支援智慧充電。", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                if let plan = controller.plan { currentPlan(plan) }
                quickCard
                weeklyCard
                strategyCard
            }
        }
        .padding(embedded ? 0 : 14)
    }

    /// 建立排程後回到主面板看狀態；在設定視窗裡留在原地，上方會出現目前的排程
    private func planStarted() {
        if !embedded { ui.page = .main }
    }

    // MARK: 目前的排程

    private func currentPlan(_ plan: ChargingPlan) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CardTitle(plan.schedule.isWeekly ? "目前排程（每週）" : "目前排程", systemImage: phaseSymbol)
                    Spacer()
                    Text(plan.restoring ? "還原中" : controller.decision?.phase.title ?? "判斷中")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(phaseColor)
                }
                Text(ChargingJourneyPresentation.time(plan.deadline, now: Date()))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(plan.targetPercent == plan.restoreLimit
                     ? "前充到 \(plan.targetPercent)%（原本的上限）・等待時維持 \(ChargingPlanEngine.holdLimit(plan, percent: store.snapshot?.percent ?? 0))%"
                     : "前充到 \(plan.targetPercent)%・等待時維持 \(ChargingPlanEngine.holdLimit(plan, percent: store.snapshot?.percent ?? 0))%・結束後還原為 \(plan.restoreLimit)%")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .weekly(let days, _) = plan.schedule {
                    Text("每週" + weekdays.filter { days.contains($0.0) }.map(\.1).joined(separator: "、"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let decision = controller.decision, decision.phase == .waiting {
                    Label("預計 \(ChargingJourneyPresentation.time(decision.startAt, now: Date())) 開始充電（需要約 \(ChargingJourneyPresentation.duration(decision.requiredMinutes))，另留 \(ChargingPlanEngine.bufferMinutes) 分鐘緩衝）",
                          systemImage: SymbolCompat.name("bolt.badge.clock"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = controller.writeError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                Button("取消排程並還原為 \(plan.restoreLimit)%", role: .destructive) { store.cancelChargingPlan() }
                    .disabled(plan.restoring)
            }
        }
    }

    // MARK: 快速設定

    private var quickCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(controller.plan == nil ? "多久後要用" : "改成新的排程", systemImage: "timer")
                ForEach([1, 2, 3], id: \.self) { hours in
                    let deadline = Date().addingTimeInterval(Double(hours) * 3600)
                    HStack(spacing: 10) {
                        Button("\(hours) 小時後") {
                            store.startChargingPlan(.once(Date().addingTimeInterval(Double(hours) * 3600)))
                            planStarted()
                        }
                        .frame(width: 92, alignment: .leading)
                        forecastLabel(until: deadline)
                        Spacer(minLength: 0)
                    }
                }
                Divider()
                DatePicker("完成時間", selection: ui.binding(\.chargingCustomDeadline), in: Date()...,
                           displayedComponents: [.date, .hourAndMinute])
                HStack(spacing: 10) {
                    Button("在這個時間前充好") {
                        store.startChargingPlan(.once(ui.chargingCustomDeadline))
                        planStarted()
                    }
                    .disabled(ui.chargingCustomDeadline.timeIntervalSinceNow < 60)
                    forecastLabel(until: ui.chargingCustomDeadline)
                }
            }
        }
    }

    /// 依目前電量與充電速度，預估來不來得及充到完成目標
    @ViewBuilder private func forecastLabel(until deadline: Date) -> some View {
        let target = store.chargingTarget
        if let forecast = store.chargingForecast(until: deadline, target: target), let percent = store.snapshot?.percent {
            let plugged = store.snapshot?.externalConnected == true ? "" : "接上電源的話，"
            if percent >= target {
                Text("已達 \(target)%").font(.caption).foregroundStyle(.secondary)
            } else if forecast.onTime {
                // 和排程相同：往前推需要的時間再加緩衝，就是開始充電的時間
                let start = deadline.addingTimeInterval(-Double(forecast.neededMinutes + ChargingPlanEngine.bufferMinutes) * 60)
                // 和排程相同：電量已高於保養上限時維持目前的電量（進位到 5%），不先放電
                let hold = min(target, max(min(settings.chargingHoldPercent, target), Int((Double(percent) / 5).rounded(.up)) * 5))
                Text(hold >= target
                     ? "\(plugged)會直接充到 \(target)%（約需 \(ChargingJourneyPresentation.duration(forecast.neededMinutes))）"
                     : start.timeIntervalSinceNow > 60
                     ? "\(plugged)可準時充到 \(target)%：先維持 \(hold)%，約 \(ChargingJourneyPresentation.time(start, now: Date())) 開始充"
                     : "\(plugged)可準時充到 \(target)%，會立刻開始充（約需 \(ChargingJourneyPresentation.duration(forecast.neededMinutes))）")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("\(plugged)來不及充到 \(target)%，預計最多約 \(forecast.reachablePercent)%（約需 \(ChargingJourneyPresentation.duration(forecast.neededMinutes))）",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 每週排程

    private var weeklyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(controller.plan?.schedule.isWeekly == true ? "改成新的每週排程" : "每週排程", systemImage: "calendar")
                HStack(spacing: 6) {
                    ForEach(weekdays, id: \.0) { day, label in
                        let selected = ui.chargingWeekdays.contains(day)
                        Button {
                            if selected { ui.chargingWeekdays.remove(day) } else { ui.chargingWeekdays.insert(day) }
                        } label: {
                            Text(label)
                                .font(.caption.weight(.semibold))
                                .frame(width: 26, height: 22)
                                .background(selected ? Color.accentColor : Color.secondary.opacity(0.13),
                                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .foregroundStyle(selected ? Color.white : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("星期\(label)")
                        .accessibilityValue(selected ? "已選取" : "未選取")
                    }
                }
                DatePicker("完成時間", selection: ui.binding(\.chargingWeeklyTime), displayedComponents: .hourAndMinute)
                Button("儲存每週排程") {
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: ui.chargingWeeklyTime)
                    store.startChargingPlan(.weekly(weekdays: ui.chargingWeekdays,
                                                    minuteOfDay: (parts.hour ?? 8) * 60 + (parts.minute ?? 0)))
                    planStarted()
                }
                .disabled(ui.chargingWeekdays.isEmpty)
                Text("例如上班日 8:00 前充到完成目標，其他時間維持保養上限。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 目標與睡眠策略

    private var strategyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle("目標與保養上限", systemImage: "slider.horizontal.3")
                Picker("完成目標", selection: targetBinding) {
                    Text("原本的上限（\(originalLimit)%）").tag(AppSettings.originalLimitTarget)
                    ForEach(options, id: \.self) { Text("\($0)%").tag($0) }
                }
                Picker("保養上限", selection: holdBinding) {
                    ForEach(options.filter { $0 <= store.chargingTarget }, id: \.self) { Text("\($0)%").tag($0) }
                }
                Text("套用到之後建立的排程。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                Picker("睡眠時", selection: strategyBinding) {
                    ForEach(ChargingSleepStrategy.allCases) { Text($0.title).tag($0) }
                }
                Text(settings.chargingSleepStrategy == .preciseWake
                     ? "時間到時叫醒 Mac 開始充電；需要輸入一次管理員密碼。"
                     : "睡著前先提高上限，在睡眠中充好，可能會比預定時間早充滿。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if settings.chargingSleepStrategy == .preciseWake {
                    Text(store.chargingWake.status)
                        .font(.caption)
                        .foregroundStyle(store.chargingWake.ready ? Color.green : Color.secondary)
                }
            }
        }
    }

    private var options: [Int] { store.chargeLimit.options.filter { $0 >= 50 } }

    /// 排程開始前的系統充電上限（排程進行中顯示排程開始前的上限）
    private var originalLimit: Int { controller.plan?.restoreLimit ?? store.chargeLimit.limit }

    private var targetBinding: Binding<Int> {
        Binding(get: {
            settings.chargingTargetPercent == AppSettings.originalLimitTarget
                ? AppSettings.originalLimitTarget : nearest(settings.chargingTargetPercent, in: options)
        }, set: { settings.chargingTargetPercent = $0 })
    }

    private var holdBinding: Binding<Int> {
        Binding(get: { nearest(settings.chargingHoldPercent, in: options.filter { $0 <= store.chargingTarget }) },
                set: { settings.chargingHoldPercent = $0 })
    }

    /// 選精準喚醒時要求管理員授權（失敗會自動改回優先準時完成）；目前的排程也改用新的策略
    private var strategyBinding: Binding<ChargingSleepStrategy> {
        Binding(get: { settings.chargingSleepStrategy }, set: { value in
            settings.chargingSleepStrategy = value
            settings.chargingWakeEnabled = value == .preciseWake
            store.setChargingSleepStrategy(value)
        })
    }

    private func nearest(_ value: Int, in choices: [Int]) -> Int {
        choices.min { abs($0 - value) < abs($1 - value) } ?? value
    }

    private var phaseSymbol: String {
        switch controller.decision?.phase {
        case .ready: return "checkmark.circle.fill"
        case .late: return "exclamationmark.triangle.fill"
        case .charging, .starting: return "bolt.fill"
        default: return "clock.fill"
        }
    }

    private var phaseColor: Color {
        switch controller.decision?.phase {
        case .ready: return .green
        case .late, .systemPaused: return .orange
        default: return .secondary
        }
    }
}
