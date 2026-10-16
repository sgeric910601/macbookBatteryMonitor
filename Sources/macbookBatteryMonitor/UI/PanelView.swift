import SwiftUI

struct RootView: View {
    @ObservedObject var store: BatteryStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: PanelState

    var body: some View {
        Group {
            if !ui.isVisible {
                Color.clear.frame(height: 1)
            } else {
                switch ui.page {
                case .main: MainPage(store: store, settings: settings, ui: ui)
                case .chargingPlan: ScrollingPage(page: .chargingPlan, ui: ui) { ChargingPlanView(store: store, settings: settings, ui: ui) }
                }
            }
        }
        .frame(width: 380)
    }
}

/// 主面板：放得下時維持原本的版面；比螢幕還高時（小螢幕或放大顯示）改成可捲動，免得下方被切掉
private struct MainPage: View {
    @ObservedObject var store: BatteryStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: PanelState

    var body: some View {
        if (ui.pageHeights[.main] ?? 0) > ScrollingPage<EmptyView>.maxHeight {
            ScrollingPage(page: .main, ui: ui) { PanelView(store: store, settings: settings, ui: ui) }
        } else {
            PanelView(store: store, settings: settings, ui: ui)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                })
                .onPreferenceChange(ContentHeightKey.self) { height in
                    if height > 0, ui.pageHeights[.main] != height { ui.pageHeights[.main] = height }
                }
        }
    }
}

struct PanelView: View {
    @ObservedObject var store: BatteryStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: PanelState

