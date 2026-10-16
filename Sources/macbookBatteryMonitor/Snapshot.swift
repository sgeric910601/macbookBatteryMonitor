import AppKit
import SwiftUI

/// `macbookBatteryMonitor --snapshot <資料夾>`：在螢幕外把面板各分頁和選單列圖示畫成 PNG，開發時檢查版面用
@MainActor
enum SnapshotCommand {
    static func run(directory: String) {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        CompanionPhoto.useBundledForScreenshots()

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
            renderSettingsWindow(store: store, ui: ui, appearance: appearance, directory: dir, suffix: suffix)
        }
        store.setHardwareSampling(active: false)
        renderMonitors(directory: dir)
        renderUpdateCard(directory: dir)
        renderChargingAppearances(directory: dir)
        renderDesktopPet(directory: dir)
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
        // 不能調整充電上限的 Mac（Intel、macOS 26 以前）：用電池與充電中各一張
        for (name, plugged) in [("battery", false), ("charging", true)] {
            if plugged { store.loadPluggedPreview(atLimit: false) } else { store.loadPreview() }
            store.chargeLimit.loadUnsupportedPreview()
            let view = RootView(store: store, settings: .shared, ui: ui)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .dark)
            render(view, appearance: .darkAqua, settle: 0.3, to: dir.appendingPathComponent("panel-no-limit-\(name)-dark.png"))
        }
        // 點充電夥伴打開的頁面：只能換外觀，並說明不支援智慧充電
        ui.page = .chargingPlan
        let plan = RootView(store: store, settings: .shared, ui: ui)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
        render(plan, appearance: .darkAqua, settle: 0.3, to: dir.appendingPathComponent("smart-charging-no-limit-dark.png"))
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

    /// 設定視窗的每個分類；一般另外畫一張 macOS 關閉了 App 通知時的提醒
    private static func renderSettingsWindow(store: BatteryStore, ui: PanelState, appearance: NSAppearance.Name,
                                             directory dir: URL, suffix: String) {
        var pages = SettingsSection.allCases.map { ($0, $0.rawValue, false) }
        pages.append((.general, "general-notifications-off", true))
        for (section, name, blocked) in pages {
            ui.settingsSection = section
            ui.notificationsBlocked = blocked
            let view = SettingsWindowView(store: store, settings: .shared, ui: ui)
                .frame(width: 720, height: section == .charging ? 1500 : 780)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, appearance == .aqua ? .light : .dark)
            render(view, appearance: appearance, settle: 0.4, to: dir.appendingPathComponent("settings-\(name)-\(suffix).png"))
        }
        ui.settingsSection = .general
        ui.notificationsBlocked = false
    }

    /// 桌面寵物：四種外觀中的三種，以及滑鼠移過去的想像框、點一下的對話框（上方與下方）
    private static func renderDesktopPet(directory dir: URL) {
        let now = Date()
        let charging = ChargingJourneyPresentation.make(percent: 62, charging: true, decision: nil, now: now)
        for (scheme, appearance) in [(ColorScheme.dark, NSAppearance.Name.darkAqua), (.light, .aqua)] {
            let view = HStack(alignment: .bottom, spacing: 18) {
                VStack(spacing: 0) {
                    DesktopPetBubbleView(text: "62%・充電中，36 分鐘後到 80%", thought: true, tailUp: false)
                    DesktopPetCompanion(presentation: charging, animated: false)
                }
                VStack(spacing: 0) {
                    DesktopPetBubbleView(text: "今天用掉 14%，補回 3%", thought: false, tailUp: false)
                    CompanionFigure(presentation: charging, appearance: .mascot, animated: false, width: 140)
                }
                VStack(spacing: 0) {
                    DesktopPetBubbleView(text: "電池健康度 91%，充過 212 次", thought: false, tailUp: false)
                    CompanionFigure(presentation: charging, appearance: .photo, animated: false, width: 140)
                }
                VStack(spacing: 0) {
                    DesktopPetCompanion(presentation: .make(percent: 80, charging: false, decision: nil, now: now), animated: false)
                    DesktopPetBubbleView(text: "80%・已達充電上限，用變壓器供電\n等待開始：明天 5:54 開始充電，明天 7:30 前到 95%",
                                         thought: false, tailUp: true)
                }
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
            .environment(\.colorScheme, scheme)
            render(view, appearance: appearance, settle: 0.3,
                   to: dir.appendingPathComponent("desktop-pet-\(scheme == .dark ? "dark" : "light").png"))
        }
    }

    /// 充電上限滑桿旁的四種外觀（充電夥伴、電池夥伴、電量條、照片）在各種排程狀態下的樣子
    private static func renderChargingAppearances(directory dir: URL) {
        let now = Date()
        let deadline = now.addingTimeInterval(9 * 3600)
        func decision(_ phase: ChargingPlanPhase) -> ChargingPlanDecision {
            ChargingPlanDecision(phase: phase, targetPercent: 100, deadline: deadline, startAt: deadline.addingTimeInterval(-7200),
                                 wakeAt: nil, desiredLimit: 100, requiredMinutes: 95)
        }
        let states: [(String, ChargingJourneyPresentation)] = [
            ("沒有排程", .make(percent: 78, charging: false, decision: nil, now: now)),
            ("等待", .make(percent: 80, charging: false, decision: decision(.waiting), now: now)),
            ("充電中", .make(percent: 86, charging: true, decision: decision(.charging), now: now)),
            ("已準備好", .make(percent: 100, charging: false, decision: decision(.ready), now: now)),
            ("可能延遲", .make(percent: 60, charging: true, decision: decision(.late), now: now)),
        ]
        let limit = SystemChargeLimit()
        limit.loadPreview(limit: 80)
        let view = HStack(alignment: .top, spacing: 16) {
            ForEach(ChargingAppearance.allCases) { appearance in
                VStack(alignment: .leading, spacing: 10) {
                    Text(appearance.title).font(.headline)
                    ForEach(states, id: \.0) { name, presentation in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.caption2).foregroundStyle(.tertiary)
                            ChargingJourneyView(presentation: presentation, appearance: appearance, animated: false, open: {}) {
                                ChargeLimitSlider(control: limit)
                            }
                        }
                    }
                }
                .frame(width: 330)
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .dark)
        render(view, appearance: .darkAqua, settle: 0.3, to: dir.appendingPathComponent("charging-appearances-dark.png"))
    }

    /// 設定視窗的「更新」卡片在各狀態下的樣子
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
