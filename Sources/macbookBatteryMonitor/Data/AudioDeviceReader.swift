import CoreAudio
import Foundation

/// 讀寫 Core Audio：裝置清單、預設輸出、預設輸入的靜音與音量。全部是公開介面，不需要權限
enum AudioDeviceReader {
    private static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func devices() -> [AudioDevices.Device] {
        var where_ = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &where_, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &where_, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard let name = name(of: id) else { return nil }
            return AudioDevices.Device(id: id, name: name, outputs: hasStreams(id, kAudioObjectPropertyScopeOutput),
                                       inputs: hasStreams(id, kAudioObjectPropertyScopeInput), transport: transport(of: id))
        }
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var where_ = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &where_, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private static func transport(of id: AudioDeviceID) -> UInt32 {
        var where_ = address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &where_, 0, nil, &size, &value) == noErr ? value : 0
    }

    private static func hasStreams(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Bool {
        var where_ = address(kAudioDevicePropertyStreams, scope)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &where_, 0, nil, &size) == noErr && size > 0
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var where_ = address(selector)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &where_, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    static var defaultOutput: AudioDeviceID? { defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) }
    static var defaultInput: AudioDeviceID? { defaultDevice(kAudioHardwarePropertyDefaultInputDevice) }

    @discardableResult
    static func setDefaultOutput(_ id: AudioDeviceID) -> Bool {
        var where_ = address(kAudioHardwarePropertyDefaultOutputDevice)
        var value = id
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &where_, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value) == noErr
    }

    // MARK: - 麥克風

    /// 預設輸入裝置有可以設定的靜音開關
    static func inputHasMuteSwitch(_ id: AudioDeviceID) -> Bool {
        var where_ = address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput)
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(id, &where_) && AudioObjectIsPropertySettable(id, &where_, &settable) == noErr && settable.boolValue
    }

    static func inputMuted(_ id: AudioDeviceID) -> Bool? {
        var where_ = address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(id, &where_), AudioObjectGetPropertyData(id, &where_, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    @discardableResult
    static func setInputMuted(_ id: AudioDeviceID, _ muted: Bool) -> Bool {
        var where_ = address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput)
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(id, &where_, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    /// 輸入音量 0～1；裝置沒有可以設定的主音量時為 nil
    static func inputVolume(_ id: AudioDeviceID) -> Float? {
        var where_ = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(id, &where_), AudioObjectIsPropertySettable(id, &where_, &settable) == noErr, settable.boolValue else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &where_, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    @discardableResult
    static func setInputVolume(_ id: AudioDeviceID, _ volume: Float) -> Bool {
        var where_ = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput)
        var value = Float32(min(max(volume, 0), 1))
        return AudioObjectSetPropertyData(id, &where_, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }
}
