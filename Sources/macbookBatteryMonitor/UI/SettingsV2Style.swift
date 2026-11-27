import AppKit
import SwiftUI

/// 設定視窗的外觀：不用系統的開關、勾選框、按鈕樣式，改用 App 自己的圓角卡片與主題色。
/// 共用元件（Card、CardTitle、IconTile、SettingsPicker）讀環境值 `settingsV2Tint`：設定視窗裡是這頁的主題色，
/// 面板（例如智慧充電頁）是 nil、照舊用系統樣式
private struct SettingsV2TintKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var settingsV2Tint: Color? {
        get { self[SettingsV2TintKey.self] }
        set { self[SettingsV2TintKey.self] = newValue }
    }
}

/// 開著、選到的顏色（平面單色，不用漸層）：所有頁面一致用 App 的薄荷綠，開或關一眼就分得出來（每頁的主題色只用在圖示與卡片）
enum V2Theme {
    static let on = Color(red: 0.20, green: 0.60, blue: 0.46)
}

/// 膠囊開關：開著是薄荷綠，關掉是淡灰；用 Button 做，才會跟著 .disabled 變灰、不能點
struct V2Switch: View {
    let title: String
    @Binding var isOn: Bool
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button { withAnimation(.snappy(duration: 0.18)) { isOn.toggle() } } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? AnyShapeStyle(V2Theme.on) : AnyShapeStyle(Color.primary.opacity(0.16)))
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .padding(2.5)
            }
            .frame(width: 38, height: 22)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "開啟" : "關閉")
        .accessibilityAddTraits(.isToggle)
    }
}

/// 一般的 Toggle 在新版視窗裡：文字在左、膠囊開關在右
struct V2ToggleStyle: ToggleStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        V2ToggleRow(configuration: configuration, tint: tint)
    }
}

/// V2ToggleStyle 的內容：要讀 isEnabled，VoiceOver 才不能操作變灰的開關
private struct V2ToggleRow: View {
    let configuration: ToggleStyleConfiguration
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            V2Switch(title: "", isOn: configuration.$isOn, tint: tint)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "開啟" : "關閉")
        .accessibilityAction { if isEnabled { configuration.isOn.toggle() } }
    }
}

/// 勾選框：主題色的圓角方塊
struct SettingsCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(configuration.isOn ? AnyShapeStyle(V2Theme.on) : AnyShapeStyle(Color.primary.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(configuration.isOn ? Color.clear : Color.primary.opacity(0.25)))
                    .overlay(Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .opacity(configuration.isOn ? 1 : 0))
                    .frame(width: 17, height: 17)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "已勾選" : "未勾選")
    }
}

/// 新版的按鈕：主題色淡底的膠囊
struct V2ButtonStyle: ButtonStyle {
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.32 : 0.16)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.35)))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
}

/// 下拉選單：膠囊外框＋目前的選項（不用系統的彈出按鈕外觀）
struct V2Menu<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Environment(\.settingsV2Tint) private var tint

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection { Label(option.label, systemImage: "checkmark") } else { Text(option.label) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(options.first { $0.value == selection }?.label ?? "").lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
            }
        }
        .menuStyle(.button)
        .buttonStyle(V2ButtonStyle(tint: tint ?? .accentColor))
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(title)
        .accessibilityValue(options.first { $0.value == selection }?.label ?? "")
    }
}

/// 時間（時：分）：兩個下拉選單，樣式和其他選項一致，不用系統的步進式日期欄位。分鐘 5 分一格，目前值不在格子上時也會列出
struct V2TimePicker: View {
    let title: String
    @Binding var selection: Date

    private var cal: Calendar { .current }
    private var hour: Int { cal.component(.hour, from: selection) }
    private var minute: Int { cal.component(.minute, from: selection) }

    private func set(hour: Int, minute: Int) {
        selection = cal.date(bySettingHour: hour, minute: minute, second: 0, of: selection) ?? selection
    }

    var body: some View {
        HStack(spacing: 4) {
            V2Menu(title: "\(title)（時）", options: (0..<24).map { ($0, String(format: "%02d", $0)) },
                   selection: Binding(get: { hour }, set: { set(hour: $0, minute: minute) }))
            Text(":").foregroundStyle(.secondary)
            V2Menu(title: "\(title)（分）",
                   options: Array(Set(stride(from: 0, to: 60, by: 5)).union([minute])).sorted().map { ($0, String(format: "%02d", $0)) },
                   selection: Binding(get: { minute }, set: { set(hour: hour, minute: $0) }))
        }
    }
}

/// 日期加時間：日期下拉（今天起 14 天）加上時間。不能選過去的日期
struct V2DateTimePicker: View {
    let title: String
    @Binding var selection: Date

