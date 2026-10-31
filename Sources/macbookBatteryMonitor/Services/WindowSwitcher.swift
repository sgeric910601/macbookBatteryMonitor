import AppKit
import ApplicationServices
import SwiftUI

/// 取代 Cmd+Tab：列出桌面上所有 App 的視窗（不只 App），最近用過的在前，附縮圖。
/// 按住快捷鍵的修飾鍵按它的按鍵選下一個、放開就切過去；很快按一下就直接回到上一個視窗，不顯示切換器
@MainActor
final class WindowSwitcher {
    static let shared = WindowSwitcher()

    /// 很快按一下時不閃出切換器
    private static let showDelay: TimeInterval = 0.12
    /// 切換器佔螢幕可用範圍的比例上限
    private static let screenFraction: CGFloat = 0.9

    private(set) var settings = SwitcherSettings()

    /// 這次切換使用的那組快捷鍵設定
    private var profile = SwitcherProfile()
    private let model = SwitcherModel()
    private var panel: OverlayPanel?
    private var showTimer: Timer?
    private var releaseTimer: Timer?
    private var clickMonitor: Any?
    private var active = false
    /// 預覽的世代：選取換了，舊的擷取結果不再顯示
    private var previewToken = 0
    private var shownMouse = NSEvent.mouseLocation

    /// 設定改變時呼叫；切換中的話結束它，下一次按快捷鍵才用新設定
    func configure(_ new: SwitcherSettings) {
        guard new != settings else { return }
        if active { end() }
        settings = new
    }

    func handle(_ action: SwitcherKeys.Action) {
        switch action {
        case .start(let slot, let delta):
            if active { end() }
            begin(slot: slot, delta)
        case .step(let delta):
            guard active else { return begin(slot: 0, delta) }
            model.select(SwitcherLayout.step(from: model.selected, delta: delta, count: model.items.count))
        case .move(let dx, let dy):
            guard active, !model.items.isEmpty else { return }
            show()
            model.select(SwitcherLayout.move(from: model.selected, dx: dx, dy: dy, in: model.grid))
        case .commit:
            commit()
        case .release:
            becomeSticky()
        case .cancel:
            end()
        case .window(let action):
            perform(action)
        case .none:
            break
        }
    }

    // MARK: - 開始、結束

