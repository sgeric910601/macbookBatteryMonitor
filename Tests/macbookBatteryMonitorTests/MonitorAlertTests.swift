import Foundation

struct MonitorAlertTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// 每 10 秒取樣一次，從 from 到 to 秒（含）；回傳哪幾秒通知了
    private func feed(_ alert: inout SustainedAlert, from: Int, to: Int, high: Bool, recovered: Bool = false) -> [Int] {
        stride(from: from, through: to, by: 10).filter {
            alert.update(high: high, recovered: recovered, at: t0.addingTimeInterval(TimeInterval($0)))
        }
    }

    /// 持續夠久才通知，只通知一次；回到正常才會再通知
    func testSustainedFiresOnceAndRearms() {
        var alert = SustainedAlert(duration: 300)
        XCTAssertEqual(feed(&alert, from: 0, to: 600, high: true), [300])
        // 降下來但還沒回到正常：再升高也不通知
        XCTAssertEqual(feed(&alert, from: 610, to: 650, high: false), [])
        XCTAssertEqual(feed(&alert, from: 660, to: 1200, high: true), [])
        // 回到正常後重新計時
        XCTAssertEqual(feed(&alert, from: 1210, to: 1220, high: false, recovered: true), [])
        XCTAssertEqual(feed(&alert, from: 1230, to: 1600, high: true), [1530])
    }

    /// 中間掉下來就重新計時
    func testDipRestartsTimer() {
        var alert = SustainedAlert(duration: 300)
        XCTAssertEqual(feed(&alert, from: 0, to: 200, high: true), [])
        XCTAssertEqual(feed(&alert, from: 210, to: 210, high: false), [])
        XCTAssertEqual(feed(&alert, from: 220, to: 600, high: true), [520])
    }

    /// 取樣中斷超過 60 秒（模組關掉、睡眠）不算持續：重新計時
    func testGapInSamplesRestartsTimer() {
        var alert = SustainedAlert(duration: 300)
        XCTAssertEqual(feed(&alert, from: 0, to: 200, high: true), [])
        XCTAssertEqual(feed(&alert, from: 400, to: 800, high: true), [700])
    }

    /// 不需要持續時間的（磁碟）第一次就通知
    func testImmediate() {
        var alert = SustainedAlert(duration: 0)
        XCTAssertEqual(feed(&alert, from: 0, to: 50, high: true), [0])
    }

    /// 各警示的條件：在門檻與恢復線之間是「不高也沒恢復」，避免來回跳
    func testRules() {
        XCTAssertTrue(MonitorAlertRules.cpu(usage: 0.95) == (true, false))
        XCTAssertTrue(MonitorAlertRules.cpu(usage: 0.8) == (false, false))
        XCTAssertTrue(MonitorAlertRules.cpu(usage: 0.5) == (false, true))
        XCTAssertTrue(MonitorAlertRules.memory(.critical) == (true, false))
        XCTAssertTrue(MonitorAlertRules.memory(.warning) == (false, false))
        XCTAssertTrue(MonitorAlertRules.memory(.normal) == (false, true))
        let gb: UInt64 = 1_000_000_000
        XCTAssertTrue(MonitorAlertRules.disk(available: 9 * gb) == (true, false))
        XCTAssertTrue(MonitorAlertRules.disk(available: 12 * gb) == (false, false))
        XCTAssertTrue(MonitorAlertRules.disk(available: 20 * gb) == (false, true))
    }
}
