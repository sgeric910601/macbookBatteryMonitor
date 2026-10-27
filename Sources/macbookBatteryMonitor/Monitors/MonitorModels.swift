import Foundation

/// 系統監控模組（每個模組在選單列各有一個圖示）
enum MonitorKind: String, CaseIterable, Identifiable, Codable {
    case cpu
    case memory
    case disk
    case network

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU／GPU"
        case .memory: return "記憶體"
        case .disk: return "磁碟"
        case .network: return "網路"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        }
    }
}

extension MonitorKind {
    /// 記憶體與磁碟合併成一個圖示：開關打開，且兩個模組都開著
    static func mergesMemoryDisk(merge: Bool, memory: Bool, disk: Bool) -> Bool { merge && memory && disk }

    /// 合併時磁碟併入記憶體的圖示，不再單獨出現
    static func shown(_ enabled: [MonitorKind], memoryDiskMerged: Bool) -> [MonitorKind] {
        memoryDiskMerged ? enabled.filter { $0 != .disk } : enabled
    }
}

// MARK: - CPU

/// 單一核心（或全部核心加總）的累計 tick
struct CPUTicks: Equatable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64

    static func + (a: CPUTicks, b: CPUTicks) -> CPUTicks {
        CPUTicks(user: a.user + b.user, system: a.system + b.system, idle: a.idle + b.idle, nice: a.nice + b.nice)
    }
}

struct CPUUsage: Codable, Equatable {
    /// 0～1
    var user: Double
    var system: Double
    var total: Double { user + system }
}

enum CPUMath {
    /// 兩次累計 tick 的差值換算成使用率；計數器回繞或重置（差值為負）時回傳 nil
    static func usage(from old: CPUTicks, to new: CPUTicks) -> CPUUsage? {
        guard new.user >= old.user, new.system >= old.system,
              new.idle >= old.idle, new.nice >= old.nice else { return nil }
        let user = Double((new.user - old.user) + (new.nice - old.nice))
        let system = Double(new.system - old.system)
        let idle = Double(new.idle - old.idle)
        let total = user + system + idle
        guard total > 0 else { return nil }
        return CPUUsage(user: user / total, system: system / total)
    }

    static func usages(from old: [CPUTicks], to new: [CPUTicks]) -> (total: CPUUsage, cores: [CPUUsage])? {
        guard old.count == new.count, !new.isEmpty,
              let total = usage(from: old.reduce(CPUTicks(user: 0, system: 0, idle: 0, nice: 0), +),
                                to: new.reduce(CPUTicks(user: 0, system: 0, idle: 0, nice: 0), +)) else { return nil }
        let cores = zip(old, new).map { usage(from: $0, to: $1) ?? CPUUsage(user: 0, system: 0) }
        return (total, cores)
    }
}

// MARK: - 記憶體

enum MemoryPressure: Int, Codable {
    case normal = 1
    case warning = 2
    case critical = 4

    var title: String {
        switch self {
        case .normal: return "正常"
        case .warning: return "警告"
        case .critical: return "嚴重"
        }
    }
}

/// 以位元組為單位；分類方式與「活動監視器」相同
struct MemoryUsage: Codable, Equatable {
    var total: UInt64
    /// App 記憶體（匿名頁面扣掉可清除的部分）
    var app: UInt64
    var wired: UInt64
    var compressed: UInt64
    /// 檔案快取（檔案對應頁面加上可清除的部分），需要時可以釋放
    var cached: UInt64
    var swapUsed: UInt64
    var swapTotal: UInt64
    var pressure: MemoryPressure

    var used: UInt64 { app + wired + compressed }
    var free: UInt64 { total > used + cached ? total - used - cached : 0 }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

enum MemoryMath {
    /// 由 vm_statistics64 的頁數換算；各項以頁為單位
    static func usage(pageSize: UInt64, internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64,
                      compressedPages: UInt64, externalPages: UInt64, total: UInt64,
                      swapUsed: UInt64, swapTotal: UInt64, pressure: MemoryPressure) -> MemoryUsage {
        let app = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        return MemoryUsage(total: total, app: app * pageSize, wired: wiredPages * pageSize,
                           compressed: compressedPages * pageSize, cached: (externalPages + purgeablePages) * pageSize,
                           swapUsed: swapUsed, swapTotal: swapTotal, pressure: pressure)
    }
}

// MARK: - 速率與格式

enum RateMath {
    /// 累計位元組換算成每秒速率；計數器歸零或回繞時回傳 0
    static func perSecond(old: UInt64, new: UInt64, interval: TimeInterval) -> Double {
        guard interval > 0, new >= old else { return 0 }
        return Double(new - old) / interval
    }
}

enum ByteFormat {
    /// 容量（十進位，與 Finder 一致）："245 GB"
    static func size(_ bytes: UInt64) -> String {
        format(Double(bytes), base: 1000, units: ["B", "KB", "MB", "GB", "TB"])
    }

