import SwiftUI

/// 設定 →「視窗與 Dock」：視窗切換以外、和視窗或 Dock 有關的擴充功能
struct WindowsSettingsView: View {
    let settings: AppSettings
    let ui: PanelState

    var body: some View {
        if settings.isInstalled(.finderKeys) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("Finder 加強", systemImage: "folder")
                    Text("在 Finder 按 ⌘X 剪下檔案，到別的資料夾按 ⌘V 就是搬移（等於 Finder 的 ⌥⌘V「搬移項目到這裡」）；剪下後如果又複製了別的東西，⌘V 照常拷貝，不會誤把檔案搬走。按 F2 重新命名（等於按 Return）。只在 Finder 是最前面的 App、而且不是在改檔名或搜尋框打字時才轉換。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    status(running: ui.finderKeysRunning)
                }
            }
        }
        if settings.isInstalled(.windowSnap) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("視窗吸附", systemImage: "rectangle.split.2x1")
                    Text("把視窗拖到螢幕左右邊緣排成半邊、拖到上緣填滿、拖到四個角排成四分之一；拖到邊緣時先顯示預覽框，放開才排版，拖離邊緣就取消。只監聽滑鼠，拖曳本身照常。系統設定 → 桌面與 Dock 的「拖移視窗到螢幕邊緣以並排」開著時，交給系統處理，這裡不動作。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    status(running: ui.windowSnapRunning)
                }
            }
        }
        if settings.isInstalled(.greenButton) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("綠色按鈕放大", systemImage: "arrow.up.left.and.arrow.down.right")
                    Text("點視窗左上角的綠色按鈕，改成填滿視窗所在螢幕的可用範圍（選單列與 Dock 還在，不進全螢幕，和「視窗 → 填滿」一樣有系統動畫）；再按一次還原成原本的位置大小。按著 Option 點照系統原本的行為。判斷是不是點到綠色按鈕最多等 15 毫秒，來不及時那一下照原本的方式進入全螢幕，不會拖慢點擊。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    status(running: ui.greenButtonRunning)
                }
            }
        }
        if settings.isInstalled(.dockClick) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("點 Dock 圖示縮到 Dock", systemImage: "dock.arrow.down.rectangle")
                    Picker("點目前 App 的 Dock 圖示時", selection: Binding(get: { settings.dockClickMode }, set: { settings.dockClickMode = $0 })) {
                        Text("把它的視窗縮到 Dock").tag(DockClick.Mode.minimize)
                        Text("隱藏 App").tag(DockClick.Mode.hide)
                    }
                    Text("只有點的是目前最前面的 App、而且它有開著的視窗時才收起來；再點一次照 Dock 原本的方式叫回來。點別的 App、拖曳圖示、按右鍵都照常。只監聽滑鼠，不攔截。開著幕前調度時，系統會把縮下去的視窗放到左邊的縮圖列而不是 Dock，這時一律改成隱藏 App。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    status(running: ui.dockClickRunning)
                }
            }
        }
        if settings.isInstalled(.lastWindowQuit) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("關閉最後視窗時結束 App", systemImage: "xmark.app")
                    Text("App 的最後一個視窗關掉時自動結束它。要所有 Space（包括縮到 Dock 的）都沒有它的視窗、而且它原本有視窗才會結束；Finder 與隱藏中的 App 不會結束。下面的 App 也不會被結束，例如關掉視窗後還要在背景播放的音樂 App。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    AppExceptionList(ids: Binding(get: { settings.lastWindowQuitExcluded }, set: { settings.lastWindowQuitExcluded = $0 }),
                                     limit: SwitcherSettings.maxExcludedApps)
                    status(running: ui.lastWindowQuitRunning)
                }
            }
        }
    }

    @ViewBuilder private func status(running: Bool) -> some View {
        if running {
            Label("運作中", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if !ui.scrollTrusted {
            Text("需要允許「輔助使用」：系統設定 → 隱私權與安全性 → 輔助使用，打開「\(AppEdition.appName)」。")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Button("打開輔助使用設定") { ScrollDirection.openAccessibilitySettings() }
        }
    }
}
