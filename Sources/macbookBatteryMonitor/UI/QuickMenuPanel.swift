import AppKit
import SwiftUI

/// 貓咪快捷面板：常用操作的捷徑。沒啟用的功能整塊不顯示。
/// 只裝 Command Line Tools 時不能用 @State，狀態都從各控制器讀
struct QuickMenuPanel: View {
    let settings: AppSettings
    let awake: KeepAwakeController
    let audio: AudioSwitchController
    /// 剪貼簿歷史不是 Observable：打開面板時的內容
    let clipboard: [String]
    var close: () -> Void
    var openSettings: (SettingsSection?) -> Void

    static let clipboardLimit = 5

    private var showsAudio: Bool { settings.isInstalled(.audioSwitch) }
    private var showsMic: Bool { showsAudio && audio.micSupported }
    private var showsCleaning: Bool { settings.isInstalled(.keyboardCleaning) }
    private var showsClipboard: Bool { settings.isInstalled(.clipboardHistory) }

    var body: some View {
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
        .padding(14)
        .frame(width: 340)
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
                        // 只有「直到關閉」看得出是哪一個；其他時間的剩餘分鐘顯示在上面的大按鈕
                        let selected = awake.state.isActive && duration == .indefinitely && awake.state.until == nil
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
                            ClipboardHistoryController.shared.clear()
                            close()
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
                openSettings(.features)
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
            .help("啟用或停用擴充功能")
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
