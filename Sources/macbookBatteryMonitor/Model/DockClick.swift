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

    /// 實際用的收法。開著幕前調度時，系統會把「縮到 Dock」的視窗放進左邊的縮圖列而不是 Dock，
    /// 而且「輔助使用」照樣回報沒縮小：再點一次會被當成視窗還開著、又縮一次，叫不回來。這時一律改成隱藏 App，
    /// 再點一次由 Dock 照原本的方式取消隱藏
    static func effectiveMode(_ mode: Mode, stageManager: Bool) -> Mode {
        stageManager ? .hide : mode
    }

    /// 隱藏後過一陣子（reopenGrace）再看一次：放開時 Dock 讓 App「重新打開」，回應慢的 App 會在我們隱藏之後才回到前面，這時再隱藏一次。
    /// mode：這次點擊實際用的收法（effectiveMode）；hidden：那時讀到 App 是不是隱藏中（問不到為 nil），
    /// 要問「輔助使用」、App 沒回應時會等，所以其他條件都成立才問；
    /// clickedAgain：隱藏之後使用者又按下過（可能就是要叫回）；doubleClick：這一下是雙擊的第一下（雙擊不算收起）
    static func hideAgain(mode: Mode, hidden: @autoclosure () -> Bool?, clickedAgain: Bool, doubleClick: Bool) -> Bool {
        mode == .hide && !clickedAgain && !doubleClick && hidden() == false
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
