import CoreGraphics

/// 視窗切換器看到的一個視窗。id 是 WindowServer 的視窗編號，全系統唯一，不用位置去對應
struct SwitcherWindow: Equatable, Identifiable {
    var id: UInt32
    var pid: Int32
    var appName: String
    var bundleID: String?
    var title: String
    var isMinimized = false
    var isHidden = false
    var isFullscreen = false
    /// 視窗所在的 Space（一般視窗只有一個；指定到所有桌面的視窗會有多個）
    var spaces: [UInt64] = []
    /// 視窗所在螢幕的識別碼；對不到時為 nil
    var displayID: String?
    /// 視窗不在目前顯示的 Space 時，它是該螢幕的第幾個 Space（從 1 算起）；在目前的 Space 或不明為 nil
    var spaceNumber: Int?
    /// 視窗的寬 ÷ 高：縮圖格子的寬度跟著它走，直式、寬螢幕的視窗才不會留一大塊空白
    var aspect: CGFloat = 1.6
    /// 視窗在螢幕上的位置與大小（左上角為原點的全域座標）；預覽選到的視窗用
    var frame = CGRect.zero
    /// App 還在執行但沒有開著的視窗（例如在「音樂」按紅色叉叉只會關掉視窗）：切過去時讓 App 重新開一個
    var isWindowless = false

    /// 沒有視窗的 App 沒有視窗編號：用不會和真正視窗編號（小於 2^31）重複的值
    static func windowlessID(pid: Int32) -> UInt32 { 0x8000_0000 | UInt32(truncatingIfNeeded: pid) }

    /// 視窗目前的特別狀態（沒有視窗、縮到最小、隱藏、全螢幕、在別的 Space）；一般視窗為 nil
    var statusText: String? {
        if isWindowless { return "沒有視窗" }
        if isMinimized { return "已縮到最小" }
        if isHidden { return "已隱藏" }
        if isFullscreen { return "全螢幕" }
        if let spaceNumber { return "Space \(spaceNumber)" }
        return nil
    }

    /// 給 VoiceOver 念的完整描述：App、標題（和 App 名稱不同才念）、狀態
    var accessibilityDescription: String {
        var parts = [appName.isEmpty ? displayTitle : appName]
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != appName { parts.append(trimmed) }
        if let statusText { parts.append(statusText) }
        return parts.joined(separator: "，")
    }

    /// 清單上顯示的名稱：沒有標題的視窗用 App 名稱
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }
}

/// 視窗最近用過的順序（MRU）。只有「使用者真的去了那個視窗」才會移動順序：App 切換、點擊、App 回報焦點視窗。
/// 視窗被關掉就移除；還沒看過的視窗排在後面，照畫面前後順序
struct WindowRecency: Equatable {
    private(set) var order: [UInt32] = []

    mutating func focus(_ id: UInt32) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
    }

    mutating func remove(_ id: UInt32) {
        order.removeAll { $0 == id }
    }

    /// 只保留還存在的視窗，避免記錄無限增長
    mutating func prune(keeping alive: Set<UInt32>) {
        order.removeAll { !alive.contains($0) }
    }

    /// stacking 是系統給的畫面前後順序（由前到後），用來排還沒有最近使用記錄的視窗
    func sorted(_ windows: [SwitcherWindow], stacking: [UInt32] = []) -> [SwitcherWindow] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let depth = Dictionary(stacking.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let keyed = windows.enumerated().map { index, window -> (group: Int, order: Int, index: Int) in
            if let r = rank[window.id] { return (0, r, index) }
            if let d = depth[window.id] { return (1, d, index) }
            return (2, index, index)
        }
        return keyed.sorted { ($0.group, $0.order, $0.index) < ($1.group, $1.order, $1.index) }.map { windows[$0.index] }
    }
}

/// WindowServer 對一個視窗回報的原始欄位（一次批次查詢取得，不用問 App，所以 App 忙碌也不會卡住）
struct WindowServerWindow: Equatable {
    var id: UInt32
    var pid: Int32
    var attributes: UInt64
    var tags: UInt64
    var level: Int32
    var spaceTypeMask: UInt64
    var alpha: Float
    /// 附屬關係：對話框（sheet）和子視窗會指向它們的主視窗；一般視窗與原生分頁是 0
    var parent: UInt32
    var frame: CGRect
    var title: String
}

