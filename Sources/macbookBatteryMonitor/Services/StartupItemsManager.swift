import AppKit
import Foundation
import Observation

/// 讀取與管理登入時自動啟動的項目。外部程式一律用絕對路徑加參數陣列呼叫，不經過 shell
@MainActor
@Observable
final class StartupItemsManager {
    private(set) var items: [StartupItem] = []
    private(set) var loading = false
    /// 給使用者看的錯誤；不含內部細節
    var message: String?

    private nonisolated static let listScript = """
    on run
        set out to ""
        tell application "System Events"
            repeat with i in login items
                set out to out & (name of i) & tab & (path of i) & linefeed
            end repeat
        end tell
        return out
    end run
    """
    private nonisolated static let addScript = """
    on run argv
        tell application "System Events"
            make login item at end with properties {path:(item 1 of argv), hidden:false}
        end tell
    end run
    """
    /// 路徑以參數傳入並用 quoted form 包起來，不會被當成 shell 指令。
    /// 以管理員身分執行時多做三件事：垃圾桶必須是真正的資料夾（不是 symlink）、目的地已存在就不覆蓋（mv -n）、
    /// 搬完把檔案還給使用者，之後從垃圾桶放回去或清空都不用再輸入密碼
    private nonisolated static let adminMoveScript = """
    on run argv
        set src to quoted form of (item 1 of argv)
        set dst to quoted form of (item 2 of argv)
        set trashDir to quoted form of (item 3 of argv)
        set uid to quoted form of (item 4 of argv)
        do shell script "[ -d " & trashDir & " ] && [ ! -L " & trashDir & " ] && [ ! -e " & dst & " ] && /bin/mv -n " & src & " " & dst & " && /usr/sbin/chown " & uid & " " & dst with administrator privileges
    end run
    """
    private nonisolated static let removeScript = """
    on run argv
        tell application "System Events"
            delete (first login item whose path is (item 1 of argv))
        end tell
    end run
    """

    func reload() {
        guard !loading else { return }
        loading = true
        let started = Date()
        Task {
            let found = await Task.detached { Self.readAll() }.value
            items = found.items
            // 檔案可能在外面被刪掉或新增，詳細資訊的快取一起作廢
            details = [:]
            reloadCount += 1
            message = found.loginItemsFailed ? "讀不到登入項目。請到系統設定 > 隱私權與安全性 > 自動化，允許本 App 控制 System Events。" : nil
            loading = false
            // 等使用者在系統授權視窗操作時，設定視窗會被擠到後面；讀完把它帶回來
            if Date().timeIntervalSince(started) > 1.5 { bringSettingsToFront() }
        }
    }

    func setEnabled(_ item: StartupItem, _ enabled: Bool) {
        guard item.canToggle, let label = item.label, StartupItemLogic.isValidLabel(label) else { return }
        let domain = "gui/\(getuid())"
        Task {
            let ok = await Task.detached { () -> Bool in
                if enabled {
                    return Self.run("/bin/launchctl", ["enable", "\(domain)/\(label)"]).status == 0
                }
                let disabled = Self.run("/bin/launchctl", ["disable", "\(domain)/\(label)"]).status == 0
                // 已經在跑的順便停掉；沒載入時會失敗，忽略
                _ = Self.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
                return disabled
            }.value
            message = ok ? nil : "無法變更這個項目。"
            reloadAfterChange()
        }
    }

    func addLoginItem(path: String) {
        guard StartupItemLogic.isValidAppPath(path) else { message = "只能新增 .app 應用程式。"; return }
        Task {
            let ok = await Task.detached { Self.run("/usr/bin/osascript", ["-e", Self.addScript, path]).status == 0 }.value
            message = ok ? nil : "無法新增登入項目。請確認已允許控制 System Events。"
            reloadAfterChange()
        }
    }

    func remove(_ item: StartupItem) {
        guard item.canRemove else { return }
        if item.kind == .loginItem { removeLoginItem(item) } else { removeAgent(item) }
    }