    private var cal: Calendar { .current }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("Md E")
        return f
    }()

    private var days: [(value: Date, label: String)] {
        let today = cal.startOfDay(for: Date())
        var starts = (0..<14).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
        let current = cal.startOfDay(for: selection)
        if !starts.contains(current) { starts.append(current); starts.sort() }
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)
        return starts.map { ($0, $0 == today ? "今天" : $0 == tomorrow ? "明天" : Self.dayFormat.string(from: $0)) }
    }

    var body: some View {
        HStack(spacing: 6) {
            V2Menu(title: "\(title)（日期）", options: days,
                   selection: Binding(get: { cal.startOfDay(for: selection) }, set: { day in
                       let c = cal.dateComponents([.hour, .minute], from: selection)
                       selection = cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: day) ?? selection
                   }))
            V2TimePicker(title: title, selection: $selection)
        }
    }
}

/// 一列「標題 … 下拉選單」
struct V2MenuRow<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            V2Menu(title: title, options: options, selection: $selection)
        }
    }
}

/// 少量選項的分段按鈕：選到的是主題色實心
struct V2Segmented<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Environment(\.settingsV2Tint) private var tint

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.label)
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(selected ? AnyShapeStyle(V2Theme.on) : AnyShapeStyle(Color.clear)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title)：\(option.label)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }
}

/// 數字加減：－ 數值 ＋
struct V2Stepper: View {
    let title: String
    let text: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    @Environment(\.settingsV2Tint) private var tint
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 8) {
            button("minus", enabled: value - step >= range.lowerBound) { value -= step }
            Text(text).monospacedDigit().frame(minWidth: 64)
            button("plus", enabled: value + step <= range.upperBound) { value += step }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(text)
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: if value + step <= range.upperBound { value += step }
            case .decrement: if value - step >= range.lowerBound { value -= step }
            @unknown default: break
            }
        }
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill((tint ?? .accentColor).opacity(0.18)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

/// 「進階」收合區：展開狀態放在 SettingsV2State（只裝 Command Line Tools 時不能用 @State）
struct V2Disclosure<Content: View>: View {
    let title: String
    let id: String
    let state: SettingsV2State
    @ViewBuilder let content: Content

    private var expanded: Bool { state.expanded.contains(id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    if expanded { state.expanded.remove(id) } else { state.expanded.insert(id) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(title).font(.callout.weight(.medium))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "已展開" : "已收合")
            if expanded {
                content
            }
        }
    }
}

/// 說明文字（小字、次要色、可換行）
struct V2Note: View {
    let text: String
    var color: Color = .secondary

    init(_ text: String, color: Color = .secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 擴充功能的卡片：標題列右邊直接開關（＝功能管理的啟用），關著時只留標題列
struct V2FeatureCard<Content: View>: View {
    let feature: ExtensionFeature
    let subtitle: String
    /// 這個功能會監聽什麼（顯示成小標籤），例如「監聽鍵盤」
    let listens: String
    let settings: AppSettings
    /// 標題列開關要另外綁的值（例如視窗切換：加入且打開才算開）；nil 時綁「已加入」
    var isOn: Binding<Bool>? = nil
    @ViewBuilder let content: Content
    @Environment(\.settingsV2Tint) private var tint

    private var binding: Binding<Bool> {
        isOn ?? Binding(get: { settings.isInstalled(feature) }, set: { settings.setInstalled(feature, $0) })
    }
    private var installed: Bool { binding.wrappedValue }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    IconTile(symbol: feature.symbol, tint: installed ? (tint ?? .accentColor) : .gray, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(feature.title).font(.headline)
                            Text(listens)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                                .foregroundStyle(.secondary)
                        }
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    V2Switch(title: "啟用\(feature.title)",
                             isOn: binding,
                             tint: tint ?? .accentColor)
                }
                if installed {
                    Divider()
                    content
                }
            }
        }
    }
}

/// 擴充功能的運作狀態：運作中，或缺少輔助使用權限時的小標記（說明與按鈕在頁首的 V2AccessibilityBanner，不每張卡重複）
struct V2FeatureStatus: View {
    let running: Bool
    let trusted: Bool

