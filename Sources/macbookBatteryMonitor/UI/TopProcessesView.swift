import AppKit
import SwiftUI

struct TopProcessesView: View {
    @ObservedObject var store: BatteryStore

    var body: some View {
        Card(expand: true) {
            VStack(alignment: .leading, spacing: 7) {
                if !store.processesLoaded {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else if store.topProcesses.isEmpty {
                    Text("目前沒有明顯耗電的程式")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    let maxPower = store.topProcesses.map(\.power).max() ?? 1
                    ForEach(store.topProcesses) { p in
                        HStack(spacing: 8) {
                            icon(for: p)
                                .frame(width: 18, height: 18)
                            Text(p.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Capsule()
                                .fill(Color.orange.softGradient)
                                .frame(width: max(3, 70 * p.power / maxPower), height: 5)
                                .frame(width: 70, alignment: .leading)
                            Text(String(format: "%.1f", p.power))
                                .monospacedDigit()
                                .frame(width: 42, alignment: .trailing)
                        }
                        .font(.callout)
                    }
                }
                Spacer(minLength: 0)
                Text("數值為「能源影響」指標（相對值，不是瓦數），\(AppSettings.shared.updateText)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            // 持續取樣；切換分頁或關閉面板時由 AppDelegate 停掉
            store.setProcessSampling(active: true)
        }
    }

    @ViewBuilder
    private func icon(for p: EnergyProcess) -> some View {
        if let path = p.appPath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
        } else {
            Image(systemName: "gearshape.fill")
                .resizable()
                .scaledToFit()
                .padding(2)
                .foregroundStyle(.secondary)
        }
    }
}
