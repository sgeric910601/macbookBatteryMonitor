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
    /// 充電器在 USB PD Discover Identity 回報的廠商代碼（USB-IF VID）；沒回報的充電器是 nil
    var vendorID: Int?
    /// 辨識同一顆充電器用（自訂名稱的鍵）：VID、PID 加上原始電壓電流檔位，只在面板開著時讀
    var fingerprint: String?

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

    /// 正在供電的孔與它收到的原始 PDO。只有一個孔有功率就是它；同時插兩條時，落選的孔也有 MaxPower，
    /// 改挑 PortControllerLoserReason 為 0 的那個（只有一個孔時 LoserReason 也可能不是 0，所以不能只看它）。仍分不出時回 nil
    static func powerPort(_ controllers: [[String: Any]]) -> (index: Int, pdos: [UInt32])? {
        func value(_ i: Int, _ key: String) -> Int { (controllers[i][key] as? NSNumber)?.intValue ?? 0 }
        let powered = controllers.indices.filter { value($0, "PortControllerMaxPower") > 0 }
        let active = powered.count == 1 ? powered : powered.filter { value($0, "PortControllerLoserReason") == 0 }
        guard active.count == 1, let raw = controllers[active[0]]["PortControllerPortPDO"] as? [NSNumber] else { return nil }
        let pdos = raw.map { UInt32(truncatingIfNeeded: $0.int64Value) }.filter { $0 != 0 }
        return pdos.isEmpty ? nil : (active[0], pdos)
    }

    /// 只取電壓電流（固定檔位與 PPS 電壓範圍），不含旗標位元：同一顆充電器換孔或重插時旗標會變。
    /// 電流無條件進位到 0.1 A、PPS 只看最高電壓：同一顆經 MagSafe 接上時，每檔電流少 10～40 mA，PPS 最低電壓與電流也會變。
    /// 用進位不用四捨五入：2.25 A 經 MagSafe 變 2.21～2.24 A，四捨五入會一邊 2.3、一邊 2.2
    static func fingerprint(vendorID: Int, productID: Int, pdos: [UInt32]) -> String {
        let levels = pdos.compactMap { pdo -> String? in
            switch pdo >> 30 {
            case 0: return "\((pdo >> 10 & 0x3FF) * 50)x\(roundUp100((pdo & 0x3FF) * 10))"
            case 3 where pdo >> 28 & 3 == 0: return "pps\((pdo >> 17 & 0xFF) * 100)"
            default: return nil
            }
        }
        return String(format: "%04x:%04x|", vendorID, productID) + levels.joined(separator: ",")
    }

    static func roundUp100<T: BinaryInteger>(_ mA: T) -> T { (mA + 99) / 100 * 100 }

    static func savedName(for fingerprint: String, in names: [String: String]) -> String? {
        savedEntry(for: fingerprint, in: names)?.name
    }

    /// 先找完全相同的指紋；找不到時，只要有一邊沒有廠商代碼（MagSafe 讀不到）而檔位相同、且只有一筆，就用那筆。
    /// 回傳命中的鍵：改名、清除要寫回這個鍵，不然借來的名稱改不掉
    static func savedEntry(for fingerprint: String, in names: [String: String]) -> (key: String, name: String)? {
        if let exact = names[fingerprint] { return (fingerprint, exact) }
        let unknownVendor = "0000:0000"
        func split(_ key: String) -> (vendor: Substring, levels: Substring)? {
            guard let bar = key.firstIndex(of: "|") else { return nil }
            return (key[..<bar], key[key.index(after: bar)...])
        }
        guard let mine = split(fingerprint) else { return nil }
        let matches = names.filter { key, _ in
            guard let other = split(key) else { return false }
            return other.levels == mine.levels && (mine.vendor == unknownVendor || other.vendor == unknownVendor)
        }
        return matches.count == 1 ? matches.first.map { ($0.key, $0.value) } : nil
    }

    /// 舊版指紋（電流到 10 mA、PPS 含最低電壓與電流）轉成目前格式，已存的名稱才找得到；已是新格式的不變
    static func migratedFingerprint(_ key: String) -> String {
        guard let bar = key.firstIndex(of: "|") else { return key }
        let levels = key[key.index(after: bar)...].split(separator: ",").map { part -> String in
            if part.hasPrefix("pps") {
                // pps5000-21000x5000 → pps21000
                guard let range = part.dropFirst(3).split(separator: "x").first,
                      let maxVoltage = range.split(separator: "-").last else { return String(part) }
                return "pps" + maxVoltage
            }
            let pair = part.split(separator: "x")
            guard pair.count == 2, let mA = Int(pair[1]), plausible.contains(mA) else { return String(part) }
            return "\(pair[0])x\(roundUp100(mA))"
        }
        return key[...bar] + levels.joined(separator: ",")
    }

    /// 已存名稱：清理名稱、舊格式的鍵轉成新格式。撞在一起時固定挑一筆（新格式優先，否則取排序最前的原鍵），每次啟動結果一樣
    static func migratedNames(_ stored: [String: String]) -> [String: String] {
        var result: [String: (name: String, original: String)] = [:]
        for (key, value) in stored.sorted(by: { $0.key < $1.key }) {
            guard let name = cleanName(value) else { continue }
            let newKey = migratedFingerprint(key)
            guard isValidFingerprint(newKey) else { continue }  // 壞掉或被改過的鍵直接丟掉，免得之後解析出錯
            // 依鍵排序走訪：已有一筆時，只有本身就是新格式的才取代它
            if let kept = result[newKey], kept.original == newKey || key != newKey { continue }
            result[newKey] = (name, key)
        }
        return result.mapValues(\.name)
    }

    /// 指紋裡的電壓、電流（mV、mA）合理範圍；超出的鍵一定是壞的，也避免相乘、進位時溢位
    static let plausible = 0...100_000

    /// 目前格式的指紋：「hhhh:hhhh|」加上逗號分隔的「電壓x電流」或「pps最高電壓」，數值都在合理範圍
    static func isValidFingerprint(_ key: String) -> Bool {
        let parts = key.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let ids = parts[0].split(separator: ":", omittingEmptySubsequences: false)
        guard ids.count == 2, ids.allSatisfy({ $0.count == 4 && Int($0, radix: 16) != nil }) else { return false }
        return parts[1].isEmpty || parts[1].split(separator: ",", omittingEmptySubsequences: false).allSatisfy { part in
            if part.hasPrefix("pps") { return Int(part.dropFirst(3)).map(plausible.contains) ?? false }
            let pair = part.split(separator: "x", omittingEmptySubsequences: false)
            return pair.count == 2 && pair.allSatisfy { Int($0).map(plausible.contains) ?? false }
        }
    }

    static let maxNameLength = 30
    static let maxSavedChargers = 100

    /// 設定檔匯入的名稱：只收「廠商:產品|檔位」格式的鍵、名稱照命名規則清理、最多 maxSavedChargers 筆
    static func importedNames(_ raw: Any?) -> [String: String] {
        guard let map = raw as? [String: Any] else { return [:] }
        // 鍵的格式由 migratedNames 檢查（isValidFingerprint）
        let valid = map.compactMapValues { $0 as? String }.filter { key, _ in key.count <= 200 }
        return Dictionary(uniqueKeysWithValues: migratedNames(valid).sorted { $0.key < $1.key }.prefix(maxSavedChargers).map { ($0.key, $0.value) })
    }

    /// 同名多筆時的說明：各筆的廠商代碼（不重複），例如「廠商代碼 0x1A2B」或「廠商代碼 0x1A2B、無廠商代碼」
    static func vendorSummary(_ fingerprints: [String]) -> String {
        let vendors = fingerprints.map { Int($0.prefix(4), radix: 16) ?? 0 }
        let known = Array(Set(vendors.filter { $0 > 0 })).sorted().map { String(format: "0x%04X", $0) }
        let parts = (known.isEmpty ? [] : ["廠商代碼 " + known.joined(separator: "、")]) + (vendors.contains(0) ? ["無廠商代碼"] : [])
        return parts.joined(separator: "、")
    }

    /// 設定頁清單上的一行說明：廠商代碼與最高的固定檔位，例如「廠商代碼 0x1A2B · 最高 20 V 約 5 A」
    static func describe(fingerprint: String) -> String {
        let parts = fingerprint.split(separator: "|", maxSplits: 1)
        let vendor = parts.first.flatMap { Int($0.prefix(4), radix: 16) } ?? 0
        let top = parts.count == 2 ? parts[1].split(separator: ",").compactMap { part -> (Int, Int)? in
            let pair = part.split(separator: "x")
            guard pair.count == 2, let v = Int(pair[0]), let a = Int(pair[1]), plausible.contains(v), plausible.contains(a) else { return nil }
            return (v, a)
        }.max { ($0.0 * $0.1, $0.0) < ($1.0 * $1.1, $1.0) } : nil  // 瓦數相同取電壓高的
        let vendorText = vendor > 0 ? String(format: "廠商代碼 0x%04X", vendor) : "無廠商代碼（MagSafe 或未回報）"
        guard let top else { return vendorText }
        // 指紋的電流已進位到 0.1 A，所以標「約」
        return vendorText + " · 最高 " + String(format: "%g V 約 %g A", Double(top.0) / 1000, Double(top.1) / 1000)
    }

    /// 使用者取的充電器名稱：去掉前後空白與控制字元、限制長度；空字串表示清除名稱
    static func cleanName(_ text: String) -> String? {
        // ZWJ stays so joined emoji survive; other control/format characters (e.g. bidi overrides) are dropped
        let dropped = CharacterSet.controlCharacters.subtracting(CharacterSet(charactersIn: "\u{200D}"))
        let cleaned = String(text.unicodeScalars.filter { !dropped.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(maxNameLength))
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
                                    chargerCount: int(reg["ChargerCount"]), includeConnection: includeConnection,
                                    portControllers: reg["PortControllerInfo"] as? [[String: Any]])
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
    private static func adapterInfo(registryDetails: [String: Any]?, chargerCount: Int?, includeConnection: Bool,
                                    portControllers: [[String: Any]]?) -> AdapterInfo? {
        // 單次快照只使用一份詳細資料，避免換充電器時混用系統不同步的名稱與規格。
        let details = registryDetails ?? (IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any])
        var info = details.map(AdapterInfo.parse)
        if info == nil { info = AdapterInfo() }
        if includeConnection {
            info?.connection = adapterConnection(chargerCount: chargerCount)
            if let port = portControllers.flatMap(AdapterInfo.powerPort) {
                let identity = partnerIdentity(port: port.index + 1)
                // 供電孔有 USB-C 的 PD 節點就是 USB-C；MagSafe 與 USB-C 都接著同一顆充電器時，連線狀態猜不出是哪條
                if identity != nil { info?.connection = "USB-C" }
                let vendorID = identity?.vendorID ?? 0
                info?.vendorID = vendorID > 0 ? vendorID : nil
                info?.fingerprint = AdapterInfo.fingerprint(vendorID: vendorID, productID: identity?.productID ?? 0, pdos: port.pdos)
            }
        }
        return info
    }

    /// 充電器對 USB PD Discover Identity 的回覆（IORegistry 的 Port-USB-C@n/CC/SOP）。
    /// 沒有這個節點（不是 USB-C 孔，例如 MagSafe）回 nil；有節點但沒回覆時兩個都是 0
    private static func partnerIdentity(port: Int) -> (vendorID: Int, productID: Int)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPortTransportComponentCCUSBPDSOP"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func value(_ key: String) -> Any? { IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() }
            guard value("Description") as? String == "Port-USB-C@\(port)/CC/SOP" else { continue }
            return ((value("Vendor ID") as? NSNumber)?.intValue ?? 0, (value("Product ID") as? NSNumber)?.intValue ?? 0)
        }
        return nil
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
