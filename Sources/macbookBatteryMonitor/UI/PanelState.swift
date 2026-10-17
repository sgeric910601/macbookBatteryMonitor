import Combine
import SwiftUI

enum PowerFlowLevel { case overview, components, chip }

enum PanelPage {
    case main
    /// 智慧充電（點主面板資訊卡最上方那一列）；設定視窗的「充電」也有一份
    case chargingPlan
}

enum BottomTab: String, CaseIterable {
    case details = "詳細資訊"
    case history = "電量歷史"
    case processes = "耗電排行"
    case peripherals = "周邊設備"
    case today = "今日"

    /// 桌上型 Mac 沒有電量，歷史分頁改叫「耗電歷史」
    func title(desktop: Bool) -> String {
        desktop && self == .history ? "耗電歷史" : rawValue
    }

    /// 桌上型 Mac 沒有電量，沒有「今日」回顧
    static func tabs(desktop: Bool) -> [BottomTab] {
        desktop ? allCases.filter { $0 != .today } : allCases
    }
}

enum HistoryRange: String, CaseIterable, Identifiable {
    case hour = "1 小時"
    case day = "24 小時"
    case week = "7 天"

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .hour: return 3600
        case .day: return 24 * 3600
        case .week: return 7 * 24 * 3600
        }
    }
}

/// 面板的介面狀態。
/// 只裝 Command Line Tools 時沒有 SwiftUI 的 macro 外掛，不能用 @State，所以集中放在這裡。
@MainActor
final class PanelState: ObservableObject {
    /// 面板關閉時設為 false，畫面會換成空白，不再監聽任何資料
    @Published var isVisible = false
    @Published var powerFlowLevel: PowerFlowLevel = .overview
    @Published var page: PanelPage = .main
    @Published var tab: BottomTab = .details
    @Published var historyRange: HistoryRange = .day
    /// 智慧充電頁等可捲動頁面量到的內容高度，下次打開直接用，面板不必先撐到最高再縮回來
    @Published var pageHeights: [PanelPage: CGFloat] = [:]
    /// macOS 關閉了這個 App 的通知（設定視窗打開時檢查）
    @Published var notificationsBlocked = false
    /// 設定視窗左邊選的分類
    @Published var settingsSection: SettingsSection = .general
    /// 打開設定視窗（由 AppDelegate 提供）；nil 時維持上次的分類
    var openSettings: (SettingsSection?) -> Void = { _ in }
    /// 有沒有「輔助使用」權限（分開設定捲動方向要用）
    @Published var scrollTrusted = false
    /// 智慧充電頁的輸入：指定完成時間、每週排程的星期與時間
    @Published var chargingCustomDeadline = Date().addingTimeInterval(4 * 3600)
    @Published var chargingWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    @Published var chargingWeeklyTime = Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
    /// 設定 → 更新：按了「安裝 Beta…」，等使用者再確認一次
    @Published var confirmingBetaInstall = false
    @Published var loginStatus: LoginItem.Status = .disabled
    @Published var loginError: String?

    func binding<T>(_ keyPath: ReferenceWritableKeyPath<PanelState, T>) -> Binding<T> {
        Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0 })
    }
}