    /// 記憶體（二進位，與「活動監視器」一致）："5.2 GB"
    static func memory(_ bytes: UInt64) -> String {
        format(Double(bytes), base: 1024, units: ["B", "KB", "MB", "GB", "TB"])
    }

    /// 傳輸速率："1.2 MB/s"
    static func rate(_ bytesPerSecond: Double) -> String {
        format(bytesPerSecond, base: 1000, units: ["B", "KB", "MB", "GB"]) + "/s"
    }

    /// 選單列用的精簡速率："1.2M"、"340K"、"0K"
    static func compactRate(_ bytesPerSecond: Double) -> String {
        let units = ["K", "M", "G"]
        var value = max(0, bytesPerSecond) / 1000
        var index = 0
        while value >= 999.5, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        return (value < 9.95 && value > 0 && index > 0 ? String(format: "%.1f", value) : String(format: "%.0f", value)) + units[index]
    }

    /// 圖表刻度用：低於 1 KB 直接寫位元組（"500B"），不會被四捨五入成 "0K"；個位數保留一位小數（"2.5M"）
    static func axisRate(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        if value == 0 { return "0" }
        if value < 1000 { return String(format: "%.0fB", value) }
        let units = ["K", "M", "G"]
        var scaled = value / 1000
        var index = 0
        while scaled >= 999.5, index < units.count - 1 {
            scaled /= 1000
            index += 1
        }
        let text = scaled < 9.95 && scaled.rounded() != scaled ? String(format: "%.1f", scaled) : String(format: "%.0f", scaled)
        return text + units[index]
    }

    /// 圖表 Y 軸的上限：往上取到 1、2、5 × 10ⁿ，刻度才會落在好讀的整數，最高的資料也不會超出最上面的格線
    static func niceAxisMax(_ value: Double, minimum: Double = 1000) -> Double {
        let target = max(minimum, value.isFinite ? value : 0)
        let magnitude = pow(10, floor(log10(target)))
        for step in [1.0, 2, 5, 10] where step * magnitude >= target { return step * magnitude }
        return 10 * magnitude
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", (fraction * 100).rounded())
    }

    private static func format(_ value: Double, base: Double, units: [String]) -> String {
        var v = max(0, value)
        var index = 0
        while v >= base, index < units.count - 1 {
            v /= base
            index += 1
        }
        if index == 0 { return String(format: "%.0f %@", v, units[index]) }
        return String(format: v < 10 ? "%.1f %@" : "%.0f %@", v, units[index])
    }
}

// MARK: - 歷史與程序

/// 圖表用的一個點；b 用於第二條線（例如 GPU、上傳、寫入）
struct MonitorPoint: Identifiable, Equatable {
    let id: Int
    let t: Date
    let a: Double
    let b: Double
}

/// 保留最近 2 分鐘、最多 n 個點的歷史（更新頻率較慢時點數較少，例如每 2 秒只會留 60 個）
struct MonitorHistory: Equatable {
    static let capacity = 120
    /// 圖表標示「最近 2 分鐘」
    static let window: TimeInterval = 120
    private(set) var points: [MonitorPoint] = []
    private var nextID = 0

    mutating func append(_ a: Double, _ b: Double = 0, at t: Date = Date()) {
        points.append(MonitorPoint(id: nextID, t: t, a: a, b: b))
        nextID += 1
        if points.count > Self.capacity { points.removeFirst(points.count - Self.capacity) }
        let cutoff = t.addingTimeInterval(-Self.window)
        if let keep = points.firstIndex(where: { $0.t >= cutoff }), keep > 0 { points.removeFirst(keep) }
    }
}

struct TopProcess: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    /// CPU 模組為百分比（單核 100%），記憶體模組為位元組
    var value: Double
    var appPath: String?
}

enum TopParse {
    struct Row: Equatable {
        var pid: Int32
        var command: String
        var value: String
    }

