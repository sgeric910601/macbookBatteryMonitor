import Foundation

enum XDRBrightnessKeyAction: Equatable {
    case system
    case activate(Double)
    case adjust(Double)
}

enum XDRBrightnessPolicy {
    static func estimatedNits(sdrMaximum: Double?, linearBrightness: Double?, gain: Double, headroom: Double) -> Int? {
        guard let sdrMaximum, let linearBrightness,
              sdrMaximum.isFinite, sdrMaximum > 0, sdrMaximum <= 10_000,
              linearBrightness.isFinite, (0...1).contains(linearBrightness),
              gain.isFinite, headroom.isFinite, headroom >= 1 else { return nil }
        let effectiveGain = min(clamp(gain), headroom)
        return Int((sdrMaximum * linearBrightness * effectiveGain).rounded())
    }

    static func clamp(_ gain: Double) -> Double { gain.isFinite ? min(1.6, max(1, gain)) : 1 }

    static func blockReason(supported: Bool, lowPower: Bool, hot: Bool, locked: Bool = false) -> String? {
        if locked { return "解鎖並開啟螢幕後才能啟用增亮" }
        if !supported { return "需要支援 EDR 的內建 XDR 螢幕" }
        if lowPower { return "省電模式中不啟用增亮" }
        if hot { return "系統溫度偏高，已還原亮度" }
        return nil
    }

    static func keyAction(up: Bool, gain: Double, active: Bool, automatic: Bool,
                          nativeBrightness: Float?) -> XDRBrightnessKeyAction {
        guard active || automatic else { return .system }
        guard let value = keyGain(up: up, gain: active ? gain : 1, nativeBrightness: nativeBrightness) else {
            return .system
        }
        return active ? .adjust(value) : .activate(value)
    }

    /// nil 表示交給系統；只有在一般亮度到頂或已有額外增亮時才接管。
    static func keyGain(up: Bool, gain: Double, nativeBrightness: Float?) -> Double? {
        guard gain > 1.001 || (up && (nativeBrightness ?? 0) >= 0.99) else { return nil }
        return clamp((gain * 100 + (up ? 5 : -5)).rounded() / 100)
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
