import AppKit
import IOKit.ps
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = BatteryStore()
    private let settings = AppSettings.shared
    private let ui = PanelState()
    /// CPU／GPU、記憶體、磁碟、網路模組
    private let monitors = ModuleCoordinator()
    private var statusItem: NSStatusItem!
    /// 每次打開都建立新的，關閉後整個釋放（連同視窗和 SwiftUI 畫面）
    private var popover: NSPopover?
    /// 面板開著時監聽面板外的點擊。系統的 .transient 有時不會收起面板，這是第二道保險
    private var outsideClickMonitors: [Any] = []
    private var refreshTimer: Timer?
    /// 更新頻率慢於每秒時，下一次更新前 1 秒先讀變壓器輸入（見 BatteryReader.recordAdapterInput）
    private var adapterPreReadTimer: Timer?
    private var processTimer: Timer?
    private var timers: [Timer] = []
    /// 上次畫到選單列的內容，沒變就不重畫
    private var lastStatusKey = ""
    private var sleeping = false
    private var powerTransitionTask: Task<Void, Never>?

    /// 所有資訊依設定的更新頻率更新（預設每秒，省電模式至少 2 秒）；面板關著時也一樣（插拔電源另由 IOPS 通知立即更新）。
    /// 同一個間隔也用來檢查耗電排行分頁是否顯示中，以決定要不要持續取樣
    private var interval: TimeInterval { settings.sampleInterval }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 已經有一個在執行（例如登入項目與舊的 LaunchAgent 同時啟動）就直接結束，避免兩個圖示、兩份通知
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != NSRunningApplication.current }) {
            NSApp.terminate(nil)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageTrailing
        }

        settings.onChange = { [weak self] in self?.updateStatusItem() }
        settings.onIntervalChange = { [weak self] in self?.applySampleInterval() }
        // 全新安裝：所有需要授權的東西都在第一次啟動時問完（系統監控、管理員 CPU 取樣、通知、藍牙）
        let freshInstall = settings.needsModeChoice
        if freshInstall { askForMode() }
        // 系統監控關閉時不建立任何模組圖示與計時器
        settings.onMonitorsChange = { [weak self] in self?.monitors.syncItems() }
        monitors.openSettings = { [weak self] in self?.showPopover(page: .settings) }
        monitors.start()
        store.adminCPU.authorizationChanged = { [weak self] pending in
            self?.popover?.behavior = pending ? .applicationDefined : .transient
        }
        if freshInstall { askForAdminCPU() }
        Notifier.shared.setup()
        // 藍牙權限還沒決定時 macOS 會跳出詢問（從舊版升級也會問這一次）；已經允許就直接在背景讀；拒絕過就不再問
        if !BLEBatteryReader.denied { store.peripherals.startBluetoothLE() }
        // 用新版覆蓋 App 後，自訂的 App 圖示會消失，套回使用者選的顏色
        AppIconChanger.restoreIfNeeded(settings.appIconColor)

        refresh()
        store.recordHistory()
        store.refreshHealth()
        store.resolveUnpluggedDateIfNeeded()
        store.backfillHistory()
        scheduleRefresh(every: interval)
        timers.append(repeating(every: 60) { $0.store.recordHistory() })
        timers.append(repeating(every: 6 * 3600) { $0.store.refreshHealth() })
        // 周邊設備電量變化很慢，每 60 秒查一次；面板停在周邊設備分頁時連所有藍牙設備一起查
        store.peripherals.refresh()
        // 系統充電上限：啟動時讀一次，之後由系統通知、打開面板時重新讀取；在面板上調整後立即更新選單列與面板
        store.chargeLimit.onChange = { [weak self] in self?.refresh() }
        store.chargeLimit.start()
        // 智慧充電：繼續上次的排程；精準喚醒的開關改變時排定或取消喚醒
        store.startChargingPlan()
        settings.onChargingWakeChange = { [weak self] in self?.store.syncChargingWake() }
        // 自動檢查發現新版本時發通知（可在設定 → 更新關閉），點通知打開設定的「更新」
        store.updater.onNewRelease = { [weak self] release in
            guard let self, self.settings.updateNotification else { return }
            Notifier.shared.notifyUpdate(release, currentVersion: self.store.updater.currentVersion)
        }
        Notifier.shared.onOpenUpdate = { [weak self] in
            // 點通知時前景是通知中心：先把 App 帶到前景，等通知收起來再開面板，否則面板一打開就會被當成點到外面而關閉
            NSApp.activateCompat()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                self.ui.scrollTarget = UpdateCard.anchor
                self.showPopover(page: .settings)
            }
        }
        // 自動檢查更新：啟動 15 秒後與之後每 6 小時看一次，距離上次檢查超過一天才真的連線
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.settings.autoCheckUpdates else { return }
            self.store.updater.checkIfDue()
        }
        timers.append(repeating(every: 6 * 3600) { delegate in
            guard delegate.settings.autoCheckUpdates, !delegate.sleeping else { return }
            delegate.store.updater.checkIfDue()
        })
        timers.append(repeating(every: PeripheralStore.interval) { delegate in
            guard !delegate.sleeping else { return }
            delegate.store.peripherals.refresh(includeAllBluetooth: delegate.ui.isVisible && delegate.ui.page == .main && delegate.ui.tab == .peripherals)
        })

        observePowerSourceChanges()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil
        )
        registerLoginItemIfNeeded()
        runPanelSelfTestIfRequested()
        runSizingSelfTestIfRequested()
        runUpdateSelfTestIfRequested()
    }

    /// 第一次啟動：只看電池（和以前的電池版一樣），還是另外在選單列加上系統監控
    private func askForMode() {
        let battery = BatteryReader.hasBattery
        let alert = NSAlert()
        alert.messageText = "要在選單列顯示哪些資訊？"
        alert.informativeText = (battery
            ? "「電池＋系統監控」會在選單列另外加入 CPU／GPU、記憶體、磁碟與網路圖示，並持續更新。「只看電池」只顯示電池圖示，耗電最少。"
            : "「耗電＋系統監控」會在選單列另外加入 CPU／GPU、記憶體、磁碟與網路圖示，並持續更新。「只看耗電」只顯示系統耗電圖示，耗電最少。")
            + "\n\n你可以隨時在「設定」>「系統監控」中更改。"
        alert.addButton(withTitle: battery ? "電池＋系統監控" : "耗電＋系統監控")
        alert.addButton(withTitle: battery ? "只看電池" : "只看耗電")
        NSApp.activateCompat()
        settings.chooseMode(systemMonitors: alert.runModal() == .alertFirstButtonReturn)
    }

    /// 第一次啟動：要不要開管理員 CPU 取樣（Apple 晶片的 CPU 能量計數器在部分機型不會更新）。
    /// Intel 直接由 SMC 讀 CPU 功耗，不需要
    private func askForAdminCPU() {
        guard !ChipInfo.isIntel else { return }
        let alert = NSAlert()
        alert.messageText = "要開啟「管理員 CPU 取樣」嗎？"
        alert.informativeText = """
            部分 Apple 晶片機型的 CPU 能量計數器不會更新，電力細項中的 CPU 功耗會顯示為「—」。開啟後，App 會安裝一個只讀取 CPU 功耗的系統服務，提供準確的數值。

            安裝服務需要管理員權限，按下「開啟…」後 macOS 會請你輸入管理員密碼。服務只在面板打開時取樣，閒置時會自行結束，不會讀取其他資料。

            你可以隨時在「設定」>「CPU 功耗」中關閉，關閉時會一併移除服務。
            """
        alert.addButton(withTitle: "開啟…")
        alert.addButton(withTitle: "暫不開啟")
        NSApp.activateCompat()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // 第一次 update 只記錄「啟動時的狀態」，選項從關變開才會安裝服務並跳出管理員授權
        store.adminCPU.update(active: false, enabled: false)
        settings.adminCPUSampling = true
        store.adminCPU.update(active: false, enabled: true)
    }

    /// 開發用：`--selftest-update` 檢查 GitHub 上的新版本，有就直接一鍵更新（App 會結束並由安裝程序重新開啟）
    private func runUpdateSelfTestIfRequested() {
        guard CommandLine.arguments.contains("--selftest-update") else { return }
        Task { [weak self] in
            guard let updater = self?.store.updater else { return }
            print("selftest: 目前版本 \(updater.currentVersion)，可以安裝：\(updater.canInstall)")
            await updater.check(userInitiated: true)
            print("selftest: 檢查結果 \(updater.state)")
            guard updater.available != nil else { return }
            await updater.install()
            print("selftest: 安裝結果 \(updater.state)")
        }
    }

    /// 開發用：`--selftest-panel` 會打開面板（耗電排行分頁）20 秒後自動關閉，用來確認關閉後取樣會停
    /// 開發用：`--selftest-sizing` 依序換頁，印出面板大小與內容的理想大小，確認 macOS 12 的面板會跟著內容調整
    private func runSizingSelfTestIfRequested() {
        guard CommandLine.arguments.contains("--selftest-sizing") else { return }
        let steps: [(String, (AppDelegate) -> Void)] = [
            ("打開主面板（詳細資訊）", { $0.ui.tab = .details; $0.showPopover(page: .main) }),
            ("耗電／電量歷史", { $0.ui.tab = .history }),
            ("設定頁", { $0.ui.page = .settings }),
            ("顯示項目", { $0.ui.page = .displayItems }),
            ("回到主面板", { $0.ui.page = .main }),
        ]
        for (index, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3 + Double(index) * 4) { [weak self] in
                guard let self else { return }
                step.1(self)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    let content = (self?.popover?.contentViewController as? NSHostingController<RootView>)?
                        .sizeThatFits(in: NSSize(width: 380, height: 100_000)) ?? .zero
                    let size = self?.popover?.contentSize ?? .zero
                    let fits = abs(content.height - size.height) < 2 && abs(content.width - size.width) < 2
                    print("selftest-sizing: \(step.0) 面板 \(Int(size.width))×\(Int(size.height)) 內容 \(Int(content.width))×\(Int(content.height)) \(fits ? "一致" : "不一致")")
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3 + Double(steps.count) * 4) { [weak self] in
            self?.popover?.performClose(nil)
            print("selftest-sizing: 結束")
            fflush(stdout)
        }
    }

    private func runPanelSelfTestIfRequested() {
        let hardware = CommandLine.arguments.contains("--selftest-hardware")
        guard hardware || CommandLine.arguments.contains("--selftest-panel") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            ui.tab = hardware ? .details : .processes
            ui.powerFlowLevel = hardware ? .components : .overview
            showPopover(page: .main)
            if hardware {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    self?.ui.powerFlowLevel = .chip
                    print("selftest: chip expanded")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                    self?.ui.page = .settings
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
                    print("selftest: settings sampling stopped \(self?.store.componentPower == nil)")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 11) { [weak self] in
                    self?.ui.page = .main
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 14) { [weak self] in
                    print("selftest: hardware sampling resumed \(self?.store.componentPower != nil)")
                    // 管理員 CPU 取樣開著時，確認讀得到 powermetrics 的 CPU 功耗
                    let cpu = self?.store.componentPower?.cpuWatts.map { String(format: "%.2f W", $0) } ?? "—"
                    print("selftest: cpu \(cpu)（管理員 CPU 取樣：\(self?.store.adminCPU.status ?? "")）")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 22) { [weak self] in
                    print("selftest: closed sampling stopped \(self?.store.componentPower == nil)")
                }
            }
            print("selftest: opened \(popover?.contentSize ?? .zero)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                self?.popover?.performClose(nil)
                print("selftest: closed")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.adminCPU.stop()
        store.chargingWake.stop()
        store.history.save()
    }

    // MARK: - Refresh

    private func refresh() {
        store.refresh()
        // 接電狀態改變且設定為「只在使用電池時省電」時，這裡會重排計時器；桌上型 Mac 一律視為接著電源
        if let s = store.snapshot {
            settings.onACPower = s.externalConnected
        } else if !BatteryReader.hasBattery {
            settings.onACPower = true
        }
        scheduleAdapterPreRead()
        store.setHardwareSampling(active: ui.isVisible && ui.page == .main && !sleeping)
        updateStatusItem()
        if let s = store.snapshot, let e = store.estimates {
            Notifier.shared.evaluate(s, state: e.state, settings: settings)
        }
        if let note = store.chargingPlan.takeNotification(), let plan = store.chargingPlan.plan {
            Notifier.shared.notifyChargingPlan(note, plan: plan)
        }
    }

    /// 更新頻率或省電模式改變後，所有計時器與 top 改用新的間隔
    private func applySampleInterval() {
        scheduleRefresh(every: interval)
        if processTimer != nil { scheduleProcessCheck() }
        monitors.applySampleInterval()
    }

    private func scheduleRefresh(every interval: TimeInterval) {
        refreshTimer?.invalidate()
        refreshTimer = repeating(every: interval) { $0.refresh() }
        // 誤差不超過 0.3 秒，下一次更新才配得到 1 秒前預先讀的變壓器輸入
        refreshTimer?.tolerance = min(interval * 0.2, 0.3)
    }

    private func scheduleAdapterPreRead() {
        adapterPreReadTimer?.invalidate()
        adapterPreReadTimer = nil
        guard interval > 1, !sleeping else { return }
        let timer = Timer(fire: Date().addingTimeInterval(interval - 1), interval: 0, repeats: false) { _ in
            MainActor.assumeIsolatedCompat { BatteryReader.recordAdapterInput() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        adapterPreReadTimer = timer
    }

    private func repeating(every interval: TimeInterval, _ action: @escaping (AppDelegate) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolatedCompat {
                guard let self else { return }
                action(self)
            }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    /// 插拔電源時馬上更新，不用等計時器
    private func observePowerSourceChanges() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolatedCompat { delegate.powerSourceChanged() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    /// 插拔通知可能比 Registry／SMC 資料早到；短暫重讀後恢復正常間隔。
    private func powerSourceChanged() {
        powerTransitionTask?.cancel()
        refresh()
        powerTransitionTask = Task { [weak self] in
            for delay in [1, 2, 3] {
                do { try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000) } catch { return }
                guard let self, !sleeping else { return }
                refresh()
            }
        }
    }

    @objc private func willSleep() {
        if store.chargingPlan.isActive { ChargingPlanLog.shared.write("系統即將睡眠") }
        sleeping = true
        powerTransitionTask?.cancel()
        store.setHardwareSampling(active: false)
        store.setProcessSampling(active: false)
        monitors.setSleeping(true)
        store.history.save()
    }

    @objc private func didWake() {
        if store.chargingPlan.isActive { ChargingPlanLog.shared.write("系統已喚醒") }
        sleeping = false
        monitors.setSleeping(false)
        refresh()
        store.peripherals.refresh()
        store.recordHistory()
    }

    // MARK: - Status item

    /// 桌上型 Mac：電腦圖示加整機耗電（取整數，數字才不會每秒跳動）；「只有圖示」時不顯示瓦數
    private func updateDesktopStatusItem(_ button: NSStatusBarButton, watts: Double) {
        let text = "\(Int(watts.rounded())) W"
        let key = "desktop|\(text)|\(settings.display)"
        guard key != lastStatusKey else { return }
        lastStatusKey = key
        // 和 MacBook 的「78% 加電池圖示」一樣，數字在圖示左邊
        button.imagePosition = .imageTrailing
        button.image = settings.display == .percentOnly ? nil
            : NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "系統耗電")
        button.title = settings.display == .iconOnly ? "" : text
        button.toolTip = "系統耗電 \(Format.watts(watts))"
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        if store.snapshot == nil, let desktop = store.desktop, let watts = desktop.systemWatts {
            updateDesktopStatusItem(button, watts: watts)
            return
        }
        guard let s = store.snapshot, let e = store.estimates else {
            guard lastStatusKey != "noBattery" else { return }
            // 桌上型 Mac（Mac mini、iMac 等）沒有電池：不要畫成空電池，免得看起來像沒電
            button.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "這台 Mac 沒有電池")
            button.title = ""
            button.toolTip = "這台 Mac 沒有電池・點一下打開面板與設定"
            lastStatusKey = "noBattery"
            return
        }
        let low = e.state == .discharging && s.percent <= settings.lowThreshold
        let minutes = e.state == .charging ? e.headlineToFull : e.headlineToEmpty
        let showsTime = settings.display == .iconAndTime || settings.display == .iconPercentAndTime
        let key = "\(s.percent)|\(e.state)|\(low)|\(settings.display)|\(showsTime ? minutes ?? -1 : 0)"
        guard key != lastStatusKey else { return }
        lastStatusKey = key

        let inlinePercent = settings.display == .iconPercentAndTime
        button.imagePosition = inlinePercent ? .imageLeading : .imageTrailing
        button.image = settings.display == .percentOnly ? nil : StatusIconRenderer.image(percent: s.percent, state: e.state, low: low, showsPercent: inlinePercent)
        let text: String
        switch settings.display {
        case .iconAndPercent:
            text = "\(s.percent)%"
        case .percentOnly:
            text = e.state == .charging ? "⚡\(s.percent)%" : "\(s.percent)%"
        case .iconOnly:
            text = ""
        case .iconAndTime, .iconPercentAndTime:
            let fallback = inlinePercent ? "—" : "\(s.percent)%"
            switch e.state {
            case .discharging: text = Format.clock(e.headlineToEmpty) ?? fallback
            case .charging: text = Format.clock(e.headlineToFull) ?? fallback
            case .full: text = inlinePercent ? "已充飽" : fallback
            case .pluggedIdle: text = e.drainingOnAC ? (Format.clock(e.headlineToEmpty) ?? fallback) : (inlinePercent ? "接電" : fallback)
            case .limitReached: text = inlinePercent ? "已達上限" : fallback
            }
        }
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)]
        )
        button.toolTip = tooltip(s, e)
    }

    private func tooltip(_ s: BatterySnapshot, _ e: Estimates) -> String {
        switch e.state {
        case .discharging:
            return "電池 \(s.percent)% · 剩餘 \(Format.duration(e.headlineToEmpty))"
        case .charging:
            if let limit = s.chargeLimit?.limit, s.percent < limit {
                return "電池 \(s.percent)% · 充到 \(limit)% 還要 \(Format.duration(e.toLimit))"
            }
            return "電池 \(s.percent)% · 充滿還要 \(Format.duration(e.toFull))"
        case .limitReached:
            return "電池 \(s.percent)% · 已達充電上限 \(s.chargeLimit?.limit ?? 100)%"
        case .pluggedIdle, .full:
            return "電池 \(s.percent)% · \(e.state.title)"
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else if let popover, popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(page: .main)
        }
    }

    private func showPopover(page: PanelPage) {
        guard let button = statusItem.button else { return }
        if let popover, popover.isShown {
            ui.page = page
            return
        }
        ui.page = page
        ui.isVisible = true
        store.panelVisible = true
        store.chargeLimit.panelOpened()
        refresh()
        // 面板每次打開才建立、關掉就釋放，關著時不會有任何 SwiftUI 畫面在背景更新
        let hosting = SizingHostingController(rootView: RootView(store: store, settings: settings, ui: ui), changes: [
            ui.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            store.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            settings.objectWillChange.map { _ in }.eraseToAnyPublisher(),
        ])
        let popover = NSPopover()
        popover.behavior = store.adminCPU.authorizing ? .applicationDefined : .transient
        popover.delegate = self
        popover.contentViewController = hosting
        // 先算好尺寸再顯示，避免面板從 0 大小長出來
        popover.contentSize = hosting.view.fittingSize
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activateCompat()
        popover.contentViewController?.view.window?.makeKey()
        startOutsideClickMonitoring()
    }

    private static let clickMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()
        // 其他 App、桌面的點擊
        if let global = NSEvent.addGlobalMonitorForEvents(matching: Self.clickMask, handler: { [weak self] _ in
            MainActor.assumeIsolatedCompat { self?.closeForOutsideClick() }
        }) {
            outsideClickMonitors.append(global)
        }
        // 本 App 其他視窗（例如系統監控圖示的面板）的點擊；面板本身與這個圖示交給原本的處理
        if let local = NSEvent.addLocalMonitorForEvents(matching: Self.clickMask, handler: { [weak self] event in
            guard let self, let popover = self.popover else { return event }
            let inside = event.window === popover.contentViewController?.view.window
                || event.window === self.statusItem.button?.window
            if !inside { self.closeForOutsideClick() }
            return event
        }) {
            outsideClickMonitors.append(local)
        }
    }

    private func stopOutsideClickMonitoring() {
        outsideClickMonitors.forEach(NSEvent.removeMonitor)
        outsideClickMonitors.removeAll()
    }

    private func closeForOutsideClick() {
        // 管理員授權視窗是別的程序的視窗，點它不能把面板關掉
        guard let popover, popover.isShown, !store.adminCPU.authorizing else { return }
        popover.performClose(nil)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "打開面板", action: #selector(openPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "設定…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "結束\(AppEdition.appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPanel() {
        showPopover(page: .main)
    }

    @objc private func openSettings() {
        showPopover(page: .settings)
    }

    // MARK: - NSPopoverDelegate

    func popoverWillShow(_ notification: Notification) {
        scheduleRefresh(every: interval)
        scheduleProcessCheck()
    }

    private func scheduleProcessCheck() {
        processTimer?.invalidate()
        processTimer = repeating(every: interval) { delegate in
            delegate.store.setProcessSampling(active: !delegate.sleeping && delegate.ui.page == .main && delegate.ui.tab == .processes)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover, closed === popover else { return }
        stopOutsideClickMonitoring()
        store.panelVisible = false
        store.setHardwareSampling(active: false)
        store.setProcessSampling(active: false)
        processTimer?.invalidate()
        processTimer = nil
        scheduleRefresh(every: interval)
        ui.page = .main
        ui.isVisible = false
        // 等這次 delegate 回呼結束再釋放；這段時間若又打開新面板，不要動到它
        DispatchQueue.main.async { [weak self] in
            closed.contentViewController = nil
            if self?.popover === closed { self?.popover = nil }
        }
    }

    // MARK: - Login item

    /// 從 /Applications 啟動、而且這個位置還沒註冊過開機自啟動時（第一次安裝、App 改名或搬移）自動註冊。
    /// 使用者在設定裡關掉後就不再自動開啟。
    private func registerLoginItemIfNeeded() {
        let defaults = UserDefaults.standard
        let path = Bundle.main.bundlePath
        guard LoginItem.isInApplications,
              !defaults.bool(forKey: LoginItem.disabledByUserKey),
              defaults.string(forKey: LoginItem.registeredPathKey) != path else { return }
        // 登錄成功才記下位置，失敗的話下次啟動會再試
        if (try? LoginItem.setEnabled(true)) != nil {
            defaults.set(path, forKey: LoginItem.registeredPathKey)
        }
    }
}
