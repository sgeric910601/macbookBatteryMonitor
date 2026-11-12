import Foundation

/// 一組快捷鍵和它自己的外觀與篩選：例如 Cmd+Tab 看全部視窗、Opt+Tab 只看目前桌面
struct SwitcherProfile: Equatable {
    var shortcut = SwitcherShortcut.commandTab
    var tileSize = SwitcherLayout.TileSize.medium
    var style = SwitcherStyle.thumbnails
    /// 依視窗數量放大或縮小，剛好填滿可用空間
    var autoSize = false
    /// 例外清單在 SwitcherSettings 裡，所有快捷鍵共用，這裡的 excludedBundleIDs 不使用
    var filter = SwitcherFilter()

    init(shortcut: SwitcherShortcut = .commandTab) { self.shortcut = shortcut }

    /// 從儲存的字典讀回；任何欄位缺少或不合法都用預設值。快捷鍵不合法時回傳 nil
    init?(stored: [String: Any], fallbackShortcut: SwitcherShortcut? = nil) {
        let defaults = SwitcherProfile()
        func bool(_ key: String, _ fallback: Bool) -> Bool { stored[key] as? Bool ?? fallback }
        func choice<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            (stored[key] as? String).flatMap(T.init(rawValue:)) ?? fallback
        }
        var parsed: SwitcherShortcut?
        if let code = stored["keyCode"] as? Int, let hold = stored["hold"] as? Int, hold & ~0xF == 0 {
            let candidate = SwitcherShortcut(keyCode: Int64(code), hold: SwitcherShortcut.Modifiers(rawValue: hold))
            if candidate.isUsable { parsed = candidate }
        }
        guard let shortcut = parsed ?? fallbackShortcut else { return nil }
        self.shortcut = shortcut
        tileSize = choice("tileSize", defaults.tileSize)
        style = choice("style", defaults.style)
        autoSize = bool("autoSize", defaults.autoSize)
        filter.spaces = choice("spaces", defaults.filter.spaces)
        filter.screens = choice("screens", defaults.filter.screens)
        filter.order = choice("order", defaults.filter.order)
        filter.showMinimized = bool("showMinimized", defaults.filter.showMinimized)
        filter.showHidden = bool("showHidden", defaults.filter.showHidden)
        filter.showFullscreen = bool("showFullscreen", defaults.filter.showFullscreen)
        filter.showWindowlessApps = bool("showWindowlessApps", defaults.filter.showWindowlessApps)
        filter.groupApps = bool("groupApps", defaults.filter.groupApps)
    }

    var stored: [String: Any] {
        [
            "keyCode": Int(shortcut.keyCode), "hold": shortcut.hold.rawValue,
            "tileSize": tileSize.rawValue, "style": style.rawValue, "autoSize": autoSize, "spaces": filter.spaces.rawValue, "screens": filter.screens.rawValue,
            "order": filter.order.rawValue, "showMinimized": filter.showMinimized, "showHidden": filter.showHidden, "showFullscreen": filter.showFullscreen,
            "showWindowlessApps": filter.showWindowlessApps, "groupApps": filter.groupApps,
        ]
    }
}

/// 視窗切換的所有設定。存成只含字串、數字、布林、字串陣列與字典陣列的字典（UserDefaults 可以直接存），
/// 讀回來時每個欄位都重新驗證，壞掉或被改過的值退回預設，不會讓切換器進入不能用的狀態
struct SwitcherSettings: Equatable {
    var vimKeys = false
    /// 放開修飾鍵後切換器保持開啟，按 Return 確認、Esc 取消
    var keepOpenAfterRelease = false
    var excludedBundleIDs: Set<String> = []
    /// 切換器顯示時擷取最新的視窗畫面（系統會在擷取時顯示「正在擷取你的畫面」）；
    /// 關閉時只用之前擷取過的快取，不擷取
    var refreshThumbnails = true
    /// 選到某個視窗時，在它原本的位置顯示它的畫面（在切換器後面）；需要擷取畫面，所以也受 refreshThumbnails 限制
    var previewSelectedWindow = false
    /// 切換器淡入、選取框移動的過渡動畫；系統開了「減少動態效果」時一律不做
    var animations = true
    /// 1 到 maxProfiles 組，第一組是主要的；順序就是按鍵判斷的順序
    var profiles = [SwitcherProfile()]

    static let maxExcludedApps = 200
    static let maxProfiles = 9

    /// 例外清單用的 Bundle ID：英數字、點、減號、底線，開頭是英數字
    static func isValidBundleID(_ id: String) -> Bool {
        guard (1...255).contains(id.utf8.count), let first = id.unicodeScalars.first, first.isASCII, first.properties.isAlphabetic || ("0"..."9").contains(Character(first)) else { return false }
        return id.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains(Character($0)) || $0 == "." || $0 == "-" || $0 == "_") }
    }

    /// 這組快捷鍵實際使用的篩選（含共用的例外清單）
    func filter(forProfile index: Int) -> SwitcherFilter {
        var filter = profiles.indices.contains(index) ? profiles[index].filter : SwitcherFilter()
        filter.excludedBundleIDs = excludedBundleIDs
        return filter
    }

    /// 已經被其他組使用的快捷鍵（不含 index 自己）
    func isTaken(_ shortcut: SwitcherShortcut, except index: Int?) -> Bool {
        profiles.enumerated().contains { $0.offset != index && $0.element.shortcut == shortcut }
    }

    init() {}

    /// 從儲存的字典讀回；任何欄位缺少或不合法都用預設值。
    /// 舊版把單一快捷鍵的欄位直接放在最外層，沒有 profiles 時就把它們當成第一組
    init(stored: [String: Any]) {
        vimKeys = stored["vimKeys"] as? Bool ?? false
        keepOpenAfterRelease = stored["keepOpen"] as? Bool ?? false
        refreshThumbnails = stored["refreshThumbnails"] as? Bool ?? true
        previewSelectedWindow = stored["previewSelectedWindow"] as? Bool ?? false
        animations = stored["animations"] as? Bool ?? true
        let excluded = (stored["excluded"] as? [String] ?? []).filter(Self.isValidBundleID)
        excludedBundleIDs = Set(excluded.prefix(Self.maxExcludedApps))
        var loaded: [SwitcherProfile] = []
        if let list = stored["profiles"] as? [[String: Any]] {
            for entry in list.prefix(Self.maxProfiles) {
                guard let profile = SwitcherProfile(stored: entry), !loaded.contains(where: { $0.shortcut == profile.shortcut }) else { continue }
                loaded.append(profile)
            }
        } else if let legacy = SwitcherProfile(stored: stored, fallbackShortcut: .commandTab) {
            loaded = [legacy]
        }
        profiles = loaded.isEmpty ? [SwitcherProfile()] : loaded
    }

    var stored: [String: Any] {
        ["vimKeys": vimKeys, "keepOpen": keepOpenAfterRelease, "refreshThumbnails": refreshThumbnails, "previewSelectedWindow": previewSelectedWindow, "animations": animations, "excluded": excludedBundleIDs.sorted(), "profiles": profiles.map(\.stored)]
    }
}
