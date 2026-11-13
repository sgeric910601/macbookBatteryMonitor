import SwiftUI

struct XDRBrightnessCard: View {
    let settings: AppSettings
    private let control = XDRBrightnessController.shared

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle("XDR 額外增亮（實驗性）", systemImage: "sun.max.fill")
                Toggle("啟用內建螢幕增亮", isOn: Binding(
                    get: { control.enabled },
                    set: { if $0 { control.enable() } else { control.disable() } }
                ))
                .disabled(!control.supported || control.preparing)
                Toggle("亮度鍵到頂後自動啟用 XDR", isOn: Binding(
                    get: { settings.xdrAutomaticActivation },
                    set: { settings.xdrAutomaticActivation = $0 }
                ))
                .disabled(!control.supported)
                HStack {
                    Text("增亮倍率")
                    Slider(value: Binding(get: { control.gain }, set: { control.setGain($0) }), in: 1...max(1.05, control.maximumGain), step: 0.05)
                        .disabled(!control.enabled || control.preparing || control.maximumGain <= 1)
                    Text("\(Int((control.gain * 100).rounded()))%")
                        .monospacedDigit().frame(width: 46, alignment: .trailing)
                }
                if let target = control.targetNits {
                    Text("峰值目標上限 \(target) nits，實際亮度由系統 EDR 餘裕決定。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(control.status).font(.callout).foregroundStyle(.secondary)
                Text(control.keysStatus).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("還原亮度") { control.disable() }
                    Button("輔助使用設定") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
                Text("支援內建 XDR 螢幕，接電或電池供電皆可使用。亮度鍵到頂後進入增亮，降低時先退出增亮；沒有按鍵權限時可用滑桿。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("增亮時顯示浮動亮度提示。nits 依系統螢幕規格與線性亮度估算，實際輸出受 EDR 餘裕限制。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("會增加耗電並影響 HDR 高光與色彩。睡眠、省電、溫度偏高或 30 分鐘後自動還原；重啟時維持一般亮度，亮度鍵到頂後可自動啟用。結束 App 時覆蓋層會一併移除。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
