import SwiftUI

/// 省電模式的電力流向：變壓器 → 系統 ⇄ 電池，只有圖示與箭頭，不跑動畫
struct StaticPowerFlowView: View {
    let s: BatterySnapshot
    let e: Estimates

    var body: some View {
        HStack(spacing: 0) {
            node(symbol: "powerplug.fill", title: "變壓器", value: adapterText, active: s.externalConnected, tint: .yellow)
            arrow(pointingRight: true, active: s.externalConnected)
            node(symbol: "laptopcomputer", title: "系統耗電", value: Format.watts(e.systemWatts), active: true, tint: .blue)
            arrow(pointingRight: batteryCharging, active: batteryActive)
            node(symbol: batterySymbol, title: batteryTitle, value: Format.watts(batteryValue), active: batteryActive,
                 tint: batteryCharging ? .green : .orange)
        }
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
    }

    private var batteryActive: Bool { e.flowKind != .adapter }
    private var batteryCharging: Bool { e.flowKind == .charging }
    /// 與動畫流向圖相同：沿箭頭方向為正值；方向確認中的短暫反向才會出現負號
    private var batteryValue: Double {
        switch e.flowKind {
        case .mixed, .battery: return -e.batteryWatts
        case .charging, .adapter: return e.batteryWatts
        }
    }
    private var batteryTitle: String {
        guard batteryActive else { return "電池閒置" }
        return batteryCharging ? "充入電池" : "電池放電"
    }

    private var adapterText: String {
        guard s.externalConnected else { return "未連接" }
        if let input = e.adapterInputWatts { return Format.watts(input) }
        if let rated = s.adapter?.watts { return "\(rated) W 額定" }
        return "已連接"
    }

    private var batterySymbol: String {
        if batteryCharging { return SymbolCompat.name("battery.100percent.bolt") }
        switch s.percent {
        case 88...: return SymbolCompat.name("battery.100percent")
        case 63..<88: return SymbolCompat.name("battery.75percent")
        case 38..<63: return SymbolCompat.name("battery.50percent")
        case 13..<38: return SymbolCompat.name("battery.25percent")
        default: return SymbolCompat.name("battery.0percent")
        }
    }

    private func node(symbol: String, title: String, value: String, active: Bool, tint: Color) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(tint.opacity(active ? 0.18 : 0.06))
                    .frame(width: 40, height: 40)
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(active ? tint : Color.secondary)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(active ? Color.primary : Color.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func arrow(pointingRight: Bool, active: Bool) -> some View {
        Image(systemName: pointingRight ? "chevron.right.2" : "chevron.left.2")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(active ? Color.accentColor : Color.secondary.opacity(0.3))
            .offset(y: -16)
    }
}
