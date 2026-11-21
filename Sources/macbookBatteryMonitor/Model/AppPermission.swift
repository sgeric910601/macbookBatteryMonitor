import Foundation

/// 設定 →「權限」列出的系統權限：哪些功能用到、系統設定在哪裡（狀態由 PermissionsView 讀取）
enum AppPermission: CaseIterable, Identifiable {
    case accessibility
    case screenRecording
    case notifications
    case bluetooth
    case automation
    case audioCapture

    var id: Self { self }

    var title: String {
        switch self {
        case .accessibility: return "輔助使用"
        case .screenRecording: return "螢幕錄製"
        case .notifications: return "通知"
        case .bluetooth: return "藍牙"
        case .automation: return "自動化（System Events）"
        case .audioCapture: return "系統錄音（只錄聲音）"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: return "accessibility"
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .notifications: return "bell"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .automation: return "gearshape.2"
        case .audioCapture: return "waveform"
        }
    }

    /// 用到這個權限的功能；空的代表目前沒有加入需要它的功能
    func users(isInstalled: (ExtensionFeature) -> Bool) -> [String] {
        switch self {
        case .accessibility: return ExtensionFeature.allCases.filter { $0.needsAccessibility && isInstalled($0) }.map(\.title)
        case .screenRecording: return isInstalled(.windowSwitcher) ? ["視窗切換的縮圖（選用）"] : []
        case .notifications: return ["電量提醒", "監控警示", "新版本通知"]
        case .bluetooth: return ["周邊設備電量"]
        case .automation: return isInstalled(.startupItems) ? ["登入項目的「登入時打開」"] : []
        case .audioCapture: return isInstalled(.appVolume) ? ["各 App 音量"] : []
        }
    }

    var settingsURL: URL {
        let pane: String
        switch self {
        case .accessibility: pane = "com.apple.preference.security?Privacy_Accessibility"
        case .screenRecording: pane = "com.apple.preference.security?Privacy_ScreenCapture"
        case .notifications: pane = "com.apple.Notifications-Settings.extension"
        case .bluetooth: pane = "com.apple.preference.security?Privacy_Bluetooth"
        case .automation: pane = "com.apple.preference.security?Privacy_Automation"
        case .audioCapture: pane = "com.apple.preference.security?Privacy_AudioCapture"
        }
        return URL(string: "x-apple.systempreferences:" + pane)!
    }
}
