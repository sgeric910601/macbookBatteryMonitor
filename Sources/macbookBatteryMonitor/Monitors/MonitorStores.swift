import Foundation
import Combine

/// 各模組由 ModuleCoordinator 依更新頻率呼叫 sample()；面板打開時另外接收 top 的程序排行

@MainActor
final class CPUMonitor: ObservableObject {
    @Published private(set) var usage: CPUUsage?
    @Published private(set) var cores: [CPUUsage] = []
    @Published private(set) var gpu: Double?
    @Published private(set) var gpuMemory: UInt64?
    @Published private(set) var load: [Double] = []
    /// a：CPU 總使用率、b：GPU 使用率（0～1）
    @Published private(set) var history = MonitorHistory()
    @Published private(set) var topProcesses: [TopProcess] = []
    @Published private(set) var topLoaded = false
    @Published private(set) var updated: Date?
    /// 這台 Mac 的風扇與溫度；沒有風扇時 fans 為空，介面就不顯示風扇區塊
    @Published private(set) var fans: [FanReading] = []
    @Published private(set) var temperatures = TemperatureSummary()
    let layout = CPUReader.coreLayout

    private var lastTicks: [CPUTicks]?
    private let thermal = ThermalReader()
    private var lastThermal: Date?
    private var thermalBusy = false
    /// 只有 CPU 面板開著時才讀風扇與溫度（讀一次要幾十毫秒），選單列圖示用不到
    private var thermalActive = false

    func setThermalActive(_ active: Bool) {
        thermalActive = active
        if active { lastThermal = nil }
    }

    func sample(at now: Date = Date()) {
        if let ticks = CPUReader.ticks() {
            if let last = lastTicks, let result = CPUMath.usages(from: last, to: ticks) {
                usage = result.total
                cores = result.cores
            }
            lastTicks = ticks
        }
        let gpuReading = GPUReader.read()
        gpu = gpuReading.utilization
        gpuMemory = gpuReading.memory
        load = CPUReader.loadAverage()
        if let usage { history.append(usage.total, gpu ?? 0, at: now) }
        // 風扇與溫度變化慢，每 2 秒讀一次就夠；在背景讀，上一次還沒回來就跳過
        if thermalActive, !thermalBusy, lastThermal.map({ now.timeIntervalSince($0) >= 2 }) ?? true {
            lastThermal = now
            thermalBusy = true
            let reader = thermal
            DispatchQueue.global(qos: .utility).async {
                let fans = reader.fans()
                let temperatures = reader.temperatures(now: now)
                Task { @MainActor [weak self] in
                    self?.fans = fans
                    self?.temperatures = temperatures
                    self?.thermalBusy = false
                }
            }
        }
        updated = now
    }

    func receiveTop(_ text: String) {
        let list = ProcessOwner.group(TopParse.rows(text), value: { Double($0) }, limit: 5)
        // top 第一段沒有差值，CPU 欄全為 0；拿到有效資料才更新
        guard !list.isEmpty else { return }
        topProcesses = list
        topLoaded = true
    }

    func clearTop() {
        topProcesses = []
        topLoaded = false
    }
}

@MainActor
final class MemoryMonitor: ObservableObject {
    @Published private(set) var usage: MemoryUsage?
    /// a：已使用比例（0～1）
    @Published private(set) var history = MonitorHistory()
    @Published private(set) var topProcesses: [TopProcess] = []
    @Published private(set) var topLoaded = false
    @Published private(set) var updated: Date?

    func sample(at now: Date = Date()) {
        if let reading = MemoryReader.read() {
            usage = reading
            history.append(reading.usedFraction, at: now)
        }
        updated = now
    }

    func receiveTop(_ text: String) {
        topProcesses = ProcessOwner.group(TopParse.rows(text), value: TopParse.memoryBytes, limit: 5)
        topLoaded = true
    }

    func clearTop() {
        topProcesses = []
        topLoaded = false
    }
}

@MainActor
final class DiskMonitor: ObservableObject {
    @Published private(set) var volume: DiskReader.Volume?
    /// 本機磁碟的 SMART 狀態（diskutil；讀不到 NVMe SMART 時才查）
    @Published private(set) var volumeHealth: DiskHealth?
    /// 本機磁碟自己記錄的出廠以來讀寫量與已用壽命（NVMe SMART）
    @Published private(set) var volumeLifetime: DiskLifetime?
    /// 目前掛載的外接磁碟，與各自的讀寫統計（key 為掛載點）
    @Published private(set) var externalVolumes: [ExternalVolume] = []
    @Published private(set) var externalStats: [String: ExternalDiskStats] = [:]
    @Published private(set) var readRate: Double = 0
    @Published private(set) var writeRate: Double = 0
    /// 自開機以來的累計讀寫
    @Published private(set) var totalRead: UInt64 = 0
    @Published private(set) var totalWritten: UInt64 = 0
    /// a：讀取、b：寫入（位元組／秒）
    @Published private(set) var history = MonitorHistory()
    @Published private(set) var updated: Date?

