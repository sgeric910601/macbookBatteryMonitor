import AppKit
import SwiftUI

/// 從面板、選單等地方打開設定時指定的分類；設定視窗用 SettingsV2Page(section) 換成對應的頁面
enum SettingsSection: String, CaseIterable {
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
    /// 登入時自動啟動的項目（擴充功能「登入項目管理」，啟用了才出現）
    case startup
    /// 用到的系統權限與狀態
    case permissions
    case update
    /// 擴充功能組最後一項：加入或移除擴充功能
    case features
}

/// 獨立的設定視窗。開著時 App 暫時出現在 Dock 與 Command-Tab，切到系統設定再回來也找得到；關掉後恢復成只在選單列
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: BatteryStore
    private let settings: AppSettings
    private let ui: PanelState
    private var window: NSWindow?
    /// 設定視窗目前的頁面
    private let v2State = SettingsV2State()
    private let v2StartupItems = StartupItemsManager()

    init(store: BatteryStore, settings: AppSettings, ui: PanelState) {
        self.store = store
        self.settings = settings
        self.ui = ui
    }

    var isShown: Bool { window != nil }
    /// 目前的頁面（selftest 印出用）
    var pageTitle: String { v2State.page.title }
    var frame: NSRect? { window?.frame }

    func close() {
        window?.performClose(nil)
    }

    /// section：要打開的分類；nil 時維持上次的分類
    func show(_ section: SettingsSection? = nil) {
        show(page: section.map(SettingsV2Page.init))
    }

    func show(page: SettingsV2Page?) {
        if let page { v2State.page = page }
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let view = SettingsV2WindowView(store: store, settings: settings, ui: ui, state: v2State, startupItems: v2StartupItems)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "設定"
        window.contentViewController = NSHostingController(rootView: view)
        window.setContentSize(NSSize(width: 720, height: 780))
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

/// 圓角方塊裡的白色圖示（側邊欄與頁首）
struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 22
    /// 設定視窗用平面單色、圖形大一點；面板等沒有主題色的地方維持漸層
    @Environment(\.settingsV2Tint) private var v2Tint

    var body: some View {
        if v2Tint != nil {
            // 新版：圖形縮放到方塊內 64% 的範圍裡（寬的圖形例如電池也不會碰到邊緣），平面單色
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: size * 0.64, height: size * 0.64)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(tint))
                .accessibilityHidden(true)
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(tint.gradient))
                .accessibilityHidden(true)
        }
    }
}

/// 設定 →「周邊設備」：目前連著的外接螢幕、USB 與 Thunderbolt 裝置。打開這頁時才讀，按「重新整理」再讀一次
struct ConnectedDevicesCard: View {
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
                        Image(systemName: Self.symbol(item.kind)).frame(width: 18).foregroundStyle(.secondary).modifier(V2ItemIcon()).accessibilityHidden(true)
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
