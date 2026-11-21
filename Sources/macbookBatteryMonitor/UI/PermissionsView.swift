import Combine
import SwiftUI

/// 設定 →「權限」：這個 App 用到的系統權限、目前狀態與哪些功能用到。頁面開著時每 2.5 秒更新，關掉就不檢查
struct PermissionsView: View {
    let settings: AppSettings

    private enum Status { case granted, denied, askWhenUsed, unconfirmed }

    @State private var statuses: [AppPermission: Status] = [:]
    private let ticker = Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(AppPermission.allCases) { permission in
                    row(permission)
                    if permission != AppPermission.allCases.last { Divider().padding(.vertical, 8) }
                }
            }
        }
        .onAppear(perform: refresh)
        .onReceive(ticker) { _ in refresh() }
        Text("在系統設定允許之後，這裡幾秒內會自動更新。權限都在「系統設定 → 隱私權與安全性」，可以隨時收回；收回後用到它的功能會停下來，其他功能照常。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ permission: AppPermission) -> some View {
        let users = permission.users(isInstalled: settings.isInstalled)
        return HStack(alignment: .top, spacing: 10) {
            IconTile(symbol: permission.symbol, tint: .gray, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(permission.title)
                    statusLabel(users.isEmpty ? nil : statuses[permission])
                }
                Text(users.isEmpty ? "目前沒有啟用需要它的功能" : "用到的功能：" + users.joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("打開系統設定") { NSWorkspace.shared.open(permission.settingsURL) }
                .controlSize(.small)
                .accessibilityLabel("打開\(permission.title)的系統設定")
        }
    }

    @ViewBuilder private func statusLabel(_ status: Status?) -> some View {
        switch status {
        case .granted: Label("已允許", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .denied: Label("未允許", systemImage: "exclamationmark.circle.fill").font(.caption).foregroundStyle(.orange)
        case .askWhenUsed: Text("用到時詢問").font(.caption).foregroundStyle(.secondary)
        case .unconfirmed: Label("無法確認", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
        case nil: EmptyView()
        }
    }

    private func refresh() {
        // 從清單「移除」後系統在這個行程裡仍回答有權限（#25），按鍵與滑鼠功能暫停中就不能顯示「已允許」
        statuses[.accessibility] = EventTapAccess.shared.isLost ? .unconfirmed : ScrollDirection.trusted ? .granted : .denied
        statuses[.screenRecording] = WindowThumbnails.hasPermission ? .granted : .denied
        statuses[.bluetooth] = BLEBatteryReader.authorized ? .granted : BLEBatteryReader.denied ? .denied : .askWhenUsed
        // 自動化的狀態要實際詢問 System Events 才知道，查詢本身可能跳出系統詢問，所以不查
        statuses[.automation] = .askWhenUsed
        // 系統錄音沒有公開的查詢方式：建立擷取時才知道，被拒時各 App 音量的卡片會說明
        statuses[.audioCapture] = AppVolumeController.shared.problem ? .denied : .askWhenUsed
        Notifier.shared.checkBlocked { blocked in statuses[.notifications] = blocked ? .denied : .granted }
    }
}
