import Foundation

struct ScrollLinearTests {
    /// 轉得快時系統會加速（一格好幾行）：改成固定的行數，方向不變
    func testFixesAcceleratedTicks() {
        XCTAssertEqual(ScrollLinear.adjust(lines: 7, lineSetting: 3), ScrollLinear.Delta(lines: 3, fixed: 3, points: 30))
        XCTAssertEqual(ScrollLinear.adjust(lines: -12, lineSetting: 1), ScrollLinear.Delta(lines: -1, fixed: -1, points: -10))
        XCTAssertEqual(ScrollLinear.adjust(lines: 1, lineSetting: 5), ScrollLinear.Delta(lines: 5, fixed: 5, points: 50))
    }

    /// 這一軸沒有捲動（例如只轉上下時的左右）：維持 0，不會憑空多出捲動
    func testZeroStaysZero() {
        XCTAssertEqual(ScrollLinear.adjust(lines: 0, lineSetting: 3), ScrollLinear.Delta(lines: 0, fixed: 0, points: 0))
    }

    /// 行數是 0 但有小數行數或像素量（慢慢轉、遠端桌面）：照那個方向，不能被歸零
    func testUsesFineDeltaWhenLinesAreZero() {
        XCTAssertEqual(ScrollLinear.adjust(lines: 0, fixed: -0.4, points: -4, lineSetting: 3), ScrollLinear.Delta(lines: -3, fixed: -3, points: -30))
        XCTAssertEqual(ScrollLinear.adjust(lines: 0, fixed: 0, points: 6, lineSetting: 1), ScrollLinear.Delta(lines: 1, fixed: 1, points: 10))
    }

    /// 可選的行數；不在清單上的（包括匯入的設定）當作關閉
    func testSettings() {
        XCTAssertEqual(ScrollLinear.choices, [0, 1, 3, 5])
        XCTAssertEqual(ScrollLinear.valid(3), 3)
        XCTAssertEqual(ScrollLinear.valid(4), 0)
        XCTAssertEqual(ScrollLinear.valid(-1), 0)
    }
}
