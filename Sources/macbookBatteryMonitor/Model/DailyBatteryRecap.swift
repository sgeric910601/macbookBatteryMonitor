import Foundation

/// 「今日」分頁：從電量歷史算出今天用掉、補回多少電量，接電幾次，用電池多久
struct DailyBatteryRecap: Equatable {
    var usedPercent = 0
    var chargedPercent = 0
    var plugInCount = 0
    var unpluggedMinutes = 0
    var longestUnpluggedMinutes = 0
    /// 今天開始（或第一筆紀錄）與最新的電量；沒有紀錄時是 nil
    var startPercent: Int?
    var endPercent: Int?

    var netChange: Int? {
        guard let startPercent, let endPercent else { return nil }
        return endPercent - startPercent
    }

    static func make(samples: [HistorySample], day: Date = Date(), calendar: Calendar = .current) -> DailyBatteryRecap {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return DailyBatteryRecap() }
        // 桌上型 Mac 的紀錄沒有電量（pct = -1）
        let ordered = samples.filter { $0.pct >= 0 }.sorted { $0.t < $1.t }
        let today = ordered.filter { $0.t >= start && $0.t < end }
        guard !today.isEmpty else { return DailyBatteryRecap() }

        // 午夜前最後一筆當作今天開始的狀態
        var points = today
        if let before = ordered.last(where: { $0.t < start }) {
            points.insert(HistorySample(t: start, pct: before.pct, watts: before.watts, plugged: before.plugged,
                                        charging: before.charging), at: 0)
        }

        var recap = DailyBatteryRecap(startPercent: points[0].pct, endPercent: today[today.count - 1].pct)
        var unplugged: TimeInterval = 0
        var stretch: TimeInterval = 0
        var longest: TimeInterval = 0
        // 依接電／用電池分段，每段只算頭尾的淨變化（接著電源時電量在上限附近 ±1% 跳動不重複計算）
        var segmentPlugged = points[0].plugged
        var segmentStart = points[0].pct
        func close(at percent: Int) {
            let net = percent - segmentStart
            if segmentPlugged { recap.chargedPercent += max(0, net) } else { recap.usedPercent += max(0, -net) }
        }
        for (left, right) in zip(points, points.dropFirst()) {
            // 中間斷了很久（睡眠、App 沒開）最多算 30 分鐘
            let dt = min(max(0, right.t.timeIntervalSince(left.t)), 30 * 60)
            if !left.plugged {
                unplugged += dt
                stretch += dt
                longest = max(longest, stretch)
            }
            guard left.plugged != right.plugged else { continue }
            // 插拔之間的變化算進前一段
            close(at: right.pct)
            if right.plugged { recap.plugInCount += 1 }
            stretch = 0
            segmentPlugged = right.plugged
            segmentStart = right.pct
        }
        close(at: points[points.count - 1].pct)
        recap.unpluggedMinutes = Int((unplugged / 60).rounded())
        recap.longestUnpluggedMinutes = Int((longest / 60).rounded())
        return recap
    }
}