    /// 解析一段 top 輸出中最後一個表頭（PID 開頭）之後的列；欄位為 pid、command、值
    static func rows(_ text: String) -> [Row] {
        let lines = text.components(separatedBy: "\n")
        guard let header = lines.lastIndex(where: { $0.hasPrefix("PID") }) else { return [] }
        return lines[(header + 1)...].compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3, let pid = Int32(parts[0]) else { return nil }
            return Row(pid: pid, command: parts[1..<(parts.count - 1)].joined(separator: " "), value: String(parts[parts.count - 1]))
        }
    }

    /// top 的記憶體欄位："523M"、"1.2G"、"880K"、"12B"，結尾可能有 + 或 -
    static func memoryBytes(_ text: String) -> Double? {
        var s = text.trimmingCharacters(in: CharacterSet(charactersIn: "+- "))
        guard let unit = s.last else { return nil }
        let multipliers: [Character: Double] = ["B": 1, "K": 1024, "M": 1024 * 1024, "G": 1024 * 1024 * 1024, "T": 1024 * 1024 * 1024 * 1024]
        if let m = multipliers[unit] {
            s.removeLast()
            return Double(s).map { $0 * m }
        }
        return Double(s)
    }
}

/// 外接磁碟（隨身碟、外接硬碟、SD 卡等）的容量
struct ExternalVolume: Equatable, Identifiable {
    var id: String { mountPoint }
    var mountPoint: String
    var name: String
    var total: UInt64
    var available: UInt64
    var used: UInt64 { total > available ? total - available : 0 }
    /// 例如 /dev/disk5s2，用來對應 IOKit 的讀寫統計與 SMART
    var deviceNode: String = ""
    /// "exfat"、"apfs"…
    var fileSystem: String = ""
    /// DiskArbitration 的裝置協定："USB"、"PCI-Express"、"Thunderbolt"…
    var connection: String = ""
}

/// diskutil 的 SMART 整體狀態，只有正常／異常。讀不到 NVMe SMART（SATA 硬碟、多數 USB 外接盒）時才用
enum DiskHealth: Equatable {
    case verified, failing, unsupported
    /// diskutil 失敗或逾時，無法判斷
    case unknown

    /// diskutil 的 SMARTStatus 文字："Verified"、"Failing"、"About to Fail"、"Not Supported"…
    static func parse(_ status: String?) -> DiskHealth {
        switch status {
        case "Verified": return .verified
        case "Failing", "About to Fail": return .failing
        default: return .unsupported
        }
    }
}

/// NVMe 硬碟自己記錄的 SMART 資料：從出廠到現在的讀寫量、已用壽命與錯誤，重新開機或重新接上都不會歸零
struct DiskLifetime: Equatable {
    /// 已用掉的設計寫入壽命（%），用超過時可能大於 100
    var percentageUsed: Int
    /// 剩下的備用區塊（%）與硬碟自己的警告門檻
    var availableSpare: Int
    var spareThreshold: Int
    /// 硬碟回報的嚴重警告位元（備用區塊不足、溫度、可靠度下降、唯讀…），0 表示沒有
    var criticalWarning: UInt8
    var bytesRead: UInt64
    var bytesWritten: UInt64
    var powerOnHours: UInt64
    var mediaErrors: UInt64

    /// 健康度：100% 減去已用壽命
    var healthPercent: Int { max(0, 100 - percentageUsed) }

    /// 硬碟自己回報有問題：有嚴重警告，或備用區塊已低於門檻
    var isFailing: Bool { criticalWarning != 0 || availableSpare < spareThreshold }

    /// NVMe 規格的「SMART／健康資訊」記錄（512 位元組，小端序）。讀寫量的單位是 512,000 位元組，欄位是 128 位元
    static func parse(_ log: [UInt8]) -> DiskLifetime? {
        guard log.count >= 192 else { return nil }
        func counter(_ offset: Int) -> UInt64 {
            let low = (0..<8).reduce(UInt64(0)) { $0 | UInt64(log[offset + $1]) << (8 * UInt64($1)) }
            // 高 64 位元不是 0 時已經大到顯示不下，直接用最大值
            let high = log[(offset + 8)..<(offset + 16)].contains { $0 != 0 }
            return high ? .max : low
        }
        func bytes(_ offset: Int) -> UInt64 {
            let (value, overflow) = counter(offset).multipliedReportingOverflow(by: 512_000)
            return overflow ? .max : value
        }
        return DiskLifetime(percentageUsed: Int(log[5]), availableSpare: Int(log[3]), spareThreshold: Int(log[4]),
                            criticalWarning: log[0], bytesRead: bytes(32), bytesWritten: bytes(48),
                            powerOnHours: counter(128), mediaErrors: counter(160))
    }
}

