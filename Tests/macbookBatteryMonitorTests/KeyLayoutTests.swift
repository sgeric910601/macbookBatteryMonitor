import Foundation

struct KeyLayoutTests {
    /// US／ABC：位置和字母對得上，照常處理；大寫（按著 Shift）也算
    func testUSLayoutKeepsKeys() {
        XCTAssertTrue(KeyLayout.usKeyCode(12, character: "q") == 12)
        XCTAssertTrue(KeyLayout.usKeyCode(13, character: "W") == 13)
        XCTAssertTrue(KeyLayout.usKeyCode(7, character: "x") == 7)
    }

    /// AZERTY 的 Q 位置是 A、Dvorak 的 C 位置是 J：不處理；讀不到字也不處理
    func testOtherLayoutsAreSkipped() {
        XCTAssertTrue(KeyLayout.usKeyCode(12, character: "a") == nil)
        XCTAssertTrue(KeyLayout.usKeyCode(8, character: "j") == nil)
        XCTAssertTrue(KeyLayout.usKeyCode(13, character: nil) == nil)
    }

    /// 不是字母鍵（F2、Return）不看字
    func testNonLetterKeysPassThrough() {
        XCTAssertTrue(KeyLayout.usKeyCode(120, character: "") == 120)
        XCTAssertTrue(KeyLayout.usKeyCode(36, character: "\r") == 36)
    }
}
