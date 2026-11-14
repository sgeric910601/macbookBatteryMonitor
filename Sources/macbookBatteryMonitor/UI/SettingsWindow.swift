import AppKit
import SwiftUI

/// 設定視窗左邊的分類
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case xdrBrightness
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
    /// 視窗與 Dock 的其他擴充功能（關閉最後視窗時結束 App 等）
    case windows
    /// 登入時自動啟動的項目
    case startup
    /// 用到的系統權限與狀態
    case permissions
    case update
    /// 擴充功能組最後一項：加入或移除擴充功能
    case features

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "一般"
        case .xdrBrightness: return "XDR 額外增亮"
        case .display: return "顯示項目"
        case .monitors: return "監控與省電"
        case .charging: return "充電"
        case .companion: return "充電夥伴"
        case .peripherals: return "周邊設備"
        case .input: return "滑鼠、觸控板與鍵盤"
        case .windowSwitcher: return "視窗切換"
        case .windows: return "視窗與 Dock"
        case .startup: return "登入項目"
        case .permissions: return "權限"
        case .update: return "更新"
        case .features: return "功能管理"
        }
    }

    /// macOS 12 就有的符號，舊系統版本也能用
    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .xdrBrightness: return "sun.max.fill"
        case .display: return "menubar.rectangle"
        case .monitors: return "cpu"
        case .charging: return "battery.100.bolt"
        case .companion: return "pawprint"
        case .peripherals: return "keyboard"
        case .input: return "computermouse"
        case .windowSwitcher: return "macwindow.on.rectangle"
        case .windows: return "dock.rectangle"
        case .startup: return "power"
        case .permissions: return "lock.shield"
        case .update: return "arrow.down.circle"
        case .features: return "square.grid.2x2"
        }
    }

    /// 側邊欄與頁首圖示方塊的顏色
    var tint: Color {
        switch self {
        case .general: return .gray
        case .xdrBrightness: return .yellow
        case .display: return .blue
        case .monitors: return .orange
        case .startup: return .indigo
        case .permissions: return .teal
        case .charging: return .green
        case .companion: return .pink
        case .peripherals: return .purple
        case .input: return .cyan
        case .windowSwitcher: return .blue
        case .windows: return .mint
        case .features: return .indigo
        case .update: return .green
        }
    }

    /// 頁首標題下的一行說明
    var subtitle: String {
        switch self {
        case .general: return "App 圖示、通知、開機啟動與設定備份"
        case .xdrBrightness: return "內建 XDR 螢幕增亮與亮度鍵自動啟用"
        case .display: return "選單列的顯示方式與面板裡的項目"
        case .monitors: return "更新頻率、省電與系統監控"
        case .startup: return "登入時自動啟動的項目與它們的來歷"
        case .permissions: return "這個 App 用到的系統權限與狀態"
        case .charging: return "充電上限與智慧充電"
        case .companion: return "充電夥伴的外觀與桌面寵物"
        case .peripherals: return "藍牙設備的低電量通知與目前連著的裝置"
        case .input: return "捲動、滑鼠側鍵、中文輸入法、防誤觸與鍵盤清潔"
        case .windowSwitcher: return "取代 Cmd+Tab 的視窗切換"
        case .windows: return "視窗吸附、綠色按鈕放大、Finder 加強、關閉最後視窗、Dock 點擊"
        case .features: return "啟用或停用擴充功能"
        case .update: return "版本、自動檢查與一鍵更新"
        }
    }

    /// 擴充功能所在的分類。「滑鼠、觸控板與鍵盤」放捲動方向與中文輸入法，加入其中一個就出現
    /// 擴充功能的設定在哪一頁；只在面板上有按鈕、沒有設定的功能（音訊切換）為 nil
    static func section(for feature: ExtensionFeature) -> SettingsSection? {
        switch feature {
        case .scrollDirection, .inputMethod, .quitGuard, .keyboardCleaning, .mouseButtons: return .input
        case .windowSwitcher: return .windowSwitcher
        case .xdrBrightness: return .xdrBrightness
        case .lastWindowQuit, .dockClick, .greenButton, .windowSnap, .finderKeys: return .windows
        case .audioSwitch, .quickMenu, .portManager, .clipboardHistory, .speedTest, .startupItems: return nil
        }
    }

    /// 側邊欄的分組：基本、電池（沒有電池時只剩周邊設備）、擴充功能（已加入的功能，最後是功能管理）
    /// 最後一組「關於」只有「更新」，單獨放在最下面
    static func sidebar(hasBattery: Bool, isInstalled: (ExtensionFeature) -> Bool) -> [(title: String, sections: [SettingsSection])] {
        [
            ("基本", [.general, .display, .monitors, .startup, .permissions]),
            ("電池", hasBattery ? [.charging, .companion, .peripherals] : [.peripherals]),
            ("擴充功能", ExtensionFeature.allCases.filter(isInstalled).compactMap(section(for:)).reduce(into: []) { if !$0.contains($1) { $0.append($1) } } + [.features]),
            ("關於", [.update]),
        ]
    }
}