    private func begin(slot: Int, _ delta: Int) {
        let started = Date()
        profile = settings.profiles.indices.contains(slot) ? settings.profiles[slot] : settings.profiles[0]
        let snapshot = WindowTracker.shared.snapshot()
        let items = settings.filter(forProfile: settings.profiles.indices.contains(slot) ? slot : 0).apply(snapshot.windows, context: snapshot.context)
        InputTap.log.notice("切換開始：視窗 \(snapshot.windows.count)，篩選後 \(items.count)，取得快照 \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        guard !items.isEmpty else {
            InputTap.shared.cancelSwitching()
            return
        }
        active = true
        model.items = items
        // 第一個是目前的視窗：往下從第二個開始，往回從最後一個開始
        model.selected = delta > 0 ? min(1, items.count - 1) : items.count - 1
        model.hasScreenAccess = WindowThumbnails.hasPermission && SkyLight.canCapture
        model.thumbnails = Dictionary(items.compactMap { item in WindowThumbnails.shared.cached(item.id).map { (item.id, $0) } }, uniquingKeysWith: { first, _ in first })
        shownMouse = NSEvent.mouseLocation
        model.animated = animationsEnabled
        showTimer = Timer.scheduledTimer(withTimeInterval: Self.showDelay, repeats: false) { _ in
            MainActor.assumeIsolated { WindowSwitcher.shared.show() }
        }
        releaseTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            MainActor.assumeIsolated { WindowSwitcher.shared.settleIfReleased() }
        }
        model.grid = SwitcherLayout.layout(style: profile.style, aspects: items.map(\.aspect), available: availableSize(), size: profile.tileSize,
                                           autoSize: profile.autoSize)
    }

    /// 保持開啟模式：放開修飾鍵後切換器留著。馬上顯示，點到切換器以外的地方就取消
    private func becomeSticky() {
        guard active else { return }
        releaseTimer?.invalidate()
        releaseTimer = nil
        show()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
            MainActor.assumeIsolated {
                InputTap.shared.cancelSwitching()
                WindowSwitcher.shared.handle(.cancel)
            }
        }
    }

    /// 放開修飾鍵的事件遺失（事件攔截中途被系統暫停）時，用實際的按鍵狀態結束切換
    private func settleIfReleased() {
        guard active, let hold = InputTap.shared.activeHold() else { return }
        let flags = NSEvent.modifierFlags
        let held = (!hold.contains(.command) || flags.contains(.command)) && (!hold.contains(.option) || flags.contains(.option))
            && (!hold.contains(.control) || flags.contains(.control))
        guard !held else { return }
        InputTap.shared.cancelSwitching()
        commit()
    }

    private func commit() {
        guard active else { return }
        let items = model.items, selected = model.selected
        end()
        guard items.indices.contains(selected) else { return }
        WindowTracker.shared.focus(items[selected])
    }

    private func end() {
        active = false
        showTimer?.invalidate()
        showTimer = nil
        releaseTimer?.invalidate()
        releaseTimer = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        panel?.orderOut(nil)
        WindowPreview.shared.hide()
        previewToken += 1
        model.items = []
        model.thumbnails = [:]
    }

    private func perform(_ action: SwitcherWindowAction) {
        guard active, model.items.indices.contains(model.selected) else { return }
        perform(action, on: model.items[model.selected])
    }

    private func perform(_ action: SwitcherWindowAction, on window: SwitcherWindow) {
        guard active else { return }
        switch WindowTracker.shared.perform(action, on: window) {
        case .unchanged:
            break
        case .updated(let minimized, let fullscreen, let hidden):
            for item in model.items where item.pid == window.pid {
                model.update(item.id) { entry in
                    if let hidden { entry.isHidden = hidden }
                    guard item.id == window.id else { return }
                    if let minimized { entry.isMinimized = minimized }
                    if let fullscreen { entry.isFullscreen = fullscreen }
                }
            }
        case .removed:
            model.remove(window.id)
            WindowThumbnails.shared.forget([window.id])
            if model.items.isEmpty { end() } else { relayout() }
        }
    }

    // MARK: - 顯示

    private func show() {
        guard active, !model.items.isEmpty, showTimer != nil else { return }
        showTimer?.invalidate()
        showTimer = nil
        let panel = panel ?? OverlayPanel()
        self.panel = panel
        let view = SwitcherView(model: model, pick: { index in
            WindowSwitcher.shared.model.selected = index
            InputTap.shared.cancelSwitching()
            WindowSwitcher.shared.commit()
        }, act: { action, window in
            WindowSwitcher.shared.perform(action, on: window)
        }, mouseMoved: { NSEvent.mouseLocation.distance(to: WindowSwitcher.shared.shownMouse) > 3 })
        relayout()
        let wasVisible = panel.isVisible
        panel.present(view, size: panelSize, screen: targetScreen())
        if animationsEnabled, !wasVisible {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
        }
        // 切換器真的顯示出來才擷取：很快按一下不顯示，也就不擷取畫面（系統會在擷取時顯示「正在擷取你的畫面」）
        requestThumbnails()
        updatePreview()
        announceSelection()
    }

    /// 切換器是不搶焦點的面板，VoiceOver 不會自己念選到什麼：選取換了就主動播報
    fileprivate func announceSelection() {
        guard NSWorkspace.shared.isVoiceOverEnabled, active, model.items.indices.contains(model.selected) else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: model.items[model.selected].accessibilityDescription, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// 選取的視窗換了：用快取的縮圖馬上顯示在視窗位置，再換成高解析度畫面
    fileprivate func updatePreview() {
        previewToken += 1
        guard settings.previewSelectedWindow, active, panel?.isVisible == true, model.items.indices.contains(model.selected) else {
            return WindowPreview.shared.hide()
        }
        let item = model.items[model.selected]
        // 沒有視窗可看（沒有視窗的 App、縮到 Dock、在別的桌面）就不預覽
        guard !item.isWindowless, !item.isMinimized, item.spaceNumber == nil, item.frame.width > 1 else { return WindowPreview.shared.hide() }
        if let cached = WindowThumbnails.shared.cached(item.id) {
            WindowPreview.shared.show(id: item.id, frame: item.frame, image: cached)
        } else {
            WindowPreview.shared.hide()
        }
        guard settings.refreshThumbnails else { return }
        let token = previewToken
        let pixels = min(3200, Int(item.frame.width * (NSScreen.main?.backingScaleFactor ?? 2)))
        WindowThumbnails.shared.captureOnce(item.id, maxPixelWidth: pixels) { image in
            let switcher = WindowSwitcher.shared
            guard switcher.active, switcher.previewToken == token else { return }
            WindowPreview.shared.show(id: item.id, frame: item.frame, image: image)
        }
    }

    private var animationsEnabled: Bool { settings.animations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private var panelSize: CGSize { SwitcherLayout.panelSize(for: model.grid, available: availableSize()) }

    private func relayout() {
        model.grid = SwitcherLayout.layout(style: profile.style, aspects: model.items.map(\.aspect), available: availableSize(), size: profile.tileSize,
                                           autoSize: profile.autoSize)
        guard let panel, panel.isVisible else { return }
        panel.present(nil as SwitcherView?, size: panelSize, screen: targetScreen())
    }

    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
    }

    private func availableSize() -> CGSize {
        let frame = targetScreen()?.visibleFrame.size ?? CGSize(width: 1200, height: 800)
        return CGSize(width: frame.width * Self.screenFraction, height: frame.height * Self.screenFraction)
    }

    /// 只有縮圖樣式需要視窗截圖；解析度依版面算出的縮圖高度（上限 1600 像素寬）
    private func requestThumbnails() {
        guard profile.style == .thumbnails, settings.refreshThumbnails else { return }
        let ids = model.items.filter { !$0.isWindowless }.map(\.id)
        let pixels = min(1600, Int(model.grid.thumbnailHeight * SwitcherLayout.aspectRange.upperBound * 2))
        WindowThumbnails.shared.request(ids, maxPixelWidth: pixels) { id, image in
            WindowSwitcher.shared.model.thumbnails[id] = image
        }
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}

extension OverlayPanel {
    /// 用指定大小放在螢幕正中間；view 為 nil 時只調整位置與大小（內容不變）
    func present<V: View>(_ view: V?, size: CGSize, screen: NSScreen?) {
        if let view { contentView = NSHostingView(rootView: view) }
        let area = screen?.visibleFrame ?? .zero
        setFrame(CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height), display: true)
        orderFrontRegardless()
    }
}

