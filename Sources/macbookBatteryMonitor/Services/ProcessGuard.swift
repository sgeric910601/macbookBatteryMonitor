import Foundation
import AppKit

/// 進程守護與敏感路徑防護機制。
/// 參考 Mole 的 app_protection.sh、app_caches.sh 與 sensitive_data 篩選演算法，
/// 確保在清理快取時絕對不誤觸敏感目錄、不在關聯應用運作時清理其動態快取。
public enum ProcessGuard {

    /// 檢查特定名稱的應用程式或工具是否正在運行
    public static func isProcessRunning(named name: String) -> Bool {
        let running = NSWorkspace.shared.runningApplications
        if running.contains(where: {
            $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame ||
            $0.bundleIdentifier?.localizedCaseInsensitiveContains(name) == true
        }) {
            return true
        }

        // 使用 sysctl / pgrep 查驗命令列背景進程
        return isCLIProcessRunning(named: name)
    }

    /// 透過 sysctl 查驗 Unix 進程表
    private static func isCLIProcessRunning(named name: String) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return false
        }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, u_int(mib.count), &procs, &size, nil, 0) == 0 else {
            return false
        }

        let bufSize = MemoryLayout.size(ofValue: procs.first?.kp_proc.p_comm)
        let target = name.lowercased()
        for p in procs {
            var nameBuf = p.kp_proc.p_comm
            let procName = withUnsafePointer(to: &nameBuf) {
                $0.withMemoryRebound(to: CChar.self, capacity: bufSize) {
                    String(cString: $0).lowercased()
                }
            }
            if procName == target {
                return true
            }
        }
        return false
    }

    /// 檢查給定路徑是否含有敏感帳號資料、身分金鑰或重要設定
    public static func isSensitivePath(_ path: String) -> Bool {
        let normalized = (path as NSString).standardizingPath.lowercased()

        let sensitiveSubstrings = [
            "/.ssh/",
            "/.gnupg/",
            "/.aws/",
            "/.kube/",
            "/.docker/config.json",
            "/keychains/",
            "/cookies/",
            "/passwords/",
            "/accounts/",
            "/credentials/",
            "/secrets/",
            "/preferences/",
            "/documents/",
            "/desktop/",
            "/downloads/"
        ]

        for s in sensitiveSubstrings {
            if normalized.contains(s) {
                return true
            }
        }

        // 結尾特定附檔名防護
        let sensitiveSuffixes = [
            ".key", ".pem", ".p12", ".pfx", ".cert", ".crt", "id_rsa", "id_ed25519"
        ]
        for s in sensitiveSuffixes {
            if normalized.hasSuffix(s) {
                return true
            }
        }

        return false
    }

    /// 檢查路徑是否屬於受保護的核心系統目錄
    public static func isProtectedSystemPath(_ path: String) -> Bool {
        let normalized = (path as NSString).standardizingPath
        let protectedPrefixes = [
            "/System",
            "/bin",
            "/sbin",
            "/usr/bin",
            "/usr/sbin",
            "/Library/Apple",
            "/Library/Preferences/SystemConfiguration"
        ]

        for prefix in protectedPrefixes {
            if normalized == prefix || normalized.hasPrefix(prefix + "/") {
                return true
            }
        }
        return false
    }

    /// 綜合安全校驗：該目標是否安全可清理
    public static func isSafeToClean(path: String, associatedProcess: String? = nil) -> (safe: Bool, reason: String?) {
        if isProtectedSystemPath(path) {
            return (false, "受保護的系統目錄，禁止清理")
        }
        if isSensitivePath(path) {
            return (false, "路徑包含機密金鑰或重要個人資料，禁止清理")
        }
        if let proc = associatedProcess, isProcessRunning(named: proc) {
            return (false, "\(proc) 正在運行中，為避免當機或資料損毀已跳過")
        }
        return (true, nil)
    }
}
