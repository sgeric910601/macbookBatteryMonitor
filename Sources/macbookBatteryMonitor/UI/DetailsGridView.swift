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

    var body: some View {
        Card(expand: true) {
            // 只顯示設定裡勾選的欄位，依序每列兩欄
            let fields = DetailField.available(limitSlider: limitSlider).filter { settings.isVisible($0) }
            if fields.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("所有欄位都已隱藏。")
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
            if s.externalConnected {
                Divider().padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text("充電器資訊").font(.callout.weight(.semibold))
                    adapterRow("名稱", s.adapter?.name ?? "系統未提供")
                    if let maker = s.adapter?.manufacturer { adapterRow("製造商", maker) }
                    if let model = s.adapter?.model { adapterRow("型號", model) }
                    if let watts = s.adapter?.watts { adapterRow("協商供電能力", "\(watts) W") }
                    if let spec = s.adapter?.specification { adapterRow("協商規格", spec) }
                    adapterRow("連接方式", s.adapter?.connection ?? "無法確認")
                }
                .font(.caption)
            }

        }
    }

    private func adapterRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
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
            // 與右上角相同的目標：有充電上限時是充到上限，否則是充滿
            if let limit = s.chargeLimit?.limit {
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
                Text(value(second)).monospacedDigit().frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
        .lineLimit(1)
    }
}
