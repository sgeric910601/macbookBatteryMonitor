import Foundation

/// 擴充功能：設定側邊欄「擴充功能」組裡可以加入或移除的功能。
/// 電池、充電、系統監控、充電夥伴、周邊設備是基本功能，不在這裡、不能移除。
/// 沒加入的功能不會啟動，設定裡也看不到；移除只改加入狀態，重新加入時原本的設定都還在。
/// 原始值是存在設定裡的鍵，只能新增、不能改名
enum ExtensionFeature: String, CaseIterable, Identifiable {
    case scrollDirection
    case windowSwitcher
    case inputMethod
    case quitGuard
    case lastWindowQuit
    case dockClick
    case keyboardCleaning
    case mouseButtons
    case audioSwitch
    case greenButton
    case windowSnap
    case finderKeys
    case quickMenu
    case portManager
    case clipboardHistory
    case xdrBrightness

    var id: String { rawValue }

    var installedKey: String { "feature.\(rawValue).installed" }

    var title: String {
        switch self {
        case .scrollDirection: return "捲動方向"
        case .windowSwitcher: return "視窗切換"
        case .inputMethod: return "中文輸入法"
        case .quitGuard: return "⌘Q／⌘W 防誤觸"
        case .lastWindowQuit: return "關閉最後視窗時結束 App"
        case .dockClick: return "點 Dock 圖示縮到 Dock"
        case .keyboardCleaning: return "鍵盤清潔模式"
        case .mouseButtons: return "滑鼠側鍵"
        case .audioSwitch: return "音訊切換"
        case .greenButton: return "綠色按鈕放大"
        case .windowSnap: return "視窗吸附"
        case .finderKeys: return "Finder 加強"
        case .quickMenu: return "貓咪快捷選單"
        case .portManager: return "Port 管理與結束程式"
        case .clipboardHistory: return "剪貼簿歷史"
        case .xdrBrightness: return "XDR 額外增亮"
        }
    }

    var symbol: String {
        switch self {
        case .scrollDirection: return "arrow.up.arrow.down"
        case .windowSwitcher: return "macwindow.on.rectangle"
        case .inputMethod: return "keyboard"
        case .quitGuard: return "hand.raised"
        case .lastWindowQuit: return "xmark.app"
        case .dockClick: return "dock.arrow.down.rectangle"
        case .keyboardCleaning: return "sparkles"
        case .mouseButtons: return "computermouse"
        case .audioSwitch: return "speaker.wave.2"
        case .greenButton: return "arrow.up.left.and.arrow.down.right"
        case .windowSnap: return "rectangle.split.2x1"
        case .finderKeys: return "folder"
        case .quickMenu: return "cat"
        case .portManager: return "point.3.connected.trianglepath.dotted"
        case .clipboardHistory: return "doc.on.clipboard"
        case .xdrBrightness: return "sun.max.fill"
        }
    }

    /// 「功能管理」頁的分組
    var group: String {
        switch self {
        case .scrollDirection: return "滑鼠與鍵盤"
        case .windowSwitcher: return "視窗與 Dock"
        case .inputMethod: return "滑鼠與鍵盤"
        case .quitGuard: return "滑鼠與鍵盤"
        case .lastWindowQuit: return "視窗與 Dock"
        case .dockClick: return "視窗與 Dock"
        case .keyboardCleaning: return "滑鼠與鍵盤"
        case .mouseButtons: return "滑鼠與鍵盤"
        case .audioSwitch: return "聲音"
        case .greenButton: return "視窗與 Dock"
        case .windowSnap: return "視窗與 Dock"
        case .finderKeys: return "視窗與 Dock"
        case .quickMenu: return "選單列"
        case .portManager: return "系統監控"
        case .clipboardHistory: return "選單列"
        case .xdrBrightness: return "系統監控"
        }
    }

