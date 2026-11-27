import Foundation

/// 周邊設備的電量（藍牙鍵盤、滑鼠、觸控板、耳機，以及透過接續互通連著的 iPhone）
struct PeripheralBattery: Identifiable, Equatable {
    enum Kind: String {
        case keyboard, mouse, trackpad, headphones, gameController, phone, other
    }

    /// 藍牙位址（小寫、冒號分隔）；沒有位址時用序號或名稱
    var id: String
    var name: String
    var kind: Kind
    /// 單一電池的電量（鍵盤、滑鼠，或耳機的主電池）
    var level: Int?
    /// 左右耳與充電盒（AirPods 等）
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    /// Apple 耳機的藍牙 Product ID（system_profiler 的 device_productID），用來顯示對應款式的圖示
    var appleProductID: Int?
    /// iPhone 等 Apple 裝置的機型名稱（例如 iPhone 13 Pro），由藍牙裝置資訊的型號代號換算
    var modelName: String?
    /// 依機型外型挑的圖示（Home 鍵、瀏海、動態島）；nil 時用該種類的通用圖示
    var modelSymbol: String?

    /// 通知與顯示用的代表電量：耳機取左右耳較低者（不含充電盒）
    var lowest: Int? { [left, right].compactMap { $0 }.min() ?? level }

