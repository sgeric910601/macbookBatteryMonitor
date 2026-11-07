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
}
