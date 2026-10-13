import SwiftUI

/// 周邊設備分頁：連線中設備的電量，每個設備可以自己設定低電量通知門檻
struct PeripheralsView: View {
    @ObservedObject var store: PeripheralStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        Card(expand: true) {
            VStack(alignment: .leading, spacing: 8) {
                if store.devices.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(store.updated == nil ? "讀取中…" : "沒有偵測到連線中的周邊設備")
                            .font(.callout)
                        Text("支援會回報電量的藍牙鍵盤、滑鼠、觸控板與耳機")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(store.devices) { row($0) }
                        }
                    }
                }
                HStack {
                    Text(footerText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        store.refresh(includeAllBluetooth: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.loading)
                    .help("立即更新")
                }
            }
        }
        .onAppear { store.refreshIfStale() }
    }

    private var footerText: String {
        guard let updated = store.updated else { return "每 60 秒更新" }
        return "每 60 秒更新・\(updated.formatted(date: .omitted, time: .standard))"
    }

    private func row(_ device: PeripheralBattery) -> some View {
        let threshold = settings.peripheralThreshold(for: device.id)
        let low = device.lowest.map { threshold > 0 && $0 <= threshold } ?? false
        return HStack(spacing: 10) {
            Image(systemName: device.symbol)
                .font(.system(size: 17))
                .frame(width: 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).lineLimit(1)
                if let detail = device.detailText {
                    Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer()
            Text(device.lowest.map { "\($0)%" } ?? "—")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(low ? Color.red : Color.primary)
            Menu {
                Picker("低電量通知", selection: Binding(get: { threshold }, set: { settings.setPeripheralThreshold($0, for: device.id) })) {
                    ForEach(AppSettings.peripheralThresholdChoices, id: \.self) { value in
                        Text(value == 0 ? "不通知" : "低於 \(value)% 時通知").tag(value)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: threshold == 0 ? "bell.slash" : "bell")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(threshold == 0 ? "低電量通知：關閉" : "低於 \(threshold)% 時通知")
        }
        .accessibilityElement(children: .combine)
    }
}
