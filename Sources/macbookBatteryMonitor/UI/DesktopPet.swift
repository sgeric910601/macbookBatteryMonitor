import AppKit
import AVFoundation
import CoreImage
import SwiftUI

/// 桌面寵物的互動狀態
@MainActor
final class DesktopPetState: ObservableObject {
    @Published var hovering = false
    /// 點一下時說的話；nil 表示沒在說話
    @Published var speech: String?
}

/// 桌面寵物：把充電夥伴放在桌面上。滑鼠移過去出現想像框（目前的狀態），點一下出現對話框（每點一次換一句），
/// 拖曳可以移動（記住位置），連點兩下打開面板，右鍵可以換外觀或隱藏。只有 MacBook 有（桌上型 Mac 沒有電池）。
/// 對話框是另一個不接收滑鼠的視窗，跟著寵物移動，不會擋到下面的東西
@MainActor
final class DesktopPetController {
    /// 和日曆小工具差不多大
    private static let size = CGSize(width: 176, height: 176)
    private static let originKey = "desktopPetOrigin"
    /// 對話框顯示幾秒
    private static let speechSeconds: TimeInterval = 4

    private let store: BatteryStore
    private let settings: AppSettings
    private let state = DesktopPetState()
    private var pet: NSPanel?
    private var bubble: NSPanel?
    private var bubbleHost: NSHostingView<DesktopPetBubbleView>?
    private var bubbleRefresh: Timer?
    private var speechEnd: DispatchWorkItem?
    private var sayingIndex = 0
    private var observers: [NSObjectProtocol] = []

    /// 連點兩下或從選單打開面板
    var openPanel: (() -> Void)?
    /// 右鍵選單打開設定視窗的「充電夥伴」
    var openSettings: (() -> Void)?

    init(store: BatteryStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    /// 依設定顯示或收起來，並套用位置（浮在視窗上方或放在桌布上）
    func sync() {
        if settings.desktopPet && BatteryReader.hasBattery { show() } else { hide() }
        pet?.level = level
        bubble?.level = level
    }

    /// 放在桌布上時和桌面圖示同一層（視窗會蓋住它）；否則浮在所有視窗上方
    private var level: NSWindow.Level {
        settings.desktopPetOnWallpaper ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1) : .floating
    }

