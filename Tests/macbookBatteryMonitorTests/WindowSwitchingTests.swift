import CoreGraphics

final class WindowSwitchingTests {
    private func window(_ id: UInt32, pid: Int32 = 1, app: String = "App", bundle: String? = nil, title: String = "",
                        spaces: [UInt64] = [1], display: String? = "A", minimized: Bool = false, hidden: Bool = false,
                        fullscreen: Bool = false) -> SwitcherWindow {
        SwitcherWindow(id: id, pid: pid, appName: app, bundleID: bundle, title: title, isMinimized: minimized, isHidden: hidden,
                       isFullscreen: fullscreen, spaces: spaces, displayID: display)
    }

    private func ids(_ windows: [SwitcherWindow]) -> [UInt32] { windows.map(\.id) }

    // MARK: 最近使用順序

    func testRecencyOnlyMovesOnRealFocus() {
        var recency = WindowRecency()
        let all = [window(1), window(2), window(3)]
        recency.focus(2)
        recency.focus(3)
        recency.focus(2)
        XCTAssertEqual(ids(recency.sorted(all)), [2, 3, 1])
        // 關掉的視窗從記錄移除，不會留下空位
        recency.remove(3)
        XCTAssertEqual(ids(recency.sorted(all)), [2, 1, 3])
        recency.prune(keeping: [1])
        XCTAssertEqual(recency.order, [])
    }

    func testRecencyFallsBackToStackingThenInputOrder() {
        var recency = WindowRecency()
        recency.focus(5)
        let all = [window(1), window(2), window(3), window(5)]
        // 5 有記錄排最前；沒記錄的照畫面前後順序（3 在 2 前面），畫面上沒有的（1）排最後
        XCTAssertEqual(ids(recency.sorted(all, stacking: [3, 2])), [5, 3, 2, 1])
        XCTAssertEqual(ids(WindowRecency().sorted(all)), [1, 2, 3, 5])
    }

    // MARK: 篩選

    func testFilters() {
        let all = [window(1, pid: 1, bundle: "com.example.a", spaces: [1]),
                   window(2, pid: 1, bundle: "com.example.a", spaces: [2]),
                   window(3, pid: 2, bundle: "com.example.b", spaces: [1], display: "B", minimized: true),
                   window(4, pid: 3, bundle: "com.example.c", spaces: [1], hidden: true),
                   window(5, pid: 4, bundle: "com.example.d", spaces: [1], fullscreen: true),
                   window(6, pid: 99, bundle: "com.example.self", spaces: [1])]
        let context = SwitcherFilter.Context(currentSpaces: [1], activeDisplay: "A", ownPID: 99)
        // 預設：只看目前的 Space，自己的視窗不列
        XCTAssertEqual(ids(SwitcherFilter(spaces: .current).apply(all, context: context)), [1, 3, 4, 5])
        var filter = SwitcherFilter()
        XCTAssertEqual(ids(filter.apply(all, context: context)), [1, 2, 3, 4, 5])
        filter.screens = .active
        XCTAssertEqual(ids(filter.apply(all, context: context)), [1, 2, 4, 5])
        filter = SwitcherFilter(spaces: .current, showMinimized: false, showHidden: false, showFullscreen: false)
        XCTAssertEqual(ids(filter.apply(all, context: context)), [1])
        filter = SwitcherFilter(excludedBundleIDs: ["com.example.a"])
        XCTAssertEqual(ids(filter.apply(all, context: context)), [3, 4, 5])
        // 同一個 App 只留最近用過的那個視窗
        filter = SwitcherFilter(spaces: .all, groupApps: true)
        XCTAssertEqual(ids(filter.apply(all, context: context)), [1, 3, 4, 5])
        // 依 App 名稱排序：名稱相同時保持原本順序
        let named = [window(1, app: "Zeta"), window(2, app: "alpha"), window(3, app: "Alpha")]
        filter = SwitcherFilter(order: .appName)
        XCTAssertEqual(ids(filter.apply(named, context: context)), [2, 3, 1])
    }

    func testFilterCurrentSpaceOfEveryDisplay() {
        // 兩個螢幕各自顯示 Space 1 和 5：兩邊看得到的視窗都算「目前」
        let all = [window(1, spaces: [1]), window(2, spaces: [5]), window(3, spaces: [9]), window(4, spaces: [1, 9])]
        let context = SwitcherFilter.Context(currentSpaces: [1, 5], activeDisplay: nil)
        XCTAssertEqual(ids(SwitcherFilter(spaces: .current).apply(all, context: context)), [1, 2, 4])
    }

