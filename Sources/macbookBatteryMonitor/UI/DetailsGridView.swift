import SwiftUI

struct DetailsGridView: View {
    let s: BatterySnapshot
    let e: Estimates
    let health: SystemHealth?
    /// 主面板有充電上限滑桿
    var limitSlider = false
    /// 打開設定視窗的「顯示項目」
    var openDisplayItems: () -> Void = {}

    private var settings: AppSettings { .shared }
    /// 表格右欄數值文字最右邊的位置，充電器規格的右緣對齊這裡
    @State private var valuesRightEdge: CGFloat?

    var body: some View {
        Card() {
          VStack(alignment: .leading, spacing: 10) {
            // 只顯示設定裡勾選的欄位，依序每列兩欄
            let fields = DetailField.available(limitSlider: limitSlider).filter { settings.isVisible($0) }
            if fields.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("所有表格欄位都已隱藏。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("在設定 → 顯示項目調整…", action: openDisplayItems)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 9) {
                    ForEach(Array(stride(from: 0, to: fields.count, by: 2)), id: \.self) { index in
                        row(fields[index], index + 1 < fields.count ? fields[index + 1] : nil)
                    }
                }
                .font(.callout)
            }
            if s.externalConnected, settings.showChargerSpecifications {
                if !fields.isEmpty { Divider() }
                ChargerSection(s: s, rightEdge: fields.isEmpty ? nil : valuesRightEdge)
            }
          }
          .coordinateSpace(name: "details")
          .onPreferenceChange(ValuesRightEdge.self) { valuesRightEdge = $0 > 0 ? $0 : nil }
        }
    }

    private func value(_ field: DetailField) -> String {
        switch field {
        case .voltage: return String(format: "%.2f V", Double(s.voltage_mV) / 1000)
        case .current: return "\(s.effectiveAmperage_mA.formatted()) mA"
        case .batteryPower: return Format.watts(abs(e.batteryWatts))
        case .systemPower: return Format.watts(e.systemWatts)
        case .systemEstimate: return systemEstimateText
        case .temperature: return s.temperature_C.map { String(format: "%.1f °C", $0) } ?? "—"
        case .health: return health?.maxCapacityPercent.map { "\($0)%" } ?? "—"
        case .computedHealth: return e.healthComputed.map { String(format: "%.1f%%", $0) } ?? "—"
        case .cycles: return cycleText
        case .condition: return health?.conditionText ?? "—"
        case .remaining: return Format.mAh(s.remaining_mAh)
        case .fullCharge: return Format.mAh(s.fullCharge_mAh)
        case .design: return Format.mAh(s.design_mAh)
        case .lowPower: return s.lowPowerMode ? "開啟" : "關閉"
        case .adapter: return adapterText
        case .chargeLimit: return s.chargeLimit.map { "\($0.limit)%" } ?? "未設定"
        case .adapterVoltage:
            guard s.externalConnected else { return "未連接" }
            return s.smcAdapterVolts.map { String(format: "%.2f V", $0) } ?? "—"
        case .adapterCurrent:
            guard s.externalConnected else { return "未連接" }
            let milliamps = s.smcAdapterAmps.map { Int(($0 * 1000).rounded()) } ?? s.systemCurrentIn_mA
            return milliamps.map { "\($0.formatted()) mA" } ?? "—"
        }
    }

    /// macOS 自己的預估：用電池時是剩餘時間，充電時是充滿時間
    private var systemEstimateText: String {
        switch e.state {
        case .discharging:
            return e.systemToEmpty.map { Format.duration($0) } ?? "計算中…"
        case .charging:
            // 與「預計充好」相同的目標：還沒到充電上限時是充到上限；已超過上限仍在充（上限沒生效）時是充滿
            if let limit = s.chargeLimit?.limit, s.percent < limit {
                return e.toLimit.map { "到 \(limit)% \(Format.clock($0) ?? "")" } ?? "計算中…"
            }
            return e.toFull.map { "充滿 \(Format.clock($0) ?? "")" } ?? "計算中…"
        case .pluggedIdle, .full, .limitReached:
            return "接電中"
        }
    }

    private var cycleText: String {
        if let design = s.designCycleCount { return "\(s.cycleCount) / \(design)" }
        return "\(s.cycleCount)"
    }

    private var adapterText: String {
        guard s.externalConnected else { return "未連接" }
        if let watts = s.adapter?.watts { return "\(watts) W" }
        return "已連接"
    }

    private func row(_ first: DetailField, _ second: DetailField?) -> some View {
        GridRow {
            Text(first.title).foregroundStyle(.secondary)
            Text(value(first)).monospacedDigit().frame(maxWidth: .infinity, alignment: .leading)
            if let second {
                Text(second.title).foregroundStyle(.secondary)
                Text(value(second)).monospacedDigit()
                    .background(GeometryReader { Color.clear.preference(key: ValuesRightEdge.self, value: $0.frame(in: .named("details")).maxX) })
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
        .lineLimit(1)
    }
}


/// 詳細資訊裡的「充電器規格」一段：充電器的規格與實際輸入集中在這裡，不在面板其他地方重複
private struct ValuesRightEdge: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// 寬度用指定值（對齊上方表格），但不小於內容需要的寬度、也不超過可用寬度，免得窄的時候疊字
private struct AlignedWidth: ViewModifier {
    let width: CGFloat?
    func body(content: Content) -> some View { AtLeastIdeal(width: width) { content } }
}

private struct AtLeastIdeal: Layout {
    let width: CGFloat?
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(.unspecified).width
        let available = proposal.width ?? ideal
        let w = min(max(width ?? available, ideal), available)
        return CGSize(width: w, height: child.sizeThatFits(ProposedViewSize(width: w, height: nil)).height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

private struct ChargerSection: View {
    let s: BatterySnapshot
    /// 有值時整段寬度只到這裡（對齊上方表格右欄的文字），沒有時撐滿
    var rightEdge: CGFloat?

    private var adapter: AdapterInfo? { s.adapter }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle("充電器規格", systemImage: "powerplug.fill")
            let limit = adapter?.watts.map { "\($0) W" }
            let groups = adapter?.levelGroups ?? []
            // 左邊：名稱與兩欄數值；右邊：支援檔位從最上面排下來，兩邊底部對齊，不用分隔線
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        ConnectorIcon(connection: adapter?.connection, charging: s.isCharging)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(adapter?.name ?? "Third-Party Charger")
                                .font(.callout.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            if !identity.isEmpty {
                                Text(identity.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).fixedSize()
                            }
                        }
                    }
                    if limit != nil || adapter?.specification != nil || input != nil {
                        // 兩段空隙一樣寬：兩欄之間、即時輸入與支援檔位之間
                        HStack(alignment: .top, spacing: 0) {
                            if limit != nil || adapter?.specification != nil {
                                column("規格上限", limit, [adapter?.specification].compactMap { $0 })
                                Spacer(minLength: 16)
                            }
                            if input != nil {
                                column("即時輸入", inputWatts.map { Format.watts($0) }, [input].compactMap { $0 })
                                Spacer(minLength: 16)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // 一個規格一行（不在規格中間換行），在左邊的高度內分布，檔位夠多時上下都對齊
                if !groups.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("支援檔位").font(.caption).foregroundStyle(.secondary)
                        ForEach(groups, id: \.self) { group in
                            Spacer(minLength: 2).frame(maxHeight: 12)  // 檔位少時不拉開，從上面緊湊排
                            Text(group).font(.caption).monospacedDigit().fixedSize()
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .modifier(AlignedWidth(width: rightEdge))
        }
    }

    /// 名稱下方一行：製造商、連接方式
    private var identity: [String] {
        [adapter?.manufacturer, adapter?.connection].compactMap { $0 }
    }

    /// 只有電壓、電流都是 SMC 同一次量測時才相乘，避免混用不同來源
    private var inputWatts: Double? {
        guard let volts = s.smcAdapterVolts, let amps = s.smcAdapterAmps else { return nil }
        return volts * amps
    }

    /// 一欄：小標題、主要數值（瓦數）、其下的細項
    private func column(_ title: String, _ main: String?, _ details: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let main { Text(main).font(.title2.weight(.semibold)) }
            ForEach(details, id: \.self) {
                Text($0).font(main == nil ? .caption : .subheadline).foregroundStyle(main == nil ? .primary : .secondary).fixedSize()
            }
        }
        .monospacedDigit()
        .fixedSize()
    }

    /// SMC 即時量測的輸入電壓與電流（和詳細資訊的變壓器電壓／電流同一來源）
    private var input: String? {
        let volts = s.smcAdapterVolts.map { String(format: "%.2f V", $0) }
        let milliamps = s.smcAdapterAmps.map { Int(($0 * 1000).rounded()) } ?? s.systemCurrentIn_mA
        let parts = [volts, milliamps.map { "\($0.formatted()) mA" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

}

/// 充電器名稱左邊的連接埠圖示，大小與顏色同周邊裝置列表的 SF Symbol。
/// USB-C 用系統的 cable.connector；SF Symbols 沒有 MagSafe，照 cable.connector 的層次自己畫（正面看的 MagSafe 3）
private struct ConnectorIcon: View {
    let connection: String?
    let charging: Bool

    var body: some View {
        Group {
            if connection?.localizedCaseInsensitiveContains("MagSafe") == true {
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 0.8).frame(width: 12, height: 2.6).opacity(0.5)
                    ZStack {
                        RoundedRectangle(cornerRadius: 2.2).frame(width: 16, height: 9)
                        // 和實體 MagSafe 一樣：充電中橘燈、沒在充電綠燈
                        Circle().fill(charging ? Color.orange : Color.green).frame(width: 2.6, height: 2.6)
                    }
                    RoundedRectangle(cornerRadius: 0.5).frame(width: 2, height: 5.5)
                }
            } else {
                Image(systemName: connection == "USB-C" ? "cable.connector" : "powerplug.fill")
            }
        }
        .font(.system(size: 17))
        .frame(width: 24, height: 20)
        .foregroundStyle(.secondary)
        .accessibilityLabel(connection ?? "充電器")
    }
}
