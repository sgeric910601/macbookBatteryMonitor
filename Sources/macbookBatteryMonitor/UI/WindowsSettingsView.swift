import SwiftUI

/// 設定 →「視窗與 Dock」：視窗切換以外、和視窗或 Dock 有關的擴充功能
struct WindowsSettingsView: View {
    let settings: AppSettings
    let ui: PanelState

    var body: some View {
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
                    if ui.lastWindowQuitRunning {
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
        }
    }
}
