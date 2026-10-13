import SwiftUI

/// 設定頁的「更新」：檢查 GitHub 上的新版本，按一下就下載、驗證並換上新版
struct UpdateCard: View {
    @ObservedObject var updater: Updater
    @ObservedObject var settings: AppSettings
    /// macOS 關閉了這個 App 的通知
    var notificationsBlocked = false

    /// 點新版本通知時捲到這張卡片
    static let anchor = "update"

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle("更新", systemImage: "arrow.down.circle")
                HStack(spacing: 8) {
                    status
                    Spacer()
                    action
                }
                if let release = updater.available {
                    Link("查看 v\(release.versionText) 的更新內容", destination: release.pageURL)
                        .font(.caption)
                }
                HStack {
                    Text("自動檢查更新")
                    Spacer()
                    Toggle("自動檢查更新", isOn: Binding(get: { settings.autoCheckUpdates }, set: { settings.autoCheckUpdates = $0 }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                HStack {
                    Text("有新版本時通知")
                    Spacer()
                    Toggle("有新版本時通知", isOn: Binding(get: { settings.updateNotification }, set: { settings.updateNotification = $0 }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .disabled(!settings.autoCheckUpdates)
                if notificationsBlocked, settings.autoCheckUpdates, settings.updateNotification {
                    Text("macOS 已關閉這個 App 的通知，請先到上方「通知」打開，才會收到新版本通知。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("每天檢查一次 GitHub 上有沒有新版本，只會提示，不會自動安裝：面板底部會出現「有新版本」，開啟通知時也會發一則通知（每個版本只通知一次，點通知直接打開這裡）。更新時會下載通用版（Apple 晶片與 Intel 都能用），驗證後換上新版並重新開啟，設定與歷史資料都會保留。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .id(Self.anchor)
    }

    @ViewBuilder private var status: some View {
        switch updater.state {
        case .idle:
            Text(lastCheckedText ?? "目前版本 \(updater.currentVersion)").font(.callout)
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("檢查中…") }.font(.callout)
        case .upToDate:
            Label("已是最新版本（\(updater.currentVersion)）", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .available(let release):
            Text("有新版本 v\(release.versionText)（目前 \(updater.currentVersion)）").font(.callout.weight(.semibold))
        case .downloading(let release):
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("下載並驗證 v\(release.versionText)…") }.font(.callout)
        case .installing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("安裝中，App 會自動重新開啟…") }.font(.callout)
        case .failed(let message):
            Text(message).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var action: some View {
        switch updater.state {
        case .available:
            if updater.canInstall {
                Button("一鍵更新") { Task { await updater.install() } }
                    .buttonStyle(.borderedProminent)
            } else {
                Link("到 GitHub 下載", destination: Updater.releasesPage)
            }
        case .checking, .downloading, .installing:
            EmptyView()
        case .failed:
            HStack(spacing: 8) {
                Link("手動下載", destination: Updater.releasesPage).font(.caption)
                Button("重試") { Task { await updater.check(userInitiated: true) } }
            }
        case .idle, .upToDate:
            Button("檢查更新") { Task { await updater.check(userInitiated: true) } }
        }
    }

    private var lastCheckedText: String? {
        updater.lastChecked.map { "目前版本 \(updater.currentVersion)・上次檢查 \($0.formatted(.relative(presentation: .named)))" }
    }
}
