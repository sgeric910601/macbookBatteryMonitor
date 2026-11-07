import Foundation

/// 會擋住輸入的攔截失去權限後怎麼恢復（偵測與執行在 EventTapAccess）。
/// 權限 API 也說沒權限（使用者關掉開關）：只放掉攔截，各功能自己的檢查會在重新允許後重新開始，不必重開 App。
/// 權限 API 還說有權限（使用者從清單「移除」，API 回答的是舊結果）：重新開啟 App，重開後的權限查詢才是新的。
/// 剛為了這個重開過又偵測到，可能是誤判：不再重開（避免一直重開），停用攔截，之後慢慢試建，建得起來就恢復。
/// 從磁碟映像或暫存位置（App Translocation）執行時重開會找不到 App，也改成停用
enum TapAccess {
    enum Recovery: Equatable { case waitForPermission, relaunch, disable }

    /// 重開後這段時間內又偵測到就不再重開
    static let relaunchCooldown: TimeInterval = 300
    /// 重開後這段時間內啟動，才說明剛才為什麼重開
    static let announceWindow: TimeInterval = 60
    /// 喚醒後這段時間內不試建：系統喚醒時本來就會暫停攔截，試建也可能暫時失敗
    static let wakeGrace: TimeInterval = 15

    static func recovery(trustedReported: Bool, lastRelaunch: Date?, now: Date, canRelaunch: Bool = true) -> Recovery {
        guard trustedReported else { return .waitForPermission }
        guard canRelaunch else { return .disable }
        guard let lastRelaunch else { return .relaunch }
        let elapsed = now.timeIntervalSince(lastRelaunch)
        // 時鐘被往回調（elapsed < 0）時當成很久以前
        return elapsed >= 0 && elapsed < relaunchCooldown ? .disable : .relaunch
    }

    /// 還在喚醒後的寬限期內時，回傳剩下的秒數
    static func wakeGraceLeft(lastWake: Date?, now: Date) -> TimeInterval? {
        guard let lastWake else { return nil }
        let left = wakeGrace - now.timeIntervalSince(lastWake)
        return left > 0 && left <= wakeGrace ? left : nil
    }

    static func shouldAnnounce(lastRelaunch: Date?, now: Date) -> Bool {
        guard let lastRelaunch else { return false }
        let elapsed = now.timeIntervalSince(lastRelaunch)
        return elapsed >= 0 && elapsed < announceWindow
    }
}
