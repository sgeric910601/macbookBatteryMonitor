import SwiftUI

/// 「今日」分頁：今天用掉、補回多少電量，接電幾次，用電池多久、最長一次多久
struct DailyRecapView: View {
    let recap: DailyBatteryRecap

    var body: some View {
        Card(expand: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        CardTitle("今日電量回顧", systemImage: "sun.max")
                        Text(headline).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(recap.netChange.map { $0 > 0 ? "+\($0)%" : "\($0)%" } ?? "—")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text("淨變化").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                HStack(spacing: 8) {
                    metric("用掉", "\(recap.usedPercent)%", SymbolCompat.name("battery.25percent"), .orange)
                    metric("補回", "\(recap.chargedPercent)%", "bolt.fill", .green)
                    metric("接電", "\(recap.plugInCount) 次", "powerplug.fill", .cyan)
                }
                HStack(spacing: 8) {
                    wide("使用電池", duration(recap.unpluggedMinutes), "clock")
                    wide("最長一次", duration(recap.longestUnpluggedMinutes), "figure.walk")
                }
                Spacer(minLength: 0)
                Text("依電量歷史計算（App 沒在執行的時段不列入）")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        recap.startPercent == nil ? "今天還沒有紀錄" : "今天用掉 \(recap.usedPercent)%，補回 \(recap.chargedPercent)%"
    }

    private func metric(_ title: String, _ value: String, _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value).font(.headline).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func wide(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.callout.weight(.semibold)).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func duration(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) 分鐘" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) 小時" : "\(hours) 小時 \(rest) 分"
    }
}
