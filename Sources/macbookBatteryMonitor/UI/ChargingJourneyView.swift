import AVFoundation
import SwiftUI

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

    static func make(percent: Int, charging: Bool, decision: ChargingPlanDecision?, now: Date = Date()) -> ChargingJourneyPresentation {
        let progress = min(1, max(0, Double(percent) / 100))
        guard let decision else {
            return .init(title: "智慧充電", detail: "指定時間前充到需要的電量，其餘時間維持保養上限",
                         progress: progress, tint: .neutral, onPad: charging, badge: nil, animatedFlow: charging)
        }
        let deadline = time(decision.deadline, now: now)
        switch decision.phase {
        case .unsupported:
            return .init(title: "智慧充電", detail: "這台 Mac 不支援調整充電上限", progress: progress, tint: .neutral,
                         onPad: false, badge: nil, animatedFlow: false)
        case .unplugged:
            return .init(title: "等待接上電源", detail: "目標 \(deadline) 前充到 \(decision.targetPercent)%", progress: progress,
                         tint: .neutral, onPad: false, badge: nil, animatedFlow: false)
        case .waiting:
            return .init(title: "保養中，等待開始充電",
                         detail: "預計 \(time(decision.startAt, now: now)) 開始，\(deadline) 前充到 \(decision.targetPercent)%",
                         progress: progress, tint: .blue, onPad: false, badge: .sleeping, animatedFlow: false)
        case .starting:
            return .init(title: "準備充電到 \(decision.targetPercent)%", detail: "目標 \(deadline) 完成", progress: progress,
                         tint: .blue, onPad: true, badge: nil, animatedFlow: false)
        case .charging:
            return .init(title: "充電到 \(decision.targetPercent)%", detail: "約 \(duration(decision.requiredMinutes))後完成・目標 \(deadline)",
                         progress: progress, tint: .green, onPad: true, badge: nil, animatedFlow: true)
        case .systemPaused:
            return .init(title: "macOS 暫停充電", detail: "仍以 \(deadline) 前充到 \(decision.targetPercent)% 為目標",
                         progress: progress, tint: .orange, onPad: true, badge: .paused, animatedFlow: false)
        case .ready:
            return .init(title: "已準備好", detail: "已達 \(decision.targetPercent)%・目標 \(deadline)", progress: progress,
                         tint: .green, onPad: false, badge: .ready, animatedFlow: false)
        case .late:
            return .init(title: "可能無法準時", detail: "繼續充電中・原定 \(deadline) 前充到 \(decision.targetPercent)%",
                         progress: progress, tint: .orange, onPad: charging, badge: .late, animatedFlow: charging)
        }
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

struct ChargingJourneyView: View {
    let presentation: ChargingJourneyPresentation
    let appearance: ChargingAppearance
    /// 面板開著、沒有省電模式時才播放動畫
    let animated: Bool
    let open: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                if appearance == .companion {
                    ChargingCompanion(onPad: presentation.onPad, badge: presentation.badge, tint: tint,
                                      animated: animated && !reduceMotion)
                        .frame(width: 60, height: 63)
                } else {
                    energyBar
                        .frame(width: 58, height: 34)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title).font(.callout.weight(.semibold))
                    Text(presentation.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("設定智慧充電")
        .accessibilityLabel("智慧充電，\(presentation.title)，\(presentation.detail)")
    }

    /// 電力流動：電量條，充電中有一個光點往右流
    private var energyBar: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animated || reduceMotion || !presentation.animatedFlow)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.18)).frame(height: 8)
                Capsule().fill(tint.opacity(0.8)).frame(width: max(8, 58 * presentation.progress), height: 8)
                if animated && !reduceMotion && presentation.animatedFlow {
                    Circle().fill(.white).frame(width: 6, height: 6)
                        .shadow(color: tint, radius: 4)
                        .offset(x: CGFloat(phase) * 50)
                }
                Image(systemName: presentation.badge?.symbol ?? "bolt.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                    .offset(y: -14)
            }
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

    /// 開發用截圖畫不出影片圖層，改用靜態圖
    static let videoAllowed = !CommandLine.arguments.contains { $0.hasPrefix("--snapshot") || $0.hasPrefix("--screenshots") }

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
