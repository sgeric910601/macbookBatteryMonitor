import SwiftUI

/// 側邊欄「擴充功能 → 功能管理」：以大項為單位打開或關掉。
/// 打開大項只讓它的頁面出現在側邊欄，不啟用任何功能（也不要求權限）；功能在該頁逐項啟用。
/// 關掉大項時組內功能全部停用、頁面從側邊欄拿掉，設定都保留
struct FeatureManagerView: View {
    let settings: AppSettings
    /// 這台 Mac 現在有沒有支援的內建 XDR 螢幕
    @State private var xdrSupported = true

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("先打開要用的大項，它的頁面才會出現在左側；再到那一頁逐項啟用需要的功能，用到權限的功能在啟用時才會詢問。關掉大項時，裡面的功能全部停用、不再運作（不攔截按鍵或滑鼠、不監聽視窗），原本的設定都會保留。")
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("已打開 \(settings.enabledFeatureGroups.count)／\(ExtensionFeature.groupOrder.count) 個大項・已啟用 \(settings.installedFeatures.count)／\(ExtensionFeature.allCases.count) 個功能")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { xdrSupported = XDRBrightnessController.shared.checkSupport() }
        // 頁面開著時闔上筆電或接上外接螢幕，也跟著更新
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            xdrSupported = XDRBrightnessController.shared.checkSupport()
        }
        ForEach(ExtensionFeature.groupOrder, id: \.self) { group in
            let features = ExtensionFeature.members(of: group)
            let enabled = settings.isGroupEnabled(group)
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group).font(.headline)
                            Text(enabled ? "已啟用 \(features.filter(settings.isInstalled).count)／\(features.count) 個功能，到「\(group == ExtensionFeature.startupItems.group ? "權限與登入項目" : group)」頁逐項啟用" : "打開後到它的頁面逐項啟用")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("打開\(group)", isOn: Binding(get: { enabled }, set: { settings.setGroupEnabled(group, $0) }))
                            .toggleStyle(SettingsSwitchStyle())
                            .labelsHidden()
                            .accessibilityLabel("打開\(group)")
                    }
                    .padding(.bottom, 8)
                    ForEach(features) { feature in
                        Divider().padding(.vertical, 8)
                        row(feature)
                    }
                }
            }
        }
        Text("電池、充電、系統監控與充電夥伴是基本功能，一直都在。停用「中文輸入法」時，Caps Lock 恢復系統預設的延遲。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ feature: ExtensionFeature) -> some View {
        let unsupported = feature == .xdrBrightness && !xdrSupported
        return HStack(spacing: 12) {
            Image(systemName: feature.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.85)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(feature.title).font(.body.weight(.medium))
                    Text(feature.badge)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
                Text(feature.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if unsupported {
                    Text("這台 Mac 現在沒有支援的內建 XDR 螢幕，不會啟動（闔上筆電只接外接螢幕時也一樣）")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Text(settings.isInstalled(feature) ? "已啟用" : "未啟用")
                .font(.caption)
                .foregroundStyle(settings.isInstalled(feature) ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
        }
    }
}
