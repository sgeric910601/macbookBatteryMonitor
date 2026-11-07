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

    /// 按下之後才收到視窗叫回：是 Dock 這一下叫回的，按下時沒有開著的視窗（#25：再點一次叫回後又被縮下去）
    func testRestoredByThisClickCountsAsMinimized() {
        let late = DockClick.stateAtClick(visibleNow: true, oursMinimizedNow: false, hasOurs: true, restoredAfterClick: true)
        XCTAssertTrue(!late.visible)
        XCTAssertTrue(late.minimizedByUs)
        XCTAssertEqual(decide(visibleWindows: late.visible, weMinimized: late.minimizedByUs), .restore)
        // 使用者自己縮的被 Dock 叫回：不動，不能又縮下去
        let user = DockClick.stateAtClick(visibleNow: true, oursMinimizedNow: false, hasOurs: false, restoredAfterClick: true)
        XCTAssertEqual(decide(visibleWindows: user.visible, weMinimized: user.minimizedByUs), .none)
        // 沒有叫回：照讀到的狀態
        let normal = DockClick.stateAtClick(visibleNow: true, oursMinimizedNow: false, hasOurs: true, restoredAfterClick: false)
        XCTAssertTrue(normal.visible)
        XCTAssertTrue(!normal.minimizedByUs)
    }
}
