import AppKit

/// 畫選單列的電池圖示。用 drawingHandler 延後繪製，
/// labelColor 會在實際畫到選單列時才依深色/淺色外觀決定顏色。
enum StatusIconRenderer {
    static func image(percent: Int, state: PowerState, low: Bool, showsPercent: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: showsPercent ? 36 : 26, height: showsPercent ? 15 : 13), flipped: false) { _ in
            let charging = state == .charging
            let chargingGreen = NSColor(srgbRed: 0.02, green: 0.46, blue: 0.20, alpha: 1)
            let outlineColor = charging ? chargingGreen : NSColor.labelColor.withAlphaComponent(0.5)
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
            if charging && showsPercent {
                // 百分比跨越已充／未充區域，使用完整深綠底確保白字對比。
                chargingGreen.setFill()
                NSBezierPath(roundedRect: inner, xRadius: 1.5, yRadius: 1.5).fill()
            }
            (charging ? chargingGreen : showsPercent ? color.withAlphaComponent(0.22) : color).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()

            if showsPercent {
                let text = "\(min(max(percent, 0), 100))%" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold),
                    .foregroundColor: charging ? NSColor.white : NSColor.labelColor,
                ]
                let size = text.size(withAttributes: attributes)
                text.draw(at: NSPoint(x: body.midX - size.width / 2, y: body.midY - size.height / 2),
                          withAttributes: attributes)
            } else if let name = overlaySymbol(state),
               let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil),
               let tinted = symbol.withSymbolConfiguration(
                   NSImage.SymbolConfiguration(pointSize: 8.5, weight: .black)
                       .applying(.init(paletteColors: [charging ? NSColor.white : NSColor.labelColor]))
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
