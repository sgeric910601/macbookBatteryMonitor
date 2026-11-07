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
