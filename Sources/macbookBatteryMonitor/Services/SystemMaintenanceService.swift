import Foundation

/// 系統層級快速維護與快取修復服務。
/// 借鑑 Mole 的 lib/optimize/maintenance.sh 實作，
/// 調用 macOS 原生系統維護二進位檔，無需 root 權限即可快速修復 DNS 快取與 QuickLook 預覽。
public enum SystemMaintenanceService {

    public struct MaintenanceOutcome: Equatable {
        public let operation: String
        public let success: Bool
        public let details: String
    }

    /// 執行指定命令
    @discardableResult
    private static func runCommand(_ launchPath: String, arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, output)
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    /// 刷新 macOS DNS 解析快取
    public static func flushDNS() -> MaintenanceOutcome {
        let (status1, _) = runCommand("/usr/bin/dscacheutil", arguments: ["-flushcache"])
        let (status2, _) = runCommand("/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"])

        let success = (status1 == 0 && (status2 == 0 || status2 == 1))
        return MaintenanceOutcome(
            operation: "刷新 DNS 快取",
            success: success,
            details: success ? "DNS 快取已成功清空並重新載入 mDNSResponder" : "執行過程回傳狀態異常 (\(status1), \(status2))"
        )
    }

    /// 重建 QuickLook 縮圖與預覽資料庫快取
    public static func rebuildQuickLookCache() -> MaintenanceOutcome {
        let (status, output) = runCommand("/usr/bin/qlmanage", arguments: ["-r", "cache"])
        let success = (status == 0)
        return MaintenanceOutcome(
            operation: "重建 QuickLook 快取",
            success: success,
            details: success ? "縮圖與 QuickLook 快取已重設：\(output)" : "qlmanage 執行失敗：\(output)"
        )
    }

    /// 強制釋放系統不活躍快取記憶體（macOS 原生 purge 指令）
    public static func purgeMemory() -> MaintenanceOutcome {
        let (status, output) = runCommand("/usr/bin/purge", arguments: [])
        let success = (status == 0)
        return MaintenanceOutcome(
            operation: "釋放不活躍記憶體",
            success: success,
            details: success ? "已強制回收未使用的磁碟讀寫記憶體快取" : "記憶體釋放未成功：\(output)"
        )
    }

    /// 一鍵執行全套無痛系統維護
    public static func performFullMaintenance() -> [MaintenanceOutcome] {
        return [
            flushDNS(),
            rebuildQuickLookCache(),
            purgeMemory()
        ]
    }
}