    private var last: (read: UInt64, written: UInt64, date: Date)?
    private var externalLast: [String: (read: UInt64, written: UInt64, date: Date)] = [:]
    /// 掛載點 → 上次查 SMART 的時間；SMART 變化很慢，每 10 分鐘在背景查一次
    private var healthChecked: [String: Date] = [:]
    private var volumeHealthChecked: Date?
    /// 正在查 SMART 的裝置節點，避免同一顆卡住時重複派工
    private var healthInFlight: Set<String> = []
    /// 只有磁碟面板開著時才查 SMART：要啟動 diskutil，還可能喚醒休眠中的外接硬碟
    private var healthActive = false
    /// 讀不到 NVMe SMART 的裝置節點，改用 diskutil；卸載後移除，節點被別的裝置重用時才會重新判斷
    private var lifetimeUnsupported: Set<String> = []
    private var lifetimeInFlight: Set<String> = []
    private static let smartQueue = DispatchQueue(label: "DiskMonitor.smart", qos: .utility)

    func setHealthActive(_ active: Bool) { healthActive = active }

    func sample(at now: Date = Date()) {
        if let reading = DiskReader.startupVolume() { volume = reading }
        externalVolumes = DiskReader.externalVolumes()
        let liveNodes = Set(externalVolumes.map(\.deviceNode) + [volume?.deviceNode ?? ""])
        DiskReader.pruneDriverCache(keeping: liveNodes)
        lifetimeUnsupported.formIntersection(liveNodes)
        sampleExternal(at: now)
        if healthActive { checkVolumeHealth(at: now) }
        // 優先讀開機磁碟自己的統計，讀不到才退回所有儲存裝置合計
        if let io = volume.flatMap({ DiskReader.ioBytes(forDevice: $0.deviceNode) }) ?? DiskReader.ioBytes() {
            if let last {
                let interval = now.timeIntervalSince(last.date)
                readRate = RateMath.perSecond(old: last.read, new: io.read, interval: interval)
                writeRate = RateMath.perSecond(old: last.written, new: io.written, interval: interval)
                history.append(readRate, writeRate, at: now)
            }
            last = (io.read, io.written, now)
            totalRead = io.read
            totalWritten = io.written
        }
        updated = now
    }

    /// 讀 NVMe 硬碟自己記錄的 SMART 資料。面板開著時每次取樣都讀（約 0.2 毫秒），總讀寫量會即時增加。
    /// 這顆讀不到時回傳 false，由呼叫端改用 diskutil
    private func readLifetime(node: String, apply: @escaping @MainActor (DiskLifetime) -> Void) -> Bool {
        guard !lifetimeUnsupported.contains(node) else { return false }
        guard !lifetimeInFlight.contains(node) else { return true }
        lifetimeInFlight.insert(node)
        Self.smartQueue.async { [weak self] in
            let result = DiskReader.lifetime(forDevice: node)
            Task { @MainActor in
                guard let self else { return }
                self.lifetimeInFlight.remove(node)
                switch result {
                case .data(let lifetime): apply(lifetime)
                case .unsupported: self.lifetimeUnsupported.insert(node)
                case .failed: break
                }
            }
        }
        return true
    }

    private func checkVolumeHealth(at now: Date) {
        guard let node = volume?.deviceNode, !node.isEmpty else { return }
        let viaSMART = readLifetime(node: node) { [weak self] lifetime in
            guard let self, volume?.deviceNode == node else { return }
            volumeLifetime = lifetime
        }
        guard !viaSMART, !healthInFlight.contains(node),
              volumeHealthChecked.map({ now.timeIntervalSince($0) > 600 }) ?? true else { return }
        volumeHealthChecked = now
        healthInFlight.insert(node)
        DispatchQueue.global(qos: .utility).async {
            let health = DiskReader.smartStatus(forDevice: node)
            Task { @MainActor [weak self] in
                self?.healthInFlight.remove(node)
                self?.volumeHealth = health
            }
        }
    }

