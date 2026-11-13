import Foundation

enum XDRBrightnessKeyAction: Equatable {
    case system
    case activate(Double)
    case adjust(Double)
}

enum XDRBrightnessPolicy {
    static let absoluteMaximumGain = 16.0

    static func needsOverlay(gain: Double) -> Bool { gain.isFinite && gain > 1.001 }

    static func maximumGain(sdrMaximum: Double?, peakHDR: Double?, potentialHeadroom: Double) -> Double {
        guard potentialHeadroom.isFinite, potentialHeadroom >= 1 else { return 1 }
        guard let sdrMaximum, let peakHDR,
              sdrMaximum.isFinite, sdrMaximum > 0, sdrMaximum <= 10_000,
              peakHDR.isFinite, peakHDR > 0, peakHDR <= 10_000 else {
            return min(1.6, potentialHeadroom)
        }
        return min(absoluteMaximumGain, potentialHeadroom, max(1, peakHDR / sdrMaximum))
    }

    static func estimatedNits(sdrMaximum: Double?, linearBrightness: Double?, gain: Double, headroom: Double) -> Int? {
        guard let sdrMaximum, let linearBrightness,
              sdrMaximum.isFinite, sdrMaximum > 0, sdrMaximum <= 10_000,
              linearBrightness.isFinite, (0...1).contains(linearBrightness),
              gain.isFinite, headroom.isFinite, headroom >= 1 else { return nil }
        let effectiveGain = clamp(gain, maximum: headroom)
        return Int((sdrMaximum * linearBrightness * effectiveGain).rounded())
    }

    static func clamp(_ gain: Double, maximum: Double = 1.6) -> Double {
        let limit = maximum.isFinite ? min(absoluteMaximumGain, max(1, maximum)) : 1
        return gain.isFinite ? min(limit, max(1, gain)) : 1
    }

    static func blockReason(supported: Bool, lowPower: Bool, hot: Bool, locked: Bool = false) -> String? {
        if locked { return "解鎖並開啟螢幕後才能啟用增亮" }
        if !supported { return "需要支援 EDR 的內建 XDR 螢幕" }
        if lowPower { return "省電模式中不啟用增亮" }
        if hot { return "系統溫度偏高，已還原亮度" }
        return nil
    }

    static func keyAction(up: Bool, gain: Double, active: Bool, automatic: Bool,
                          nativeBrightness: Float?, maximum: Double = 1.6) -> XDRBrightnessKeyAction {
        guard active || automatic else { return .system }
        guard let value = keyGain(up: up, gain: active ? gain : 1, nativeBrightness: nativeBrightness, maximum: maximum) else {
            return .system
        }
        return active ? .adjust(value) : .activate(value)
    }

    /// nil 表示交給系統；只有在一般亮度到頂或已有額外增亮時才接管。
    static func keyGain(up: Bool, gain: Double, nativeBrightness: Float?, maximum: Double = 1.6) -> Double? {
        guard gain > 1.001 || (up && (nativeBrightness ?? 0) >= 0.99) else { return nil }
        return clamp((gain * 100 + (up ? 5 : -5)).rounded() / 100, maximum: maximum)
    }

}

/// 記住原生按下事件的去向，跨過上限後可接管 repeat，仍將放開事件送回系統。
struct XDRBrightnessKeySequence {
    private struct Press {
        let sentDownToSystem: Bool
        let allowsAdjustment: Bool
        var consuming: Bool
    }
    private var presses: [Int: Press] = [:]

    func shouldAdjustDown(code: Int, repeating: Bool) -> Bool {
        presses[code]?.allowsAdjustment ?? !repeating
    }

    mutating func consumeDown(code: Int, adjusted: Bool, repeating: Bool) -> Bool {
        if var press = presses[code] {
            if press.allowsAdjustment && adjusted { press.consuming = true }
            presses[code] = press
            return press.consuming
        }
        let consumed = adjusted && !repeating
        presses[code] = Press(sentDownToSystem: !consumed, allowsAdjustment: !repeating, consuming: consumed)
        return consumed
    }

    mutating func consumeUp(code: Int) -> Bool {
        guard let press = presses.removeValue(forKey: code) else { return false }
        return !press.sentDownToSystem
    }
}

/// 亮度鍵只使用最近一次背景取樣，資料過期或環境不允許時交還系統。
struct XDRKeySnapshot: Sendable {
    let nativeBrightness: Float?
    let allowed: Bool
    let sampledAt: TimeInterval

    func action(up: Bool, gain: Double, active: Bool, automatic: Bool,
                maximum: Double, now: TimeInterval) -> XDRBrightnessKeyAction {
        let age = now - sampledAt
        guard allowed, age >= 0, age <= 2.5 else { return .system }
        return XDRBrightnessPolicy.keyAction(up: up, gain: gain, active: active,
            automatic: automatic, nativeBrightness: nativeBrightness, maximum: maximum)
    }
}

/// 每次啟動使用不同代號，晚到的 GPU 呈現回呼不能揭開已停止或重啟的畫面。
struct XDRPresentationGate {
    private var current: UUID?

    mutating func begin() -> UUID {
        let token = UUID()
        current = token
        return token
    }

    mutating func stop() { current = nil }
    func canReveal(_ token: UUID) -> Bool { current == token }
}
