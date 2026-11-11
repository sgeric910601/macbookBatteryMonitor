import CoreAudio
import Foundation
import Combine

/// 音訊切換：面板上的喇叭選單。打開選單時才讀裝置清單，平常不監聽任何東西
@MainActor
final class AudioSwitchController: ObservableObject {
    static let shared = AudioSwitchController()

    @Published private(set) var outputs: [AudioDevices.MenuItem] = []
    @Published private(set) var micMuted = false
    @Published private(set) var micSupported = false
    /// 目前的輸入裝置沒有靜音開關，「靜音」其實是把輸入音量調到 0（會議軟體的自動音量可能調回來）
    @Published private(set) var micUsesVolume = false
    /// 用音量代替靜音時，取消後要還原的音量（只在這次執行中記得；App 結束時一律還原，不會一直停在 0）
    private var restoreVolume: [AudioDeviceID: Float] = [:]

    func refresh() {
        outputs = AudioDevices.outputs(AudioDeviceReader.devices(), current: AudioDeviceReader.defaultOutput)
        guard let input = AudioDeviceReader.defaultInput else {
            micSupported = false
            micMuted = false
            return
        }
        let hasSwitch = AudioDeviceReader.inputHasMuteSwitch(input)
        micSupported = AudioDevices.mutePlan(hasMuteSwitch: hasSwitch, volume: AudioDeviceReader.inputVolume(input)) != .unsupported
        micUsesVolume = !hasSwitch
        if hasSwitch {
            micMuted = AudioDeviceReader.inputMuted(input) == true
        } else {
            // 用音量代替靜音時：使用者自己把音量調回來，就不再算靜音
            if restoreVolume[input] != nil, (AudioDeviceReader.inputVolume(input) ?? 0) > 0 { restoreVolume[input] = nil }
            micMuted = restoreVolume[input] != nil
        }
    }

    /// 選單上的文字：沒有靜音開關時照實說是調音量
    var micTitle: String {
        if micUsesVolume { return micMuted ? "還原輸入音量" : "輸入音量調到 0" }
        return micMuted ? "取消麥克風靜音" : "麥克風靜音"
    }

    /// App 結束前把調到 0 的輸入音量還原
    func restoreInputVolumes() {
        for (input, volume) in restoreVolume { AudioDeviceReader.setInputVolume(input, volume) }
        restoreVolume = [:]
    }

    func select(_ id: UInt32) {
        AudioDeviceReader.setDefaultOutput(id)
        refresh()
    }

    func toggleMic() {
        guard let input = AudioDeviceReader.defaultInput else { return }
        let hasSwitch = AudioDeviceReader.inputHasMuteSwitch(input)
        if micMuted {
            if hasSwitch {
                AudioDeviceReader.setInputMuted(input, false)
            } else if let volume = restoreVolume.removeValue(forKey: input) {
                AudioDeviceReader.setInputVolume(input, volume)
            }
        } else {
            switch AudioDevices.mutePlan(hasMuteSwitch: hasSwitch, volume: AudioDeviceReader.inputVolume(input)) {
            case .muteSwitch: AudioDeviceReader.setInputMuted(input, true)
            case let .volume(restoreTo):
                restoreVolume[input] = restoreTo
                AudioDeviceReader.setInputVolume(input, 0)
            case .unsupported: break
            }
        }
        refresh()
    }
}
