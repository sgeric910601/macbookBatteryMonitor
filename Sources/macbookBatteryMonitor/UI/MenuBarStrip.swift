import AppKit

/// 合併顯示時的第二條狀態列：點選單列上合併的圖示，在下方展開一條，列出電池（桌上型為耗電）與各系統監控圖示，
/// 數字即時更新。點上面的圖示打開它的面板（再點一次收起來），點其他地方或按 Esc 收起整條。
/// 只有展開時系統監控才取樣，收起來就停
@MainActor
final class MenuBarStrip: NSObject {
    private static let batteryKey = "battery"

    private let monitors: ModuleCoordinator
    /// 選單列上合併的那個圖示：電池圖示的內容直接照抄它
    private let mergedButton: () -> NSStatusBarButton?

    /// 電池面板：從第二條狀態列的圖示打開、關閉、是否開著、面板視窗
    var openBattery: ((NSView) -> Void)?
    var closeBattery: (() -> Void)?
    var batteryShown: (() -> Bool)?
    var batteryWindow: (() -> NSWindow?)?

    private var panel: NSPanel?
    private var stack: NSStackView?
    private var buttons: [StripButton] = []
    private var timer: Timer?
    private var eventMonitors: [Any] = []

    init(monitors: ModuleCoordinator, mergedButton: @escaping () -> NSStatusBarButton?) {
        self.monitors = monitors
        self.mergedButton = mergedButton
    }

    var isShown: Bool { panel != nil }
    var window: NSWindow? { panel }

    func toggle() {
        isShown ? close() : show()
    }

    func show() {
        guard panel == nil, mergedButton() != nil else { return }
        monitors.stripActive = true

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 28),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        // 和選單一樣的半透明背景
        let background = NSVisualEffectView()
        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background

        // 和選單列相同的順序：系統監控在左、電池在最右邊
        buttons = (monitors.enabledKinds.map(\.rawValue) + [Self.batteryKey]).map { key in
            let button = StripButton(key: key)
            button.target = self
            button.action = #selector(buttonClicked(_:))
            stack.addArrangedSubview(button)
            return button
        }
        self.panel = panel
        self.stack = stack
        refresh()
        panel.orderFrontRegardless()

        let interval = AppSettings.shared.sampleInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolatedCompat { self?.refresh() }
        }
        startEventMonitors()
    }

    func close() {
        guard let panel else { return }
        closePanels()
        timer?.invalidate()
        timer = nil
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
        panel.orderOut(nil)
        self.panel = nil
        stack = nil
        buttons = []
        monitors.stripActive = false
    }

    private func closePanels() {
        if batteryShown?() == true { closeBattery?() }
        monitors.closePanel()
    }

    // MARK: 圖示

    private func refresh() {
        for button in buttons {
            if button.key == Self.batteryKey {
                guard let source = mergedButton() else { continue }
                button.image = source.image
                button.attributedTitle = source.attributedTitle
                button.imagePosition = source.title.isEmpty ? .imageOnly : source.imagePosition
                button.toolTip = source.toolTip
            } else if let kind = MonitorKind(rawValue: button.key) {
                let content = monitors.stripContent(kind)
                button.image = content.image
                button.title = ""
                button.imagePosition = .imageOnly
                button.toolTip = content.tooltip
            }
        }
        layout()
    }

    /// 貼在選單列下方，右邊對齊合併的圖示；寬度跟著內容變
    private func layout() {
        guard let panel, let stack, let anchor = mergedButton(), let anchorWindow = anchor.window else { return }
        let size = stack.fittingSize
        let anchorFrame = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let screen = anchorWindow.screen ?? NSScreen.main
        var x = anchorFrame.maxX - size.width
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + 4), visible.maxX - size.width - 4)
        }
        let frame = NSRect(x: x, y: anchorWindow.frame.minY - size.height - 6, width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    // MARK: 點擊

    /// 開發用自我測試：模擬點第二條狀態列上的某個圖示，回傳點到的是哪一個
    @discardableResult
    func selfTestClick(_ key: String) -> Bool {
        guard let button = buttons.first(where: { $0.key == key }) else { return false }
        buttonClicked(button)
        return true
    }

    @objc private func buttonClicked(_ sender: StripButton) {
        if CommandLine.arguments.contains("--selftest-strip") {
            print("selftest: 點 \(sender.key)，電池面板開著 \(batteryShown?() == true)，模組面板 \(monitors.panelWindow?.isVisible == true)")
        }
        if sender.key == Self.batteryKey {
            if batteryShown?() == true {
                closeBattery?()
            } else {
                monitors.closePanel()
                openBattery?(sender)
            }
        } else if let kind = MonitorKind(rawValue: sender.key) {
            if monitors.isPanelShown(kind) {
                monitors.closePanel()
            } else {
                if batteryShown?() == true { closeBattery?() }
                monitors.showPanel(kind, from: sender)
            }
        }
    }

    /// 點其他 App、桌面或本 App 其他視窗就收起來；第二條狀態列、它打開的面板與合併的圖示交給原本的處理。Esc 也會收起來
    private func startEventMonitors() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolatedCompat { self?.close() }
        }) {
            eventMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            guard let self else { return event }
            let ours = [self.panel, self.monitors.panelWindow, self.batteryWindow?(), self.mergedButton()?.window]
            if !ours.contains(where: { $0 != nil && $0 === event.window }) { self.close() }
            return event
        }) {
            eventMonitors.append(local)
        }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53, let self, self.isShown else { return event }
            self.close()
            return nil
        }) {
            eventMonitors.append(keys)
        }
    }
}

/// 第二條狀態列上的一個圖示：外觀和選單列的圖示一樣（沒有邊框、等寬數字）
private final class StripButton: NSButton {
    let key: String

    init(key: String) {
        self.key = key
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryChange)
        imageScaling = .scaleNone
        font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
        setContentHuggingPriority(.required, for: .horizontal)
        heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    /// 不在前景時第一下也算點擊
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 10, height: 24)
    }
}