    private func show() {
        guard pet == nil else { return }
        let panel = Self.makePanel(size: Self.size, ignoresMouse: false)
        panel.level = level
        let container = PetContainerView(frame: NSRect(origin: .zero, size: Self.size))
        container.host(DesktopPetFigureView(store: store, settings: settings))
        container.onHover = { [weak self] in self?.setHovering($0) }
        container.onClick = { [weak self] in self?.speak() }
        container.onDoubleClick = { [weak self] in self?.openPanel?() }
        container.menuProvider = { [weak self] in self?.menu() }
        panel.contentView = container
        panel.setFrameOrigin(savedOrigin() ?? defaultOrigin())
        panel.orderFrontRegardless()
        pet = panel
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolatedCompat {
                    self?.saveOrigin()
                    self?.layoutBubble()
                }
            })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolatedCompat { self?.keepOnScreen() }
            })
        keepOnScreen()
    }

    private func hide() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        speechEnd?.cancel()
        bubbleRefresh?.invalidate()
        bubbleRefresh = nil
        state.hovering = false
        state.speech = nil
        bubble?.orderOut(nil)
        bubble = nil
        bubbleHost = nil
        pet?.orderOut(nil)
        pet = nil
    }

    // MARK: 互動

    private func setHovering(_ hovering: Bool) {
        state.hovering = hovering
        updateBubble()
    }

    /// 點一下：說下一句話，幾秒後收起來
    private func speak() {
        guard let status = status(includeToday: true) else { return }
        let sayings = DesktopPetMessages.sayings(status)
        state.speech = sayings[sayingIndex % sayings.count]
        sayingIndex += 1
        speechEnd?.cancel()
        let end = DispatchWorkItem { [weak self] in
            self?.state.speech = nil
            self?.updateBubble()
        }
        speechEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.speechSeconds, execute: end)
        updateBubble()
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("打開面板") { [weak self] in self?.openPanel?() })
        menu.addItem(.separator())
        for appearance in ChargingAppearance.allCases {
            menu.addItem(ClosureMenuItem(appearance.shortTitle, checked: settings.chargingAppearance == appearance) { [weak self] in
                self?.settings.chargingAppearance = appearance
            })
        }
        menu.addItem(ClosureMenuItem("換照片…") { [weak self] in self?.settings.chooseCompanionPhoto() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("浮在視窗上方", checked: !settings.desktopPetOnWallpaper) { [weak self] in
            self?.settings.desktopPetOnWallpaper = false
        })
        menu.addItem(ClosureMenuItem("放在桌布上", checked: settings.desktopPetOnWallpaper) { [weak self] in
            self?.settings.desktopPetOnWallpaper = true
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("充電夥伴設定…") { [weak self] in self?.openSettings?() })
        menu.addItem(ClosureMenuItem("隱藏桌面寵物") { [weak self] in self?.settings.desktopPet = false })
        return menu
    }

    // MARK: 對話框

    /// 說話時顯示對話框；滑鼠停在上面時顯示想像框（每秒更新）；都沒有就收起來
    private func updateBubble() {
        guard let pet else { return }
        let text: String?
        let thought: Bool
        if let speech = state.speech {
            text = speech
            thought = false
        } else if state.hovering, let status = status(includeToday: false) {
            text = DesktopPetMessages.thought(status)
            thought = true
        } else {
            text = nil
            thought = false
        }
        guard let text else {
            bubbleRefresh?.invalidate()
            bubbleRefresh = nil
            bubble?.orderOut(nil)
            return
        }
        if bubble == nil {
            let panel = Self.makePanel(size: DesktopPetBubbleView.size, ignoresMouse: true)
            panel.level = level
            let host = NSHostingView(rootView: DesktopPetBubbleView(text: text, thought: thought, tailUp: false))
            panel.contentView = host
            bubble = panel
            bubbleHost = host
        }
        bubbleHost?.rootView = DesktopPetBubbleView(text: text, thought: thought, tailUp: false)
        layoutBubble()
        if bubble?.parent == nil, let bubble { pet.addChildWindow(bubble, ordered: .above) }
        bubble?.orderFrontRegardless()
        if thought, bubbleRefresh == nil {
            bubbleRefresh = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolatedCompat { self?.updateBubble() }
            }
        } else if !thought {
            bubbleRefresh?.invalidate()
            bubbleRefresh = nil
        }
    }

    /// 緊貼在貓咪頭上；上面空間不夠就貼在下方（尾巴朝上）。對話框視窗固定大小、不接收滑鼠，
    /// 框貼著靠近貓咪的那一邊畫，不論文字幾行都不會離貓咪太遠
    private func layoutBubble() {
        guard let pet, let bubble, let host = bubbleHost, let screen = pet.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = DesktopPetBubbleView.size
        // 貓咪的身體在視窗中間偏下，頭上方要往下疊一點才看起來貼著
        let above = NSPoint(x: pet.frame.midX - size.width / 2, y: pet.frame.maxY - 30)
        let below = above.y + size.height > visible.maxY
        if host.rootView.tailUp != below {
            host.rootView = DesktopPetBubbleView(text: host.rootView.text, thought: host.rootView.thought, tailUp: below)
        }
        var origin = below ? NSPoint(x: above.x, y: pet.frame.minY - size.height + 4) : above
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        bubble.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: 狀態

    private func status(includeToday: Bool) -> DesktopPetStatus? {
        guard let s = store.snapshot, let e = store.estimates else { return nil }
        var status = DesktopPetStatus(percent: s.percent, state: e.state)
        status.drainingOnAC = e.drainingOnAC
        status.minutesToEmpty = e.headlineToEmpty
        status.minutesToFull = e.headlineToFull
        status.limit = e.toLimit != nil ? s.chargeLimit?.limit : nil
        status.lowThreshold = settings.lowThreshold
        if store.chargeLimit.supported, let decision = store.chargingPlan.decision {
            let journey = store.companionPresentation(s, e)
            status.planTitle = journey.title
            status.planDetail = journey.detail
            status.planWaiting = decision.phase == .waiting
            status.planReady = decision.phase == .ready
        }
        if includeToday {
            let recap = DailyBatteryRecap.make(samples: store.history.samples, day: s.date)
            if recap.startPercent != nil {
                status.usedToday = recap.usedPercent
                status.chargedToday = recap.chargedPercent
            }
        }
        status.healthPercent = store.systemHealth?.maxCapacityPercent
        status.cycleCount = store.systemHealth?.cycleCount ?? (s.cycleCount > 0 ? s.cycleCount : nil)
        status.systemWatts = e.systemWatts
        return status
    }

    // MARK: 位置

    private func savedOrigin() -> NSPoint? {
        guard let text = UserDefaults.standard.string(forKey: Self.originKey) else { return nil }
        return NSPointFromString(text)
    }

    private func saveOrigin() {
        guard let pet else { return }
        UserDefaults.standard.set(NSStringFromPoint(pet.frame.origin), forKey: Self.originKey)
    }

    /// 預設在主螢幕右下角
    private func defaultOrigin() -> NSPoint {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        return NSPoint(x: visible.maxX - Self.size.width - 24, y: visible.minY + 24)
    }

    /// 顯示時、換螢幕或拔掉外接螢幕後，把整隻寵物收進它所在的螢幕；不在任何螢幕上就放回預設位置
    private func keepOnScreen() {
        guard let pet else { return }
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(pet.frame) }) else {
            pet.setFrameOrigin(defaultOrigin())
            return
        }
        let visible = screen.visibleFrame
        var origin = pet.frame.origin
        origin.x = min(max(origin.x, visible.minX), visible.maxX - pet.frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - pet.frame.height)
        if origin != pet.frame.origin { pet.setFrameOrigin(origin) }
    }

    private static func makePanel(size: CGSize, ignoresMouse: Bool) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        // 每個桌面都看得到；全螢幕的 App 裡不出現，也不出現在 Command-Tab 與視窗循環
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = ignoresMouse
        panel.isMovable = !ignoresMouse
        panel.becomesKeyOnlyIfNeeded = true
        return panel
    }
}