/// 哪些 WindowServer 視窗是使用者能切過去的「視窗」，哪些是幻影（畫在系統裡、但 App 不打算給人看）。
/// 位元的意義是對照實際視窗狀態逆向得來（macOS 15、26、27 實測相同），任何一項在未來的系統改變都要重新驗證
enum WindowAdmission {
    /// attributes：視窗已排進畫面（ordered-in）。縮到 Dock、App 隱藏、換到別的 Space、正在關閉都會清掉它
    static let orderedInAttribute: UInt64 = 0x2
    /// tags：正好在視窗縮到 Dock 時設起
    static let minimizedTag: UInt64 = 1 << 60
    /// tags：視窗所屬的 App 被隱藏（Cmd+H）
    static let hiddenTag: UInt64 = 1 << 39
    /// spaceTypeMask：視窗在全螢幕的 Space
    static let fullscreenSpaceMask: UInt64 = 0x20

    enum Verdict: Equatable {
        case admit
        /// 有資料、但不是使用者看得到的視窗：Electron 的 show:false、透明度 0 的提醒、原生分頁的背景分頁
        case phantom
        /// 根本不是切換的目標：附屬視窗、浮動面板與 HUD、輔助用的小表面
        case notAWindow
    }

    static func isOrderedIn(_ w: WindowServerWindow) -> Bool { w.attributes & orderedInAttribute != 0 }
    static func isMinimized(_ w: WindowServerWindow) -> Bool { w.tags & minimizedTag != 0 }
    static func isAppHidden(_ w: WindowServerWindow) -> Bool { w.tags & hiddenTag != 0 }
    static func isFullscreen(_ w: WindowServerWindow) -> Bool { w.spaceTypeMask & fullscreenSpaceMask != 0 }

    /// spaces 是視窗所屬的 Space，currentSpaces 是各螢幕目前顯示的 Space
    static func verdict(_ w: WindowServerWindow, spaces: [UInt64], currentSpaces: Set<UInt64>) -> Verdict {
        guard w.id != 0, w.parent == 0, w.level == 0,
              SwitcherFilter.isRealWindow(size: w.frame.size, layer: Int(w.level)) else { return .notAWindow }
        guard w.alpha > 0 else { return .phantom }
        if isOrderedIn(w) || isMinimized(w) || isAppHidden(w) { return .admit }
        // 沒排進畫面、也不是縮小或隱藏：在別的 Space 才是真的視窗；還在目前的 Space 或沒有 Space 就是幻影
        let elsewhere = !spaces.isEmpty && currentSpaces.isDisjoint(with: spaces)
        return elsewhere ? .admit : .phantom
    }
}

/// 要列出哪些視窗
struct SwitcherFilter: Equatable {
    enum Screens: String, CaseIterable { case all, active }
    enum Spaces: String, CaseIterable { case all, current }
    enum Order: String, CaseIterable { case recentlyUsed, appName }

    var screens = Screens.all
    var spaces = Spaces.all
    var showMinimized = true
    var showHidden = true
    var showFullscreen = true
    /// 列出還在執行但沒有視窗的 App
    var showWindowlessApps = true
    var excludedBundleIDs: Set<String> = []
    /// 同一個 App 只留一個視窗（最近用過的那個）
    var groupApps = false
    var order = Order.recentlyUsed

    struct Context: Equatable {
        /// 每個螢幕各有一個目前顯示的 Space
        var currentSpaces: Set<UInt64> = []
        var activeDisplay: String?
        var ownPID: Int32 = 0
    }

    /// windows 要已經照最近使用順序排好
    func apply(_ windows: [SwitcherWindow], context: Context) -> [SwitcherWindow] {
        var seenApps = Set<Int32>()
        var result = windows.filter { window in
            if window.pid == context.ownPID { return false }
            if let id = window.bundleID, excludedBundleIDs.contains(id) { return false }
            if !showMinimized, window.isMinimized { return false }
            if !showHidden, window.isHidden { return false }
            if !showFullscreen, window.isFullscreen { return false }
            if !showWindowlessApps, window.isWindowless { return false }
            if spaces == .current, !context.currentSpaces.isEmpty, !window.spaces.isEmpty, context.currentSpaces.isDisjoint(with: window.spaces) { return false }
            if screens == .active, let display = context.activeDisplay, let own = window.displayID, own != display { return false }
            return true
        }
        if groupApps { result = result.filter { seenApps.insert($0.pid).inserted } }
        if order == .appName {
            result = result.enumerated().sorted { a, b in
                let cmp = a.element.appName.localizedStandardCompare(b.element.appName)
                return cmp == .orderedSame ? a.offset < b.offset : cmp == .orderedAscending
            }.map(\.element)
        }
        return result
    }

