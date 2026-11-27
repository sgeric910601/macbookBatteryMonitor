import Foundation

final class HistoryTests {
    private func sample(_ minutesAgo: Double, plugged: Bool, now: Date) -> HistorySample {
        HistorySample(t: now.addingTimeInterval(-minutesAgo * 60), pct: 80, watts: nil, plugged: plugged, charging: false)
    }

    /// 圖表十字準線：取時間最接近的點；附近沒有資料（超過容許間隔）時不顯示
    func testNearestChartPoint() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let points = [0, 60, 120, 600].enumerated().map { index, offset in
            ChartPoint(id: index, t: base.addingTimeInterval(TimeInterval(offset)), pct: Double(80 - index), watts: nil,
                       plugged: false, segment: 0, wattsSegment: 0)
        }
        XCTAssertEqual(ChartPoint.nearest(points, to: base.addingTimeInterval(70), maxGap: 60)?.id, 1)
        XCTAssertEqual(ChartPoint.nearest(points, to: base.addingTimeInterval(100), maxGap: 60)?.id, 2)
        XCTAssertNil(ChartPoint.nearest(points, to: base.addingTimeInterval(360), maxGap: 60))
        XCTAssertNil(ChartPoint.nearest([], to: base, maxGap: 60))
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
