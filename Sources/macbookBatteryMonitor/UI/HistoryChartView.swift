import SwiftUI

struct HistoryChartView: View {
    @ObservedObject var history: HistoryStore
    @ObservedObject var ui: PanelState
    /// 桌上型 Mac：沒有電量，只畫耗電
    var desktop = false

    private var range: HistoryRange { ui.historyRange }

    var body: some View {
        let now = Date()
        let points = history.points(range: range.seconds, now: now)
        let domain = now.addingTimeInterval(-range.seconds)...now
        let wattPoints = points.filter { $0.watts != nil }

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
                    wattsChart(wattPoints, domain: domain, showsTime: true)
                        .frame(height: 150)
                    Text(desktopSummary(wattPoints))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if points.count < 2 {
                collecting
            } else {
                // macOS 12 沒有 Swift Charts：用 Canvas 畫，用電池時藍色、接電時綠色
                PlotView(series: [PlotSeries(points: points.map {
                            PlotPoint(x: $0.t.timeIntervalSinceReferenceDate, y: $0.pct, segment: $0.segment,
                                      color: $0.plugged ? .green : .blue)
                         }, lineWidth: 2)],
                         xDomain: plotDomain(domain), yDomain: 0...100, yTicks: [0, 50, 100],
                         yLabel: { "\(Int($0))%" }, yAxis: .leading,
                         xTicks: axisDates(domain).map(\.timeIntervalSinceReferenceDate), xLabel: timeLabel)
                    .padding(.trailing, 10)
                    .frame(height: wattPoints.isEmpty ? 140 : 100)

                if !wattPoints.isEmpty {
                    wattsChart(wattPoints, domain: domain, showsTime: false)
                        .frame(height: 42)
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
    private func wattsChart(_ points: [ChartPoint], domain: ClosedRange<Date>, showsTime: Bool) -> some View {
        let top = ByteFormat.niceAxisMax(points.compactMap(\.watts).max() ?? 0, minimum: 5)
        let ticks: [Double] = showsTime ? [0, top / 2, top] : [0, top]
        return PlotView(series: [PlotSeries(points: points.map {
                            PlotPoint(x: $0.t.timeIntervalSinceReferenceDate, y: $0.watts ?? 0, segment: $0.wattsSegment, color: .orange)
                        }, lineWidth: nil, fillOpacity: 0.45)],
                        xDomain: plotDomain(domain), yDomain: 0...top, yTicks: ticks,
                        yLabel: { "\(Int($0))W" }, yAxis: .leading,
                        xTicks: showsTime ? axisDates(domain).map(\.timeIntervalSinceReferenceDate) : [],
                        xLabel: showsTime ? timeLabel : nil)
            .padding(.trailing, 10)
    }

    private func plotDomain(_ domain: ClosedRange<Date>) -> ClosedRange<Double> {
        domain.lowerBound.timeIntervalSinceReferenceDate...domain.upperBound.timeIntervalSinceReferenceDate
    }

    private func timeLabel(_ x: Double) -> String {
        Date(timeIntervalSinceReferenceDate: x).formatted(xFormat)
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
        return "平均耗電 \(Format.watts(watts.reduce(0, +) / Double(watts.count))) · " + range
    }
}
