import Foundation

public enum CPUHelperConstants {
    public static let label = "com.kuan.batterymonitor.cpu"
    public static let directory = "/Library/PrivilegedHelperTools/com.kuan.batterymonitor.cpu"
    public static let executable = directory + "/CPUPowerHelper"
    public static let configuration = directory + "/config.json"
    /// 目前排定的智慧充電喚醒時間（服務自己寫，用來取消；不接受客戶端給的路徑）
    public static let chargingWakeRecord = directory + "/charging-wake"
    /// 智慧充電喚醒事件的固定識別碼（`pmset -g sched` 會顯示）
    public static let chargingWakeIdentifier = "com.kuan.batterymonitor.charging"
    public static let launchDaemon = "/Library/LaunchDaemons/" + label + ".plist"
    /// 通訊協定改變時加一；舊版服務會被視為未安裝，需要重新授權。
    /// 智慧充電喚醒是額外加的功能，不改版本號：舊服務照樣提供 CPU 取樣，要用喚醒時才重新安裝（見 chargingWake）
    public static let version = 3
    /// 沒有任何取樣租約多久後服務自行結束（launchd 會在下次連線時再啟動）
    public static let idleExit: TimeInterval = 30

    /// 只接受與 App 更新頻率相同的 1、2、5、10 秒；其他值取不超過它的最近一檔
    public static let samplingIntervals = [1, 2, 5, 10]
    public static func samplingInterval(_ requested: Int) -> Int { samplingIntervals.last { $0 <= requested } ?? 1 }

    /// 取樣租約的有效時間：至少 5 秒，且要比兩次要求的間隔長，App 每次更新續約
    public static func leaseDuration(interval: Int) -> TimeInterval { TimeInterval(max(5, samplingInterval(interval) * 2 + 1)) }
}

/// 智慧充電喚醒的限制：服務只接受一個時間，識別碼固定，只能排在 1 分鐘後到 7 天內；
/// App 端估算有小幅變動時不必每次重排
public enum ChargingWakePolicy {
    public static let earliest: TimeInterval = 60
    public static let latest: TimeInterval = 7 * 24 * 3600
    /// 與目前排定的時間相差超過這麼多才重排
    public static let replaceThreshold: TimeInterval = 5 * 60

    public static func isAllowed(_ epoch: TimeInterval, now: Date) -> Bool {
        guard epoch.isFinite else { return false }
        let interval = epoch - now.timeIntervalSince1970
        return interval >= earliest && interval <= latest
    }

    public static func shouldReplace(existing: Date?, with candidate: Date) -> Bool {
        guard let existing else { return true }
        return abs(candidate.timeIntervalSince(existing)) >= replaceThreshold
    }

    /// 管理員 CPU 取樣與智慧充電喚醒共用同一個服務：兩個都關掉才移除
    public static func keepsHelper(cpuSampling: Bool, chargingWake: Bool) -> Bool { cpuSampling || chargingWake }
}

public struct CPUHelperConfiguration: Codable {
    public let uid: UInt32
    public let version: Int
    /// 這個服務能排定智慧充電喚醒（v1.7.0 起安裝的服務；舊服務的設定沒有這個值）
    public let chargingWake: Bool?
    public init(uid: UInt32) { self.uid = uid; version = CPUHelperConstants.version; chargingWake = true }
}

public struct CPUHelperReply: Codable {
    public let version: Int
    public let reading: CPUPowerReading?
    public let error: String?
    public init(reading: CPUPowerReading?, error: String? = nil) {
        version = CPUHelperConstants.version
        self.reading = reading
        self.error = error
    }
}

/// 不接受指令、路徑或 PID；取樣間隔只能是 1、2、5、10 秒。高權限工作只有固定的 CPU 功耗讀取，
/// 以及一個固定識別碼、限定時間範圍的智慧充電喚醒事件
@objc public protocol CPUHelperProtocol {
    func sample(active: Bool, interval: Int, withReply reply: @escaping (Data) -> Void)
    /// 排定（或改排）智慧充電喚醒；epoch 是 1970 年起的秒數。成功回傳 nil，否則回傳原因
    func scheduleChargingWake(at epoch: Double, withReply reply: @escaping (String?) -> Void)
    func cancelChargingWake(withReply reply: @escaping (String?) -> Void)
    func uninstall(withReply reply: @escaping (String?) -> Void)
}
