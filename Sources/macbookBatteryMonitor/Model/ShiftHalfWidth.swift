/// 中文輸入法（例如內建注音）按住 Shift 打字會出現全形「Ａ」「！」「＜」。輸入法不切換，改把這些按鍵換成
/// 「不按 Shift、文字是半形字」的按鍵：輸入法沒在組字時會原樣放行，和英文鍵盤打出來的一樣。
/// 正在組字時輸入法會把任何按鍵吃掉，所以每次按住 Shift 的第一個字要先送出組字（InputSourceFix 做）。
/// 這裡只做判斷
struct ShiftHalfWidth {
    enum Event {
        case keyDown(keyCode: Int, shift: Bool, otherModifiers: Bool)
        case keyUp(keyCode: Int, shift: Bool)
        case shiftReleased
    }

    enum Action: Equatable {
        case pass
        /// 換成半形字；commitFirst：先送出正在組的字
        case halfWidth(commitFirst: Bool)
    }

    /// 美式鍵盤按 Shift 打出來的字，依虛擬按鍵碼。空白鍵不在裡面（注音用 Shift＋空白切換全半形）
    private static let shifted: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P",
        37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "!", 19: "@", 20: "#", 21: "$", 23: "%", 22: "^", 26: "&", 28: "*", 25: "(", 29: ")", 27: "_", 24: "+",
        50: "~", 33: "{", 30: "}", 42: "|", 41: ":", 39: "\"", 43: "<", 47: ">", 44: "?",
    ]

    static func halfWidthText(keyCode: Int) -> String? { shifted[keyCode] }

    /// 只對中文輸入法生效：不能直接打 ASCII、而且主要語言是中文。俄文、韓文、日文等鍵盤不處理
    static func isChineseInputMethod(languages: [String], asciiCapable: Bool) -> Bool {
        !asciiCapable && (languages.first?.hasPrefix("zh") ?? false)
    }

    /// 這次按住 Shift 已經轉換過（組字已送出）
    private(set) var holding = false

    /// imeActive：目前是中文輸入法（見 isChineseInputMethod）。按住期間不看它：送出組字時會短暫切到英文鍵盤
    mutating func handle(_ event: Event, imeActive: Bool) -> Action {
        switch event {
        case let .keyDown(keyCode, shift, otherModifiers):
            // 沒按 Shift：這次按住結束（也涵蓋漏掉放開 Shift 的事件）
            guard shift else {
                holding = false
                return .pass
            }
            guard imeActive || holding, !otherModifiers, Self.shifted[keyCode] != nil else { return .pass }
            defer { holding = true }
            return .halfWidth(commitFirst: !holding)
        case let .keyUp(keyCode, shift):
            return holding && shift && Self.shifted[keyCode] != nil ? .halfWidth(commitFirst: false) : .pass
        case .shiftReleased:
            holding = false
            return .pass
        }
    }
}
