import Foundation

final class HistoryTests {
    private func sample(_ minutesAgo: Double, plugged: Bool, now: Date) -> HistorySample {
        HistorySample(t: now.addingTimeInterval(-minutesAgo * 60), pct: 80, watts: nil, plugged: plugged, charging: false)
    }

    /// 耗電面積圖只在真的沒資料超過 10 分鐘時斷開；7 天的圖每點合併約 42 分鐘，連續資料仍要連成一段
    func testWattsSegmentsFollowRealGaps() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        func segments(_ minutes: [Int], range: TimeInterval) -> Int {
            let samples = minutes.reversed().map {
                HistorySample(t: now.addingTimeInterval(-Double($0) * 60), pct: 80, watts: 10, plugged: true, charging: false)
            }
            return Set(HistoryStore.points(samples, range: range, now: now).map(\.wattsSegment)).count
        }
        let week = 7 * 24 * 3600.0
        let all = Array(0..<(7 * 24 * 60))
        XCTAssertEqual(segments(all, range: week), 1)
        // 闔蓋 2 小時：比每點合併的時間長，要斷開
        XCTAssertEqual(segments(all.filter { !(3000..<3120).contains($0) }, range: week), 2)
        // 1 小時的圖每分鐘一點：空 15 分鐘就斷開，空 5 分鐘不斷
        XCTAssertEqual(segments(all.filter { $0 < 60 && !(20..<35).contains($0) }, range: 3600), 2)
        XCTAssertEqual(segments(all.filter { $0 < 60 && !(20..<25).contains($0) }, range: 3600), 1)
    }

    func testUnpluggedTimeStartsAtBootAfterShutdown() {
        let now = Date()
        // 三天前接著電，之後拔電、關機；今天開機後一直用電池
        let samples = [sample(3 * 24 * 60 + 10, plugged: true, now: now), sample(3 * 24 * 60, plugged: false, now: now),
                       sample(20, plugged: false, now: now), sample(1, plugged: false, now: now)]
        let boot = now.addingTimeInterval(-25 * 60)
        XCTAssertEqual(HistoryStore.lastUnplugged(in: samples, now: now, bootTime: boot), boot)
        // 這次開機前就拔電、中間只是睡眠：照原本的拔電時間算
        let earlyBoot = now.addingTimeInterval(-5 * 24 * 3600)
        XCTAssertEqual(HistoryStore.lastUnplugged(in: samples, now: now, bootTime: earlyBoot), samples[1].t)
        // 還接著電、或紀錄太舊：不算
        XCTAssertNil(HistoryStore.lastUnplugged(in: samples + [sample(0.5, plugged: true, now: now)], now: now, bootTime: boot))
        XCTAssertNil(HistoryStore.lastUnplugged(in: Array(samples.prefix(3)), now: now, bootTime: boot))
        XCTAssertEqual(BootTime.clamp(samples[1].t, bootTime: nil), samples[1].t)
    }
}
