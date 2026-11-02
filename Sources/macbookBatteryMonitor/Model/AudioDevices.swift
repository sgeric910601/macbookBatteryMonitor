/// 音訊切換：輸出裝置選單與麥克風靜音的做法。只做判斷，讀寫 Core Audio 在 AudioDeviceReader
enum AudioDevices {
    struct Device: Equatable {
        let id: UInt32
        let name: String
        let outputs: Bool
        let inputs: Bool
    }

    struct MenuItem: Equatable {
        let id: UInt32
        let name: String
        let isCurrent: Bool
    }

    enum MutePlan: Equatable {
        /// 裝置有靜音開關
        case muteSwitch
        /// 沒有靜音開關：音量調到 0，取消時還原成這個音量
        case volume(restoreTo: Float)
        /// 兩種都不能調
        case unsupported
    }

    static func outputs(_ devices: [Device], current: UInt32?) -> [MenuItem] {
        devices.filter(\.outputs)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { MenuItem(id: $0.id, name: $0.name, isCurrent: $0.id == current) }
    }

    /// volume：輸入音量（0～1），讀不到時為 nil
    static func mutePlan(hasMuteSwitch: Bool, volume: Float?) -> MutePlan {
        if hasMuteSwitch { return .muteSwitch }
        guard let volume else { return .unsupported }
        return .volume(restoreTo: volume > 0 ? volume : 0.5)
    }
}
