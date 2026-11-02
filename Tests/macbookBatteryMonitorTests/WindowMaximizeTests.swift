import Foundation

struct WindowMaximizeTests {
    private let screen = CGRect(x: 0, y: 39, width: 1800, height: 1050)

    /// 第一次按：填滿可用範圍，記下原本的位置大小；再按一次：還原
    func testMaximizeThenRestore() {
        var memory = WindowMaximize()
        let original = CGRect(x: 200, y: 150, width: 800, height: 600)
        XCTAssertEqual(memory.toggle(window: 7, frame: original, visible: screen), screen)
        XCTAssertEqual(memory.toggle(window: 7, frame: screen, visible: screen), original)
        // 還原後再按：又是放大
        XCTAssertEqual(memory.toggle(window: 7, frame: original, visible: screen), screen)
    }

    /// 已經差不多填滿（App 自己限制了尺寸、差幾點）也算放大過，再按就還原
    func testNearlyMaximizedCountsAsMaximized() {
        var memory = WindowMaximize()
        let original = CGRect(x: 100, y: 100, width: 700, height: 500)
        _ = memory.toggle(window: 3, frame: original, visible: screen)
        let appClamped = CGRect(x: 0, y: 39, width: 1796, height: 1047)
        XCTAssertEqual(memory.toggle(window: 3, frame: appClamped, visible: screen), original)
    }

    /// 沒記過原本大小、但已經填滿（例如使用者自己拉滿的）：沒有可以還原的，維持填滿
    func testFullWithoutMemoryStaysFull() {
        var memory = WindowMaximize()
        XCTAssertEqual(memory.toggle(window: 9, frame: screen, visible: screen), screen)
    }

    /// 每個視窗各自記；被關掉的視窗可以清掉，記錄不會一直變多
    func testPerWindowMemory() {
        var memory = WindowMaximize()
        let a = CGRect(x: 10, y: 60, width: 300, height: 200), b = CGRect(x: 400, y: 300, width: 500, height: 400)
        _ = memory.toggle(window: 1, frame: a, visible: screen)
        _ = memory.toggle(window: 2, frame: b, visible: screen)
        XCTAssertEqual(memory.toggle(window: 1, frame: screen, visible: screen), a)
        memory.forget(window: 2)
        XCTAssertEqual(memory.toggle(window: 2, frame: screen, visible: screen), screen)
    }
}
