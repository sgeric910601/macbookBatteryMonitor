import Charts
import SwiftUI

struct HistoryChartView: View {
    let history: HistoryStore
    let ui: PanelState
    /// 桌上型 Mac：沒有電量，只畫耗電
    var desktop = false

    private var range: HistoryRange { ui.historyRange }
    /// 滑鼠在圖上指到的時間；離開圖表時為 nil。兩張圖共用，垂直線同步
    @State private var hoverDate: Date?

    var body: some View {
        let now = Date()
        let points = history.points(range: range.seconds, now: now)
        let domain = now.addingTimeInterval(-range.seconds)...now
        let wattPoints = points.filter { $0.watts != nil }
        // 圖上最多 240 點，相鄰兩點約隔 range/240；離最近的點超過這個間隔（中間沒資料）就不顯示。
        // 至少 5 分鐘，因為從 pmset 補回的資料每 5 分鐘一筆
        let spacing = max(300, range.seconds / 240)
        let hovered = hoverDate.flatMap { ChartPoint.nearest(points, to: $0, maxGap: spacing) }

        Card(expand: true) {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("", selection: ui.binding(\.historyRange)) {
                    ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 190)
                Spacer()
                legend
            }

            if desktop {
                if wattPoints.count < 2 {
                    collecting
                } else {
                    wattsChart(wattPoints, domain: domain, showsTime: true, hovered: hovered)
                        .frame(minHeight: 150, maxHeight: .infinity)
                        .padding(.top, 16)
                    Text(desktopSummary(wattPoints))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if points.count < 2 {
                collecting
            } else {
                Chart {
                    ForEach(points) { p in
                        LineMark(
                            x: .value("時間", p.t),
                            y: .value("電量", p.pct),
                            series: .value("段", p.segment)
                        )
                        .foregroundStyle(p.plugged ? Color.green : Color.blue)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                    if let hovered {
                        crosshair(x: hovered.t, y: .value("電量", hovered.pct), color: hovered.plugged ? .green : .blue,
                                  label: hovered, labelBelow: hovered.pct > 60)
                    }
                }
                .chartXScale(domain: domain)
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) { Text("\(v)%") }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: axisDates(domain)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: xFormat)
                    }
                }
                .padding(.trailing, 10)
                .hoverTracking($hoverDate, step: range.seconds / 480)
                // 和上面的時間範圍按鈕拉開一點；卡片下方的空間給圖表用
                .padding(.top, 16)
                .frame(minHeight: wattPoints.isEmpty ? 140 : 100, maxHeight: .infinity)

                if !wattPoints.isEmpty {
                    wattsChart(wattPoints, domain: domain, showsTime: false, hovered: hovered)
                        .frame(height: 56)
                }

                Text(summary(points))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        }
    }

    private var collecting: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title2)
            Text("資料收集中，每分鐘記錄一次…")
                .font(.callout)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 耗電面積圖；桌上型 Mac 時是主圖，要顯示時間軸
    private func wattsChart(_ points: [ChartPoint], domain: ClosedRange<Date>, showsTime: Bool, hovered: ChartPoint?) -> some View {
        Chart {
            ForEach(points) { p in
                AreaMark(
                    x: .value("時間", p.t),
                    y: .value("功率", p.watts ?? 0),
                    series: .value("段", p.wattsSegment)
                )
                .foregroundStyle(Color.orange.opacity(0.35).gradient)
                .interpolationMethod(.monotone)
            }
            if let hovered {
                if let watts = hovered.watts {
                    // 桌上型只有這張圖，數值標在這裡
                    crosshair(x: hovered.t, y: .value("功率", watts), color: .orange, label: desktop ? hovered : nil, labelBelow: false)
                } else {
                    RuleMark(x: .value("時間", hovered.t))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
        }
        .chartXScale(domain: domain)
        .chartXAxis {
            if showsTime {
                AxisMarks(values: axisDates(domain)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: xFormat)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: showsTime ? 3 : 2)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text("\(Int(v))W") }
                }
            }
        }
        .padding(.trailing, 10)
        .hoverTracking($hoverDate, step: range.seconds / 480)
    }

    /// 十字準線：垂直線指出時間、水平線指出數值，交會處一個點
    @ChartContentBuilder
    private func crosshair(x: Date, y: PlottableValue<Double>, color: Color, label: ChartPoint?, labelBelow: Bool) -> some ChartContent {
        RuleMark(x: .value("時間", x))
            .foregroundStyle(Color.secondary.opacity(0.6))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        RuleMark(y: y)
            .foregroundStyle(Color.secondary.opacity(0.6))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        PointMark(x: .value("時間", x), y: y)
            .foregroundStyle(color)
            .symbolSize(36)
            // 標籤跟著交會點，靠邊時往內收、不超出圖表；點在上半部時放下面，才不會蓋住點
            .annotation(position: labelBelow ? .bottom : .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                if let label { hoverLabel(label) }
            }
    }

    /// 指到的那一點：時間、電量（桌上型沒有）與耗電
    private func hoverLabel(_ point: ChartPoint) -> some View {
        let time = point.t.formatted(range == .week ? .dateTime.month(.defaultDigits).day().hour().minute() : .dateTime.hour().minute())
        let parts = [time, desktop ? nil : "\(Int(point.pct.rounded()))%", point.watts.map { Format.watts($0) }].compactMap { $0 }
        return Text(parts.joined(separator: " · "))
            .font(.caption2.monospacedDigit())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.regularMaterial))
    }

    private var legend: some View {
        HStack(spacing: 8) {
            if !desktop {
                legendItem(.blue, "用電池")
                legendItem(.green, "接電源")
            }
            legendItem(.orange, "耗電")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
    }

    /// 對齊整點/整天的刻度，太靠近左右邊緣的不畫（標籤會被切掉）
    private func axisDates(_ domain: ClosedRange<Date>) -> [Date] {
        let calendar = Calendar.current
        let (component, step): (Calendar.Component, Int)
        let start: Date
        switch range {
        case .hour:
            (component, step) = (.minute, 15)
            start = calendar.dateInterval(of: .hour, for: domain.lowerBound)?.start ?? domain.lowerBound
        case .day:
            (component, step) = (.hour, 6)
            start = calendar.startOfDay(for: domain.lowerBound)
        case .week:
            (component, step) = (.day, 1)
            start = calendar.startOfDay(for: domain.lowerBound)
        }
        let margin = range.seconds * 0.07
        var dates: [Date] = []
        var date = start
        while date <= domain.upperBound {
            if date.timeIntervalSince(domain.lowerBound) > margin, domain.upperBound.timeIntervalSince(date) > margin {
                dates.append(date)
            }
            guard let next = calendar.date(byAdding: component, value: step, to: date) else { break }
            date = next
        }
        return dates
    }

    private var xFormat: Date.FormatStyle {
        range == .week ? .dateTime.month(.defaultDigits).day() : .dateTime.hour().minute()
    }

    private func desktopSummary(_ points: [ChartPoint]) -> String {
        let watts = points.compactMap(\.watts)
        let average = watts.reduce(0, +) / Double(max(1, watts.count))
        return "平均耗電 \(Format.watts(average)) · 最高 \(Format.watts(watts.max()))"
    }

    private func summary(_ points: [ChartPoint]) -> String {
        let watts = points.compactMap(\.watts)
        let minPct = Int(points.map(\.pct).min() ?? 0)
        let maxPct = Int(points.map(\.pct).max() ?? 0)
        let range = "電量範圍 \(minPct)%–\(maxPct)%"
        guard !watts.isEmpty else { return range + " · 耗電資料收集中" }
        return "平均耗電 \(Format.watts(watts.reduce(0, +) / Double(watts.count))) · 最高 \(Format.watts(watts.max())) · " + range
    }
}

private extension View {
    /// 滑鼠在圖表的繪圖區移動時，把指到的時間寫進 date；離開時清掉
    /// 移動不到 step 秒（約半個點的間隔）不更新，免得每個像素都重算整張圖
    func hoverTracking(_ date: Binding<Date?>, step: TimeInterval) -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard case .active(let location) = phase, let plot = proxy.plotFrame else {
                            date.wrappedValue = nil
                            return
                        }
                        let x = location.x - geometry[plot].origin.x
                        let value = (0...geometry[plot].width).contains(x) ? proxy.value(atX: x, as: Date.self) : nil
                        if let value, let old = date.wrappedValue, abs(value.timeIntervalSince(old)) < step { return }
                        date.wrappedValue = value
                    }
            }
        }
    }
}
