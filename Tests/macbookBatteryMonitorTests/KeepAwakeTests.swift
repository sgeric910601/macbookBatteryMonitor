import Foundation

struct KeepAwakeTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// 開始後到期就停；「直到關閉」不會自己停
    func testStartAndExpire() {
        var awake = KeepAwake()
        XCTAssertTrue(!awake.isActive)
        awake.start(.hour1, now: now)
        XCTAssertTrue(awake.isActive)
        XCTAssertTrue(awake.duration == .hour1)
        XCTAssertTrue(!awake.shouldStop(now: now.addingTimeInterval(3599), batteryPercent: 80, onBattery: true))
        XCTAssertTrue(awake.shouldStop(now: now.addingTimeInterval(3600), batteryPercent: 80, onBattery: true))
        awake.start(.indefinitely, now: now)
        XCTAssertTrue(!awake.shouldStop(now: now.addingTimeInterval(86400 * 30), batteryPercent: 80, onBattery: true))
        XCTAssertTrue(awake.duration == .indefinitely)
        awake.stop()
        XCTAssertTrue(!awake.isActive)
        XCTAssertTrue(awake.duration == nil)
    }

    /// 用電池而且電量到 10% 以下時停止；接著電源時不管電量
    func testStopsOnLowBattery() {
        var awake = KeepAwake()
        awake.start(.indefinitely, now: now)
        XCTAssertTrue(!awake.shouldStop(now: now, batteryPercent: 11, onBattery: true))
        XCTAssertTrue(awake.shouldStop(now: now, batteryPercent: 10, onBattery: true))
        XCTAssertTrue(!awake.shouldStop(now: now, batteryPercent: 5, onBattery: false))
        // 桌上型 Mac 沒有電池
        XCTAssertTrue(!awake.shouldStop(now: now, batteryPercent: nil, onBattery: false))
        // 沒在啟用時不需要停
        XCTAssertTrue(!KeepAwake().shouldStop(now: now, batteryPercent: 1, onBattery: true))
    }

    /// 剩餘時間的文字：無條件進位到分鐘，超過一小時顯示幾小時幾分；「直到關閉」沒有剩餘時間
    func testRemainingText() {
        var awake = KeepAwake()
        awake.start(.minutes30, now: now)
        XCTAssertEqual(awake.remainingText(now: now), "30 分鐘")
        XCTAssertEqual(awake.remainingText(now: now.addingTimeInterval(29 * 60 + 1)), "1 分鐘")
        awake.start(.hour2, now: now)
        XCTAssertEqual(awake.remainingText(now: now.addingTimeInterval(10 * 60)), "1 小時 50 分")
        XCTAssertEqual(awake.remainingText(now: now), "2 小時")
        awake.start(.indefinitely, now: now)
        XCTAssertEqual(awake.remainingText(now: now), nil)
    }

    /// 選單上的時間選項依序排列，各有名稱
    func testDurations() {
        XCTAssertEqual(KeepAwake.Duration.allCases.map(\.title), ["30 分鐘", "1 小時", "2 小時", "直到關閉"])
        XCTAssertEqual(KeepAwake.Duration.hour2.seconds, 7200)
        XCTAssertEqual(KeepAwake.Duration.indefinitely.seconds, nil)
    }

    /// 指定的 App 有任何一個在執行就防止休眠；清單空的、都沒在執行、用電池而且電量到 10% 以下時不防止
    func testAutoWhileAppsRun() {
        let list: Set<String> = ["com.example.Slides", "com.example.Player"]
        XCTAssertTrue(KeepAwake.autoHolds(running: ["com.apple.finder", "com.example.Player"], list: list, batteryPercent: 80, onBattery: true))
        XCTAssertTrue(!KeepAwake.autoHolds(running: ["com.apple.finder"], list: list, batteryPercent: 80, onBattery: true))
        XCTAssertTrue(!KeepAwake.autoHolds(running: ["com.example.Player"], list: [], batteryPercent: 80, onBattery: true))
        XCTAssertTrue(!KeepAwake.autoHolds(running: ["com.example.Player"], list: list, batteryPercent: 10, onBattery: true))
        XCTAssertTrue(KeepAwake.autoHolds(running: ["com.example.Player"], list: list, batteryPercent: 5, onBattery: false))
        XCTAssertTrue(KeepAwake.autoHolds(running: ["com.example.Slides"], list: list, batteryPercent: nil, onBattery: false))
    }
}
