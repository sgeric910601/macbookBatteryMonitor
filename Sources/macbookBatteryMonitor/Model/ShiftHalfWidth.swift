/// 中文輸入法（例如內建注音）按住 Shift 打字母會打出全形英文「Ａ」。這裡決定什麼時候暫時切到英文鍵盤：
/// 按住 Shift 打第一個字母時切過去（這個字母就打成半形），放開 Shift 時切回原本的輸入法。
/// 只做判斷，切換與事件攔截在 InputSourceFix
struct ShiftHalfWidth {
    enum Event {
        case keyDown(keyCode: Int, shift: Bool, otherModifiers: Bool)
        case shiftReleased
    }

    enum Action: Equatable { case pass, switchToASCII, restore }

    /// 美式鍵盤 A～Z 的虛擬按鍵碼（Shift + 這些鍵才處理；數字與標點不動）
    static let letterKeyCodes: Set<Int> = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17,
                                           31, 32, 34, 35, 37, 38, 40, 45, 46]

    /// 已經暫時切到英文鍵盤，放開 Shift 時要切回去
    private(set) var switched = false

    /// imeActive：目前的輸入法不是英文鍵盤（不能直接打 ASCII，例如注音、拼音、日文）
    mutating func handle(_ event: Event, imeActive: Bool) -> Action {
        switch event {
        case let .keyDown(keyCode, shift, otherModifiers):
            // 保險：漏掉放開 Shift 的事件（例如攔截剛好被系統暫停）時，不按 Shift 的下一個鍵就切回去，不會一直卡在英文
            if switched, !shift {
                switched = false
                return .restore
            }
            guard !switched, imeActive, shift, !otherModifiers, Self.letterKeyCodes.contains(keyCode) else { return .pass }
            switched = true
            return .switchToASCII
        case .shiftReleased:
            guard switched else { return .pass }
            switched = false
            return .restore
        }
    }
}