    /// 太小的東西不是使用者看得到的視窗（App 的輔助表面，例如 2×66 像素）
    static func isRealWindow(size: CGSize, layer: Int) -> Bool {
        layer == 0 && size.width >= 100 && size.height >= 50
    }
}

/// 切換器開著時，作用在選到的視窗上的動作
enum SwitcherWindowAction: Equatable {
    case close, minimize, fullscreen, hide, quit
}

/// 一組快捷鍵：按住 hold 的修飾鍵，按 keyCode 開始並選下一個，加 Shift 往回
struct SwitcherShortcut: Equatable {
    struct Modifiers: OptionSet, Equatable {
        let rawValue: Int
        static let command = Modifiers(rawValue: 1)
        static let option = Modifiers(rawValue: 2)
        static let control = Modifiers(rawValue: 4)
        static let shift = Modifiers(rawValue: 8)
    }

    var keyCode: Int64
    /// 要按住的修飾鍵，不含 Shift（Shift 用來往回）；不可以是空的，否則一般打字會被攔
    var hold: Modifiers

    static let commandTab = SwitcherShortcut(keyCode: 48, hold: .command)

    /// 修飾鍵本身的按鍵代碼（左右 Shift、Control、Option、Command、Caps Lock、Fn）：不能當作觸發鍵
    static let modifierKeyCodes: Set<Int64> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    /// 可以接受的快捷鍵：一定要按住修飾鍵（否則一般打字會被攔）、Shift 保留給往回、觸發鍵不是修飾鍵，
    /// 並避開系統保留的強制結束視窗（Command+Option+Esc 與加上 Shift、Control 的組合）
    var isUsable: Bool {
        guard !hold.isEmpty, !hold.contains(.shift), (0...127).contains(keyCode), !Self.modifierKeyCodes.contains(keyCode) else { return false }
        return !(keyCode == 53 && hold.isSuperset(of: [.command, .option]))
    }

    private static let keyNames: [Int64: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "⌫", 53: "⎋", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
        100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    /// 顯示用的名稱，例如「⌘ Tab」「⌃⌥ `」
    var displayName: String {
        var symbols = ""
        if hold.contains(.control) { symbols += "⌃" }
        if hold.contains(.option) { symbols += "⌥" }
        if hold.contains(.command) { symbols += "⌘" }
        return symbols + " " + (Self.keyNames[keyCode] ?? "按鍵 \(keyCode)")
    }
}

/// 視窗切換的按鍵判斷，在攔截事件的執行緒上使用。
/// 開始：按住某組快捷鍵的修飾鍵再按它的按鍵；結束：放開修飾鍵就切過去。
/// 事件可能遺失（放開修飾鍵的事件沒收到）：切換中收到任何按鍵時發現修飾鍵已經不在，就先結束再處理那個按鍵
struct SwitcherKeys {
    enum Event { case keyDown, keyUp, flagsChanged }
    enum Action: Equatable {
        case none
        /// 用第 slot 組快捷鍵開始切換，delta 是第一步：下一個（1）或上一個（-1）
        case start(slot: Int, delta: Int)
        /// 選下一個（1）或上一個（-1）
        case step(Int)
        /// 在格狀版面上移動：dx 左右、dy 上下（往下為正）
        case move(dx: Int, dy: Int)
        case commit
        case cancel
        /// 放開了修飾鍵，但設定是保持開啟：切換器留著，等 Return 確認、Esc 取消或點選
        case release
        case window(SwitcherWindowAction)
    }

    static let escape: Int64 = 53
    static let left: Int64 = 123, right: Int64 = 124, down: Int64 = 125, up: Int64 = 126
    private static let vimLeft: Int64 = 4, vimDown: Int64 = 38, vimUp: Int64 = 40, vimRight: Int64 = 37
    private static let windowKeys: [Int64: SwitcherWindowAction] = [13: .close, 46: .minimize, 3: .fullscreen, 4: .hide, 12: .quit]

    static let returnKeys: Set<Int64> = [36, 76]

    var shortcuts: [SwitcherShortcut]
    var vimKeys = false
    /// 放開修飾鍵就切過去（預設）；關閉時切換器保持開啟
    var releaseCommits = true
    /// 目前切換中是第幾組快捷鍵
    private(set) var activeSlot: Int?
    /// 保持開啟模式下，修飾鍵已經放開、切換器留著等待確認
    private(set) var sticky = false
    private var swallowedDown = Set<Int64>()

