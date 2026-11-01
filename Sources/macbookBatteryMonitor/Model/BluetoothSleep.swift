/// 睡眠時關閉藍牙、醒來打開。只開回自己關掉的：使用者自己關的藍牙醒來後維持關閉。
/// 連著藍牙鍵盤、滑鼠或觸控板時不關，否則醒來時用它們叫不醒 Mac（桌上型 Mac 只剩電源鍵）。
/// 只做判斷，實際開關在 BluetoothPower
struct BluetoothSleep {
    enum Action: Equatable { case none, powerOff, powerOn }

    /// 這次睡眠是我們關掉的藍牙。存在設定裡：睡眠中 App 被結束，下次啟動時還知道要打開
    private(set) var turnedOff: Bool

    init(turnedOff: Bool) { self.turnedOff = turnedOff }

    mutating func willSleep(enabled: Bool, poweredOn: Bool, wakeInputConnected: Bool) -> Action {
        guard enabled, poweredOn, !wakeInputConnected, !turnedOff else { return .none }
        turnedOff = true
        return .powerOff
    }

    mutating func didWake() -> Action {
        guard turnedOff else { return .none }
        turnedOff = false
        return .powerOn
    }

    /// 啟動時：上次睡眠關掉的藍牙還沒等到醒來就結束了
    mutating func didLaunch() -> Action { didWake() }

    /// 喚醒 Mac 用得到的藍牙輸入裝置：Generic Desktop 的滑鼠（2）、鍵盤（6），以及觸控板等 Digitizer（0x0D）。
    /// 傳輸方式 Bluetooth、Bluetooth Low Energy，以及 Apple 配件的 BT- 開頭（例如 BT-AACP）都算，寧可多算也不要叫不醒 Mac
    static func isWakeInput(transport: String, usagePage: Int, usage: Int) -> Bool {
        guard transport.hasPrefix("Bluetooth") || transport.hasPrefix("BT-") else { return false }
        return (usagePage == 1 && (usage == 2 || usage == 6)) || usagePage == 0x0D
    }
}