/// 桌面寵物的圖案：和主面板同一個充電夥伴，一直會動，只有省電模式時是靜態圖
struct DesktopPetFigureView: View {
    @ObservedObject var store: BatteryStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        Group {
            if let s = store.snapshot, let e = store.estimates {
                let presentation = store.companionPresentation(s, e)
                // 換照片時重畫
                let _ = settings.companionPhotoVersion
                if settings.chargingAppearance == .companion {
                    DesktopPetCompanion(presentation: presentation, animated: !settings.powerSavingActive)
                } else {
                    CompanionFigure(presentation: presentation, appearance: settings.chargingAppearance,
                                    animated: !settings.powerSavingActive, width: 140)
                }
            }
        }
        .frame(width: 176, height: 176)
    }
}

/// 桌面寵物的貓咪（日曆小工具大小）：用高解析度的貓咪動畫（320 像素寬），充電時下方畫發光的充電墊、
/// 上方畫充電標示，都用向量畫，放大也清楚。主面板的小貓咪仍用合成好的小影片
struct DesktopPetCompanion: View {
    let presentation: ChargingJourneyPresentation
    let animated: Bool

    var body: some View {
        VStack(spacing: -2) {
            if presentation.onPad { chargingSign }
            ZStack(alignment: .bottom) {
                if presentation.onPad { pad }
                cat.padding(.bottom, presentation.onPad ? 12 : 0)
            }
        }
        .frame(width: 160, height: 160, alignment: .bottom)
        .overlay(alignment: .topTrailing) {
            if let badge = presentation.badge {
                Image(systemName: badge.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white, presentation.color)
                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).padding(2))
                    .padding(.top, 22)
            }
        }
        .accessibilityHidden(true)
    }

    private var cat: some View {
        Group {
            if SpriteLoop.allowed, let url = Bundle.main.url(forResource: "pet-cat", withExtension: "mov") {
                SpriteLoop(url: url, animated: animated)
            } else if let url = Bundle.main.url(forResource: "pet-cat", withExtension: "png"), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.high)
            }
        }
        .frame(width: 160, height: 106)
    }

    /// 發光的充電墊
    private var pad: some View {
        ZStack {
            Ellipse()
                .fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.82)], startPoint: .top, endPoint: .bottom))
                .frame(width: 138, height: 28)
            Ellipse()
                .stroke(Color.green, lineWidth: 3)
                .frame(width: 112, height: 17)
                .shadow(color: .green.opacity(0.9), radius: 4)
        }
        .padding(.bottom, 2)
    }

    /// 充電標示：上方訊號波紋，下面接綠色圓圈裡的閃電（和主面板的貓咪相同）
    private var chargingSign: some View {
        VStack(spacing: -9) {
            Image(systemName: "wifi")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.green.opacity(0.55))
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.green))
        }
    }
}

