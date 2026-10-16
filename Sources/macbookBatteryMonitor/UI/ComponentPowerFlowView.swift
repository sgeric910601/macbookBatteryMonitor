import SwiftUI

struct ComponentPowerFlowView: View {
    let breakdown: PowerBreakdown
    @ObservedObject var ui: PanelState
    /// 省電模式關掉流動動畫
    var animated = true
    /// 桌上型 Mac 的面板：來源畫成桌機；值是有沒有內建螢幕（iMac 有，Mac mini 沒有），沒有時「其他」不含螢幕
    var desktopWithDisplay: Bool? = nil
    private var desktop: Bool { desktopWithDisplay != nil }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private var chip: Bool { ui.powerFlowLevel == .chip }
    @ObservedObject private var settings = AppSettings.shared
    /// 依設定隱藏的項目不顯示；沒有 ANE 通道的機型直接拿掉 ANE
    private var rows: [ComponentRow] {
        let all: [ComponentRow] = chip ? [
            ComponentRow(item: .cpu, name: "CPU", symbol: "cpu", watts: breakdown.cpuWatts),
            ComponentRow(item: .gpu, name: "GPU", symbol: "square.stack.3d.up", watts: breakdown.gpuWatts),
            ComponentRow(item: .ane, name: "ANE", symbol: "brain", watts: breakdown.aneWatts),
        ] : [
            ComponentRow(item: .backlight, name: "螢幕背光", symbol: "display", watts: breakdown.backlightWatts),
            ComponentRow(item: .chip, name: "晶片運算", symbol: "cpu", watts: breakdown.chipWatts),
            ComponentRow(item: .other, name: otherName, symbol: "ellipsis", watts: breakdown.otherWatts),
        ]
        return all.filter { available($0.item) && settings.isVisible($0.item) }
    }
    /// 這台機器讀不到的項目（沒有 ANE 通道、沒有背光感測器）直接不顯示
    private func available(_ item: FlowItem) -> Bool {
        switch item {
        case .ane: return breakdown.aneAvailable
        case .backlight: return breakdown.backlightAvailable
        default: return true
        }
    }
    private var otherName: String {
        if breakdown.otherIncludesMissing { return "未分類（估算）" }
        if breakdown.backlightAvailable { return "其他（估算）" }
        // 沒有背光感測器：MacBook、iMac 的螢幕算在其他裡；Mac mini 這類沒有內建螢幕的桌上型 Mac 就只是其他
        return desktopWithDisplay ?? true ? "其他（含螢幕）" : "其他（估算）"
    }
    private var chipComplete: Bool {
        breakdown.cpuWatts != nil && breakdown.gpuWatts != nil && (breakdown.aneWatts != nil || !breakdown.aneAvailable)
    }
    private var chipItemsText: String { breakdown.aneAvailable ? "CPU、GPU 與 ANE" : "CPU 與 GPU" }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                VStack(spacing: 5) {
                    Image(systemName: chip ? "cpu" : (desktop ? "desktopcomputer" : "laptopcomputer")).font(.system(size: 21))
                    Text(Format.watts(chip ? breakdown.chipWatts : breakdown.systemWatts))
                        .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    Text(chip ? (chipComplete ? "晶片合計" : "已取得合計") : "系統負載").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .frame(width: 58, height: 92)
                .background(Color.primary.opacity(0.055), in: SideRoundedRectangle(leading: 13))
                ComponentRibbons(values: rows.map(\.watts), total: chip ? breakdown.chipWatts : breakdown.systemWatts,
                                 animated: animated && !reduceMotion, dark: scheme == .dark)
                    .frame(maxWidth: .infinity).frame(height: 126)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    if rows.isEmpty {
                        Button { ui.openSettings(.display) } label: {
                            Text("項目都已隱藏\n點這裡到設定調整")
                                .font(.system(size: 9)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .buttonStyle(.plain)
                        .help("打開設定 → 顯示項目")
                    }
                    ForEach(rows, id: \.item) { row in
                        if row.item == .chip {
                            Button { ui.powerFlowLevel = .chip } label: {
                                endpoint(row, expandable: true)
                            }
                            .buttonStyle(.plain)
                            .help("展開 \(chipItemsText) 功耗")
                            .accessibilityLabel("晶片運算，\(Format.watts(row.watts))，展開細項")
                        } else {
                            endpoint(row, expandable: false)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(row.name)，\(Format.watts(row.watts))")
                        }
                    }
                }
                .frame(width: 72)
            }
            Text(breakdown.message)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("總功耗與背光來自感測器，\(chipItemsText)為系統估算；「其他」是差值，只是近似值。")
        }
    }

    private func endpoint(_ row: ComponentRow, expandable: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: row.symbol).font(.system(size: 14))
            HStack(spacing: 2) {
                Text(row.name).font(.system(size: 9))
                if expandable { Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)) }
            }
        }
        .frame(maxWidth: .infinity).frame(height: 38)
        .background(Color.primary.opacity(expandable ? 0.085 : 0.055),
                    in: SideRoundedRectangle(trailing: 11))
    }
}

