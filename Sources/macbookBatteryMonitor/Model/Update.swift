import CryptoKit
import Foundation

/// 版本號與 Beta 序號。GitHub 的 tag 是 v1.7.1、v1.8.0-beta.1；App 的 Info.plist 是 1.8.0，
/// Beta 另外帶 MBMPrerelease = beta.1。同一個版本號的正式版比它的任何 Beta 都新
struct AppVersion: Equatable, Comparable {
    var numbers: [Int]
    /// nil 是正式版
    var beta: Int?

    var isBeta: Bool { beta != nil }
    /// 畫面上顯示的版本：1.7.1、1.8.0 beta 1
    var text: String { numbers.map(String.init).joined(separator: ".") + (beta.map { " beta \($0)" } ?? "") }

    init(numbers: [Int], beta: Int? = nil) {
        self.numbers = numbers
        self.beta = beta
    }

    /// "v1.7.1"、"1.7.1"、"v1.8.0-beta.1"；其他格式回傳 nil
    init?(_ text: String) {
        let parts = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let numbers = UpdateLogic.version(String(parts[0])) else { return nil }
        var beta: Int?
        if parts.count == 2 {
            let suffix = parts[1]
            guard suffix.hasPrefix("beta."), let number = Int(suffix.dropFirst(5)), number > 0 else { return nil }
            beta = number
        }
        self.init(numbers: numbers, beta: beta)
    }

    /// 執行中的 App 的版本（Info.plist）
    static func current(info: [String: Any]? = Bundle.main.infoDictionary) -> AppVersion {
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let prerelease = info?["MBMPrerelease"] as? String
        return AppVersion(prerelease.map { "\(short)-\($0)" } ?? short) ?? AppVersion(numbers: UpdateLogic.version(short) ?? [0])
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if UpdateLogic.isNewer(rhs.numbers, than: lhs.numbers) { return true }
        if UpdateLogic.isNewer(lhs.numbers, than: rhs.numbers) { return false }
        switch (lhs.beta, rhs.beta) {
        case (nil, _): return false
        case (_, nil): return true
        case let (left?, right?): return left < right
        }
    }
}

/// GitHub Releases 上可以更新的版本、對應這個 App 的下載資訊
struct ReleaseInfo: Equatable {
    var tag: String
    var version: [Int]
    var pageURL: URL
    var assetName: String
    var assetURL: URL
    var assetSize: Int
    /// Release 附的 SHA256SUMS.txt（加入一鍵更新之後的 Release 才有）
    var checksumURL: URL?
    /// SHA256SUMS.txt 的更新簽章（v1.7.5 起的 Release 才有）
    var signatureURL: URL? = nil
    /// Beta 序號；nil 是正式版
    var beta: Int? = nil

    var appVersion: AppVersion { AppVersion(numbers: version, beta: beta) }
    var isBeta: Bool { beta != nil }
    /// 校驗檔與更新簽章都有才能一鍵更新
    var isSigned: Bool { checksumURL != nil && signatureURL != nil }
    var versionText: String { appVersion.text }
}

enum UpdateLogic {
    static let checksumFile = "SHA256SUMS.txt"
    /// SHA256SUMS.txt 的更新簽章：一行 base64，是 64 bytes 的 Ed25519 原始簽章，簽的是 SHA256SUMS.txt 的原始位元組。
    /// 發布時在發布者的 Mac 上用 Scripts/sign-release.sh 簽（私鑰只在那台的鑰匙圈）
    static let signatureFile = "SHA256SUMS.sig"

    /// 一鍵更新信任的更新簽章公鑰（32 bytes 原始公鑰的 base64）。用陣列存：換金鑰時先發一版同時信任新舊兩把的 App
    static let updatePublicKeys = ["IgVQOfoM0nYqd6D4kCw0UmjhdWgzPXJiyPmrwZysQ3k="]

    /// 新版 App 一定要是這張憑證簽的（Scripts/make-signing-cert.sh 建立的「macbookBatteryMonitor Signing」，
    /// 和 Scripts/check-signature.sh 相同）；用別的憑證或 ad-hoc 簽的都不安裝
    static let codeRequirement = #"identifier "com.kuan.batterymonitor" and certificate leaf = H"8a0f04d547969a353a94b2697263f1326370aec0""#

