import Foundation
import IOKit
import IOKit.ps

struct AdapterInfo: Codable, Equatable {
    var watts: Int?
    var voltage_mV: Int?
    var current_mA: Int?
    var name: String?
    var manufacturer: String?
    var model: String?
    var connection: String?
    /// 充電器支援的電壓檔位（AdapterDetails 的 UsbHvcMenu），舊快照沒有這欄
    var levels: [Level]?

    struct Level: Codable, Equatable {
        var voltage_mV: Int
        var current_mA: Int
    }

    static func parse(_ details: [String: Any]) -> AdapterInfo {
        func positive(_ key: String) -> Int? {
            guard let n = details[key] as? NSNumber, n.intValue > 0 else { return nil }
            return n.intValue
        }
        func text(_ key: String) -> String? {
            guard let value = details[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        func productName(_ value: String?) -> String? {
            guard let value else { return nil }
            let generic = ["pd charger", "usb pd charger", "usb-c charger", "charger"]
            return generic.contains(value.lowercased()) ? nil : value
        }
        return AdapterInfo(watts: positive("Watts"), voltage_mV: positive("AdapterVoltage") ?? positive("Voltage"),
            current_mA: positive("Current"), name: productName(text("Name")) ?? productName(text("Description")),
            manufacturer: text("Manufacturer"), model: text("Model"), levels: levels(details["UsbHvcMenu"]))
    }

    private static func levels(_ raw: Any?) -> [Level]? {
        guard let items = raw as? [[String: Any]] else { return nil }
        let levels = items.compactMap { item -> Level? in
            guard let v = (item["MaxVoltage"] as? NSNumber)?.intValue, v > 0,
                  let a = (item["MaxCurrent"] as? NSNumber)?.intValue, a > 0 else { return nil }
            return Level(voltage_mV: v, current_mA: a)
        }
        return levels.isEmpty ? nil : levels.sorted { $0.voltage_mV < $1.voltage_mV }
    }

    /// 支援檔位，電流相同的電壓合併成一組：["5／9／15 V 3 A", "20 V 2.25 A"]。
    /// 相差 50 mA 內算相同、顯示取到 0.05 A：經 MagSafe 接上時每檔會少 10～40 mA（2.96、2.98 A…）
    var levelGroups: [String] {
        guard let levels else { return [] }
        var groups: [(volts: [String], current_mA: Int)] = []
        for level in levels {
            let volts = String(format: "%g", Double(level.voltage_mV) / 1000)
            if let last = groups.last, abs(last.current_mA - level.current_mA) <= 50 {
                groups[groups.count - 1].volts.append(volts)
                groups[groups.count - 1].current_mA = max(last.current_mA, level.current_mA)
            } else { groups.append(([volts], level.current_mA)) }
        }
        return groups.map { "\($0.volts.joined(separator: "／")) V \(String(format: "%g", Double(($0.current_mA + 25) / 50 * 50) / 1000)) A" }
    }
    var levelSummary: String? { levelGroups.isEmpty ? nil : levelGroups.joined(separator: "、") }
    var specification: String? {
        guard let v = voltage_mV, let a = current_mA, v > 0, a > 0 else { return nil }
        return String(format: "%g V · %g A", Double(v) / 1000, Double(a) / 1000)
    }
    /// 多種連接埠同時啟用時不猜測哪個正在供電。
    static func connectionLabel(activeTypes: [String], chargerCount: Int? = nil) -> String? {
        let types = Set(activeTypes)
        let magSafe = types.filter { $0.localizedCaseInsensitiveContains("MagSafe") }
        // MagSafe 只有供電用途；系統只認到一個充電器時，USB-C 的活動連線可能只是周邊。
        // 有多個充電來源時，不能從連線狀態判斷實際選中的來源。
        if let chargerCount, chargerCount > 1 { return nil }
        if magSafe.count == 1, types.count == 1 || chargerCount == 1 { return magSafe.first }
        guard types.count == 1 else { return nil }
        return types.contains("USB-C") ? "USB-C" : nil
    }
}

/// 某一時間點讀到的原始電池資料。時間單位都是分鐘，nil 代表系統沒提供或還在計算。
struct BatterySnapshot: Codable, Equatable {
    var date = Date()
    var percent = 0
    var isCharging = false
    var externalConnected = false
    var fullyCharged = false
    var voltage_mV = 0
    /// 負值代表放電
    var amperage_mA = 0
    var cycleCount = 0
    var designCycleCount: Int?
    var remaining_mAh: Int?
    var fullCharge_mAh: Int?
    var nominal_mAh: Int?
    var design_mAh: Int?
    var avgTimeToEmpty: Int?
    var avgTimeToFull: Int?
    var psTimeToEmpty: Int?
    var psTimeToFull: Int?
    /// macOS 的電源資訊有剩餘時間欄位（-1 代表還在估算）。有的話以它為準，不改用電池晶片的平均時間
    var psReportsTime = false
    /// Intel Mac。快要充滿、充電電流很小時，SMC 推算的電池功率不可靠，改以電池晶片為準（由 BatteryStore 設定）
    var isIntel = false
    var temperature_C: Double?
    var notChargingReason: Int?
    var adapter: AdapterInfo?
    var systemLoad_mW: Int?
    var systemPowerIn_mW: Int?
    var lowPowerMode = false
    var serial: String?
    /// 系統設定的充電上限（沒設定時為 nil）
    var chargeLimit: ChargeLimit?

    var smcBatteryWatts: Double?
    var smcAdapterWatts: Double?
    /// 變壓器即時輸入電壓（V）與電流（A），SMC VD0R／ID0R，與 smcAdapterWatts 同一次讀取
    var smcAdapterVolts: Double?
    var smcAdapterAmps: Double?
    /// 電池晶片回報的輸入電流（mA），沒有 SMC 讀值時備援
    var systemCurrentIn_mA: Int?
    var smcSystemWatts: Double?

    /// 電池功率（W，正值充入、負值放出），用同次 SMC 輸入與系統功率推算。
    /// 缺少任一路時退回 Registry 電壓 × 電流，不使用不可靠的 PPBR。
    var liveBatteryWatts: Double? {
        guard let system = smcSystemWatts else { return nil }
        if !externalConnected { return -system }
        guard let input = smcAdapterWatts else { return nil }
        // Intel 在 85% 以上充電電流很小時，SMC 推算會是小負值：實測 2015 MacBook Air 86% 時推算 -3 W，
        // 電池晶片卻是充電中、+528 mA，macOS 也顯示充電中。晶片明確回報在充電時改用晶片的電流
        if isIntel, isCharging, amperage_mA > 50, input - system < 0 { return nil }
        return input - system
    }

    /// 是否正在充電。電池晶片的 IsCharging 會停在舊值：實測 M1 接著電源、SMC 顯示約 14 W 充入電池、電量持續上升時，
    /// 仍有十幾秒回報「未充電、電流 0」。有 SMC 即時功率時以功率為準，只有數值落在模糊區間才看晶片旗標。
    var chargingNow: Bool {
        guard externalConnected else { return false }
        guard let watts = liveBatteryWatts else { return isCharging }
        // 到達上限後 macOS 不再充電，SMC 兩路取樣時間不同步會有約 ±4 W 的雜訊，要晶片旗標與功率都同意才算
        if let limit = chargeLimit?.limit, percent >= limit { return isCharging && watts >= 3 }
        if watts >= 3 { return true }
        if watts < 0.5 { return false }
        return isCharging
    }

    /// 電量高於充電上限、電池正在放電到上限（與「供電不足」相同，以 -50 mA 為門檻，避免雜訊）
    var drainingAboveLimit: Bool {
        guard let limit = chargeLimit?.limit else { return false }
        return percent > limit && effectiveAmperage_mA < -50
    }

    /// 電量高於系統充電上限、macOS 暫停變壓器供電讓電池放電到上限（生效中的策略只在接電時存在）
    var drainingToChargeLimit: Bool {
        guard let limit = chargeLimit, limit.active else { return false }
        return percent >= limit.limit - 1
    }

    /// SMC 功率換算的近似電流；原始 Registry 電流保留供診斷。
    var effectiveAmperage_mA: Int {
        guard let watts = liveBatteryWatts, voltage_mV > 0 else { return amperage_mA }
        if !externalConnected, watts > 0 { return min(0, amperage_mA) }
        return Int((watts * 1_000_000 / Double(voltage_mV)).rounded())
    }

    mutating func applyLivePower(battery: Double?, adapter: Double?, system: Double?) {
        func valid(_ value: Double?, signed: Bool = false) -> Double? {
            guard let value, value.isFinite, abs(value) < 500, signed || value >= 0 else { return nil }
            return value
        }
        smcBatteryWatts = valid(battery, signed: true)
        smcAdapterWatts = valid(adapter)
        smcSystemWatts = valid(system)
    }

    /// AC／滿電旗標可能在停止供電後仍保留；只在有明確零輸入且放電時覆寫。
    mutating func reconcilePowerSource(inputMilliwatts: Int?) {
        if externalConnected, let input = smcAdapterWatts, input > 0.5 {
            // 已接上時，SMC 可排除 Registry 零輸入的延遲；不覆寫明確的拔除狀態。
        } else if externalConnected, drainingToChargeLimit {
            // 放電到充電上限時變壓器暫停供電，但線仍接著，不視為拔除。
        } else if !isCharging, effectiveAmperage_mA < -50,
                  (smcAdapterWatts.map { $0 <= 0.5 } ?? (inputMilliwatts == 0)) {
            externalConnected = false
        }
        if !externalConnected {
            isCharging = false
            adapter = nil
            systemPowerIn_mW = nil
            smcAdapterVolts = nil
            smcAdapterAmps = nil
            systemCurrentIn_mA = nil
        }
    }
}

enum BatteryReader {
    private static let smc = SMC()

    /// SMC 的 PSTR（系統功率）比 PDTR（變壓器輸入）慢一次更新：實測兩者都每秒更新一次，
    /// PSTR 幾乎等於 1 秒前的 PDTR（平均差 0.01 W），同時讀的兩個值直接相減會有約 ±4 W 的雜訊，
    /// 面板上系統耗電也會看起來慢變壓器一秒。記住上一筆 PDTR，配對同一次更新的系統功率。只在主執行緒使用。
    private static var previousAdapterInput: (reading: AdapterReading, uptime: TimeInterval)?

    /// 變壓器輸入的一次讀取：功率 PDTR，以及電壓 VD0R、電流 ID0R（三者同一次更新，功率約等於電壓 × 電流）
    struct AdapterReading: Equatable {
        var watts: Double
        var volts: Double? = nil
        var amps: Double? = nil
    }

    private static func readAdapterInput() -> AdapterReading? {
        guard let smc, let watts = smc.read("PDTR") else { return nil }
        return AdapterReading(watts: watts, volts: smc.read("VD0R"), amps: smc.read("ID0R"))
    }

    /// 更新頻率慢於每秒時，在下一次更新前 1 秒先讀一次變壓器輸入，讓下一次更新有可以配對的值
    static func recordAdapterInput() {
        guard let reading = readAdapterInput() else { return }
        previousAdapterInput = (reading, ProcessInfo.processInfo.systemUptime)
    }

    /// 0.5～1.6 秒前讀到的變壓器輸入與現在的 PSTR 是同一次更新；沒有就退回現在的值
    static func alignedAdapterInput(current: AdapterReading?, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> AdapterReading? {
        defer { if let current { previousAdapterInput = (current, now) } }
        if let previous = previousAdapterInput, (0.5...1.6).contains(now - previous.uptime) { return previous.reading }
        return current
    }

    /// includeConnection：掃連接埠辨識 MagSafe／USB-C。只顯示在面板裡，面板關著時不用掃
    static func read(includeTemperature: Bool = true, includeLivePower: Bool = true, includeConnection: Bool = true) -> BatterySnapshot? {
        // 桌上型 Mac 的電池元件是空的，不讀，改走桌上型的系統耗電
        guard hasBattery, let reg = registryProperties() else { return nil }
        let data = reg["BatteryData"] as? [String: Any] ?? [:]
        let telemetry = reg["PowerTelemetryData"] as? [String: Any] ?? [:]
        let charger = reg["ChargerData"] as? [String: Any] ?? [:]
        let ps = internalBatteryDescription() ?? [:]

        // 新舊系統的 key 位置不同：有的在頂層，有的在 BatteryData 裡
        func lookup(_ keys: String...) -> Int? {
            for key in keys {
                if let v = int(reg[key]) ?? int(data[key]) { return v }
            }
            return nil
        }

        var s = BatterySnapshot()
        if let cur = int(ps["Current Capacity"]), let max = int(ps["Max Capacity"]), max > 0 {
            s.percent = cur * 100 / max
        } else if let cur = int(reg["CurrentCapacity"]), let max = int(reg["MaxCapacity"]), max > 0 {
            s.percent = cur * 100 / max
        }
        s.isCharging = bool(ps["Is Charging"]) ?? bool(reg["IsCharging"]) ?? false
        if let connected = bool(reg["ExternalConnected"]) {
            s.externalConnected = connected
        } else if let state = ps["Power Source State"] as? String {
            s.externalConnected = state == "AC Power"
        } else {
            s.externalConnected = bool(reg["ExternalConnected"]) ?? false
        }
        s.fullyCharged = bool(reg["FullyCharged"]) ?? bool(ps["Is Charged"]) ?? false
        s.voltage_mV = int(reg["Voltage"]) ?? int(reg["AppleRawBatteryVoltage"]) ?? 0
        s.amperage_mA = int(reg["Amperage"]) ?? int(reg["InstantAmperage"]) ?? 0
        s.cycleCount = int(reg["CycleCount"]) ?? 0
        s.designCycleCount = int(reg["DesignCycleCount9C"]) ?? int(reg["DesignCycleCount"])
        s.remaining_mAh = lookup("AppleRawCurrentCapacity", "RemainingCapacity")
        s.fullCharge_mAh = lookup("AppleRawMaxCapacity", "FullChargeCapacity")
        s.nominal_mAh = lookup("NominalChargeCapacity")
        s.design_mAh = lookup("DesignCapacity")
        s.avgTimeToEmpty = validMinutes(int(reg["AvgTimeToEmpty"]))
        s.avgTimeToFull = validMinutes(int(reg["AvgTimeToFull"]))
        s.psTimeToEmpty = validMinutes(int(ps["Time to Empty"]))
        s.psTimeToFull = validMinutes(int(ps["Time to Full Charge"]))
        s.psReportsTime = ps["Time to Empty"] != nil || ps["Time to Full Charge"] != nil
        s.notChargingReason = int(charger["NotChargingReason"]) ?? int(reg["NotChargingReason"])
        s.systemLoad_mW = positive(int(telemetry["SystemLoad"]))
        s.systemPowerIn_mW = positive(int(telemetry["SystemPowerIn"]))
        s.systemCurrentIn_mA = positive(int(telemetry["SystemCurrentIn"]))
        if includeLivePower {
            // 電池功率由 PDTR − PSTR 推算，不使用 PPBR（見 liveBatteryWatts），所以不必讀
            let input = alignedAdapterInput(current: readAdapterInput())
            s.smcAdapterVolts = input?.volts.flatMap { $0.isFinite && $0 >= 0 && $0 < 60 ? $0 : nil }
            s.smcAdapterAmps = input?.amps.flatMap { $0.isFinite && $0 >= 0 && $0 < 15 ? $0 : nil }
            s.applyLivePower(battery: nil, adapter: input?.watts, system: smc?.read("PSTR"))
        }
        s.chargeLimit = ChargeLimitReader.current()
        s.reconcilePowerSource(inputMilliwatts: int(telemetry["SystemPowerIn"]))
        s.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        s.serial = reg["Serial"] as? String

        if let t = int(reg["Temperature"]) ?? int(data["Temperature"]) ?? int(reg["VirtualTemperature"]), t > 0 {
            s.temperature_C = Double(t) / 100
        } else if includeTemperature {
            s.temperature_C = smc?.batteryTemperature()
        }

        if s.externalConnected {
            s.adapter = adapterInfo(registryDetails: reg["AdapterDetails"] as? [String: Any],
                                    chargerCount: int(reg["ChargerCount"]), includeConnection: includeConnection)
        } else {
            s.adapter = nil
        }
        return s
    }

    /// 這台 Mac 有沒有內建電池（桌上型 Mac 沒有）。Apple 晶片的桌上型 Mac（例如 M1 Mac mini）也有 AppleSmartBattery，
    /// 只是 BatteryInstalled 是 No、電量與電壓都是 0，所以先看機型名稱，再看電池有沒有裝著，以及系統的電源清單裡有沒有內建電池
    static let hasBattery: Bool = {
        if isDesktopModel(productName: productName()) { return false }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }
        let installed = IORegistryEntryCreateCFProperty(service, "BatteryInstalled" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
        guard installed != false, let battery = internalBatteryDescription() else { return false }
        return battery[kIOPSIsPresentKey] as? Bool != false
    }()

    /// 產品名稱看得出是桌上型 Mac。Apple 晶片 2022 年起的機型代號都是 "MacXX,Y"（例如 M2 Mac mini 是 "Mac14,3"），
    /// 看不出是不是筆電，所以看產品名稱，例如 "Mac mini (M1, 2020)"。Intel 的桌上型 Mac 沒有 AppleSmartBattery，不用看
    static func isDesktopModel(productName: String) -> Bool {
        ["Mac mini", "iMac", "Mac Studio", "Mac Pro"].contains { productName.hasPrefix($0) }
    }

    /// 裝置樹裡的產品名稱，例如 "MacBook Air (M1, 2020)"；只有 Apple 晶片的 Mac 有，其他回傳空字串
    private static func productName() -> String {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != IO_OBJECT_NULL else { return "" }
        defer { IOObjectRelease(entry) }
        guard let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data else { return "" }
        return String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// 桌上型 Mac 的整機耗電（SMC PSTR）
    static func desktopSystemWatts() -> Double? {
        guard let watts = smc?.read("PSTR"), watts.isFinite, watts >= 0, watts < 2000 else { return nil }
        return watts
    }

    /// 只讀 PowerTelemetryData 的 SystemLoad（W）。不碰任何共用快取，可以在背景執行緒呼叫
    static func systemLoadWatts() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        guard let telemetry = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
              let load = (telemetry["SystemLoad"] as? NSNumber)?.int64Value, load > 0 else { return nil }
        return Double(load) / 1000
    }

    /// 變壓器規格：每次更新都從同一次讀到的電池資料取（不另外查），換充電器後不會顯示舊資料
    private static func adapterInfo(registryDetails: [String: Any]?, chargerCount: Int?, includeConnection: Bool) -> AdapterInfo? {
        // 單次快照只使用一份詳細資料，避免換充電器時混用系統不同步的名稱與規格。
        let details = registryDetails ?? (IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any])
        var info = details.map(AdapterInfo.parse)
        if info == nil { info = AdapterInfo() }
        if includeConnection { info?.connection = adapterConnection(chargerCount: chargerCount) }
        return info
    }

    private static func adapterConnection(chargerCount: Int?) -> String? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccessoryManager"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var types: [String] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let active = IORegistryEntryCreateCFProperty(service, "ConnectionActive" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber,
                  active.boolValue,
                  let type = IORegistryEntryCreateCFProperty(service, "PortTypeDescription" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String else { continue }
            types.append(type)
        }
        return AdapterInfo.connectionLabel(activeTypes: types, chargerCount: chargerCount)
    }

    private static func registryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict
    }

    private static func internalBatteryDescription() -> [String: Any]? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            if desc["Type"] as? String == "InternalBattery" { return desc }
        }
        return nil
    }

    /// 負數會以 64-bit 補數存在 registry 裡，用 int64Value 取回帶正負號的值
    private static func int(_ any: Any?) -> Int? {
        guard let n = any as? NSNumber else { return nil }
        return Int(truncatingIfNeeded: n.int64Value)
    }

    private static func bool(_ any: Any?) -> Bool? {
        (any as? NSNumber)?.boolValue
    }

    private static func validMinutes(_ v: Int?) -> Int? {
        guard let v, v > 0, v < 65535 else { return nil }
        return v
    }

    private static func positive(_ v: Int?) -> Int? {
        guard let v, v > 0 else { return nil }
        return v
    }
}
