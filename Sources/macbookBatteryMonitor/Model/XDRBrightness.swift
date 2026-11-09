import Foundation

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

    static func blockReason(supported: Bool, onAC: Bool, lowPower: Bool, hot: Bool, locked: Bool = false) -> String? {
        if locked { return "解鎖並開啟螢幕後才能啟用增亮" }
        if !supported { return "需要支援 EDR 的內建 XDR 螢幕" }
        if !onAC { return "接上電源後才能啟用增亮" }
        if lowPower { return "省電模式中不啟用增亮" }
        if hot { return "系統溫度偏高，已還原亮度" }
        return nil
    }

    /// nil 表示交給系統；只有在一般亮度到頂或已有額外增亮時才接管。
    static func keyGain(up: Bool, gain: Double, nativeBrightness: Float?) -> Double? {
        guard gain > 1.001 || (up && (nativeBrightness ?? 0) >= 0.99) else { return nil }
        return clamp((gain * 100 + (up ? 5 : -5)).rounded() / 100)
    }

}

/// 每次實體按壓維持相同歸屬，避免系統只收到部分事件。
struct XDRBrightnessKeySequence {
    private var ownership: [Int: Bool] = [:]

    func shouldAdjustDown(code: Int, repeating: Bool) -> Bool {
        ownership[code] ?? !repeating
    }

    mutating func consumeDown(code: Int, adjusted: Bool) -> Bool {
        if let consumed = ownership[code] { return consumed }
        ownership[code] = adjusted
        return adjusted
    }

    mutating func consumeUp(code: Int) -> Bool {
        ownership.removeValue(forKey: code) ?? false
    }
}
