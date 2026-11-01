import Foundation

/// 擴充功能：設定側邊欄「擴充功能」組裡可以加入或移除的功能。
/// 電池、充電、系統監控、充電夥伴、周邊設備是基本功能，不在這裡、不能移除。
/// 沒加入的功能不會啟動，設定裡也看不到；移除只改加入狀態，重新加入時原本的設定都還在。
/// 原始值是存在設定裡的鍵，只能新增、不能改名
enum ExtensionFeature: String, CaseIterable, Identifiable {
    case scrollDirection
    case windowSwitcher
    case inputMethod

    var id: String { rawValue }

    var installedKey: String { "feature.\(rawValue).installed" }

    var title: String {
        switch self {
        case .scrollDirection: return "捲動方向"
        case .windowSwitcher: return "視窗切換"
        case .inputMethod: return "中文輸入法"
        }
    }

    var symbol: String {
        switch self {
        case .scrollDirection: return "arrow.up.arrow.down"
        case .windowSwitcher: return "macwindow.on.rectangle"
        case .inputMethod: return "keyboard"
        }
    }

    /// 「功能管理」頁的分組
    var group: String {
        switch self {
        case .scrollDirection: return "滑鼠與鍵盤"
        case .windowSwitcher: return "視窗與 Dock"
        case .inputMethod: return "滑鼠與鍵盤"
        }
    }

    /// 加入後在背景做什麼，標在名稱旁邊，讓人知道它會監聽哪種輸入
    var badge: String {
        switch self {
        case .scrollDirection: return "監聽滑鼠捲動"
        case .windowSwitcher: return "監聽鍵盤"
        case .inputMethod: return "監聽鍵盤"
        }
    }

    var detail: String {
        switch self {
        case .scrollDirection: return "滑鼠與觸控板分開設定捲動方向"
        case .windowSwitcher: return "用視窗切換取代 Cmd+Tab"
        case .inputMethod: return "Caps Lock 切換中英不延遲、按住 Shift 打半形英文與符號"
        }
    }

    /// 沒存過加入狀態（從還沒有擴充功能的舊版更新）時：捲動方向，以及開關已經打開過的功能（switchedOn）視為已加入，
    /// 更新不會讓它消失；沒用過的新功能不會自己出現，要到「功能管理」加入
    func isInstalled(stored: Bool?, switchedOn: Bool) -> Bool { stored ?? (self == .scrollDirection || switchedOn) }

    /// 全新安裝第一次啟動時寫入：擴充功能都要「輔助使用」權限，一開始都不加入，免得一裝好就看到權限要求
    static var freshInstallChoices: [String: Bool] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.installedKey, false) })
    }
}