    private func sampleExternal(at now: Date) {
        let live = Set(externalVolumes.map(\.id))
        externalStats = externalStats.filter { live.contains($0.key) }
        externalLast = externalLast.filter { live.contains($0.key) }
        healthChecked = healthChecked.filter { live.contains($0.key) }
        for volume in externalVolumes {
            var usage = externalStats[volume.id] ?? ExternalDiskStats()
            if let io = DiskReader.ioBytes(forDevice: volume.deviceNode) {
                if let previous = externalLast[volume.id] {
                    let interval = now.timeIntervalSince(previous.date)
                    usage.readRate = RateMath.perSecond(old: previous.read, new: io.read, interval: interval)
                    usage.writeRate = RateMath.perSecond(old: previous.written, new: io.written, interval: interval)
                    usage.history.append(usage.readRate, usage.writeRate, at: now)
                }
                externalLast[volume.id] = (io.read, io.written, now)
                usage.totalRead = io.read
                usage.totalWritten = io.written
            }
            externalStats[volume.id] = usage
            guard healthActive else { continue }
            let id = volume.id, node = volume.deviceNode
            let viaSMART = readLifetime(node: node) { [weak self] lifetime in
                // 期間若換成別的裝置（同掛載點），不要把舊裝置的結果貼上去
                guard let self, externalVolumes.first(where: { $0.id == id })?.deviceNode == node else { return }
                externalStats[id]?.lifetime = lifetime
            }
            if !viaSMART, !healthInFlight.contains(node),
               healthChecked[id].map({ now.timeIntervalSince($0) > 600 }) ?? true {
                healthChecked[id] = now
                healthInFlight.insert(node)
                DispatchQueue.global(qos: .utility).async {
                    let health = DiskReader.smartStatus(forDevice: node)
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        healthInFlight.remove(node)
                        // 期間若換成別的裝置（同掛載點），不要把舊裝置的結果貼上去
                        if externalVolumes.first(where: { $0.id == id })?.deviceNode == node {
                            externalStats[id]?.health = health
                        }
                    }
                }
            }
        }
    }
}

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var interface: String?
    /// Wi-Fi、乙太網路等
    @Published private(set) var kind: String?
    @Published private(set) var address: String?
    @Published private(set) var downloadRate: Double = 0
    @Published private(set) var uploadRate: Double = 0
    /// 目前介面自開機以來的累計收發
    @Published private(set) var totalReceived: UInt64 = 0
    @Published private(set) var totalSent: UInt64 = 0
    /// a：下載、b：上傳（位元組／秒）
    @Published private(set) var history = MonitorHistory()
    @Published private(set) var updated: Date?
    /// 面板關閉後繼續測，下次打開仍看得到結果
    let speedTest = NetworkSpeedTest()

    private var last: (interface: String, received: UInt64, sent: UInt64, date: Date)?

    func sample(at now: Date = Date()) {
        let primary = NetworkReader.primaryInterface()
        if primary != interface {
            interface = primary
            // 介面類型查詢較慢，只在切換網路時查
            kind = primary.map(NetworkReader.kind(of:))
            last = nil
        }
        address = primary.flatMap(NetworkReader.ipv4Address(of:))

        guard let primary, let counter = NetworkReader.counters(for: primary) else {
            downloadRate = 0
            uploadRate = 0
            history.append(0, 0, at: now)
            updated = now
            return
        }
        if let last, last.interface == primary {
            let interval = now.timeIntervalSince(last.date)
            downloadRate = RateMath.perSecond(old: last.received, new: counter.received, interval: interval)
            uploadRate = RateMath.perSecond(old: last.sent, new: counter.sent, interval: interval)
            history.append(downloadRate, uploadRate, at: now)
        }
        last = (primary, counter.received, counter.sent, now)
        totalReceived = counter.received
        totalSent = counter.sent
        updated = now
    }
}

// MARK: - 截圖用的示範數據（README、版本說明），不含任何使用者的真實資料

private func previewHistory(count: Int = MonitorHistory.capacity, now: Date, _ value: (Double) -> (Double, Double)) -> MonitorHistory {
    var history = MonitorHistory()
    for i in 0..<count {
        let v = value(Double(i))
        history.append(v.0, v.1, at: now.addingTimeInterval(Double(i - count)))
    }
    return history
}

private func previewApps(_ values: [Double]) -> [TopProcess] {
    let apps = [("Safari", "/Applications/Safari.app"), ("照片", "/System/Applications/Photos.app"),
                ("音樂", "/System/Applications/Music.app"), ("郵件", "/System/Applications/Mail.app"),
                ("Finder", "/System/Library/CoreServices/Finder.app")]
    return zip(apps, values).map { TopProcess(id: $0.0.1, name: $0.0.0, value: $0.1, appPath: $0.0.1) }
}

