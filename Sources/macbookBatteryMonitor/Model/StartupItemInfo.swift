import Foundation

/// 一個啟動項目的來歷：它是什麼、誰簽的、替哪個 App 工作、還留著哪些相關檔案
struct StartupItemInfo: Equatable {
    /// 憑證上的簽署者，例如「Developer ID Application: Example Inc (ABCDE12345)」
    var signer: String?
    var teamID: String?
    /// 程式自己的識別碼（bundle identifier 或簽章識別碼）
    var identifier: String?
    /// 這個元件替哪些 App 工作（輔助程式的授權名單；找不到時用 Label 推測）
    var relatedBundleIDs: [String] = []
    /// relatedBundleIDs 裡，現在還裝著的
    var installedRelatedIDs: [String] = []
    /// 從殘留的偏好設定、容器等檔名推測出來的 App 識別碼（不是輔助程式自己宣告的）
    var inferredAppIDs: [String] = []
    var installedInferredIDs: [String] = []
    /// 識別碼對應的顯示名稱（已安裝用 App 實際名稱，否則從識別碼拆出來）
    var appNames: [String: String] = [:]
    var vendorHint: String?
    var programExists = true
    /// 可能的殘留檔案（精確比對，不是模糊搜尋），完整路徑
    var leftovers: [String] = []

    /// 相關 App 都已經不在
    var ownerMissing: Bool { !relatedBundleIDs.isEmpty && installedRelatedIDs.isEmpty }
}

enum StartupItemInfoLogic {
    /// 輔助程式的授權名單長得像 `identifier "com.example.App" and anchor apple generic ...`
    static func bundleID(fromRequirement text: String) -> String? {
        guard let start = text.range(of: "identifier \"") else { return nil }
        let rest = text[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let id = String(rest[..<end])
        return StartupItemLogic.isValidLabel(id) ? id : nil
    }

    /// 反向網域的第二段，通常是開發者或公司：com.example.Tool → example
    static func vendorHint(label: String) -> String? {
        let parts = label.split(separator: ".")
        guard parts.count >= 3, ["com", "org", "net", "io", "app"].contains(parts[0].lowercased()) else { return nil }
        return String(parts[1])
    }

    /// 用 Label 推測相關的識別碼：自己，以及去掉最後一段（常見的 .helper、.daemon）後的上層
    static func guessedIDs(label: String) -> [String] {
        let parts = label.split(separator: ".")
        var ids = [label]
        if parts.count >= 4 { ids.append(parts.dropLast().joined(separator: ".")) }
        return ids
    }

    /// 檔名（去掉 .plist）等於識別碼，或以「識別碼.」開頭
    static func matches(fileName: String, ids: [String]) -> Bool {
        let base = fileName.hasSuffix(".plist") ? String(fileName.dropLast(6)) : fileName
        return ids.contains { id in
            base.caseInsensitiveCompare(id) == .orderedSame || base.lowercased().hasPrefix(id.lowercased() + ".")
        }
    }

    /// 殘留檔案裡，放在偏好設定、容器、快取、Application Support 底下、檔名像 App 識別碼（反向網域至少三段）的，
    /// 去掉副檔名後就是推測的 App 識別碼。排除項目自己的 Label
    static func inferredAppIDs(fromPaths paths: [String], excluding label: String?) -> [String] {
        let folders = ["Preferences", "Containers", "Caches", "Logs", "Application Support"]
        var result: [String] = []
        for path in paths {
            let parts = path.split(separator: "/").map(String.init)
            guard parts.count >= 2, folders.contains(parts[parts.count - 2]) else { continue }
            var name = parts[parts.count - 1]
            if name.hasSuffix(".plist") { name = String(name.dropLast(6)) }
            guard name.split(separator: ".").count >= 3, StartupItemLogic.isValidLabel(name),
                  name != label, !result.contains(name) else { continue }
            result.append(name)
        }
        return result
    }

    /// 從識別碼拆出好讀的名稱：com.example.Tool.App → Tool
    static func friendlyName(fromIdentifier id: String) -> String {
        var parts = id.split(separator: ".").map(String.init)
        guard !parts.isEmpty else { return id }
        let last = parts[parts.count - 1]
        if let first = parts.first?.lowercased(), ["com", "org", "net", "io", "app", "co", "me"].contains(first) { parts.removeFirst() }
        if parts.count >= 2 { parts.removeFirst() }
        let generic: Set<String> = ["app", "helper", "daemon", "agent", "xpc", "xpchelper", "service", "launcher", "widget", "privilegedhelpertool", "login", "loginitem"]
        while parts.count > 1, generic.contains(parts[parts.count - 1].lowercased()) { parts.removeLast() }
        let name = parts.joined(separator: " ")
        return name.isEmpty ? last : name
    }

    /// 搜尋用的網址；識別名稱已驗證過只含英數與 . - _
    static func searchURL(for label: String) -> URL? {
        guard StartupItemLogic.isValidLabel(label) else { return nil }
        return URL(string: "https://duckduckgo.com/?q=\(label)")
    }

    /// 資料夾名稱剛好等於開發者名稱（例如 Application Support/Example）
    static func matchesVendor(fileName: String, vendor: String?) -> Bool {
        guard let vendor, vendor.count >= 3 else { return false }
        return fileName.caseInsensitiveCompare(vendor) == .orderedSame
    }

    /// 蘋果自己的項目不掃殘留
    static func shouldScan(label: String?) -> Bool {
        guard let label else { return false }
        return !label.hasPrefix("com.apple.")
    }

    /// 路徑所在的 .app 或 .xpc 套件，沒有就是 nil
    static func containerBundlePath(of path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        var built = ""
        for part in path.split(separator: "/") {
            built += "/" + part
            if part.hasSuffix(".app") || part.hasSuffix(".xpc") { return built }
        }
        return nil
    }
}
