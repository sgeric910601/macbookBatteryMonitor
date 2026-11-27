import AppKit

/// 選單列圖示的提示框，開著時數字跟著更新。
/// 系統的 toolTip 一換文字就會在游標目前的位置重新顯示（滑鼠剛離開時也會，提示框就跑到畫面中間），
/// 所以自己畫：固定在圖示正下方，只換文字不換位置
private final class LiveToolTip: NSResponder {
    weak var view: NSView?
    var text = "" {
        didSet { if TipPanel.shared.owner === self { TipPanel.shared.show(for: self) } }
    }
    private var delay: Timer?

    override func mouseEntered(with event: NSEvent) {
        delay?.invalidate()
        // 和系統提示框差不多的延遲：滑鼠只是經過不會跳出來
        delay = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            guard let self, NSEvent.pressedMouseButtons == 0, self.isHovered else { return }
            TipPanel.shared.show(for: self)
        }
    }

    override func mouseExited(with event: NSEvent) {
        delay?.invalidate()
        TipPanel.shared.hide(self)
    }

    /// 游標在圖示上，而且圖示還在畫面上
    var isHovered: Bool {
        guard let view, let window = view.window, window.isVisible else { return false }
        return window.convertToScreen(view.convert(view.bounds, to: nil)).contains(NSEvent.mouseLocation)
    }
}

/// 全 App 共用一個提示框視窗，同時只會有一個圖示的提示
private final class TipPanel {
    static let shared = TipPanel()
    private(set) weak var owner: LiveToolTip?
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private var watch: Timer?
    private var clickMonitor: Any?

    private init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let background = NSVisualEffectView()
        background.material = .toolTip
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 6
        background.layer?.masksToBounds = true
        label.font = .toolTipsFont(ofSize: 0)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = 420
        background.addSubview(label)
        panel.contentView = background
    }

    func show(for tip: LiveToolTip) {
        guard !tip.text.isEmpty, let view = tip.view, let window = view.window, let screen = window.screen else { hide(tip); return }
        owner = tip
        label.stringValue = tip.text
        let size = label.fittingSize
        let padding = NSSize(width: 8, height: 4)
        label.frame = NSRect(x: padding.width, y: padding.height, width: ceil(size.width), height: ceil(size.height))
        let icon = window.convertToScreen(view.convert(view.bounds, to: nil))
        let frameSize = NSSize(width: ceil(size.width) + padding.width * 2, height: ceil(size.height) + padding.height * 2)
        // 圖示正下方置中，不超出螢幕左右
        let visible = screen.visibleFrame
        let x = min(max(icon.midX - frameSize.width / 2, visible.minX + 4), visible.maxX - frameSize.width - 4)
        panel.setFrame(NSRect(x: x, y: icon.minY - 6 - frameSize.height, width: frameSize.width, height: frameSize.height), display: true)
        guard !panel.isVisible else { return }
        panel.orderFrontRegardless()
        // 面板可能被別的東西收起（沒經過 hide）：先拆掉上一次的檢查，不會疊出第二個計時器與監聽
        stopWatching()
        // 選單列圖示常收不到離開事件（例如全螢幕時選單列收起）：顯示期間自己確認游標還在
        watch = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.owner?.isHovered != true { self.hide(nil) }
        }
        // 點了圖示（開面板、右鍵選單）就收起，和系統提示框一樣
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.hide(nil)
            return event
        }
    }

    /// tip 不是 nil 時只收起它自己的提示（滑鼠已經移到別的圖示、換了主人就不動）
    func hide(_ tip: LiveToolTip?) {
        if let tip, owner !== tip { return }
        owner = nil
        stopWatching()
        panel.orderOut(nil)
    }

    private func stopWatching() {
        watch?.invalidate()
        watch = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }
}

private var liveToolTipKey: UInt8 = 0

extension NSView {
    /// setLiveToolTip 設的最新文字（合併成一個圖示時要複製過去）
    var liveToolTip: String? { (objc_getAssociatedObject(self, &liveToolTipKey) as? LiveToolTip)?.text }

    /// 數字每秒更新的提示框：提示框開著時文字跟著換，位置固定在圖示下方
    func setLiveToolTip(_ text: String?) {
        let tip: LiveToolTip
        if let existing = objc_getAssociatedObject(self, &liveToolTipKey) as? LiveToolTip {
            tip = existing
        } else {
            tip = LiveToolTip()
            tip.view = self
            // 追蹤範圍跟著可見範圍走（圖示寬度變了不用重新登記）；owner 不被保留，由 view 保留
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: tip))
            objc_setAssociatedObject(self, &liveToolTipKey, tip, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        let new = text ?? ""
        guard tip.text != new else { return }
        tip.text = new
        // 不再設系統的 toolTip，旁白（VoiceOver）改從輔助說明讀到同樣的文字
        setAccessibilityHelp(new.isEmpty ? nil : new)
    }
}
