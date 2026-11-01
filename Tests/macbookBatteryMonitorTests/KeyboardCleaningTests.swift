import Foundation

struct KeyboardCleaningTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// 清潔中擋下所有鍵盤事件（一般按鍵、修飾鍵、亮度音量等系統鍵）；滑鼠與觸控板照常，才點得到「結束清潔」
    func testBlocksKeyboardOnlyWhileActive() {
        var cleaning = KeyboardCleaning()
        XCTAssertTrue(!cleaning.blocks(.keyDown))
        cleaning.start(seconds: 60, now: now)
        for kind in [KeyboardCleaning.EventKind.keyDown, .keyUp, .flagsChanged, .systemKey] { XCTAssertTrue(cleaning.blocks(kind)) }
        XCTAssertTrue(!cleaning.blocks(.pointer))
        cleaning.stop()
        XCTAssertTrue(!cleaning.blocks(.keyDown))
    }

    /// 時間到自動結束；剩餘秒數無條件進位
    func testExpires() {
        var cleaning = KeyboardCleaning()
        cleaning.start(seconds: 60, now: now)
        XCTAssertEqual(cleaning.remainingSeconds(now: now.addingTimeInterval(0.5)), 60)
        XCTAssertEqual(cleaning.remainingSeconds(now: now.addingTimeInterval(59.2)), 1)
        XCTAssertTrue(!cleaning.isExpired(now: now.addingTimeInterval(59.9)))
        XCTAssertTrue(cleaning.isExpired(now: now.addingTimeInterval(60)))
    }

    /// 可選的時間；超出範圍的退回預設 60 秒（包括匯入的設定）
    func testDurations() {
        XCTAssertEqual(KeyboardCleaning.durations, [30, 60, 120])
        XCTAssertEqual(KeyboardCleaning.validDuration(120), 120)
        XCTAssertEqual(KeyboardCleaning.validDuration(5), 60)
        XCTAssertEqual(KeyboardCleaning.validDuration(9999), 60)
    }
}
