import Foundation
import Security
import ServiceManagement

/// 開機（登入）自動啟動。優先用 SMAppService，失敗時退回 LaunchAgent plist。
enum LoginItem {
    enum Status {
        case enabled
        case requiresApproval
        case disabled
    }

    static let label = "com.kuan.batterymonitor"
    /// 上次自動註冊時 App 的位置
    static let registeredPathKey = "loginItemRegisteredPath"
    /// 上次自動註冊時 App 的程式碼雜湊（cdhash）
    static let registeredCodeKey = "loginItemRegisteredCode"
    /// 使用者在設定裡手動關掉
    static let disabledByUserKey = "loginItemDisabledByUser"

    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// 這個 App 的程式碼雜湊（cdhash）。macOS 13 的登入項目用它辨認 App，每次建置、重新簽章都不同；讀不到時用版本號
    static var codeIdentity: String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess,
              let unique = (info as? [String: Any])?[kSecCodeInfoUnique as String] as? Data else {
            return Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        }
        return unique.map { String(format: "%02x", $0) }.joined()
    }

    static var isInApplications: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        default:
            return FileManager.default.fileExists(atPath: agentURL.path) ? .enabled : .disabled
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            do {
                try SMAppService.mainApp.register()
                // 以前退回寫的 LaunchAgent 要移除，否則登入時會啟動兩次
                try? FileManager.default.removeItem(at: agentURL)
            } catch {
                try writeLaunchAgent()
            }
        } else {
            try? SMAppService.mainApp.unregister()
            try? FileManager.default.removeItem(at: agentURL)
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func writeLaunchAgent() throws {
        guard let executable = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: agentURL, options: .atomic)
    }
}
