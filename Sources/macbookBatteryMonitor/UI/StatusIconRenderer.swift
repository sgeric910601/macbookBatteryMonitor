import AppKit

/// 畫選單列的電池圖示。用 drawingHandler 延後繪製，
/// labelColor 會在實際畫到選單列時才依深色/淺色外觀決定顏色。
enum StatusIconRenderer {
    static func image(percent: Int, state: PowerState, low: Bool, showsPercent: Bool = false,
                      chargingColor: NSColor = .systemGreen, chargingTextColor: NSColor = .white) -> NSImage {
        // 座標都以 26×13（內嵌百分比 36×15）設計，整張圖等比例放大 sizeScale 倍
        let base = NSSize(width: showsPercent ? 36 : 26, height: showsPercent ? 15 : 13)
        let image = NSImage(size: NSSize(width: base.width * sizeScale, height: base.height * sizeScale), flipped: false) { _ in
            let transform = NSAffineTransform()
            transform.scale(by: sizeScale)
            transform.concat()
            let charging = state == .charging
            // labelColor 在深色外觀只有約 85% 不透明，疊在綠色上偏灰；插頭改用純白（淺色外觀純黑），和 Mac 原生電池一致
            let plugColor: NSColor = NSAppearance.current.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
            let outlineColor = NSColor.labelColor.withAlphaComponent(0.5)
            let body = NSRect(x: 0.5, y: 0.5, width: showsPercent ? 32.5 : 22.5, height: showsPercent ? 14 : 12)
            let outline = NSBezierPath(roundedRect: body, xRadius: 3.5, yRadius: 3.5)
            outline.lineWidth = 1
            outlineColor.setStroke()
            outline.stroke()
            outlineColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: body.maxX + 0.75, y: body.midY - 2.5, width: 1.75, height: 5), xRadius: 0.8, yRadius: 0.8).fill()

            let inner = body.insetBy(dx: fillInset, dy: fillInset)
            let level = CGFloat(min(max(percent, 0), 100)) / 100
            let fill = NSRect(x: inner.minX, y: inner.minY, width: max(1.5, inner.width * level), height: inner.height)
            let color = fillColor(state: state, low: low)
            (charging ? chargingColor : showsPercent ? color.withAlphaComponent(0.22) : color).setFill()
            NSBezierPath(roundedRect: fill, xRadius: fillRadius, yRadius: fillRadius).fill()