    /// 加入後在背景做什麼，標在名稱旁邊，讓人知道它會監聽哪種輸入
    var badge: String {
        switch self {
        case .scrollDirection: return "監聽滑鼠捲動"
        case .windowSwitcher: return "監聽鍵盤"
        case .inputMethod: return "監聽鍵盤"
        case .quitGuard: return "監聽鍵盤"
        case .lastWindowQuit: return "監聽視窗"
        case .dockClick: return "監聽滑鼠點擊"
        case .keyboardCleaning: return "清潔時攔截鍵盤"
        case .mouseButtons: return "監聽滑鼠側鍵"
        case .audioSwitch: return "不需要權限"
        case .greenButton: return "監聽滑鼠點擊"
        case .windowSnap: return "監聽滑鼠拖曳"
        case .finderKeys: return "監聽鍵盤"
        case .quickMenu: return "不需要權限"
        case .portManager: return "不需要權限"
        case .clipboardHistory: return "每 0.75 秒看剪貼簿"
        case .xdrBrightness: return "監聽亮度鍵"
        }
    }

    var detail: String {
        switch self {
        case .scrollDirection: return "滑鼠與觸控板分開設定捲動方向"
        case .windowSwitcher: return "用視窗切換取代 Cmd+Tab"
        case .inputMethod: return "Caps Lock 切換中英不延遲、按住 Shift 打半形英文與符號"
        case .quitGuard: return "要按住 ⌘Q 或 ⌘W 一下子才結束 App 或關閉，避免誤按"
        case .lastWindowQuit: return "App 最後一個視窗關掉時自動結束它，可以設定例外"
        case .dockClick: return "點目前 App 的 Dock 圖示，把它的視窗縮到 Dock 或隱藏，再點一次叫回來"
        case .keyboardCleaning: return "暫時停用鍵盤，方便擦鍵盤；時間到或點「結束清潔」就恢復"
        case .mouseButtons: return "多按鍵滑鼠的第 4、5 鍵換成上一頁、下一頁或 Mission Control"
        case .audioSwitch: return "面板上切換音訊輸出裝置、一鍵把麥克風靜音"
        case .greenButton: return "點視窗的綠色按鈕改成填滿螢幕（不進全螢幕），再按一次還原"
        case .windowSnap: return "把視窗拖到螢幕邊緣或角落，放開後排成半邊、填滿或四分之一"
        case .finderKeys: return "在 Finder 用 ⌘X、⌘V 剪下搬移檔案，按 F2 重新命名"
        case .quickMenu: return "選單列多一個貓咪圖示，點開直接操作防止休眠、麥克風、鍵盤清潔、音訊輸出與剪貼簿歷史"
        case .portManager: return "網路面板列出監聽中的連接埠，可以結束對應的程式；CPU、記憶體清單可以右鍵結束 App"
        case .clipboardHistory: return "記住最近 30 筆複製的文字（只在記憶體、不記密碼工具標成機密的內容），從貓咪快捷選單選回來（要一起啟用貓咪快捷選單）"
        case .xdrBrightness: return "讓內建 XDR 螢幕額外增亮，亮度鍵到頂後可自動啟用；會增加耗電"
        }
    }

    /// 需要「輔助使用」權限（權限頁依這個列出用到的功能）
    var needsAccessibility: Bool {
        switch self {
        case .audioSwitch, .quickMenu, .portManager, .clipboardHistory: return false
        default: return true
        }
    }

    /// 沒存過加入狀態（從還沒有擴充功能的舊版更新）時：捲動方向，以及開關已經打開過的功能（switchedOn）視為已加入，
    /// 更新不會讓它消失；沒用過的新功能不會自己出現，要到「功能管理」加入
    func isInstalled(stored: Bool?, switchedOn: Bool) -> Bool { stored ?? (self == .scrollDirection || switchedOn) }

    /// 每個功能實際的加入狀態，寫進匯出的設定：沒存過、靠規則算出來的也寫出來
    static func installedValues(_ isInstalled: (ExtensionFeature) -> Bool) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.installedKey, isInstalled($0)) })
    }

    /// 全新安裝第一次啟動時寫入：擴充功能一開始都不加入，免得一裝好就看到權限要求或多出按鈕
    static var freshInstallChoices: [String: Bool] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.installedKey, false) })
    }
}
