import SwiftUI

enum Format {
    static func duration(_ minutes: Int?) -> String {
        guard let minutes, minutes >= 0 else { return "—" }
        if minutes < 60 { return "\(minutes) 分" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) 小時" : "\(h) 小時 \(m) 分"
    }

    static func clock(_ minutes: Int?) -> String? {
        guard let minutes, minutes >= 0 else { return nil }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    static func watts(_ w: Double?) -> String {
        guard let w else { return "—" }
        return String(format: "%.1f W", w)
    }

    static func mAh(_ v: Int?) -> String {
        guard let v else { return "—" }
        return "\(v.formatted()) mAh"
    }

    static func milliamps(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded()).formatted()) mA"
    }

    static func since(_ date: Date, now: Date = Date()) -> String {
        duration(max(0, Int(now.timeIntervalSince(date) / 60)))
    }
}

extension PowerState {
    var title: String {
        switch self {
        case .discharging: return "使用電池中"
        case .charging: return "充電中"
        case .pluggedIdle: return "已接電源・未充電"
        case .full: return "已充飽"
        case .limitReached: return "已達充電上限"
        }
    }

    var symbol: String {
        switch self {
        case .discharging: return SymbolCompat.name("battery.75percent")
        case .charging: return "bolt.fill"
        case .pluggedIdle: return "powerplug.fill"
        case .full: return "checkmark.circle.fill"
        case .limitReached: return "checkmark.shield.fill"
        }
    }

    var tint: Color {
        switch self {
        case .discharging: return .secondary
        case .charging: return .green
        case .pluggedIdle: return .orange
        case .full: return .green
        case .limitReached: return .green
        }
    }
}

struct Card<Content: View>: View {
    /// 填滿父層給的高度（下方分頁用，切換時高度才不會跳）
    var expand = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: expand ? .infinity : nil, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

struct CardTitle: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

/// 面板用的大電池圖示
struct BatteryGlyph: View {
    var percent: Int
    var state: PowerState
    var lowThreshold: Int
    /// 有設定充電上限時，在電池裡畫一條刻度線
    var limit: Int? = nil

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let nub = max(3, geo.size.width * 0.06)
            let bodyWidth = geo.size.width - nub - 2
            HStack(spacing: 2) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: h * 0.28, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.55), lineWidth: 2)
                    RoundedRectangle(cornerRadius: h * 0.16, style: .continuous)
                        .fill(color.softGradient)
                        .frame(width: max(3, (bodyWidth - 8) * CGFloat(min(max(percent, 0), 100)) / 100))
                        .padding(4)
                    if let limit, limit < 100 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.7))
                            .frame(width: 1.5, height: h - 4)
                            .offset(x: 4 + (bodyWidth - 8) * CGFloat(limit) / 100 - 0.75)
                    }
                    if let overlay {
                        Image(systemName: overlay)
                            .font(.system(size: h * 0.5, weight: .heavy))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 1)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: bodyWidth)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: nub, height: h * 0.38)
            }
        }
    }

    private var color: Color {
        guard state == .discharging else { return .green }
        if percent <= lowThreshold { return .red }
        if percent <= lowThreshold + 10 { return .orange }
        return .green
    }

    private var overlay: String? {
        switch state {
        case .charging: return "bolt.fill"
        case .pluggedIdle, .full, .limitReached: return "powerplug.fill"
        case .discharging: return nil
        }
    }
}

extension Color {
    /// macOS 12 沒有 Color.gradient：上亮下暗的線性漸層，效果接近
    var softGradient: LinearGradient {
        LinearGradient(colors: [self, opacity(0.78)], startPoint: .top, endPoint: .bottom)
    }
}
