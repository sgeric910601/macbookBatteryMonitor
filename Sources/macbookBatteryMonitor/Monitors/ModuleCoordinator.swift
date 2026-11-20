import AppKit
import SwiftUI

/// 系統監控模組的選單列圖示、定時取樣與面板
@MainActor
final class ModuleCoordinator: NSObject, NSPopoverDelegate {
    let cpu = CPUMonitor()
    let memory = MemoryMonitor()
    let disk = DiskMonitor()
    let network = NetworkMonitor()

    /// 由 AppDelegate 提供：打開設定視窗
    var openSettings: (() -> Void)?

    private let settings = AppSettings.shared
    private var items: [MonitorKind: NSStatusItem] = [:]
    /// 上次畫到選單列的內容，沒變就不重畫
    private var lastKeys: [MonitorKind: String] = [:]
    /// 選單列的記憶體圖示目前是不是和磁碟合併的兩行版本
    private var memoryItemMerged = false
    /// 選單列圖示目前畫的是不是不加底色的標籤
    private var plainLabels = false
    private var timer: Timer?
    /// 每次打開都建立新的，關閉後整個釋放
    private var popover: NSPopover?
    private var openKind: MonitorKind?
    /// 從選單列圖示打開的面板：系統的 .transient 打開過選單（例如快捷選單）後常不會自己收起來，自己監聽面板外的點擊
    private var outsideClickMonitors: [Any] = []
    /// 不加底色時 GPU 是選單列上獨立的一個圖示（點了開 GPU 面板）
    private var gpuItem: NSStatusItem?
    private var lastGPUKey: String?
    /// 開著的是 GPU 圖示的面板
    private var openGPU = false
    private var topStream: TopStream?
    private var sleeping = false
    /// 螢幕關著或切到其他使用者：不畫選單列；有開警示時每 30 秒取樣一次，警示照常（見 RefreshPacing）
    private var unseen = false
    private var cpuAlert = SustainedAlert(duration: MonitorAlertRules.cpuDuration)
    private var memoryAlert = SustainedAlert(duration: MonitorAlertRules.memoryDuration)
    private var diskAlert = SustainedAlert(duration: 0)

    /// 合併顯示時的第二條狀態列開著：沒有選單列圖示也要取樣，讓上面的數字即時更新
    var stripActive = false {
        didSet {
            guard stripActive != oldValue else { return }
            if stripActive { tick() }
            updateTimer()
        }
    }

    /// 有開啟的模組（左到右：CPU、記憶體、磁碟、網路；記憶體與磁碟合併時只有記憶體）
    var enabledKinds: [MonitorKind] {
        MonitorKind.shown(MonitorKind.allCases.filter(settings.isMonitorEnabled), memoryDiskMerged: settings.memoryDiskMerged)
    }

    func start() {
        syncItems()
        runSelfTestIfRequested()
    }

