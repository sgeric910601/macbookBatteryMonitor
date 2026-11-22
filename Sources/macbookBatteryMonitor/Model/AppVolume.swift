import Foundation

/// 各 App 分開調音量（播放在 AppVolumeController）。
/// 只有調低或靜音的 App 才會被擷取、改音量再播放；維持 100% 的 App 完全不碰，不多耗電
enum AppVolume {
    struct Setting: Equatable {
        /// 0～1
        var volume: Double = 1
        var muted = false

        var gain: Float { muted ? 0 : Float(AppVolume.clamp(volume)) }
        /// 100% 且沒靜音：不用擷取
        var needsTap: Bool { muted || AppVolume.clamp(volume) < 0.995 }
    }

    static func clamp(_ volume: Double) -> Double { volume.isFinite ? min(max(volume, 0), 1) : 1 }

    /// 發出聲音的常常是 Helper 程序（例如瀏覽器的「Helper (Renderer)」），它的套件識別碼以 App 的識別碼開頭：
    /// 取最長的、在「.」邊界上相符的那個 App
    static func owner(ofProcessBundleID processID: String, apps: Set<String>) -> String? {
        guard !processID.isEmpty else { return nil }
        if let owner = apps.filter({ processID == $0 || processID.hasPrefix($0 + ".") }).max(by: { $0.count < $1.count }) { return owner }
        // Safari 的聲音由 WebKit 的程序發出，識別碼不是 Safari 開頭。
        // shortcut: 其他用 WebKit 網頁元件的 App 的聲音也會算在 Safari；要分清楚得查程序的負責 App（只有私有函式）
        if processID.hasPrefix("com.apple.WebKit."), apps.contains(safari) { return safari }
        return nil
    }

    /// 發出聲音的程序歸給哪個 App：先用程序本身是哪個 App（pidOwner），再看識別碼前綴；
    /// 結果若是某個一般 App 的子識別碼（例如 Brave 的 Helper 本身也是背景 App：com.brave.Browser.helper），再往上歸到那個 App
    static func resolveOwner(pidOwner: String?, processBundleID: String, apps: Set<String>, regularApps: Set<String>) -> String? {
        guard let owner = pidOwner ?? owner(ofProcessBundleID: processBundleID, apps: apps) else { return nil }
        if regularApps.contains(owner) { return owner }
        return regularApps.filter { owner.hasPrefix($0 + ".") }.max { $0.count < $1.count } ?? owner
    }

    /// 新的擷取什麼時候接手（靜音 App 原本的聲音、改由我們播放）
    enum ArmDecision: Equatable {
        case wait
        /// fromFullVolume：App 原本是 100% 播放（第一次建立）；重建時舊的擷取已經接手，接著用目前的設定
        case arm(fromFullVolume: Bool)
    }

    /// 卡片列出的 App：正在播放的，加上調整過而且還開著的（暫停時也要能調回）；依識別碼排序
    static func listed(playing: Set<String>, adjusted: Set<String>, running: Set<String>) -> [(bundleID: String, isPlaying: Bool)] {
        playing.union(adjusted.intersection(running)).sorted().map { ($0, playing.contains($0)) }
    }

    /// 收到聲音（確定接上了）就接手；重建時舊的擷取已經接手（App 已經被靜音），等不到聲音 0.5 秒後也接手（反正是無聲）。
    /// 第一次建立時一直等到 App 出聲，App 原本的聲音照常，不會斷一下
    static func armDecision(heardSound: Bool, oldArmed: Bool, waited: Double) -> ArmDecision {
        if heardSound { return .arm(fromFullVolume: !oldArmed) }
        if oldArmed, waited > 0.5 { return .arm(fromFullVolume: false) }
        return .wait
    }

    /// 調整過的 App 安靜這麼久就拆掉擷取，輸出裝置才能休息；再出聲時重新接上
    static let idleTeardown: TimeInterval = 10

    /// 從沒出聲過、或已經安靜超過 idleTeardown：不需要擷取
    static func isIdle(lastPlaying: Date?, now: Date) -> Bool {
        guard let lastPlaying else { return true }
        return now.timeIntervalSince(lastPlaying) >= idleTeardown
    }

    static let safari = "com.apple.Safari"
    /// 存起來的 App 數量上限
    static let maxStored = 256

    // MARK: - 儲存

    /// 存成 [識別碼: [volume, muted]]；只存不是預設值的
    static func stored(_ settings: [String: Setting]) -> [String: [String: Any]] {
        settings.filter { $0.value.needsTap }.mapValues { ["volume": clamp($0.volume), "muted": $0.muted] }
    }

    /// 讀回時檢查型別與範圍；壞掉的項目略過
    static func settings(stored: [String: Any]) -> [String: Setting] {
        var result: [String: Setting] = [:]
        for (key, value) in stored.sorted(by: { $0.key < $1.key }) {
            guard result.count < maxStored else { break }
            guard !key.isEmpty, key.count <= 255, let dict = value as? [String: Any] else { continue }
            let volume = (dict["volume"] as? Double).map(clamp) ?? 1
            let muted = dict["muted"] as? Bool ?? false
            let setting = Setting(volume: volume, muted: muted)
            if setting.needsTap { result[key] = setting }
        }
        return result
    }
}

// MARK: - 混音（音訊執行緒上跑：不配置記憶體、不上鎖）

extension AppVolume {
    /// 把擷取到的交錯 Float32 聲音乘上音量寫到輸出：輸出聲道比較少時取平均（例如藍牙通話時的單聲道），
    /// 比較多時重複最後一個聲道；音量每個取樣往目標靠近一點，避免突然變大小的爆音。
    /// 回傳更新後的音量與這段輸入的最大振幅（用來判斷是不是一直收到無聲資料）
    static func mix(input: UnsafePointer<Float>, inputChannels: Int, inputSamples: Int,
                    output: UnsafeMutablePointer<Float>, outputChannels: Int, outputSamples: Int,
                    gain current: Float, target: Float, ramp: Float) -> (gain: Float, peak: Float) {
        guard outputChannels > 0, outputSamples > 0 else { return (current, 0) }
        guard inputChannels > 0, inputSamples > 0 else {
            output.update(repeating: 0, count: outputSamples)
            return (current, 0)
        }
        let frames = min(inputSamples / inputChannels, outputSamples / outputChannels)
        var gain = current
        var peak: Float = 0
        for frame in 0..<frames {
            gain += (target - gain) * ramp
            let source = input + frame * inputChannels
            for channel in 0..<inputChannels { peak = max(peak, abs(source[channel])) }
            let destination = output + frame * outputChannels
            if outputChannels < inputChannels {
                var sum: Float = 0
                for channel in 0..<inputChannels { sum += source[channel] }
                let mono = sum / Float(inputChannels) * gain
                for channel in 0..<outputChannels { destination[channel] = mono }
            } else {
                for channel in 0..<outputChannels { destination[channel] = source[min(channel, inputChannels - 1)] * gain }
            }
        }
        let written = frames * outputChannels
        if written < outputSamples { (output + written).update(repeating: 0, count: outputSamples - written) }
        return (gain, peak)
    }

    /// 約 30 ms 從目前音量滑到目標音量的係數
    static func rampCoefficient(sampleRate: Double) -> Float {
        sampleRate > 0 ? Float(1 - exp(-1 / (sampleRate * 0.030))) : 1
    }
}
