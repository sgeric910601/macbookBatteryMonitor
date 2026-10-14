import AppKit
import CryptoKit
import Foundation
import Combine

/// 一鍵更新：從 GitHub Releases 下載新版，驗證後換掉目前的 App 並重新開啟。
/// Beta 測試版只有使用者按「檢查更新」時才會找，不會自動通知，安裝前另外確認（見 UpdateCard）
@MainActor
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case downloading(ReleaseInfo)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?

    /// 最近的 Release 清單（包含 Beta）；正式版只看 releases/latest 會漏掉 Beta
    static let releasesAPI = URL(string: "https://api.github.com/repos/sgeric910601/macbookBatteryMonitor/releases?per_page=20")!
    static let releasesPage = URL(string: "https://github.com/sgeric910601/macbookBatteryMonitor/releases/latest")!
    /// 自動檢查的間隔
    static let checkInterval: TimeInterval = 24 * 3600
    private static let lastCheckKey = "lastUpdateCheck"
    /// 上次發過通知（或手動檢查時已經看到）的新版本
    private static let notifiedKey = "lastNotifiedUpdate"

    /// 自動檢查發現新版本時呼叫，每個版本只呼叫一次；手動檢查時使用者已經看到，不呼叫
    var onNewRelease: ((ReleaseInfo) -> Void)?

    /// 執行中的版本（Beta 會帶序號）
    let current = AppVersion.current()
    /// 畫面上顯示的目前版本：1.7.1、1.8.0 beta 1
    var currentVersion: String { current.text }

    var available: ReleaseInfo? {
        switch state {
        case .available(let release), .downloading(let release): return release
        default: return nil
        }
    }

    /// 只有正式打包的 App 才能安裝（開發用的執行檔沒有 .app 可以換）
    var canInstall: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier == "com.kuan.batterymonitor"
    }

    init() {
        lastChecked = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
    }

    /// 自動檢查：距離上次超過一天才查；查不到不顯示錯誤
    func checkIfDue() {
        guard state == .idle || state == .upToDate else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.checkInterval { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        switch state {
        case .checking, .downloading, .installing: return
        default: break
        }
        state = .checking
        var request = URLRequest(url: Self.releasesAPI, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("macbookBatteryMonitor/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            lastChecked = Date()
            UserDefaults.standard.set(lastChecked, forKey: Self.lastCheckKey)
            // 舊系統版本：系統已升級到 macOS 14 以上時改裝主版本的通用版
            let mainSupported = ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0))
                && !Compat.forceMacOS12Paths
            let releases = UpdateLogic.releases(json: data, edition: AppEdition.current.rawValue, mainSupported: mainSupported)
            guard !releases.isEmpty else {
                state = userInitiated ? .failed("找不到新版的下載檔") : .idle
                return
            }
            let found = UpdateLogic.choose(releases, current: current)
            // Beta 只在手動檢查時列出，也不發通知
            if let beta = found.beta, found.stable == nil, userInitiated {
                state = .available(beta)
                return
            }
            guard let release = found.stable else {
                state = .upToDate
                return
            }
            state = .available(release)
            let defaults = UserDefaults.standard
            if UpdateLogic.shouldNotify(release.version, lastNotified: defaults.string(forKey: Self.notifiedKey)) {
                defaults.set(release.tag, forKey: Self.notifiedKey)
                if !userInitiated { onNewRelease?(release) }
            }
        } catch {
            state = userInitiated ? .failed("無法連線到 GitHub，請稍後再試") : .idle
        }
    }

    /// 下載、驗證、安裝；成功時 App 會結束並由安裝程序重新開啟新版
    func install() async {
        guard let release = available, canInstall else { return }
        let target = Bundle.main.bundleURL
        let folder = target.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path), FileManager.default.isWritableFile(atPath: target.path) else {
            state = .failed("App 所在位置沒有寫入權限，請到 GitHub 手動下載")
            return
        }
        state = .downloading(release)
        Self.removeStaleWorkFolders()
        do {
            let staged = try await Self.download(release)
            state = .installing
            try Self.launchInstaller(staged: staged, target: target)
            // 讓畫面先顯示「安裝中」再結束
            try? await Task.sleep(nanoseconds: 300_000_000)
            NSApp.terminate(nil)
        } catch let error as UpdateError {
            state = .failed(error.message)
        } catch {
            state = .failed("下載失敗：\(error.localizedDescription)")
        }
    }

    struct UpdateError: Error { let message: String }

    /// 之前中斷的更新（例如下載到一半 App 被結束）留下的暫存資料夾
    nonisolated private static func removeStaleWorkFolders() {
        let temp = FileManager.default.temporaryDirectory
        for name in (try? FileManager.default.contentsOfDirectory(atPath: temp.path)) ?? [] where name.hasPrefix("update-") {
            try? FileManager.default.removeItem(at: temp.appendingPathComponent(name))
        }
    }

    /// 下載 zip、比對 SHA-256、解壓並驗證內容，回傳準備好的新版 App 位置；失敗時清掉暫存資料夾
    nonisolated private static func download(_ release: ReleaseInfo) async throws -> URL {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            return try await downloadAndVerify(release, into: work)
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw error
        }
    }

    nonisolated private static func downloadAndVerify(_ release: ReleaseInfo, into work: URL) async throws -> URL {
        var request = URLRequest(url: release.assetURL, timeoutInterval: 120)
        request.setValue("macbookBatteryMonitor", forHTTPHeaderField: "User-Agent")
        let (temp, response) = try await URLSession.shared.download(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let final = response.url, UpdateLogic.isTrusted(final) else {
            throw UpdateError(message: "下載失敗：伺服器回應異常")
        }
        let zip = work.appendingPathComponent(release.assetName)
        try FileManager.default.moveItem(at: temp, to: zip)
        let data = try Data(contentsOf: zip)
        guard data.count > 0, data.count < 100_000_000 else { throw UpdateError(message: "下載的檔案大小異常") }

        // 有校驗檔就一定要對得上
        if let checksumURL = release.checksumURL {
            let (sums, _) = try await URLSession.shared.data(from: checksumURL)
            guard let expected = UpdateLogic.checksum(in: String(decoding: sums, as: UTF8.self), for: release.assetName) else {
                throw UpdateError(message: "校驗檔裡找不到這個下載檔")
            }
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else { throw UpdateError(message: "下載的檔案校驗不符，已取消更新") }
        }

        let unpacked = work.appendingPathComponent("unpacked")
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) == 0 else { throw UpdateError(message: "解壓縮失敗") }
        let app = unpacked.appendingPathComponent("macbookBatteryMonitor.app")
        // v1.7.1 起只有一個 App，系統監控是設定裡的開關，不再比對版本別
        // 版本號與 Beta 序號都要和 Release 的 tag 一致（正式版的 App 不能帶 Beta 序號）
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "com.kuan.batterymonitor",
              (info["CFBundleShortVersionString"] as? String).flatMap(UpdateLogic.version) == release.version,
              AppVersion.current(info: info).beta == release.beta else {
            throw UpdateError(message: "下載的 App 與這個 App 或版本號不符")
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) == 0 else {
            throw UpdateError(message: "新版 App 的簽章驗證失敗")
        }
        return app
    }

    /// 寫一個小腳本：等這個 App 結束後換上新版（換不過去就放回原本的版本）並重新開啟
    nonisolated private static func launchInstaller(staged: URL, target: URL) throws {
        let script = staged.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("install.sh")
        try """
        #!/bin/sh
        pid="$1"; target="$2"; staged="$3"
        i=0
        while kill -0 "$pid" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
        backup="${target%.app}.previous.app"
        rm -rf "$backup"
        if mv "$target" "$backup" && mv "$staged" "$target"; then
          rm -rf "$backup"
        elif [ ! -d "$target" ] && [ -d "$backup" ]; then
          mv "$backup" "$target"
        fi
        xattr -dr com.apple.quarantine "$target" 2>/dev/null
        open "$target"
        rm -rf "$(dirname "$0")"
        """.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), target.path, staged.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// 開發用快照：直接設定狀態，檢查各狀態的版面
    func loadPreview(_ state: State) { self.state = state }

    nonisolated private static func run(_ path: String, _ arguments: [String]) -> Int32 {
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
