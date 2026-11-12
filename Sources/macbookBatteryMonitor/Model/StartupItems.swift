import Foundation

/// 登入時自動啟動的項目：登入項目（System Events）與 LaunchAgent / LaunchDaemon
struct StartupItem: Identifiable, Equatable {
    enum Kind: String {
        case loginItem
        case userAgent
        case systemAgent
        case systemDaemon

        var title: String {
            switch self {
            case .loginItem: return "登入項目"
            case .userAgent: return "使用者代理程式"
            case .systemAgent: return "系統代理程式"
            case .systemDaemon: return "系統常駐程式"
            }
        }
    }

    var id: String
    var name: String
    var path: String
    var kind: Kind
    /// LaunchAgent / LaunchDaemon 的 Label；登入項目沒有
    var label: String?
    /// 登入項目一定是啟用；LaunchAgent 看有沒有被 launchctl 停用
    var enabled: Bool
    /// LaunchAgent / LaunchDaemon 的 plist 位置；登入項目沒有
    var plistPath: String? = nil
    /// 指向的程式已經不存在（App 被刪掉但設定檔還在）
    var missing = false
    /// 本 App 自己的登入項目或備援代理程式：停用會把正在跑的自己停掉，只顯示
    var isOwn = false

    /// 圖示取自程式所在的 .app；不在 .app 裡時用程式本身
    var iconPath: String { StartupItemLogic.appBundlePath(of: path) ?? path }

    /// plist 的 Label 跟檔名一致。不一致的（可能冒用別的軟體的 Label）只顯示，不給開關或移除
    var labelMatchesFile: Bool {
        guard let plistPath, let label else { return true }
        return ((plistPath as NSString).lastPathComponent as NSString).deletingPathExtension == label
    }

    /// 只有使用者層級的第三方 LaunchAgent 能在這裡開關
    var canToggle: Bool {
        kind == .userAgent && !isOwn && labelMatchesFile && label.map { !$0.hasPrefix("com.apple.") } == true
    }

    /// 登入項目是 .app 就可移除；使用者代理程式只有在程式已經不存在時才給移除。系統層級的只列出
    var canRemove: Bool {
        guard !isOwn else { return false }
        if kind == .loginItem { return StartupItemLogic.isValidAppPath(path) }
        guard kind == .userAgent, missing, plistPath != nil, labelMatchesFile, let label else { return false }
        return !label.hasPrefix("com.apple.")
    }
}

