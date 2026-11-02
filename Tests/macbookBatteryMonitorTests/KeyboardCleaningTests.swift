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

    /// 擦的時候按到鍵就重新倒數：只有停手滿設定的秒數才恢復，不會擦到一半鍵盤就有作用
    func testKeyPressRestartsCountdown() {
        var cleaning = KeyboardCleaning()
        cleaning.start(seconds: 30, now: now)
        cleaning.keyPressed(now: now.addingTimeInterval(25))
        XCTAssertTrue(!cleaning.isExpired(now: now.addingTimeInterval(40)))
        XCTAssertEqual(cleaning.remainingSeconds(now: now.addingTimeInterval(25)), 30)
        XCTAssertTrue(cleaning.isExpired(now: now.addingTimeInterval(55)))
        // 沒在清潔時按鍵不會開始
        var idle = KeyboardCleaning()
        idle.keyPressed(now: now)
        XCTAssertTrue(!idle.isActive)
    }

    /// 按住不放（自動重複，例如鍵卡住或貓趴在鍵盤上）不重設倒數；不論怎麼按，最多 5 分鐘一定恢復
    func testRepeatsAndHardLimit() {
        var cleaning = KeyboardCleaning()
        cleaning.start(seconds: 30, now: now)
        cleaning.keyPressed(now: now.addingTimeInterval(20), isRepeat: true)
        XCTAssertTrue(cleaning.isExpired(now: now.addingTimeInterval(30)))
        var busy = KeyboardCleaning()
        busy.start(seconds: 120, now: now)
        for second in stride(from: 0, through: 400, by: 10) { busy.keyPressed(now: now.addingTimeInterval(Double(second)), isRepeat: false) }
        XCTAssertTrue(busy.isExpired(now: now.addingTimeInterval(KeyboardCleaning.hardLimit)))
    }
}
