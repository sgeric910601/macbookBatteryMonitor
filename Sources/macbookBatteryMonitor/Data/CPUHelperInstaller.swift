import Foundation
import CryptoKit
import CPUPowerShared
import Darwin

/// 一次授權安裝 root 保護的固定輔助程式；不修改 sudoers 或保存密碼。
enum CPUHelperInstaller {
    static var installed: Bool { configuration != nil }

    /// 服務能排定智慧充電喚醒：v1.7.1 以前安裝的服務只有 CPU 取樣，要用喚醒時需重新安裝
    static var supportsChargingWake: Bool { configuration?.chargingWake == true }

    /// 已安裝、檔案權限正確且屬於這個使用者的服務設定
    private static var configuration: CPUHelperConfiguration? {
        let fm = FileManager.default
        for (path, mode) in [(CPUHelperConstants.directory, 0o755),
                             (CPUHelperConstants.executable, 0o755),
                             (CPUHelperConstants.configuration, 0o644),
                             (CPUHelperConstants.launchDaemon, 0o644)] {
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  (attrs[.ownerAccountID] as? NSNumber)?.intValue == 0,
                  (attrs[.posixPermissions] as? NSNumber)?.intValue == mode,
                  attrs[.type] as? FileAttributeType != .typeSymbolicLink else { return nil }
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: CPUHelperConstants.configuration)),
              let config = try? JSONDecoder().decode(CPUHelperConfiguration.self, from: data),
              config.uid == getuid(), config.version == CPUHelperConstants.version else { return nil }
        return config
    }

    /// 系統裡留有任何服務檔案（包含版本不符的舊服務），關閉選項時要移除
    static var present: Bool {
        FileManager.default.fileExists(atPath: CPUHelperConstants.launchDaemon)
            || FileManager.default.fileExists(atPath: CPUHelperConstants.directory)
    }

    static func makeProcess(bundle: Bundle = .main, lease: URL) throws -> Process {
        let helper = bundle.bundleURL.appendingPathComponent("Contents/Library/Helpers/CPUPowerHelper")
        let data = try Data(contentsOf: helper)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let configuration = String(decoding: try JSONEncoder().encode(CPUHelperConfiguration(uid: getuid())), as: UTF8.self)
        let plist: [String: Any] = [
            "Label": CPUHelperConstants.label,
            "ProgramArguments": [CPUHelperConstants.executable],
            "MachServices": [CPUHelperConstants.label: true],
            "ProcessType": "Background",
            "AssociatedBundleIdentifiers": ["com.kuan.batterymonitor"],
        ]
        let plistText = String(decoding: try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0), as: UTF8.self)
        let script = """
        set -eu
        umask 022
        /bin/mkdir -p /Library/PrivilegedHelperTools /Library/LaunchDaemons
        /bin/test -f \(quote(lease.path))
        stage=$(/usr/bin/mktemp -d /Library/PrivilegedHelperTools/.batterymonitor-cpu.XXXXXXXX)
        trap '/bin/rm -rf "$stage"' EXIT
        /bin/cp \(quote(helper.path)) "$stage/CPUPowerHelper"
        hash=$(/usr/bin/shasum -a 256 "$stage/CPUPowerHelper")
        [ "${hash%% *}" = \(quote(digest)) ]
        /usr/bin/codesign --verify --strict "$stage/CPUPowerHelper"
        /usr/bin/printf '%s' \(quote(configuration)) > "$stage/config.json"
        /usr/bin/printf '%s' \(quote(plistText)) > "$stage/daemon.plist"
        /usr/sbin/chown -R root:wheel "$stage"
        /bin/chmod 755 "$stage" "$stage/CPUPowerHelper"
        /bin/chmod 644 "$stage/config.json" "$stage/daemon.plist"
        /bin/test -f \(quote(lease.path))
        /bin/launchctl bootout system/\(CPUHelperConstants.label) >/dev/null 2>&1 || true
        /bin/rm -rf \(quote(CPUHelperConstants.directory))
        /bin/mv "$stage" \(quote(CPUHelperConstants.directory))
        /bin/mv \(quote(CPUHelperConstants.directory + "/daemon.plist")) \(quote(CPUHelperConstants.launchDaemon))
        if ! /bin/launchctl bootstrap system \(quote(CPUHelperConstants.launchDaemon)); then
          /bin/rm -f \(quote(CPUHelperConstants.launchDaemon))
          /bin/rm -rf \(quote(CPUHelperConstants.directory))
          exit 1
        fi
        # osascript 中止不代表 root shell 已中止；最後再檢查取消狀態並回復。
        if ! /bin/test -f \(quote(lease.path)); then
          /bin/launchctl bootout system/\(CPUHelperConstants.label) >/dev/null 2>&1 || true
          /bin/rm -f \(quote(CPUHelperConstants.launchDaemon))
          /bin/rm -rf \(quote(CPUHelperConstants.directory))
          exit 1
        fi
        """
        let command = "/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/sh -c " + quote(script)
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        return task
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