    private func server(id: UInt32 = 10, attributes: UInt64 = 0x3, tags: UInt64 = 0, level: Int32 = 0, mask: UInt64 = 0x1, alpha: Float = 1,
                        parent: UInt32 = 0, size: CGSize = CGSize(width: 800, height: 600)) -> WindowServerWindow {
        WindowServerWindow(id: id, pid: 1, attributes: attributes, tags: tags, level: level, spaceTypeMask: mask, alpha: alpha, parent: parent,
                           frame: CGRect(origin: .zero, size: size), title: "")
    }

    func testWindowAdmission() {
        let current: Set<UInt64> = [1]
        // 一般視窗：排進畫面
        XCTAssertEqual(WindowAdmission.verdict(server(), spaces: [1], currentSpaces: current), .admit)
        // 縮到 Dock、App 被隱藏：沒排進畫面，但是真的視窗
        XCTAssertEqual(WindowAdmission.verdict(server(attributes: 0, tags: WindowAdmission.minimizedTag), spaces: [], currentSpaces: current), .admit)
        XCTAssertEqual(WindowAdmission.verdict(server(attributes: 0, tags: WindowAdmission.hiddenTag), spaces: [1], currentSpaces: current), .admit)
        // 在別的 Space：真的視窗
        XCTAssertEqual(WindowAdmission.verdict(server(attributes: 0), spaces: [2], currentSpaces: current), .admit)
        // Electron 的 show:false：還在目前的 Space、沒排進畫面 → 幻影
        XCTAssertEqual(WindowAdmission.verdict(server(attributes: 0), spaces: [1], currentSpaces: current), .phantom)
        // 原生分頁的背景分頁：沒有 Space、沒排進畫面 → 幻影
        XCTAssertEqual(WindowAdmission.verdict(server(attributes: 0), spaces: [], currentSpaces: current), .phantom)
        // 透明度 0（Outlook 提醒）：即使排進畫面也是幻影
        XCTAssertEqual(WindowAdmission.verdict(server(alpha: 0), spaces: [1], currentSpaces: current), .phantom)
        // 附屬視窗、浮動面板（層級不是 0）、輔助用的小表面、編號 0：不是切換目標
        XCTAssertEqual(WindowAdmission.verdict(server(parent: 5), spaces: [1], currentSpaces: current), .notAWindow)
        XCTAssertEqual(WindowAdmission.verdict(server(level: 3), spaces: [1], currentSpaces: current), .notAWindow)
        XCTAssertEqual(WindowAdmission.verdict(server(size: CGSize(width: 2, height: 66)), spaces: [1], currentSpaces: current), .notAWindow)
        XCTAssertEqual(WindowAdmission.verdict(server(id: 0), spaces: [1], currentSpaces: current), .notAWindow)
        // 狀態位元的解讀；全螢幕看 Space 類型
        XCTAssertTrue(WindowAdmission.isFullscreen(server(mask: 0x20)) && !WindowAdmission.isFullscreen(server()))
        XCTAssertTrue(WindowAdmission.isMinimized(server(tags: 1 << 60)) && !WindowAdmission.isMinimized(server(tags: 1 << 39)))
        XCTAssertTrue(WindowAdmission.isAppHidden(server(tags: 1 << 39)))
    }

    func testWindowlessApps() {
        // 「音樂」關掉視窗後還在執行：預設列出，可以關掉；也受例外清單影響
        var music = window(SwitcherWindow.windowlessID(pid: 7), pid: 7, app: "Music", bundle: "com.example.music", spaces: [])
        music.isWindowless = true
        let all = [window(1, pid: 1), music]
        let context = SwitcherFilter.Context(currentSpaces: [1], activeDisplay: nil)
        XCTAssertEqual(ids(SwitcherFilter().apply(all, context: context)), [1, SwitcherWindow.windowlessID(pid: 7)])
        XCTAssertEqual(ids(SwitcherFilter(showWindowlessApps: false).apply(all, context: context)), [1])
        XCTAssertEqual(ids(SwitcherFilter(excludedBundleIDs: ["com.example.music"]).apply(all, context: context)), [1])
        // 編號不會和真正的視窗編號重複
        XCTAssertTrue(SwitcherWindow.windowlessID(pid: 7) >= 0x8000_0000)
        // 沒有最近使用記錄的排在有記錄的後面
        var recency = WindowRecency()
        recency.focus(1)
        XCTAssertEqual(ids(recency.sorted([music, window(1)])), [1, SwitcherWindow.windowlessID(pid: 7)])
    }

    func testFilterKeepsWindowsWithoutSpaceInfo() {
        // 查不到 Space 的視窗不能因此消失
        let all = [window(1, spaces: []), window(2, spaces: [7])]
        let context = SwitcherFilter.Context(currentSpaces: [1], activeDisplay: nil)
        XCTAssertEqual(ids(SwitcherFilter(spaces: .current).apply(all, context: context)), [1])
        XCTAssertEqual(ids(SwitcherFilter(spaces: .current).apply(all, context: SwitcherFilter.Context(currentSpaces: [], activeDisplay: nil))), [1, 2])
    }

