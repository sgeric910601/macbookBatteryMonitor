import AppKit
import Observation
import SwiftUI

/// 設定視窗的頁面
enum SettingsV2Page: String, CaseIterable, Identifiable {
    case general, menuBar, monitor, power
    case charging, companion, peripherals
    case keyboard, mouse, windows, quickMenu, network, features
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "一般"
        case .menuBar: return "選單列"
        case .monitor: return "系統監控"
        case .power: return "省電與睡眠"
        case .charging: return "充電"
        case .companion: return "充電夥伴"
        case .peripherals: return "周邊設備"
        case .keyboard: return "鍵盤"
        case .mouse: return "滑鼠與觸控板"
        case .windows: return "視窗與 Dock"
        case .quickMenu: return "貓咪快捷選單"
        case .network: return "網路與螢幕"
        case .features: return "功能管理"
        case .system: return "權限與登入項目"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .menuBar: return "menubar.rectangle"
        case .monitor: return "cpu"
        case .power: return "moon.zzz"
        case .charging: return "battery.100.bolt"
        case .companion: return "pawprint"
        case .peripherals: return "headphones"
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .windows: return "dock.rectangle"
        case .quickMenu: return "cat"
        case .network: return "sun.max.fill"
        case .features: return "square.grid.2x2"
        case .system: return "lock.shield"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .menuBar: return .blue
        case .monitor: return .orange
        // 黃色上的白字看不清楚：用深一點的琥珀色
        case .power, .network: return Color(red: 0.86, green: 0.6, blue: 0.1)
        case .charging: return .green
        case .companion: return .pink
        case .peripherals: return .purple
        case .keyboard, .mouse: return .cyan
        case .windows: return .mint
        case .quickMenu: return .pink
        case .features: return .indigo
        case .system: return .teal
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "App 圖示、通知、開機啟動、更新與設定備份"
        case .menuBar: return "選單列的電池圖示與面板裡的項目"
        case .monitor: return "選單列的系統監控與警示"
        case .power: return "更新頻率、省電與睡眠"
        case .charging: return "充電上限與智慧充電"
        case .companion: return "充電夥伴的外觀與桌面寵物"
        case .peripherals: return "藍牙設備的低電量通知與目前連著的裝置"
        case .keyboard: return "中文輸入法、防誤觸與鍵盤清潔"
        case .mouse: return "捲動方向與滑鼠側鍵"
        case .windows: return "視窗切換、吸附、綠色按鈕、Finder 加強、Dock 點擊"
        case .quickMenu: return "選單列的貓咪圖示，以及面板上要放哪些項目"
        case .network: return "Port 管理、網路測速與內建 XDR 螢幕的額外增亮"
        case .features: return "啟用或停用擴充功能"
        case .system: return "用到的系統權限與登入時自動啟動的項目"
        }
    }

    /// 這頁的擴充功能（每個一張卡，標題列直接開關）
    var features: [ExtensionFeature] {
        switch self {
        case .keyboard: return [.inputMethod, .quitGuard, .keyboardCleaning]
        case .mouse: return [.scrollDirection, .mouseButtons]
        case .windows: return [.windowSwitcher, .lastWindowQuit, .dockClick, .greenButton, .windowSnap, .finderKeys]
        case .quickMenu: return [.quickMenu, .audioSwitch, .clipboardHistory]
        case .network: return [.portManager, .speedTest, .xdrBrightness]
        default: return []
        }
    }

    /// 側邊欄：基本、電池（沒有電池時只剩周邊設備）、擴充功能、最下面的權限與登入項目。
    /// 擴充功能的頁面一直都在：每個功能在自己的卡片上就能打開，不用先去功能管理
    static func sidebar(hasBattery: Bool) -> [(title: String, pages: [SettingsV2Page])] {
        [
            ("基本", [.general, .menuBar, .monitor, .power]),
            ("電池", hasBattery ? [.charging, .companion, .peripherals] : [.peripherals]),
            ("擴充功能", [.keyboard, .mouse, .windows, .quickMenu, .network, .features]),
            ("系統", [.system]),
        ]
    }

    /// 從 SettingsSection 打開（例如貓咪面板的「更多設定…」、權限提示）
    init(_ old: SettingsSection) {
        switch old {
        case .general, .update: self = .general
        case .display: self = .menuBar
        case .monitors: self = .monitor
        case .charging: self = .charging
        case .companion: self = .companion
        case .peripherals: self = .peripherals
        case .input: self = .keyboard
        case .windowSwitcher, .windows: self = .windows
        case .startup, .permissions: self = .system
        case .features: self = .features
        case .xdrBrightness: self = .network
        }
    }
}

/// 只裝 Command Line Tools 時 @State 不一定可用：目前的頁面放在控制器持有的物件裡
@MainActor
@Observable
final class SettingsV2State {
    var page: SettingsV2Page = .general
    /// 展開中的「進階」區塊
    var expanded: Set<String> = []
}

struct SettingsV2WindowView: View {
    let store: BatteryStore
    let settings: AppSettings
    let ui: PanelState
    let state: SettingsV2State
    let startupItems: StartupItemsManager

