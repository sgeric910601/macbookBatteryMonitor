import AppKit
import SwiftUI

/// `macbookBatteryMonitor --snapshot <資料夾>`：在螢幕外把面板各分頁和選單列圖示畫成 PNG，開發時檢查版面用
@MainActor
enum SnapshotCommand {
    static func run(directory: String) {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store = BatteryStore()
        let ui = PanelState()
        ui.isVisible = true
        store.panelVisible = true
        store.refresh()
        store.refreshHealth()
        store.resolveUnpluggedDateIfNeeded()
        store.backfillHistory()
        // 只讀取系統充電上限，不會寫入
        store.chargeLimit.onChange = { store.refresh() }
        store.chargeLimit.refresh()
        store.setHardwareSampling(active: true)
        wait(1.1)
        store.setHardwareSampling(active: true)
        wait(1.1)

        let pages: [(String, () -> Void)] = [
            ("details", { ui.page = .main; ui.tab = .details }),
            ("history", { ui.page = .main; ui.tab = .history }),
            ("processes", { ui.page = .main; ui.tab = .processes }),
            // 周邊設備用示範數據，才看得到有設備時的版面
            ("peripherals", { ui.page = .main; ui.tab = .peripherals; store.peripherals.loadPreview() }),
            ("settings", { ui.notificationsBlocked = false; ui.page = .settings }),
            // 點新版本通知打開設定時，捲到「更新」卡片
            ("settings-update", { ui.page = .main; ui.scrollTarget = UpdateCard.anchor; ui.page = .settings }),
            // macOS 關閉了 App 的通知時的提醒
            ("settings-notifications-off", {
                ui.page = .main; ui.notificationsBlocked = true; ui.scrollTarget = UpdateCard.anchor; ui.page = .settings
            }),
            ("display-items", { ui.notificationsBlocked = false; ui.page = .displayItems }),
        ]
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            for (name, configure) in pages {
                configure()
                let view = RootView(store: store, settings: .shared, ui: ui)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, appearance == .aqua ? .light : .dark)
                render(view, appearance: appearance, settle: name == "processes" ? 3 : 0.5,
                       to: dir.appendingPathComponent("panel-\(name)-\(suffix).png"))
            }
            ui.page = .main
            for chip in [false, true] {
                ui.powerFlowLevel = chip ? .chip : .components
                store.setHardwareSampling(active: true)
                wait(1.1)
                store.setHardwareSampling(active: true)
                let view = RootView(store: store, settings: .shared, ui: ui)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, appearance == .aqua ? .light : .dark)
                render(view, appearance: appearance, settle: 0.3,
                       to: dir.appendingPathComponent("panel-hardware-\(chip ? "chip" : "components")-\(suffix).png"))
            }
            ui.powerFlowLevel = .overview
            renderComponentFlows(appearance: appearance, directory: dir, suffix: suffix)
            renderPowerFlows(appearance: appearance, to: dir.appendingPathComponent("power-flows-\(suffix).png"))
            renderStatusIcons(appearance: appearance, to: dir.appendingPathComponent("icons-\(suffix).png"))
            renderStatusIcons(appearance: appearance, to: dir.appendingPathComponent("icons-percent-time-\(suffix).png"), showsPercent: true)
        }
        store.setHardwareSampling(active: false)
        renderMonitors(directory: dir)
        renderUpdateCard(directory: dir)
        renderPluggedPanels(directory: dir)
        renderDesktopPanels(directory: dir)
        print("已輸出到 \(dir.path)")
    }

    /// 接著電源時（充電中、已達充電上限）的主面板，用示範數據
    private static func renderPluggedPanels(directory dir: URL) {
        let store = BatteryStore()
        let ui = PanelState()
        ui.isVisible = true
        for (name, atLimit) in [("charging", false), ("limit", true)] {
            store.loadPluggedPreview(atLimit: atLimit)
            let view = RootView(store: store, settings: .shared, ui: ui)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .dark)
            render(view, appearance: .darkAqua, settle: 0.3, to: dir.appendingPathComponent("panel-plugged-\(name)-dark.png"))
        }
    }

    /// 桌上型 Mac（沒有電池）的主面板，用示範數據
    private static func renderDesktopPanels(directory dir: URL) {
        let store = BatteryStore()
        let ui = PanelState()
        ui.isVisible = true
        store.loadDesktopPreview()
        for (name, tab, level) in [("details", BottomTab.details, PowerFlowLevel.overview), ("history", .history, .chip)] {
            ui.tab = tab
            ui.powerFlowLevel = level
            let view = RootView(store: store, settings: .shared, ui: ui)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .dark)
            render(view, appearance: .darkAqua, settle: 0.4, to: dir.appendingPathComponent("panel-desktop-\(name)-dark.png"))
        }
    }

    /// 設定頁的「更新」卡片在各狀態下的樣子
    private static func renderUpdateCard(directory dir: URL) {
        let updater = Updater()
        let release = ReleaseInfo(tag: "v9.9.9", version: [9, 9, 9],
                                  pageURL: URL(string: "https://github.com/sgeric910601/macbookBatteryMonitor/releases")!,
                                  assetName: "x.zip", assetURL: URL(string: "https://github.com/x.zip")!, assetSize: 0, checksumURL: nil)
        var beta = release
        beta.tag = "v9.9.9-beta.1"
        beta.beta = 1
        let states: [(String, Updater.State, Bool)] = [
            ("idle", .idle, false), ("uptodate", .upToDate, false), ("available", .available(release), false),
            ("beta", .available(beta), false), ("beta-confirm", .available(beta), true),
            ("downloading", .downloading(release), false), ("failed", .failed("無法連線到 GitHub，請稍後再試"), false)]
        for (name, state, confirming) in states {
            updater.loadPreview(state)
            let ui = PanelState()
            ui.confirmingBetaInstall = confirming
            let view = UpdateCard(updater: updater, settings: .shared, ui: ui)
                .padding(14)
                .frame(width: 380)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .dark)
            render(view, appearance: .darkAqua, settle: 0.2, to: dir.appendingPathComponent("update-\(name)-dark.png"))
        }
    }

    /// 系統監控模組：四個面板與選單列小圖
    private static func renderMonitors(directory dir: URL) {
        let cpu = CPUMonitor(), memory = MemoryMonitor(), disk = DiskMonitor(), network = NetworkMonitor()
        let cpuTop = TopStream(arguments: ["-l", "0", "-s", "1", "-o", "cpu", "-stats", "pid,command,cpu", "-n", "15"]) { cpu.receiveTop($0) }
        let memoryTop = TopStream(arguments: ["-l", "0", "-s", "1", "-o", "mem", "-stats", "pid,command,mem", "-n", "15"]) { memory.receiveTop($0) }
        cpuTop.start()
        memoryTop.start()
        cpu.setThermalActive(true)
        // 磁碟健康狀態（SMART）平常只在面板開著時查，截圖時也要先開始查，不然會停在「讀取中…」
        disk.setHealthActive(true)
        for _ in 0..<4 {
            let now = Date()
            cpu.sample(at: now)
            memory.sample(at: now)
            disk.sample(at: now)
            network.sample(at: now)
            wait(1)
        }
        cpuTop.stop()
        memoryTop.stop()
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            for kind in MonitorKind.allCases {
                let view = MonitorPanel(kind: kind, cpu: cpu, memory: memory, disk: disk, network: network, onSettings: {})
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, appearance == .aqua ? .light : .dark)
                render(view, appearance: appearance, settle: 0.3, to: dir.appendingPathComponent("monitor-\(kind.rawValue)-\(suffix).png"))
            }
            let views = MonitorDebug.menuBarImages(cpu: cpu, memory: memory, disk: disk, network: network).map { image -> NSView in
                let button = NSButton(image: image, target: nil, action: nil)
                button.isBordered = false
                return button
            }
            let stack = NSStackView(views: views)
            stack.spacing = 14
            stack.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
            stack.wantsLayer = true
            stack.appearance = NSAppearance(named: appearance)
            stack.layer?.backgroundColor = (appearance == .aqua ? NSColor(white: 0.93, alpha: 1) : NSColor(white: 0.12, alpha: 1)).cgColor
            let window = NSWindow(contentRect: NSRect(x: -5000, y: 0, width: 600, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = stack
            stack.setFrameSize(stack.fittingSize)
            window.orderFrontRegardless()
            wait(0.3)
            save(view: stack, to: dir.appendingPathComponent("monitors-menubar-\(suffix).png"))
            window.orderOut(nil)
        }
    }

    static func wait(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func render<V: View>(_ view: V, appearance: NSAppearance.Name, settle: TimeInterval, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: NSRect(x: -5000, y: 0, width: 380, height: 800),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.setFrameSize(hosting.fittingSize)
        window.setContentSize(hosting.fittingSize)
        window.orderFrontRegardless()
        wait(settle)
        hosting.setFrameSize(hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        save(view: hosting, to: url)
        window.orderOut(nil)
    }

    /// 固定資料可檢查充電、放電、閒置及混合供電，無須實際插拔電源。
    private static func renderPowerFlows(appearance: NSAppearance.Name, to url: URL) {
        let cases: [(String, Bool, Double)] = [
            ("充電", true, 18), ("放電", false, -12),
            ("已接電源・電池閒置", true, 0), ("變壓器與電池一起供電", true, -5),
        ]
        let view = VStack(spacing: 10) {
            ForEach(cases.indices, id: \.self) { index in
                let item = cases[index]
                let snapshot = BatterySnapshot(percent: 72, externalConnected: item.1)
                let estimates = Estimates(state: item.2 > 0 ? .charging : (item.1 ? .pluggedIdle : .discharging),
                                          batteryWatts: item.2, systemWatts: 12,
                                          adapterInputWatts: item.1 ? 12 + item.2 : nil)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0).font(.caption).foregroundStyle(.secondary)
                    PowerFlowView(s: snapshot, e: estimates)
                }
            }
        }
        .padding(14)
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, appearance == .aqua ? .light : .dark)
        render(view, appearance: appearance, settle: 0.2, to: url)
    }

    private static func renderComponentFlows(appearance: NSAppearance.Name, directory: URL, suffix: String) {
        let now = ProcessInfo.processInfo.systemUptime
        let complete = ComponentPowerSample(uptime: now, interval: 1, backlightWatts: 3,
                                            cpuWatts: 2, gpuWatts: 1, aneWatts: 0, systemWatts: 12, systemWindowAligned: true)
        var missing = complete
        missing.aneWatts = nil
        var estimated = complete
        estimated.cpuWatts = nil
        estimated.systemWindowAligned = false
        estimated.systemWindowEstimated = true
        var sampling = complete
        sampling.cpuWatts = nil
        sampling.gpuWatts = nil
        sampling.aneWatts = nil
        sampling.sampling = true
        let cases: [(String, ComponentPowerSample, Double)] = [
            ("complete", complete, 12), ("missing", missing, 12), ("estimated", estimated, 12),
            ("inconsistent", complete, 4), ("sampling", sampling, 12),
        ]
        for (name, sample, total) in cases {
            for chip in [false, true] {
                let ui = PanelState()
                ui.powerFlowLevel = chip ? .chip : .components
                let breakdown = PowerBreakdown.make(systemWatts: total, components: sample, now: now)
                let view = PowerFlowView(s: BatterySnapshot(percent: 72),
                    e: Estimates(state: .discharging, batteryWatts: -12, systemWatts: 12),
                    breakdown: breakdown, ui: ui)
                    .padding(14)
                    .frame(width: 380)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, appearance == .aqua ? .light : .dark)
                render(view, appearance: appearance, settle: 0.1,
                       to: directory.appendingPathComponent("hardware-\(name)-\(chip ? "chip" : "components")-\(suffix).png"))
            }
        }
    }

    private static func renderStatusIcons(appearance: NSAppearance.Name, to url: URL, showsPercent: Bool = false) {
        let cases: [(Int, PowerState, Bool)] = [(82, .discharging, false), (15, .discharging, true), (55, .charging, false), (80, .pluggedIdle, false), (95, .limitReached, false), (100, .full, false)]
        let stack = NSStackView(views: cases.map { pct, state, low in
            let time: String
            switch state {
            case .discharging: time = "3:25"
            case .charging: time = "1:20"
            case .full: time = "已充飽"
            case .pluggedIdle: time = "接電"
            case .limitReached: time = "已達上限"
            }
            let button = NSButton(title: showsPercent ? time : "\(pct)%", image: StatusIconRenderer.image(percent: pct, state: state, low: low, showsPercent: showsPercent), target: nil, action: nil)
            button.isBordered = false
            button.imagePosition = showsPercent ? .imageLeading : .imageTrailing
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
            return button
        })
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        stack.wantsLayer = true
        stack.appearance = NSAppearance(named: appearance)
        stack.layer?.backgroundColor = (appearance == .aqua ? NSColor(white: 0.93, alpha: 1) : NSColor(white: 0.12, alpha: 1)).cgColor
        let window = NSWindow(contentRect: NSRect(x: -5000, y: 0, width: 500, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = stack
        stack.setFrameSize(stack.fittingSize)
        window.orderFrontRegardless()
        wait(0.3)
        save(view: stack, to: url)
        window.orderOut(nil)
    }

    private static func save(view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
