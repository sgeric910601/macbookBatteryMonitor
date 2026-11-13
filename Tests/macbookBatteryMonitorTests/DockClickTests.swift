import Foundation

struct DockClickTests {
    private func decide(frontAtDown: Int32? = 7, item: Int32? = 7, visibleWindows: Bool = true, moved: Double = 0,
                        action: DockClick.Mode = .minimize, weMinimized: Bool = false) -> DockClick.Action {
        DockClick.decide(frontAppAtMouseDown: frontAtDown, clickedApp: item, hadVisibleWindows: visibleWindows, dragDistance: moved,
                         mode: action, minimizedByUs: weMinimized)
    }

    /// 點最前面那個 App 的 Dock 圖示、它有開著的視窗：縮到 Dock（或隱藏）
    func testClickOnFrontAppMinimizes() {
        XCTAssertEqual(decide(), .minimize)
        XCTAssertEqual(decide(action: .hide), .hide)
    }

    /// 開著幕前調度時縮下去的視窗會進左邊的縮圖列、再點也叫不回來：不管設定是哪一種都改成隱藏；關著時照設定
    func testStageManagerHidesInstead() {
        XCTAssertEqual(DockClick.effectiveMode(.minimize, stageManager: true), .hide)
        XCTAssertEqual(DockClick.effectiveMode(.hide, stageManager: true), .hide)
        XCTAssertEqual(DockClick.effectiveMode(.minimize, stageManager: false), .minimize)
        XCTAssertEqual(DockClick.effectiveMode(.hide, stageManager: false), .hide)
        XCTAssertEqual(decide(action: DockClick.effectiveMode(.minimize, stageManager: true)), .hide)
        // 視窗都收起來了：隱藏不靠我們叫回（Dock 會取消隱藏），只有我們縮下去的才叫回
        XCTAssertEqual(decide(visibleWindows: false, action: DockClick.effectiveMode(.minimize, stageManager: true)), .none)
        // 沒開幕前調度時縮下去的，之後才打開幕前調度：再點一次照樣叫回
        XCTAssertEqual(decide(visibleWindows: false, action: DockClick.effectiveMode(.minimize, stageManager: true), weMinimized: true),
                       .restore)
    }

    /// 隱藏後被晚到的「重新打開」叫回：使用者沒再點才再隱藏一次
    func testHideAgainOnlyWhenBroughtBack() {
        let stageManager = DockClick.effectiveMode(.minimize, stageManager: true)
        // 開著幕前調度、App 又出現、沒再點：再隱藏
        XCTAssertTrue(DockClick.hideAgain(mode: stageManager, hidden: false, clickedAgain: false, doubleClick: false))
        // 使用者又點了一下（可能就是要叫回）：不再隱藏
        XCTAssertTrue(!DockClick.hideAgain(mode: stageManager, hidden: false, clickedAgain: true, doubleClick: false))
        // 還隱藏著、或問不到：不用再隱藏
        XCTAssertTrue(!DockClick.hideAgain(mode: stageManager, hidden: true, clickedAgain: false, doubleClick: false))
        XCTAssertTrue(!DockClick.hideAgain(mode: stageManager, hidden: nil, clickedAgain: false, doubleClick: false))
        // 雙擊不算收起：不再隱藏
        XCTAssertTrue(!DockClick.hideAgain(mode: stageManager, hidden: false, clickedAgain: false, doubleClick: true))
        XCTAssertTrue(!DockClick.hideAgain(mode: stageManager, hidden: false, clickedAgain: true, doubleClick: true))
        // 沒開幕前調度、設定是縮到 Dock：走原本的縮小，從不隱藏
        let minimize = DockClick.effectiveMode(.minimize, stageManager: false)
        XCTAssertTrue(!DockClick.hideAgain(mode: minimize, hidden: false, clickedAgain: false, doubleClick: false))
        // 沒開幕前調度、設定是隱藏 App：和開著時一樣會再隱藏
        XCTAssertTrue(DockClick.hideAgain(mode: DockClick.effectiveMode(.hide, stageManager: false), hidden: false,
                                          clickedAgain: false, doubleClick: false))
        // 又點了或雙擊時不去問 App 是不是隱藏中（App 沒回應時會等）
        var asked = 0
        func hidden() -> Bool? {
            asked += 1
            return false
        }
        XCTAssertTrue(!DockClick.hideAgain(mode: stageManager, hidden: hidden(), clickedAgain: true, doubleClick: false))
        XCTAssertTrue(!DockClick.hideAgain(mode: stageManager, hidden: hidden(), clickedAgain: false, doubleClick: true))
        XCTAssertEqual(asked, 0)
        XCTAssertTrue(DockClick.hideAgain(mode: stageManager, hidden: hidden(), clickedAgain: false, doubleClick: false))
        XCTAssertEqual(asked, 1)
    }

