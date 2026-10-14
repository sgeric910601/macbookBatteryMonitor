import AVFoundation
import SwiftUI
import VideoToolbox

/// 主面板資訊卡最上方的「智慧充電」列：左邊是充電夥伴（貓咪）或電量條，右邊是排程狀態，點一下打開智慧充電頁
struct ChargingJourneyPresentation: Equatable {
    enum Tint: Equatable { case neutral, blue, green, orange }
    /// 充電夥伴旁邊的小標示
    enum Badge: Equatable {
        case sleeping, paused, ready, late

        var symbol: String {
            switch self {
            case .sleeping: return "moon.zzz.fill"
            case .paused: return "pause.circle.fill"
            case .ready: return "checkmark.circle.fill"
            case .late: return "exclamationmark.circle.fill"
            }
        }
    }

    var title: String
    var detail: String
    var progress: Double
    var tint: Tint
    /// 貓咪躺在充電墊上（充電中）或只有貓咪
    var onPad: Bool
    var badge: Badge?
    var animatedFlow: Bool

    /// 電池夥伴的表情
    enum Mood: Equatable { case resting, sleeping, charging, happy, worried }

    var mood: Mood {
        switch badge {
        case .sleeping: return .sleeping
        case .ready: return .happy
        case .late, .paused: return .worried
        case nil: return onPad ? .charging : .resting
        }
    }

    static func make(percent: Int, charging: Bool, decision: ChargingPlanDecision?, now: Date = Date()) -> ChargingJourneyPresentation {
        let progress = min(1, max(0, Double(percent) / 100))
        guard let decision else {
            // 沒有排程時也跟著充電狀態變色：充電中是綠色（電量條、電池夥伴與光點的光暈）
            return .init(title: "智慧充電", detail: "指定時間前充好，平常維持保養上限",
                         progress: progress, tint: charging ? .green : .neutral, onPad: charging, badge: nil, animatedFlow: charging)
        }
        let deadline = time(decision.deadline, now: now)
        let target = "\(decision.targetPercent)%"
        switch decision.phase {
        case .unsupported:
            return .init(title: "智慧充電", detail: "這台 Mac 不支援調整充電上限", progress: progress, tint: .neutral,
                         onPad: false, badge: nil, animatedFlow: false)
        case .unplugged:
            return .init(title: "等待接上電源", detail: "\(deadline) 前充到 \(target)", progress: progress,
                         tint: .neutral, onPad: false, badge: nil, animatedFlow: false)
        case .waiting:
            return .init(title: "等待開始", detail: "\(time(decision.startAt, now: now)) 開始充電，\(deadline) 前到 \(target)",
                         progress: progress, tint: .blue, onPad: false, badge: .sleeping, animatedFlow: false)
        case .starting:
            return .init(title: "準備充電", detail: "\(deadline) 前到 \(target)", progress: progress,
                         tint: .blue, onPad: true, badge: nil, animatedFlow: false)
        case .charging:
            return .init(title: "充電中", detail: "約 \(duration(decision.requiredMinutes))後到 \(target)，目標 \(deadline)",
                         progress: progress, tint: .green, onPad: true, badge: nil, animatedFlow: true)
        case .systemPaused:
            return .init(title: "macOS 暫停充電", detail: "目標 \(deadline) 前到 \(target)",
                         progress: progress, tint: .orange, onPad: true, badge: .paused, animatedFlow: false)
        case .ready:
            return .init(title: "已準備好", detail: "已達 \(target)", progress: progress,
                         tint: .green, onPad: false, badge: .ready, animatedFlow: false)
        case .late:
            return .init(title: "可能無法準時", detail: "繼續充電中，原定 \(deadline) 前到 \(target)",
                         progress: progress, tint: .orange, onPad: charging, badge: .late, animatedFlow: charging)
        }
    }

    /// 不能從 App 調整充電上限的 Mac（Intel、macOS 26 以前）：一樣顯示充電夥伴，旁邊說明沒有智慧充電
    static func unsupported(percent: Int, charging: Bool) -> ChargingJourneyPresentation {
        return .init(title: "充電夥伴", detail: "這台 Mac 不支援智慧充電，點一下可換外觀",
                     progress: min(1, max(0, Double(percent) / 100)), tint: charging ? .green : .neutral,
                     onPad: charging, badge: nil, animatedFlow: charging)
    }

    /// 今天只顯示時間，明天加上「明天」，其他日子加上日期與星期
    static func time(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        let clock = date.formatted(date: .omitted, time: .shortened)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return clock
        case 1: return "明天 \(clock)"
        default: return date.formatted(.dateTime.month().day().weekday().hour().minute())
        }
    }

    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(max(1, minutes)) 分鐘" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) 小時" : "\(hours) 小時 \(rest) 分"
    }
}

