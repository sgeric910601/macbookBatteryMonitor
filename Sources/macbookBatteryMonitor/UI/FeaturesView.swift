import SwiftUI

/// 側邊欄「擴充功能 → 功能管理」：依分組列出擴充功能，用開關啟用或停用。
/// 停用不是解除安裝：功能停止運作、從側邊欄拿掉，設定都保留，再啟用就回來
struct FeatureManagerView: View {
    @ObservedObject var settings: AppSettings

    private var groups: [String] {
        ExtensionFeature.allCases.map(\.group).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("只啟用會用到的功能。停用的功能完全不運作（不攔截按鍵或滑鼠、不監聽視窗），也從側邊欄拿掉；原本的設定都會保留，再啟用就回來。這裡的開關決定功能要不要出現，功能裡面的細項在它自己的設定頁調整。")
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("已啟用 \(settings.installedFeatures.count)／\(ExtensionFeature.allCases.count) 項")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        ForEach(groups, id: \.self) { group in
            Text(group)
                .font(.headline)
                .padding(.top, 8)
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    let features = ExtensionFeature.allCases.filter { $0.group == group }
                    ForEach(features) { feature in
                        row(feature)
                        if feature != features.last { Divider().padding(.vertical, 8) }
                    }
                }
            }
        }
        Text("大部分擴充功能需要「輔助使用」權限，用到時才會詢問（功能自己的開關原本就開著時，會在啟用時詢問）。停用「中文輸入法」時，Caps Lock 恢復系統預設的延遲。電池、充電、系統監控與充電夥伴是基本功能，一直都在。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ feature: ExtensionFeature) -> some View {
        return HStack(spacing: 12) {
            Image(systemName: SymbolCompat.name(feature.symbol))
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
            }
            Spacer()
            Toggle("啟用", isOn: Binding(get: { settings.isInstalled(feature) }, set: { settings.setInstalled(feature, $0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("啟用\(feature.title)")
        }
    }
}