    func testRealWindowSize() {
        XCTAssertTrue(SwitcherFilter.isRealWindow(size: CGSize(width: 800, height: 600), layer: 0))
        XCTAssertTrue(!SwitcherFilter.isRealWindow(size: CGSize(width: 2, height: 66), layer: 0))
        XCTAssertTrue(!SwitcherFilter.isRealWindow(size: CGSize(width: 800, height: 600), layer: 25))
    }

    // MARK: 按鍵

    private typealias Mod = SwitcherShortcut.Modifiers

    private func press(_ keys: inout SwitcherKeys, _ code: Int64, _ mods: Mod) -> (Bool, SwitcherKeys.Action) {
        let r = keys.handle(.keyDown, keyCode: code, modifiers: mods)
        return (r.swallow, r.action)
    }

    func testKeysStartStepAndCommit() {
        var keys = SwitcherKeys()
        // 沒按修飾鍵的 Tab 不管
        XCTAssertTrue(press(&keys, 48, []) == (false, .none))
        XCTAssertTrue(!keys.active)
        XCTAssertTrue(press(&keys, 48, .command) == (true, .start(slot: 0, delta: 1)))
        XCTAssertTrue(keys.active)
        XCTAssertTrue(press(&keys, 48, [.command, .shift]) == (true, .step(-1)))
        // 按鍵放開也攔下，只攔一次
        XCTAssertTrue(keys.handle(.keyUp, keyCode: 48, modifiers: .command).swallow)
        XCTAssertTrue(!keys.handle(.keyUp, keyCode: 48, modifiers: .command).swallow)
        // Shift 的變化不結束；放開 Command 才切過去
        XCTAssertTrue(keys.handle(.flagsChanged, keyCode: 56, modifiers: .command).action == .none)
        XCTAssertTrue(keys.active)
        XCTAssertTrue(keys.handle(.flagsChanged, keyCode: 55, modifiers: []).action == .commit)
        XCTAssertTrue(!keys.active)
        // 沒在切換時放開修飾鍵沒事
        XCTAssertTrue(keys.handle(.flagsChanged, keyCode: 55, modifiers: []).action == .none)
    }

    func testKeysIgnoreOtherModifiersAndUnusedShortcuts() {
        var keys = SwitcherKeys()
        // Command+Option+Tab 留給其他 App
        XCTAssertTrue(press(&keys, 48, [.command, .option]) == (false, .none))
        // 沒有修飾鍵的快捷鍵（會攔下一般打字）和含 Shift 的設定都不接受
        XCTAssertEqual(SwitcherKeys(shortcuts: [SwitcherShortcut(keyCode: 48, hold: []), SwitcherShortcut(keyCode: 48, hold: [.command, .shift])]).shortcuts.count, 0)
    }

    func testKeysMultipleShortcuts() {
        var keys = SwitcherKeys(shortcuts: [.commandTab, SwitcherShortcut(keyCode: 50, hold: .option)])
        XCTAssertTrue(press(&keys, 50, .option) == (true, .start(slot: 1, delta: 1)))
        XCTAssertEqual(keys.activeSlot, 1)
        // 切換中放開的修飾鍵要看這一組的
        XCTAssertTrue(keys.handle(.flagsChanged, keyCode: 58, modifiers: []).action == .commit)
        XCTAssertTrue(press(&keys, 48, .command) == (true, .start(slot: 0, delta: 1)))
        XCTAssertEqual(keys.activeSlot, 0)
    }

    func testKeysNavigationAndWindowActions() {
        var keys = SwitcherKeys()
        _ = press(&keys, 48, .command)
        XCTAssertTrue(press(&keys, 123, .command) == (true, .move(dx: -1, dy: 0)))
        XCTAssertTrue(press(&keys, 124, .command) == (true, .move(dx: 1, dy: 0)))
        XCTAssertTrue(press(&keys, 126, .command) == (true, .move(dx: 0, dy: -1)))
        XCTAssertTrue(press(&keys, 125, .command) == (true, .move(dx: 0, dy: 1)))
        XCTAssertTrue(press(&keys, 13, .command) == (true, .window(.close)))
        XCTAssertTrue(press(&keys, 46, .command) == (true, .window(.minimize)))
        XCTAssertTrue(press(&keys, 3, .command) == (true, .window(.fullscreen)))
        XCTAssertTrue(press(&keys, 4, .command) == (true, .window(.hide)))
        XCTAssertTrue(press(&keys, 12, .command) == (true, .window(.quit)))
        // 其他按鍵照常交出去，切換還在
        XCTAssertTrue(press(&keys, 0, .command) == (false, .none))
        XCTAssertTrue(keys.active)
        // 沒在切換時這些鍵完全不攔
        var idle = SwitcherKeys()
        XCTAssertTrue(press(&idle, 13, .command) == (false, .none))
        XCTAssertTrue(press(&idle, 124, []) == (false, .none))
    }

