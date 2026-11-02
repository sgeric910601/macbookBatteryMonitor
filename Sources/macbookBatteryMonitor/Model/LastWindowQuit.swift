/// 關閉最後一個視窗時自動結束 App。寧可不結束也不要誤結束，所以條件都要成立：
/// 之前看過它有視窗；跨所有 Space 的 WindowServer 查詢與「輔助使用」都說沒有視窗了；不是 Finder、不在例外清單、沒被隱藏；
/// 已經啟動完成而且執行超過 minimumRunTime（有啟動畫面的 App 關掉啟動畫面後，主視窗可能過好幾秒才出現）。
/// 只做判斷，監聽與結束在 LastWindowQuitController
struct LastWindowQuit {
    /// 一律不自動結束：Finder 沒有視窗時仍然要管桌面；通話與會議 App 在通話中、接聽來電的瞬間可能沒有視窗，結束會掛斷通話；
    /// 虛擬機器的視窗常常辨識不到，結束等於把虛擬機器關機
    static let alwaysExcluded: Set<String> = [
        "com.apple.finder", "com.apple.FaceTime", "com.apple.mobilephone",
        "us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2", "com.tinyspeck.slackmacgap", "com.hnc.Discord",
        "Cisco-Systems.Spark", "com.webex.meetingmanager", "com.skype.skype", "jp.naver.line.mac",
        "com.parallels.desktop.console", "com.vmware.fusion", "com.utmapp.UTM",
    ]
    static let minimumRunTime: Double = 10

    /// 每個 App 上次看到的視窗數
    private var windowCounts: [Int32: Int] = [:]

    mutating func saw(pid: Int32, windows: Int) { windowCounts[pid] = windows }

    mutating func forget(pid: Int32) { windowCounts[pid] = nil }

    /// isRegularApp：目前是一般 App（在 Dock 上）；背景 App（例如只有設定視窗的選單列工具）不結束。要在當下讀，不能只看 Info.plist。
    /// runningFor：啟動完成後執行了幾秒，還沒啟動完成或不知道時傳 nil
    func shouldQuit(pid: Int32, bundleID: String?, serverWindows: Int, axWindows: Int, excluded: Set<String>, isHidden: Bool,
                    isRegularApp: Bool, runningFor: Double?) -> Bool {
        guard let bundleID, !Self.alwaysExcluded.contains(bundleID), !excluded.contains(bundleID), !isHidden, isRegularApp else { return false }
        guard let runningFor, runningFor >= Self.minimumRunTime else { return false }
        guard (windowCounts[pid] ?? 0) > 0 else { return false }
        return serverWindows == 0 && axWindows == 0
    }
}
