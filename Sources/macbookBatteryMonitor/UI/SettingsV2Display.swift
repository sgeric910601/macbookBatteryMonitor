import AppKit
import SwiftUI

/// 新版設定的「螢幕亮度」頁：內建 XDR 螢幕的額外增亮。
/// 卡片上的按鈕啟用或停用這個功能，標題列的主開關
/// 「啟用內建螢幕增亮」，只管開始或還原增亮。版面照其他擴充功能頁：頁首的輔助使用橫幅、標題列的「監聽亮度鍵」標籤、
/// 不畫刻度的滑桿、運作狀態小標記，長說明收合。
struct SettingsV2XDRPage: View {
    let settings: AppSettings
    let ui: PanelState
    let state: SettingsV2State
    private let control = XDRBrightnessController.shared
    @Environment(\.settingsV2Tint) private var tint

    private typealias SwitchRow = SettingsView.SwitchRow

    private var installed: Bool { settings.isInstalled(.xdrBrightness) }
    /// 只有「亮度鍵到頂後自動啟用」要攔截亮度鍵，才需要輔助使用；滑桿不需要
    private var needsAccessibility: Bool { installed && settings.xdrAutomaticActivation }

    var body: some View {
        V2AccessibilityBanner(trusted: ui.scrollTrusted || !needsAccessibility)
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    IconTile(symbol: ExtensionFeature.xdrBrightness.symbol, tint: installed ? (tint ?? .accentColor) : .gray, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(ExtensionFeature.xdrBrightness.title).font(.headline)
                            Text("監聽亮度鍵")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                                .foregroundStyle(.secondary)
                        }
                        Text("讓內建 XDR 螢幕比平常更亮（實驗性）").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    V2Switch(title: "啟用內建螢幕增亮",
                             isOn: Binding(get: { installed && control.enabled }, set: setBoost),
                             tint: tint ?? .accentColor)
                        .disabled(!installed || !control.supported || control.preparing)
                }
                if !installed {
                    V2Note("啟用後會監聽亮度鍵（亮度鍵到頂後自動增亮時），並增加耗電。")
                    Button("啟用\(ExtensionFeature.xdrBrightness.title)") { settings.setInstalled(.xdrBrightness, true) }
                        .disabled(!control.supported)
                } else {
                    Divider()
                    statusRow
                    HStack(spacing: 8) {
                        Text("增亮倍率")
                        // 不用 step：每 5% 一格會畫出一整排刻度；放開時取到 5% 的倍數
                        Slider(value: Binding(get: { control.gain }, set: { control.setGain(($0 * 20).rounded() / 20) }),
                               in: 1...max(1.05, control.maximumGain))
                            .controlSize(.small)
                            .accessibilityLabel("增亮倍率")
                            .disabled(!control.enabled || control.preparing || control.maximumGain <= 1)
                        Text("\(Int((control.gain * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    if let target = control.targetNits {
                        V2Note("這台螢幕的峰值目標上限約 \(target) nits，實際亮度由系統的 EDR 餘裕決定。")
                    }
                    SwitchRow("亮度鍵到頂後自動增亮", isOn: Binding(
                        get: { settings.xdrAutomaticActivation },
                        set: { settings.xdrAutomaticActivation = $0 }
                    ))
                    .disabled(!control.supported)
                    if settings.xdrAutomaticActivation { keysRow }
                    HStack {
                        Button("還原亮度") { _ = control.disable() }
                            .disabled(!control.enabled)
                        // 停用時會先還原亮度
                        Button("停用\(ExtensionFeature.xdrBrightness.title)") { settings.setInstalled(.xdrBrightness, false) }
                    }
                    V2Disclosure(title: "說明", id: "xdr.help", state: state) {
                        VStack(alignment: .leading, spacing: 6) {
                            V2Note("支援內建 XDR 螢幕，接電或電池供電皆可使用。亮度鍵到頂後再按亮度增加鍵就接續增亮，降低時先退出增亮；沒有輔助使用權限時可以用上面的滑桿。")
                            V2Note("增亮時畫面上會出現浮動的亮度提示。nits 是依系統回報的螢幕規格與亮度估算，不是儀器量測，實際輸出受 EDR 餘裕限制。")
                            V2Note("會增加耗電並影響 HDR 高光與色彩。睡眠、鎖定、省電模式、溫度偏高或 30 分鐘後會自動還原；重新啟動後維持一般亮度，結束 App 時一併移除。")
                            V2Note("要完全停用這個功能（不再監聽亮度鍵並還原亮度），按上面的「停用」。")
                        }
                    }
                }
            }
        }
    }

    /// 增亮中：綠色「運作中」；否則顯示控制器回報的原因（例如不支援的螢幕、30 分鐘已到）
    @ViewBuilder private var statusRow: some View {
        if control.enabled {
            Label("增亮中", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if !control.status.isEmpty {
            V2Note(control.status)
        }
    }

    /// 亮度鍵監聽的狀態：缺輔助使用權限時橘色提醒（說明與按鈕在頁首橫幅），其餘照控制器回報
    @ViewBuilder private var keysRow: some View {
        if !ui.scrollTrusted {
            Label("需要允許「輔助使用」才能用亮度鍵增亮", systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            V2Note(control.keysStatus)
        }
    }

    /// 打開：開始增亮；關掉：還原亮度
    private func setBoost(_ on: Bool) {
        if on {
            control.enable()
        } else {
            _ = control.disable()
        }
    }
}