extension CPUMonitor {
    func loadPreview(now: Date = Date()) {
        usage = CPUUsage(user: 0.18, system: 0.09)
        let e = max(layout.efficiency, 4), p = max(layout.performance, 4)
        cores = (0..<e).map { CPUUsage(user: 0.30 - Double($0) * 0.04, system: 0.10) }
            + (0..<p).map { CPUUsage(user: 0.20 - Double($0) * 0.04, system: 0.05) }
        gpu = 0.12
        gpuMemory = 512 * 1024 * 1024
        load = [2.35, 2.10, 1.98]
        history = previewHistory(now: now) { (0.25 + 0.08 * sin($0 / 7) + 0.04 * sin($0 / 2.3), 0.10 + 0.05 * sin($0 / 11)) }
        topProcesses = previewApps([34.5, 12.2, 8.1, 3.4, 1.6])
        topLoaded = true
        fans = [FanReading(id: 0, name: "左側風扇", rpm: 2323, minRPM: 2317, maxRPM: 6800),
                FanReading(id: 1, name: "右側風扇", rpm: 2509, minRPM: 2317, maxRPM: 6800)]
        temperatures = TemperatureSummary(cpu: .init(average: 52.0, maximum: 54.7), gpu: .init(average: 50.7, maximum: 51.3),
                                          soc: .init(average: 47.5, maximum: 49.2), battery: .init(average: 34.5, maximum: 34.5),
                                          storage: .init(average: 38.9, maximum: 38.9))
        updated = now
    }
}

extension MemoryMonitor {
    func loadPreview(now: Date = Date()) {
        let gib: UInt64 = 1024 * 1024 * 1024
        usage = MemoryUsage(total: 16 * gib, app: 6 * gib + gib / 4, wired: 2 * gib + gib / 10, compressed: gib + gib / 2,
                            cached: 3 * gib + gib / 2, swapUsed: 0, swapTotal: 0, pressure: .normal)
        history = previewHistory(now: now) { (0.61 + 0.015 * sin($0 / 13), 0) }
        topProcesses = previewApps([1.8, 0.82, 0.41, 0.38, 0.16].map { $0 * Double(gib) })
        topLoaded = true
        updated = now
    }
}

extension DiskMonitor {
    func loadPreview(now: Date = Date()) {
        volume = DiskReader.Volume(name: "Macintosh HD", total: 494_384_795_648, available: 312_000_000_000,
                                   fileSystem: "apfs", connection: "Apple Fabric")
        volumeHealth = .verified
        volumeLifetime = DiskLifetime(percentageUsed: 2, availableSpare: 100, spareThreshold: 99, criticalWarning: 0,
                                      bytesRead: 41_300_000_000_000, bytesWritten: 28_600_000_000_000,
                                      powerOnHours: 1512, mediaErrors: 0)
        externalVolumes = [
            ExternalVolume(mountPoint: "/Volumes/Backup", name: "Backup", total: 2_000_000_000_000, available: 1_240_000_000_000,
                           fileSystem: "apfs", connection: "Thunderbolt"),
            ExternalVolume(mountPoint: "/Volumes/USB", name: "USB", total: 64_000_000_000, available: 57_000_000_000,
                           fileSystem: "exfat", connection: "USB"),
        ]
        externalStats = [
            "/Volumes/Backup": ExternalDiskStats(readRate: 38_000_000, writeRate: 12_000_000, totalRead: 640_000_000_000,
                                                 totalWritten: 210_000_000_000,
                                                 history: previewHistory(now: now) { i in (max(0, 30_000_000 + 20_000_000 * sin(i / 6)), max(0, 9_000_000 + 8_000_000 * sin(i / 9))) },
                                                 health: .verified,
                                                 lifetime: DiskLifetime(percentageUsed: 12, availableSpare: 100, spareThreshold: 10,
                                                                        criticalWarning: 0, bytesRead: 48_200_000_000_000,
                                                                        bytesWritten: 31_700_000_000_000, powerOnHours: 5120, mediaErrors: 0)),
            "/Volumes/USB": ExternalDiskStats(totalRead: 4_000_000_000, totalWritten: 1_200_000_000, history: previewHistory(now: now) { _ in (0, 0) },
                                              health: .unsupported),
        ]
        readRate = 2_400_000
        writeRate = 900_000
        totalRead = 85_000_000_000
        totalWritten = 41_000_000_000
        history = previewHistory(now: now) { i in
            (max(0, 1_500_000 + 1_200_000 * sin(i / 5)), max(0, 600_000 + 500_000 * sin(i / 8 + 1)))
        }
        updated = now
    }
}

extension NetworkMonitor {
    func loadPreview(now: Date = Date()) {
        interface = "en0"
        kind = "Wi-Fi"
        address = "192.168.1.23"
        downloadRate = 2_800_000
        uploadRate = 340_000
        totalReceived = 12_400_000_000
        totalSent = 1_900_000_000
        history = previewHistory(now: now) { i in
            (max(0, 2_000_000 + 1_500_000 * sin(i / 6)), max(0, 300_000 + 150_000 * sin(i / 4 + 2)))
        }
        updated = now
    }
}
