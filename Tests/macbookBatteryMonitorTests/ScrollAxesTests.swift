import Foundation

struct ScrollAxesTests {
    /// 每個捲動量欄位屬於哪一軸：公開的行數、像素、精細值，以及沒有公開文件的 175～178（176／178 垂直、175／177 水平）
    func testFieldAxes() {
        for field in [11, 96, 93, 176, 178] { XCTAssertEqual(ScrollAxes.axis(ofField: field), .vertical) }
        for field in [12, 97, 94, 175, 177] { XCTAssertEqual(ScrollAxes.axis(ofField: field), .horizontal) }
        XCTAssertEqual(ScrollAxes.axis(ofField: 137), nil)
    }

    /// 上下一律反向；左右只有打開「左右也反向」時才反
    func testMultiplier() {
        XCTAssertEqual(ScrollAxes.multiplier(.vertical, reverseHorizontal: false), -1)
        XCTAssertEqual(ScrollAxes.multiplier(.vertical, reverseHorizontal: true), -1)
        XCTAssertEqual(ScrollAxes.multiplier(.horizontal, reverseHorizontal: true), -1)
        XCTAssertEqual(ScrollAxes.multiplier(.horizontal, reverseHorizontal: false), 1)
    }
}