    /// 簽章要是其中一把公鑰簽的；格式不對（不是 base64、長度不對）一律不通過
    static func isSignatureValid(_ signature: String, for sums: Data, publicKeys: [String] = updatePublicKeys) -> Bool {
        guard let raw = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)), raw.count == 64 else { return false }
        return publicKeys.contains { encoded in
            guard let data = Data(base64Encoded: encoded), data.count == 32,
                  let key = try? Curve25519.Signing.PublicKey(rawRepresentation: data) else { return false }
            return key.isValidSignature(raw, for: sums)
        }
    }

    /// "v1.4.1"、"1.4.1" → [1, 4, 1]；有不是數字的部分就回傳 nil
    static func version(_ text: String) -> [Int]? {
        let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = trimmed.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        return parts.map { $0! }
    }

    /// 逐段比較，缺的段當 0（1.4 == 1.4.0）
    static func isNewer(_ candidate: [Int], than current: [Int]) -> Bool {
        for i in 0..<max(candidate.count, current.count) {
            let a = i < candidate.count ? candidate[i] : 0
            let b = i < current.count ? current[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// 新版本比上次通知過的版本新才通知（同一個版本只通知一次）
    static func shouldNotify(_ candidate: [Int], lastNotified: String?) -> Bool {
        guard let last = lastNotified.flatMap(version) else { return true }
        return isNewer(candidate, than: last)
    }

    /// v1.7.2 起給人下載、也給一鍵更新用的 DMG（macOS 14 以上的通用版）。檔名固定不帶版本號，
    /// 「最新版本」的下載連結（releases/latest/download/…）永遠有效
    static let dmgAssetName = "macbookBatteryMonitor.dmg"

    /// v1.7.1、v1.7.2 的通用版 zip（Apple 晶片與 Intel）。v1.7.2 仍附上，v1.7.1 的一鍵更新才找得到
    static func universalAssetName(tag: String) -> String {
        "macbookBatteryMonitor-\(tag)-macOS-universal.zip"
    }

    /// 舊系統版本（macOS 12、13）的 DMG（v1.7.2 起，檔名固定）
    static let legacyDMGAssetName = "macbookBatteryMonitor-macOS12.dmg"

    /// 舊系統版本（macOS 12、13）的 zip（v1.7.1、v1.7.2）
    static func legacyAssetName(tag: String) -> String {
        "macbookBatteryMonitor-\(tag)-macOS12.zip"
    }

    /// v1.7.2 以前附的電池版／系統監控版檔名（給 v1.5.0～v1.6.2 的一鍵更新）
    static func assetName(tag: String, edition: String) -> String {
        "macbookBatteryMonitor-\(tag)-\(edition)-macOS-arm64.zip"
    }

    /// 只從 GitHub 的網址下載（下載連結會轉址到 githubusercontent.com）
    static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host == "api.github.com" || host.hasSuffix(".githubusercontent.com")
    }

    /// 解析單一個 Release（GET /repos/{owner}/{repo}/releases/latest 的回應）：只接受正式版
    /// - Parameter mainSupported: 這台 Mac 能不能跑主版本（macOS 14 以上）；舊系統版本在系統升級後改裝主版本
    static func release(json: Data, edition: String, mainSupported: Bool = true) -> ReleaseInfo? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let release = release(root, edition: edition, mainSupported: mainSupported), !release.isBeta else { return nil }
        return release
    }

    /// 解析 GET /repos/{owner}/{repo}/releases 的清單（包含 Beta），格式不對或找不到下載檔的略過
    static func releases(json: Data, edition: String, mainSupported: Bool = true) -> [ReleaseInfo] {
        guard let list = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else { return [] }
        return list.compactMap { release($0, edition: edition, mainSupported: mainSupported) }
    }

    /// 從清單挑出可以更新的版本：正式版取比目前新的最新一個；Beta 只有比目前版本、也比最新正式版新時才列出
    /// （是否顯示 Beta 由呼叫的地方決定：只有使用者手動檢查時才找 Beta，也不發通知）
    static func choose(_ releases: [ReleaseInfo], current: AppVersion) -> (stable: ReleaseInfo?, beta: ReleaseInfo?) {
        let newer = releases.filter { current < $0.appVersion }
        let stable = newer.filter { !$0.isBeta }.max { $0.appVersion < $1.appVersion }
        let beta = newer.filter { release in
            release.isBeta && (stable.map { $0.appVersion < release.appVersion } ?? true)
        }.max { $0.appVersion < $1.appVersion }
        return (stable, beta)
    }

    /// 一個 Release：優先用 DMG，再來是 zip，都沒有的舊 Release 才用舊檔名；都找不到就回傳 nil。
    /// 舊系統版本（legacy）只找 macOS12 的檔案，系統已升級到 macOS 14 以上（mainSupported）時優先改裝通用版。
    /// 標成預先發行（prerelease）的必須是 v1.8.0-beta.1 這種 tag，正式版的 tag 不能帶 Beta 序號
    static func release(_ root: [String: Any], edition: String, mainSupported: Bool = true) -> ReleaseInfo? {
        guard let tag = root["tag_name"] as? String, let parsed = AppVersion(tag),
              root["draft"] as? Bool != true,
              (root["prerelease"] as? Bool == true) == parsed.isBeta,
              let page = (root["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = root["assets"] as? [[String: Any]] else { return nil }
        let version = parsed.numbers
        func asset(_ name: String) -> (url: URL, size: Int)? {
            guard let item = assets.first(where: { $0["name"] as? String == name }),
                  let url = (item["browser_download_url"] as? String).flatMap(URL.init(string:)), isTrusted(url) else { return nil }
            return (url, item["size"] as? Int ?? 0)
        }
        let candidates: [String]
        if edition == "legacy" {
            let own = [legacyDMGAssetName, legacyAssetName(tag: tag)]
            candidates = mainSupported ? [dmgAssetName, universalAssetName(tag: tag)] + own : own
        } else {
            let legacyEdition = edition == "battery" ? "battery" : "status"
            candidates = [dmgAssetName, universalAssetName(tag: tag), assetName(tag: tag, edition: legacyEdition)]
        }
        guard let name = candidates.first(where: { asset($0) != nil }), let file = asset(name) else { return nil }
        return ReleaseInfo(tag: tag, version: version, pageURL: page, assetName: name, assetURL: file.url,
                           assetSize: file.size, checksumURL: asset(checksumFile)?.url, signatureURL: asset(signatureFile)?.url,
                           beta: parsed.beta)
    }

    /// SHA256SUMS.txt 每行「<64 位十六進位>  <檔名>」
    static func checksum(in text: String, for name: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2, parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "*")) == name else { continue }
            let hash = parts[0].lowercased()
            if hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) { return hash }
        }
        return nil
    }
}
