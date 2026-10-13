import SwiftUI

/// 智慧充電頁：目前的排程、快速設定、每週排程、目標與保養上限、睡眠時的策略
struct ChargingPlanView: View {
    @ObservedObject var store: BatteryStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: PanelState

    /// 星期一排到星期日（Calendar 的 weekday：1 = 星期日）
    private let weekdays = [(2, "一"), (3, "二"), (4, "三"), (5, "四"), (6, "五"), (7, "六"), (1, "日")]

    private var controller: ChargingPlanController { store.chargingPlan }
    private var supported: Bool { store.chargeLimit.supported }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Text("智慧充電").font(.headline)
                HStack {
                    Button { ui.page = .main } label: { Label("返回", systemImage: "chevron.left") }
                        .buttonStyle(.borderless)
                    Spacer()
                }
            }

            Text("平常把充電上限維持在保養上限，算好需要的時間，再把上限提高到目標，讓 Mac 在指定時間前充好；結束後還原原本的上限。實際充電仍由 macOS 控制。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !supported {
                Card {
                    Label("這台 Mac 不支援調整充電上限（需要 Apple 晶片的 MacBook，且系統設定的「電池」裡有充電上限），無法使用智慧充電。",
                          systemImage: "exclamationmark.triangle")
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
        .padding(14)
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
                Text("前充到 \(plan.targetPercent)%・等待時維持 \(plan.holdPercent)%・結束後還原為 \(plan.restoreLimit)%")
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
                CardTitle(controller.plan == nil ? "快速設定" : "改成新的排程", systemImage: "timer")
                HStack(spacing: 8) {
                    ForEach([1, 2, 3], id: \.self) { hours in
                        Button("\(hours) 小時後") {
                            store.startChargingPlan(.once(Date().addingTimeInterval(Double(hours) * 3600)))
                            ui.page = .main
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Divider()
                DatePicker("完成時間", selection: ui.binding(\.chargingCustomDeadline), in: Date()...,
                           displayedComponents: [.date, .hourAndMinute])
                Button("在這個時間前充好") {
                    store.startChargingPlan(.once(ui.chargingCustomDeadline))
                    ui.page = .main
                }
                .disabled(ui.chargingCustomDeadline.timeIntervalSinceNow < 60)
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
                    ui.page = .main
                }
                .disabled(ui.chargingWeekdays.isEmpty)
                Text("例如上班日 8:00 前充到 100%，其他時間維持保養上限。")
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
                    ForEach(options, id: \.self) { Text("\($0)%").tag($0) }
                }
                Picker("保養上限", selection: holdBinding) {
                    ForEach(options.filter { $0 <= settings.chargingTargetPercent }, id: \.self) { Text("\($0)%").tag($0) }
                }
                Text("新的排程使用這裡的設定。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                Picker("睡眠時", selection: strategyBinding) {
                    ForEach(ChargingSleepStrategy.allCases) { Text($0.title).tag($0) }
                }
                Text(settings.chargingSleepStrategy == .preciseWake
                     ? "在該開始充電前叫醒 Mac 調整充電上限，等待期間維持保養上限。需要管理員授權一次（與「管理員 CPU 取樣」共用同一個服務，App 只能排定這一個喚醒事件）；授權失敗或服務無法使用時，自動改用「優先準時完成」。"
                     : "Mac 睡著時無法準時調整上限：睡眠前若還在等待，會先把上限提高到目標，讓 macOS 在睡眠中充好（可能比預定時間早充滿）。")
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

    private var targetBinding: Binding<Int> {
        Binding(get: { nearest(settings.chargingTargetPercent, in: options) }, set: { settings.chargingTargetPercent = $0 })
    }

    private var holdBinding: Binding<Int> {
        Binding(get: { nearest(settings.chargingHoldPercent, in: options.filter { $0 <= settings.chargingTargetPercent }) },
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
