import Foundation

struct RefreshPacingTests {
    /// 有人看時照設定的間隔；沒人看時至少 30 秒，設定本來就更長的不縮短
    func testIntervalStretchesOnlyWhenUnseen() {
        XCTAssertEqual(RefreshPacing.interval(base: 1, unseen: false), 1)
        XCTAssertEqual(RefreshPacing.interval(base: 1, unseen: true), 30)
        XCTAssertEqual(RefreshPacing.interval(base: 60, unseen: true), 60)
    }

    /// 平常誤差最多 0.3 秒（配合變壓器預讀）；沒人看時放寬到間隔的一成
    func testTolerance() {
        XCTAssertEqual(RefreshPacing.tolerance(base: 1, unseen: false), 0.2)
        XCTAssertEqual(RefreshPacing.tolerance(base: 5, unseen: false), 0.3)
        XCTAssertEqual(RefreshPacing.tolerance(base: 1, unseen: true), 3)
        XCTAssertEqual(RefreshPacing.tolerance(base: 60, unseen: true), 6)
    }
}