    private var hasBattery: Bool { store.snapshot != nil }
    private var groups: [(title: String, pages: [SettingsV2Page])] {
        SettingsV2Page.sidebar(hasBattery: hasBattery)
    }
    /// 沒有電池時的電池頁不在側邊欄：改顯示一般
    private var current: SettingsV2Page {
        groups.flatMap(\.pages).contains(state.page) ? state.page : .general
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    // 通知可能被關掉，所以每一頁都顯示：使用者才知道按鍵與滑鼠功能為什麼沒有作用
                    if ui.inputPaused, ExtensionFeature.blockingTap.contains(where: settings.isInstalled) {
                        Card {
                            Label("無法確認「輔助使用」權限，按鍵與滑鼠相關功能已暫停。請到系統設定 → 隱私權與安全性 →「輔助使用」（macOS 27 起叫「裝置控制和資料取用」）確認已允許\(AppEdition.appName)；權限恢復後會自動恢復，或重新開啟 App。",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    content
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(current)
            .environment(\.settingsV2Tint, current.tint)
            .toggleStyle(V2ToggleStyle(tint: current.tint))
            .buttonStyle(V2ButtonStyle(tint: current.tint))
            .tint(current.tint)
        }
        .frame(minWidth: 700, idealWidth: 800, minHeight: 480, idealHeight: 640)
        // 每次換頁都重讀：通知是否被關、登入項目狀態可能在系統設定裡改過
        .onAppear(perform: refreshSystemState)
        .onChange(of: current) { refreshSystemState() }
    }

    private func refreshSystemState() {
        Notifier.shared.checkBlocked { ui.notificationsBlocked = $0 }
        ui.loginStatus = LoginItem.status
    }

    private var sidebar: some View {
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
                        ForEach(group.pages) { page in
                            SettingsV2SidebarRow(page: page, selected: page == current) { state.page = page }
                        }
                    }
                }
                .padding(10)
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(AppEdition.appName).font(.caption.weight(.semibold))
                    Text("版本 \(store.updater.currentVersion)").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(V2ButtonStyle(tint: .red))
                .help("結束\(AppEdition.appName)")
                .accessibilityLabel("結束\(AppEdition.appName)")
            }
            .padding(12)
        }
        .frame(width: 214)
        .background(Color.primary.opacity(0.025))
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconTile(symbol: current.systemImage, tint: current.tint, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(current.title).font(.title2.weight(.semibold))
                Text(current.subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder private var content: some View {
        switch current {
        case .menuBar:
            SettingsV2MenuBarPage(settings: settings, hasBattery: hasBattery, state: state)
            DisplayItemsView(settings: settings, limitSlider: store.chargeLimit.supported)
        case .general:
            SettingsV2GeneralPage(settings: settings, ui: ui, updater: store.updater, hasBattery: hasBattery, state: state)
        case .monitor:
            SettingsV2MonitorPage(settings: settings, adminCPU: store.adminCPU, hasBattery: hasBattery, state: state)
        case .power:
            SettingsV2PowerPage(settings: settings, hasBattery: hasBattery)
        case .charging:
            SettingsView(chargeLimit: store.chargeLimit, hasBattery: hasBattery, planActive: store.chargingPlan.isActive)
            ChargingPlanView(store: store, settings: settings, ui: ui, embedded: true)
        case .companion:
            SettingsV2CompanionPage(settings: settings)
        case .peripherals:
            PeripheralAlertsCard(store: store.peripherals, settings: settings)
            ConnectedDevicesCard()
        case .keyboard:
            SettingsV2KeyboardPage(settings: settings, ui: ui, state: state)
        case .mouse:
            SettingsV2MousePage(settings: settings, ui: ui, state: state)
        case .windows:
            SettingsV2WindowsPage(settings: settings, ui: ui, state: state)
        case .quickMenu:
            SettingsV2QuickMenuPage(settings: settings)
        case .network:
            V2FeatureCard(feature: .portManager, subtitle: "網路面板列出監聽中的連接埠，可以結束對應的程式", listens: "不需要權限", settings: settings) {
                V2Note("CPU、記憶體清單也可以右鍵結束 App。")
            }
            V2FeatureCard(feature: .speedTest, subtitle: "網路面板多一個測速卡片，按下才測", listens: "按下才連網", settings: settings) {
                V2Note("測一次約 20～30 秒、會用掉數百 MB 流量，連到 Apple 的測速伺服器。要在「系統監控」開著網路模組才會顯示。")
            }
            SettingsV2XDRPage(settings: settings, ui: ui, state: state)
        case .features:
            FeatureManagerView(settings: settings)
        case .system:
            PermissionsView(settings: settings)
            Text("登入時自動執行的項目").font(.headline).padding(.top, 8)
            StartupItemsGate(settings: settings, manager: startupItems)
        }
    }
}

/// 側邊欄的一列：選到時是柔和的色塊
private struct SettingsV2SidebarRow: View {
    let page: SettingsV2Page
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                IconTile(symbol: page.systemImage, tint: page.tint, size: 26)
                Text(page.title)
                    .fontWeight(selected ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? page.tint.opacity(0.2) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
