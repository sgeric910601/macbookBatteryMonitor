import AppKit
import SwiftUI

/// macOS 12 沒有 Grid（macOS 13 起才有），這裡用固定欄寬的 HStack／VStack 排出相同的表格

/// 文字在指定字型樣式下的最大寬度，用來決定標籤欄寬
enum TextWidth {
    static func max(_ texts: [String], style: NSFont.TextStyle = .callout) -> CGFloat {
        let font = NSFont.preferredFont(forTextStyle: style)
        let widths = texts.map { ($0 as NSString).size(withAttributes: [.font: font]).width }
        return ceil(widths.max() ?? 0)
    }
}

/// 「標籤 數值 標籤 數值」兩組一列：標籤欄寬依該欄最長的標籤，兩個數值欄平分剩下的寬度
struct PairRows: View {
    struct Pair: Hashable {
        var label: String
        var value: String
    }

    let pairs: [Pair]
    var spacing: CGFloat = 10
    var rowSpacing: CGFloat = 9

    var body: some View {
        let left = stride(from: 0, to: pairs.count, by: 2).map { pairs[$0].label }
        let right = stride(from: 1, to: pairs.count, by: 2).map { pairs[$0].label }
        let leftWidth = TextWidth.max(left)
        let rightWidth = TextWidth.max(right)
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(Array(stride(from: 0, to: pairs.count, by: 2)), id: \.self) { index in
                HStack(spacing: spacing) {
                    cell(pairs[index], labelWidth: leftWidth)
                    if index + 1 < pairs.count {
                        cell(pairs[index + 1], labelWidth: rightWidth)
                    } else {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
    }

    private func cell(_ pair: Pair, labelWidth: CGFloat) -> some View {
        HStack(spacing: spacing) {
            Text(pair.label).foregroundStyle(.secondary).frame(width: labelWidth, alignment: .leading)
            Text(pair.value).monospacedDigit().minimumScaleFactor(0.7).frame(maxWidth: .infinity, alignment: .leading)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 兩欄等寬的一列（開關、勾選框）
struct TwoColumns<Left: View, Right: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    var body: some View {
        HStack(spacing: spacing) {
            left.frame(maxWidth: .infinity, alignment: .leading)
            right.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// macOS 12 沒有 UnevenRoundedRectangle：只有左側或右側兩個角是圓角的矩形
struct SideRoundedRectangle: Shape {
    var leading: CGFloat = 0
    var trailing: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + leading, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - trailing, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: trailing)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: trailing)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: leading)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: leading)
        path.closeSubpath()
        return path
    }
}
