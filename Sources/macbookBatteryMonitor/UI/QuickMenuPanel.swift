import AppKit
import SwiftUI

/// 面板顯示哪一頁：只裝 Command Line Tools 時不能用 @State，放在控制器持有的物件裡
@MainActor
@Observable
final class QuickMenuState {
    enum Page { case main, features }
    var page: Page = .main
}

/// 貓咪快捷面板：常用操作的捷徑。沒啟用的功能整塊不顯示。
/// 只裝 Command Line Tools 時不能用 @State，狀態都從各控制器讀
struct QuickMenuPanel: View {
    let settings: AppSettings
    let state: QuickMenuState
    let awake: KeepAwakeController
    let audio: AudioSwitchController
    var close: () -> Void
    var openSettings: (SettingsSection?) -> Void

    static let clipboardLimit = 5

    private var showsAudio: Bool { settings.isInstalled(.audioSwitch) }
    private var showsMic: Bool { showsAudio && audio.micSupported }
    private var showsCleaning: Bool { settings.isInstalled(.keyboardCleaning) }
    private var showsClipboard: Bool { settings.isInstalled(.clipboardHistory) }
    /// 直接讀最新的歷史：面板開著時複製或清除，清單會跟著更新
    private var clipboard: [String] { ClipboardHistoryController.shared.history.items }

    /// 擴充功能頁疊在主畫面上、用主畫面的大小：切換時面板大小不變。主畫面在背後只佔位置，看不到也點不到
    var body: some View {
        mainPage
            .opacity(state.page == .main ? 1 : 0)
            .allowsHitTesting(state.page == .main)
            .accessibilityHidden(state.page != .main)
            // 也拿掉鍵盤焦點：開著「完整鍵盤控制」時，Tab 不會跳到看不見的按鈕
            .disabled(state.page != .main)
            .overlay {
                if state.page == .features { featuresPage }
            }
            .padding(14)
            .frame(width: 340)
    }

