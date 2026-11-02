/// ⌘Q／⌘W 防誤觸：要按住一段時間才結束 App 或關閉。按下時記住最前面的 App，
/// 按滿時間、而且最前面還是它，才交給 QuitGuardController 對那個 App 送出；中途放開、換 App、按別的鍵都取消。
/// 只做判斷，事件攔截與送出在 QuitGuardController
struct QuitGuard {
    enum Kind: Equatable { case quit, close }

    struct Hold: Equatable {
        let kind: Kind
        /// 按下時最前面的 App（pid）
        let app: Int32
        let began: Double
    }

    enum Event {
        /// switcherOpen：視窗切換器正開著（這時 Q／W 是切換器的動作）
        case keyDown(keyCode: Int, command: Bool, otherModifiers: Bool, isRepeat: Bool, time: Double, frontApp: Int32, switcherOpen: Bool = false)
        case keyUp(keyCode: Int)
        case commandReleased
    }

    enum Action: Equatable { case pass, swallow }

    static let quitKey = 12, closeKey = 13

    var holdQuit: Bool
    var holdClose: Bool
    /// 要按住幾秒
    var duration: Double

    private(set) var holding: Hold?
    /// 攔下了按下、放開時也要攔下的鍵（不讓 App 收到單獨的放開）
    private var swallowedDown = Set<Int>()

    init(holdQuit: Bool, holdClose: Bool, duration: Double) {
        self.holdQuit = holdQuit
        self.holdClose = holdClose
        self.duration = duration
    }

    private func kind(of keyCode: Int) -> Kind? {
        switch keyCode {
        case Self.quitKey where holdQuit: return .quit
        case Self.closeKey where holdClose: return .close
        default: return nil
        }
    }

    mutating func handle(_ event: Event) -> Action {
        switch event {
        case let .keyDown(keyCode, command, otherModifiers, isRepeat, time, frontApp, switcherOpen):
            // 切換器開著：Q／W 交給切換器（結束或關閉選到的那個），按住中的也取消
            if switcherOpen {
                holding = nil
                return .pass
            }
            // 攔下過、還沒放開的鍵自動重複送出：一律攔下。按住結束或取消後還按著時放行，會連續關分頁或結束換過去的 App
            if isRepeat, swallowedDown.contains(keyCode) { return .swallow }
            // 真正又按了一次：之前漏掉的放開不再算數
            if !isRepeat { swallowedDown.remove(keyCode) }
            if command, !otherModifiers, let kind = kind(of: keyCode) {
                // 按住中的自動重複或又按一次：維持原本的計時
                if let holding, holding.kind == kind { return .swallow }
                // 沒在按住時的自動重複（例如功能剛打開時已經按著）：不管
                if isRepeat { return .pass }
                holding = Hold(kind: kind, app: frontApp, began: time)
                swallowedDown.insert(keyCode)
                return .swallow
            }
            // 按住期間按了別的鍵：取消，那個鍵照常送出
            holding = nil
            return .pass
        case let .keyUp(keyCode):
            guard swallowedDown.remove(keyCode) != nil else { return .pass }
            // 提早放開：取消
            if let holding, kind(of: keyCode) == holding.kind { self.holding = nil }
            return .swallow
        case .commandReleased:
            holding = nil
            return .pass
        }
    }

    /// 放棄這次按住（例如攔截被系統暫停），但記得哪些鍵被攔下：放開時照樣攔下，App 不會收到單獨的放開
    mutating func cancelHold() { holding = nil }

    /// 0～1，畫面上的進度環用
    func progress(now: Double) -> Double {
        guard let holding, duration > 0 else { return 0 }
        return min(1, max(0, (now - holding.began) / duration))
    }

    /// 定時呼叫：按滿時間而且最前面還是同一個 App 時，回傳要送出的動作；最前面換了就取消
    mutating func complete(now: Double, frontApp: Int32) -> Hold? {
        guard let holding else { return nil }
        guard frontApp == holding.app else {
            self.holding = nil
            return nil
        }
        guard now - holding.began >= duration else { return nil }
        self.holding = nil
        return holding
    }
}