    init(shortcuts: [SwitcherShortcut] = [.commandTab], vimKeys: Bool = false, releaseCommits: Bool = true) {
        self.shortcuts = shortcuts.filter(\.isUsable)
        self.vimKeys = vimKeys
        self.releaseCommits = releaseCommits
    }

    var active: Bool { activeSlot != nil }

    /// 回傳要不要攔下這個事件（不交給其他 App 與系統），以及要做的事
    mutating func handle(_ event: Event, keyCode: Int64, modifiers: SwitcherShortcut.Modifiers) -> (swallow: Bool, action: Action) {
        switch event {
        case .flagsChanged:
            guard let slot = activeSlot, !sticky, !modifiers.isSuperset(of: shortcuts[slot].hold) else { return (false, .none) }
            guard releaseCommits else {
                sticky = true
                return (false, .release)
            }
            return (false, finish(.commit))
        case .keyUp:
            return (swallowedDown.remove(keyCode) != nil, .none)
        case .keyDown:
            return keyDown(keyCode, modifiers)
        }
    }

    private mutating func keyDown(_ keyCode: Int64, _ modifiers: SwitcherShortcut.Modifiers) -> (swallow: Bool, action: Action) {
        let held = modifiers.subtracting(.shift)
        if let slot = shortcuts.firstIndex(where: { $0.keyCode == keyCode && $0.hold == held }) {
            let delta = modifiers.contains(.shift) ? -1 : 1
            let continuing = activeSlot == slot
            activeSlot = slot
            sticky = false
            swallowedDown.insert(keyCode)
            return (true, continuing ? .step(delta) : .start(slot: slot, delta: delta))
        }
        guard let slot = activeSlot else { return (false, .none) }
        // 放開修飾鍵的事件遺失了：先切過去，這個按鍵照常交出去（保持開啟模式本來就不按著修飾鍵）
        guard sticky || modifiers.isSuperset(of: shortcuts[slot].hold) else { return (false, finish(.commit)) }
        let action: Action
        switch keyCode {
        case _ where sticky && Self.returnKeys.contains(keyCode):
            swallowedDown.insert(keyCode)
            return (true, finish(.commit))
        case _ where sticky && keyCode == shortcuts[slot].keyCode:
            swallowedDown.insert(keyCode)
            return (true, .step(modifiers.contains(.shift) ? -1 : 1))
        case Self.escape:
            swallowedDown.insert(keyCode)
            return (true, finish(.cancel))
        case Self.left: action = .move(dx: -1, dy: 0)
        case Self.right: action = .move(dx: 1, dy: 0)
        case Self.up: action = .move(dx: 0, dy: -1)
        case Self.down: action = .move(dx: 0, dy: 1)
        case Self.vimLeft where vimKeys: action = .move(dx: -1, dy: 0)
        case Self.vimRight where vimKeys: action = .move(dx: 1, dy: 0)
        case Self.vimUp where vimKeys: action = .move(dx: 0, dy: -1)
        case Self.vimDown where vimKeys: action = .move(dx: 0, dy: 1)
        default:
            guard let window = Self.windowKeys[keyCode] else { return (false, .none) }
            action = .window(window)
        }
        swallowedDown.insert(keyCode)
        return (true, action)
    }

    private mutating func finish(_ action: Action) -> Action {
        activeSlot = nil
        sticky = false
        return action
    }
}

/// 切換器的呈現方式
enum SwitcherStyle: String, CaseIterable {
    /// 視窗縮圖，格子寬度跟著視窗的長寬比
    case thumbnails
    /// 只有 App 圖示（像 Dock），選到的那個下方顯示標題
    case appIcons
    /// 精簡的標題列表，一列一個視窗
    case titles
}

/// 版面：決定每個視窗的格子多大、怎麼排，整體放不下就縮小
enum SwitcherLayout {
    enum TileSize: String, CaseIterable {
        case small, medium, large

        /// 縮圖區的高度
        var thumbnailHeight: CGFloat {
            switch self {
            case .small: return 100
            case .medium: return 140
            case .large: return 200
            }
        }

        /// App 圖像樣式的圖示邊長
        var iconSize: CGFloat {
            switch self {
            case .small: return 48
            case .medium: return 64
            case .large: return 88
            }
        }

        /// 標題列表樣式一列的高度
        var rowHeight: CGFloat {
            switch self {
            case .small: return 30
            case .medium: return 36
            case .large: return 44
            }
        }
    }