    var body: some View {
        VStack(spacing: 10) {
            if let s = store.snapshot, let e = store.estimates {
                HeaderView(s: s, e: e, lowThreshold: settings.lowThreshold)
                TimeCard(s: s, e: e, unpluggedAt: store.unpluggedAt, pluggedInAt: store.pluggedInAt,
                         fullThreshold: settings.fullThreshold,
                         chargeLimit: store.chargeLimit.supported ? store.chargeLimit : nil,
                         planActive: store.chargingPlan.isActive,
                         journey: store.companionPresentation(s, e),
                         appearance: settings.chargingAppearance,
                         animated: ui.isVisible && !settings.powerSavingActive,
                         openPlan: { ui.page = .chargingPlan })
                PowerFlowView(s: s, e: e, breakdown: store.breakdown, ui: ui, powerSaving: settings.powerSavingActive)
                Picker("", selection: ui.binding(\.tab)) {
                    ForEach(BottomTab.tabs(desktop: false), id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Group {
                    switch ui.tab {
                    case .details: DetailsGridView(s: s, e: e, health: store.systemHealth, limitSlider: store.chargeLimit.supported,
                                                   openDisplayItems: { ui.openSettings(.display) })
                    case .history: HistoryChartView(history: store.history, ui: ui)
                    case .processes: TopProcessesView(store: store)
                    case .peripherals: PeripheralsView(store: store.peripherals, settings: settings)
                    case .today: DailyRecapView(recap: DailyBatteryRecap.make(samples: store.history.samples, day: s.date))
                    }
                }
                .frame(height: 231, alignment: .top)
                footer(updated: s.date)
            } else if let desktop = store.desktop {
                DesktopPanelView(store: store, desktop: desktop, settings: settings, ui: ui)
                footer(updated: desktop.date)
            } else {
                UnavailableMessage(title: "找不到電池", systemImage: SymbolCompat.name("battery.0percent"), description: "讀不到這台 Mac 的電池與耗電資訊。")
                footer(updated: nil)
            }
        }
        .padding(14)
        // 面板換成可捲動的版面時，SwiftUI 會重建內容，可能在面板關閉後才補發 onAppear：只有面板真的開著才開始取樣
        .onAppear { if ui.isVisible { store.setHardwareSampling(active: true) } }
        .onDisappear { store.setHardwareSampling(active: false) }
    }

    private func footer(updated: Date?) -> some View {
        HStack(spacing: 12) {
            if let updated {
                Text("更新於 \(updated.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            // Beta 是使用者手動找到的，不在面板上提示
            if let release = store.updater.available, !release.isBeta {
                Button {
                    ui.openSettings(.update)
                } label: {
                    Label("有新版本 v\(release.versionText)", systemImage: "arrow.down.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("到設定一鍵更新")
            }
            Button {
                ui.openSettings(nil)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("設定")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("結束\(AppEdition.appName)")
        }
    }
}

private struct HeaderView: View {
    let s: BatterySnapshot
    let e: Estimates
    let lowThreshold: Int

    var body: some View {
        HStack(spacing: 14) {
            BatteryGlyph(percent: s.percent, state: e.state, lowThreshold: lowThreshold, limit: s.chargeLimit?.limit)
                .frame(width: 62, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(s.percent)%")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Label(e.state.title, systemImage: e.state.symbol)
                    .font(.callout)
                    .foregroundStyle(e.state.tint)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(headline.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(headline.value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }

    private var headline: (caption: String, value: String) {
        switch e.state {
        case .discharging:
            return ("剩餘時間", e.headlineToEmpty.map { Format.duration($0) } ?? "計算中…")
        case .charging:
            if let limit = s.chargeLimit?.limit, s.percent < limit {
                return ("充到 \(limit)% 還要", e.toLimit.map { Format.duration($0) } ?? "計算中…")
            }
            return ("充滿還要", e.toFull.map { Format.duration($0) } ?? "計算中…")
        case .pluggedIdle:
            if e.drainingOnAC {
                return ("剩餘時間", e.headlineToEmpty.map { Format.duration($0) } ?? "計算中…")
            }
            return ("電源供電", "暫停充電")
        case .full:
            return ("電源供電", "已充飽")
        case .limitReached:
            // 上限數值已在狀態文字與滑桿上，這裡改顯示供電狀況
            return ("電源供電", s.drainingAboveLimit ? "放電到上限" : "暫停充電")
        }
    }
}

private struct TimeCard: View {
    let s: BatterySnapshot
    let e: Estimates
    let unpluggedAt: Date?
    /// App 執行中插上電源的時間：剛插電、macOS 還沒開始充電時改用另一段說明
    var pluggedInAt: Date?
    let fullThreshold: Int
    /// 充電上限滑桿（支援調整的 Mac 才有），放在卡片最上方
    var chargeLimit: SystemChargeLimit?
    var planActive = false
    /// 充電夥伴與智慧充電：支援調整充電上限的 Mac 放在滑桿左邊、排程狀態在滑桿下方；不支援的 Mac 只有夥伴與說明
    var journey: ChargingJourneyPresentation?
    var appearance: ChargingAppearance = .companion
    var animated = false
    var openPlan: () -> Void = {}

    /// 上限數值只在滑桿顯示，卡片其他地方不再重複
    private var limitShownAbove: Bool { chargeLimit != nil }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                if let chargeLimit, let journey {
                    ChargingJourneyView(presentation: journey, appearance: appearance, animated: animated, open: openPlan) {
                        ChargeLimitSlider(control: chargeLimit, planActive: planActive)
                    }
                    Divider()
                } else if let journey {
                    // 不能調整充電上限的 Mac：一樣有充電夥伴，只是沒有滑桿
                    ChargingJourneyView(presentation: journey, appearance: appearance, animated: animated, open: openPlan) {
                        EmptyView()
                    }
                    Divider()
                }
                switch e.state {
                case .discharging: discharging
                case .charging: charging
                case .pluggedIdle, .full, .limitReached: plugged
                }
            }
        }
    }

    private var discharging: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle("預估可用時間", systemImage: "clock")
            // macOS 12 沒有 Grid：標籤欄寬依最長的標籤，兩個時間欄固定寬度
            let labelWidth = TextWidth.max(["系統預估", "依目前耗電"])
            VStack(alignment: .leading, spacing: 5) {
                estimateRow(labelWidth, "", Text("用到 0%").font(.caption).foregroundColor(.secondary),
                            Text("用到 10%").font(.caption).foregroundColor(.secondary))
                estimateRow(labelWidth, "系統預估", Text(e.systemToEmpty == nil ? "計算中…" : Format.duration(e.systemToEmpty)),
                            Text(e.systemTo10 == nil && s.percent > Estimator.reservePercent ? "計算中…" : to10(e.systemTo10)).bold())
                estimateRow(labelWidth, "依目前耗電", Text(Format.duration(e.liveToEmpty)), Text(to10(e.liveTo10)).bold())
            }
            .font(.callout)
            .monospacedDigit()
            Divider()
            HStack {
                Text("已使用電池").foregroundStyle(.secondary)
                Spacer()
                Text(unpluggedAt.map { Format.since($0) } ?? "—").monospacedDigit()
            }
            .font(.callout)
            if let current = e.avgDischarge_mA {
                Text("近 3 分鐘平均放電 \(Format.milliamps(current))（約 \(Format.watts(current * Double(s.voltage_mV) / 1_000_000))）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var charging: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle("充電預估", systemImage: "bolt")
            // 剛開始充電的頭一分鐘還沒有平均電流，macOS 也還在估算
            if let limit = s.chargeLimit?.limit {
                row(limitShownAbove ? "充到上限" : "充到上限 (\(limit)%)", e.toLimit.map { Format.duration($0) } ?? "計算中…")
            } else {
                row("充滿 (100%)", e.toFull.map { Format.duration($0) } ?? "計算中…")
            }
            if fullThreshold < 100, s.percent < fullThreshold {
                row("充到 \(fullThreshold)%", Format.duration(Estimator.minutesToCharge(to: fullThreshold, snapshot: s, estimates: e)))
            }
            row("近 3 分鐘平均充電電流", e.avgCharge_mA.map { Format.milliamps($0) } ?? "計算中…")
            row("充入功率", Format.watts(max(0, e.batteryWatts)))
        }
    }

    private var plugged: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle("電源狀態", systemImage: "powerplug")
            Text(pluggedMessage)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let limit = s.chargeLimit?.limit {
                if !limitShownAbove {
                    row("充電上限", "\(limit)%（系統設定）")
                }
                if let minutes = minutesToDrain(to: limit) {
                    row("降到上限約需", Format.duration(minutes))
                }
            }
            if let watts = s.adapter?.watts {
                row("變壓器", "\(watts) W")
            }
        }
    }

    /// 電量高於上限、macOS 正在放電時，估計多久會降到上限
    private func minutesToDrain(to limit: Int) -> Int? {
        guard s.drainingAboveLimit, let full = s.fullCharge_mAh else { return nil }
        let current = e.avgDischarge_mA ?? Double(-s.effectiveAmperage_mA)
        guard current > 10 else { return nil }
        return Int((Double(full) * Double(s.percent - limit) / 100 / current * 60).rounded())
    }

    private var justPlugged: Bool {
        pluggedInAt.map { s.date.timeIntervalSince($0) < 30 } ?? false
    }

    private var pluggedMessage: String {
        switch e.state {
        case .limitReached:
            let limit = s.chargeLimit?.limit ?? 100
            if s.drainingAboveLimit {
                return "電量高於上限，macOS 正在讓電池慢慢降到 \(limit)%。"
            }
            if s.percent > limit {
                return "已超過充電上限，暫停充電；降到 \(limit)% 以下才會再充。"
            }
            return "已充到上限，暫停充電，由變壓器供電。"
        case .full:
            return "已充飽，由變壓器供電。"
        case .pluggedIdle where justPlugged:
            // Intel 的充電器要十幾秒才開始充電，這段期間電池可能還在放電
            return "剛接上電源，幾秒後就會開始充電。"
        case .pluggedIdle where e.drainingOnAC:
            return "供電不足，電池仍在放電，預估剩餘 \(Format.duration(e.headlineToEmpty))。"
        default:
            return "接著電源但沒有在充電，可能是最佳化電池充電或溫度保護。"
        }
    }

    private func estimateRow(_ labelWidth: CGFloat, _ label: String, _ toEmpty: Text, _ to10: Text) -> some View {
        HStack(spacing: 14) {
            Text(label).foregroundStyle(.secondary).frame(width: labelWidth, alignment: .leading)
            toEmpty.frame(width: 104, alignment: .leading)
            to10.frame(maxWidth: .infinity, alignment: .leading)
        }
        .lineLimit(1)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }

    private func to10(_ minutes: Int?) -> String {
        s.percent <= Estimator.reservePercent ? "已低於 10%" : Format.duration(minutes)
    }
}

/// 內容比螢幕高時（例如智慧充電頁）改成可捲動，面板最高到螢幕可用高度；放得下時維持內容原本的高度。
/// 否則 macOS 會把超出螢幕的上半部（返回按鈕與第一張卡片）直接切掉
struct ScrollingPage<Content: View>: View {
    let page: PanelPage
    @ObservedObject var ui: PanelState
    @ViewBuilder var content: Content

    /// 扣掉選單列與 popover 箭頭、邊緣的空間
    static var maxHeight: CGFloat { max(300, (NSScreen.main?.visibleFrame.height ?? 800) - 40) }
    private var maxHeight: CGFloat { Self.maxHeight }

    var body: some View {
        ScrollView {
            content
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                })
        }
        .bounceOnlyWhenScrollable()
        .frame(height: min(ui.pageHeights[page] ?? maxHeight, maxHeight))
        .onPreferenceChange(ContentHeightKey.self) { height in
            if height > 0, ui.pageHeights[page] != height { ui.pageHeights[page] = height }
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