private struct ComponentRow {
    var item: FlowItem
    var name: String
    var symbol: String
    var watts: Double?
}

private struct ComponentRibbons: NSViewRepresentable {
    let values: [Double?]
    let total: Double?
    let animated: Bool
    let dark: Bool
    func makeNSView(context: Context) -> ComponentRibbonView { ComponentRibbonView() }
    func updateNSView(_ view: ComponentRibbonView, context: Context) {
        let config = ComponentRibbonView.Configuration(values: values, total: total, animated: animated, dark: dark)
        if view.configuration != config { view.configuration = config; view.needsLayout = true }
    }
}

private final class ComponentRibbonView: NSView {
    struct Configuration: Equatable {
        var values: [Double?]
        var total: Double?
        var animated: Bool
        var dark: Bool
    }
    var configuration: Configuration?
    private let flows = PowerFlowLayers()
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        guard let layer, let c = configuration, bounds.width > 8 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayers?.filter { !(($0.name ?? "").hasPrefix("flow-")) }.forEach { $0.removeFromSuperlayer() }
        flows.begin(in: layer)
        // Match the source card (92 pt) and destination cards (38 pt).
        // Only measured positive branches participate in the source split.
        let active = c.values.map { $0.map { $0.isFinite && $0 > 0 } ?? false }
        let count = active.filter { $0 }.count
        let sourceWidth: CGFloat = count > 0 ? 92 / CGFloat(count) : 0
        var source: CGFloat = (bounds.height - 92) / 2
        // 右側卡片（高 38、間距 6）垂直置中；項目被隱藏時卡片變少，流帶終點跟著卡片位置
        let top = max(0, (bounds.height - (CGFloat(c.values.count) * 44 - 6)) / 2)
        let start: CGFloat = 4
        let end = bounds.width - 4
        let ink = c.dark ? NSColor(white: 0.95, alpha: 1) : NSColor(white: 0.24, alpha: 1)
        for index in c.values.indices {
            let center = top + CGFloat(index) * 44 + 19
            let width: CGFloat = 38
            if active[index] {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: start, y: source))
                path.addCurve(to: CGPoint(x: end, y: center - width / 2),
                              control1: CGPoint(x: bounds.width / 2, y: source),
                              control2: CGPoint(x: bounds.width / 2, y: center - width / 2))
                path.addLine(to: CGPoint(x: end, y: center + width / 2))
                path.addCurve(to: CGPoint(x: start, y: source + sourceWidth),
                              control1: CGPoint(x: bounds.width / 2, y: center + width / 2),
                              control2: CGPoint(x: bounds.width / 2, y: source + sourceWidth))
                path.closeSubpath()
                let base = CAShapeLayer()
                base.path = path
                base.fillColor = (c.dark ? NSColor.white : NSColor.black).withAlphaComponent(0.065).cgColor
                layer.addSublayer(base)
                flows.update(id: "flow-\(index)", path: path, bounds: bounds, animated: c.animated,
                             dark: c.dark, startX: start, endX: end)
                source += sourceWidth
            }
            let label = CATextLayer()
            label.contentsScale = window?.backingScaleFactor ?? 2
            label.frame = CGRect(x: 4, y: center - 8, width: bounds.width - 8, height: 20)
            label.alignmentMode = .center
            label.string = NSAttributedString(string: Format.watts(c.values[index]), attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold), .foregroundColor: ink])
            layer.addSublayer(label)
        }
        flows.end()
        CATransaction.commit()
    }
}