/// 單一外接磁碟的讀寫統計（計數器從接上那一刻起算）
struct ExternalDiskStats: Equatable {
    var readRate: Double = 0
    var writeRate: Double = 0
    var totalRead: UInt64 = 0
    var totalWritten: UInt64 = 0
    var history = MonitorHistory()
    var health: DiskHealth?
    /// 支援 NVMe SMART 的外接硬碟（例如 Thunderbolt 外接盒）才有
    var lifetime: DiskLifetime?
}

/// 掛載項目的裝置資訊，供判斷是否為實體外接磁碟
struct ExternalMountTraits: Equatable {
    var mountPoint: String
    var deviceNode: String
    var isInternal: Bool
    var protocolName: String?
}

enum ExternalDisk {
    /// 只收掛在 /Volumes 下的實體外接磁碟；排除系統內部磁區、內建儲存、磁碟映像檔（DMG）與網路磁碟
    static func isExternal(_ traits: ExternalMountTraits) -> Bool {
        guard traits.mountPoint.hasPrefix("/Volumes/"),
              isValidDeviceNode(traits.deviceNode),
              !traits.isInternal else { return false }
        return traits.protocolName != "Disk Image" && traits.protocolName != "Virtual Interface"
    }
}

extension ExternalDisk {
    /// 裝置節點必須是 /dev/disk<N>(s<M>)*（只接受 ASCII 數字），才會交給 IOKit、DiskArbitration 與 diskutil
    static func isValidDeviceNode(_ node: String) -> Bool {
        guard node.hasPrefix("/dev/disk") else { return false }
        let rest = node.dropFirst("/dev/disk".count)
        guard let first = rest.first, first.isASCII, first.isNumber else { return false }
        var previousWasS = false
        for ch in rest {
            if ch.isASCII, ch.isNumber { previousWasS = false; continue }
            if ch == "s", !previousWasS { previousWasS = true; continue }
            return false
        }
        return !previousWasS
    }

    /// 磁碟標籤由磁碟本身決定，顯示前去掉控制字元與雙向文字控制符，並限制長度
    static func displayName(_ raw: String) -> String {
        let cleaned = String(String.UnicodeScalarView(raw.unicodeScalars.filter {
            $0.properties.generalCategory != .control && $0.properties.generalCategory != .format
        }))
        let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "外接磁碟" : String(trimmed.prefix(64))
    }
}

// MARK: - 風扇與溫度

struct FanReading: Equatable, Identifiable {
    var id: Int
    var name: String
    var rpm: Double
    var minRPM: Double
    var maxRPM: Double
    /// 佔最高轉速的比例（0～1）
    var fraction: Double { maxRPM > 0 ? min(1, max(0, rpm / maxRPM)) : 0 }
}

/// 各類溫度的平均與最高值（°C）；機型沒有的項目為 nil
struct TemperatureSummary: Equatable {
    struct Stat: Equatable {
        var average: Double
        var maximum: Double
    }
    var cpu: Stat?
    var gpu: Stat?
    /// SoC 晶片（PMU die）感測器
    var soc: Stat?
    var battery: Stat?
    var storage: Stat?
    /// 機型有核心溫度感測器，但目前讀不到有效值（核心群組休眠）；介面顯示「休眠中」而不是整列消失
    var coreSensorsAsleep = false
    var isEmpty: Bool { cpu == nil && gpu == nil && soc == nil && battery == nil && storage == nil && !coreSensorsAsleep }
}

enum ThermalMath {
    enum Category: Hashable { case cpu, gpu, soc, battery, storage }

    /// 感測器名稱 → 類別；不認得的（PMU tdev、TP 等）回傳 nil
    static func category(for name: String) -> Category? {
        if name.hasPrefix("pACC MTR Temp Sensor") || name.hasPrefix("eACC MTR Temp Sensor") { return .cpu }
        if name.hasPrefix("GPU MTR Temp Sensor") { return .gpu }
        if name.hasPrefix("PMU tdie") || name.hasPrefix("SOC MTR Temp Sensor") || name.hasPrefix("PMGR SOC Die Temp Sensor") { return .soc }
        if name.hasPrefix("gas gauge battery") { return .battery }
        if name.hasPrefix("NAND CH") { return .storage }
        return nil
    }

