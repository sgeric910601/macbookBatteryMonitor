import AppKit
import CoreImage
import ImageIO
import SwiftUI

/// 照片外觀的一隻眼睛：中心與半徑都是正規化座標（照片左上角為原點，邊長為 1）
struct CatEye: Equatable {
    var x: Double
    var y: Double
    var radius: Double

    /// 內建的貓咪照片量好的兩隻眼睛（會動的眼睛只給這張照片）
    static let bundled = [CatEye(x: 0.184, y: 0.479, radius: 0.061), CatEye(x: 0.572, y: 0.465, radius: 0.074)]
}

/// 眼睛的狀態：張開（跟著游標、會眨眼）、睡覺（閉著）
enum CatMood: Equatable {
    case awake, sleeping
}

/// 一隻眼睛要用的圖：從照片做出來一次，之後交給 Core Animation。座標都以眼睛中心為原點、半徑為單位
private struct CatEyeImages {
    /// 眼睛開口的柔邊遮罩（-1.16r～1.16r × -1.10r～1.10r）
    static let opening = CGRect(x: -1.16, y: -1.10, width: 2.32, height: 2.20)
    /// 虹膜（含瞳孔與反光），柔邊（-1.06r～1.06r）
    static let iris = CGRect(x: -1.06, y: -1.06, width: 2.12, height: 2.12)
    /// 眼皮蓋住的範圍（-1.3r～1.3r）
    static let cover = CGRect(x: -1.3, y: -1.3, width: 2.6, height: 2.6)

    let openingMask: CGImage
    let iris: CGImage
    let closed: CGImage

    init?(photo: CGImage, eye: CatEye) {
        let side = CGFloat(photo.width)
        let r = CGFloat(eye.radius) * side
        let center = CGPoint(x: CGFloat(eye.x) * side, y: CGFloat(eye.y) * side)
        // 每張圖用照片的解析度做（放大時由 Core Animation 縮放）
        func pixels(_ rect: CGRect) -> CGSize { CGSize(width: max(8, rect.width * r), height: max(8, rect.height * r)) }
        func crop(_ rect: CGRect) -> CGImage? {
            photo.cropping(to: CGRect(x: center.x + rect.minX * r, y: center.y + rect.minY * r, width: rect.width * r, height: rect.height * r))
        }
        guard let openingMask = Self.softMask(size: pixels(Self.opening), solid: 0.8),
              let irisCrop = crop(Self.iris),
              let iris = Self.masked(irisCrop, size: pixels(Self.iris), solid: 0.82),
              let band = crop(CGRect(x: -1.25, y: -1.5, width: 2.5, height: 0.42)),
              let closed = Self.lid(band, size: pixels(Self.cover)) else { return nil }
        self.openingMask = openingMask
        self.iris = iris
        self.closed = closed
    }

    private static func context(_ size: CGSize) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let ctx = CGContext(data: nil, width: Int(size.width.rounded()), height: Int(size.height.rounded()), bitsPerComponent: 8,
                            bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.interpolationQuality = .high
        return ctx
    }