    var body: some View {
        if running {
            Label("運作中", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if !trusted {
            Label("需要允許「輔助使用」才會運作", systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

/// 擴充功能頁的頁首：沒有輔助使用權限時說明一次怎麼打開
struct V2AccessibilityBanner: View {
    let trusted: Bool

    var body: some View {
        if !trusted {
            Card {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    V2Note("這頁的功能需要允許「輔助使用」：系統設定 → 隱私權與安全性 → 輔助使用（macOS 27 起叫「裝置控制和資料取用」），打開「\(AppEdition.appName)」。", color: .primary)
                    Spacer(minLength: 8)
                    Button("打開設定") { ScrollDirection.openAccessibilitySettings() }
                }
            }
        }
    }
}

/// 只有開關、沒有文字的 Toggle（文字另外排）：膠囊開關
struct SettingsSwitchStyle: ToggleStyle {
    @Environment(\.settingsV2Tint) private var tint

    func makeBody(configuration: Configuration) -> some View {
        V2Switch(title: "", isOn: configuration.$isOn, tint: tint ?? .accentColor)
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// 選單：面板裡（沒有主題色）是系統 Picker（呼叫端照舊可加 .labelsHidden()），設定視窗裡是膠囊下拉選單或分段按鈕
struct SettingsPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    var segmented = false
    /// 設定視窗裡不顯示標題（面板裡由呼叫端的 .labelsHidden() 決定）
    var hidesTitle = false
    /// 新版改成圖形格子：每個選項的 SF Symbol
    var symbol: ((Value) -> String)?
    @Environment(\.settingsV2Tint) private var tint

    init(_ title: String, selection: Binding<Value>, options: [(value: Value, label: String)],
         segmented: Bool = false, hidesTitle: Bool = false, symbol: ((Value) -> String)? = nil) {
        self.title = title
        _selection = selection
        self.options = options
        self.segmented = segmented
        self.hidesTitle = hidesTitle
        self.symbol = symbol
    }

    var body: some View {
        if tint != nil, let symbol {
            VStack(alignment: .leading, spacing: 6) {
                if !hidesTitle { Text(title) }
                V2Tiles(title: title, options: options, selection: $selection, minWidth: 100, graphicHeight: 32) { value in
                    V2SymbolGraphic(symbol: symbol(value), selected: value == selection)
                }
            }
        } else if tint != nil {
            if segmented {
                if hidesTitle {
                    V2Segmented(title: title, options: options, selection: $selection)
                } else {
                    HStack {
                        Text(title)
                        Spacer(minLength: 12)
                        V2Segmented(title: title, options: options, selection: $selection).frame(maxWidth: 280)
                    }
                }
            } else if hidesTitle {
                V2Menu(title: title, options: options, selection: $selection)
            } else {
                V2MenuRow(title: title, options: options, selection: $selection)
            }
        } else if segmented {
            native.pickerStyle(.segmented)
        } else {
            native
        }
    }

    private var native: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
        }
    }
}

/// 圖形化的選擇：每個選項一格，上面是圖、下面是名稱；選到的格子有薄荷綠的框
struct V2Tiles<Value: Hashable, Graphic: View>: View {
    let title: String
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var minWidth: CGFloat = 110
    var graphicHeight: CGFloat = 48
    @ViewBuilder let graphic: (Value) -> Graphic

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth), spacing: 8)], spacing: 8) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button { selection = option.value } label: {
                    VStack(spacing: 8) {
                        graphic(option.value)
                            .frame(height: graphicHeight)
                        Text(option.label)
                            .font(.caption)
                            .foregroundStyle(selected ? .primary : .secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(V2TileBackground(selected: selected))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title)：\(option.label)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// 可以開關的圖形格子（例如系統監控的四個模組）：開著時有薄荷綠的框與圖示
struct V2ToggleTile: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button { isOn.toggle() } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isOn ? V2Theme.on : Color.secondary)
                    .frame(height: 28)
                Text(title).font(.caption).foregroundStyle(isOn ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(V2TileBackground(selected: isOn))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "開啟" : "關閉")
        .accessibilityAddTraits(.isToggle)
    }
}

/// 圖形格子的底：平面淡色，選到時是薄荷綠的淡底與框
struct V2TileBackground: View {
    let selected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(selected ? V2Theme.on.opacity(0.14) : Color.primary.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? V2Theme.on : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1))
    }
}

/// 只用 SF Symbol 當圖的格子
struct V2SymbolGraphic: View {
    let symbol: String
    let selected: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 26, weight: .regular))
            .foregroundStyle(selected ? V2Theme.on : Color.secondary)
    }
}

/// 清單裡每一項的小圖示（周邊設備、連著的裝置）：放大並放在淡色方塊裡
struct V2ItemIcon: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 17, weight: .medium))
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
    }
}

/// 清單每一列左邊的功能圖示（功能管理、權限）：一律是這頁主題色的平面方塊、同樣大小
struct SettingsListIcon: View {
    let symbol: String
    @Environment(\.settingsV2Tint) private var tint

    var body: some View {
        IconTile(symbol: symbol, tint: tint ?? .accentColor, size: 34)
    }
}
