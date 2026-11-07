import AppKit
import Darwin
import Observation

/// 監聽中的連接埠（解析與判斷在 PortList）與結束程式。lsof 參數固定、不經過 shell，只看得到自己帳號的程式；
/// 打開網路面板或按「重新整理」時才讀。結束前一定先確認，送出訊號前再核對一次這個 PID 的擁有者、名稱與啟動時間
/// （PID 可能被另一個同名程式重複使用，例如 node、python3）
@MainActor
@Observable
final class PortManager {
    static let shared = PortManager()

    private(set) var listeners: [PortList.Listener] = []
    private(set) var loading = false
    /// 列出時每個 PID 的啟動時間；送出訊號前比對，不一樣就是別的程式用了同一個 PID
    @ObservationIgnored private var startTimes: [Int32: UInt64] = [:]

    func refresh() {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let output = Shell.runSync("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcnu"], timeout: 5) ?? ""
            let parsed = PortList.parse(output)
            let starts = Dictionary(parsed.compactMap { listener in Self.owner(of: listener.pid).map { (listener.pid, $0.started) } }) { first, _ in first }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    PortManager.shared.listeners = parsed
                    PortManager.shared.startTimes = starts
                    PortManager.shared.loading = false
                }
            }
        }
    }

    /// 確認後送出 SIGTERM（讓程式有機會收尾）；擁有者或名稱和清單上的不一樣就不送
    func confirmTerminate(_ listener: PortList.Listener) {
        guard PortList.canTerminate(pid: listener.pid, uid: listener.uid, myUID: Int(getuid()), myPID: getpid()),
              // 確認對話框開著時清單可能重新整理過：用列出這一筆時記下的啟動時間比對
              let expectedStart = startTimes[listener.pid] else { return }
        let alert = NSAlert()
        alert.messageText = "結束「\(listener.command)」？"
        alert.informativeText = "它正在監聽連接埠 \(listener.port)（PID \(listener.pid)）。會先請它正常結束，還沒存的資料可能會不見。"
        alert.addButton(withTitle: "結束")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let owner = Self.owner(of: listener.pid), owner.uid == listener.uid, owner.name == listener.command,
              owner.started == expectedStart else {
            refresh()
            return
        }
        if kill(listener.pid, SIGTERM) != 0 {
            let alreadyGone = errno == ESRCH
            let failed = NSAlert()
            failed.messageText = "無法結束「\(listener.command)」"
            failed.informativeText = alreadyGone ? "它已經結束了。" : "沒有權限結束這個程式。"
            failed.runModal()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { MainActor.assumeIsolated { PortManager.shared.refresh() } }
    }

    /// 這個 PID 現在的擁有者、程式名稱（lsof 的 c 欄位是 15 個字元以內的程式名稱，這裡同樣取 comm）與啟動時間（微秒）
    nonisolated static func owner(of pid: pid_t) -> (uid: Int, name: String, started: UInt64)? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let name = withUnsafeBytes(of: info.pbi_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return (Int(info.pbi_uid), name, info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec)
    }

    /// CPU／記憶體清單的「結束 App」：和 ⌘Q 一樣正常結束，App 有沒存的檔案時會照常詢問
    static func confirmQuit(appPath: String, name: String) {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == appPath && $0.processIdentifier != getpid() }
        guard !apps.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "結束「\(name)」？"
        alert.informativeText = "和按 ⌘Q 一樣請它正常結束；有沒存的檔案時 App 會照常詢問。"
        alert.addButton(withTitle: "結束")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for app in apps { app.terminate() }
    }
}