/// 充電上限滑桿加上智慧充電：左邊是充電夥伴（或電量條），右邊上方是滑桿、下方一兩行排程狀態，
/// 點夥伴或狀態打開智慧充電頁。和滑桿放在同一列，主面板只比沒有智慧充電時高一點
struct ChargingJourneyView<Control: View>: View {
    let presentation: ChargingJourneyPresentation
    let appearance: ChargingAppearance
    /// 面板開著、沒有省電模式時才播放動畫
    let animated: Bool
    let open: () -> Void
    /// 充電上限滑桿
    @ViewBuilder var control: Control

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: open) {
                Group {
                    switch appearance {
                    case .companion:
                        ChargingCompanion(onPad: presentation.onPad, badge: presentation.badge, tint: tint,
                                          animated: animated && !reduceMotion)
                            .frame(width: 48, height: 50)
                    case .mascot:
                        BatteryMascot(mood: presentation.mood, level: presentation.progress, tint: tint,
                                      animated: animated && !reduceMotion)
                            .frame(width: 48, height: 50)
                    case .energy:
                        // 和貓咪同高，切換外觀時下面的內容不會跟著移動
                        energyBar
                            .frame(width: 48, height: 50)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("設定智慧充電")
            .accessibilityLabel("設定智慧充電")
            VStack(alignment: .leading, spacing: 3) {
                control
                Button(action: open) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        (Text(presentation.title).fontWeight(.semibold).foregroundColor(.primary)
                            + Text("・" + presentation.detail).foregroundColor(.secondary))
                            .font(.caption)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 2)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("設定智慧充電")
                .accessibilityLabel("智慧充電，\(presentation.title)，\(presentation.detail)")
            }
        }
    }

    /// 電力流動：電量條，充電中有一個光點往右流。光點用 Core Animation 播放，不逐幀更新 SwiftUI：
    /// 逐幀更新會讓整個面板每幀重新排版、文字重畫，2015 MacBook Air 實測 CPU 約 26%
    private var energyBar: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(tint.opacity(0.18)).frame(height: 8)
            Capsule().fill(tint.opacity(0.8)).frame(width: max(8, 48 * presentation.progress), height: 8)
            if animated && !reduceMotion && presentation.animatedFlow {
                FlowDot(glow: nsTint, travel: 40)
                    .frame(width: 48, height: 14)
            }
            Image(systemName: presentation.badge?.symbol ?? "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .offset(y: -14)
        }
    }

    private var nsTint: NSColor {
        switch presentation.tint {
        case .neutral: return .secondaryLabelColor
        case .blue: return .systemCyan
        case .green: return .systemGreen
        case .orange: return .systemOrange
        }
    }

    private var tint: Color {
        switch presentation.tint {
        case .neutral: return .secondary
        case .blue: return .cyan
        case .green: return .green
        case .orange: return .orange
        }
    }
}

/// 充電夥伴：會動的貓咪。充電時躺在發光的充電墊上、上方有充電波紋，其他時候只有貓咪在睡覺。
/// 動畫是透明背景的 HEVC 影片（6 秒循環）；不播放時（面板關閉、省電模式、減少動態效果、截圖）顯示第一格的靜態圖
struct ChargingCompanion: View {
    let onPad: Bool
    let badge: ChargingJourneyPresentation.Badge?
    let tint: Color
    let animated: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if animated, Self.videoAllowed, let url = Self.resource(onPad, "mov") {
                    LoopingVideo(url: url)
                } else if let url = Self.resource(onPad, "png"), let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().interpolation(.high)
                }
            }
            .aspectRatio(152.0 / 160.0, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let badge {
                Image(systemName: badge.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white, tint)
                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).padding(1))
            }
        }
        .accessibilityHidden(true)
    }

    /// 開發用截圖畫不出影片圖層，改用靜態圖。沒有 HEVC 硬體解碼的 Mac（例如 2015 年的 Intel 機型）也用靜態圖：
    /// 帶透明的 HEVC 只能用 CPU 解碼，2015 MacBook Air 實測面板開著時 CPU 約 8%
    static let videoAllowed = !CommandLine.arguments.contains { $0.hasPrefix("--snapshot") || $0.hasPrefix("--screenshots") }
        && VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)

    static func resource(_ onPad: Bool, _ ext: String) -> URL? {
        Bundle.main.url(forResource: onPad ? "companion-charging" : "companion-resting", withExtension: ext)
    }
}

/// 循環播放一段沒有聲音的透明影片
private struct LoopingVideo: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> LoopingVideoView { LoopingVideoView(url: url) }
    func updateNSView(_ view: LoopingVideoView, context: Context) { view.play(url) }
    static func dismantleNSView(_ view: LoopingVideoView, coordinator: ()) { view.stop() }
}

private final class LoopingVideoView: NSView {
    private let player = AVQueuePlayer()
    private let playerLayer = AVPlayerLayer()
    private var looper: AVPlayerLooper?
    private var url: URL?

    init(url: URL) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = .clear
        // 要求 BGRA 輸出，影片的透明度才會保留
        playerLayer.pixelBufferAttributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        layer?.addSublayer(playerLayer)
        play(url)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func play(_ url: URL) {
        guard url != self.url else { return }
        self.url = url
        looper?.disableLooping()
        player.removeAllItems()
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.play()
    }

    func stop() {
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        url = nil
    }
}

/// 電量條上往右流的光點（1.6 秒一趟）。動畫交給 Core Animation，SwiftUI 只在設定改變時更新
private struct FlowDot: NSViewRepresentable {
    let glow: NSColor
    let travel: CGFloat

