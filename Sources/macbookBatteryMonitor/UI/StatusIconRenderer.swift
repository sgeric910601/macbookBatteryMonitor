import AppKit

/// 畫選單列的電池圖示。用 drawingHandler 延後繪製，
/// labelColor 會在實際畫到選單列時才依深色/淺色外觀決定顏色。
enum StatusIconRenderer {
    static func image(percent: Int, state: PowerState, low: Bool, showsPercent: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: showsPercent ? 36 : 26, height: showsPercent ? 15 : 13), flipped: false) { _ in
            let charging = state == .charging
            let outlineColor = NSColor.labelColor.withAlphaComponent(0.5)
            let body = NSRect(x: 0.5, y: 0.5, width: showsPercent ? 32.5 : 22.5, height: showsPercent ? 14 : 12)
            let outline = NSBezierPath(roundedRect: body, xRadius: 3.5, yRadius: 3.5)
            outline.lineWidth = 1
            outlineColor.setStroke()
            outline.stroke()
            outlineColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: body.maxX + 0.75, y: body.midY - 2.5, width: 1.75, height: 5), xRadius: 0.8, yRadius: 0.8).fill()

            let inner = body.insetBy(dx: 2, dy: 2)
            let level = CGFloat(min(max(percent, 0), 100)) / 100
            let fill = NSRect(x: inner.minX, y: inner.minY, width: max(1.5, inner.width * level), height: inner.height)
            let color = fillColor(state: state, low: low)
            (charging ? NSColor.systemGreen : showsPercent ? color.withAlphaComponent(0.22) : color).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()

            if showsPercent {
                let text = "\(min(max(percent, 0), 100))%" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold),
                    .foregroundColor: NSColor.labelColor,
                ]
                let size = text.size(withAttributes: attributes)
                text.draw(at: NSPoint(x: body.midX - size.width / 2, y: body.midY - size.height / 2),
                          withAttributes: attributes)
                if charging {
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).addClip()
                    var filledAttributes = attributes
                    filledAttributes[.foregroundColor] = NSColor.black
                    text.draw(at: NSPoint(x: body.midX - size.width / 2, y: body.midY - size.height / 2),
                              withAttributes: filledAttributes)
                    NSGraphicsContext.restoreGraphicsState()
                }
            } else if let name = overlaySymbol(state),
               let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil),
               let tinted = symbol.withSymbolConfiguration(
                   NSImage.SymbolConfiguration(pointSize: 8.5, weight: .black)
                       .applying(.init(paletteColors: [charging ? NSColor.black : NSColor.labelColor]))
               ) {
                let s = tinted.size
                tinted.draw(in: NSRect(x: body.midX - s.width / 2, y: body.midY - s.height / 2, width: s.width, height: s.height))
            }
            return true
        }
        image.accessibilityDescription = "電池 \(percent)%"
        return image
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
        clip.cornerRadius = 1.5
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
        let width = (inlinePercent ? 28.5 : 18.5) * CGFloat(min(100, max(0, percent))) / 100
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clip.frame = CGRect(x: rect.minX + 2.5 * scaleX, y: rect.minY + 2.5 * scaleY,
                            width: max(1.5, width) * scaleX, height: (inlinePercent ? 10 : 8) * scaleY)
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
