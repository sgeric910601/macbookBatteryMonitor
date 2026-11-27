import AppKit
import SwiftUI

/// 新版設定 →「選單列」：每個顯示方式直接畫出選單列上的樣子（和 AppDelegate 一樣用 StatusIconRenderer 組），
/// 充電圖示的預覽固定顯示，自訂選項收合。
struct SettingsV2MenuBarPage: View {
    let settings: AppSettings
    let hasBattery: Bool
    let state: SettingsV2State

    /// 預覽用的範例：68%、還能用 3 小時 42 分
    private static let percent = 68
    private static let minutes = 222

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle("電池圖示", systemImage: "menubar.rectangle")
                if hasBattery {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(MenuBarDisplay.allCases) { display in
                            DisplayOption(display: display, selected: settings.display == display,
                                          preview: preview(display, state: .discharging)) {
                                settings.display = display
                            }
                        }
                    }
                } else {
                    Text("沒有電池的 Mac 在選單列顯示系統耗電瓦數。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        if hasBattery {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        CardTitle("充電時的樣子", systemImage: "bolt.fill")
                        Spacer()
                        MenuBarSample { preview(settings.display, state: .charging) }
                            .accessibilityLabel("充電中 \(Self.percent)% 的預覽")
                    }
                    V2Disclosure(title: "自訂充電圖示（調整時右邊的預覽會跟著變）", id: "menuBar.charging", state: state) {
                        chargingOptions
                    }
                }
            }
        }
    }

    /// 和 AppDelegate.updateStatusItem 相同的組法：圖示在文字左邊（圖示內百分比）或右邊
    @ViewBuilder private func preview(_ display: MenuBarDisplay, state: PowerState) -> some View {
        let inlinePercent = display == .iconPercentAndTime
        let icon = display == .percentOnly ? nil : StatusIconRenderer.image(
            percent: Self.percent, state: state, low: false, showsPercent: inlinePercent,
            chargingColor: settings.chargingIconColor, chargingTextColor: settings.chargingIconTextColor)
        let text = Self.text(display, state: state)
        HStack(spacing: 4) {
            if inlinePercent, let icon { Image(nsImage: icon) }
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
            }
            if !inlinePercent, let icon { Image(nsImage: icon) }
        }
    }

    private static func text(_ display: MenuBarDisplay, state: PowerState) -> String {
        switch display {
        case .iconAndPercent: return "\(percent)%"
        case .percentOnly: return state == .charging ? "⚡\(percent)%" : "\(percent)%"
        case .iconOnly: return ""
        case .iconAndTime, .iconPercentAndTime: return Format.clock(minutes) ?? "\(percent)%"
        }
    }

    @ViewBuilder private var chargingOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            V2MenuRow(title: "百分比文字", options: [("white", "白色"), ("black", "黑色"), ("automatic", "跟隨系統外觀")],
                      selection: binding(\.chargingIconText))
            V2MenuRow(title: "充電顏色", options: [("native", "Apple 原生綠"), ("mint", "薄荷綠"), ("emerald", "翡翠綠"),
                                                ("lime", "萊姆綠"), ("custom", "自訂色盤")],
                      selection: binding(\.chargingIconPreset))
            if settings.chargingIconPreset == "custom" {
                ColorPicker("自訂充電顏色", selection: Binding(
                    get: { Color(nsColor: settings.chargingIconBaseColor) },
                    set: { settings.chargingIconColorData = try? NSKeyedArchiver.archivedData(
                        withRootObject: NSColor($0), requiringSecureCoding: true) }
                ), supportsOpacity: false)
            }
            HStack {
                Text("底色不透明度")
                // 不用 step：每 1% 一格會畫出一整排刻度；取到 1% 的倍數
                Slider(value: Binding(get: { settings.chargingIconOpacity },
                                      set: { settings.chargingIconOpacity = ($0 * 100).rounded() / 100 }), in: 0...1)
                    .accessibilityLabel("充電底色不透明度")
                Text("\(Int((settings.chargingIconOpacity * 100).rounded()))%")
                    .monospacedDigit().frame(width: 42, alignment: .trailing)
            }
            Toggle("充電時顯示流光", isOn: binding(\.chargingIconFlow))
            V2Note("依實際電量比例填充。省電模式與減少動態效果會停止流光。")
            Button("還原圖示預設") {
                settings.chargingIconText = "white"
                settings.chargingIconNativeColor = true
                settings.chargingIconPreset = "native"
                settings.chargingIconOpacity = 1
                settings.chargingIconColorData = nil
                settings.chargingIconFlow = true
            }
        }
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }
}

/// 一個顯示方式：上面是選單列的樣子，下面是名稱；選到的有框
private struct DisplayOption<Preview: View>: View {
    let display: MenuBarDisplay
    let selected: Bool
    let preview: Preview
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 8) {
                MenuBarSample { preview }
                Text(display.title)
                    .font(.caption)
                    .foregroundStyle(selected ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("選單列顯示方式：\(display.title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 選單列的一小段背景，讓預覽看起來像在選單列上（跟著系統的深色或淺色外觀）
private struct MenuBarSample<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }
}
