import AppKit

/// 選單列的貓咪快捷選單：點開直接操作常用功能（防止休眠、音訊、麥克風、鍵盤清潔、擴充功能開關、設定）。
/// 選單每次打開時才依目前狀態建立，平常不做任何事；不需要權限
@MainActor
final class QuickMenuController: NSObject, NSMenuDelegate {
    static let shared = QuickMenuController()

    private var item: NSStatusItem?
    private var settings: AppSettings?
    private var openSettings: ((SettingsSection?) -> Void)?

    func apply(enabled: Bool, settings: AppSettings, openSettings: @escaping (SettingsSection?) -> Void) {
        self.settings = settings
        self.openSettings = openSettings
        guard enabled else {
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.catIcon()
        item.button?.toolTip = "快捷選單"
        item.button?.setAccessibilityLabel("快捷選單")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
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

    // MARK: - 選單

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated { rebuild(menu) }
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let settings else { return }

        // 防止休眠
        let awake = KeepAwakeController.shared
        let awakeItem = NSMenuItem(title: awake.state.isActive ? "防止休眠中（\(awake.state.remainingText(now: Date()) ?? "直到關閉")）" : "防止休眠",
                                   action: nil, keyEquivalent: "")
        awakeItem.image = NSImage(systemSymbolName: awake.state.isActive ? "cup.and.saucer.fill" : "cup.and.saucer", accessibilityDescription: nil)
        let awakeMenu = NSMenu()
        if awake.state.isActive { awakeMenu.addItem(action("停止防止休眠") { KeepAwakeController.shared.stop() }) }
        for duration in KeepAwake.Duration.allCases {
            awakeMenu.addItem(action(duration.title) { KeepAwakeController.shared.start(duration) })
        }
        awakeMenu.addItem(.separator())
        awakeMenu.addItem(action("螢幕也保持亮著", checked: awake.keepDisplayOn) { KeepAwakeController.shared.keepDisplayOn.toggle() })
        awakeItem.submenu = awakeMenu
        menu.addItem(awakeItem)

        // 音訊輸出與麥克風
        let audio = AudioSwitchController.shared
        audio.refresh()
        let outputItem = NSMenuItem(title: "音訊輸出", action: nil, keyEquivalent: "")
        outputItem.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: nil)
        let outputMenu = NSMenu()
        for output in audio.outputs {
            let id = output.id
            outputMenu.addItem(action(output.name, checked: output.isCurrent) { AudioSwitchController.shared.select(id) })
        }
        outputItem.submenu = outputMenu
        menu.addItem(outputItem)
        if audio.micSupported {
            let mic = action(audio.micMuted ? "取消麥克風靜音" : "麥克風靜音") { AudioSwitchController.shared.toggleMic() }
            mic.image = NSImage(systemSymbolName: audio.micMuted ? "mic.slash" : "mic", accessibilityDescription: nil)
            menu.addItem(mic)
        }

        // 鍵盤清潔（啟用了才有）
        if settings.isInstalled(.keyboardCleaning) {
            let seconds = settings.keyboardCleaningSeconds
            let clean = action("開始鍵盤清潔") { _ = KeyboardCleaningController.shared.start(seconds: seconds) }
            clean.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            menu.addItem(clean)
        }

        // 擴充功能開關
        menu.addItem(.separator())
        let featuresItem = NSMenuItem(title: "擴充功能", action: nil, keyEquivalent: "")
        featuresItem.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        let featuresMenu = NSMenu()
        for feature in ExtensionFeature.allCases where feature != .quickMenu {
            let on = settings.isInstalled(feature)
            featuresMenu.addItem(action(feature.title, checked: on) { [weak settings] in settings?.setInstalled(feature, !on) })
        }
        featuresItem.submenu = featuresMenu
        menu.addItem(featuresItem)

        menu.addItem(.separator())
        menu.addItem(action("設定…") { [weak self] in self?.openSettings?(nil) })
        menu.addItem(action("結束\(AppEdition.appName)") { NSApp.terminate(nil) })
    }

    /// 用閉包當動作的選單項目
    private func action(_ title: String, checked: Bool = false, _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        item.state = checked ? .on : .off
        return item
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func run() {
        MainActor.assumeIsolated { handler() }
    }
}
