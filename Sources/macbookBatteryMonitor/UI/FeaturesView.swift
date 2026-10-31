import SwiftUI

/// 側邊欄「擴充功能 → 功能管理」：依分組列出擴充功能，按鈕加入或移除。
/// 用按鈕不用開關：開關留給功能自己的「打開／關閉」，兩者才不會混在一起
struct FeatureManagerView: View {
    let settings: AppSettings

    private var groups: [String] {
        AppFeature.allCases.map(\.group).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("只加入會用到的功能。移除的功能會停止，並從側邊欄拿掉；原本的設定都會保留，重新加入就回來。")
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("已加入 \(settings.installedFeatures.count)／\(AppFeature.allCases.count) 項")
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
                    let features = AppFeature.allCases.filter { $0.group == group }
                    ForEach(features) { feature in
                        row(feature)
                        if feature != features.last { Divider().padding(.vertical, 8) }
                    }
                }
            }
        }
        Text("擴充功能需要「輔助使用」權限；加入後，打開功能自己的開關時才會詢問。電池、充電、系統監控與充電夥伴是基本功能，一直都在。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ feature: AppFeature) -> some View {
        let installed = settings.isInstalled(feature)
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
            }
            Spacer()
            Button(installed ? "移除" : "加入") { settings.setInstalled(feature, !installed) }
                .accessibilityLabel("\(installed ? "移除" : "加入")\(feature.title)")
        }
    }
}