/// 想像框（滑鼠移過去，圓角加兩個小圓點）或對話框（點一下，圓角加三角形尾巴）
struct DesktopPetBubbleView: View {
    /// 對話框視窗的固定大小，框貼著靠近貓咪的那一邊
    static let size = CGSize(width: 290, height: 150)

    let text: String
    let thought: Bool
    /// 對話框在寵物下方時尾巴朝上
    let tailUp: Bool

    var body: some View {
        bubble
            .frame(width: Self.size.width, height: Self.size.height, alignment: tailUp ? .top : .bottom)
    }

    private var bubble: some View {
        VStack(spacing: 2) {
            if tailUp { tail }
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 250)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: thought ? 16 : 10, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: thought ? 16 : 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1))
            if !tailUp { tail }
        }
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        .padding(6)
    }

    @ViewBuilder private var tail: some View {
        if thought {
            // 想像框：離寵物越近的圓點越小
            VStack(spacing: 2) {
                Circle().frame(width: tailUp ? 5 : 8, height: tailUp ? 5 : 8)
                Circle().frame(width: tailUp ? 8 : 5, height: tailUp ? 8 : 5)
            }
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .overlay(VStack(spacing: 2) {
                Circle().stroke(Color.secondary.opacity(0.35)).frame(width: tailUp ? 5 : 8, height: tailUp ? 5 : 8)
                Circle().stroke(Color.secondary.opacity(0.35)).frame(width: tailUp ? 8 : 5, height: tailUp ? 8 : 5)
            })
        } else {
            BubbleTail(up: tailUp)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(BubbleTail(up: tailUp).stroke(Color.secondary.opacity(0.35), lineWidth: 1))
                .frame(width: 14, height: 8)
                .padding(tailUp ? .bottom : .top, -3)
        }
    }
}

/// 循環播放影片的每一格：畫格只在第一次顯示時解碼一次，之後用 Core Animation 逐格換圖，播放交給系統合成，
/// App 幾乎不用 CPU。桌面寵物一直顯示，若用影片播放要每格解碼、提交圖層，M1 實測多用約 4% CPU；
/// 這樣也不需要 HEVC 硬體解碼，舊的 Intel Mac 一樣會動。主面板的貓咪也用這個
struct SpriteLoop: NSViewRepresentable {
    let url: URL
    let animated: Bool

    /// 開發用截圖畫不出動畫，只畫第一格
    static let allowed = !CommandLine.arguments.contains { $0.hasPrefix("--snapshot") || $0.hasPrefix("--screenshots") }

    func makeNSView(context: Context) -> SpriteLoopView { SpriteLoopView() }

    func updateNSView(_ view: SpriteLoopView, context: Context) {
        view.configure(url: url, animated: animated)
    }
}

final class SpriteLoopView: NSView {
    private struct Frames {
        var images: [CGImage]
        var duration: Double
    }