    func testKeysVimMode() {
        var keys = SwitcherKeys(vimKeys: true)
        _ = press(&keys, 48, .command)
        XCTAssertTrue(press(&keys, 4, .command) == (true, .move(dx: -1, dy: 0)))
        XCTAssertTrue(press(&keys, 38, .command) == (true, .move(dx: 0, dy: 1)))
        XCTAssertTrue(press(&keys, 40, .command) == (true, .move(dx: 0, dy: -1)))
        XCTAssertTrue(press(&keys, 37, .command) == (true, .move(dx: 1, dy: 0)))
        // vim 模式下 H 是往左，不再是隱藏
        XCTAssertTrue(press(&keys, 4, .command) != (true, .window(.hide)))
        // 沒開 vim 時 hjkl 不移動
        var plain = SwitcherKeys()
        _ = press(&plain, 48, .command)
        XCTAssertTrue(press(&plain, 38, .command) == (false, .none))
    }

    func testKeysRecoverFromLostModifierRelease() {
        var keys = SwitcherKeys()
        _ = press(&keys, 48, .command)
        // 放開 Command 的事件遺失，之後打字的第一個鍵：先切過去，這個鍵照常交出去
        XCTAssertTrue(press(&keys, 0, []) == (false, .commit))
        XCTAssertTrue(!keys.active)
        // 之後不會再重複切換
        XCTAssertTrue(keys.handle(.flagsChanged, keyCode: 55, modifiers: []).action == .none)
        // 遺失後又按 Tab：重新開始
        _ = press(&keys, 48, .command)
        XCTAssertTrue(press(&keys, 48, .command) == (true, .step(1)))
    }

    func testKeysEscapeCancelsAndSwallowsKeyUps() {
        var keys = SwitcherKeys()
        _ = press(&keys, 48, .command)
        XCTAssertTrue(press(&keys, 53, .command) == (true, .cancel))
        XCTAssertTrue(!keys.active)
        // 取消後放開 Command 不會切換；Esc 與 Tab 的放開仍被攔下，不會漏給前景 App
        XCTAssertTrue(keys.handle(.flagsChanged, keyCode: 55, modifiers: []).action == .none)
        XCTAssertTrue(keys.handle(.keyUp, keyCode: 53, modifiers: []).swallow)
        XCTAssertTrue(keys.handle(.keyUp, keyCode: 48, modifiers: []).swallow)
        // 沒在切換時 Esc 不攔
        XCTAssertTrue(press(&keys, 53, []) == (false, .none))
    }

    func testKeepOpenMode() {
        var keys = SwitcherKeys(releaseCommits: false)
        _ = press(&keys, 48, .command)
        // 放開 Command：不切換，切換器留著
        XCTAssertTrue(keys.handle(.flagsChanged, keyCode: 55, modifiers: []).action == .release)
        XCTAssertTrue(keys.active && keys.sticky)
        // 不用修飾鍵：Tab、方向鍵、Shift+Tab 移動，W 等視窗動作照常，其他鍵交出去
        XCTAssertTrue(press(&keys, 48, []) == (true, .step(1)))
        XCTAssertTrue(press(&keys, 48, .shift) == (true, .step(-1)))
        XCTAssertTrue(press(&keys, 124, []) == (true, .move(dx: 1, dy: 0)))
        XCTAssertTrue(press(&keys, 13, []) == (true, .window(.close)))
        XCTAssertTrue(press(&keys, 0, []) == (false, .none))
        XCTAssertTrue(keys.active)
        // Return 確認（主鍵盤與數字鍵盤），之後恢復正常
        XCTAssertTrue(press(&keys, 36, []) == (true, .commit))
        XCTAssertTrue(!keys.active && !keys.sticky)
        XCTAssertTrue(keys.handle(.keyUp, keyCode: 36, modifiers: []).swallow)
        // Esc 取消
        _ = press(&keys, 48, .command)
        _ = keys.handle(.flagsChanged, keyCode: 55, modifiers: [])
        XCTAssertTrue(press(&keys, 53, []) == (true, .cancel))
        XCTAssertTrue(!keys.active)
        // 保持開啟時再按一次快捷鍵會重新按住：再放開又回到等待確認
        _ = press(&keys, 48, .command)
        _ = keys.handle(.flagsChanged, keyCode: 55, modifiers: [])
        XCTAssertTrue(press(&keys, 48, .command) == (true, .step(1)))
        XCTAssertTrue(!keys.sticky)
        XCTAssertTrue(keys.handle(.flagsChanged, keyCode: 55, modifiers: []).action == .release)
        // 預設模式沒開保持開啟時 Return 不是確認鍵
        var normal = SwitcherKeys()
        _ = press(&normal, 48, .command)
        XCTAssertTrue(press(&normal, 36, .command) == (false, .none))
    }

