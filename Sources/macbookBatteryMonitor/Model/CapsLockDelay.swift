/// Caps Lock 延遲（hidutil 的 CapsLockDelayOverride，單位 ms）：縮短前先記下原本的值，關掉時還原
enum CapsLockDelay {
    /// 0 會讓 Caps Lock 一次切兩次、誤開大寫，注音打出全形（實測）；30 ms 不會，延遲也幾乎感覺不到
    static let short = 30
    /// 讀不到原本的值時才用。Apple 沒有文件寫明預設值，這是 macOS 27.2 上 hidutil 讀到的值
    static let fallback = 75
    /// 寫回 hidutil 前檢查：超出範圍（讀錯或 defaults 被改壞）就用 fallback，不讓 Caps Lock 變得不能用
    static let validRange = 1...2000

    static func restoreValue(saved: Int?) -> Int {
        guard let saved, validRange.contains(saved) else { return fallback }
        return saved
    }

    /// 從 `hidutil property --get CapsLockDelayOverride` 的輸出找出原本的值：每個鍵盤服務一行，取最多的那個數字。
    /// 0 和 short 是本 App（或舊版設 0）改過留下的，先略過
    static func original(fromHidutil output: String) -> Int? {
        var counts: [Int: Int] = [:]
        for line in output.split(separator: "\n") {
            guard let last = line.split(separator: " ").last, let value = Int(last), value != 0, value != short, validRange.contains(value) else { continue }
            counts[value, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) })?.key
    }
}