    struct Grid: Equatable {
        /// 每一列有哪些視窗（索引），由上到下、由左到右
        var rows: [[Int]]
        /// 每個視窗的格子寬度，索引對應視窗
        var widths: [CGFloat]
        var tileHeight: CGFloat
        var thumbnailHeight: CGFloat
        /// 縮到最小還是放不下：需要捲動
        var scrolls: Bool
        var style = SwitcherStyle.thumbnails
        var spacing = SwitcherLayout.spacing

        static let empty = Grid(rows: [], widths: [], tileHeight: 0, thumbnailHeight: 0, scrolls: false)

        var count: Int { widths.count }
    }

    static let spacing: CGFloat = 12
    static let listSpacing: CGFloat = 4
    static let padding: CGFloat = 16
    /// 格子左右與上下的內縮
    static let tilePadding: CGFloat = 8
    /// 標題列高度
    static let titleHeight: CGFloat = 34
    /// 縮圖寬度的範圍（相對於縮圖高度）：太窄的視窗不會細得看不見，太寬的視窗不會霸占整列
    static let aspectRange: ClosedRange<CGFloat> = 0.55...2.4
    /// 標題至少要有的寬度
    static let minimumContentWidth: CGFloat = 110
    /// 縮小的下限（相對於原本大小）
    static let minimumScale: CGFloat = 0.6
    /// 自動調整大小：視窗少時最多放大到原本的幾倍，縮圖高度不超過這個值
    static let maximumAutoScale: CGFloat = 1.8
    static let maximumAutoThumbnailHeight: CGFloat = 360
    /// 標題列表的寬度上限
    static let maximumListWidth: CGFloat = 520
    /// App 圖像樣式的格子最小寬度與選中標題的高度
    static let minimumIconTileWidth: CGFloat = 110
    static let iconTitleHeight: CGFloat = 22

    static func tileWidth(aspect: CGFloat, thumbnailHeight: CGFloat) -> CGFloat {
        let clamped = min(max(aspect, aspectRange.lowerBound), aspectRange.upperBound)
        return max(clamped * thumbnailHeight, minimumContentWidth) + 2 * tilePadding
    }

    /// 依樣式排版。autoSize 開啟時視窗少會放大、視窗多會縮小，剛好填滿可用空間；關閉時從原本大小開始，放不下才縮小
    static func layout(style: SwitcherStyle, aspects: [CGFloat], available: CGSize, size: TileSize, autoSize: Bool = false) -> Grid {
        switch style {
        case .thumbnails: return grid(aspects: aspects, available: available, size: size, autoSize: autoSize)
        case .appIcons: return iconGrid(count: aspects.count, available: available, size: size, autoSize: autoSize)
        case .titles: return listGrid(count: aspects.count, available: available, size: size)
        }
    }

    /// 從大到小試每個比例，第一個放得下的就用；縮到下限還放不下就用下限並要求捲動
    private static func fit(autoSize: Bool, baseHeight: CGFloat, usableHeight: CGFloat, build: (CGFloat) -> (grid: Grid, height: CGFloat)) -> Grid {
        let cap = autoSize ? min(maximumAutoScale, maximumAutoThumbnailHeight / max(baseHeight, 1)) : 1
        var scale = max(cap, minimumScale)
        while true {
            let attempt = build(scale)
            let fits = attempt.height <= usableHeight
            if fits || scale <= minimumScale {
                var grid = attempt.grid
                grid.scrolls = !fits
                return grid
            }
            scale = max(minimumScale, scale - 0.05)
        }
    }

    static func grid(aspects: [CGFloat], available: CGSize, size: TileSize, autoSize: Bool = false) -> Grid {
        guard !aspects.isEmpty, available.width > 0, available.height > 0 else { return .empty }
        let usableWidth = available.width - 2 * padding
        let usableHeight = available.height - 2 * padding
        return fit(autoSize: autoSize, baseHeight: size.thumbnailHeight, usableHeight: usableHeight) { scale in
            let thumbnail = size.thumbnailHeight * scale
            let tileHeight = thumbnail + titleHeight + 2 * tilePadding
            let widths = aspects.map { min(tileWidth(aspect: $0, thumbnailHeight: thumbnail), usableWidth) }
            let rows = pack(widths, usableWidth: usableWidth, spacing: spacing)
            let height = CGFloat(rows.count) * tileHeight + CGFloat(rows.count - 1) * spacing
            return (Grid(rows: rows, widths: widths, tileHeight: tileHeight, thumbnailHeight: thumbnail, scrolls: false), height)
        }
    }

