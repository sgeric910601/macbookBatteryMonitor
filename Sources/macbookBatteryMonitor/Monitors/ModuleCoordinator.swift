import AppKit
import Combine
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
    private var timer: Timer?
    /// 每次打開都建立新的，關閉後整個釋放
    private var popover: NSPopover?
    private var openKind: MonitorKind?
    private var topStream: TopStream?
    private var sleeping = false

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
            if enabled, items[kind] == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.autosaveName = "monitor.\(kind.rawValue)"
                if let button = item.button {
                    button.target = self
                    button.action = #selector(itemClicked(_:))
                    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                    button.imagePosition = .imageOnly
                }
                items[kind] = item
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
        // 關掉測速開關或網路模組後就看不到測速卡片，正在跑的測速也一起停掉
        if !(settings.networkSpeedTest && settings.isMonitorEnabled(.network)) {
            network.speedTest.cancel()
        }
        tick()
        updateTimer()
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

    /// 更新頻率或省電模式改變後，計時器與 top 改用新的間隔
    func applySampleInterval() {
        timer?.invalidate()
        timer = nil
        updateTimer()
        if topStream != nil { startTop() }
    }

    // MARK: - 定時取樣（依設定的更新頻率）

    private func updateTimer() {
        let shouldRun = (!items.isEmpty || stripActive) && !sleeping
        if shouldRun, timer == nil {
            let interval = settings.sampleInterval
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolatedCompat { self?.tick() }
            }
            timer.tolerance = interval * 0.1
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
        for (kind, item) in items { render(kind, item) }
        // top 意外結束時（例如被強制結束），面板還開著就重新啟動
        if let topStream, !topStream.isRunning, !sleeping { topStream.start() }
    }

    // MARK: - 選單列

    private func render(_ kind: MonitorKind, _ item: NSStatusItem) {
        guard let button = item.button else { return }
        let content = menuBarContent(kind)
        guard content.key != lastKeys[kind] else { return }
        lastKeys[kind] = content.key
        button.image = content.image()
        button.toolTip = content.tooltip
        // 圖示寬度固定（依範本計算），第一次畫好後鎖住長度；
        // 否則每秒換圖都會觸發 _adjustLength，讓整條選單列重新排版
        if item.length == NSStatusItem.variableLength {
            let width = button.fittingSize.width
            if width > 0 { item.length = ceil(width) }
        }
    }

    private func menuBarContent(_ kind: MonitorKind) -> (key: String, tooltip: String, image: () -> NSImage) {
        switch kind {
        case .cpu:
            let c = cpu.usage.map { ByteFormat.percent($0.total) } ?? "—"
            let g = cpu.gpu.map(ByteFormat.percent) ?? "—"
            return ("\(c)|\(g)", "CPU \(c)・GPU \(g)", {
                MonitorMenuBarRenderer.twoLines([("CPU", c, MonitorMenuBarRenderer.green), ("GPU", g, MonitorMenuBarRenderer.orange)], valueTemplate: "100%")
            })
        case .memory where settings.memoryDiskMerged:
            let m = memory.usage.map { ByteFormat.percent($0.usedFraction) } ?? "—"
            let d = diskUsedText
            let pressure = memory.usage?.pressure ?? .normal
            return ("merged|\(m)|\(d)|\(pressure.rawValue)", "\(memoryTooltip)\n\(diskTooltip)", {
                MonitorMenuBarRenderer.memoryDisk(memory: m, disk: d, pressure: pressure)
            })
        case .memory:
            let value = memory.usage.map { ByteFormat.percent($0.usedFraction) } ?? "—"
            let pressure = memory.usage?.pressure ?? .normal
            return ("\(value)|\(pressure.rawValue)", memoryTooltip, {
                MonitorMenuBarRenderer.symbolValue(symbol: "memorychip", value: value, valueTemplate: "100%",
                                                   color: MonitorMenuBarRenderer.pressureColor(pressure))
            })
        case .disk:
            let value = diskUsedText
            return (value, diskTooltip, {
                MonitorMenuBarRenderer.symbolValue(symbol: "internaldrive", value: value, valueTemplate: "100%")
            })
        case .network:
            let up = ByteFormat.compactRate(network.uploadRate)
            let down = ByteFormat.compactRate(network.downloadRate)
            let tooltip = "上傳 \(ByteFormat.rate(network.uploadRate))・下載 \(ByteFormat.rate(network.downloadRate))"
            return ("\(up)|\(down)", tooltip, {
                MonitorMenuBarRenderer.twoLines([("↑", up, MonitorMenuBarRenderer.orange), ("↓", down, MonitorMenuBarRenderer.green)], valueTemplate: "999K")
            })
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
        guard let kind = items.first(where: { $0.value.button === sender })?.key else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu(for: kind)
            return
        }
        if let popover, popover.isShown {
            let sameModule = openKind == kind
            popover.closeNow()
            if sameModule { return }
        }
        showPopover(kind, from: sender)
    }

    private func showPopover(_ kind: MonitorKind, from button: NSView, behavior: NSPopover.Behavior = .transient) {
        openKind = kind
        cpu.setThermalActive(kind == .cpu)
        disk.setHealthActive(kind == .disk || (kind == .memory && settings.memoryDiskMerged))
        tick()
        let root = MonitorPanel(kind: kind, cpu: cpu, memory: memory, disk: disk, network: network,
                                memoryDiskMerged: settings.memoryDiskMerged,
                                showsSpeedTest: settings.networkSpeedTest,
                                onSettings: { [weak self] in
                                    self?.popover?.closeNow(animated: false)
                                    self?.openSettings?()
                                })
        let changes: AnyPublisher<Void, Never>
        switch kind {
        case .cpu: changes = cpu.objectWillChange.map { _ in }.eraseToAnyPublisher()
        case .memory: changes = memory.objectWillChange.map { _ in }.eraseToAnyPublisher()
        case .disk: changes = disk.objectWillChange.map { _ in }.eraseToAnyPublisher()
        case .network: changes = network.objectWillChange.map { _ in }.eraseToAnyPublisher()
        }
        let hosting = SizingHostingController(rootView: root, changes: [changes])
        let popover = NSPopover()
        popover.behavior = behavior
        popover.delegate = self
        popover.contentViewController = hosting
        popover.contentSize = hosting.view.fittingSize
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.allowInFullScreen()
        NSApp.activateCompat()
        popover.contentViewController?.view.window?.makeKey()
        startTop()
    }

    /// CPU 與記憶體面板開著時，持續跑一個 top 更新程序排行（間隔同設定）
    private func startTop() {
        topStream?.stop()
        topStream = nil
        guard !sleeping, let openKind else { return }
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
            MainActor.assumeIsolatedCompat {
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
            topStream?.stop()
            topStream = nil
            openKind = nil
            cpu.setThermalActive(false)
            disk.setHealthActive(false)
        }
        DispatchQueue.main.async { [weak self] in
            closed.contentViewController = nil
            if self?.popover === closed { self?.popover = nil }
        }
    }

    private func showMenu(for kind: MonitorKind) {
        guard let item = items[kind] else { return }
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
    static func twoLines(_ lines: [(label: String, value: String, color: NSColor)], valueTemplate: String,
                         valueColors: [NSColor?] = []) -> NSImage {
        let labelWidth = lines.map { ($0.label as NSString).size(withAttributes: [.font: labelFont]).width }.max() ?? 0
        let badgeWidth = ceil(labelWidth + 5)
        let valueWidth = (valueTemplate as NSString).size(withAttributes: [.font: lineFont]).width
        let size = NSSize(width: ceil(badgeWidth + 3 + valueWidth), height: height)
        return NSImage(size: size, flipped: true) { rect in
            let scale = pixelsPerPoint
            let lineHeight = rect.height / 2
            for (index, line) in lines.prefix(2).enumerated() {
                let y = CGFloat(index) * lineHeight
                let badge = snap(NSRect(x: 0, y: y + 0.75, width: badgeWidth, height: lineHeight - 1.5), scale: scale)
                line.color.setFill()
                NSBezierPath(roundedRect: badge, xRadius: 2.5, yRadius: 2.5).fill()
                let label = NSAttributedString(string: line.label, attributes: [.font: labelFont, .foregroundColor: NSColor.white])
                let labelSize = label.size()
                label.draw(at: NSPoint(x: snap(badge.midX - labelSize.width / 2, scale: scale),
                                       y: snap(badge.midY - labelSize.height / 2, scale: scale)))
                let valueColor = (index < valueColors.count ? valueColors[index] : nil) ?? NSColor.labelColor
                let value = NSAttributedString(string: line.value, attributes: [.font: lineFont, .foregroundColor: valueColor])
                let valueSize = value.size()
                value.draw(at: NSPoint(x: snap(rect.width - valueSize.width, scale: scale),
                                       y: snap(y + (lineHeight - valueSize.height) / 2, scale: scale)))
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