    /// 點別的 App（是要切過去）、點的不是 App 圖示、按下時沒有最前面的 App：不動
    func testOtherClicksAreLeftAlone() {
        XCTAssertEqual(decide(frontAtDown: 3), .none)
        XCTAssertEqual(decide(item: nil), .none)
        XCTAssertEqual(decide(frontAtDown: nil), .none)
    }

    /// 視窗都已經縮到 Dock：是我們縮的就叫回來（很多 App 自己不會叫回）；使用者自己縮的不動
    func testSecondClickRestoresWhatWeMinimized() {
        XCTAssertEqual(decide(visibleWindows: false, weMinimized: true), .restore)
        XCTAssertEqual(decide(visibleWindows: false), .none)
        // 點的是別的 App、或拖曳：不叫回
        XCTAssertEqual(decide(frontAtDown: 3, visibleWindows: false, weMinimized: true), .none)
        XCTAssertEqual(decide(visibleWindows: false, moved: 9, weMinimized: true), .none)
    }

    /// 拖曳圖示（移動超過幾個點）：不是點擊，不動
    func testDragIsNotAClick() {
        XCTAssertEqual(decide(moved: 4), .minimize)
        XCTAssertEqual(decide(moved: 6), .none)
    }

    /// 回呼晚跑時 Dock 已經切到被點的 App：前景 App 要用按下那一刻以前最後一次切換（#25：點背景 App 也被縮下去）
    func testFrontAppIsTheOneBeforeTheClick() {
        let history: [(pid: Int32, time: Double)] = [(1, 10), (2, 20), (3, 30.5)]
        XCTAssertEqual(DockClick.frontApp(at: 30, history: history), 2)
        XCTAssertEqual(DockClick.frontApp(at: 30.5, history: history), 3)
        XCTAssertEqual(DockClick.frontApp(at: 99, history: history), 3)
        XCTAssertNil(DockClick.frontApp(at: 5, history: history))
        // 點背景 App（3）時讀到的已經是切換後的：用紀錄判斷，按下時最前面是 2，不動
        XCTAssertEqual(decide(frontAtDown: DockClick.frontApp(at: 30, history: history), item: 3), .none)
    }

    /// 有沒有開著的視窗用 WindowServer 的清單判斷：只算這個 App 一般層級、看得見、夠大的視窗；
    /// 我們縮下去還沒叫回的視窗就算被 Dock 先叫回了也不算（回呼晚跑時不會又縮下去，#25）
    func testVisibleWindowFromWindowServer() {
        let normal = DockClick.ScreenWindow(pid: 7, id: 1, layer: 0, alpha: 1, size: CGSize(width: 800, height: 600))
        XCTAssertTrue(DockClick.hasVisibleWindow([normal], pid: 7, excluding: []))
        XCTAssertTrue(!DockClick.hasVisibleWindow([normal], pid: 8, excluding: []))
        XCTAssertTrue(!DockClick.hasVisibleWindow([normal], pid: 7, excluding: [1]))
        var helper = normal
        helper.size = CGSize(width: 10, height: 10)
        var floating = normal
        floating.layer = 3
        var invisible = normal
        invisible.alpha = 0
        XCTAssertTrue(!DockClick.hasVisibleWindow([helper, floating, invisible], pid: 7, excluding: []))
        // 被 Dock 先叫回的是我們縮的（1），另一個開著的視窗（2）照算
        var other = normal
        other.id = 2
        XCTAssertTrue(DockClick.hasVisibleWindow([normal, other], pid: 7, excluding: [1]))
    }
}
