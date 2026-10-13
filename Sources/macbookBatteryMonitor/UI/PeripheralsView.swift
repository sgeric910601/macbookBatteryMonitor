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
                        if BLEBatteryReader.denied { bluetoothDenied }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(store.devices) { row($0) }
                        }
                    }
                }
                if BLEBatteryReader.denied, !store.devices.isEmpty { bluetoothDenied }
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

    /// 「左／右／盒」小標籤加電量；沒有這顆電池時不顯示，低於通知門檻時紅色（充電盒不通知，所以不變紅）
    @ViewBuilder private func levelColumn(_ label: String, _ level: Int?, threshold: Int) -> some View {
        if let level {
            VStack(spacing: 0) {
                Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
                Text("\(level)%")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(threshold > 0 && level <= threshold ? Color.red : Color.primary)
            }
        }
    }

    /// 藍牙權限被拒絕：羅技、Razer 等藍牙低功耗滑鼠與鍵盤的電量讀不到
    private var bluetoothDenied: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("沒有藍牙權限，讀不到羅技、Razer 等藍牙低功耗滑鼠與鍵盤的電量（Apple 的設備與耳機不受影響）。")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Button("打開系統設定的藍牙權限") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.caption)
        }
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
            Text(device.name).lineLimit(1)
            Spacer(minLength: 6)
            if device.detailText != nil {
                // 耳機：左耳、右耳、充電盒各一欄，不再另外只顯示一個數字
                HStack(spacing: 10) {
                    levelColumn("左", device.left, threshold: threshold)
                    levelColumn("右", device.right, threshold: threshold)
                    levelColumn("盒", device.caseLevel, threshold: 0)
                }
                // 三欄維持完整寬度（「100%」不換行、標籤不被擠掉），空間不夠時由左邊的名稱截斷
                .fixedSize()
            } else {
                Text(device.lowest.map { "\($0)%" } ?? "—")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(low ? Color.red : Color.primary)
            }
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