    /// 程式已經不存在的代理程式：把 plist 搬到垃圾桶（可以放回去）。系統層級的要管理員密碼
    private func removeAgent(_ item: StartupItem) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard let plist = item.plistPath, let label = item.label, StartupItemLogic.isValidLabel(label),
              StartupItemLogic.isRemovablePlistPath(plist, home: home) else {
            message = "無法移除這個項目。"
            return
        }
        let isUser = item.kind == .userAgent
        let trash = "\(home)/.Trash"
        let uid = getuid()
        Task {
            let result = await Task.detached { () -> String? in
                // 確認之後檔案可能已經變了：重新讀一次，跟使用者看到的一致才動手
                guard let current = Self.readAgent(at: plist, kind: item.kind, disabled: []),
                      current.label == label, current.path == item.path, current.missing else {
                    return "這個項目剛剛已經變動，請重新整理後再試。"
                }
                if item.kind != .systemDaemon { _ = Self.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"]) }
                if isUser {
                    return (try? FileManager.default.trashItem(at: URL(fileURLWithPath: plist), resultingItemURL: nil)) != nil
                        ? nil : "無法移除這個項目。"
                }
                let name = (plist as NSString).lastPathComponent
                let target = trash + "/\(Int(Date().timeIntervalSince1970))-" + name
                // 密碼視窗可能開很久；使用者慢慢輸入時不要被當成逾時中斷
                let moved = Self.run("/usr/bin/osascript", ["-e", Self.adminMoveScript, plist, target, trash, String(uid)], timeout: 300)
                return moved.status == 0 ? nil : "無法移除這個項目（可能取消了密碼輸入）。"
            }.value
            message = result
            // 不管成功與否都重讀，用實際的檔案狀態更新畫面
            reloadAfterChange()
        }
    }

    func removeLoginItem(_ item: StartupItem) {
        guard item.canRemove, StartupItemLogic.isValidAppPath(item.path) else { return }
        Task {
            let ok = await Task.detached { Self.run("/usr/bin/osascript", ["-e", Self.removeScript, item.path]).status == 0 }.value
            message = ok ? nil : "無法移除登入項目。"
            reloadAfterChange()
        }
    }

    /// 展開某個項目的詳細資訊時才查，結果存起來
    private(set) var details: [String: StartupItemInfo] = [:]
    /// 每次重新讀取完成加一；詳細頁用它知道要重查
    private(set) var reloadCount = 0

    func loadDetails(_ item: StartupItem) {
        guard details[item.id] == nil else { return }
        Task {
            let info = await Task.detached { StartupItemInspector.inspect(item) }.value
            details[item.id] = info
        }
    }

    func openSystemSettings() {
        LoginItem.openSystemSettings()
    }

    /// 操作完成後呼叫：系統的授權與密碼視窗會搶走焦點，設定視窗會被擠到後面
    private func reloadAfterChange() {
        loading = false
        bringSettingsToFront()
        reload()
    }

    private func bringSettingsToFront() {
        NSApp.activate()
        NSApp.windows.first { $0.title == "設定" }?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 背景執行緒

    private nonisolated static func readAll() -> (items: [StartupItem], loginItemsFailed: Bool) {
        var result: [StartupItem] = []
        let listing = run("/usr/bin/osascript", ["-e", listScript])
        if listing.status == 0 { result += StartupItemLogic.parseLoginItems(listing.output) }
        let disabled = StartupItemLogic.parseDisabled(run("/bin/launchctl", ["print-disabled", "gui/\(getuid())"]).output)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders: [(String, StartupItem.Kind)] = [
            ("\(home)/Library/LaunchAgents", .userAgent),
            ("/Library/LaunchAgents", .systemAgent),
            ("/Library/LaunchDaemons", .systemDaemon),
        ]
        for (folder, kind) in folders {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            for name in names where name.hasSuffix(".plist") {
                if let item = readAgent(at: "\(folder)/\(name)", kind: kind, disabled: disabled) { result.append(item) }
            }
        }
        return (StartupItemLogic.sorted(result), listing.status != 0)
    }

    /// 只讀一般檔案、最多 1 MB：資料夾裡被放進 FIFO、/dev/zero 之類的連結時不會卡住
    private nonisolated static func readAgent(at path: String, kind: StartupItem.Kind, disabled: Set<String>) -> StartupItem? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size <= 1_000_000,
              let data = FileManager.default.contents(atPath: path) else { return nil }
        return StartupItemLogic.parseAgent(plist: data, fileName: (path as NSString).lastPathComponent, kind: kind,
                                           disabledLabels: disabled, plistPath: path)
    }

    /// 預設最多等 15 秒；System Events 等使用者授權時不會無限卡住
    private nonisolated static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return (-1, "") }
        // 邊跑邊讀輸出：輸出超過管線緩衝時，行程才不會卡在寫入而跑到逾時
        var data = Data()
        let reader = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            reader.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return (-1, "")
        }
        reader.wait()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
