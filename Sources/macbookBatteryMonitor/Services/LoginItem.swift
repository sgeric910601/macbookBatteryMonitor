import AppKit
import ServiceManagement

/// 開機（登入）自動啟動。macOS 13 起優先用 SMAppService，失敗時或 macOS 12 改用 LaunchAgent plist。
enum LoginItem {
    enum Status {
        case enabled
        case requiresApproval
        case disabled
    }

    private static let label = "com.kuan.batterymonitor"
    /// 上次自動註冊時 App 的位置
    static let registeredPathKey = "loginItemRegisteredPath"
    /// 使用者在設定裡手動關掉
    static let disabledByUserKey = "loginItemDisabledByUser"

    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isInApplications: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    static var status: Status {
        if #available(macOS 13, *), !Compat.forceMacOS12Paths {
            switch SMAppService.mainApp.status {
            case .enabled: return .enabled
            case .requiresApproval: return .requiresApproval
            default: break
            }
        }
        return FileManager.default.fileExists(atPath: agentURL.path) ? .enabled : .disabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard #available(macOS 13, *), !Compat.forceMacOS12Paths else {
                try writeLaunchAgent()
                return
            }
            do {
                try SMAppService.mainApp.register()
                // 以前退回寫的 LaunchAgent 要移除，否則登入時會啟動兩次
                try? FileManager.default.removeItem(at: agentURL)
            } catch {
                try writeLaunchAgent()
            }
        } else {
            if #available(macOS 13, *), !Compat.forceMacOS12Paths { try? SMAppService.mainApp.unregister() }
            try? FileManager.default.removeItem(at: agentURL)
        }
    }

    static func openSystemSettings() {
        if #available(macOS 13, *), !Compat.forceMacOS12Paths {
            SMAppService.openSystemSettingsLoginItems()
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.users") {
            // macOS 12：系統偏好設定 →「使用者與群組」的登入項目
            NSWorkspace.shared.open(url)
        }
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
