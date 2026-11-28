import AppKit
import SwiftUI

/// 新版設定的擴充功能頁（鍵盤、滑鼠與觸控板、視窗與 Dock）：每個功能一張卡，標題列右邊直接開關；
/// 常用設定留在外面，細項和長說明收合
struct SettingsV2KeyboardPage: View {
    private let page = SettingsV2Page.keyboard
    let settings: AppSettings
    let ui: PanelState
    let state: SettingsV2State

    private typealias SwitchRow = SettingsView.SwitchRow

    var body: some View {
        V2AccessibilityBanner(trusted: ui.scrollTrusted || !page.features.contains(where: settings.isInstalled))
        V2FeatureCard(feature: .inputMethod, subtitle: "Caps Lock 與 Shift 切換中英更順手", listens: "監聽鍵盤", settings: settings) {
            VStack(alignment: .leading, spacing: 10) {
                SwitchRow("按住 Shift 打半形英文與符號", isOn: binding(\.shiftHalfWidth))
                SwitchRow("Caps Lock 切換中英不延遲（外接鍵盤）", isOn: binding(\.capsLockNoDelay))
                if settings.shiftHalfWidth {
                    V2FeatureStatus(running: ui.shiftRunning, trusted: ui.scrollTrusted)
                }
                V2Disclosure(title: "說明", id: "keyboard.input.help", state: state) {
                    V2Note("macOS 為了防誤觸，Caps Lock 要按住一下才切換；打開後按一下就切（只對外接鍵盤有效：macOS 27.2 實測，使用系統的「大寫鎖定鍵切換輸入法」時，內建鍵盤由 macOS 自己判斷）。注音等中文輸入法按住 Shift 打字會變全形「Ａ」「！」「，」；打開後按住 Shift 時和英文鍵盤一樣全部打出半形，放開 Shift 就繼續打中文（Shift + 逗號、句號會是 < >，中文標點請改用其他方式打）。關掉「不延遲」時恢復系統預設的延遲。")
                }
            }
        }
        V2FeatureCard(feature: .quitGuard, subtitle: "按住一下才結束 App 或關閉視窗", listens: "監聽鍵盤", settings: settings) {
            VStack(alignment: .leading, spacing: 10) {
                SwitchRow("按住 ⌘Q 才結束 App", isOn: binding(\.quitGuardQuit))
                SwitchRow("按住 ⌘W 才關閉", isOn: binding(\.quitGuardClose))
                V2MenuRow(title: "要按住", options: AppSettings.quitGuardDurations.map { ($0, "\($0.formatted()) 秒") },
                          selection: binding(\.quitGuardDuration))
                if settings.quitGuardQuit || settings.quitGuardClose {
                    V2FeatureStatus(running: ui.quitGuardRunning, trusted: ui.scrollTrusted)
                }
                V2Disclosure(title: "說明", id: "keyboard.quit.help", state: state) {
                    V2Note("按下時記住最前面的 App，按滿時間才把 ⌘Q／⌘W 送給它；中途放開、換到別的 App 或按了別的鍵都會取消，不會關到後面的視窗。⌘W 送出前也會確認焦點視窗沒換。")
                }
            }
        }
        V2FeatureCard(feature: .keyboardCleaning, subtitle: "暫停整個鍵盤，方便擦拭", listens: "清潔時攔截鍵盤", settings: settings) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("停手多久後恢復")
                    Spacer(minLength: 12)
                    V2Menu(title: "停手多久後恢復", options: KeyboardCleaning.durations.map { ($0, "\($0) 秒") },
                           selection: binding(\.keyboardCleaningSeconds))
                    Button("開始清潔") {
                        if !KeyboardCleaningController.shared.start(seconds: settings.keyboardCleaningSeconds) {
                            ScrollDirection.requestTrust()
                        }
                    }
                }
                V2FeatureStatus(running: false, trusted: ui.scrollTrusted)
                V2Disclosure(title: "說明", id: "keyboard.cleaning.help", state: state) {
                    V2Note("暫時停用整個鍵盤，包括功能列的亮度、音量鍵；滑鼠與觸控板照常；擦的時候按到鍵會重新倒數，停手滿設定的秒數或點畫面中央的「結束清潔」就恢復。Touch ID 指紋照常可以用，但它也是電源鍵，按下去 Mac 一樣會鎖定或睡眠，長按會強制關機，擦的時候輕一點。")
                }
            }
        }
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }
}

struct SettingsV2MousePage: View {
    private let page = SettingsV2Page.mouse
    let settings: AppSettings
    let ui: PanelState
    let state: SettingsV2State

    private typealias SwitchRow = SettingsView.SwitchRow

    private var scrollActive: Bool {
        settings.scrollReverseMouse || settings.scrollReverseTrackpad || settings.scrollLinearLines > 0
            || settings.scrollHorizontalKey != .off || settings.scrollSmooth
    }

