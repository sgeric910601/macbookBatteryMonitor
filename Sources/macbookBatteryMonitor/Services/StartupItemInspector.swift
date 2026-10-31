import AppKit
import Foundation
import Security

/// 只讀：查簽章、查相關 App 有沒有裝、在固定資料夾裡找精確比對的殘留檔案。不修改任何檔案
enum StartupItemInspector {
    nonisolated static func inspect(_ item: StartupItem) -> StartupItemInfo {
        var info = StartupItemInfo()
        let fm = FileManager.default
        info.programExists = item.path.isEmpty || !item.path.hasPrefix("/") || fm.fileExists(atPath: item.path)
        info.vendorHint = item.label.flatMap { StartupItemInfoLogic.vendorHint(label: $0) }

        var authorized: [String] = []
        let codePath = StartupItemInfoLogic.containerBundlePath(of: item.path) ?? item.path
        if codePath.hasPrefix("/"), fm.fileExists(atPath: codePath) {
            readSignature(at: codePath, into: &info, authorized: &authorized)
        }

        // 只有輔助程式自己宣告的授權名單才算「相關的 App」；Label 推測的名稱只拿來找檔案，不拿來下結論
        var related = authorized
        // 登入項目本身就是 App：識別碼算
        if let id = info.identifier, !related.contains(id), item.kind == .loginItem { related.append(id) }
        info.relatedBundleIDs = related
        info.installedRelatedIDs = related.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        for id in related { info.appNames[id] = appName(for: id) }

        if StartupItemInfoLogic.shouldScan(label: item.label), let label = item.label {
            info.leftovers = findLeftovers(item: item, ids: related + StartupItemInfoLogic.guessedIDs(label: label))
            info.inferredAppIDs = StartupItemInfoLogic.inferredAppIDs(fromPaths: info.leftovers, excluding: label)
                .filter { !related.contains($0) }
            info.installedInferredIDs = info.inferredAppIDs.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
            for id in info.inferredAppIDs { info.appNames[id] = appName(for: id) }
        }
        return info
    }

    /// 已安裝的 App 用實際名稱；找不到時從識別碼拆出來
    private nonisolated static func appName(for id: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return StartupItemInfoLogic.friendlyName(fromIdentifier: id)
    }

    private nonisolated static func readSignature(at path: String, into info: inout StartupItemInfo, authorized: inout [String]) {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess, let staticCode else { return }
        var cfInfo: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &cfInfo) == errSecSuccess,
              let dict = cfInfo as? [String: Any] else { return }
        info.teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String
        info.identifier = dict[kSecCodeInfoIdentifier as String] as? String
        if let certs = dict[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certs.first,
           let summary = SecCertificateCopySubjectSummary(leaf) as String? {
            info.signer = summary
        }
        if let plist = dict[kSecCodeInfoPList as String] as? [String: Any] {
            if let id = plist["CFBundleIdentifier"] as? String { info.identifier = id }
            for requirement in (plist["SMAuthorizedClients"] as? [String]) ?? [] {
                if let id = StartupItemInfoLogic.bundleID(fromRequirement: requirement) { authorized.append(id) }
            }
        }
    }

    /// 固定的幾個資料夾，各一層：識別碼精確比對，加上資料夾名稱等於開發者名稱
    private nonisolated static func findLeftovers(item: StartupItem, ids: [String]) -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let folders = [
            "/Library/LaunchDaemons", "/Library/LaunchAgents", "/Library/PrivilegedHelperTools",
            "/Library/Application Support", "/Library/Audio/Plug-Ins/HAL", "/Library/Preferences",
            "\(home)/Library/LaunchAgents", "\(home)/Library/Application Support", "\(home)/Library/Preferences",
            "\(home)/Library/Caches", "\(home)/Library/Logs", "\(home)/Library/Containers",
        ]
        let vendor = item.label.flatMap { StartupItemInfoLogic.vendorHint(label: $0) }
        var found: [String] = []
        for folder in folders {
            let supportFolder = folder.hasSuffix("Application Support")
            for name in (try? fm.contentsOfDirectory(atPath: folder)) ?? [] {
                if StartupItemInfoLogic.matches(fileName: name, ids: ids)
                    || (supportFolder && StartupItemInfoLogic.matchesVendor(fileName: name, vendor: vendor)) {
                    found.append("\(folder)/\(name)")
                }
            }
        }
        // 設定檔本身與它指向的程式（含所在的 .app / .xpc）
        if let plist = item.plistPath { found.append(plist) }
        if item.path.hasPrefix("/"), fm.fileExists(atPath: item.path) {
            found.append(StartupItemInfoLogic.containerBundlePath(of: item.path) ?? item.path)
        }
        var seen = Set<String>()
        return found.filter { seen.insert($0).inserted }.sorted()
    }
}
