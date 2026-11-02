import Foundation

struct MouseButtonsTests {
    /// 第 4、5 鍵（按鈕編號 3、4）照設定對應；其他按鈕（左、右、中鍵）一律不碰
    func testMapping() {
        let buttons = MouseButtons(back: .back, forward: .forward)
        XCTAssertEqual(buttons.action(forButton: 3), .back)
        XCTAssertEqual(buttons.action(forButton: 4), .forward)
        for other in [0, 1, 2, 5, 6] { XCTAssertEqual(buttons.action(forButton: other), nil) }
        // 設成「不處理」的按鈕照常交給 App
        XCTAssertEqual(MouseButtons(back: .none, forward: .missionControl).action(forButton: 3), nil)
    }

    /// 每個動作送出的按鍵：上一頁 ⌘[、下一頁 ⌘]、Mission Control 是 Control＋↑
    func testShortcuts() {
        XCTAssertEqual(MouseButtons.Action.back.shortcut, MouseButtons.Shortcut(keyCode: 33, command: true, control: false))
        XCTAssertEqual(MouseButtons.Action.forward.shortcut, MouseButtons.Shortcut(keyCode: 30, command: true, control: false))
        XCTAssertEqual(MouseButtons.Action.missionControl.shortcut, MouseButtons.Shortcut(keyCode: 126, command: false, control: true))
        XCTAssertEqual(MouseButtons.Action.none.shortcut, nil)
    }

    /// 存在設定裡的值不認得時當作不處理（包括匯入的設定）
    func testStoredValues() {
        XCTAssertEqual(MouseButtons.Action(stored: "forward"), .forward)
        XCTAssertEqual(MouseButtons.Action(stored: "launchRockets"), MouseButtons.Action.none)
        XCTAssertEqual(MouseButtons.Action(stored: nil), MouseButtons.Action.none)
        XCTAssertTrue(!MouseButtons(back: .none, forward: .none).isActive)
        XCTAssertTrue(MouseButtons(back: .none, forward: .back).isActive)
    }
}
