import AppKit
import Charts
import SwiftUI

/// 系統監控模組的面板。只裝 Command Line Tools 時不能用 @State，畫面只讀取各模組的資料
struct MonitorPanel: View {
    let kind: MonitorKind
    let cpu: CPUMonitor
    let memory: MemoryMonitor
    let disk: DiskMonitor
    let network: NetworkMonitor
    var memoryDiskMerged = false
    /// 只看 GPU（不加底色時選單列的 GPU 圖示）
    var gpuOnly = false
    /// GPU 有自己的圖示和面板：CPU 面板不再顯示 GPU
    var separateGPU = false
    /// 設定裡打開了網路測速才顯示測速卡片
    var showsSpeedTest = false
    var onSettings: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            // 內容比螢幕高時（接了多顆外接磁碟）改成可捲動；太高的 popover 會被系統挪到圖示旁邊，不再置中在圖示下方
            HeightCap(maxHeight: Self.maxContentHeight) {
                ScrollView(.vertical) {
                    VStack(spacing: 10) {
                        switch kind {
                        case .cpu where gpuOnly: GPUPanel(cpu: cpu)
                        case .cpu: CPUPanel(cpu: cpu, showsGPU: !separateGPU)
                        case .memory:
                            MemoryPanel(memory: memory)
                            if memoryDiskMerged { DiskPanel(disk: disk) }
                        case .disk: DiskPanel(disk: disk)
                        case .network: NetworkPanel(network: network, showsSpeedTest: showsSpeedTest)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    /// 面板內容區的高度上限：可用螢幕高度扣掉箭頭、內距與頁尾
    private static var maxContentHeight: CGFloat {
        let screen = NSScreen.main ?? NSScreen.screens.first
        return max(320, (screen?.visibleFrame.height ?? 800) - 120)
    }

    private var updated: Date? {
        switch kind {
        case .cpu: return cpu.updated
        case .memory: return memory.updated
        case .disk: return disk.updated
        case .network: return network.updated
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let updated {
                Text("\(AppSettings.shared.updateText)・\(updated.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: onSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("設定")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("結束\(AppEdition.appName)")
        }
    }
}

/// 子視圖的理想高度超過上限時，只佔上限高度（子視圖是 ScrollView，會自己捲動）
private struct HeightCap: Layout {
    var maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: ideal.width, height: min(ideal.height, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

// MARK: - 共用元件

private struct PanelHeader: View {
    let symbol: String
    let title: String
    let value: String
    let detail: String
    var tint: Color = .primary
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var tint: Color? = nil

    init(_ label: String, _ value: String, tint: Color? = nil) {
        self.label = label
        self.value = value
        self.tint = tint
    }

    var body: some View {
        HStack {
            if let tint {
                Circle().fill(tint).frame(width: 7, height: 7)
            }
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}

/// 最近 2 分鐘的兩條線；percent 時 y 軸固定 0～100%
private struct MonitorChart: View {
    let points: [MonitorPoint]
    let a: (name: String, color: Color)
    let b: (name: String, color: Color)?
    var percent = false
    /// 上方已經有帶顏色圓點的數值列時不必重複圖例
    var showsLegend = true

    var body: some View {
        // 「最近 2 分鐘」與 Y 軸最上方的刻度都靠右，間距要夠才不會擠在一起
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                if showsLegend {
                    legend(a.name, a.color)
                    if let b { legend(b.name, b.color) }
                }
                Spacer()
                Text("最近 2 分鐘")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if points.count < 2 {
                Text("收集中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70)
            } else {
                chart
                    .frame(height: 70)
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("時間", p.t), y: .value(a.name, p.a), series: .value("線", a.name))
                    .foregroundStyle(a.color.opacity(0.18))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("時間", p.t), y: .value(a.name, p.a), series: .value("線", a.name))
                    .foregroundStyle(a.color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)
            }
            if let b {
                ForEach(points) { p in
                    LineMark(x: .value("時間", p.t), y: .value(b.name, p.b), series: .value("線", b.name))
                        .foregroundStyle(b.color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.monotone)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYScale(domain: 0...axisMax)
        .chartYAxis {
            // 固定三條刻度：0、一半、上限（上限往上取整數，最高的資料不會超出格線）
            AxisMarks(position: .trailing, values: axisTicks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(percent ? ByteFormat.percent(v) : ByteFormat.axisRate(v))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var axisMax: Double {
        percent ? 1 : ByteFormat.niceAxisMax(points.map { max($0.a, $0.b) }.max() ?? 0)
    }

    private var axisTicks: [Double] {
        let top = axisMax
        return [0, top / 2, top]
    }

    private func legend(_ name: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(name)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

/// 使用量最高的 App；同一個 App 的子程序已合併
private struct TopList: View {
    let title: String
    let processes: [TopProcess]
    let loaded: Bool
    let valueText: (Double) -> String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                CardTitle(title, systemImage: "list.number")
                if !loaded {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else if processes.isEmpty {
                    Text("目前沒有明顯的使用量")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(processes) { p in
                        HStack(spacing: 8) {
                            icon(for: p)
                                .frame(width: 16, height: 16)
                            Text(p.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(valueText(p.value))
                                .monospacedDigit()
                        }
                        .font(.callout)
                        .contextMenu {
                            // 「Port 管理與結束程式」啟用時，App 可以從這裡正常結束
                            if let path = p.appPath, AppSettings.shared.isInstalled(.portManager) {
                                Button("結束「\(p.name)」…") { PortManager.confirmQuit(appPath: path, name: p.name) }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func icon(for p: TopProcess) -> some View {
        if let path = p.appPath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
        } else {
            Image(systemName: "gearshape.fill")
                .resizable()
                .scaledToFit()
                .padding(2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - CPU／GPU

private struct CPUPanel: View {
    let cpu: CPUMonitor
    var showsGPU = true

    var body: some View {
        VStack(spacing: 10) {
            PanelHeader(symbol: "cpu", title: "CPU",
                        value: cpu.usage.map { ByteFormat.percent($0.total) } ?? "—",
                        detail: cpu.usage.map { "使用者 \(ByteFormat.percent($0.user))・系統 \(ByteFormat.percent($0.system))" } ?? "計算中…")
            Card {
                MonitorChart(points: cpu.history.points, a: ("CPU", .green), b: showsGPU ? ("GPU", .orange) : nil, percent: true)
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("各核心", systemImage: "square.grid.3x3")
                    let e = cpu.layout.efficiency
                    if cpu.cores.count > e, e > 0 {
                        CoreBars(title: "效能核心", cores: Array(cpu.cores[e...]), color: .green)
                        CoreBars(title: "節能核心", cores: Array(cpu.cores[..<e]), color: .mint)
                    } else {
                        CoreBars(title: "核心", cores: cpu.cores, color: .green)
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    if showsGPU {
                        InfoRow("GPU 使用率", cpu.gpu.map(ByteFormat.percent) ?? "—")
                        InfoRow("GPU 記憶體", cpu.gpuMemory.map(ByteFormat.memory) ?? "—")
                    }
                    InfoRow("平均負載（1／5／15 分）", cpu.load.isEmpty ? "—" : cpu.load.map { String(format: "%.2f", $0) }.joined(separator: "／"))
                }
            }
            if !cpu.fans.isEmpty || !cpu.temperatures.isEmpty {
                ThermalCard(fans: cpu.fans, temperatures: cpu.temperatures)
            }
            TopList(title: "CPU 使用率最高的 App", processes: cpu.topProcesses, loaded: cpu.topLoaded) {
                String(format: "%.1f%%", $0)
            }
        }
    }
}

/// 只看 GPU（不加底色時選單列的 GPU 圖示）：GPU 的歷史、詳細資料、溫度
private struct GPUPanel: View {
    let cpu: CPUMonitor

    var body: some View {
        VStack(spacing: 10) {
            PanelHeader(symbol: "cpu.fill", title: "GPU",
                        value: cpu.gpu.map(ByteFormat.percent) ?? "—",
                        detail: ChipInfo.shortName)
            Card {
                // 歷史紀錄裡第二條是 GPU：只畫 GPU 這條
                MonitorChart(points: cpu.history.points.map { MonitorPoint(id: $0.id, t: $0.t, a: $0.b, b: 0) },
                             a: ("GPU", .orange), b: nil, percent: true)
            }
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    InfoRow("晶片", ChipInfo.shortName)
                    if let cores = GPUReader.coreCount { InfoRow("GPU 核心", "\(cores)") }
                    InfoRow("使用率", cpu.gpu.map(ByteFormat.percent) ?? "—")
                    if cpu.gpuRenderer != nil { InfoRow("Renderer 使用率", cpu.gpuRenderer.map(ByteFormat.percent) ?? "—") }
                    if cpu.gpuTiler != nil { InfoRow("Tiler 使用率", cpu.gpuTiler.map(ByteFormat.percent) ?? "—") }
                    InfoRow("GPU 記憶體", cpu.gpuMemory.map(ByteFormat.memory) ?? "—")
                }
            }
            if !cpu.fans.isEmpty || !cpu.temperatures.isEmpty {
                ThermalCard(fans: cpu.fans, temperatures: cpu.temperatures)
            }
        }
    }
}

/// 風扇轉速與溫度；機型沒有風扇或沒有感測器的部分整塊不顯示
private struct ThermalCard: View {
    let fans: [FanReading]
    let temperatures: TemperatureSummary

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(fans.isEmpty ? "溫度" : "風扇與溫度", systemImage: "thermometer.medium")
                if !temperatures.isEmpty {
                    if temperatures.coreSensorsAsleep {
                        InfoRow("CPU／GPU", "核心休眠中，暫無讀值")
                    }
                    temperatureRow("CPU", temperatures.cpu)
                    temperatureRow("GPU", temperatures.gpu)
                    temperatureRow("SoC 晶片", temperatures.soc)
                    temperatureRow("電池", temperatures.battery)
                    temperatureRow("儲存裝置", temperatures.storage)
                }
                ForEach(fans) { fan in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(fan.name).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(fan.rpm.rounded())) RPM・\(ByteFormat.percent(fan.fraction))").monospacedDigit()
                        }
                        ProgressView(value: fan.fraction).tint(.cyan)
                    }
                }
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private func temperatureRow(_ title: String, _ stat: TemperatureSummary.Stat?) -> some View {
        if let stat {
            InfoRow(title, abs(stat.average - stat.maximum) < 0.05
                    ? String(format: "%.1f°C", stat.average)
                    : String(format: "%.1f°C（最高 %.1f°C）", stat.average, stat.maximum))
        }
    }
}

private struct CoreBars: View {
    let title: String
    let cores: [CPUUsage]
    let color: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(cores.enumerated()), id: \.offset) { _, core in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 2).fill(color.gradient)
                            .frame(height: max(2, 30 * core.total))
                    }
                    .frame(width: 14, height: 30)
                    .help(ByteFormat.percent(core.total))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 記憶體

private struct MemoryPanel: View {
    let memory: MemoryMonitor

    var body: some View {
        VStack(spacing: 10) {
            if let m = memory.usage {
                PanelHeader(symbol: "memorychip", title: "記憶體",
                            value: ByteFormat.percent(m.usedFraction),
                            detail: "已使用 \(ByteFormat.memory(m.used)) / \(ByteFormat.memory(m.total))",
                            tint: tint(m.pressure))
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        CompositionBar(segments: segments(m), total: m.total)
                        ForEach(segments(m), id: \.name) { s in
                            InfoRow(s.name, ByteFormat.memory(s.bytes), tint: s.color)
                        }
                    }
                }
                Card {
                    MonitorChart(points: memory.history.points, a: ("已使用", .blue), b: nil, percent: true)
                }
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        InfoRow("記憶體壓力", m.pressure.title)
                        InfoRow("Swap 已使用", m.swapTotal > 0 ? "\(ByteFormat.memory(m.swapUsed)) / \(ByteFormat.memory(m.swapTotal))" : "未使用")
                    }
                }
            } else {
                PanelHeader(symbol: "memorychip", title: "記憶體", value: "—", detail: "讀取中…")
            }
            TopList(title: "使用記憶體最多的 App", processes: memory.topProcesses, loaded: memory.topLoaded) {
                ByteFormat.memory(UInt64($0))
            }
        }
    }

    private struct Segment {
        let name: String
        let bytes: UInt64
        let color: Color
    }

    private func segments(_ m: MemoryUsage) -> [Segment] {
        [
            Segment(name: "App 記憶體", bytes: m.app, color: .blue),
            Segment(name: "系統保留", bytes: m.wired, color: .orange),
            Segment(name: "已壓縮", bytes: m.compressed, color: .purple),
            Segment(name: "檔案快取", bytes: m.cached, color: .gray),
            Segment(name: "可用", bytes: m.free, color: Color.primary.opacity(0.12)),
        ]
    }

    private func tint(_ pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: return .primary
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private struct CompositionBar: View {
        let segments: [Segment]
        let total: UInt64

        var body: some View {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(segments, id: \.name) { s in
                        Rectangle()
                            .fill(s.color)
                            .frame(width: total > 0 ? max(0, geo.size.width * CGFloat(Double(s.bytes) / Double(total)) - 1) : 0)
                    }
                }
            }
            .frame(height: 10)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}

// MARK: - 磁碟

private struct DiskPanel: View {
    let disk: DiskMonitor

    var body: some View {
        VStack(spacing: 10) {
            let v = disk.volume
            DiskSection(symbol: "internaldrive", name: v?.name ?? "磁碟", total: v?.total, available: v?.available,
                        fileSystem: v?.fileSystem ?? "", connection: v?.connection ?? "", health: disk.volumeHealth,
                        lifetime: disk.volumeLifetime, readRate: disk.readRate, writeRate: disk.writeRate, history: disk.history,
                        totalRead: disk.totalRead, totalWritten: disk.totalWritten, totalsTitle: "開機以來")
            ForEach(disk.externalVolumes) { volume in
                let usage = disk.externalStats[volume.id] ?? ExternalDiskStats()
                DiskSection(symbol: "externaldrive", name: volume.name, total: volume.total, available: volume.available,
                            fileSystem: volume.fileSystem, connection: volume.connection, health: usage.health,
                            lifetime: usage.lifetime, readRate: usage.readRate, writeRate: usage.writeRate, history: usage.history,
                            totalRead: usage.totalRead, totalWritten: usage.totalWritten, totalsTitle: "接上以來")
            }
        }
    }
}

/// 一顆磁碟的完整資訊：標題、容量、檔案系統、健康度、讀寫速度與累計。本機與外接磁碟共用。
/// 讀得到 NVMe SMART 時，健康度改成百分比，累計讀寫改成硬碟自己記錄的出廠以來總量
private struct DiskSection: View {
    let symbol: String
    let name: String
    let total: UInt64?
    let available: UInt64?
    let fileSystem: String
    let connection: String
    let health: DiskHealth?
    let lifetime: DiskLifetime?
    let readRate: Double
    let writeRate: Double
    let history: MonitorHistory
    let totalRead: UInt64
    let totalWritten: UInt64
    let totalsTitle: String

    var body: some View {
        let used = total.flatMap { total in available.map { total > $0 ? total - $0 : 0 } }
        let fraction = total.flatMap { total in total > 0 ? used.map { Double($0) / Double(total) } : nil } ?? 0
        VStack(spacing: 10) {
            PanelHeader(symbol: symbol, title: name,
                        value: total == nil ? "—" : ByteFormat.percent(fraction),
                        detail: total.flatMap { total in available.map { "可用 \(ByteFormat.size($0))・共 \(ByteFormat.size(total))" } } ?? "讀取中…")
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: fraction)
                        .tint(fraction > 0.9 ? .red : fraction > 0.8 ? .orange : .blue)
                    detailRows(used: used)
                }
            }
            activityCards
        }
    }

    @ViewBuilder
    private func detailRows(used: UInt64?) -> some View {
        InfoRow("已使用", used.map(ByteFormat.size) ?? "—")
        InfoRow("可用", available.map(ByteFormat.size) ?? "—")
        InfoRow("總容量", total.map(ByteFormat.size) ?? "—")
        if !fileSystem.isEmpty { InfoRow("檔案系統", fileSystem.uppercased()) }
        if !connection.isEmpty { InfoRow("連線類型", connection) }
        if let lifetime {
            lifetimeRows(lifetime)
        } else {
            smartStatusRow
        }
    }

    @ViewBuilder
    private func lifetimeRows(_ lifetime: DiskLifetime) -> some View {
        let percent = lifetime.healthPercent
        if lifetime.isFailing {
            InfoRow("健康度", "\(percent)%・硬碟回報異常，建議立即備份", tint: .red)
        } else {
            InfoRow("健康度", "\(percent)%", tint: percent >= 70 ? .green : percent >= 30 ? .orange : .red)
        }
        if lifetime.mediaErrors > 0 {
            InfoRow("媒體錯誤", "\(lifetime.mediaErrors) 次", tint: .orange)
        }
    }

    @ViewBuilder
    private var smartStatusRow: some View {
        switch health {
        case .verified: InfoRow("健康度（SMART）", "正常", tint: .green)
        case .failing: InfoRow("健康度（SMART）", "異常，建議立即備份", tint: .red)
        case .unsupported: InfoRow("健康度（SMART）", "此裝置不支援")
        case .unknown: InfoRow("健康度（SMART）", "無法讀取")
        case nil: InfoRow("健康度（SMART）", "讀取中…")
        }
    }

    private var activityCards: some View {
        VStack(spacing: 10) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow("讀取", ByteFormat.rate(readRate), tint: .green)
                    InfoRow("寫入", ByteFormat.rate(writeRate), tint: .orange)
                    MonitorChart(points: history.points, a: ("讀取", .green), b: ("寫入", .orange), showsLegend: false)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    if let lifetime {
                        CardTitle("出廠以來", systemImage: "clock.arrow.circlepath")
                        InfoRow("累計讀取", ByteFormat.size(lifetime.bytesRead))
                        InfoRow("累計寫入", ByteFormat.size(lifetime.bytesWritten))
                        InfoRow("通電時間", DiskSection.hours(lifetime.powerOnHours))
                    } else {
                        CardTitle(totalsTitle, systemImage: "clock.arrow.circlepath")
                        InfoRow("累計讀取", ByteFormat.size(totalRead))
                        InfoRow("累計寫入", ByteFormat.size(totalWritten))
                    }
                }
            }
        }
    }
}

extension DiskSection {
    /// 通電時間："2,306 小時（約 96 天）"
    static func hours(_ hours: UInt64) -> String {
        let text = "\(hours.formatted()) 小時"
        return hours >= 48 ? text + "（約 \((hours / 24).formatted()) 天）" : text
    }
}

// MARK: - 網路

private struct NetworkPanel: View {
    let network: NetworkMonitor
    let showsSpeedTest: Bool

    var body: some View {
        VStack(spacing: 10) {
            PanelHeader(symbol: "network", title: network.kind.map { "\($0)（\(network.interface ?? "")）" } ?? "網路",
                        value: "↓ " + ByteFormat.rate(network.downloadRate),
                        detail: network.interface == nil ? "未連線" : "IP \(network.address ?? "—")")
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow("下載", ByteFormat.rate(network.downloadRate), tint: .green)
                    InfoRow("上傳", ByteFormat.rate(network.uploadRate), tint: .orange)
                    MonitorChart(points: network.history.points, a: ("下載", .green), b: ("上傳", .orange), showsLegend: false)
                }
            }
            ConnectionStatusCard(status: NetworkStatusMonitor.shared)
            if AppSettings.shared.isInstalled(.portManager) { PortsCard(manager: PortManager.shared) }
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    CardTitle("開機以來（目前的網路介面）", systemImage: "clock.arrow.circlepath")
                    InfoRow("累計下載", ByteFormat.size(network.totalReceived))
                    InfoRow("累計上傳", ByteFormat.size(network.totalSent))
                }
            }
            if showsSpeedTest {
                SpeedTestCard(test: network.speedTest)
            }
        }
    }
}

/// 監聽中的連接埠：打開面板時讀一次，可以重新整理、結束自己帳號的程式（會先確認）
private struct PortsCard: View {
    let manager: PortManager

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    CardTitle("監聽中的連接埠", systemImage: "point.3.connected.trianglepath.dotted")
                    Spacer()
                    Button { manager.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("重新整理")
                        .accessibilityLabel("重新整理連接埠")
                }
                if manager.listeners.isEmpty {
                    Text(manager.loading ? "讀取中…" : "沒有你的程式在監聽 TCP 連接埠").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(manager.listeners) { listener in
                    HStack(spacing: 8) {
                        Text("\(listener.port)").monospacedDigit().frame(width: 52, alignment: .leading)
                        Text(listener.command).lineLimit(1).truncationMode(.middle)
                        if listener.localOnly { Text("只限本機").font(.caption2).foregroundStyle(.secondary) }
                        Spacer(minLength: 4)
                        Button("結束") { manager.confirmTerminate(listener) }
                            .controlSize(.small)
                            .accessibilityLabel("結束 \(listener.command)（連接埠 \(listener.port)）")
                    }
                    .font(.callout)
                }
                Text("只列出你自己帳號的程式；結束前會先確認，並請程式正常結束。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { manager.refresh() }
    }
}

/// 連線狀態：VPN、低數據模式、按流量計費。面板打開時才監看，不連到外部伺服器
private struct ConnectionStatusCard: View {
    let status: NetworkStatusMonitor

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                CardTitle("連線狀態", systemImage: "lock.shield")
                InfoRow("VPN", status.vpnInterfaces.isEmpty ? "沒有連線" : "已連線（\(status.vpnInterfaces.joined(separator: "、"))）",
                        tint: status.vpnInterfaces.isEmpty ? nil : .green)
                ForEach(status.notes, id: \.self) { note in
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onAppear { status.start() }
        .onDisappear { status.stop() }
    }
}

private struct SpeedTestCard: View {
    let test: NetworkSpeedTest

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    CardTitle("網路測速", systemImage: "speedometer")
                    Spacer()
                    if test.isRunning {
                        ProgressView().controlSize(.small)
                        Button("停止") { test.cancel() }
                            .controlSize(.small)
                    } else {
                        Button(test.result == nil ? "開始測速" : "重新測速") { test.start() }
                            .controlSize(.small)
                    }
                }
                if test.isRunning {
                    InfoRow("下載（即時）", SpeedTestResult.bitRate(test.liveDownload * 8), tint: .green)
                    InfoRow("上傳（即時）", SpeedTestResult.bitRate(test.liveUpload * 8), tint: .orange)
                    note("即時數字是整個網路介面的流量，包含其他程式；正式結果以測完為準")
                } else if let result = test.result {
                    InfoRow("下載", result.download.map(SpeedTestResult.bitRate) ?? "—", tint: .green)
                    InfoRow("上傳", result.upload.map(SpeedTestResult.bitRate) ?? "—", tint: .orange)
                    InfoRow("回應能力", result.responsiveness.map { String(format: "%.0f RPM", $0) } ?? "—")
                        .help("網路忙碌時每分鐘能完成的往返次數，越高越不容易卡頓")
                    InfoRow("閒置延遲", result.idleLatency.map { String(format: "%.0f ms", $0) } ?? "—")
                    if let missing = result.missingPart {
                        note("這次沒有測到\(missing)速度（通常是測速伺服器的連線逾時），可以再測一次", color: .orange)
                    }
                    note("\(result.date.formatted(date: .omitted, time: .shortened)) 測試・Apple 測速伺服器")
                }
                if case .failed(let message) = test.phase {
                    note(message, color: .red)
                } else if !test.isRunning, test.result == nil {
                    note("約需 20～30 秒，會用掉數百 MB 流量，使用行動網路時請留意")
                }
            }
        }
    }

    private func note(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}
