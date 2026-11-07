import AppKit
import SwiftUI

/// 選單列的貓咪快捷面板：點開直接操作常用功能（防止休眠、麥克風、鍵盤清潔、音訊輸出、剪貼簿歷史）。
/// 和電池、系統監控的面板同一套規則：點圖示開、再點收；點其他圖示直接換過去；點其他地方收起。
/// 面板每次打開才建立、關掉就釋放，平常不做任何事；不需要權限
@MainActor
final class QuickMenuController: NSObject, NSPopoverDelegate {
    static let shared = QuickMenuController()

    private var item: NSStatusItem?
    private var settings: AppSettings?
    private var openSettings: ((SettingsSection?) -> Void)?
    private var popover: NSPopover?
    private var outsideClickMonitors: [Any] = []

    func apply(enabled: Bool, settings: AppSettings, openSettings: @escaping (SettingsSection?) -> Void) {
        self.settings = settings
        self.openSettings = openSettings
        guard enabled else {
            popover?.closeNow(animated: false)
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.catIcon()
        item.button?.toolTip = "快捷選單"
        item.button?.setAccessibilityLabel("快捷選單")
        item.button?.target = self
        item.button?.action = #selector(itemClicked)
        self.item = item
    }

    /// 去背的貓咪照片縮到選單列的高度（保持比例）；讀不到時用系統的貓咪符號
    private static func catIcon() -> NSImage? {
        let height: CGFloat = 18
        guard let url = Bundle.main.url(forResource: "icon-cat", withExtension: "png"), let photo = NSImage(contentsOf: url),
              photo.size.height > 0 else {
            let symbol = NSImage(systemSymbolName: "cat", accessibilityDescription: "快捷選單")
            symbol?.isTemplate = true
            return symbol
        }
        let size = NSSize(width: (photo.size.width / photo.size.height * height).rounded(), height: height)
        return NSImage(size: size, flipped: false) { rect in
            photo.draw(in: rect)
            return true
        }
    }

    // MARK: - 面板

    @objc private func itemClicked(_ sender: NSStatusBarButton) {
        if let popover, popover.isShown {
            popover.closeNow()
        } else {
            showPopover(from: sender)
        }
    }

    private func showPopover(from button: NSView) {
        guard let settings else { return }
        AudioSwitchController.shared.refresh()
        let root = QuickMenuPanel(settings: settings, awake: .shared, audio: .shared,
                                  clipboard: ClipboardHistoryController.shared.history.items,
                                  close: { [weak self] in self?.popover?.closeNow() },
                                  openSettings: { [weak self] section in
                                      self?.popover?.closeNow(animated: false)
                                      self?.openSettings?(section)
                                  })
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = hosting
        popover.contentSize = hosting.view.fittingSize
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.allowInFullScreen()
        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()
        startOutsideClickMonitoring(button: button)
    }

    /// 點其他 App、桌面或本 App 其他視窗（電池、系統監控的圖示與面板）就收起來。
    /// 面板本身與貓咪圖示交給原本的處理（再點一次圖示是收起）
    private func startOutsideClickMonitoring(button: NSView) {
        stopOutsideClickMonitoring()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.popover?.closeNow() }
        }) {
            outsideClickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self, weak button] event in
            guard let self, let popover = self.popover else { return event }
            let inside = event.window === popover.contentViewController?.view.window || event.window === button?.window
            if !inside { popover.closeNow() }
            return event
        }) {
            outsideClickMonitors.append(local)
        }
    }

    private func stopOutsideClickMonitoring() {
        outsideClickMonitors.forEach(NSEvent.removeMonitor)
        outsideClickMonitors.removeAll()
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover else { return }
        if closed === popover { stopOutsideClickMonitoring() }
        DispatchQueue.main.async { [weak self] in
            closed.contentViewController = nil
            if self?.popover === closed { self?.popover = nil }
        }
    }
}
