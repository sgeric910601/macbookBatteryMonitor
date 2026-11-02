import AppKit
import Darwin
import Observation

/// 監聽中的連接埠（解析與判斷在 PortList）與結束程式。lsof 參數固定、不經過 shell，只看得到自己帳號的程式；
/// 打開網路面板或按「重新整理」時才讀。結束前一定先確認，送出訊號前再核對一次這個 PID 的擁有者與名稱（PID 可能被重複使用）
@MainActor
@Observable
final class PortManager {
    static let shared = PortManager()

    private(set) var listeners: [PortList.Listener] = []
    private(set) var loading = false

    func refresh() {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let output = Shell.runSync("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcnu"], timeout: 5) ?? ""
            let parsed = PortList.parse(output)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    PortManager.shared.listeners = parsed
                    PortManager.shared.loading = false
                }
            }
        }
    }

    /// 確認後送出 SIGTERM（讓程式有機會收尾）；擁有者或名稱和清單上的不一樣就不送
    func confirmTerminate(_ listener: PortList.Listener) {
        guard PortList.canTerminate(pid: listener.pid, uid: listener.uid, myUID: Int(getuid()), myPID: getpid()) else { return }
        let alert = NSAlert()
        alert.messageText = "結束「\(listener.command)」？"
        alert.informativeText = "它正在監聽連接埠 \(listener.port)（PID \(listener.pid)）。會先請它正常結束，還沒存的資料可能會不見。"
        alert.addButton(withTitle: "結束")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let owner = Self.owner(of: listener.pid), owner.uid == listener.uid, owner.name == listener.command else {
            refresh()
            return
        }
        kill(listener.pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { MainActor.assumeIsolated { PortManager.shared.refresh() } }
    }

    /// 這個 PID 現在的擁有者與程式名稱（lsof 的 c 欄位是 15 個字元以內的程式名稱，這裡同樣取 comm）
    static func owner(of pid: pid_t) -> (uid: Int, name: String)? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        let name = withUnsafeBytes(of: info.pbsi_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return (Int(info.pbsi_uid), name)
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