    /// 開發用：`--selftest-monitors` 依序打開 CPU、記憶體面板各 10 秒再關閉，量測耗電並確認 top 會停止；
    /// 最後切換一次「記憶體與磁碟放在同一個圖示」再切回來，每一步印出選單列圖示的寬度
    private func runSelfTestIfRequested() {
        guard CommandLine.arguments.contains("--selftest-monitors") else { return }
        for (delay, kind) in [(2.0, MonitorKind.cpu), (12.0, .memory)] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let button = items[kind]?.button else { return }
                popover?.closeNow()
                showPopover(kind, from: button)
                print("selftest: opened \(kind.rawValue)")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 22) { [weak self] in
            self?.popover?.closeNow()
            print("selftest: closed")
            self?.printItemWidths("選單列圖示")
            self?.settings.mergeMemoryDisk.toggle()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 24) { [weak self] in
            self?.printItemWidths("切換合併後")
            self?.settings.mergeMemoryDisk.toggle()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 26) { [weak self] in
            self?.printItemWidths("切回原本")
            fflush(stdout)
        }
    }

    private func printItemWidths(_ label: String) {
        let widths = MonitorKind.allCases.compactMap { kind in items[kind].map { "\(kind.rawValue) \(Int($0.length))" } }
        print("selftest: \(label)：\(widths.joined(separator: "、"))（記憶體與磁碟合併 \(settings.memoryDiskMerged)）")
    }

    /// 依設定新增或移除選單列圖示。後建立的圖示會排在左邊，所以由右而左建立：網路、磁碟、記憶體、CPU。
    /// 合併顯示時不建立，改在第二條狀態列上顯示
    func syncItems() {
        for kind in MonitorKind.allCases.reversed() {
            let enabled = settings.isMonitorEnabled(kind) && !settings.menuBarCombined
                && !(kind == .disk && settings.memoryDiskMerged)
            // GPU 要比 CPU 先建，執行中切換和重啟後的順序才一致
            if kind == .cpu { syncGPUItem(cpuEnabled: enabled) }
            if enabled, items[kind] == nil {
                items[kind] = makeItem(autosaveName: "monitor.\(kind.rawValue)")
            } else if !enabled, let item = items[kind] {
                if openKind == kind { popover?.closeNow() }
                NSStatusBar.system.removeStatusItem(item)
                items[kind] = nil
                lastKeys[kind] = nil
            }
        }
        // 單獨和合併的記憶體圖示寬度不同：鎖住的長度要放開重新量；面板內容也不同，開著的記憶體面板先關掉
        if settings.memoryDiskMerged != memoryItemMerged {
            memoryItemMerged = settings.memoryDiskMerged
            if let item = items[.memory] {
                if openKind == .memory { popover?.closeNow() }
                item.length = NSStatusItem.variableLength
                lastKeys[.memory] = nil
            }
        }
        // 換標籤樣式後每個圖示的寬度都不同：鎖住的長度全部放開重新量
        if settings.monitorPlainLabels != plainLabels {
            plainLabels = settings.monitorPlainLabels
            for (kind, item) in items {
                item.length = NSStatusItem.variableLength
                lastKeys[kind] = nil
            }
            lastGPUKey = nil
        }
        // 關掉測速開關或網路模組後就看不到測速卡片，正在跑的測速也一起停掉
        if !(settings.isInstalled(.speedTest) && settings.isMonitorEnabled(.network)) {
            network.speedTest.cancel()
        }
        tick()
        updateTimer()
    }

    private func makeItem(autosaveName: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = autosaveName
        if let button = item.button {
            button.target = self
            button.action = #selector(itemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }
        return item
    }

    /// 不加底色時 CPU 與 GPU 各一個圖示；彩色底塊時兩行畫在 CPU 圖示裡
    private func syncGPUItem(cpuEnabled: Bool) {
        let wanted = cpuEnabled && settings.monitorPlainLabels
        if wanted, gpuItem == nil {
            // 順序由建立先後決定：CPU 已經在時先拿掉，讓 syncItems 接著重建，排法才會和重啟後一樣
            if let cpu = items[.cpu] {
                if openKind == .cpu { popover?.closeNow() }
                NSStatusBar.system.removeStatusItem(cpu)
                items[.cpu] = nil
                lastKeys[.cpu] = nil
            }
            gpuItem = makeItem(autosaveName: "monitor.gpu")
        } else if !wanted, let item = gpuItem {
            if openGPU { popover?.closeNow() }
            NSStatusBar.system.removeStatusItem(item)
            gpuItem = nil
            lastGPUKey = nil
        }
    }

    /// App 結束時一起結束測速，networkQuality 不會隨 app 結束，否則會繼續用掉流量
    func stop() {
        network.speedTest.cancel()
    }

    func setSleeping(_ value: Bool) {
        sleeping = value
        if value {
            topStream?.stop()
        } else {
            tick()
            if openKind != nil { startTop() }
        }
        updateTimer()
    }

    func setUnseen(_ value: Bool) {
        guard value != unseen else { return }
        unseen = value
        timer?.invalidate()
        timer = nil
        if value {
            topStream?.stop()
        } else if !sleeping {
            tick()
            if openKind != nil { startTop() }
        }
        updateTimer()
    }

    /// 更新頻率或省電模式改變後，計時器與 top 改用新的間隔
    func applySampleInterval() {
        timer?.invalidate()
        timer = nil
        updateTimer()
        if topStream != nil { startTop() }
    }

    // MARK: - 定時取樣（依設定的更新頻率）

    private func updateTimer() {
        let alerting = settings.alertCPU || settings.alertMemory || settings.alertDisk
        let shouldRun = (!items.isEmpty || stripActive) && !sleeping && (!unseen || alerting)
        if shouldRun, timer == nil {
            let base = settings.sampleInterval
            let interval = RefreshPacing.interval(base: base, unseen: unseen)
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = unseen ? RefreshPacing.tolerance(base: base, unseen: true) : interval * 0.1
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !shouldRun {
            timer?.invalidate()
            timer = nil
        }
    }

    /// 只取樣有開啟的模組（選單列有圖示，或第二條狀態列開著）
    private func tick() {
        let now = Date()
        func active(_ kind: MonitorKind) -> Bool {
            items[kind] != nil || (stripActive && settings.isMonitorEnabled(kind))
                || (kind == .disk && settings.memoryDiskMerged && items[.memory] != nil)
        }
        if active(.cpu) { cpu.sample(at: now) }
        if active(.memory) { memory.sample(at: now) }
        if active(.disk) { disk.sample(at: now) }
        if active(.network) { network.sample(at: now) }
        checkAlerts(cpu: active(.cpu), memory: active(.memory), disk: active(.disk), at: now)
        guard !unseen else { return }
        for (kind, item) in items { render(kind, item) }
        if let gpuItem { renderGPU(gpuItem) }
        // top 意外結束時（例如被強制結束），面板還開著就重新啟動
        if let topStream, !topStream.isRunning, !sleeping { topStream.start() }
    }

    /// 監控警示：只判斷這次有取樣的模組；沒取樣的不更新，下次取樣隔太久會重新計時
    private func checkAlerts(cpu cpuActive: Bool, memory memoryActive: Bool, disk diskActive: Bool, at now: Date) {
        if settings.alertCPU, cpuActive, let usage = cpu.usage {
            let rule = MonitorAlertRules.cpu(usage: usage.total)
            if cpuAlert.update(high: rule.high, recovered: rule.recovered, at: now) { Notifier.shared.notifyCPUBusy() }
        }
        if settings.alertMemory, memoryActive, let usage = memory.usage {
            let rule = MonitorAlertRules.memory(usage.pressure)
            if memoryAlert.update(high: rule.high, recovered: rule.recovered, at: now) { Notifier.shared.notifyMemoryPressure() }
        }
        // 可清出的空間還沒校正完（剛啟動）時剩餘空間偏少，先不判斷，免得誤報
        if settings.alertDisk, diskActive, let volume = disk.volume, volume.calibrated {
            let rule = MonitorAlertRules.disk(available: volume.available)
            if diskAlert.update(high: rule.high, recovered: rule.recovered, at: now) { Notifier.shared.notifyDiskLow(available: volume.available) }
        }
    }

    // MARK: - 選單列

    private func render(_ kind: MonitorKind, _ item: NSStatusItem) {
        guard let button = item.button else { return }
        // GPU 有自己的圖示時，CPU 圖示只畫 CPU
        let content = kind == .cpu && gpuItem != nil ? plainCPUOnly : menuBarContent(kind)
        // 提示框不跟著比對鍵：滑鼠停著時跳過的更新，移開後下一次就補上（文字沒變不會重設）
        button.setToolTipUnlessHovered(content.tooltip)
        guard content.key != lastKeys[kind] else { return }
        lastKeys[kind] = content.key
        apply(content.image(), to: item)
    }

    private func renderGPU(_ item: NSStatusItem) {
        let g = cpu.gpu.map(ByteFormat.percent) ?? "—"
        item.button?.setToolTipUnlessHovered("GPU \(g)")
        guard g != lastGPUKey else { return }
        lastGPUKey = g
        apply(MonitorMenuBarRenderer.columns([("GPU", g, nil)], valueTemplate: MonitorMenuBarRenderer.plainTemplate), to: item)
    }

    private var plainCPUOnly: (key: String, tooltip: String, image: () -> NSImage) {
        let c = cpu.usage.map { ByteFormat.percent($0.total) } ?? "—"
        return ("cpuOnly|\(c)", "CPU \(c)", { MonitorMenuBarRenderer.columns([("CPU", c, nil)], valueTemplate: MonitorMenuBarRenderer.plainTemplate) })
    }

    private func apply(_ image: NSImage, to item: NSStatusItem) {
        guard let button = item.button else { return }
        button.image = image
        // 圖示寬度固定（依範本計算），第一次畫好後鎖住長度；
        // 否則每秒換圖都會觸發 _adjustLength，讓整條選單列重新排版
        if item.length == NSStatusItem.variableLength {
            let width = settings.monitorPlainLabels ? image.size.width + MonitorMenuBarRenderer.plainItemPadding
                                                    : button.fittingSize.width
            if width > 0 { item.length = ceil(width) }
        }
    }

    private func menuBarContent(_ kind: MonitorKind) -> (key: String, tooltip: String, image: () -> NSImage) {
        let content = menuBarParts(kind)
        let plain = settings.monitorPlainLabels
        // 樣式也放進 key：換樣式時一定重畫
        return ((plain ? "plain|" : "") + content.key, content.tooltip, {
            plain ? content.plain() : content.badge()
        })
    }

    /// 每個模組兩種畫法：彩色底塊的標籤（badge）與不加底色、標籤在上數值在下（plain）
    private func menuBarParts(_ kind: MonitorKind) -> (key: String, tooltip: String, badge: () -> NSImage, plain: () -> NSImage) {
        typealias R = MonitorMenuBarRenderer
        switch kind {
        case .cpu:
            let c = cpu.usage.map { ByteFormat.percent($0.total) } ?? "—"
            let g = cpu.gpu.map(ByteFormat.percent) ?? "—"
            return ("\(c)|\(g)", "CPU \(c)・GPU \(g)",
                    { R.twoLines([("CPU", c, R.green), ("GPU", g, R.orange)], valueTemplate: "100%") },
                    { R.columns([("CPU", c, nil), ("GPU", g, nil)], valueTemplate: MonitorMenuBarRenderer.plainTemplate) })
        case .memory where settings.memoryDiskMerged:
            let m = memory.usage.map { ByteFormat.percent($0.usedFraction) } ?? "—"
            let d = diskUsedText
            let pressure = memory.usage?.pressure ?? .normal
            return ("merged|\(m)|\(d)|\(pressure.rawValue)", "\(memoryTooltip)\n\(diskTooltip)",
                    { R.memoryDisk(memory: m, disk: d, pressure: pressure) },
                    { R.columns([("MEM", m, R.pressureColor(pressure)), ("DISK", d, nil)], valueTemplate: MonitorMenuBarRenderer.plainTemplate) })
        case .memory:
            let value = memory.usage.map { ByteFormat.percent($0.usedFraction) } ?? "—"
            let pressure = memory.usage?.pressure ?? .normal
            return ("\(value)|\(pressure.rawValue)", memoryTooltip,
                    { R.symbolValue(symbol: "memorychip", value: value, valueTemplate: "100%", color: R.pressureColor(pressure)) },
                    { R.columns([("MEM", value, R.pressureColor(pressure))], valueTemplate: MonitorMenuBarRenderer.plainTemplate) })
        case .disk:
            let value = diskUsedText
            return (value, diskTooltip,
                    { R.symbolValue(symbol: "internaldrive", value: value, valueTemplate: "100%") },
                    { R.columns([("DISK", value, nil)], valueTemplate: MonitorMenuBarRenderer.plainTemplate) })
        case .network:
            let up = ByteFormat.compactRate(network.uploadRate)
            let down = ByteFormat.compactRate(network.downloadRate)
            let tooltip = "上傳 \(ByteFormat.rate(network.uploadRate))・下載 \(ByteFormat.rate(network.downloadRate))"
            // 不加底色時帶單位（「4 KB/s」），上下用彩色圓點區分
            let withUnit = { (rate: String) in rate.replacingOccurrences(of: #"([KMG])$"#, with: " $1B/s", options: .regularExpression) }
            return ("\(up)|\(down)", tooltip,
                    { R.twoLines([("↑", up, R.orange), ("↓", down, R.green)], valueTemplate: "999K") },
                    { R.twoLines([("", withUnit(up), R.orange), ("", withUnit(down), R.green)], valueTemplate: "99 KB/s", plain: true) })
        }
    }

    private var diskUsedText: String {
        let fraction = disk.volume.map { $0.total > 0 ? Double($0.used) / Double($0.total) : 0 }
        return fraction.map(ByteFormat.percent) ?? "—"
    }

    private var memoryTooltip: String {
        memory.usage.map { "記憶體 \(ByteFormat.memory($0.used)) / \(ByteFormat.memory($0.total))・壓力\($0.pressure.title)" } ?? "記憶體"
    }

    private var diskTooltip: String {
        disk.volume.map { "\($0.name) 可用 \(ByteFormat.size($0.available))・讀 \(ByteFormat.rate(disk.readRate))・寫 \(ByteFormat.rate(disk.writeRate))" } ?? "磁碟"
    }

    /// 第二條狀態列上的圖示（和選單列的圖示相同）
    func stripContent(_ kind: MonitorKind) -> (image: NSImage, tooltip: String) {
        let content = menuBarContent(kind)
        return (content.image(), content.tooltip)
    }

    /// 這個模組的面板開著嗎
    func isPanelShown(_ kind: MonitorKind) -> Bool { popover?.isShown == true && openKind == kind }

    /// 從第二條狀態列打開面板：面板不會因為點到第二條狀態列而自己關掉，開關交給第二條狀態列處理
    func showPanel(_ kind: MonitorKind, from view: NSView) {
        popover?.closeNow()
        showPopover(kind, from: view, behavior: .applicationDefined)
    }

    func closePanel() {
        popover?.closeNow()
    }

    /// 面板的視窗（第二條狀態列判斷點擊是不是在面板裡）
    var panelWindow: NSWindow? { popover?.contentViewController?.view.window }

    // MARK: - 面板

    @objc private func itemClicked(_ sender: NSStatusBarButton) {
        let isGPU = gpuItem?.button === sender
        guard let kind = isGPU ? .cpu : items.first(where: { $0.value.button === sender })?.key else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu(on: isGPU ? gpuItem : items[kind])
            return
        }
        if let popover, popover.isShown {
            let sameModule = openKind == kind && openGPU == isGPU
            popover.closeNow()
            if sameModule { return }
        }
        showPopover(kind, from: sender, gpu: isGPU)
    }

    private func showPopover(_ kind: MonitorKind, from button: NSView, behavior: NSPopover.Behavior = .transient,
                             gpu: Bool = false) {
        // 舊面板的 popoverDidClose 可能在新面板接手後才到，那時不會拆它的點擊監聽：先拆，免得作用在新面板上
        stopOutsideClickMonitoring()
        openKind = kind
        openGPU = gpu
        cpu.setThermalActive(kind == .cpu)
        disk.setHealthActive(kind == .disk || (kind == .memory && settings.memoryDiskMerged))
        tick()
        let root = MonitorPanel(kind: kind, cpu: cpu, memory: memory, disk: disk, network: network,
                                memoryDiskMerged: settings.memoryDiskMerged, gpuOnly: gpu, separateGPU: gpuItem != nil,
                                showsSpeedTest: settings.isInstalled(.speedTest),
                                onSettings: { [weak self] in
                                    self?.popover?.closeNow(animated: false)
                                    self?.openSettings?()
                                })
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        let popover = NSPopover()
        popover.behavior = behavior
        popover.delegate = self
        popover.contentViewController = hosting
        popover.contentSize = hosting.view.fittingSize
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.allowInFullScreen()
        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()
        if behavior == .transient, popover.isShown { startOutsideClickMonitoring(button: button) }
        startTop()
    }

    /// 點其他 App、桌面或本 App 其他視窗（電池面板、快捷選單的圖示等）就收起來。
    /// 面板本身與打開它的圖示交給原本的處理（再點一次圖示是收起）
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

    /// CPU 與記憶體面板開著時，持續跑一個 top 更新程序排行（間隔同設定）
    private func startTop() {
        topStream?.stop()
        topStream = nil
        // GPU、磁碟那一欄的面板沒有程序排行
        guard !sleeping, !unseen, let openKind, !openGPU else { return }
        let column: String
        switch openKind {
        case .cpu:
            cpu.clearTop()
            column = "cpu"
        case .memory:
            memory.clearTop()
            column = "mem"
        case .disk, .network:
            return
        }
        let stream = TopStream(arguments: ["-l", "0", "-s", "\(Int(settings.sampleInterval))", "-o", column, "-stats", "pid,command,\(column)", "-n", "15"]) { [weak self] text in
            MainActor.assumeIsolated {
                guard let self else { return }
                if openKind == .cpu { self.cpu.receiveTop(text) } else { self.memory.receiveTop(text) }
            }
        }
        stream.start()
        topStream = stream
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover else { return }
        // 切換到另一個模組時，新面板已經接手；這裡只釋放舊的
        if closed === popover {
            stopOutsideClickMonitoring()
            topStream?.stop()
            topStream = nil
            openKind = nil
            openGPU = false
            cpu.setThermalActive(false)
            disk.setHealthActive(false)
        }
        DispatchQueue.main.async { [weak self] in
            closed.contentViewController = nil
            if self?.popover === closed { self?.popover = nil }
        }
    }

    private func showMenu(on item: NSStatusItem?) {
        guard let item else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "設定…", action: #selector(openSettingsFromMenu), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "結束\(AppEdition.appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func openSettingsFromMenu() {
        openSettings?()
    }
}

/// 畫選單列的小圖。用 drawingHandler 延後繪製，顏色會跟著深淺色外觀
enum MonitorMenuBarRenderer {
    /// 標籤底色：綠、橘兩個色相差最多，底色偏深讓白字清楚
    static let green = NSColor(srgbRed: 0.10, green: 0.62, blue: 0.27, alpha: 1)
    static let orange = NSColor(srgbRed: 0.90, green: 0.40, blue: 0.00, alpha: 1)
    /// 記憶體壓力升高時數值的顏色：警告橘、嚴重紅，正常用一般文字顏色
    static func pressureColor(_ pressure: MemoryPressure) -> NSColor? {
        switch pressure {
        case .normal: return nil
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    /// 記憶體與磁碟合併的圖示：上面記憶體、下面磁碟；記憶體壓力升高時數字一樣變橘、變紅，和單獨的記憶體圖示相同
    static func memoryDisk(memory: String, disk: String, pressure: MemoryPressure) -> NSImage {
        twoLines([("MEM", memory, green), ("DISK", disk, orange)], valueTemplate: "100%", valueColors: [pressureColor(pressure), nil])
    }

    private static let labelFont = NSFont.systemFont(ofSize: 8, weight: .heavy)
    private static let lineFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
    /// 不加底色時同一個圖示裡欄位之間的間距（第二條狀態列的 CPU／GPU、記憶體／磁碟）
    static let plainSpacing: CGFloat = 8
    /// 不加底色時每個圖示左右合計的留白：圖示之間的距離都一樣
    static let plainItemPadding: CGFloat = 0
    /// 不加底色時欄位寬度固定以兩位數預留；100% 時字稍微縮小塞進去，選單列不會橫移
    static let plainTemplate = "88%"
    // 選單列只有約 20 點高：標籤約 6 點、數值約 9 點的字高，中間留約 4 點
    private static let columnLabelFont = NSFont.systemFont(ofSize: 9, weight: .regular)
    /// 不加底色時網路上下行的圓點直徑
    private static let plainDot: CGFloat = 6
    private static let plainLineFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
    private static let columnValueFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)

    private static var height: CGFloat { max(18, NSStatusBar.system.thickness - 2) }

    /// 目前繪製目標每個點對應的像素數：內建螢幕是 2，一般外接螢幕是 1
    private static var pixelsPerPoint: CGFloat {
        max(1, NSGraphicsContext.current?.cgContext.ctm.a ?? 1)
    }

    /// 把座標對齊到整數像素。座標落在半個像素上時，線條與邊緣會被抗鋸齒糊成兩個像素寬，在 1x 螢幕上最明顯
    private static func snap(_ value: CGFloat, scale: CGFloat) -> CGFloat { (value * scale).rounded() / scale }

    private static func snap(_ rect: NSRect, scale: CGFloat) -> NSRect {
        let minX = snap(rect.minX, scale: scale), minY = snap(rect.minY, scale: scale)
        let maxX = snap(rect.maxX, scale: scale), maxY = snap(rect.maxY, scale: scale)
        return NSRect(x: minX, y: minY, width: max(1 / scale, maxX - minX), height: max(1 / scale, maxY - minY))
    }

    /// 兩行，每行「彩色底塊的標籤＋靠右的數值」；寬度依 valueTemplate 固定，數字變動時圖示不會左右晃。
    /// 標籤是白字配實心色塊（CPU 與下載用綠、GPU 與上傳用橘，與面板圖表一致），在任何桌布與深淺色選單列上都清楚。
    /// valueColors 依行指定數值的顏色（例如記憶體壓力），沒有指定的行用一般文字顏色
    /// plain：標籤位置改畫實心彩色圓點（細的彩色箭頭壓在桌布上的半透明選單列會看不清楚）
    static func twoLines(_ lines: [(label: String, value: String, color: NSColor)], valueTemplate: String,
                         valueColors: [NSColor?] = [], plain: Bool = false) -> NSImage {
        let font = labelFont
        let labelWidth = lines.map { ($0.label as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let badgeWidth = plain ? plainDot + 2 : ceil(labelWidth + 5)
        let valueFont = plain ? plainLineFont : lineFont
        let valueWidth = (valueTemplate as NSString).size(withAttributes: [.font: valueFont]).width
        let size = NSSize(width: ceil(badgeWidth + 3 + valueWidth), height: height)
        return NSImage(size: size, flipped: true) { rect in
            let scale = pixelsPerPoint
            let lineHeight = rect.height / 2
            for (index, line) in lines.prefix(2).enumerated() {
                let y = CGFloat(index) * lineHeight
                let badge = snap(NSRect(x: 0, y: y + 0.75, width: badgeWidth, height: lineHeight - 1.5), scale: scale)
                if plain {
                    line.color.setFill()
                    NSBezierPath(ovalIn: snap(NSRect(x: 0, y: y + (lineHeight - plainDot) / 2, width: plainDot, height: plainDot), scale: scale)).fill()
                    let valueColor = (index < valueColors.count ? valueColors[index] : nil) ?? NSColor.labelColor
                    let value = NSAttributedString(string: line.value, attributes: [.font: fitted(valueFont, line.value, width: valueWidth),
                                                                                    .foregroundColor: valueColor])
                    let valueSize = value.size()
                    value.draw(at: NSPoint(x: snap(rect.width - valueSize.width, scale: scale),
                                           y: snap(y + (lineHeight - valueSize.height) / 2, scale: scale)))
                    continue
                }
                line.color.setFill()
                NSBezierPath(roundedRect: badge, xRadius: 2.5, yRadius: 2.5).fill()
                let label = NSAttributedString(string: line.label, attributes: [.font: font,
                                                                                .foregroundColor: plain ? NSColor.labelColor : NSColor.white])
                let labelSize = label.size()
                label.draw(at: NSPoint(x: snap(badge.midX - labelSize.width / 2, scale: scale),
                                       y: snap(badge.midY - labelSize.height / 2, scale: scale)))
                let valueColor = (index < valueColors.count ? valueColors[index] : nil) ?? NSColor.labelColor
                let value = NSAttributedString(string: line.value, attributes: [.font: valueFont, .foregroundColor: valueColor])
                let valueSize = value.size()
                value.draw(at: NSPoint(x: snap(rect.width - valueSize.width, scale: scale),
                                       y: snap(y + (lineHeight - valueSize.height) / 2, scale: scale)))
            }
            return true
        }
    }

    /// 不加底色的欄位（像 Stats）：每欄上面是小字標籤、下面是數值，多欄並排；寬度依 valueTemplate 固定，數字變動時不會左右晃。
    /// valueColor 沒有指定時用一般文字顏色（記憶體壓力升高時變橘、變紅）
    /// 文字比給的寬度寬時，等比例縮小字級到剛好放得下（最小 70%）
    private static func fitted(_ font: NSFont, _ text: String, width: CGFloat) -> NSFont {
        let natural = (text as NSString).size(withAttributes: [.font: font]).width
        guard natural > width, natural > 0 else { return font }
        return font.withSize(font.pointSize * max(0.7, width / natural))
    }

    /// 每一欄的寬度
    static func columnWidths(_ labels: [String], valueTemplate: String) -> [CGFloat] {
        let templateWidth = (valueTemplate as NSString).size(withAttributes: [.font: columnValueFont]).width
        return labels.map { max(templateWidth, ($0 as NSString).size(withAttributes: [.font: columnLabelFont]).width) }
    }

    static func columns(_ items: [(label: String, value: String, valueColor: NSColor?)], valueTemplate: String) -> NSImage {
        let widths = columnWidths(items.map(\.label), valueTemplate: valueTemplate)
        let spacing = plainSpacing
        let size = NSSize(width: ceil(widths.reduce(0, +) + spacing * CGFloat(max(0, items.count - 1))), height: height)
        // 上下撐滿：標籤的字頂貼齊上緣、數值的底線貼齊下緣，中間留下的就是兩行的間距
        let labelTop = 0.5 - (columnLabelFont.ascender - columnLabelFont.capHeight)
        let valueTop = size.height - 0.5 - columnValueFont.ascender
        return NSImage(size: size, flipped: true) { rect in
            let scale = pixelsPerPoint
            var x: CGFloat = 0
            for (index, item) in items.enumerated() {
                let width = widths[index]
                // 標籤用一般文字色：次要色在桌布上的半透明選單列太淡
                let label = NSAttributedString(string: item.label, attributes: [.font: columnLabelFont,
                                                                                .foregroundColor: NSColor.labelColor])
                let labelSize = label.size()
                label.draw(at: NSPoint(x: snap(x + (width - labelSize.width) / 2, scale: scale), y: snap(labelTop, scale: scale)))
                // 寬度固定：比範本寬的數值（例如 100%）字稍微縮小塞進去，選單列不會跟著橫移；底線仍和其他數字對齊
                let font = fitted(columnValueFont, item.value, width: width)
                let value = NSAttributedString(string: item.value, attributes: [.font: font,
                                                                                .foregroundColor: item.valueColor ?? NSColor.labelColor])
                let valueSize = value.size()
                value.draw(at: NSPoint(x: snap(x + (width - valueSize.width) / 2, scale: scale),
                                       y: snap(valueTop + columnValueFont.ascender - font.ascender, scale: scale)))
                x += width + spacing
            }
            return true
        }
    }

    /// SF Symbol ＋ 單一數值
    static func symbolValue(symbol: String, value: String, valueTemplate: String, color: NSColor? = nil) -> NSImage {
        // 寬度固定用粗一級的字重算，數字變動或換螢幕時圖示不會左右晃
        let layoutConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let layoutSize = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(layoutConfig)?.size ?? .zero
        let valueWidth = (valueTemplate as NSString).size(withAttributes: [.font: valueFont]).width
        let size = NSSize(width: ceil(layoutSize.width + 3 + valueWidth), height: height)
        return NSImage(size: size, flipped: false) { rect in
            let scale = pixelsPerPoint
            let textColor = color ?? NSColor.labelColor
            // 2x 螢幕用粗一級才與文字一樣清楚；1x 螢幕上粗線條會糊成兩個像素，改用一般字重
            let weight: NSFont.Weight = scale >= 2 ? .semibold : .regular
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: weight)
            if let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let natural = symbolImage.size
                // 圖示當成遮罩，整個填上與文字完全相同的顏色（不受符號內建的圖層透明度影響）
                let iconRect = snap(NSRect(x: 0, y: (rect.height - natural.height) / 2, width: natural.width, height: natural.height),
                                    scale: scale)
                let tinted = NSImage(size: natural, flipped: false) { bounds in
                    symbolImage.draw(in: bounds)
                    textColor.setFill()
                    bounds.fill(using: .sourceIn)
                    return true
                }
                tinted.draw(in: iconRect)
            }
            let text = NSAttributedString(string: value, attributes: [.font: valueFont, .foregroundColor: textColor])
            let textSize = text.size()
            text.draw(at: NSPoint(x: snap(rect.width - textSize.width, scale: scale),
                                  y: snap((rect.height - textSize.height) / 2, scale: scale)))
            return true
        }
    }
}
