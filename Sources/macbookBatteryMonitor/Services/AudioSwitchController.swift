import CoreAudio
import Foundation
import Observation

/// 音訊切換：面板上的喇叭選單。打開選單時才讀裝置清單，平常不監聽任何東西
@MainActor
@Observable
final class AudioSwitchController {
    static let shared = AudioSwitchController()

    private(set) var outputs: [AudioDevices.MenuItem] = []
    private(set) var micMuted = false
    private(set) var micSupported = false
    /// 用音量代替靜音時，取消後要還原的音量（只在這次執行中記得）
    @ObservationIgnored private var restoreVolume: [AudioDeviceID: Float] = [:]

    func refresh() {
        outputs = AudioDevices.outputs(AudioDeviceReader.devices(), current: AudioDeviceReader.defaultOutput)
        guard let input = AudioDeviceReader.defaultInput else {
            micSupported = false
            micMuted = false
            return
        }
        let hasSwitch = AudioDeviceReader.inputHasMuteSwitch(input)
        micSupported = AudioDevices.mutePlan(hasMuteSwitch: hasSwitch, volume: AudioDeviceReader.inputVolume(input)) != .unsupported
        micMuted = hasSwitch ? AudioDeviceReader.inputMuted(input) == true : restoreVolume[input] != nil
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