    static func iconGrid(count: Int, available: CGSize, size: TileSize, autoSize: Bool = false) -> Grid {
        guard count > 0, available.width > 0, available.height > 0 else { return .empty }
        let usableWidth = available.width - 2 * padding
        let usableHeight = available.height - 2 * padding
        return fit(autoSize: autoSize, baseHeight: size.iconSize, usableHeight: usableHeight) { scale in
            let icon = size.iconSize * scale
            let width = min(max(icon + 2 * tilePadding + 24, minimumIconTileWidth), usableWidth)
            let tileHeight = icon + iconTitleHeight + 2 * tilePadding
            let rows = pack(Array(repeating: width, count: count), usableWidth: usableWidth, spacing: spacing)
            let height = CGFloat(rows.count) * tileHeight + CGFloat(rows.count - 1) * spacing
            return (Grid(rows: rows, widths: Array(repeating: width, count: count), tileHeight: tileHeight, thumbnailHeight: icon, scrolls: false,
                         style: .appIcons), height)
        }
    }

    static func listGrid(count: Int, available: CGSize, size: TileSize) -> Grid {
        guard count > 0, available.width > 0, available.height > 0 else { return .empty }
        let width = min(maximumListWidth, available.width - 2 * padding)
        let height = CGFloat(count) * size.rowHeight + CGFloat(count - 1) * listSpacing
        let fits = height <= available.height - 2 * padding
        return Grid(rows: (0..<count).map { [$0] }, widths: Array(repeating: width, count: count), tileHeight: size.rowHeight,
                    thumbnailHeight: 0, scrolls: !fits, style: .titles, spacing: listSpacing)
    }

    private static func pack(_ widths: [CGFloat], usableWidth: CGFloat, spacing: CGFloat) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var used: CGFloat = 0
        for (index, width) in widths.enumerated() {
            let needed = rows[rows.count - 1].isEmpty ? width : used + spacing + width
            if needed > usableWidth, !rows[rows.count - 1].isEmpty {
                rows.append([index])
                used = width
            } else {
                rows[rows.count - 1].append(index)
                used = needed
            }
        }
        return rows
    }

    /// 一列的寬度
    static func rowWidth(_ row: [Int], in grid: Grid) -> CGFloat {
        row.reduce(0) { $0 + grid.widths[$1] } + CGFloat(max(row.count - 1, 0)) * grid.spacing
    }

    /// 切換器整體的大小：最寬的一列加邊距，不超過可用空間
    static func panelSize(for grid: Grid, available: CGSize) -> CGSize {
        guard !grid.rows.isEmpty else { return .zero }
        let width = (grid.rows.map { rowWidth($0, in: grid) }.max() ?? 0) + 2 * padding
        let height = CGFloat(grid.rows.count) * grid.tileHeight + CGFloat(grid.rows.count - 1) * grid.spacing + 2 * padding
        return CGSize(width: min(width, available.width), height: min(height, available.height))
    }

    /// 選下一個或上一個，到頭繞回另一頭
    static func step(from index: Int, delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + delta) % count + count) % count
    }

    /// 方向鍵移動：左右一格（到頭繞回），上下一列（選那一列裡水平位置最接近的，到頭繞回）
    static func move(from index: Int, dx: Int, dy: Int, in grid: Grid) -> Int {
        guard grid.count > 0 else { return 0 }
        if dx != 0 || dy == 0 { return step(from: index, delta: dx, count: grid.count) }
        guard let current = grid.rows.firstIndex(where: { $0.contains(index) }) else { return index }
        let target = ((current + dy) % grid.rows.count + grid.rows.count) % grid.rows.count
        let center = centerX(of: index, in: grid.rows[current], grid: grid)
        return grid.rows[target].min { abs(centerX(of: $0, in: grid.rows[target], grid: grid) - center) < abs(centerX(of: $1, in: grid.rows[target], grid: grid) - center) } ?? index
    }

    /// 某一格的中心，以整體置中的位置計算
    private static func centerX(of index: Int, in row: [Int], grid: Grid) -> CGFloat {
        let widest = grid.rows.map { rowWidth($0, in: grid) }.max() ?? 0
        var x = (widest - rowWidth(row, in: grid)) / 2
        for item in row {
            if item == index { return x + grid.widths[item] / 2 }
            x += grid.widths[item] + grid.spacing
        }
        return x
    }
}