/// 設定視窗：左邊是分類，右邊是該分類的卡片。不用 NavigationSplitView（macOS 13 起才有），舊系統版本也能用同一份
struct SettingsWindowView: View {
    let store: BatteryStore
    let settings: AppSettings
    let ui: PanelState
    @State private var startupItems = StartupItemsManager()

    private var hasBattery: Bool { store.snapshot != nil }

    private var groups: [(title: String, sections: [SettingsSection])] {
        SettingsSection.sidebar(hasBattery: hasBattery, isInstalled: settings.isInstalled)
    }
    private var sections: [SettingsSection] { groups.flatMap(\.sections) }

    /// 沒有電池時「充電」「充電夥伴」不在側邊欄，移除的擴充功能也不在，改顯示一般
    private var current: SettingsSection {
        sections.contains(ui.settingsSection) ? ui.settingsSection : .general
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(groups, id: \.title) { group in
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.top, group.title == groups.first?.title ? 4 : 14)
                                .padding(.bottom, 2)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.sections) { section in
                                SidebarRow(section: section, selected: section == current) { ui.settingsSection = section }
                            }
                        }
                    }
                    .padding(10)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(AppEdition.appName) \(store.updater.currentVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("結束\(AppEdition.appName)") { NSApp.terminate(nil) }
                        .controlSize(.small)
                }
                .padding(12)
            }
            .frame(width: 214)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        IconTile(symbol: current.systemImage, tint: current.tint, size: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(current.title).font(.title2.weight(.semibold))
                            Text(current.subtitle).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 4)
                    // 通知可能被關掉，所以每一頁都顯示：使用者才知道按鍵與滑鼠功能為什麼沒有作用
                    if ui.inputPaused {
                        Label("無法確認「輔助使用」權限，按鍵與滑鼠相關功能已暫停。請到系統設定 → 隱私權與安全性 →「輔助使用」（macOS 27 起叫「裝置控制和資料取用」）確認已允許\(AppEdition.appName)；權限恢復後會自動恢復，或重新開啟 App。",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // 登入項目分頁沒有 SettingsView 的卡片，不放進去，否則隱藏的卡片之間的間距會把標題與內容撐開
                    if current != .startup {
                        SettingsView(settings: settings, ui: ui, adminCPU: store.adminCPU, updater: store.updater,
                                     chargeLimit: store.chargeLimit, hasBattery: hasBattery,
                                     section: current, planActive: store.chargingPlan.isActive)
                    }
                    switch current {
                    case .display: DisplayItemsView(settings: settings, limitSlider: store.chargeLimit.supported)
                    case .charging: ChargingPlanView(store: store, settings: settings, ui: ui, embedded: true)
                    case .peripherals:
                        PeripheralAlertsCard(store: store.peripherals, settings: settings)
                        ConnectedDevicesCard()
                    case .windowSwitcher: WindowSwitcherSettingsView(settings: settings, ui: ui)
                    case .windows: WindowsSettingsView(settings: settings, ui: ui)
                    case .startup: StartupItemsGate(settings: settings, manager: startupItems)
                    case .features: FeatureManagerView(settings: settings)
                    case .permissions: PermissionsView(settings: settings)
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
        ui.shiftRunning = InputSourceFix.shared.isRunning
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

/// 圓角方塊裡的白色圖示（側邊欄與頁首）
struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(tint.gradient))
            .accessibilityHidden(true)
    }
}

/// 側邊欄的一列：選到時是柔和的色塊，不用系統的實心藍色
private struct SidebarRow: View {
    let section: SettingsSection
    let selected: Bool
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                IconTile(symbol: section.systemImage, tint: section.tint)
                Text(section.title)
                    .fontWeight(selected ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? section.tint.opacity(0.2) : hovering ? Color.primary.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 設定 →「周邊設備」：目前連著的外接螢幕、USB 與 Thunderbolt 裝置。打開這頁時才讀，按「重新整理」再讀一次
private struct ConnectedDevicesCard: View {
    @State private var items: [ConnectedDevices.Item] = []

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CardTitle("目前連著的裝置", systemImage: "cable.connector")
                    Spacer()
                    Button("重新整理") { items = ConnectedDeviceReader.read() }
                        .controlSize(.small)
                }
                if items.isEmpty {
                    Text("沒有外接螢幕、USB 或 Thunderbolt 裝置").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Image(systemName: Self.symbol(item.kind)).frame(width: 18).foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(item.name)
                        if let detail = item.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Text(Self.kindName(item.kind)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Mac 內建的元件與 USB Hub 不列。藍牙設備的電量在面板的「周邊設備」分頁。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { items = ConnectedDeviceReader.read() }
    }

    private static func symbol(_ kind: ConnectedDevices.Kind) -> String {
        switch kind {
        case .display: return "display"
        case .usb: return "cable.connector.horizontal"
        case .thunderbolt: return "bolt.horizontal"
        }
    }

    private static func kindName(_ kind: ConnectedDevices.Kind) -> String {
        switch kind {
        case .display: return "螢幕"
        case .usb: return "USB"
        case .thunderbolt: return "Thunderbolt"
        }
    }
}
