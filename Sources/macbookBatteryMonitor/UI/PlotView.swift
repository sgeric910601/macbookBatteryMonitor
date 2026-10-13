import SwiftUI

/// macOS 12 沒有 Swift Charts（macOS 13 起），電量歷史、耗電歷史與系統監控的曲線改用 Canvas 自己畫。
/// 支援折線、面積、依 segment 斷開與分色、水平格線與刻度標籤
struct PlotPoint {
    var x: Double
    var y: Double
    /// 不同 segment 的點不會連線
    var segment: Int = 0
    /// 這一段的顏色（取每段第一個點）
    var color: Color
}

struct PlotSeries {
    var points: [PlotPoint]
    /// 線寬；nil 表示不畫線（只畫面積）
    var lineWidth: CGFloat? = 1.5
    /// 線下方填色的不透明度；nil 表示不填
    var fillOpacity: Double? = nil
}

struct PlotView: View {
    enum AxisSide { case leading, trailing, hidden }

    var series: [PlotSeries]
    var xDomain: ClosedRange<Double>
    var yDomain: ClosedRange<Double>
    var yTicks: [Double] = []
    var yLabel: (Double) -> String = { _ in "" }
    var yAxis: AxisSide = .leading
    var xTicks: [Double] = []
    var xLabel: ((Double) -> String)? = nil
    var labelWidth: CGFloat = 34

    var body: some View {
        Canvas { context, size in
            let left = yAxis == .leading ? labelWidth : 0
            let right = yAxis == .trailing ? labelWidth : 0
            let bottom: CGFloat = xLabel == nil ? 0 : 16
            let plot = CGRect(x: left, y: 5, width: max(1, size.width - left - right), height: max(1, size.height - bottom - 10))
            let xSpan = max(1e-9, xDomain.upperBound - xDomain.lowerBound)
            let ySpan = max(1e-9, yDomain.upperBound - yDomain.lowerBound)
            func px(_ x: Double) -> CGFloat { plot.minX + CGFloat((x - xDomain.lowerBound) / xSpan) * plot.width }
            func py(_ y: Double) -> CGFloat {
                plot.maxY - CGFloat((min(max(y, yDomain.lowerBound), yDomain.upperBound) - yDomain.lowerBound) / ySpan) * plot.height
            }

            for tick in yTicks {
                var line = Path()
                line.move(to: CGPoint(x: plot.minX, y: py(tick)))
                line.addLine(to: CGPoint(x: plot.maxX, y: py(tick)))
                context.stroke(line, with: .color(.primary.opacity(0.12)), lineWidth: 0.5)
                let text = Text(yLabel(tick)).font(.system(size: 9)).foregroundColor(.secondary)
                switch yAxis {
                case .leading: context.draw(text, at: CGPoint(x: plot.minX - 4, y: py(tick)), anchor: .trailing)
                case .trailing: context.draw(text, at: CGPoint(x: plot.maxX + 4, y: py(tick)), anchor: .leading)
                case .hidden: break
                }
            }
            for tick in xTicks where xDomain.contains(tick) {
                var line = Path()
                line.move(to: CGPoint(x: px(tick), y: plot.minY))
                line.addLine(to: CGPoint(x: px(tick), y: plot.maxY))
                context.stroke(line, with: .color(.primary.opacity(0.12)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                if let xLabel {
                    context.draw(Text(xLabel(tick)).font(.system(size: 10)).foregroundColor(.secondary),
                                 at: CGPoint(x: px(tick), y: plot.maxY + 3), anchor: .top)
                }
            }

            for item in series {
                var segments: [[PlotPoint]] = []
                for point in item.points {
                    if let last = segments.last?.last, last.segment == point.segment {
                        segments[segments.count - 1].append(point)
                    } else {
                        segments.append([point])
                    }
                }
                for segment in segments {
                    guard let first = segment.first, let last = segment.last else { continue }
                    var line = Path()
                    line.move(to: CGPoint(x: px(first.x), y: py(first.y)))
                    for point in segment.dropFirst() { line.addLine(to: CGPoint(x: px(point.x), y: py(point.y))) }
                    if let opacity = item.fillOpacity, segment.count > 1 {
                        var area = line
                        area.addLine(to: CGPoint(x: px(last.x), y: plot.maxY))
                        area.addLine(to: CGPoint(x: px(first.x), y: plot.maxY))
                        area.closeSubpath()
                        context.fill(area, with: .linearGradient(
                            Gradient(colors: [first.color.opacity(opacity), first.color.opacity(opacity * 0.5)]),
                            startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))
                    }
                    if let width = item.lineWidth {
                        context.stroke(line, with: .color(first.color),
                                       style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                    }
                }
            }
        }
    }
}