    private var mainPage: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                awakeTile
                if showsMic { micTile }
                if showsCleaning { cleaningTile }
            }
            awakeCard
            if showsAudio, !audio.outputs.isEmpty { audioCard }
            if showsClipboard { clipboardCard }
            footer
        }
    }

    // MARK: - 擴充功能頁

    /// 快捷選單本身不列：在這裡關掉，面板和貓咪圖示會一起消失
    /// 面板每次打開才建立，所以這裡只查一次這台 Mac 有沒有支援的內建 XDR 螢幕
    private let xdrSupported = XDRBrightnessController.shared.checkSupport()

    /// 沒有支援的內建 XDR 螢幕時不能加入 XDR 增亮；已加入的仍列出來，可以移除
    private var panelFeatures: [ExtensionFeature] {
        ExtensionFeature.allCases.filter {
            $0 != .quickMenu && !($0 == .xdrBrightness && !xdrSupported && !settings.isInstalled($0))
        }
    }

    private var featureGroups: [String] {
        panelFeatures.map(\.group).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    private var featuresPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    state.page = .main
                } label: {
                    Label("返回", systemImage: "chevron.left")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                Spacer()
                Text("擴充功能")
                    .font(.headline)
                Spacer()
                // 和左邊的「返回」等寬，標題置中
                Label("返回", systemImage: "chevron.left").font(.callout.weight(.medium)).hidden()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(featureGroups, id: \.self) { group in
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(panelFeatures.filter { $0.group == group }) { feature in
                                    FeatureRow(feature: feature, settings: settings, openPermissions: { openSettings(.permissions) })
                                }
                            }
                        }
                    }
                }
            }
            HStack {
                Text("需要權限而還沒允許的功能，打開時會帶你到權限頁")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("更多設定…") { openSettings(.features) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 大按鈕

    private var awakeTile: some View {
        // 每 30 秒重畫一次；剩餘時間用現在時間算（不能用上次重畫的時間，剛按下時會多出一分鐘）
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            QuickTile(symbol: awake.state.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
                      title: "防止休眠",
                      detail: awake.state.isActive ? (awake.state.remainingText(now: Date()) ?? "直到關閉") : "關閉",
                      on: awake.state.isActive, tint: .orange) {
                if awake.state.isActive { awake.stop() } else { awake.start(.indefinitely) }
            }
        }
    }

    private var micTile: some View {
        QuickTile(symbol: audio.micMuted ? "mic.slash.fill" : "mic.fill",
                  title: "麥克風",
                  detail: audio.micMuted ? "已靜音" : "未靜音",
                  on: audio.micMuted, tint: .red) {
            audio.toggleMic()
        }
        .help(audio.micTitle)
    }

    private var cleaningTile: some View {
        QuickTile(symbol: "sparkles", title: "鍵盤清潔", detail: "\(settings.keyboardCleaningSeconds) 秒",
                  on: false, tint: .teal) {
            close()
            // 沒有「輔助使用」權限：跳出系統的詢問，並打開設定的權限頁，不要什麼都沒發生
            guard !KeyboardCleaningController.shared.start(seconds: settings.keyboardCleaningSeconds) else { return }
            ScrollDirection.requestTrust()
            openSettings(.permissions)
        }
        .help("鎖住鍵盤 \(settings.keyboardCleaningSeconds) 秒，方便擦鍵盤")
    }

    // MARK: - 卡片

    private var awakeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                QuickCardTitle("防止休眠時間", symbol: "timer", tint: .orange)
                HStack(spacing: 6) {
                    ForEach(KeepAwake.Duration.allCases, id: \.self) { duration in
                        let selected = awake.state.duration == duration
                        Button { awake.start(duration) } label: {
                            Text(duration.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(selected ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(selected ? AnyShapeStyle(Color.orange.gradient) : AnyShapeStyle(Color.primary.opacity(0.08))))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                Toggle(isOn: Binding(get: { awake.keepDisplayOn }, set: { awake.keepDisplayOn = $0 })) {
                    Label("螢幕也保持亮著", systemImage: "display")
                        .font(.callout)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    private var audioCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                QuickCardTitle("音訊輸出", symbol: "speaker.wave.2.fill", tint: .blue)
                    .padding(.bottom, 4)
                ForEach(audio.outputs, id: \.id) { output in
                    QuickRow(symbol: AudioDevices.symbol(transport: output.transport), tint: .blue,
                             title: output.name, selected: output.isCurrent) {
                        audio.select(output.id)
                    }
                }
            }
        }
    }

    private var clipboardCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    QuickCardTitle("剪貼簿歷史", symbol: "doc.on.clipboard.fill", tint: .purple)
                    Spacer()
                    if !clipboard.isEmpty {
                        Button {
                            // 清除後面板留著，清單變回空的
                            ClipboardHistoryController.shared.clear()
                        } label: {
                            Label("清除", systemImage: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.bottom, 4)
                if clipboard.isEmpty {
                    Text("複製的文字會出現在這裡")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                ForEach(Array(clipboard.prefix(Self.clipboardLimit).enumerated()), id: \.offset) { _, text in
                    QuickRow(symbol: Self.clipboardSymbol(text), tint: .purple,
                             title: ClipboardHistory.preview(text), selected: false) {
                        ClipboardHistoryController.shared.restore(text)
                        close()
                    }
                    .help(String(text.prefix(500)))
                }
            }
        }
    }

    /// 剪貼簿項目的圖示：網址、多行文字、一般文字
    private static func clipboardSymbol(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return "link" }
        return trimmed.contains("\n") ? "text.alignleft" : "textformat"
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                state.page = .features
            } label: {
                HStack(spacing: 7) {
                    IconTile(symbol: "square.grid.2x2.fill", tint: .indigo, size: 22)
                    Text("功能管理")
                        .font(.callout.weight(.medium))
                }
                .padding(.leading, 5)
                .padding(.trailing, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("在面板裡啟用或停用擴充功能")
            Spacer()
            FooterIcon(symbol: "gearshape.fill", help: "設定") { openSettings(nil) }
            FooterIcon(symbol: "power", help: "結束\(AppEdition.appName)") { NSApp.terminate(nil) }
        }
        .padding(.top, 2)
    }
}

/// 卡片標題：彩色小方塊圖示加文字
private struct QuickCardTitle: View {
    let title: String
    let symbol: String
    let tint: Color

    init(_ title: String, symbol: String, tint: Color) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 7) {
            IconTile(symbol: symbol, tint: tint, size: 20)
            Text(title)
                .font(.callout.weight(.semibold))
        }
    }
}

/// 頁尾的圓形圖示按鈕
private struct FooterIcon: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// 面板上方的大按鈕：開著時整塊上色
private struct QuickTile: View {
    let symbol: String
    let title: String
    let detail: String
    let on: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(on ? .white : tint)
                    .frame(height: 24)
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(on ? .white : .primary)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(on ? .white.opacity(0.85) : .secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(on ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.primary.opacity(0.045))))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(on ? 0 : 0.07)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(detail)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// 擴充功能頁的一列：圖示、名稱、背景會做什麼、開關
private struct FeatureRow: View {
    let feature: ExtensionFeature
    let settings: AppSettings
    /// 系統的權限詢問會讓面板收起來：還沒允許時直接帶到設定的權限頁，不要什麼都沒發生
    var openPermissions: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            IconTile(symbol: feature.symbol, tint: .indigo, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(feature.title)
                    .font(.callout)
                Text(feature.badge)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .help(feature.detail)
            Spacer()
            Toggle(feature.title, isOn: Binding(get: { settings.isInstalled(feature) }, set: { on in
                settings.setInstalled(feature, on)
                if on, feature.needsAccessibility, !AXIsProcessTrusted() { openPermissions() }
            }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

/// 卡片裡可點的一列（音訊裝置、剪貼簿項目）：選中的整列上色並打勾
private struct QuickRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? .white : tint)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.14))))
                Text(title)
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? tint.opacity(0.12) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
