import Foundation

struct QuitGuardTests {
    private let q = 12, w = 13, a = 0
    private let start = 100.0

    private func down(_ code: Int, cmd: Bool = true, other: Bool = false, repeat r: Bool = false, at time: Double? = nil, app: Int32 = 1) -> QuitGuard.Event {
        .keyDown(keyCode: code, command: cmd, otherModifiers: other, isRepeat: r, time: time ?? start, frontApp: app)
    }

    /// 按住 ⌘Q 滿時間才結束一開始的 App；按下的那一下和自動重複都攔下
    func testHoldingQuitCompletes() {
        var guardian = QuitGuard(holdQuit: true, holdClose: true, duration: 1)
        XCTAssertEqual(guardian.handle(down(q)), .swallow)
        XCTAssertEqual(guardian.holding?.kind, .quit)
        XCTAssertEqual(guardian.holding?.app, 1)
        XCTAssertEqual(guardian.handle(down(q, repeat: true, at: start + 0.5)), .swallow)
        XCTAssertEqual(guardian.progress(now: start + 0.5), 0.5)
        XCTAssertEqual(guardian.complete(now: start + 0.99, frontApp: 1), nil)
        XCTAssertEqual(guardian.complete(now: start + 1, frontApp: 1), QuitGuard.Hold(kind: .quit, app: 1, began: start))
        XCTAssertTrue(guardian.holding == nil)
        // 完成後放開按鍵：攔下，不讓 App 收到單獨的放開
        XCTAssertEqual(guardian.handle(.keyUp(keyCode: q)), .swallow)
    }

    /// 提早放開 Q 或 Cmd：取消，什麼都不做
    func testEarlyReleaseCancels() {
        var guardian = QuitGuard(holdQuit: true, holdClose: true, duration: 1)
        _ = guardian.handle(down(w))
        XCTAssertEqual(guardian.handle(.keyUp(keyCode: w)), .swallow)
        XCTAssertTrue(guardian.holding == nil)
        XCTAssertEqual(guardian.complete(now: start + 2, frontApp: 1), nil)
        _ = guardian.handle(down(q))
        XCTAssertEqual(guardian.handle(.commandReleased), .pass)
        XCTAssertTrue(guardian.holding == nil)
    }

    /// 按住期間最前面的 App 換了：取消，不會結束後面的 App
    func testFrontAppChangeCancels() {
        var guardian = QuitGuard(holdQuit: true, holdClose: true, duration: 1)
        _ = guardian.handle(down(q, app: 1))
        XCTAssertEqual(guardian.complete(now: start + 1.5, frontApp: 2), nil)
        XCTAssertTrue(guardian.holding == nil)
    }

    /// 按住期間按了別的鍵：取消，那個鍵照常送出
    func testOtherKeyCancels() {
        var guardian = QuitGuard(holdQuit: true, holdClose: true, duration: 1)
        _ = guardian.handle(down(q))
        XCTAssertEqual(guardian.handle(down(a, at: start + 0.2)), .pass)
        XCTAssertTrue(guardian.holding == nil)
    }

    /// 沒打開的、加了 Shift 等其他修飾鍵的、沒按 Cmd 的：都不管
    func testLeavesOtherShortcutsAlone() {
        var guardian = QuitGuard(holdQuit: true, holdClose: false, duration: 1)
        XCTAssertEqual(guardian.handle(down(w)), .pass)
        XCTAssertEqual(guardian.handle(down(q, other: true)), .pass)
        XCTAssertEqual(guardian.handle(down(q, cmd: false)), .pass)
        XCTAssertEqual(guardian.handle(.keyUp(keyCode: q)), .pass)
        XCTAssertTrue(guardian.holding == nil)
        // 沒在按住時收到的自動重複（例如功能剛打開）也不管
        XCTAssertEqual(guardian.handle(down(q, repeat: true)), .pass)
    }

    /// 按住時再按一次（例如另一隻手又按了 Q）：維持原本的計時，不重新開始
    func testSecondPressKeepsOriginalTimer() {
        var guardian = QuitGuard(holdQuit: true, holdClose: true, duration: 1)
        _ = guardian.handle(down(q, at: start))
        XCTAssertEqual(guardian.handle(down(q, at: start + 0.6)), .swallow)
        XCTAssertEqual(guardian.holding?.began, start)
    }

    /// 按住結束或取消之後，還按著的鍵自動重複送出：一律攔下，否則會連續關分頁、或結束換過去的 App
    func testRepeatsAfterHoldEndAreSwallowed() {
        var completed = QuitGuard(holdQuit: true, holdClose: true, duration: 1)
        _ = completed.handle(down(w))
        _ = completed.complete(now: start + 1, frontApp: 1)
        XCTAssertEqual(completed.handle(down(w, repeat: true, at: start + 1.1)), .swallow)
        var switched = QuitGuard(holdQuit: true, holdClose: true, duration: 1)
        _ = switched.handle(down(q, app: 1))
        _ = switched.complete(now: start + 0.5, frontApp: 2)
        XCTAssertEqual(switched.handle(down(q, repeat: true, at: start + 0.6, app: 2)), .swallow)
        // 先放開 Cmd、Q 還按著：重複的 q 不能打進輸入框
        var released = QuitGuard(holdQuit: true, holdClose: true, duration: 1)
        _ = released.handle(down(q))
        _ = released.handle(.commandReleased)
        XCTAssertEqual(released.handle(down(q, cmd: false, repeat: true, at: start + 0.6)), .swallow)
        // 放開之後再按 Q：照常
        XCTAssertEqual(released.handle(.keyUp(keyCode: q)), .swallow)
        XCTAssertEqual(released.handle(down(q, cmd: false, at: start + 1)), .pass)
    }

    /// 攔截被系統暫停時只放棄這次按住，記得哪些鍵被攔下，放開時照樣攔下，不讓 App 收到單獨的放開
    func testCancelKeepsSwallowedKeys() {
        var guardian = QuitGuard(holdQuit: true, holdClose: true, duration: 1)
        _ = guardian.handle(down(q))
        guardian.cancelHold()
        XCTAssertTrue(guardian.holding == nil)
        XCTAssertEqual(guardian.handle(.keyUp(keyCode: q)), .swallow)
    }

    /// 按住 ⌘W 時改按 ⌘Q：換成新的一次按住，重新計時
    func testSwitchingKeyStartsNewHold() {
        var guardian = QuitGuard(holdQuit: true, holdClose: true, duration: 1)
        _ = guardian.handle(down(w, at: start))
        XCTAssertEqual(guardian.handle(down(q, at: start + 0.5)), .swallow)
        XCTAssertEqual(guardian.holding, QuitGuard.Hold(kind: .quit, app: 1, began: start + 0.5))
    }

    /// 漏掉了放開（例如攔截暫停時）：下一次真正按下同一個鍵時清掉舊紀錄，那次的放開照常送出，鍵不會卡住
    func testRealPressClearsStaleSwallowedKey() {
        var guardian = QuitGuard(holdQuit: true, holdClose: true, duration: 1)
        _ = guardian.handle(down(q))
        guardian.cancelHold()
        XCTAssertEqual(guardian.handle(down(q, cmd: false, at: start + 5)), .pass)
        XCTAssertEqual(guardian.handle(.keyUp(keyCode: q)), .pass)
    }
}
