import Foundation
import Combine

struct HistorySample: Codable {
    var t: Date
    /// 電量 %；桌上型 Mac 沒有電池，記為 -1
    var pct: Int
    /// 系統耗電（W）。從 pmset 紀錄回填的資料沒有功率
    var watts: Double?
    var plugged: Bool
    var charging: Bool
}

struct ChartPoint: Identifiable {
    let id: Int
    let t: Date
    let pct: Double
    let watts: Double?
    let plugged: Bool
    /// 不同段的點不會連線（中間長時間沒資料、或接電狀態改變）
    let segment: Int
    /// 功率圖的分段：沒有功率資料的地方斷開
    let wattsSegment: Int
}

@MainActor
final class HistoryStore: ObservableObject {
    static let retention: TimeInterval = 7 * 24 * 3600

    @Published private(set) var samples: [HistorySample] = []
    private var isPreview = false
    private var unsaved = 0
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            // 沿用改名前的資料夾，舊的歷史紀錄才讀得到
            .appendingPathComponent("BatteryMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        if let data = try? Data(contentsOf: fileURL) {
            if let decoded = try? JSONDecoder().decode([HistorySample].self, from: data) {
                samples = decoded.sorted { $0.t < $1.t }
            } else {
                // 讀不懂就先備份，免得 15 分鐘後被新的空檔覆蓋掉
                let backup = dir.appendingPathComponent("history-\(Int(Date().timeIntervalSince1970)).json.bak")
                try? FileManager.default.moveItem(at: fileURL, to: backup)
            }
        }
        trim()
    }

    func add(_ sample: HistorySample) {
        samples.append(sample)
        trim()
        unsaved += 1
        if unsaved >= 15 { save() }
    }

    /// 用 pmset 紀錄補上 App 沒在跑時的電量。已經有資料的時段（前後 5 分鐘內）不補
    func backfill(_ entries: [HistorySample]) {
        let cutoff = Date().addingTimeInterval(-Self.retention)
        var added: [HistorySample] = []
        for entry in entries where entry.t >= cutoff {
            if let last = added.last, entry.t.timeIntervalSince(last.t) < 300 { continue }
            if hasSample(near: entry.t, within: 300) { continue }
            added.append(entry)
        }
        guard !added.isEmpty else { return }
        samples = (samples + added).sorted { $0.t < $1.t }
        save()
    }

    private func hasSample(near t: Date, within interval: TimeInterval) -> Bool {
        var low = 0, high = samples.count
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].t < t { low = mid + 1 } else { high = mid }
        }
        if low < samples.count, samples[low].t.timeIntervalSince(t) < interval { return true }
        if low > 0, t.timeIntervalSince(samples[low - 1].t) < interval { return true }
        return false
    }

    /// 截圖用：換成示範資料，只放在記憶體裡，之後也不會寫回使用者的歷史檔
    func loadPreview(_ preview: [HistorySample]) {
        isPreview = true
        samples = preview
    }

    func save() {
        guard !isPreview else { return }
        guard let data = try? JSONEncoder().encode(samples) else { return }
        try? data.write(to: fileURL, options: .atomic)
        unsaved = 0
    }

    /// 最近一次從接電變成用電池的時間。紀錄太舊（App 中間沒在跑）就不採信。
    func lastUnplugged() -> Date? {
        guard let last = samples.last, !last.plugged, Date().timeIntervalSince(last.t) < 600 else { return nil }
        guard let pluggedIndex = samples.lastIndex(where: { $0.plugged }) else { return nil }
        return samples[samples.index(after: pluggedIndex)].t
    }

    /// 取指定時間範圍的資料並降採樣到 maxPoints 以內
    func points(range: TimeInterval, maxPoints: Int = 240, now: Date = Date()) -> [ChartPoint] {
        let start = now.addingTimeInterval(-range)
        let slice = samples.filter { $0.t >= start }
        guard !slice.isEmpty else { return [] }

        let bucket = max(1, Int((Double(slice.count) / Double(maxPoints)).rounded(.up)))
        // 睡眠時電量幾乎不變，所以只有超過 6 小時沒資料才斷線
        let gapLimit: TimeInterval = 6 * 3600
        var out: [ChartPoint] = []
        var segment = 0
        var wattsSegment = 0
        var previous: ChartPoint?
        var i = 0
        while i < slice.count {
            let chunk = slice[i..<min(i + bucket, slice.count)]
            let t = chunk[chunk.startIndex].t
            let pct = Double(chunk.reduce(0) { $0 + $1.pct }) / Double(chunk.count)
            let wattValues = chunk.compactMap(\.watts)
            let watts = wattValues.isEmpty ? nil : wattValues.reduce(0, +) / Double(wattValues.count)
            let plugged = chunk.contains { $0.plugged }
            if let p = previous {
                if watts == nil || p.watts == nil || t.timeIntervalSince(p.t) > 600 {
                    wattsSegment += 1
                }
                if t.timeIntervalSince(p.t) > gapLimit {
                    segment += 1
                } else if plugged != p.plugged {
                    // 換顏色時把上一個點複製到新段，線才會接起來
                    segment += 1
                    out.append(ChartPoint(id: out.count, t: p.t, pct: p.pct, watts: nil, plugged: plugged,
                                          segment: segment, wattsSegment: wattsSegment))
                }
            }
            let point = ChartPoint(id: out.count, t: t, pct: pct, watts: watts, plugged: plugged,
                                   segment: segment, wattsSegment: wattsSegment)
            out.append(point)
            previous = point
            i += bucket
        }
        return out
    }

    private func trim() {
        let cutoff = Date().addingTimeInterval(-Self.retention)
        if let first = samples.firstIndex(where: { $0.t >= cutoff }), first > 0 {
            samples.removeFirst(first)
        } else if let last = samples.last, last.t < cutoff {
            samples.removeAll()
        }
    }
}