@MainActor
@Observable
final class SwitcherModel {
    var items: [SwitcherWindow] = []
    var selected = 0
    var thumbnails: [UInt32: CGImage] = [:]
    var grid = SwitcherLayout.Grid.empty
    var hasScreenAccess = false

    /// 選取框移動的過渡動畫（由切換器依設定與系統的「減少動態效果」決定）
    var animated = false

    func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        withAnimation(animated ? .easeOut(duration: 0.12) : nil) { selected = index }
    }

    func update(_ id: UInt32, _ change: (inout SwitcherWindow) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    func remove(_ id: UInt32) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        thumbnails[id] = nil
        selected = min(selected, max(items.count - 1, 0))
    }
}

private struct SwitcherView: View {
    let model: SwitcherModel
    let pick: (Int) -> Void
    let act: (SwitcherWindowAction, SwitcherWindow) -> Void
    let mouseMoved: () -> Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let grid = model.grid
        ScrollViewReader { proxy in
            ScrollView(grid.scrolls ? .vertical : []) {
                VStack(spacing: grid.spacing) {
                    ForEach(Array(grid.rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: grid.spacing) {
                            ForEach(row, id: \.self) { index in
                                if model.items.indices.contains(index) {
                                    let item = model.items[index]
                                    tile(item, selected: index == model.selected, grid: grid, size: CGSize(width: grid.widths[index], height: grid.tileHeight))
                                        .id(item.id)
                                        .onContinuousHover { phase in
                                            if case .active = phase, mouseMoved() { model.select(index) }
                                        }
                                        .onTapGesture { pick(index) }
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel(item.accessibilityDescription)
                                        .accessibilityAddTraits(index == model.selected ? [.isButton, .isSelected] : .isButton)
                                        .accessibilityAction { pick(index) }
                                        .accessibilityAction(named: "關閉視窗") { act(.close, item) }
                                        .accessibilityAction(named: "縮到 Dock") { act(.minimize, item) }
                                        .accessibilityAction(named: "全螢幕") { act(.fullscreen, item) }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(SwitcherLayout.padding)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selected) { _, selected in
                guard model.items.indices.contains(selected) else { return }
                proxy.scrollTo(model.items[selected].id)
                WindowSwitcher.shared.updatePreview()
                WindowSwitcher.shared.announceSelection()
            }
        }
        .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.regularMaterial),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(reduceTransparency ? 0.35 : 0), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("視窗切換")
        .overlay(alignment: .bottom) {
            if !model.hasScreenAccess, grid.style == .thumbnails {
                Text("允許「螢幕錄製」後才會顯示視窗縮圖")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
        }
    }
}

extension SwitcherView {
    @ViewBuilder fileprivate func tile(_ item: SwitcherWindow, selected: Bool, grid: SwitcherLayout.Grid, size: CGSize) -> some View {
        switch grid.style {
        case .thumbnails:
            SwitcherTile(window: item, image: model.thumbnails[item.id], selected: selected, size: size, act: act)
        case .appIcons:
            SwitcherIconTile(window: item, selected: selected, size: size, iconSize: grid.thumbnailHeight)
        case .titles:
            SwitcherRow(window: item, selected: selected, size: size, act: act)
        }
    }
}

/// 視窗狀態標籤的內容；各種樣式共用
private func statusLabel(for window: SwitcherWindow) -> (symbol: String, text: String)? {
    guard let text = window.statusText else { return nil }
    if window.isWindowless { return ("macwindow", text) }
    if window.isMinimized { return ("minus.circle", text) }
    if window.isHidden { return ("eye.slash", text) }
    if window.isFullscreen { return ("arrow.up.left.and.arrow.down.right", text) }
    return ("square.on.square", text)
}

/// App 圖像樣式：只有圖示，選到的那個下方顯示標題
private struct SwitcherIconTile: View {
    let window: SwitcherWindow
    let selected: Bool
    let size: CGSize
    let iconSize: CGFloat

    private var icon: NSImage? { NSRunningApplication(processIdentifier: window.pid)?.icon }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if let icon { Image(nsImage: icon).resizable().scaledToFit().frame(width: iconSize, height: iconSize) }
                if let status = statusLabel(for: window) {
                    Image(systemName: status.symbol)
                        .font(.system(size: max(10, iconSize * 0.2), weight: .semibold))
                        .padding(3)
                        .background(.ultraThickMaterial, in: Circle())
                        .help(status.text)
                        .accessibilityLabel(status.text)
                }
            }
            Text(selected ? window.displayTitle : " ")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(height: SwitcherLayout.iconTitleHeight - 4)
        }
        .padding(SwitcherLayout.tilePadding)
        .frame(width: size.width, height: size.height)
        .opacity(window.isMinimized || window.isHidden ? 0.75 : 1)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Color.accentColor.opacity(0.28) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.displayTitle)
    }
}