enum StartupItemLogic {
    /// launchctl 的 Label 只接受這些字元，避免把奇怪的字串帶進參數
    static func isValidLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 200 else { return false }
        return label.unicodeScalars.allSatisfy { scalar in
            (scalar.value < 128) && (CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "-" || scalar == "_")
        }
    }

    /// 新增登入項目只接受絕對路徑的 .app
    static func isValidAppPath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path.hasSuffix(".app"), path.count <= 1024 else { return false }
        guard !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        return !path.split(separator: "/").contains("..")
    }

    /// 顯示名稱：路徑裡有 .app 就用 App 名稱，否則用 Label
    static func displayName(label: String, executable: String?) -> String {
        if let executable {
            for part in executable.split(separator: "/") where part.hasSuffix(".app") {
                return String(part.dropLast(4))
            }
        }
        return label
    }

    /// 真正要啟動的程式。用 `open` 開 App 的設定，目標是後面那個 .app，不是 open 本身
    static func realTarget(program: String?, arguments: [String]?) -> String? {
        let first = program ?? arguments?.first
        guard first == "/usr/bin/open", let arguments else { return first }
        let target = arguments.dropFirst().first { $0.hasPrefix("/") && $0.hasSuffix(".app") }
        return target ?? first
    }

    /// 路徑中第一個 .app 的完整路徑
    static func appBundlePath(of path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        var built = ""
        for part in path.split(separator: "/") {
            built += "/" + part
            if part.hasSuffix(".app") { return built }
        }
        return nil
    }

    /// 刪除代理程式 plist 只允許使用者 LaunchAgents 資料夾直接底下的 .plist
    static func isRemovablePlistPath(_ path: String, home: String) -> Bool {
        guard path.hasSuffix(".plist"), !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        let url = URL(fileURLWithPath: path)
        guard url.standardizedFileURL.path == path else { return false }
        return url.deletingLastPathComponent().path == home + "/Library/LaunchAgents"
    }

    /// 只有確定沒有這個檔案（ENOENT）才算程式不存在。外接磁碟沒接上、沒權限看的資料夾（EACCES）都不下結論
    static func isMissing(path: String, statError: Int32) -> Bool {
        guard path.hasPrefix("/"), path != "/Volumes", !path.hasPrefix("/Volumes/") else { return false }
        return statError == ENOENT
    }

    /// stat 失敗時的 errno；成功回傳 0。
    /// 找不到（ENOENT）但路徑本身或某一層存在的資料夾是符號連結時，目標可能只是在沒接上的外接磁碟：回傳 ESTALE，不算不存在
    static func statError(_ path: String) -> Int32 {
        var info = stat()
        if stat(path, &info) == 0 { return 0 }
        let error = errno
        guard error == ENOENT else { return error }
        // 找到最深一層存在的資料夾；下一層若是斷掉的符號連結，或解開連結後落在 /Volumes，目標可能在沒接上的磁碟
        var existing = "/"
        for component in path.split(separator: "/") {
            let next = existing == "/" ? "/" + component : existing + "/" + component
            guard stat(next, &info) == 0 else {
                if lstat(next, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK { return ESTALE }
                break
            }
            existing = next
        }
        let resolved = URL(fileURLWithPath: existing).resolvingSymlinksInPath().path
        return resolved == "/Volumes" || resolved.hasPrefix("/Volumes/") ? ESTALE : ENOENT
    }

    /// 本 App 自己的項目：Label 相同，或指向本 App 的 bundle
    static func isOwnItem(label: String?, path: String, ownLabel: String, ownBundlePath: String) -> Bool {
        if label == ownLabel { return true }
        // 解開符號連結再比，經過連結指到本 App 的也算
        let own = URL(fileURLWithPath: ownBundlePath).resolvingSymlinksInPath().standardizedFileURL.path
        guard path.hasPrefix("/") else { return false }
        let target = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        return target == own || target.hasPrefix(own + "/")
    }

    static func parseAgent(plist data: Data, fileName: String, kind: StartupItem.Kind, disabledLabels: Set<String>,
                           plistPath: String? = nil, statError: (String) -> Int32 = StartupItemLogic.statError) -> StartupItem? {
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = object as? [String: Any] else { return nil }
        let fallback = fileName.hasSuffix(".plist") ? String(fileName.dropLast(6)) : fileName
        let label = (dict["Label"] as? String) ?? fallback
        guard isValidLabel(label) else { return nil }
        let executable = realTarget(program: dict["Program"] as? String, arguments: dict["ProgramArguments"] as? [String])
        return StartupItem(id: "\(kind.rawValue):\(fileName)",
                           name: displayName(label: label, executable: executable),
                           path: executable ?? "",
                           kind: kind, label: label,
                           enabled: !disabledLabels.contains(label),
                           plistPath: plistPath,
                           missing: executable.map { isMissing(path: $0, statError: statError($0)) } ?? false)
    }

    /// osascript 的輸出：每行「名稱 TAB 路徑」
    static func parseLoginItems(_ output: String) -> [StartupItem] {
        // 同一個路徑可能登錄多次，id 加上順序才不會重複
        output.split(whereSeparator: \.isNewline).enumerated().compactMap { index, line in
            let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2, !fields[0].isEmpty else { return nil }
            let path = String(fields[1])
            return StartupItem(id: "loginItem:\(index):\(path)", name: String(fields[0]), path: path,
                               kind: .loginItem, label: nil, enabled: true)
        }
    }

    /// `launchctl print-disabled` 的輸出：`"label" => disabled`（舊版是 `=> true`）
    static func parseDisabled(_ output: String) -> Set<String> {
        var result = Set<String>()
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard value == "disabled" || value == "true" else { continue }
            let label = parts[0].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"")))
            if !label.isEmpty { result.insert(label) }
        }
        return result
    }

    /// 同種類先按名稱排序
    static func sorted(_ items: [StartupItem]) -> [StartupItem] {
        items.sorted {
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
