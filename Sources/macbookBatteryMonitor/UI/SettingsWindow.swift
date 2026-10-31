import AppKit
import SwiftUI

/// 設定視窗左邊的分類
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    /// 選單列顯示方式、電力流向細項與詳細資訊欄位
    case display
    /// 更新頻率、省電模式、系統監控與 CPU 功耗
    case monitors
    /// 充電上限與智慧充電（只有 MacBook 有；面板也有一份智慧充電頁）
    case charging
    /// 外觀與桌面寵物（只有 MacBook 有）
    case companion
    /// 每個藍牙設備的低電量通知
    case peripherals
    /// 滑鼠與觸控板分開的捲動方向
    case input
    /// 視窗切換（取代 Cmd+Tab）：快捷鍵、外觀、要列出的視窗、例外清單
    case windowSwitcher
    case update

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "一般"
        case .display: return "顯示項目"
        case .monitors: return "監控與省電"
        case .charging: return "充電"
        case .companion: return "充電夥伴"
        case .peripherals: return "周邊設備"
        case .input: return "滑鼠與觸控板"
        case .windowSwitcher: return "視窗切換"
        case .update: return "更新"
        }
    }

    /// macOS 12 就有的符號，舊系統版本也能用
    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .display: return "menubar.rectangle"
        case .monitors: return "cpu"
        case .charging: return "battery.100.bolt"
        case .companion: return "pawprint"
        case .peripherals: return "keyboard"
        case .input: return "computermouse"
        case .windowSwitcher: return "macwindow.on.rectangle"
        case .update: return "arrow.down.circle"
        }
    }

    static func available(hasBattery: Bool) -> [SettingsSection] {
        hasBattery ? allCases : allCases.filter { $0 != .charging && $0 != .companion }
    }
}

/// 設定視窗：左邊是分類，右邊是該分類的卡片。不用 NavigationSplitView（macOS 13 起才有），舊系統版本也能用同一份
struct SettingsWindowView: View {
    let store: BatteryStore
    let settings: AppSettings
    let ui: PanelState

    private var hasBattery: Bool { store.snapshot != nil }

    private var sections: [SettingsSection] { SettingsSection.available(hasBattery: hasBattery) }

    /// 沒有電池時「充電」「充電夥伴」不在側邊欄，改顯示一般
    private var current: SettingsSection {
        sections.contains(ui.settingsSection) ? ui.settingsSection : .general
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                List(selection: Binding<SettingsSection?>(get: { current }, set: { if let section = $0 { ui.settingsSection = section } })) {
                    ForEach(sections) { section in
                        Label(section.title, systemImage: section.systemImage).tag(section)
                    }
                }
                .listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(AppEdition.appName) \(store.updater.currentVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("結束\(AppEdition.appName)") { NSApp.terminate(nil) }
                        .controlSize(.small)
                }
                .padding(12)
            }
            .frame(width: 190)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(current.title).font(.title2.weight(.semibold))
                    SettingsView(settings: settings, ui: ui, adminCPU: store.adminCPU, updater: store.updater,
                                 chargeLimit: store.chargeLimit, hasBattery: hasBattery,
                                 section: current, planActive: store.chargingPlan.isActive)
                    switch current {
                    case .display: DisplayItemsView(settings: settings, limitSlider: store.chargeLimit.supported)
                    case .charging: ChargingPlanView(store: store, settings: settings, ui: ui, embedded: true)
                    case .peripherals: PeripheralAlertsCard(store: store.peripherals, settings: settings)
                    case .windowSwitcher: WindowSwitcherSettingsView(settings: settings, ui: ui)
                    default: EmptyView()
                    }
                }
                .padding(20)
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 換分類時從最上面開始
            .id(current)
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 440, idealHeight: 600)
    }
}

/// 獨立的設定視窗。開著時 App 暫時出現在 Dock 與 Command-Tab，切到系統設定再回來也找得到；關掉後恢復成只在選單列
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: BatteryStore
    private let settings: AppSettings
    private let ui: PanelState
    private var window: NSWindow?

    init(store: BatteryStore, settings: AppSettings, ui: PanelState) {
        self.store = store
        self.settings = settings
        self.ui = ui
    }

    var isShown: Bool { window != nil }
    var frame: NSRect? { window?.frame }

    func close() {
        window?.performClose(nil)
    }

    /// section：要打開的分類；nil 時維持上次的分類
    func show(_ section: SettingsSection? = nil) {
        if let section { ui.settingsSection = section }
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let view = SettingsWindowView(store: store, settings: settings, ui: ui)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "設定"
        window.contentViewController = NSHostingController(rootView: view)
        window.setContentSize(NSSize(width: 720, height: 600))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        // 記住位置與大小
        window.setFrameAutosaveName("SettingsWindow")
        store.chargeLimit.panelOpened()
        return window
    }

    /// 從系統設定（通知、登入項目）回來時重新讀狀態
    func windowDidBecomeKey(_ notification: Notification) {
        Notifier.shared.checkBlocked { [weak self] in self?.ui.notificationsBlocked = $0 }
        ui.loginStatus = LoginItem.status
        ui.scrollTrusted = ScrollDirection.trusted
        ui.scrollRunning = ScrollDirection.shared.isRunning
        ui.inputTapRunning = InputController.shared.isRunning
    }

    func windowWillClose(_ notification: Notification) {
        guard let closed = notification.object as? NSWindow, closed === window else { return }
        window = nil
        // 等這次 delegate 回呼結束再釋放畫面
        DispatchQueue.main.async { closed.contentViewController = nil }
        NSApp.setActivationPolicy(.accessory)
    }

    /// 出現在 Dock 時選單列會顯示 App 的選單：至少要能用 ⌘W 關視窗、⌘Q 結束
    private func installMainMenu() {
        guard NSApp.mainMenu == nil else { return }
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "隱藏\(AppEdition.appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "結束\(AppEdition.appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)
        let windowMenu = NSMenu(title: "視窗")
        windowMenu.addItem(withTitle: "關閉", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "縮到最小", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
}

extension View {
    /// 設定視窗：卡片只出現在它所屬的分類
    @ViewBuilder func settingsSection(_ owner: SettingsSection, shown: SettingsSection) -> some View {
        if owner == shown { self }
    }
}