    /// 橢圓形的柔邊漸層：中間到 solid 是滿的，之後漸漸變成 0
    private static func drawSoft(_ ctx: CGContext, size: CGSize, solid: CGFloat, full: CGColor, empty: CGColor, space: CGColorSpace) {
        guard let gradient = CGGradient(colorsSpace: space, colors: [full, full, empty] as CFArray, locations: [0, solid, 1]) else { return }
        ctx.saveGState()
        ctx.scaleBy(x: size.width / 2, y: size.height / 2)
        ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: 1, y: 1), startRadius: 0, endCenter: CGPoint(x: 1, y: 1), endRadius: 1, options: [])
        ctx.restoreGState()
    }

    /// 給 Core Animation 遮罩用：看透明度
    private static func softMask(size: CGSize, solid: CGFloat) -> CGImage? {
        guard let ctx = context(size), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        drawSoft(ctx, size: size, solid: solid, full: CGColor(gray: 0, alpha: 1), empty: CGColor(gray: 0, alpha: 0), space: space)
        return ctx.makeImage()
    }

    /// 給 CGContext 裁切用：灰階、沒有透明度，白色是顯示
    private static func clipMask(size: CGSize, solid: CGFloat) -> CGImage? {
        let gray = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: Int(size.width.rounded()), height: Int(size.height.rounded()), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        drawSoft(ctx, size: size, solid: solid, full: CGColor(gray: 1, alpha: 1), empty: CGColor(gray: 0, alpha: 1), space: gray)
        return ctx.makeImage()
    }

    /// 把一小條毛放大成整塊並柔化，蓋上去才不會看到一條條拉長的紋路
    private static func blurred(_ image: CGImage, to size: CGSize) -> CGImage? {
        guard let ctx = context(size) else { return nil }
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        guard let stretched = ctx.makeImage() else { return nil }
        let input = CIImage(cgImage: stretched).clampedToExtent()
        let output = input.applyingGaussianBlur(sigma: Double(min(size.width, size.height)) * 0.035)
            .cropped(to: CGRect(origin: .zero, size: size))
        return blurContext.createCGImage(output, from: CGRect(origin: .zero, size: size))
    }

    private static let blurContext = CIContext(options: [.useSoftwareRenderer: false])

    /// 照片的一塊加上柔邊
    private static func masked(_ image: CGImage, size: CGSize, solid: CGFloat) -> CGImage? {
        guard let ctx = context(size), let mask = clipMask(size: size, solid: solid) else { return nil }
        ctx.clip(to: CGRect(origin: .zero, size: size), mask: mask)
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }

    /// 眼皮：眼睛正上方那一條毛往下延伸、柔化後蓋住眼睛（柔邊），壓暗一點接上眼窩的顏色，
    /// 再畫一條往下彎的眼線
    private static func lid(_ band: CGImage, size: CGSize) -> CGImage? {
        guard let ctx = context(size), let mask = clipMask(size: size, solid: 0.62),
              let fur = blurred(band, to: size) else { return nil }
        ctx.saveGState()
        ctx.clip(to: CGRect(origin: .zero, size: size), mask: mask)
        ctx.draw(fur, in: CGRect(origin: .zero, size: size))
        // 整塊稍微壓暗，下半部（眼線附近）再暗一點，像眼皮的陰影
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.1))
        ctx.fill(CGRect(origin: .zero, size: size))
        let shade = [CGColor(gray: 0, alpha: 0.22), CGColor(gray: 0, alpha: 0)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: shade, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height * 0.2), end: CGPoint(x: 0, y: size.height * 0.6), options: [])
        }
        ctx.restoreGState()
        // 以下用眼睛座標（中心為原點、半徑為 1、y 往下）畫線
        let unit = size.width / cover.width
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.scaleBy(x: unit, y: -unit)
        ctx.setStrokeColor(CGColor(srgbRed: 0.13, green: 0.12, blue: 0.14, alpha: 0.85))
        ctx.setLineCap(.round)
        ctx.setLineWidth(0.11)
        ctx.move(to: CGPoint(x: -0.85, y: 0.65))
        ctx.addQuadCurve(to: CGPoint(x: 0.85, y: 0.65), control: CGPoint(x: 0, y: 0.95))
        ctx.strokePath()
        return ctx.makeImage()
    }
}

/// 照片上會動的眼睛：眼珠跟著游標、偶爾眨眼、睡覺時閉眼。
/// 只有眼睛那一小塊是 Core Animation 圖層，移動滑鼠時只改圖層位置，不會讓 SwiftUI 重畫
final class CatEyesView: NSView {
    private struct EyeLayers {
        let eye: CatEye
        let container: CALayer
        let iris: CALayer
        let lid: CALayer
        let lidMask: CALayer
    }

    private var layersByEye: [EyeLayers] = []
    private var configuredKey: Int?
    private var blinkTimer: Timer?
    private var gaze: [CGPoint] = []

    var mood: CatMood = .awake {
        didSet { if mood != oldValue { applyMood(animated: true) } }
    }