    func makeNSView(context: Context) -> FlowDotView { FlowDotView() }

    func updateNSView(_ view: FlowDotView, context: Context) {
        view.configure(glow: glow, travel: travel)
    }
}

final class FlowDotView: NSView {
    private let dot = CALayer()
    private var glow: NSColor?
    private var travel: CGFloat = 0
    private var laidOut: CGRect = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        dot.bounds = CGRect(x: 0, y: 0, width: 6, height: 6)
        dot.cornerRadius = 3
        dot.backgroundColor = NSColor.white.cgColor
        dot.shadowOpacity = 1
        dot.shadowRadius = 4
        dot.shadowOffset = .zero
        layer?.addSublayer(dot)
    }

    required init?(coder: NSCoder) { nil }

    /// 面板每秒更新時也會呼叫；設定沒變就不重來，光點才不會每秒跳回起點
    func configure(glow: NSColor, travel: CGFloat) {
        guard glow != self.glow || travel != self.travel else { return }
        self.glow = glow
        self.travel = travel
        restart()
    }

    override func layout() {
        super.layout()
        guard bounds != laidOut else { return }
        laidOut = bounds
        restart()
    }

    private func restart() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.shadowColor = glow?.cgColor
        dot.position = CGPoint(x: 3, y: bounds.midY)
        dot.removeAnimation(forKey: "flow")
        let flow = CABasicAnimation(keyPath: "position.x")
        flow.fromValue = 3
        flow.toValue = 3 + travel
        flow.duration = 1.6
        flow.repeatCount = .infinity
        dot.add(flow, forKey: "flow")
        CATransaction.commit()
    }
}

/// 電池夥伴：有表情的電池，裡面的底色是目前的電量。
/// 等待時閉眼睡覺、準備或正在充電時微笑、充好時開心、可能延遲或系統暫停時擔心；面板開著時偶爾眨眼
struct BatteryMascot: View {
    let mood: ChargingJourneyPresentation.Mood
    /// 0…1
    let level: Double
    let tint: Color
    let animated: Bool

    var body: some View {
        Group {
            if animated && mood != .sleeping {
                // 每 4 秒眨一次眼：只在閉眼與張眼的那一刻更新，不必一直重畫；睡覺時本來就閉著眼
                TimelineView(BlinkSchedule()) { context in
                    face(blink: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: BlinkSchedule.period)
                         < BlinkSchedule.closed)
                }
            } else {
                face(blink: false)
            }
        }
        .accessibilityHidden(true)
    }

    private func face(blink: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.opacity(0.12))
            // 電量：從左邊填到目前的百分比
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.22))
                    .frame(width: max(6, (proxy.size.width - 6) * level))
                    .padding(3)
            }
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(tint.opacity(0.7), lineWidth: 2)
            HStack(spacing: 9) {
                eye(closed: blink)
                eye(closed: blink)
            }
            .offset(y: -4)
            mouth
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 13, height: 7)
                .offset(y: 7)
            if mood == .sleeping {
                Text("z")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .offset(x: 14, y: -11)
            }
        }
        .frame(width: 40, height: 30)
        .overlay(alignment: .trailing) {
            Capsule().fill(tint.opacity(0.7)).frame(width: 3.5, height: 11).offset(x: 4.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func eye(closed: Bool) -> some View {
        Group {
            if mood == .sleeping || closed {
                Capsule().fill(tint).frame(width: 7, height: 2)
            } else {
                Circle().fill(tint).frame(width: 4.5, height: 4.5)
            }
        }
        .frame(width: 7, height: 5)
    }

    private var mouth: Path {
        Path { path in
            switch mood {
            case .happy:
                // 開心：大大的笑
                path.move(to: CGPoint(x: 0, y: 0))
                path.addQuadCurve(to: CGPoint(x: 13, y: 0), control: CGPoint(x: 6.5, y: 10))
            case .charging:
                path.move(to: CGPoint(x: 2, y: 2))
                path.addQuadCurve(to: CGPoint(x: 11, y: 2), control: CGPoint(x: 6.5, y: 7))
            case .worried:
                path.move(to: CGPoint(x: 1, y: 6))
                path.addQuadCurve(to: CGPoint(x: 12, y: 6), control: CGPoint(x: 6.5, y: 0))
            case .resting, .sleeping:
                path.move(to: CGPoint(x: 3, y: 4))
                path.addLine(to: CGPoint(x: 10, y: 4))
            }
        }
    }
}

/// 眨眼的時間點：每 4 秒閉眼 0.18 秒，只產生閉眼與張眼兩個時間
private struct BlinkSchedule: TimelineSchedule {
    static let period: TimeInterval = 4
    static let closed: TimeInterval = 0.18

    func entries(from start: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var base = (start.timeIntervalSinceReferenceDate / Self.period).rounded(.down) * Self.period
        var opening = false
        return AnyIterator {
            let date = Date(timeIntervalSinceReferenceDate: base + (opening ? Self.closed : 0))
            if opening { base += Self.period }
            opening.toggle()
            return date
        }
    }
}