    /// 0 度或超過 110 度都當成讀取失敗
    static func isPlausible(_ value: Double) -> Bool { value.isFinite && value > 0 && value <= 110 }

    /// SMC 的核心溫度鍵：核心群組斷電休眠時會固定回報 0、4.6、5.3、6.7、8.4 這類假值
    /// （實測 M2 Pro 閒置時效能核心全是這些值），真正的晶片溫度不會低於室溫，所以 20 度以下一律視為沒有資料
    static func isValidDieTemperature(_ value: Double) -> Bool { value.isFinite && value >= 20 && value <= 110 }

    /// 核心溫度每秒都可能在「有效」與「休眠假值」之間跳動（實測閒置 45 秒有 20 秒整組無效）。
    /// 每個感測器各自保留最近一次有效值，讀到假值或讀不到時沿用，
    /// 超過 maxAge 才放棄。這樣醒著與休眠的核心會一起算進平均，不會因為只剩節能核心醒著而讓平均偏低
    static func effectiveDieValues(_ readings: [(key: String, value: Double?)],
                                   held: inout [String: (value: Double, date: Date)],
                                   now: Date, maxAge: TimeInterval = 120) -> [Double] {
        var result: [Double] = []
        for reading in readings {
            if let value = reading.value, isValidDieTemperature(value) {
                held[reading.key] = (value, now)
                result.append(value)
            } else if let previous = held[reading.key], now.timeIntervalSince(previous.date) <= maxAge {
                result.append(previous.value)
            } else {
                held[reading.key] = nil
            }
        }
        return result
    }

    /// 只用有效的核心感測器算平均與最高；全部休眠時回傳 nil
    static func dieStatistic(_ values: [Double]) -> TemperatureSummary.Stat? {
        let valid = values.filter(isValidDieTemperature)
        guard !valid.isEmpty else { return nil }
        return .init(average: valid.reduce(0, +) / Double(valid.count), maximum: valid.max() ?? 0)
    }

    /// 備援鍵依序取第一個有效的晶片溫度
    static func firstValid(_ values: [Double?]) -> TemperatureSummary.Stat? {
        guard let value = values.compactMap({ $0 }).first(where: isValidDieTemperature) else { return nil }
        return .init(average: value, maximum: value)
    }

    /// SSD、電池等不會休眠的感測器：合理範圍內的值取平均與最高
    static func plainStatistic(_ values: [Double?]) -> TemperatureSummary.Stat? {
        let valid = values.compactMap { $0 }.filter(isPlausible)
        guard !valid.isEmpty else { return nil }
        return .init(average: valid.reduce(0, +) / Double(valid.count), maximum: valid.max() ?? 0)
    }

    /// 同名感測器（一個名稱常有兩個服務）先平均成一點，再依類別彙整
    static func summary(_ readings: [(name: String, value: Double)]) -> TemperatureSummary {
        var perName: [String: [Double]] = [:]
        for reading in readings where isPlausible(reading.value) { perName[reading.name, default: []].append(reading.value) }
        var perCategory: [Category: [Double]] = [:]
        for (name, values) in perName {
            guard let category = category(for: name) else { continue }
            perCategory[category, default: []].append(values.reduce(0, +) / Double(values.count))
        }
        func stat(_ category: Category) -> TemperatureSummary.Stat? {
            guard let values = perCategory[category], !values.isEmpty else { return nil }
            return .init(average: values.reduce(0, +) / Double(values.count), maximum: values.max() ?? 0)
        }
        return TemperatureSummary(cpu: stat(.cpu), gpu: stat(.gpu), soc: stat(.soc), battery: stat(.battery), storage: stat(.storage))
    }
}

/// 各晶片世代的 CPU／GPU 溫度 SMC 鍵。鍵名依世代不同，只收錄在實機上用負載測試確認過的世代；
/// 其他晶片回傳 nil，介面就不顯示 CPU／GPU 溫度，不會顯示錯誤的數字
struct ThermalKeys: Equatable {
    var cpu: [String]
    var gpu: [String]
    /// 核心鍵都讀不到時改用的 CPU 鍵，依序取第一個有效的（Intel：PECI、die、proximity）
    var cpuFallback: [String] = []
    /// 系統溫度感測器（HID）讀不到時改用的 SMC 鍵（Intel 沒有 HID 溫度感測器）
    var storage: [String] = []
    var battery: [String] = []
    /// 核心群組會斷電休眠（Apple 晶片）：讀不到時顯示「休眠中」；Intel 沒有這種情況
    var coresSleep = true
}