    /// 眼睛跟著游標；關掉時不監聽滑鼠，眼睛看前方
    var followsCursor = true {
        didSet { if followsCursor != oldValue { updateCursorWatching() } }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    /// 滑鼠事件交給底下的寵物視窗處理
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// key：照片換了才重做圖層
    func configure(photo: CGImage, eyes: [CatEye], key: Int) {
        guard key != configuredKey, let root = layer else { return }
        configuredKey = key
        layersByEye.forEach { $0.container.removeFromSuperlayer(); $0.lid.removeFromSuperlayer() }
        layersByEye = eyes.compactMap { eye in
            guard let images = CatEyeImages(photo: photo, eye: eye) else { return nil }
            let container = CALayer()
            let mask = CALayer()
            mask.contents = images.openingMask
            container.mask = mask
            container.backgroundColor = CGColor(srgbRed: 0.20, green: 0.24, blue: 0.30, alpha: 1)
            let iris = CALayer()
            iris.contents = images.iris
            container.addSublayer(iris)
            let lid = CALayer()
            lid.contents = images.closed
            let lidMask = CALayer()
            lidMask.backgroundColor = CGColor(gray: 0, alpha: 1)
            lidMask.anchorPoint = CGPoint(x: 0.5, y: 0)
            lid.mask = lidMask
            for item in [container, lid] { root.addSublayer(item) }
            return EyeLayers(eye: eye, container: container, iris: iris, lid: lid, lidMask: lidMask)
        }
        gaze = Array(repeating: .zero, count: layersByEye.count)
        needsLayout = true
        applyMood(animated: false)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, item) in layersByEye.enumerated() {
            let r = CGFloat(item.eye.radius) * bounds.width
            let center = CGPoint(x: CGFloat(item.eye.x) * bounds.width, y: CGFloat(item.eye.y) * bounds.height)
            func frame(_ rect: CGRect) -> CGRect {
                CGRect(x: center.x + rect.minX * r, y: center.y + rect.minY * r, width: rect.width * r, height: rect.height * r)
            }
            item.container.frame = frame(CatEyeImages.opening)
            item.container.mask?.frame = item.container.bounds
            item.iris.bounds = CGRect(x: 0, y: 0, width: CatEyeImages.iris.width * r, height: CatEyeImages.iris.height * r)
            item.lid.frame = frame(CatEyeImages.cover)
            item.lidMask.bounds = CGRect(x: 0, y: 0, width: item.lid.bounds.width, height: lidHeight(for: item))
            item.lidMask.position = CGPoint(x: item.lid.bounds.midX, y: 0)
            placeIris(index, r: r)
        }
        CATransaction.commit()
    }

    private func lidHeight(for item: EyeLayers) -> CGFloat {
        mood == .sleeping ? item.lid.bounds.height : 0
    }

    private func placeIris(_ index: Int, r: CGFloat) {
        let item = layersByEye[index]
        let offset = index < gaze.count ? gaze[index] : .zero
        item.iris.position = CGPoint(x: item.container.bounds.midX + offset.x * r * 0.3, y: item.container.bounds.midY + offset.y * r * 0.16)
    }

    // MARK: 跟著游標

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateCursorWatching()
        if window != nil {
            scheduleBlink()
        } else {
            blinkTimer?.invalidate()
            blinkTimer = nil
        }
    }

    private func updateCursorWatching() {
        if window != nil, followsCursor {
            CursorWatcher.shared.add(self) { [weak self] point in self?.look(at: point) }
            look(at: NSEvent.mouseLocation)
        } else {
            CursorWatcher.shared.remove(self)
            lookAhead()
        }
    }

    /// 看前方
    private func lookAhead() {
        gaze = Array(repeating: .zero, count: layersByEye.count)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        for index in layersByEye.indices { placeIris(index, r: CGFloat(layersByEye[index].eye.radius) * bounds.width) }
        CATransaction.commit()
    }

    /// 開發用快照：直接指定注視方向（-1～1）
    func setGazeForSnapshot(_ direction: CGPoint) {
        gaze = Array(repeating: direction, count: layersByEye.count)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in layersByEye.indices { placeIris(index, r: CGFloat(layersByEye[index].eye.radius) * bounds.width) }
        CATransaction.commit()
    }

    /// 眼珠往游標的方向移：游標離眼睛越遠移得越多，最多是半徑的 0.3（左右）與 0.16（上下）
    private func look(at screenPoint: NSPoint) {
        guard let window, followsCursor, mood == .awake, !layersByEye.isEmpty else { return }
        let next: [CGPoint] = layersByEye.map { item in
            let local = CGPoint(x: CGFloat(item.eye.x) * bounds.width, y: CGFloat(item.eye.y) * bounds.height)
            let center = window.convertPoint(toScreen: convert(local, to: nil))
            let dx = screenPoint.x - center.x, dy = screenPoint.y - center.y
            let distance = hypot(dx, dy)
            guard distance >= 1 else { return .zero }
            let strength = min(1, distance / max(bounds.width * 1.5, 60))
            // 螢幕座標 y 往上，這個視圖 y 往下
            return CGPoint(x: dx / distance * strength, y: -dy / distance * strength)
        }
        // 眼珠幾乎沒動（不到半徑的 1%）就不更新，省下重畫
        let moved = zip(next, gaze).contains { abs($0.x - $1.x) > 0.03 || abs($0.y - $1.y) > 0.05 }
        guard moved || gaze.count != next.count else { return }
        gaze = next
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        for index in layersByEye.indices { placeIris(index, r: CGFloat(layersByEye[index].eye.radius) * bounds.width) }
        CATransaction.commit()
    }

    // MARK: 眨眼、睡覺

    private func scheduleBlink() {
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: .random(in: 2.5...6), repeats: false) { [weak self] _ in
            MainActor.assumeIsolatedCompat {
                self?.blink(twice: Int.random(in: 0..<5) == 0)
                self?.scheduleBlink()
            }
        }
    }

    private func blink(twice: Bool) {
        guard mood == .awake else { return }
        for item in layersByEye {
            let close = CABasicAnimation(keyPath: "bounds.size.height")
            close.fromValue = 0
            close.toValue = item.lid.bounds.height
            close.duration = 0.09
            close.autoreverses = true
            close.repeatCount = twice ? 2 : 1
            close.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            item.lidMask.add(close, forKey: "blink")
        }
    }

    private func applyMood(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.2)
        for item in layersByEye {
            item.container.opacity = mood == .awake ? 1 : 0
            item.lidMask.bounds.size.height = lidHeight(for: item)
        }
        CATransaction.commit()
        if mood == .awake, followsCursor { look(at: NSEvent.mouseLocation) }
    }
}

