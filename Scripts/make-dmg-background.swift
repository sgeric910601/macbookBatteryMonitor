// 產生 DMG 視窗的背景圖：左邊 App、右邊「應用程式」之間畫箭頭，下方說明第一次打開被擋下時怎麼辦
//   swiftc -O Scripts/make-dmg-background.swift -o build/make-dmg-background && build/make-dmg-background
//   tiffutil -cathidpicheck build/dmg-background.png build/dmg-background@2x.png -out Resources/DMG/background.tiff
// 圖示位置寫在 Scripts/make-dmg.sh（App 在 140、應用程式在 400，高度 150，視窗內容 540×380）
import AppKit

let width: CGFloat = 540
let height: CGFloat = 380

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// 置中畫一段文字；y 是文字上緣（左上角為原點）
func text(_ string: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineSpacing = 3
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                      .foregroundColor: color, .paragraphStyle: paragraph]
    NSAttributedString(string: string, attributes: attributes).draw(in: NSRect(x: 20, y: y, width: width - 40, height: 80))
}

func render(scale: CGFloat, to path: String) {
    let pixelsWide = Int(width * scale), pixelsHigh = Int(height * scale)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("無法建立圖片") }
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    // 以左上角為原點
    let flip = NSAffineTransform()
    flip.translateX(by: 0, yBy: height)
    flip.scaleX(by: 1, yBy: -1)
    flip.concat()
    let flipped = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    NSGraphicsContext.current = flipped

    // 和 App 圖示一樣的薄荷綠，往下漸漸變白
    NSGradient(starting: rgb(0xDDF3EA), ending: rgb(0xFAFCFB))!.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)

    text("電池與系統監控", y: 26, size: 20, weight: .semibold, color: rgb(0x1F3A33))

    // 箭頭：App（中心 140）→ 應用程式（中心 400），避開兩邊 100 點的圖示
    let arrow = NSBezierPath()
    arrow.lineWidth = 6
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 214, y: 146))
    arrow.line(to: NSPoint(x: 322, y: 146))
    arrow.move(to: NSPoint(x: 304, y: 130))
    arrow.line(to: NSPoint(x: 324, y: 146))
    arrow.line(to: NSPoint(x: 304, y: 162))
    rgb(0x3F8F78, 0.85).setStroke()
    arrow.stroke()

    text("把 App 拖到「應用程式」", y: 250, size: 14, weight: .medium, color: rgb(0x1F3A33))

    // 沒有 Apple 開發者簽章：第一次打開會被擋下
    let note = NSRect(x: 40, y: 290, width: width - 80, height: 66)
    let box = NSBezierPath(roundedRect: note, xRadius: 10, yRadius: 10)
    rgb(0xFFFFFF, 0.75).setFill()
    box.fill()
    rgb(0x3F8F78, 0.25).setStroke()
    box.lineWidth = 1
    box.stroke()
    text("第一次打開被擋下時：\n系統設定 → 隱私權與安全性 → 按「強制打開」", y: note.minY + 12, size: 12, color: rgb(0x40524D))

    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("無法輸出 PNG") }
    try! data.write(to: URL(fileURLWithPath: path))
    print("已輸出 \(path)（\(pixelsWide)×\(pixelsHigh)）")
}

render(scale: 1, to: "build/dmg-background.png")
render(scale: 2, to: "build/dmg-background@2x.png")
