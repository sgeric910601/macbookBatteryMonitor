import SwiftUI

/// 桌上型 Mac（沒有電池）的主面板：整機耗電、硬體細項、耗電歷史、耗電排行與周邊設備
struct DesktopPanelView: View {
    @ObservedObject var store: BatteryStore
    let desktop: DesktopPower
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: PanelState

    /// 面板開著時，標題、詳細資訊與耗電細項都用同一次硬體取樣的整機耗電，數字才會對得起來
    private var current: DesktopPower {
        var value = desktop
        if let watts = store.breakdown.systemWatts { value.systemWatts = watts }
        return value
    }

    var body: some View {
        let desktop = current
        VStack(spacing: 10) {
            DesktopHeaderView(desktop: desktop)
            DesktopPowerSection(breakdown: store.breakdown, ui: ui, powerSaving: settings.powerSavingActive,
                                hasBuiltInDisplay: desktop.hasBuiltInDisplay)
            Picker("", selection: ui.binding(\.tab)) {
                ForEach(BottomTab.allCases, id: \.self) { Text($0.title(desktop: true)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Group {
                switch ui.tab {
                case .details: DesktopDetailsView(desktop: desktop, breakdown: store.breakdown)
                case .history: HistoryChartView(history: store.history, ui: ui, desktop: true)
                case .processes: TopProcessesView(store: store)
                case .peripherals: PeripheralsView(store: store.peripherals, settings: settings)
                }
            }
            .frame(height: 231, alignment: .top)
        }
    }
}

private struct DesktopHeaderView: View {
    let desktop: DesktopPower

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
                .frame(width: 62, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(desktop.systemWatts.map { String(format: "%.1f W", $0) } ?? "—")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Label("系統耗電", systemImage: "powerplug")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("近 3 分鐘平均")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Format.watts(desktop.averageWatts))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }
}

/// 沒有電池就沒有變壓器與電池的流向，直接從系統細項開始；點晶片運算再展開 CPU／GPU／ANE
private struct DesktopPowerSection: View {
    let breakdown: PowerBreakdown
    @ObservedObject var ui: PanelState
    let powerSaving: Bool
    let hasBuiltInDisplay: Bool

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                if ui.powerFlowLevel == .chip {
                    Button {
                        ui.powerFlowLevel = .components
                    } label: {
                        Label("系統細項", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("耗電細項").foregroundStyle(.secondary)
                }
                Spacer()
                Text(AppSettings.shared.updateText).foregroundStyle(.secondary)
            }
            .font(.caption)
            ComponentPowerFlowView(breakdown: breakdown, ui: ui, animated: !powerSaving, desktopWithDisplay: hasBuiltInDisplay)
        }
    }
}

private struct DesktopDetailsView: View {
    let desktop: DesktopPower
    let breakdown: PowerBreakdown

    var body: some View {
        Card(expand: true) {
            PairRows(pairs: rows.map { PairRows.Pair(label: $0.0, value: $0.1) })
                .font(.callout)
        }
    }

    private var rows: [(String, String)] {
        var rows: [(String, String)] = [
            ("系統耗電", Format.watts(desktop.systemWatts)),
            ("近 3 分鐘", Format.watts(desktop.averageWatts)),
            ("CPU 功耗", Format.watts(breakdown.cpuWatts)),
            ("GPU 功耗", Format.watts(breakdown.gpuWatts)),
        ]
        if breakdown.aneAvailable { rows.append(("ANE 功耗", Format.watts(breakdown.aneWatts))) }
        rows += [
            ("晶片運算", Format.watts(breakdown.chipWatts)),
            ("其他", Format.watts(breakdown.otherWatts)),
            ("低耗電模式", desktop.lowPowerMode ? "開啟" : "關閉"),
            ("已開機", uptimeText),
            ("處理器", desktop.processor),
            ("機型", desktop.model),
        ]
        return rows
    }

    private var uptimeText: String {
        let minutes = Int(desktop.uptime / 60)
        guard minutes >= 24 * 60 else { return Format.duration(minutes) }
        return "\(minutes / (24 * 60)) 天 \(minutes % (24 * 60) / 60) 小時"
    }

}
