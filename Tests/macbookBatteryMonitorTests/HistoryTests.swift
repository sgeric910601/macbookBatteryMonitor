import Foundation

final class HistoryTests {
    private func sample(_ minutesAgo: Double, plugged: Bool, now: Date) -> HistorySample {
        HistorySample(t: now.addingTimeInterval(-minutesAgo * 60), pct: 80, watts: nil, plugged: plugged, charging: false)
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
