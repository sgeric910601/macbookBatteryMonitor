import Darwin
import Foundation

/// 系統設定「電池健康度與充電」裡的充電上限。
/// powerd 把目前生效的充電策略存成 NSKeyedArchiver 格式（類別名 ChargeCtrlPolicy），
/// 檔案權限一般使用者可讀，這裡只讀不寫。
/// 注意：這份策略只在接電時存在，拔掉電源後會被清空；使用者設定本身由 SystemChargeLimit 向系統的充電上限服務讀取。
struct ChargeLimit: Codable, Equatable {
    /// 上限 %
    var limit: Int
    /// 例如 manualChargeLimit（使用者手動設定）
    var reason: String
    /// false 表示目前沒在生效（用電池中），數值是上次接電時讀到的
    var active = true
}

/// 對應系統的 ChargeCtrlPolicy，只解出需要的欄位
@objc(BMChargeCtrlPolicy)
private final class ChargeCtrlPolicyStub: NSObject, NSCoding {
    let soclimit: Int
    let reason: String?
    let terminated: Bool

    init?(coder: NSCoder) {
        soclimit = coder.decodeInteger(forKey: "soclimit")
        reason = coder.decodeObject(forKey: "reason") as? String
        terminated = coder.decodeBool(forKey: "terminated")
    }

    func encode(with coder: NSCoder) {}
}

enum ChargeLimitReader {
    private static let url = URL(fileURLWithPath: "/Library/Preferences/com.apple.powerd.charging.plist")
    private static let lastKnownKey = "lastKnownChargeLimit"
    /// 接電後等這麼久還沒有生效中的策略，就當作使用者已經關掉充電上限
    private static let clearAfterPlugged: TimeInterval = 120

    /// 系統充電上限服務讀到的設定：100 表示不限制；讀不到（不支援的 Mac）或系統暫時沒有套用時為 nil
    private(set) static var systemLimit: Int?

    /// SystemChargeLimit 讀到或調整上限後呼叫，用電池時也能顯示正確的上限
    static func updateFromSystem(limit: Int, enabled: Bool) {
        let defaults = UserDefaults.standard
        if limit >= 100 {
            systemLimit = 100
            defaults.removeObject(forKey: lastKnownKey)
        } else if enabled {
            systemLimit = limit
            if defaults.integer(forKey: lastKnownKey) != limit { defaults.set(limit, forKey: lastKnownKey) }
        } else {
            systemLimit = nil
        }
    }

    /// 接電時以生效中的策略為準；用電池時策略會被清空，改用系統服務讀到的設定，再不行就用最後一次讀到的值。
    /// - Parameter pluggedSince: 這次接上電源的時間；nil 表示不判斷是否已關閉（只讀不清除）
    static func resolve(externalConnected: Bool, pluggedSince: Date?) -> ChargeLimit? {
        let defaults = UserDefaults.standard
        if let live = current() {
            if defaults.integer(forKey: lastKnownKey) != live.limit { defaults.set(live.limit, forKey: lastKnownKey) }
            return live
        }
        if let systemLimit {
            return systemLimit < 100 ? ChargeLimit(limit: systemLimit, reason: "manualChargeLimit", active: false) : nil
        }
        let cached = defaults.integer(forKey: lastKnownKey)
        guard cached > 0 else { return nil }
        if externalConnected, let pluggedSince, Date().timeIntervalSince(pluggedSince) > clearAfterPlugged {
            defaults.removeObject(forKey: lastKnownKey)
            return nil
        }
        return ChargeLimit(limit: cached, reason: "lastKnown", active: false)
    }

    /// 給設定頁用：生效中的值，沒有就用上次記住的
    static func lastKnown() -> ChargeLimit? {
        resolve(externalConnected: false, pluggedSince: nil)
    }
    /// 上次讀到的檔案修改時間（秒、奈秒）
    private static var cachedModified: (Int, Int)?
    private static var cached: ChargeLimit?

    /// 檔案沒變就用上次的結果，不重複解析
    /// 每秒都會呼叫，用 stat() 只讀修改時間（FileManager.attributesOfItem 會建整個屬性字典，慢很多）
    static func current() -> ChargeLimit? {
        var info = stat()
        let modified = stat(url.path, &info) == 0 ? (info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec) : nil
        if let modified, let cachedModified, modified == cachedModified { return cached }
        cachedModified = modified
        cached = read()
        return cached
    }

    private static func read() -> ChargeLimit? {
        (try? Data(contentsOf: url)).flatMap(parse)
    }

    /// com.apple.powerd.charging.plist 的內容 → 生效中的使用者上限；格式不符時為 nil
    static func parse(_ data: Data) -> ChargeLimit? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let archive = plist["policies"] as? Data,
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: archive) else { return nil }
        unarchiver.requiresSecureCoding = false
        unarchiver.setClass(ChargeCtrlPolicyStub.self, forClassName: "ChargeCtrlPolicy")
        let policies = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? [Any] ?? []
        unarchiver.finishDecoding()

        // 可能同時有多個策略（例如最佳化充電暫停），取生效中且上限最低的
        let active = policies
            .compactMap { $0 as? ChargeCtrlPolicyStub }
            // 只採用使用者在系統設定裡設的上限；「最佳化電池充電」等暫時的暫停不算
            .filter { !$0.terminated && $0.reason == "manualChargeLimit" && $0.soclimit > 0 && $0.soclimit < 100 }
            .min { $0.soclimit < $1.soclimit }
        guard let active else { return nil }
        return ChargeLimit(limit: active.soclimit, reason: active.reason ?? "")
    }
}
