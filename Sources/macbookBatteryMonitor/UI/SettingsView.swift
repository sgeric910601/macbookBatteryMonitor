import SwiftUI

/// 設定 →「充電」最上面的充電上限卡片；SwitchRow 是設定頁共用的開關列
struct SettingsView: View {
    let chargeLimit: SystemChargeLimit
    /// 桌上型 Mac 沒有電池：不顯示充電上限
    var hasBattery = true
    /// 智慧充電進行中：充電上限滑桿的提示不同
    var planActive = false

    private var limitText: String {
        if chargeLimit.supported { return chargeLimit.limit >= 100 ? "不限制（100%）" : "\(chargeLimit.limit)%" }
        return ChargeLimitReader.lastKnown().map { "\($0.limit)%" } ?? "未設定"
    }

    var body: some View {
        // 桌上型 Mac 沒有電池，也沒有充電上限
        if hasBattery {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    if chargeLimit.supported {
                        // 和主面板的滑桿是同一個設定（滑桿自己有「充電上限」標題）
                        ChargeLimitSlider(control: chargeLimit, planActive: planActive)
                        Text("和主面板的滑桿、系統設定「電池」裡的充電上限同步。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        CardTitle("充電上限", systemImage: "checkmark.shield")
                        HStack {
                            Text("系統充電上限")
                            Spacer()
                            Text(limitText)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Text(ChargeLimitReader.lastKnown()?.active == false
                             ? "這台 Mac 無法從 App 調整；用電池時顯示的是上次接電時的數值。"
                             : "這台 Mac 無法從 App 調整，只顯示目前的設定。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("在系統設定中修改") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
    }

    struct SwitchRow: View {
        let title: String
        let isOn: Binding<Bool>

        init(_ title: String, isOn: Binding<Bool>) {
            self.title = title
            self.isOn = isOn
        }

        @Environment(\.settingsV2Tint) private var tint

        var body: some View {
            Toggle(title, isOn: isOn).toggleStyle(V2ToggleStyle(tint: tint ?? .accentColor))
        }
    }
}