/// 標題列表樣式：一列一個視窗，圖示、標題、狀態
private struct SwitcherRow: View {
    let window: SwitcherWindow
    let selected: Bool
    let size: CGSize
    let act: (SwitcherWindowAction, SwitcherWindow) -> Void
    @State private var hovered = false

    private var icon: NSImage? { NSRunningApplication(processIdentifier: window.pid)?.icon }

    var body: some View {
        HStack(spacing: 8) {
            if let icon { Image(nsImage: icon).resizable().frame(width: size.height * 0.6, height: size.height * 0.6) }
            Text(window.displayTitle).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            if hovered, !window.isWindowless {
                HStack(spacing: 6) {
                    button("xmark", .red, .close, "關閉視窗")
                    button("minus", .yellow, .minimize, window.isMinimized ? "從 Dock 還原" : "縮到 Dock")
                    button("arrow.up.left.and.arrow.down.right", .green, .fullscreen, "全螢幕")
                }
            } else if let status = statusLabel(for: window) {
                Label(status.text, systemImage: status.symbol).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .frame(width: size.width, height: size.height)
        .opacity(window.isMinimized || window.isHidden ? 0.75 : 1)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Color.accentColor.opacity(0.28) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    private func button(_ symbol: String, _ color: Color, _ action: SwitcherWindowAction, _ help: String) -> some View {
        Button { act(action, window) } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.black.opacity(0.7))
                .frame(width: 18, height: 18)
                .background(color, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct SwitcherTile: View {
    let window: SwitcherWindow
    let image: CGImage?
    let selected: Bool
    let size: CGSize
    let act: (SwitcherWindowAction, SwitcherWindow) -> Void
    @State private var hovered = false

    private var icon: NSImage? { NSRunningApplication(processIdentifier: window.pid)?.icon }
    private var dimmed: Bool { window.isMinimized || window.isHidden }

    private var status: (symbol: String, text: String)? { statusLabel(for: window) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                if let icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                Text(window.displayTitle).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .frame(height: SwitcherLayout.titleHeight - 6)
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.5))
                    if let icon { Image(nsImage: icon).resizable().scaledToFit().padding(size.width * 0.18) }
                }
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .topTrailing) { if let status { badge(status) } }
            .overlay(alignment: .bottom) { if hovered, !window.isWindowless { controls } }
        }
        .padding(SwitcherLayout.tilePadding)
        .frame(width: size.width, height: size.height)
        .opacity(dimmed ? 0.75 : 1)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Color.accentColor.opacity(0.28) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    /// 格子太窄放不下文字時只顯示圖示，文字改成提示與輔助使用的標籤；文字永遠單行，不換行
    private var compactBadge: Bool { size.width < 170 }

    private func badge(_ status: (symbol: String, text: String)) -> some View {
        Group {
            if compactBadge {
                Image(systemName: status.symbol).font(.system(size: 11, weight: .semibold)).padding(5)
            } else {
                Label(status.text, systemImage: status.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
            }
        }
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(6)
        .help(status.text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.text)
    }

    /// 指標停在縮圖上時的三顆按鈕：關閉、縮到 Dock（再按一次還原）、全螢幕
    private var controls: some View {
        HStack(spacing: 8) {
            control("xmark", .red, .close, "關閉視窗")
            control("minus", .yellow, .minimize, window.isMinimized ? "從 Dock 還原" : "縮到 Dock")
            control("arrow.up.left.and.arrow.down.right", .green, .fullscreen, "全螢幕")
        }
        .padding(8)
    }

    private func control(_ symbol: String, _ color: Color, _ action: SwitcherWindowAction, _ help: String) -> some View {
        Button { act(action, window) } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.black.opacity(0.7))
                .frame(width: 20, height: 20)
                .background(color, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
