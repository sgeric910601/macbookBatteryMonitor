import AppKit
import Darwin

/// App 從哪裡執行。從 DMG 打開，或被 macOS 搬到暫存位置執行（App Translocation：帶著網路下載的隔離標記、
/// 沒用 Finder 搬過的 App）時，一鍵更新換不掉它、也不會加入開機自啟動，退出 DMG 後 App 還會結束。
/// 這時啟動時詢問，改從「應用程式」（或被搬走之前的位置）裡的那一份執行
enum AppLocation {
    enum Problem: Equatable {
        /// 從 DMG（唯讀的磁碟）打開
        case diskImage
        /// macOS 把它搬到暫存位置執行
        case translocated
    }

    static let applicationsURL = URL(fileURLWithPath: "/Applications/macbookBatteryMonitor.app")

    static func problem(for url: URL = Bundle.main.bundleURL) -> Problem? {
        if url.path.contains("/AppTranslocation/") { return .translocated }
        let readOnly = (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true
        if readOnly, url.path.hasPrefix("/Volumes/") { return .diskImage }
        return nil
    }

    /// 被搬到暫存位置執行時，原本的位置。Security 的 SecTranslocateCreateOriginalPathForURL 沒有公開標頭，執行時才找；找不到就是 nil
    static func originalURL(of url: URL = Bundle.main.bundleURL) -> URL? {
        typealias Function = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let symbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        guard let original = unsafeBitCast(symbol, to: Function.self)(url as CFURL, nil)?.takeRetainedValue() as URL?,
              original.standardizedFileURL.path != url.standardizedFileURL.path else { return nil }
        return original
    }

    /// 該改從哪裡執行：被搬到暫存位置時是原本的位置（找不到就當作在「應用程式」），從 DMG 打開時是「應用程式」
    static func preferredURL(for problem: Problem) -> URL {
        problem == .translocated ? (originalURL() ?? applicationsURL) : applicationsURL
    }

    static func isOurApp(_ url: URL) -> Bool {
        Bundle(url: url)?.bundleIdentifier == "com.kuan.batterymonitor"
    }

    /// 目標位置的 App 版本；沒有這個 App 時是 nil
    static func installedVersion(at url: URL) -> AppVersion? {
        guard isOurApp(url), let bundle = Bundle(url: url) else { return nil }
        return AppVersion.current(info: bundle.infoDictionary)
    }

    /// 從 DMG 打開、而目標沒有這個 App 或是比較舊的版本時，要先把執行中的這一版拷貝過去
    static func needsInstall(_ problem: Problem, at target: URL) -> Bool {
        problem == .diskImage && (installedVersion(at: target).map { $0 < AppVersion.current() } ?? true)
    }

    /// 啟動時檢查：有問題就詢問要不要改從「應用程式」執行；使用者同意而且已經安排好重新開啟時回傳 true（呼叫的地方接著結束 App）。
    /// 帶開發用參數（--selftest-… 等）啟動時不詢問
    @MainActor static func promptIfNeeded() -> Bool {
        guard let problem = problem(), !CommandLine.arguments.dropFirst().contains(where: { $0.hasPrefix("--") }) else { return false }
        let target = preferredURL(for: problem)
        let installed = installedVersion(at: target)
        let install = needsInstall(problem, at: target)
        let place = target.deletingLastPathComponent().path == "/Applications" ? "「應用程式」" : "原本的位置"

        let alert = NSAlert()
        switch problem {
        case .translocated:
            alert.messageText = "「\(AppEdition.appName)」正在從 macOS 的暫存位置執行"
            alert.informativeText = "這份 App 帶著從網路下載的隔離標記，又沒有用 Finder 搬過，macOS 就把它放在暫存位置執行，"
                + "一鍵更新與開機自啟動都無法使用。按「改從\(place)打開」會清掉它的隔離標記並重新打開，只需要做一次；"
                + "macOS 可能會再請你到「系統設定 → 隱私權與安全性」按一次「強制打開」。"
            alert.addButton(withTitle: "改從\(place)打開")
        case .diskImage:
            alert.messageText = "你打開的是 DMG 裡的「\(AppEdition.appName)」"
            alert.informativeText = install
                ? "從 DMG 執行時一鍵更新與開機自啟動都無法使用，退出 DMG 後 App 也會結束。按「安裝到應用程式並打開」會把這一版拷貝到「應用程式」\(installed == nil ? "" : "（取代原本較舊的版本）")，再從那裡打開。"
                : "從 DMG 執行時一鍵更新與開機自啟動都無法使用，退出 DMG 後 App 也會結束。「應用程式」裡已經有這個 App，改從那裡打開即可。"
            alert.addButton(withTitle: install ? "安裝到應用程式並打開" : "改從應用程式打開")
        }
        alert.addButton(withTitle: "以後再說")
        NSApp.activateCompat()
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        do {
            try relaunch(at: target, installing: install)
            return true
        } catch let error as LocationError {
            let failure = NSAlert()
            failure.messageText = "沒辦法改從\(place)打開"
            failure.informativeText = error.message
            failure.runModal()
            return false
        } catch {
            return false
        }
    }

    struct LocationError: Error { let message: String }

    /// 確認目標是這個 App 的憑證簽的、清掉隔離標記，安排這個 App 結束後從目標重新打開（只允許同時執行一份，所以要等這份結束）。
    /// installing：先把執行中的這一份拷貝過去（取代原本的）
    @MainActor static func relaunch(at target: URL, installing: Bool) throws {
        if installing {
            let staged = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).new")
            try? FileManager.default.removeItem(at: staged)
            guard run("/usr/bin/ditto", [Bundle.main.bundleURL.path, staged.path]) == 0 else {
                throw LocationError(message: "沒有權限寫入「應用程式」。請在 Finder 把 App 拖到「應用程式」，退出 DMG 後從那裡打開。")
            }
            if FileManager.default.fileExists(atPath: target.path) {
                guard isOurApp(target), (try? FileManager.default.trashItem(at: target, resultingItemURL: nil)) != nil else {
                    try? FileManager.default.removeItem(at: staged)
                    throw LocationError(message: "無法取代「應用程式」裡原本的 App。請在 Finder 把 App 拖到「應用程式」並選擇取代。")
                }
            }
            try FileManager.default.moveItem(at: staged, to: target)
        }
        // 不加 --strict：換過圖示顏色的 App 最上層有自訂圖示檔
        guard isOurApp(target), run("/usr/bin/codesign", ["--verify", "--deep", "-R", "=" + UpdateLogic.codeRequirement, target.path]) == 0 else {
            throw LocationError(message: "\(target.path) 不是這個 App 的正式版本，沒有改從那裡打開。")
        }
        guard run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", target.path]) == 0 else {
            throw LocationError(message: "沒有權限清掉 \(target.path) 的隔離標記。請在終端機執行：xattr -dr com.apple.quarantine \"\(target.path)\"")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "i=0; while kill -0 \"$0\" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done; open \"$1\"",
                             String(ProcessInfo.processInfo.processIdentifier), target.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private static func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
