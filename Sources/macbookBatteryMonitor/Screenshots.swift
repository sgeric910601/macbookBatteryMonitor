import AppKit
import SwiftUI

/// `--screenshots <資料夾>`：用示範數據畫出只看電池、電池＋系統監控、省電模式、周邊設備與桌上型 Mac 的介紹圖（README 與版本說明用），不含使用者的真實資料
@MainActor
enum ScreenshotCommand {
    static func run(directory: String) {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date()
        let store = BatteryStore()
        store.loadPreview(now: now)
        let ui = PanelState()
        ui.isVisible = true
        ui.tab = .details
        let cpu = CPUMonitor(), memory = MemoryMonitor(), disk = DiskMonitor(), network = NetworkMonitor()
        cpu.loadPreview(now: now)
        memory.loadPreview(now: now)
        disk.loadPreview(now: now)
        network.loadPreview(now: now)

        let batteryIcon = StatusIconRenderer.image(percent: 78, state: .discharging, low: false, showsPercent: false)
        let battery = MenuItem(image: batteryIcon, text: "78%")
        let modules = MonitorDebug.menuBarImages(cpu: cpu, memory: memory, disk: disk, network: network).map { MenuItem(image: $0, text: nil) }

        let batteryEdition = Showcase(menuItems: [battery]) {
            Popover { RootView(store: store, settings: .shared, ui: ui) }
        }
        SnapshotCommand.render(batteryEdition, appearance: .darkAqua, settle: 0.6, to: dir.appendingPathComponent("edition-battery.png"))

        let statusEdition = Showcase(menuItems: modules + [battery]) {
            ForEach(MonitorKind.allCases) { kind in
                Popover { MonitorPanel(kind: kind, cpu: cpu, memory: memory, disk: disk, network: network, onSettings: {}) }
            }
        }
        SnapshotCommand.render(statusEdition, appearance: .darkAqua, settle: 0.6, to: dir.appendingPathComponent("edition-status.png"))

        // 省電模式：主面板改用靜態電力流向；畫完還原使用者原本的設定
        let settings = AppSettings.shared
        let previous = settings.powerSaving
        settings.powerSaving = true
        let powerSaving = Showcase(menuItems: [battery]) {
            Popover { RootView(store: store, settings: settings, ui: ui) }
        }
        SnapshotCommand.render(powerSaving, appearance: .darkAqua, settle: 0.6, to: dir.appendingPathComponent("power-saving.png"))
        settings.powerSaving = previous

        // 周邊設備分頁（示範設備）
        store.peripherals.loadPreview(now: now)
        ui.tab = .peripherals
        let peripherals = Showcase(menuItems: [battery]) {
            Popover { RootView(store: store, settings: settings, ui: ui) }
        }
        SnapshotCommand.render(peripherals, appearance: .darkAqua, settle: 0.6, to: dir.appendingPathComponent("peripherals.png"))
        ui.tab = .details

        // 智慧充電：接著電源維持保養上限 80%、明天 7:30 前充到 100%，旁邊是今日回顧與智慧充電頁
        let planStore = BatteryStore()
        planStore.loadPluggedPreview(now: now, atLimit: true)
        planStore.loadChargingPlanPreview(now: now)
        let planUI = PanelState()
        planUI.isVisible = true
        planUI.tab = .today
        let pagesUI = PanelState()
        pagesUI.isVisible = true
        pagesUI.page = .chargingPlan
        let pluggedIcon = StatusIconRenderer.image(percent: 80, state: .limitReached, low: false, showsPercent: false)
        let smartCharging = Showcase(menuItems: [MenuItem(image: pluggedIcon, text: "80%")]) {
            Popover { RootView(store: planStore, settings: settings, ui: planUI) }
            Popover { ChargingPlanView(store: planStore, settings: settings, ui: pagesUI).frame(width: 380) }
        }
        SnapshotCommand.render(smartCharging, appearance: .darkAqua, settle: 0.6, to: dir.appendingPathComponent("smart-charging.png"))

        // 桌上型 Mac（沒有電池）：選單列電腦圖示加系統耗電，面板是系統耗電與耗電細項
        let desktopStore = BatteryStore()
        desktopStore.loadDesktopPreview(now: now)
        let desktopUI = PanelState()
        desktopUI.isVisible = true
        let desktopIcon = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) ?? NSImage()
        desktopIcon.isTemplate = true
        let desktop = Showcase(menuItems: [MenuItem(image: desktopIcon, text: "38 W")]) {
            Popover { RootView(store: desktopStore, settings: settings, ui: desktopUI) }
        }
        SnapshotCommand.render(desktop, appearance: .darkAqua, settle: 0.6, to: dir.appendingPathComponent("desktop.png"))
        print("已輸出到 \(dir.path)")
    }

    private struct MenuItem: Identifiable {
        let id = UUID()
        let image: NSImage
        let text: String?
    }

    /// 上方模擬選單列，下方並排面板
    private struct Showcase<Panels: View>: View {
        let menuItems: [MenuItem]
        @ViewBuilder var panels: Panels

        var body: some View {
            VStack(alignment: .trailing, spacing: 14) {
                HStack(spacing: 16) {
                    ForEach(menuItems) { item in
                        HStack(spacing: 4) {
                            if let text = item.text {
                                Text(text).font(.system(size: 13)).monospacedDigit()
                            }
                            Image(nsImage: item.image)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.55)))
                HStack(alignment: .top, spacing: 18) {
                    panels
                }
            }
            .padding(24)
            .background(LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.30), Color(red: 0.08, green: 0.09, blue: 0.13)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .environment(\.colorScheme, .dark)
        }
    }

    /// 模擬彈出面板的外觀
    private struct Popover<Content: View>: View {
        @ViewBuilder var content: Content

        var body: some View {
            content
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
        }
    }
}
