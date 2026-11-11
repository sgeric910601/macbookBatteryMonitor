import CoreGraphics

/// 點 Dock 圖示縮到 Dock：只監聽、不攔截滑鼠，Dock 原本的點擊與拖曳都照常。
/// 只有點的是按下時最前面那個 App、它有開著的視窗、而且不是拖曳或長按時才動作。再點一次時叫回上次縮下去的所有視窗
/// （很多 App 自己不會叫回）；使用者自己縮的不動。
/// 按下時判斷（Dock 還沒動作），放開時執行；做法參考 braenden/dock-minimize（MIT，只參考行為）。
/// 只做判斷，監聽與執行在 DockClickController
enum DockClick {
    enum Mode: String, CaseIterable { case minimize, hide }
    enum Action: Equatable { case none, minimize, hide, restore }

    /// 按下到放開移動超過這麼多點就算拖曳
    static let maxClickDistance = 5.0

    /// clickedApp：點到的 Dock 項目是哪個 App（不是 App 圖示時為 nil）；minimizedByUs：上次是我們把它的視窗縮下去、還沒叫回
    static func decide(frontAppAtMouseDown: Int32?, clickedApp: Int32?, hadVisibleWindows: Bool, dragDistance: Double,
                       mode: Mode, minimizedByUs: Bool) -> Action {
        guard let front = frontAppAtMouseDown, let clickedApp, clickedApp == front, dragDistance <= maxClickDistance else { return .none }
        if hadVisibleWindows { return mode == .minimize ? .minimize : .hide }
        return minimizedByUs ? .restore : .none
    }

    /// 某個時間點最前面的 App。監聽只收不擋，回呼跑到時 Dock 可能已經切換 App，不能讀「現在」的前景 App：
    /// 用切換紀錄（依時間排序）找出按下那一刻以前最後一次切換到的 App；紀錄都比按下晚時為 nil
    static func frontApp(at time: Double, history: [(pid: Int32, time: Double)]) -> Int32? {
        history.last { $0.time <= time }?.pid
    }

    /// WindowServer 列出的一個畫面上的視窗（CGWindowList，不問 App，不會等）
    struct ScreenWindow: Equatable {
        var pid: Int32
        var id: UInt32
        var layer: Int
        var alpha: Double
        var size: CGSize
    }

    /// 有些 App 在畫面上留著看不見的小輔助視窗，不算
    static let minWindowSide: CGFloat = 40

    /// 按下那一刻這個 App 在目前桌面上有沒有開著的一般視窗。Dock 在放開時才讓 App 叫回視窗，按下時讀到的就是點擊前的狀態；
    /// excluding 是我們縮下去、還沒叫回的視窗：回呼晚跑時 Dock 可能已經叫回其中一個，不能把它當成開著的視窗又縮下去
    static func hasVisibleWindow(_ windows: [ScreenWindow], pid: Int32, excluding: Set<UInt32>) -> Bool {
        windows.contains {
            $0.pid == pid && $0.layer == 0 && $0.alpha > 0 && !excluding.contains($0.id)
                && $0.size.width > minWindowSide && $0.size.height > minWindowSide
        }
    }
}