    /// 同一段影片的畫格只解碼一次（切換外觀、隱藏再顯示都不用重新解碼）
    @MainActor private static var cache: [URL: Frames] = [:]

    private let sprite = CALayer()
    private var url: URL?
    private var animated = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        sprite.contentsGravity = .resizeAspect
        layer?.addSublayer(sprite)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.frame = bounds
        CATransaction.commit()
    }

    func configure(url: URL, animated: Bool) {
        guard url != self.url || animated != self.animated else { return }
        self.url = url
        self.animated = animated
        if let frames = Self.cache[url] {
            apply(frames)
            return
        }
        // 解碼完成前（或萬一解不出來）先放同名的靜態圖，最差也是 v1.7.1 那樣的靜態貓咪，不會空白
        if sprite.contents == nil, let poster = NSImage(contentsOf: url.deletingPathExtension().appendingPathExtension("png")) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sprite.contents = poster
            CATransaction.commit()
        }
        Task.detached(priority: .utility) {
            let frames = await Self.decode(url)
            await MainActor.run {
                guard let frames else { return }
                Self.cache[url] = frames
                if self.url == url { self.apply(frames) }
            }
        }
    }

    private func apply(_ frames: Frames) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.removeAnimation(forKey: "loop")
        sprite.contents = frames.images.first
        if animated, frames.images.count > 1 {
            let loop = CAKeyframeAnimation(keyPath: "contents")
            loop.values = frames.images
            loop.calculationMode = .discrete
            loop.duration = frames.duration
            loop.repeatCount = .infinity
            loop.isRemovedOnCompletion = false
            sprite.add(loop, forKey: "loop")
        }
        CATransaction.commit()
    }

    /// 讀出影片的每一格（保留透明度）
    private static func decode(_ url: URL) async -> Frames? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let duration = try? await asset.load(.duration),
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        reader.add(output)
        guard reader.startReading() else { return nil }
        let context = CIContext(options: [.cacheIntermediates: false])
        var images: [CGImage] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let image = CIImage(cvPixelBuffer: buffer)
            if let cg = context.createCGImage(image, from: image.extent) { images.append(cg) }
        }
        guard !images.isEmpty else { return nil }
        return Frames(images: images, duration: duration.seconds)
    }
}

/// 對話框的三角形尾巴
private struct BubbleTail: Shape {
    let up: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if up {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        return path
    }
}

/// 寵物視窗的內容：SwiftUI 只負責畫，滑鼠都由這裡處理（移過去、點一下、連點兩下、拖曳、右鍵）
private final class PetContainerView: NSView {
    var onHover: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    private var mouseDownEvent: NSEvent?
    private var dragged = false
    private var pendingClick: DispatchWorkItem?
    private var tracking: NSTrackingArea?

    func host<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    /// App 不在前景時第一下也算點擊
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragged, let down = mouseDownEvent, let window else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard dx * dx + dy * dy > 9 else { return }
        dragged = true
        pendingClick?.cancel()
        window.performDrag(with: down)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        guard !dragged else { return }
        if event.clickCount >= 2 {
            pendingClick?.cancel()
            onDoubleClick?()
            return
        }
        // 等一下確認不是連點兩下，才當成點一下
        let click = DispatchWorkItem { [weak self] in self?.onClick?() }
        pendingClick = click
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: click)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

/// 用 closure 處理的選單項目
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func run() { handler() }
}

extension BatteryStore {
    /// 主面板與桌面寵物共用的充電夥伴狀態：支援調整充電上限時跟著智慧充電，不支援時只看是否在充電
    func companionPresentation(_ s: BatterySnapshot, _ e: Estimates) -> ChargingJourneyPresentation {
        chargeLimit.supported
            ? ChargingJourneyPresentation.make(percent: s.percent, charging: e.state == .charging,
                                               decision: chargingPlan.decision, now: s.date)
            : ChargingJourneyPresentation.unsupported(percent: s.percent, charging: e.state == .charging)
    }
}