            if showsPercent {
                let text = "\(min(max(percent, 0), 100))%" as NSString
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold),
                    .foregroundColor: charging ? chargingTextColor : NSColor.labelColor,
                ]
                if charging {
                    let shadow = NSShadow()
                    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
                    shadow.shadowBlurRadius = 1
                    shadow.shadowOffset = .zero
                    attributes[.shadow] = shadow
                }
                let size = text.size(withAttributes: attributes)
                text.draw(at: NSPoint(x: body.midX - size.width / 2, y: body.midY - size.height / 2),
                          withAttributes: attributes)
            } else if let name = overlaySymbol(state),
               let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil),
               let tinted = symbol.withSymbolConfiguration(
                   NSImage.SymbolConfiguration(pointSize: overlayPointSize, weight: .black)
                       .applying(.init(paletteColors: [charging ? chargingTextColor : plugColor]))
               ) {
                let s = tinted.size
                // 符號的圖形在自己的外框裡偏上下，所以量出實際圖形的中心再對齊電池中心
                let ink = inkCenter(symbol: name)
                // 實機像素量測：只用墨跡中心計算，插頭仍偏下約 0.6 個螢幕像素，所以往上補 0.25（插頭才和綠色區塊上下等距）
                let measuredBias: CGFloat = charging ? 0 : 0.25
                let rect = NSRect(x: body.midX - ink.x, y: body.midY - ink.y + measuredBias, width: s.width, height: s.height)
                // 插頭、閃電和綠色之間留一圈很細的空隙：先用符號的輪廓往四周挖掉綠色（透明），再畫符號。
                // 閃電用「充電圖示文字顏色」（預設白色），和內嵌百分比的文字同一個設定
                let gap: CGFloat = 0.4
                for (dx, dy) in [(-gap, 0), (gap, 0), (0, -gap), (0, gap), (-gap * 0.7, -gap * 0.7), (gap * 0.7, gap * 0.7), (-gap * 0.7, gap * 0.7), (gap * 0.7, -gap * 0.7)] {
                    tinted.draw(in: rect.offsetBy(dx: dx, dy: dy), from: .zero, operation: .destinationOut, fraction: 1)
                }
                tinted.draw(in: rect)
            }
            return true
        }
        image.accessibilityDescription = "電池 \(percent)%"
        return image
    }

    /// 整顆電池的放大倍數（等比例）：綠色區塊 9 點 × 1.2 = 10.8 點
    static let sizeScale: CGFloat = 1.2

    /// 綠色區塊離外框路徑的距離（外框線寬 1，所以和線的內緣隔 1.0）；
    /// 外框圓角 3.5、內緣半徑 3，綠色圓角取「3.5 − 距離」才會同心，四周間距一致
    static let fillInset: CGFloat = 1.5
    static var fillRadius: CGFloat { 3.5 - fillInset }

    private static let overlayPointSize: CGFloat = 8.5
    private static var inkCenters: [String: NSPoint] = [:]

    /// 符號實際有顏色的部分的中心（點，原點在左下）；用 8 倍點陣掃描 alpha，每個符號只量一次
    private static func inkCenter(symbol name: String) -> NSPoint {
        if let cached = inkCenters[name] { return cached }
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil),
              let image = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: overlayPointSize, weight: .black)
                  .applying(.init(paletteColors: [.black]))) else { return .zero }
        let fallback = NSPoint(x: image.size.width / 2, y: image.size.height / 2)
        let scale = 8
        let w = Int(image.size.width.rounded(.up)) * scale, h = Int(image.size.height.rounded(.up)) * scale
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return fallback }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h { for x in 0..<w where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= 0 else { return fallback }
        // 點陣的第 0 列在上方，轉成原點在左下的座標
        let center = NSPoint(x: CGFloat(minX + maxX + 1) / 2 / CGFloat(scale),
                             y: (CGFloat(h) - CGFloat(minY + maxY + 1) / 2) / CGFloat(scale))
        inkCenters[name] = center
        return center
    }

    private static func fillColor(state: PowerState, low: Bool) -> NSColor {
        if low { return .systemRed }
        switch state {
        case .charging, .full, .pluggedIdle, .limitReached: return .systemGreen
        case .discharging: return NSColor.labelColor.withAlphaComponent(0.9)
        }
    }

    private static func overlaySymbol(_ state: PowerState) -> String? {
        switch state {
        case .charging: return "bolt.fill"
        case .pluggedIdle, .full, .limitReached: return "powerplug.fill"
        case .discharging: return nil
        }
    }
}

/// 僅在已充電的綠色區域疊加流光，由 Core Animation 播放，不額外取樣電池。
@MainActor
final class ChargingIconFlowView: NSView {
    private let clip = CALayer()
    private let shine = CAGradientLayer()
    var percent = 0
    var inlinePercent = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        clip.masksToBounds = true
        shine.colors = [NSColor.white.withAlphaComponent(0).cgColor,
                        NSColor.white.withAlphaComponent(0.38).cgColor,
                        NSColor.white.withAlphaComponent(0).cgColor]
        shine.startPoint = CGPoint(x: 0, y: 0.5)
        shine.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(clip)
        clip.addSublayer(shine)
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard let button = superview as? NSStatusBarButton,
              let rect = button.cell?.imageRect(forBounds: button.bounds) else { return }
        let scaleX = rect.width / (inlinePercent ? 36 : 26)
        let scaleY = rect.height / (inlinePercent ? 15 : 13)
        let width = ((inlinePercent ? 32.5 : 22.5) - 2 * StatusIconRenderer.fillInset) * CGFloat(min(100, max(0, percent))) / 100
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let origin = 0.5 + StatusIconRenderer.fillInset
        clip.cornerRadius = StatusIconRenderer.fillRadius * scaleY
        clip.frame = CGRect(x: rect.minX + origin * scaleX, y: rect.minY + origin * scaleY,
                            width: max(1.5, width) * scaleX,
                            height: ((inlinePercent ? 14 : 12) - 2 * StatusIconRenderer.fillInset) * scaleY)
        shine.frame = CGRect(x: -12, y: 0, width: 12, height: clip.bounds.height)
        CATransaction.commit()
        if shine.animation(forKey: "flow") == nil {
            let flow = CABasicAnimation(keyPath: "transform.translation.x")
            flow.fromValue = 0
            flow.toValue = 48
            flow.duration = 1.6
            flow.repeatCount = .infinity
            shine.add(flow, forKey: "flow")
        }
    }
}
