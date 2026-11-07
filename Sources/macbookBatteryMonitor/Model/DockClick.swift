/// 點 Dock 圖示縮到 Dock：只監聽、不攔截滑鼠，Dock 原本的點擊與拖曳都照常。
/// 只有點的是按下時最前面那個 App、它有開著的視窗、而且不是拖曳時才動作。再點一次時叫回上次縮下去的視窗
/// （很多 App 自己不會叫回）；使用者自己縮的不動。
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

    /// 點擊當下的視窗狀態。讀到的是按下後的狀態，Dock 可能已經把縮下去的視窗叫回來；
    /// 按下之後才收到「視窗叫回」就是 Dock 這一下叫回的，代表按下那一刻沒有開著的視窗，我們縮下去的也還沒被叫回
    static func stateAtClick(visibleNow: Bool, oursMinimizedNow: Bool, hasOurs: Bool,
                             restoredAfterClick: Bool) -> (visible: Bool, minimizedByUs: Bool) {
        guard restoredAfterClick else { return (visibleNow, oursMinimizedNow) }
        return (false, hasOurs)
    }
}
