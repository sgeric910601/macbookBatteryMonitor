import Foundation

/// system_profiler 才有的系統健康度（「最大容量」）和狀況
struct SystemHealth: Codable, Equatable {
    var maxCapacityPercent: Int?
    var condition: String?
    var cycleCount: Int?

    var conditionText: String? {
        guard let condition else { return nil }
        switch condition {
        case "Good": return "良好"
        case "Normal": return "正常"
        case "Fair": return "尚可"
        case "Poor": return "不佳"
        case "Service Recommended": return "建議維修"
        case "Check Battery": return "請檢查電池"
        case "Replace Soon": return "即將需要更換"
        case "Replace Now": return "需要更換"
        default: return condition
        }
    }
}

enum SystemProfiler {
    static func readSync() -> SystemHealth? {
        guard let output = Shell.runSync("/usr/sbin/system_profiler", ["SPPowerDataType", "-json"]),
              let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["SPPowerDataType"] as? [[String: Any]],
              let battery = items.first(where: { $0["_name"] as? String == "spbattery_information" }),
              let health = battery["sppower_battery_health_info"] as? [String: Any] else { return nil }
        let maxCapacity = (health["sppower_battery_health_maximum_capacity"] as? String)
            .flatMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) }
        return SystemHealth(
            maxCapacityPercent: maxCapacity,
            condition: health["sppower_battery_health"] as? String,
            cycleCount: health["sppower_battery_cycle_count"] as? Int
        )
    }

    static func read() async -> SystemHealth? {
        await Task.detached(priority: .utility) { readSync() }.value
    }
}

/// 從 pmset 的電源紀錄找出這次拔掉電源的時間（App 第一次執行、還沒有自己的紀錄時用）
enum PowerLog {
    static func lastUnpluggedDateSync() -> Date? {
        guard let output = Shell.runSync("/bin/sh", ["-c", "pmset -g log | grep -E 'Using (AC|Batt)'"]) else { return nil }
        let lines = output.split(separator: "\n")
        guard let lastAC = lines.lastIndex(where: { $0.contains("Using AC") }) else { return nil }
        let next = lines.index(after: lastAC)
        guard next < lines.endIndex else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: String(lines[next].prefix(25)))
    }

    /// pmset 紀錄裡的「Using Batt(Charge: 87)」，用來回填歷史電量
    static func chargeHistorySync() -> [HistorySample] {
        guard let output = Shell.runSync("/bin/sh", ["-c", "pmset -g log | grep -E 'Using (AC|Batt)\\(Charge'"]) else { return [] }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        // macOS 12 沒有 Swift Regex，改用 NSRegularExpression
        guard let pattern = try? NSRegularExpression(pattern: #"Using (AC|Batt)\(Charge: ?(\d+)\)"#) else { return [] }
        return output.split(separator: "\n").compactMap { line in
            let text = String(line)
            guard let date = formatter.date(from: String(text.prefix(25))),
                  let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let source = Range(match.range(at: 1), in: text), let digits = Range(match.range(at: 2), in: text),
                  let pct = Int(text[digits]) else { return nil }
            let plugged = text[source] == "AC"
            return HistorySample(t: date, pct: pct, watts: nil, plugged: plugged, charging: plugged && pct < 100)
        }
    }

    static func chargeHistory() async -> [HistorySample] {
        await Task.detached(priority: .utility) { chargeHistorySync() }.value
    }

    static func lastUnpluggedDate() async -> Date? {
        await Task.detached(priority: .utility) { lastUnpluggedDateSync() }.value
    }
}
