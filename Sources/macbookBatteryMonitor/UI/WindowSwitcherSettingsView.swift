import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 「視窗切換」分類：開關與權限、快捷鍵、外觀、要列出的視窗、例外清單
struct WindowSwitcherSettingsView: View {
    let settings: AppSettings
    let ui: PanelState

    /// 正在錄製第幾組；等於 profiles.count 代表錄製新增的一組
    @State private var recordingIndex: Int?
    /// 下方「外觀」與「要列出的視窗」正在編輯第幾組
    @State private var selected = 0
    @State private var recordingMessage: String?
    @State private var monitor: Any?

    var body: some View {
        enableCard
        if settings.windowSwitcher {
            shortcutCard
            profileCard
            exceptionsCard
            actionsCard
        }
    }

    // MARK: - 開關與權限

    private var enableCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle("視窗切換", systemImage: "macwindow.on.rectangle")
                SettingsView.SwitchRow("用視窗切換取代 Cmd+Tab", isOn: Binding(get: { settings.windowSwitcher }, set: { settings.windowSwitcher = $0 }))
                Text("按住快捷鍵的修飾鍵再按它的按鍵，列出所有視窗（不只 App），最近用過的在前，附視窗縮圖。放開就切過去，很快按一下直接回到上一個視窗。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if settings.windowSwitcher {
                    status
                }
            }
        }
    }

    @ViewBuilder private var status: some View {
        if ui.inputTapRunning {
            Label("運作中", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        } else if ui.scrollTrusted {
            Label("啟動中…", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
        } else {
            Text("需要允許「輔助使用」：系統設定 → 隱私權與安全性 → 輔助使用，打開「\(AppEdition.appName)」。")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Button("打開輔助使用設定") { ScrollDirection.openAccessibilitySettings() }
        }
        if WindowThumbnails.hasPermission {
            Label("視窗縮圖：已允許「螢幕錄製」", systemImage: "photo").font(.caption).foregroundStyle(.secondary)
        } else {
            Text("允許「螢幕錄製」後才會顯示視窗縮圖；沒有允許時只顯示 App 圖示與標題。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("要求權限") { WindowThumbnails.requestPermission() }
                Button("打開螢幕錄製設定") { Self.open("Privacy_ScreenCapture") }
            }
        }
    }

    private static func open(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 快捷鍵

    private var recording: Bool { recordingIndex != nil }
    private var profiles: [SwitcherProfile] { settings.switcher.profiles }
    private var current: Int { min(selected, profiles.count - 1) }

    private var shortcutCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle("快捷鍵", systemImage: "keyboard")
                ForEach(Array(profiles.enumerated()), id: \.offset) { index, profile in
                    HStack {
                        Text(index == 0 ? "主要" : "第 \(index + 1) 組")
                        Spacer()
                        Text(recordingIndex == index ? "請按下新的組合…" : profile.shortcut.displayName)
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.08)))
                        Button(recordingIndex == index ? "取消" : "更改") { recordingIndex == index ? stopRecording() : startRecording(index) }
                        if index == 0 {
                            Button("還原預設") {
                                stopRecording()
                                guard !settings.switcher.isTaken(.commandTab, except: 0) else { return }
                                settings.switcher.profiles[0].shortcut = .commandTab
                            }
                            .disabled(profile.shortcut == .commandTab && recordingIndex != 0)
                        } else {
                            Button("刪除") {
                                stopRecording()
                                settings.switcher.profiles.remove(at: index)
                                selected = min(selected, settings.switcher.profiles.count - 1)
                            }
                        }
                    }
                }
                if let recordingMessage {
                    Text(recordingMessage).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Button("新增一組快捷鍵") { startRecording(profiles.count) }
                    .disabled(profiles.count >= SwitcherSettings.maxProfiles || recording)
                Text("每組快捷鍵可以有自己的外觀和要列出的視窗，例如 Cmd+Tab 看全部、Option+Tab 只看目前桌面。「更改」會取代那一組原本的按鍵；要多一組請按「新增一組快捷鍵」。要按住至少一個修飾鍵（Command、Option 或 Control）；Shift 用來往回選。錄製時切換器暫停，所以預設的 Cmd+Tab 要用「還原預設」設回。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                SettingsView.SwitchRow("放開修飾鍵後保持開啟", isOn: bind(\.keepOpenAfterRelease))
                Text("開啟時放開修飾鍵不會切換：用方向鍵或 Tab 選，Return 確認、Esc 取消，點切換器以外的地方也會取消。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                SettingsView.SwitchRow("用 H J K L 移動選取", isOn: bind(\.vimKeys))
                Text("開啟後 H 改成往左移動，隱藏 App 的快捷鍵就停用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording(_ index: Int) {
        stopRecording()
        recordingMessage = nil
        recordingIndex = index
        // 錄製時暫停切換器，否則按下目前的快捷鍵會先被它攔走
        InputTap.shared.setSwitcher(shortcuts: [], vimKeys: false, releaseCommits: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        guard recording else { return }
        recordingIndex = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        // 恢復目前設定的快捷鍵
        settings.onWindowSwitcherChange?()
    }

    private func handle(_ event: NSEvent) {
        guard let index = recordingIndex else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53, flags.intersection([.command, .option, .control, .shift]).isEmpty {
            recordingMessage = nil
            stopRecording()
            return
        }
        var hold = SwitcherShortcut.Modifiers()
        if flags.contains(.command) { hold.insert(.command) }
        if flags.contains(.option) { hold.insert(.option) }
        if flags.contains(.control) { hold.insert(.control) }
        let candidate = SwitcherShortcut(keyCode: Int64(event.keyCode), hold: hold)
        if flags.contains(.shift) {
            recordingMessage = "Shift 保留給往回選，請改用其他修飾鍵。"
        } else if !candidate.isUsable {
            recordingMessage = hold.isEmpty ? "要按住至少一個修飾鍵（Command、Option 或 Control）。" : "這個組合不能使用（系統保留）。"
        } else if settings.switcher.isTaken(candidate, except: index) {
            recordingMessage = "這個組合已經被另一組使用。"
        } else {
            recordingMessage = nil
            if index < settings.switcher.profiles.count {
                settings.switcher.profiles[index].shortcut = candidate
            } else if settings.switcher.profiles.count < SwitcherSettings.maxProfiles {
                settings.switcher.profiles.append(SwitcherProfile(shortcut: candidate))
                selected = settings.switcher.profiles.count - 1
            }
            stopRecording()
        }
    }

    // MARK: - 每組快捷鍵的外觀與篩選

    @ViewBuilder private var profileCard: some View {
        if profiles.count > 1 {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("設定哪一組", systemImage: "slider.horizontal.3")
                    Picker("", selection: Binding(get: { current }, set: { selected = $0 })) {
                        ForEach(Array(profiles.enumerated()), id: \.offset) { index, profile in
                            Text(profile.shortcut.displayName).tag(index)
                        }
                    }
                    .labelsHidden()
                    Text("下面「外觀」和「要列出的視窗」只套用在這一組快捷鍵。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        appearanceCard
        windowsCard
    }

    // MARK: - 外觀

    private var appearanceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle("外觀", systemImage: "rectangle.grid.2x2")
                Picker("樣式", selection: bindProfile(\.style)) {
                    ForEach(SwitcherStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("大小", selection: bindProfile(\.tileSize)) {
                    ForEach(SwitcherLayout.TileSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if profiles[current].style != .titles {
                    SettingsView.SwitchRow("自動調整大小", isOn: bindProfile(\.autoSize))
                }
                if profiles[current].style == .thumbnails {
                    SettingsView.SwitchRow("切換時更新視窗縮圖", isOn: bind(\.refreshThumbnails))
                    Text("開啟時每次顯示切換器都擷取最新畫面，系統會在這段時間於狀態列顯示「正在擷取你的畫面」。關閉後只用之前擷取過的畫面（沒擷取過的視窗顯示圖示），不再擷取、也不會出現這個提示；縮圖可能不是最新的。這個開關對所有快捷鍵生效。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SettingsView.SwitchRow("動畫", isOn: bind(\.animations))
                Text("切換器淡入、選取框移動的過渡。系統開啟「減少動態效果」時不做動畫。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SettingsView.SwitchRow("預覽選到的視窗", isOn: bind(\.previewSelectedWindow))
                Text("選到某個視窗時，在它原本的位置顯示它的畫面（切換器後面），不用切過去就能看到內容。需要「螢幕錄製」權限，也會擷取畫面；縮到 Dock、在別的桌面或沒有視窗的項目不預覽。關閉「切換時更新視窗縮圖」時只顯示之前擷取過的畫面。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("縮圖：視窗畫面；App 圖像：只有圖示（像 Dock），選到的下方顯示標題；標題：精簡列表。自動調整大小會在視窗少時放大、多時縮小，剛好填滿螢幕；關閉時固定大小，放不下才縮小。放不下又縮到下限時才會捲動。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 要列出的視窗

    private var windowsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle("要列出的視窗", systemImage: "line.3.horizontal.decrease.circle")
                Picker("桌面（Space）", selection: bindFilter(\.spaces)) {
                    ForEach(SwitcherFilter.Spaces.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("螢幕", selection: bindFilter(\.screens)) {
                    ForEach(SwitcherFilter.Screens.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("排序", selection: bindFilter(\.order)) {
                    ForEach(SwitcherFilter.Order.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                SettingsView.SwitchRow("縮到 Dock 的視窗", isOn: bindFilter(\.showMinimized))
                SettingsView.SwitchRow("已隱藏 App 的視窗", isOn: bindFilter(\.showHidden))
                SettingsView.SwitchRow("全螢幕視窗", isOn: bindFilter(\.showFullscreen))
                SettingsView.SwitchRow("還在執行但沒有視窗的 App", isOn: bindFilter(\.showWindowlessApps))
                SettingsView.SwitchRow("每個 App 只列一個視窗", isOn: bindFilter(\.groupApps))
                Text("螢幕「目前」指滑鼠所在的螢幕。沒有視窗的 App（例如在「音樂」按紅色叉叉）選到時會讓它重新開啟視窗。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 例外清單

    private var exceptionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle("例外清單", systemImage: "eye.slash")
                Text("這些 App 的視窗不會出現在切換器裡，例如虛擬機器、遠端桌面。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                let excluded = settings.switcher.excludedBundleIDs.sorted()
                if excluded.isEmpty {
                    Text("目前沒有").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(excluded, id: \.self) { id in
                    HStack {
                        Text(Self.appName(for: id))
                        Text(id).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("移除") { settings.switcher.excludedBundleIDs.remove(id) }
                            .controlSize(.small)
                    }
                }
                HStack {
                    Menu("加入執行中的 App") {
                        ForEach(runningCandidates(), id: \.id) { candidate in
                            Button(candidate.name) { add(candidate.id) }
                        }
                    }
                    Button("從磁碟選擇…") { chooseFromDisk() }
                }
                .disabled(settings.switcher.excludedBundleIDs.count >= SwitcherSettings.maxExcludedApps)
            }
        }
    }

    private func runningCandidates() -> [(id: String, name: String)] {
        let excluded = settings.switcher.excludedBundleIDs
        let me = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .compactMap { app -> (id: String, name: String)? in
                guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != me, !excluded.contains(id),
                      SwitcherSettings.isValidBundleID(id) else { return nil }
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func chooseFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        add(id)
    }

    private func add(_ id: String) {
        guard SwitcherSettings.isValidBundleID(id), settings.switcher.excludedBundleIDs.count < SwitcherSettings.maxExcludedApps else { return }
        settings.switcher.excludedBundleIDs.insert(id)
    }

    private static func appName(for id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: - 切換中的按鍵

    private var actionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                CardTitle("切換器開著時", systemImage: "command")
                Text("方向鍵或 Tab 移動，Shift+Tab 往回，Esc 取消。選到的視窗可以直接按：W 關閉、M 縮到 Dock（再按一次還原）、F 全螢幕、H 隱藏 App、Q 結束 App。滑鼠停在縮圖上也有關閉、縮小、全螢幕的按鈕。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 綁定

    private func bind<T>(_ keyPath: WritableKeyPath<SwitcherSettings, T>) -> Binding<T> {
        Binding(get: { settings.switcher[keyPath: keyPath] }, set: { settings.switcher[keyPath: keyPath] = $0 })
    }

    /// 目前選的那一組快捷鍵的欄位
    private func bindProfile<T>(_ keyPath: WritableKeyPath<SwitcherProfile, T>) -> Binding<T> {
        Binding(get: { profiles[current][keyPath: keyPath] },
                set: { value in
                    guard settings.switcher.profiles.indices.contains(current) else { return }
                    settings.switcher.profiles[current][keyPath: keyPath] = value
                })
    }

    private func bindFilter<T>(_ keyPath: WritableKeyPath<SwitcherFilter, T>) -> Binding<T> {
        bindProfile((\SwitcherProfile.filter).appending(path: keyPath))
    }
}

extension SwitcherStyle {
    var title: String {
        switch self {
        case .thumbnails: return "縮圖"
        case .appIcons: return "App 圖像"
        case .titles: return "標題"
        }
    }
}

extension SwitcherLayout.TileSize {
    var title: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }
}

extension SwitcherFilter.Spaces {
    var title: String { self == .all ? "所有桌面" : "目前桌面" }
}

extension SwitcherFilter.Screens {
    var title: String { self == .all ? "所有螢幕" : "目前螢幕" }
}

extension SwitcherFilter.Order {
    var title: String { self == .recentlyUsed ? "最近使用" : "App 名稱" }
}
