import Foundation

/// 設定的匯出與匯入（換 Mac、重灌時帶過去）。檔案是 plist：{ format, version, settings }。
/// 匯入時只收清單裡認得的設定，而且型別要對；不認得或壞掉的略過，其他照常匯入
enum SettingsBackup {
    enum Kind { case bool, int, double, string, strings, intMap, dictionary }

    enum ReadError: Error, Equatable { case tooLarge, unreadable, notOurs, newerVersion }

    static let format = "macbookBatteryMonitor-settings"
    static let version = 1
    /// 設定檔只有幾 KB，超過這個大小一定不是
    static let maxSize = 1_000_000

    /// 只匯出清單裡、而且型別正確的設定
    static func export(_ values: [String: Any], schema: [String: Kind]) throws -> Data {
        let settings = values.compactMapValues { $0 }.filter { key, value in schema[key].map { normalized(value, $0) != nil } ?? false }
        return try PropertyListSerialization.data(fromPropertyList: ["format": format, "version": version, "settings": settings],
                                                  format: .xml, options: 0)
    }

    /// 回傳通過檢查的設定（已轉成 Bool、Int、Double 等確定的型別）
    static func read(_ data: Data, schema: [String: Kind]) throws -> [String: Any] {
        guard data.count <= maxSize else { throw ReadError.tooLarge }
        guard let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw ReadError.unreadable
        }
        guard root["format"] as? String == format, let settings = root["settings"] as? [String: Any] else { throw ReadError.notOurs }
        guard let fileVersion = integer(root["version"]), fileVersion >= 1 else { throw ReadError.notOurs }
        guard fileVersion <= version else { throw ReadError.newerVersion }
        var accepted: [String: Any] = [:]
        for (key, value) in settings {
            if let kind = schema[key], let clean = normalized(value, kind) { accepted[key] = clean }
        }
        return accepted
    }

    private static func isBool(_ value: Any) -> Bool { CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() }

    /// 整數（不收布林、小數）
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, !isBool(number), !CFNumberIsFloatType(number) else { return nil }
        return number.intValue
    }

    private static func normalized(_ value: Any, _ kind: Kind) -> Any? {
        switch kind {
        case .bool: return isBool(value) ? (value as? Bool) : nil
        case .int: return integer(value)
        case .double:
            // NaN、無限大過不了上下限檢查，用到的地方會當掉
            guard let number = value as? NSNumber, !isBool(number), number.doubleValue.isFinite else { return nil }
            return number.doubleValue
        case .string: return value as? String
        case .strings: return value as? [String]
        case .intMap:
            guard let map = value as? [String: Any] else { return nil }
            let ints = map.compactMapValues { integer($0) }
            return ints.count == map.count ? ints : nil
        case .dictionary:
            // 內容由讀取它的設定自己驗證（例如 SwitcherSettings 會把壞掉的欄位退回預設）
            return value as? [String: Any]
        }
    }
}