enum ThermalKeyTable {
    /// "Apple M2 Pro" → M2 世代。M2 Pro 實測：效能核心（Tp01 起每核心三個點取中間）、
    /// 節能核心（Tp1h／Tp1l／Tp1p／Tp1t）在 CPU 負載下明顯升溫，Tg0f／Tg0j 隨 GPU 負載升溫
    static func keys(forChip brand: String) -> ThermalKeys? {
        let name = brand.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("Intel") { return intel }
        let isM2 = name == "Apple M2" || name.hasPrefix("Apple M2 ")
        guard isM2 else { return nil }
        return ThermalKeys(
            cpu: ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j", "Tp1h", "Tp1t", "Tp1p", "Tp1l"],
            gpu: ["Tg0f", "Tg0j"])
    }

    /// Intel Mac（Mac mini 2018 i5-8500B 實測）：TC1C 起每個核心一個鍵（沒有的核心回報 -127，會被過濾），
    /// TCXC 是 PECI 回報的 CPU 溫度、TC0F 是 die、TC0P 是 proximity；內顯是 TCGC（PECI），
    /// 有獨立顯卡的機型另有 TG0D／TG0P；SSD 是 TH0a／TH0b；MacBook 的電池是 TB0T 系列
    static let intel = ThermalKeys(
        cpu: (1...8).map { "TC\($0)C" },
        gpu: ["TG0D", "TG0P", "TCGC"],
        cpuFallback: ["TCXC", "TC0F", "TC0D", "TC0E", "TC0P"],
        storage: ["TH0a", "TH0b"],
        battery: ["TB0T", "TB1T", "TB2T"],
        coresSleep: false)
}

/// macOS 內建 networkQuality（`-c` 輸出的 JSON）的測速結果
struct SpeedTestResult: Equatable {
    /// 位元／秒
    var download: Double?
    var upload: Double?
    /// 網路忙碌時每分鐘能完成的往返次數（RPM），越高越不卡
    var responsiveness: Double?
    /// 閒置時的往返延遲（毫秒）
    var idleLatency: Double?
    var date: Date

    /// 下載或上傳沒測到時是哪一個（「下載」「上傳」）；都有就是 nil
    var missingPart: String? {
        switch (download, upload) {
        case (nil, .some): return "下載"
        case (.some, nil): return "上傳"
        default: return nil
        }
    }

    /// 欄位缺少或不合理時留空；下載、上傳都沒有就當作失敗。
    /// 速度是 0 也留空：那是沒測到（例如上傳的連線全部逾時，networkQuality 仍回報 0），不是真的 0
    static func parse(_ data: Data, at date: Date) -> SpeedTestResult? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func value(_ key: String) -> Double? {
            guard let number = json[key] as? NSNumber else { return nil }
            let value = number.doubleValue
            return value.isFinite && value >= 0 ? value : nil
        }
        func throughput(_ key: String) -> Double? { value(key).flatMap { $0 > 0 ? $0 : nil } }
        let result = SpeedTestResult(download: throughput("dl_throughput"), upload: throughput("ul_throughput"),
                                     responsiveness: value("responsiveness"), idleLatency: value("base_rtt"), date: date)
        return result.download == nil && result.upload == nil ? nil : result
    }

    /// networkQuality 的參數。macOS 12 沒有 -M（測試時間上限），加了會直接失敗，
    /// 所以只在說明裡列出 -M 時才加；沒有上限時靠 App 自己 60 秒後強制結束
    static func arguments(help: String, maxRuntime: Int) -> [String] {
        help.contains("-M:") ? ["-c", "-M", String(maxRuntime)] : ["-c"]
    }

    /// 測速常用的位元速率："17.2 Mbps"、"850 Kbps"、"1.2 Gbps"
    static func bitRate(_ bitsPerSecond: Double) -> String {
        let value = max(0, bitsPerSecond)
        if value >= 999.5e6 { return String(format: "%.1f Gbps", value / 1e9) }
        if value < 999.5e3, value > 0 { return String(format: "%.0f Kbps", value / 1e3) }
        let mbps = value / 1e6
        return String(format: mbps < 99.95 && mbps > 0 ? "%.1f Mbps" : "%.0f Mbps", mbps)
    }
}
