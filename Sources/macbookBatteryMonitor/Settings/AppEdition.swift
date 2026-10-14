import Foundation

/// 打包時寫進 Info.plist 的 MBMEdition。
/// v1.7.1 起只有一個 App（Apple 晶片與 Intel 通用），系統監控改成可在設定開關，第一次啟動時詢問。
/// 發布時仍附上舊檔名的 battery／status zip，讓 v1.5.0～v1.6.1 的一鍵更新找得到檔案（舊版會檢查 MBMEdition）；
/// 從舊版升級的使用者依原本的版本別決定系統監控預設開或關，不再詢問
enum AppEdition: String {
    case battery
    case status
    case universal
    /// 舊系統版本（macOS 12、13）
    case legacy

    /// 直接執行未打包的執行檔（開發時）視為通用版
    static let current: AppEdition = {
        (Bundle.main.object(forInfoDictionaryKey: "MBMEdition") as? String).flatMap(AppEdition.init(rawValue:)) ?? .universal
    }()

    /// App 名稱（與 build.sh 寫進各語言 InfoPlist.strings 的繁體中文名稱相同）
    static let appName = "電池與系統監控"
}