/// 全螢幕的游標位置：所有會動的眼睛共用一組事件監聽，每秒最多通知 20 次，沒人在看就停
@MainActor
final class CursorWatcher {
    static let shared = CursorWatcher()

    /// 每次通知至少隔多久：每秒 20 次，眼睛轉動看起來一樣順
    private static let interval: TimeInterval = 1.0 / 20

    private var handlers: [ObjectIdentifier: (NSPoint) -> Void] = [:]
    private var monitors: [Any] = []
    private var lastSent: TimeInterval = 0
    private var trailing: DispatchWorkItem?

    func add(_ owner: AnyObject, handler: @escaping (NSPoint) -> Void) {
        handlers[ObjectIdentifier(owner)] = handler
        if monitors.isEmpty { start() }
    }

    func remove(_ owner: AnyObject) {
        handlers[ObjectIdentifier(owner)] = nil
        if handlers.isEmpty { stop() }
    }

    /// 有沒有在監聽滑鼠移動（開發用自我測試）
    var isWatching: Bool { !monitors.isEmpty }

    /// 開發用自我測試：假裝游標移到某個位置，走和真的移動一樣的節流
    func simulateMove(to point: NSPoint) {
        simulated = point
        moved()
    }

    private var simulated: NSPoint?

    private func start() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolatedCompat { self?.moved() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.moved()
            return event
        }) {
            monitors.append(local)
        }
    }

    private func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        trailing?.cancel()
        trailing = nil
    }

    /// 太密的事件先略過，最後一個位置一定會送到
    private func moved() {
        let now = CACurrentMediaTime()
        if now - lastSent >= Self.interval {
            send()
        } else if trailing == nil {
            let work = DispatchWorkItem { [weak self] in
                self?.trailing = nil
                self?.send()
            }
            trailing = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.interval, execute: work)
        }
    }

    private func send() {
        lastSent = CACurrentMediaTime()
        let point = simulated ?? NSEvent.mouseLocation
        handlers.values.forEach { $0(point) }
    }
}

/// SwiftUI 裡的會動的眼睛：照片換了才重做圖層，平常只更新狀態
struct CatEyesOverlay: NSViewRepresentable {
    let photo: CGImage
    let eyes: [CatEye]
    let key: Int
    let mood: CatMood
    var followsCursor = true

    func makeNSView(context: Context) -> CatEyesView { CatEyesView(frame: .zero) }

    func updateNSView(_ view: CatEyesView, context: Context) {
        view.configure(photo: photo, eyes: eyes, key: key)
        view.mood = mood
        view.followsCursor = followsCursor
    }
}