    var body: some View {
        V2AccessibilityBanner(trusted: ui.scrollTrusted || !page.features.contains(where: settings.isInstalled))
        V2FeatureCard(feature: .scrollDirection, subtitle: "滑鼠和觸控板分開設定捲動方向", listens: "監聽滑鼠捲動", settings: settings) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    V2ToggleTile(title: "滑鼠滾輪反向", symbol: "computermouse", isOn: binding(\.scrollReverseMouse))
                    V2ToggleTile(title: "觸控板反向", symbol: "rectangle.and.hand.point.up.left", isOn: binding(\.scrollReverseTrackpad))
                }
                if scrollActive {
                    if ui.scrollRunning || !ui.scrollTrusted {
                        V2FeatureStatus(running: ui.scrollRunning, trusted: ui.scrollTrusted)
                    } else {
                        // 有權限、還沒開始：每 5 秒會再試一次
                        Label("啟動中…", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                    }
                }
                V2Disclosure(title: "進階（左右反向、每格行數、平滑捲動、改成左右捲動）", id: "mouse.scroll.advanced", state: state) {
                    VStack(alignment: .leading, spacing: 10) {
                        SwitchRow("左右捲動也反向", isOn: binding(\.scrollReverseHorizontal))
                            .disabled(!settings.scrollReverseMouse && !settings.scrollReverseTrackpad)
                        V2MenuRow(title: "滑鼠滾輪每格", options: ScrollLinear.choices.map { ($0, $0 == 0 ? "照系統加速" : "固定 \($0) 行") },
                                  selection: binding(\.scrollLinearLines))
                        SwitchRow("滑鼠滾輪平滑捲動", isOn: binding(\.scrollSmooth))
                        V2MenuRow(title: "滾輪改成左右捲動", options: ScrollHorizontalKey.allCases.map { ($0, $0.title) },
                                  selection: binding(\.scrollHorizontalKey))
                        V2Note("macOS 的「自然捲動」是滑鼠和觸控板一起變；這裡可以只反轉其中一種。兩指在觸控板上捲動算觸控板，其他（包括 Magic Mouse）算滑鼠。")
                    }
                }
            }
        }
        V2FeatureCard(feature: .mouseButtons, subtitle: "多按鍵滑鼠拇指那兩顆", listens: "監聽滑鼠側鍵", settings: settings) {
            VStack(alignment: .leading, spacing: 10) {
                V2MenuRow(title: "第 4 鍵（後退）", options: MouseButtons.Action.allCases.map { ($0, $0.title) },
                          selection: binding(\.mouseBackButton))
                V2MenuRow(title: "第 5 鍵（前進）", options: MouseButtons.Action.allCases.map { ($0, $0.title) },
                          selection: binding(\.mouseForwardButton))
                if settings.mouseBackButton != .none || settings.mouseForwardButton != .none {
                    V2FeatureStatus(running: ui.mouseButtonsRunning, trusted: ui.scrollTrusted)
                }
                V2Note("「上一頁、下一頁」送出 ⌘[、⌘]，Safari、Finder 等大部分 App 都能用；設成「不處理」的按鍵照常交給 App。")
            }
        }
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }
}

struct SettingsV2WindowsPage: View {
    private let page = SettingsV2Page.windows
    let settings: AppSettings
    let ui: PanelState
    let state: SettingsV2State

    private typealias SwitchRow = SettingsView.SwitchRow