    var symbol: String {
        switch kind {
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .gameController: return "gamecontroller"
        case .phone: return modelSymbol ?? "iphone"
        case .headphones:
            if let id = appleProductID, let symbol = Self.headphoneSymbol(productID: id) { return symbol }
            if name.localizedCaseInsensitiveContains("AirPods Max") { return "airpodsmax" }
            if name.localizedCaseInsensitiveContains("AirPods Pro") { return "airpodspro" }
            if name.localizedCaseInsensitiveContains("AirPods") { return "airpods" }
            return "headphones"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }

    /// AirPods 的 Product ID → 系統內建的款式圖示（SF Symbols）；不認得的回 nil，改用名稱判斷
    static func headphoneSymbol(productID: Int) -> String? {
        switch productID {
        case 0x2002, 0x200F: return "airpods"              // AirPods 第 1、2 代
        case 0x2013: return "airpods.gen3"                 // AirPods 第 3 代
        case 0x2019, 0x201B:                               // AirPods 4（含主動降噪款）
            if #available(macOS 15, *) { return "airpods.gen4" }
            return "airpods.gen3"
        case 0x200E, 0x2014, 0x2024: return "airpodspro"   // AirPods Pro、Pro 2（Lightning、USB-C）
        case 0x200A, 0x201F: return "airpodsmax"           // AirPods Max（Lightning、USB-C）
        default: return nil
        }
    }

    /// AirPods 的 Product ID → 型號名稱（顯示在藍牙名稱下方）；不認得的回 nil
    static func headphoneName(productID: Int) -> String? {
        switch productID {
        case 0x2002: return "AirPods（第 1 代）"
        case 0x200F: return "AirPods（第 2 代）"
        case 0x2013: return "AirPods（第 3 代）"
        case 0x2019, 0x201B: return "AirPods 4"
        case 0x200E: return "AirPods Pro"
        case 0x2014, 0x2024: return "AirPods Pro（第 2 代）"
        case 0x200A, 0x201F: return "AirPods Max"
        default: return nil
        }
    }

    /// 「左 80%・右 76%・盒 45%」；只有單一電池時為 nil
    var detailText: String? {
        let parts = [left.map { "左 \($0)%" }, right.map { "右 \($0)%" }, caseLevel.map { "盒 \($0)%" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "・")
    }
}

enum PeripheralParse {
    /// 藍牙位址統一成小寫、冒號分隔（IORegistry 用 -，system_profiler 用 :）
    static func normalizedAddress(_ address: String) -> String {
        address.lowercased().replacingOccurrences(of: "-", with: ":")
    }

    static func kind(name: String, minorType: String? = nil) -> PeripheralBattery.Kind {
        let text = ((minorType ?? "") + " " + name).lowercased()
        if text.contains("keyboard") { return .keyboard }
        if text.contains("trackpad") { return .trackpad }
        if text.contains("mouse") { return .mouse }
        if text.contains("headphone") || text.contains("headset") || text.contains("airpods") || text.contains("beats") { return .headphones }
        if text.contains("gamepad") || text.contains("controller") || text.contains("joystick") { return .gameController }
        return .other
    }

    /// "80%" → 80
    static func percent(_ value: Any?) -> Int? {
        if let number = value as? Int { return (0...100).contains(number) ? number : nil }
        guard let text = value as? String,
              let number = Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) else { return nil }
        return (0...100).contains(number) ? number : nil
    }

    /// `system_profiler SPBluetoothDataType -json` 中連線中、有回報電量的設備
    static func bluetooth(json: Data) -> [PeripheralBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var result: [PeripheralBattery] = []
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    let device = PeripheralBattery(
                        id: (info["device_address"] as? String).map(normalizedAddress) ?? name,
                        name: name,
                        kind: kind(name: name, minorType: info["device_minorType"] as? String),
                        level: percent(info["device_batteryLevelMain"]) ?? percent(info["device_batteryLevel"]),
                        left: percent(info["device_batteryLevelLeft"]),
                        right: percent(info["device_batteryLevelRight"]),
                        caseLevel: percent(info["device_batteryLevelCase"]),
                        appleProductID: appleProductID(info),
                        modelName: appleProductID(info).flatMap(PeripheralBattery.headphoneName))
                    if device.lowest != nil || device.caseLevel != nil { result.append(device) }
                }
            }
        }
        return mergeSameName(result)
    }

    /// 廠商是 Apple（0x004C）時的 Product ID："0x2013" → 0x2013
    static func appleProductID(_ info: [String: Any]) -> Int? {
        func hex(_ key: String) -> Int? {
            guard let text = info[key] as? String, text.lowercased().hasPrefix("0x") else { return nil }
            return Int(text.dropFirst(2), radix: 16)
        }
        return hex("device_vendorID") == 0x004C ? hex("device_productID") : nil
    }

    /// 新款 AirPods 在系統藍牙資訊裡可能列兩次（兩個位址，其中一筆只有部分電量），同名的合併成一行：
    /// 左耳、右耳、充電盒各取有數值的那筆，兩筆都有時以資料比較完整的為準
    static func mergeSameName(_ devices: [PeripheralBattery]) -> [PeripheralBattery] {
        func completeness(_ device: PeripheralBattery) -> Int {
            [device.level, device.left, device.right, device.caseLevel].compactMap { $0 }.count
        }
        var merged: [PeripheralBattery] = []
        for device in devices {
            guard let index = merged.firstIndex(where: { $0.name.caseInsensitiveCompare(device.name) == .orderedSame }) else {
                merged.append(device)
                continue
            }
            let existing = merged[index]
            var primary = completeness(device) > completeness(existing) ? device : existing
            let other = primary == device ? existing : device
            primary.level = primary.level ?? other.level
            primary.left = primary.left ?? other.left
            primary.right = primary.right ?? other.right
            primary.caseLevel = primary.caseLevel ?? other.caseLevel
            primary.appleProductID = primary.appleProductID ?? other.appleProductID
            primary.modelName = primary.modelName ?? other.modelName
            primary.modelSymbol = primary.modelSymbol ?? other.modelSymbol
            if primary.kind == .other { primary.kind = other.kind }
            merged[index] = primary
        }
        return merged
    }

    /// IORegistry 中有 BatteryPercent 的 HID 服務；同一個設備可能有好幾個服務，依 id 合併
    static func hid(_ services: [[String: Any]]) -> [PeripheralBattery] {
        var result: [PeripheralBattery] = []
        for service in services {
            guard let level = percent(service["BatteryPercent"]) else { continue }
            let name = service["Product"] as? String ?? "藍牙設備"
            let id = (service["DeviceAddress"] as? String).map(normalizedAddress)
                ?? (service["SerialNumber"] as? String) ?? name
            guard !result.contains(where: { $0.id == id }) else { continue }
            result.append(PeripheralBattery(id: id, name: name, kind: kind(name: name), level: level))
        }
        return result
    }

    /// 藍牙標準電池服務的「電池電量」（0x2A19）：一個位元組，0～100
    static func bluetoothLELevel(_ value: Data?) -> Int? {
        guard let byte = value?.first, byte <= 100 else { return nil }
        return Int(byte)
    }

    /// 藍牙字串特徵值（例如型號 0x2A24）：UTF-8，去掉結尾的 NUL 與空白；空字串或超過 64 字元（不是型號）回 nil
    static func bluetoothLEText(_ value: Data?) -> String? {
        guard let value, let text = String(data: value, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        return trimmed.isEmpty || trimmed.count > 64 ? nil : trimmed
    }

    /// 藍牙低功耗 HID 設備的種類：名稱看得出來就用名稱，否則看 HID 用途
    /// （Generic Desktop 0x01：滑鼠 0x02、搖桿 0x04、遊戲手把 0x05、鍵盤 0x06；Digitizer 0x0D：觸控板）
    static func kind(name: String, usages: [(page: Int, usage: Int)]) -> PeripheralBattery.Kind {
        let byName = kind(name: name)
        if byName != .other { return byName }
        let set = Set(usages.map { "\($0.page):\($0.usage)" })
        if set.contains("1:2") { return .mouse }
        if set.contains("1:6") { return .keyboard }
        if set.contains("13:5") || set.contains("13:4") { return .trackpad }
        if set.contains("1:5") || set.contains("1:4") { return .gameController }
        return .other
    }

    /// 藍牙裝置資訊的型號代號（0x2A24，例如 "iPhone14,2"）→ iPhone 機型名稱與圖示；不是 iPhone 時回 nil。
    /// 不認得的代號（多半是新機）顯示通用名稱與圖示
    static func iPhone(model: String) -> (name: String, symbol: String?)? {
        // 只收 Apple 機型代號的格式（字首＋數字,數字），其他廠商的型號（例如 "iPhone Case"）不算
        guard model.range(of: #"^iPhone[0-9]+,[0-9]+$"#, options: .regularExpression) != nil else { return nil }
        return (iPhoneNames[model] ?? "iPhone", iPhoneSymbol(model))
    }

    /// iPhone XS 以後（iOS 18 支援的機型起）
    static let iPhoneNames: [String: String] = [
        "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max", "iPhone11,6": "iPhone XS Max", "iPhone11,8": "iPhone XR",
        "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE（第 2 代）",
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,6": "iPhone SE（第 3 代）", "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max", "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,5": "iPhone 16e",
        "iPhone18,3": "iPhone 17", "iPhone18,4": "iPhone Air", "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max",
    ]

    /// iPhone 外型對應的系統圖示：Home 鍵 gen1、瀏海 gen2、動態島 gen3；不認得的（多半是新機）回 nil 用通用圖示
    static func iPhoneSymbol(_ model: String) -> String? {
        guard iPhoneNames[model] != nil else { return nil }
        if ["iPhone12,8", "iPhone14,6"].contains(model) { return "iphone.gen1" }
        let notch: Set = ["iPhone11,2", "iPhone11,4", "iPhone11,6", "iPhone11,8", "iPhone12,1", "iPhone12,3", "iPhone12,5",
                          "iPhone13,1", "iPhone13,2", "iPhone13,3", "iPhone13,4", "iPhone14,2", "iPhone14,3", "iPhone14,4",
                          "iPhone14,5", "iPhone14,7", "iPhone14,8", "iPhone17,5"]
        return notch.contains(model) ? "iphone.gen2" : "iphone.gen3"
    }

    /// 設定關掉「顯示 iPhone」時，清單與低電量通知都不含手機
    static func visible(_ devices: [PeripheralBattery], showPhones: Bool) -> [PeripheralBattery] {
        showPhones ? devices : devices.filter { $0.kind != .phone }
    }

    /// 加上藍牙低功耗設備：同名的設備已經由 IORegistry 或 system_profiler 列出時（例如 Apple 的設備），以原本的為準
    static func merge(_ devices: [PeripheralBattery], bluetoothLE: [PeripheralBattery]) -> [PeripheralBattery] {
        var merged = devices
        for device in bluetoothLE where !merged.contains(where: { $0.name.caseInsensitiveCompare(device.name) == .orderedSame }) {
            merged.append(device)
        }
        return merged.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 同一個設備兩邊都有時合併：名稱與左右耳用 system_profiler 的（使用者取的藍牙名稱），缺的電量用 HID 補
    static func merge(hid: [PeripheralBattery], bluetooth: [PeripheralBattery]) -> [PeripheralBattery] {
        var merged = bluetooth
        for device in hid {
            if let index = merged.firstIndex(where: { $0.id == device.id }) {
                if merged[index].lowest == nil { merged[index].level = device.level }
                if merged[index].kind == .other { merged[index].kind = device.kind }
            } else {
                merged.append(device)
            }
        }
        return merged.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// 每個設備降到自己的門檻只通知一次；電量回到門檻以上（充過電）才會再通知
struct PeripheralAlerts {
    private(set) var fired: Set<String> = []

    /// 回傳這次要通知的設備；threshold 為 0 表示這個設備不通知
    mutating func evaluate(_ devices: [PeripheralBattery], threshold: (String) -> Int) -> [PeripheralBattery] {
        var due: [PeripheralBattery] = []
        for device in devices {
            guard let level = device.lowest else { continue }
            let limit = threshold(device.id)
            if limit > 0, level <= limit {
                if fired.insert(device.id).inserted { due.append(device) }
            } else if limit == 0 || level > limit + 2 {
                fired.remove(device.id)
            }
        }
        return due
    }
}