    func testShortcutValidationAndNames() {
        XCTAssertEqual(SwitcherShortcut.commandTab.displayName, "⌘ Tab")
        XCTAssertEqual(SwitcherShortcut(keyCode: 50, hold: [.control, .option]).displayName, "⌃⌥ `")
        XCTAssertEqual(SwitcherShortcut(keyCode: 100, hold: .command).displayName, "⌘ F8")
        XCTAssertEqual(SwitcherShortcut(keyCode: 99, hold: .command).displayName, "⌘ F3")
        XCTAssertEqual(SwitcherShortcut(keyCode: 90, hold: .option).displayName, "⌥ 按鍵 90")
        XCTAssertTrue(SwitcherShortcut.commandTab.isUsable)
        // 沒有修飾鍵、含 Shift、修飾鍵當觸發鍵、超出範圍的代碼都不行
        XCTAssertTrue(!SwitcherShortcut(keyCode: 48, hold: []).isUsable)
        XCTAssertTrue(!SwitcherShortcut(keyCode: 48, hold: [.command, .shift]).isUsable)
        XCTAssertTrue(!SwitcherShortcut(keyCode: 55, hold: .option).isUsable)
        XCTAssertTrue(!SwitcherShortcut(keyCode: 200, hold: .command).isUsable)
        XCTAssertTrue(!SwitcherShortcut(keyCode: -1, hold: .command).isUsable)
        // 系統保留的強制結束視窗
        XCTAssertTrue(!SwitcherShortcut(keyCode: 53, hold: [.command, .option]).isUsable)
        XCTAssertTrue(!SwitcherShortcut(keyCode: 53, hold: [.command, .option, .control]).isUsable)
        XCTAssertTrue(SwitcherShortcut(keyCode: 53, hold: .command).isUsable)
    }

    func testAccessibilityDescription() {
        var window = SwitcherWindow(id: 1, pid: 1, appName: "Notes", bundleID: nil, title: "Shopping list")
        XCTAssertEqual(window.accessibilityDescription, "Notes，Shopping list")
        window.isMinimized = true
        XCTAssertEqual(window.accessibilityDescription, "Notes，Shopping list，已縮到最小")
        // 標題和 App 名稱相同或沒有標題時只念一次
        XCTAssertEqual(SwitcherWindow(id: 2, pid: 1, appName: "Music", bundleID: nil, title: "Music").accessibilityDescription, "Music")
        XCTAssertEqual(SwitcherWindow(id: 3, pid: 1, appName: "Music", bundleID: nil, title: "  ").accessibilityDescription, "Music")
        var other = SwitcherWindow(id: 4, pid: 1, appName: "Safari", bundleID: nil, title: "Docs")
        other.spaceNumber = 2
        XCTAssertEqual(other.accessibilityDescription, "Safari，Docs，Space 2")
        XCTAssertEqual(other.statusText, "Space 2")
        XCTAssertEqual(SwitcherWindow(id: 5, pid: 9, appName: "Music", bundleID: nil, title: "", isWindowless: true).statusText, "沒有視窗")
    }

