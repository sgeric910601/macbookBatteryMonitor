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
}
