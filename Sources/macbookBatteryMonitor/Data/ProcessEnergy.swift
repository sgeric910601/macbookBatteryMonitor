import Darwin
import Foundation

struct EnergyProcess: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// top 的 POWER 指標（相對耗電量，不是瓦數）
    var power: Double
    var appPath: String?
}

enum ProcessEnergy {
    private static let arguments = ["-l", "2", "-s", "1", "-o", "power", "-stats", "pid,command,power", "-n", "20"]

    static func sampleSync(limit: Int = 5) -> [EnergyProcess] {
        parse(Shell.runSync("/usr/bin/top", arguments), limit: limit)
    }

    /// top 會印兩次取樣，第一次的 POWER 都是 0，只用最後一段。
    /// 同一個 App 的 helper 程序（例如瀏覽器分頁）會合併到 App 名下。
    static func parse(_ output: String?, limit: Int) -> [EnergyProcess] {
        guard let output else { return [] }
        let lines = output.components(separatedBy: "\n")
        guard let header = lines.lastIndex(where: { $0.hasPrefix("PID") }) else { return [] }

        var groups: [String: EnergyProcess] = [:]
        for line in lines[(header + 1)...] {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3, let pid = Int32(parts[0]), let power = Double(parts[parts.count - 1]), power > 0 else { continue }
            let command = parts[1..<(parts.count - 1)].joined(separator: " ")
            if command == "top" { continue }

            let app = appBundle(for: pid)
            let key = app ?? "pid:\(pid)"
            let name = app.map { FileManager.default.displayName(atPath: $0) } ?? processName(pid) ?? command
            groups[key, default: EnergyProcess(id: key, name: name, power: 0, appPath: app)].power += power
        }
        return Array(groups.values.sorted { $0.power > $1.power }.prefix(limit))
    }

    /// 取最外層的 .app，讓 helper 歸到主程式
    private static func appBundle(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    private static func processName(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let name = String(cString: buffer)
        return name.isEmpty ? nil : name
    }
}
