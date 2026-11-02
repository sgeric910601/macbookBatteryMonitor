/// 監聽中的 TCP 連接埠（lsof -F 的輸出）與結束程式的安全判斷。只做解析與判斷，執行 lsof 與送訊號在 PortManager
enum PortList {
    struct Listener: Equatable, Identifiable {
        let pid: Int32
        let command: String
        let uid: Int
        let port: Int
        /// 只聽本機（127.0.0.1、::1），外面連不進來
        let localOnly: Bool
        var id: String { "\(pid)-\(port)" }
    }

    /// p 是 PID、c 是程式名稱、u 是使用者編號、n 是「位址:連接埠」。同一個程式同一個連接埠只列一次（IPv4 與 IPv6）
    static func parse(_ text: String) -> [Listener] {
        var pid: Int32?, command = "", uid = -1
        var seen: [String: Int] = [:]
        var result: [Listener] = []
        for line in text.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = Int32(value)
                command = ""
                uid = -1
            case "c": command = value
            case "u": uid = Int(value) ?? -1
            case "n":
                guard let pid, let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]), port > 0 else { continue }
                let host = String(value[..<colon])
                let local = host.hasPrefix("127.") || host == "[::1]" || host == "localhost"
                let key = "\(pid)-\(port)"
                if let index = seen[key] {
                    // 同一個連接埠只要有一個位址不是本機，就算外面連得進來
                    if !local, result[index].localOnly {
                        result[index] = Listener(pid: pid, command: result[index].command, uid: result[index].uid, port: port, localOnly: false)
                    }
                    continue
                }
                seen[key] = result.count
                result.append(Listener(pid: pid, command: command, uid: uid, port: port, localOnly: local))
            default: continue
            }
        }
        return result.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    /// 只能結束自己帳號的程式，不能結束 PID 1 以下（核心、launchd）或自己
    static func canTerminate(pid: Int32, uid: Int, myUID: Int, myPID: Int32) -> Bool {
        pid > 1 && pid != myPID && uid == myUID
    }
}