    var body: some View {
        V2AccessibilityBanner(trusted: ui.scrollTrusted || !page.features.contains(where: settings.isInstalled))
        // 舊版有「加入」與「取代 Cmd+Tab」兩個開關；兩者都開才算開，從舊版升級、只加入沒打開的人按一下就會兩個都打開
        V2FeatureCard(feature: .windowSwitcher, subtitle: "用快捷鍵在所有視窗之間切換，附縮圖", listens: "監聽鍵盤", settings: settings,
                      isOn: Binding(get: { settings.isInstalled(.windowSwitcher) && settings.windowSwitcher },
                                    set: { on in
                                        settings.setInstalled(.windowSwitcher, on)
                                        if on { settings.windowSwitcher = true }
                                    })) {
            VStack(alignment: .leading, spacing: 10) {
                V2FeatureStatus(running: ui.inputTapRunning, trusted: ui.scrollTrusted)
                SwitcherThumbnailPermission()
                V2Note("按住修飾鍵再按它的按鍵，列出所有視窗，最近用過的在前；放開就切過去，很快按一下直接回到上一個視窗。")
            }
        }
        if settings.isInstalled(.windowSwitcher) && settings.windowSwitcher {
            // 詳細設定本身就是好幾張卡片，收合在卡片外面
            V2Disclosure(title: "視窗切換的詳細設定（快捷鍵、外觀、要列出的視窗、例外）", id: "windows.switcher.details", state: state) {
                WindowSwitcherSettingsView(settings: settings, ui: ui, showsEnableCard: false)
            }
            .padding(.horizontal, 4)
        }
        V2FeatureCard(feature: .dockClick, subtitle: "點 Dock 圖示收起，再點一次叫回", listens: "監聽滑鼠點擊", settings: settings) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsPicker("點目前 App 的 Dock 圖示時",
                               selection: Binding(get: { settings.dockClickMode }, set: { settings.dockClickMode = $0 }),
                               options: [(DockClick.Mode.minimize, "把視窗縮到 Dock"), (DockClick.Mode.hide, "隱藏 App")],
                               symbol: { $0 == .minimize ? "dock.arrow.down.rectangle" : "eye.slash" })
                V2FeatureStatus(running: ui.dockClickRunning, trusted: ui.scrollTrusted)
                V2Disclosure(title: "說明", id: "windows.dock.help", state: state) {
                    V2Note("只有點的是目前最前面的 App、而且它有開著的視窗時才收起來；再點一次照 Dock 原本的方式叫回來。點別的 App、拖曳圖示、按右鍵都照常。只監聽滑鼠，不攔截。")
                }
            }
        }
        V2FeatureCard(feature: .greenButton, subtitle: "填滿螢幕而不是進入全螢幕", listens: "監聽滑鼠點擊", settings: settings) {
            VStack(alignment: .leading, spacing: 10) {
                V2FeatureStatus(running: ui.greenButtonRunning, trusted: ui.scrollTrusted)
                V2Disclosure(title: "說明", id: "windows.green.help", state: state) {
                    V2Note("點視窗左上角的綠色按鈕，改成填滿視窗所在螢幕的可用範圍（選單列與 Dock 還在，不進全螢幕）；再按一次還原成原本的位置大小。按著 Option 點照系統原本的行為。")
                }
            }
        }
        V2FeatureCard(feature: .windowSnap, subtitle: "拖到邊緣排成半邊或四分之一", listens: "監聽滑鼠拖曳", settings: settings) {
            VStack(alignment: .leading, spacing: 10) {
                V2FeatureStatus(running: ui.windowSnapRunning, trusted: ui.scrollTrusted)
                V2Disclosure(title: "說明", id: "windows.snap.help", state: state) {
                    V2Note("拖到左右邊緣排成半邊、拖到上緣填滿、拖到四個角排成四分之一；先顯示預覽框，放開才排版。系統設定 → 桌面與 Dock 的「拖移視窗到螢幕邊緣以並排」開著時，交給系統處理。")
                }
            }
        }
        V2FeatureCard(feature: .finderKeys, subtitle: "⌘X 剪下檔案、fn+F2 改名", listens: "監聽鍵盤", settings: settings) {
            VStack(alignment: .leading, spacing: 10) {
                V2FeatureStatus(running: ui.finderKeysRunning, trusted: ui.scrollTrusted)
                V2Disclosure(title: "說明", id: "windows.finder.help", state: state) {
                    V2Note("在 Finder 按 ⌘X 剪下檔案，到別的資料夾按 ⌘V 就是搬移；剪下後如果又複製了別的東西，⌘V 照常拷貝。按 F2 重新命名（功能列是亮度鍵時要按 fn+F2）。只在 Finder 是最前面的 App、而且不是在改檔名或搜尋框打字時才轉換。")
                }
            }
        }
        V2FeatureCard(feature: .lastWindowQuit, subtitle: "最後一個視窗關掉時結束 App", listens: "監聽視窗", settings: settings) {
            VStack(alignment: .leading, spacing: 10) {
                Text("不要結束的 App")
                AppExceptionList(ids: Binding(get: { settings.lastWindowQuitExcluded }, set: { settings.lastWindowQuitExcluded = $0 }),
                                 limit: SwitcherSettings.maxExcludedApps)
                V2FeatureStatus(running: ui.lastWindowQuitRunning, trusted: ui.scrollTrusted)
                V2Disclosure(title: "說明", id: "windows.lastWindow.help", state: state) {
                    V2Note("要所有 Space（包括縮到 Dock 的）都沒有它的視窗、而且它原本有視窗才會結束；Finder 與隱藏中的 App 不會結束。")
                }
            }
        }
    }
}

/// 貓咪快捷選單：主開關在卡片標題，面板上的項目（各自要開才會出現）列在裡面
struct SettingsV2QuickMenuPage: View {
    let settings: AppSettings

    private typealias SwitchRow = SettingsView.SwitchRow

    private func installed(_ feature: ExtensionFeature) -> Binding<Bool> {
        Binding(get: { settings.isInstalled(feature) }, set: { settings.setInstalled(feature, $0) })
    }

    var body: some View {
        V2FeatureCard(feature: .quickMenu, subtitle: "選單列多一個貓咪圖示，點開快速操作", listens: "不需要權限", settings: settings) {
            VStack(alignment: .leading, spacing: 10) {
                V2Note("面板上一直有「防止休眠」。下面的項目各自開了才會出現在面板上。")
                SwitchRow("音訊切換（輸出裝置、麥克風靜音）", isOn: installed(.audioSwitch))
                SwitchRow("剪貼簿歷史", isOn: installed(.clipboardHistory))
                V2Note("鍵盤清潔在「鍵盤」頁開啟，開了也會出現在面板上。")
            }
        }
    }
}
