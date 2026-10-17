import Foundation

/// 桌面寵物要說的狀態（只放數值，方便測試）
struct DesktopPetStatus: Equatable {
    var percent: Int
    var state: PowerState
    /// 接著電源但供電不足，電池仍在放電
    var drainingOnAC = false
    var minutesToEmpty: Int?
    /// 充到上限（有上限時）或充滿要多久
    var minutesToFull: Int?
    /// 有充電上限、而且正在充到上限時才有
    var limit: Int?
    var lowThreshold = 20
    /// 智慧充電的狀態與說明（沒有排程時是 nil）
    var planTitle: String?
    var planDetail: String?
    var planWaiting = false
    var planReady = false
    /// 今天用掉、補回的電量（沒有今天的紀錄時是 nil）
    var usedToday: Int?
    var chargedToday: Int?
    var healthPercent: Int?
    var cycleCount: Int?
    var systemWatts: Double?
}

/// 桌面寵物的想像框（滑鼠移過去，目前的狀態）與對話框（點一下，每點一次換一句）
enum DesktopPetMessages {
    /// 用滑鼠來回摸牠時說的話
    static let purrs = ["呼嚕呼嚕～", "好舒服喔", "再摸一下嘛", "喵～"]

    static func thought(_ s: DesktopPetStatus) -> String {
        var lines = ["\(s.percent)%・\(stateText(s))"]
        if let title = s.planTitle {
            lines.append(title + (s.planDetail.map { "：" + $0 } ?? ""))
        }
        return lines.joined(separator: "\n")
    }

    static func sayings(_ s: DesktopPetStatus) -> [String] {
        var list = [mood(s)]
        if let used = s.usedToday, let charged = s.chargedToday {
            list.append("今天用掉 \(used)%，補回 \(charged)%")
        }
        if let health = s.healthPercent {
            list.append(s.cycleCount.map { "電池健康度 \(health)%，充過 \($0) 次" } ?? "電池健康度 \(health)%")
        }
        if let watts = s.systemWatts, watts > 0 {
            list.append(String(format: "現在整台 Mac 用了 %.1f W", watts))
        }
        return list
    }

    static func stateText(_ s: DesktopPetStatus) -> String {
        switch s.state {
        case .charging:
            guard let minutes = s.minutesToFull else { return "充電中" }
            if let limit = s.limit { return "充電中，\(duration(minutes))後到 \(limit)%" }
            return "充電中，\(duration(minutes))後充滿"
        case .discharging:
            return s.minutesToEmpty.map { "還能用 \(duration($0))" } ?? "使用電池中"
        case .limitReached:
            return "已達充電上限，用變壓器供電"
        case .full:
            return "已充飽"
        case .pluggedIdle:
            return s.drainingOnAC ? "供電不足，電池在放電" : "接著電源，暫停充電"
        }
    }

    static func mood(_ s: DesktopPetStatus) -> String {
        if s.planReady { return "準備好了，隨時可以出門！" }
        if s.planWaiting, let detail = s.planDetail { return "我先睡一下，\(detail)" }
        let draining = s.state == .discharging || (s.state == .pluggedIdle && s.drainingOnAC)
        if draining {
            if s.percent <= 10 { return "快沒電了！拜託快接上電源" }
            if s.percent <= s.lowThreshold { return "肚子有點餓，記得幫我充電" }
            return "陪你一起努力，還有 \(s.percent)%"
        }
        switch s.state {
        case .charging: return "充電中，好溫暖～"
        case .limitReached, .full: return "吃飽了，現在靠變壓器供電"
        default: return "插著電在休息"
        }
    }

    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(max(1, minutes)) 分鐘" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) 小時" : "\(hours) 小時 \(rest) 分"
    }
}