    func testSettingsRoundTripAndValidation() {
        // 預設值讀寫不變
        XCTAssertEqual(SwitcherSettings(stored: SwitcherSettings().stored), SwitcherSettings())
        XCTAssertEqual(SwitcherSettings(stored: [:]), SwitcherSettings())
        var custom = SwitcherSettings()
        custom.vimKeys = true
        custom.keepOpenAfterRelease = true
        custom.refreshThumbnails = false
        custom.previewSelectedWindow = true
        custom.animations = false
        custom.excludedBundleIDs = ["com.example.vm", "org.example.remote-desktop"]
        custom.profiles[0].shortcut = SwitcherShortcut(keyCode: 50, hold: [.option])
        custom.profiles[0].tileSize = .large
        custom.profiles[0].style = .appIcons
        custom.profiles[0].autoSize = true
        custom.profiles[0].filter.spaces = .current
        custom.profiles[0].filter.screens = .active
        custom.profiles[0].filter.order = .appName
        custom.profiles[0].filter.showMinimized = false
        custom.profiles[0].filter.showWindowlessApps = false
        custom.profiles[0].filter.groupApps = true
        var second = SwitcherProfile(shortcut: .commandTab)
        second.style = .titles
        second.filter.spaces = .current
        custom.profiles.append(second)
        XCTAssertEqual(SwitcherSettings(stored: custom.stored), custom)
        // 壞掉的值各自退回預設，其他欄位不受影響
        var brokenProfile = custom.profiles[0].stored
        brokenProfile["tileSize"] = "huge"
        brokenProfile["style"] = "carousel"
        brokenProfile["autoSize"] = 1
        brokenProfile["spaces"] = 7
        var broken = custom.stored
        broken["profiles"] = [brokenProfile]
        broken["vimKeys"] = "yes"
        let loaded = SwitcherSettings(stored: broken)
        XCTAssertEqual(loaded.profiles.count, 1)
        XCTAssertEqual(loaded.profiles[0].tileSize, .medium)
        XCTAssertEqual(loaded.profiles[0].style, .thumbnails)
        XCTAssertEqual(loaded.profiles[0].autoSize, false)
        XCTAssertEqual(loaded.profiles[0].filter.spaces, SwitcherFilter().spaces)
        XCTAssertEqual(loaded.profiles[0].filter.order, .appName)
        XCTAssertEqual(loaded.vimKeys, false)
        XCTAssertEqual(loaded.refreshThumbnails, false)
        XCTAssertEqual(loaded.previewSelectedWindow, true)
        XCTAssertEqual(SwitcherSettings(stored: [:]).previewSelectedWindow, false)
        XCTAssertEqual(SwitcherSettings(stored: [:]).animations, true)
        XCTAssertEqual(SwitcherSettings(stored: ["refreshThumbnails": "no"]).refreshThumbnails, true)
        XCTAssertEqual(SwitcherSettings(stored: [:]).refreshThumbnails, true)
        // 不能當快捷鍵的那一組丟掉（沒有修飾鍵、含 Shift、未知的修飾位元）；全部壞掉退回預設
        for hold in [0, 9, 33] {
            var bad = custom.profiles[0].stored
            bad["keyCode"] = 48
            bad["hold"] = hold
            XCTAssertEqual(SwitcherSettings(stored: ["profiles": [bad]]).profiles, [SwitcherProfile()])
        }
        // 重複的快捷鍵只留第一組；組數有上限
        var duplicate = custom.stored
        duplicate["profiles"] = [custom.profiles[0].stored, custom.profiles[0].stored]
        XCTAssertEqual(SwitcherSettings(stored: duplicate).profiles.count, 1)
        let many = (0..<20).map { index -> [String: Any] in
            var entry = SwitcherProfile().stored
            entry["keyCode"] = 10 + index
            return entry
        }
        XCTAssertEqual(SwitcherSettings(stored: ["profiles": many]).profiles.count, SwitcherSettings.maxProfiles)
        // 舊版（單一快捷鍵、欄位在最外層）升級成第一組，壞掉的快捷鍵退回 Cmd+Tab
        let legacy: [String: Any] = ["keyCode": 50, "hold": 2, "style": "titles", "spaces": "current", "excluded": ["com.example.vm"], "vimKeys": true]
        let migrated = SwitcherSettings(stored: legacy)
        XCTAssertEqual(migrated.profiles.count, 1)
        XCTAssertEqual(migrated.profiles[0].shortcut, SwitcherShortcut(keyCode: 50, hold: [.option]))
        XCTAssertEqual(migrated.profiles[0].style, .titles)
        XCTAssertEqual(migrated.profiles[0].filter.spaces, .current)
        XCTAssertEqual(migrated.excludedBundleIDs, ["com.example.vm"])
        XCTAssertEqual(SwitcherSettings(stored: ["keyCode": 48, "hold": 0]).profiles[0].shortcut, .commandTab)
        // 例外清單共用給每一組，且併進該組的篩選
        XCTAssertEqual(custom.filter(forProfile: 1).excludedBundleIDs, custom.excludedBundleIDs)
        XCTAssertEqual(custom.filter(forProfile: 1).spaces, .current)
        XCTAssertTrue(custom.isTaken(.commandTab, except: 0) && !custom.isTaken(.commandTab, except: 1))
        // 例外清單：不合法的 Bundle ID 丟掉；數量有上限
        var excluded = custom.stored
        excluded["excluded"] = ["com.example.ok", "../etc/passwd", "", "has space", "a;b", String(repeating: "a", count: 300), "中文.app"]
        XCTAssertEqual(SwitcherSettings(stored: excluded).excludedBundleIDs, ["com.example.ok"])
        excluded["excluded"] = (0..<500).map { "com.example.app\($0)" }
        XCTAssertEqual(SwitcherSettings(stored: excluded).excludedBundleIDs.count, SwitcherSettings.maxExcludedApps)
        XCTAssertTrue(SwitcherSettings.isValidBundleID("com.apple.Safari") && SwitcherSettings.isValidBundleID("org.example_app-2"))
        XCTAssertTrue(!SwitcherSettings.isValidBundleID(".hidden") && !SwitcherSettings.isValidBundleID("-x"))
    }


