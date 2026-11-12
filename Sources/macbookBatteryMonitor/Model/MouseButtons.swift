import CoreGraphics

/// 滑鼠側鍵：第 4、5 鍵（拇指那兩顆，按鈕編號 3、4）換成上一頁、下一頁或 Mission Control。
/// 只做判斷，攔截與送出按鍵在 MouseButtonsController
struct MouseButtons: Equatable {
    enum Action: String, CaseIterable {
        case none, back, forward, missionControl

        init(stored: String?) { self = stored.flatMap(Self.init(rawValue:)) ?? .none }

        var title: String {
            switch self {
            case .none: return "不處理"
            case .back: return "上一頁（⌘[）"
            case .forward: return "下一頁（⌘]）"
            case .missionControl: return "Mission Control"
            }
        }

        var shortcut: Shortcut? {
            switch self {
            case .none: return nil
            case .back: return Shortcut(keyCode: 33, command: true, control: false)
            case .forward: return Shortcut(keyCode: 30, command: true, control: false)
            case .missionControl: return Shortcut(keyCode: 126, command: false, control: true)
            }
        }
    }

    struct Shortcut: Equatable {
        let keyCode: Int
        let command: Bool
        let control: Bool
    }

    /// 第 4 鍵（通常是「後退」那顆）與第 5 鍵
    var back: Action
    var forward: Action

    var isActive: Bool { back != .none || forward != .none }

    struct Window: Equatable {
        let pid: Int32
        /// 0 是一般視窗；選單列、Dock 等是更上層
        let layer: Int
        let bounds: CGRect
    }

    /// 游標下最上面的一般視窗屬於最前面的 App。windows 由前到後排；送出的快捷鍵會到最前面的 App，
    /// 游標停在別的 App（例如背景的瀏覽器）時不轉換，免得 ⌘[ 跑去編輯器裡縮排
    static func pointerOverFrontApp(_ point: CGPoint, windows: [Window], front: Int32) -> Bool {
        windows.first { $0.layer == 0 && $0.bounds.contains(point) }?.pid == front
    }

    /// 要接手的按鈕回傳動作；不處理的按鈕回傳 nil，事件照常交給 App
    func action(forButton number: Int) -> Action? {
        let action: Action
        switch number {
        case 3: action = back
        case 4: action = forward
        default: return nil
        }
        return action == .none ? nil : action
    }
}