    // MARK: 版面

    func testGridFitsAndShrinks() {
        let screen = CGSize(width: 1600, height: 1000)
        // 直式、一般、寬螢幕的視窗：格子寬度跟著長寬比，三個排成一列
        let mixed = SwitcherLayout.grid(aspects: [0.6, 1.6, 2.2], available: screen, size: .medium)
        XCTAssertEqual(mixed.rows, [[0, 1, 2]])
        XCTAssertTrue(mixed.widths[0] < mixed.widths[1] && mixed.widths[1] < mixed.widths[2])
        XCTAssertTrue(!mixed.scrolls)
        // 比例極端的視窗有寬度上下限；標題至少有最小寬度
        let extreme = SwitcherLayout.grid(aspects: [0.01, 50], available: screen, size: .medium)
        XCTAssertEqual(extreme.widths[1], SwitcherLayout.aspectRange.upperBound * 140 + 16)
        XCTAssertTrue(extreme.widths[0] >= SwitcherLayout.minimumContentWidth + 16)
        // 一列放不下就換行，每個視窗都在某一列，順序不變
        let many = SwitcherLayout.grid(aspects: Array(repeating: 1.6, count: 30), available: screen, size: .medium)
        XCTAssertTrue(many.rows.count > 1 && !many.scrolls)
        XCTAssertEqual(many.rows.flatMap { $0 }, Array(0..<30))
        // 太多視窗：先縮小，縮到下限還放不下才捲動
        let huge = SwitcherLayout.grid(aspects: Array(repeating: 1.6, count: 400), available: screen, size: .large)
        XCTAssertTrue(huge.scrolls)
        XCTAssertEqual(huge.thumbnailHeight, SwitcherLayout.TileSize.large.thumbnailHeight * SwitcherLayout.minimumScale)
        // 面板大小不超過可用空間
        let size = SwitcherLayout.panelSize(for: huge, available: screen)
        XCTAssertTrue(size.width <= screen.width && size.height <= screen.height)
        XCTAssertEqual(SwitcherLayout.grid(aspects: [], available: screen, size: .medium), .empty)
        // 很窄的螢幕：每個視窗自己一列
        XCTAssertEqual(SwitcherLayout.grid(aspects: [1.6, 1.6], available: CGSize(width: 220, height: 800), size: .medium).rows, [[0], [1]])
    }

    func testStyleLayouts() {
        let screen = CGSize(width: 1600, height: 1000)
        let aspects = Array(repeating: CGFloat(1.6), count: 40)
        // App 圖像：每格一樣大、排成多列，照順序；比縮圖樣式一頁放得下更多
        let icons = SwitcherLayout.layout(style: .appIcons, aspects: aspects, available: screen, size: .medium)
        XCTAssertEqual(icons.style, .appIcons)
        XCTAssertTrue(Set(icons.widths).count == 1 && icons.thumbnailHeight == SwitcherLayout.TileSize.medium.iconSize)
        XCTAssertEqual(icons.rows.flatMap { $0 }, Array(0..<40))
        XCTAssertTrue(!icons.scrolls)
        let thumbs = SwitcherLayout.layout(style: .thumbnails, aspects: aspects, available: screen, size: .medium)
        XCTAssertTrue(icons.rows[0].count > thumbs.rows[0].count)
        // 標題列表：一列一個、寬度不超過上限、間距較小、太多就捲動
        let list = SwitcherLayout.layout(style: .titles, aspects: Array(repeating: 1.6, count: 5), available: screen, size: .medium)
        XCTAssertEqual(list.rows, [[0], [1], [2], [3], [4]])
        XCTAssertEqual(list.widths[0], SwitcherLayout.maximumListWidth)
        XCTAssertEqual(list.spacing, SwitcherLayout.listSpacing)
        XCTAssertTrue(!list.scrolls)
        XCTAssertTrue(SwitcherLayout.layout(style: .titles, aspects: aspects, available: CGSize(width: 1600, height: 500), size: .large).scrolls)
        let panel = SwitcherLayout.panelSize(for: list, available: screen)
        XCTAssertEqual(panel.width, SwitcherLayout.maximumListWidth + 2 * SwitcherLayout.padding)
        XCTAssertEqual(panel.height, 5 * 36 + 4 * SwitcherLayout.listSpacing + 2 * SwitcherLayout.padding)
        // 窄螢幕：列表寬度不超過可用寬度
        XCTAssertEqual(SwitcherLayout.layout(style: .titles, aspects: [1.6], available: CGSize(width: 300, height: 800), size: .medium).widths[0], 300 - 2 * SwitcherLayout.padding)
        // 沒有視窗
        for style in SwitcherStyle.allCases {
            XCTAssertEqual(SwitcherLayout.layout(style: style, aspects: [], available: screen, size: .medium), .empty)
        }
        // 列表用上下鍵移動
        XCTAssertEqual(SwitcherLayout.move(from: 0, dx: 0, dy: 1, in: list), 1)
        XCTAssertEqual(SwitcherLayout.move(from: 0, dx: 0, dy: -1, in: list), 4)
    }

    func testAutoSize() {
        let screen = CGSize(width: 1600, height: 1000)
        // 視窗少：放大，但不超過上限
        let fixedFew = SwitcherLayout.grid(aspects: [1.6, 1.6, 1.6], available: screen, size: .medium)
        let autoFew = SwitcherLayout.grid(aspects: [1.6, 1.6, 1.6], available: screen, size: .medium, autoSize: true)
        XCTAssertEqual(fixedFew.thumbnailHeight, 140)
        XCTAssertTrue(autoFew.thumbnailHeight > fixedFew.thumbnailHeight)
        XCTAssertTrue(autoFew.thumbnailHeight <= SwitcherLayout.maximumAutoThumbnailHeight)
        XCTAssertTrue(!autoFew.scrolls)
        // 放大後整體仍放得進螢幕
        let size = SwitcherLayout.panelSize(for: autoFew, available: screen)
        XCTAssertTrue(size.width <= screen.width && size.height <= screen.height)
        // 視窗多：自動大小不會比固定大小更大（一樣要縮小），而且放得下的話不捲動
        let manyAspects = Array(repeating: CGFloat(1.6), count: 40)
        let fixedMany = SwitcherLayout.grid(aspects: manyAspects, available: screen, size: .medium)
        let autoMany = SwitcherLayout.grid(aspects: manyAspects, available: screen, size: .medium, autoSize: true)
        XCTAssertTrue(autoMany.thumbnailHeight >= fixedMany.thumbnailHeight - 0.001)
        XCTAssertTrue(autoMany.thumbnailHeight <= 140 * SwitcherLayout.maximumAutoScale)
        // 一個視窗：放大到上限而不是填滿整個螢幕
        let single = SwitcherLayout.grid(aspects: [1.6], available: screen, size: .medium, autoSize: true)
        XCTAssertEqual(single.thumbnailHeight, min(140 * SwitcherLayout.maximumAutoScale, SwitcherLayout.maximumAutoThumbnailHeight))
        // 圖示樣式也會放大
        let autoIcons = SwitcherLayout.iconGrid(count: 3, available: screen, size: .medium, autoSize: true)
        XCTAssertTrue(autoIcons.thumbnailHeight > SwitcherLayout.TileSize.medium.iconSize)
        // 放不下就縮小到下限並捲動，自動大小也一樣
        let huge = SwitcherLayout.grid(aspects: Array(repeating: 1.6, count: 500), available: screen, size: .large, autoSize: true)
        XCTAssertTrue(huge.scrolls)
        XCTAssertEqual(huge.thumbnailHeight, SwitcherLayout.TileSize.large.thumbnailHeight * SwitcherLayout.minimumScale)
    }

    func testGridMovement() {
        // 7 個視窗：
        //  0 1 2
        //  3 4 5
        //  6
        let grid = SwitcherLayout.Grid(rows: [[0, 1, 2], [3, 4, 5], [6]], widths: Array(repeating: 100, count: 7), tileHeight: 100, thumbnailHeight: 60, scrolls: false)
        XCTAssertEqual(SwitcherLayout.move(from: 0, dx: -1, dy: 0, in: grid), 6)
        XCTAssertEqual(SwitcherLayout.move(from: 6, dx: 1, dy: 0, in: grid), 0)
        XCTAssertEqual(SwitcherLayout.move(from: 1, dx: 0, dy: 1, in: grid), 4)
        // 最後一列只有一個、置中：從它往下回到第一列，選水平位置最接近的（中間那個）
        XCTAssertEqual(SwitcherLayout.move(from: 4, dx: 0, dy: 1, in: grid), 6)
        XCTAssertEqual(SwitcherLayout.move(from: 6, dx: 0, dy: 1, in: grid), 1)
        XCTAssertEqual(SwitcherLayout.move(from: 5, dx: 0, dy: -1, in: grid), 2)
        XCTAssertEqual(SwitcherLayout.move(from: 2, dx: 0, dy: -1, in: grid), 6)
        XCTAssertEqual(SwitcherLayout.step(from: 0, delta: -1, count: 7), 6)
        XCTAssertEqual(SwitcherLayout.move(from: 0, dx: 0, dy: 1, in: .empty), 0)
    }
}
