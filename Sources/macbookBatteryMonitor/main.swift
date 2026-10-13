import AppKit
import UserNotifications

if CommandLine.arguments.contains("--dump-monitors") {
    MainActor.assumeIsolatedCompat { MonitorDebug.dump() }
    exit(0)
}

/// 開發用：讀一次周邊設備電量（含所有藍牙設備）並印出
if CommandLine.arguments.contains("--dump-peripherals") {
    let start = Date()
    let services = PeripheralReader.hidServices()
    let audio = PeripheralReader.bluetoothAudioConnected()
    let devices = PeripheralReader.read(includeAllBluetooth: true)
    print("HID 電量服務 \(services.count) 個・藍牙音訊裝置連線中：\(audio)・耗時 \(Int(Date().timeIntervalSince(start) * 1000)) ms")
    for device in devices {
        print("\(device.name)（\(device.kind.rawValue)）\(device.lowest.map { "\($0)%" } ?? "—") \(device.detailText ?? "")")
    }
    if devices.isEmpty { print("沒有連線中、會回報電量的周邊設備") }
    exit(0)
}

/// 開發用：每秒印一份感測器表格，可接次數，例如 --dump-sensors 10
if let index = CommandLine.arguments.firstIndex(of: "--dump-sensors") {
    let next = CommandLine.arguments.dropFirst(index + 1).first
    SensorDump.run(count: min(600, max(1, next.flatMap { Int($0) } ?? 1)))
    exit(0)
}

/// 開發用：印出這個 App 的通知權限（要執行 .app 裡的執行檔，系統才認得是哪個 App）
if CommandLine.arguments.contains("--notification-status") {
    let done = DispatchSemaphore(value: 0)
    UNUserNotificationCenter.current().getNotificationSettings { settings in
        let status = ["尚未詢問", "已拒絕", "已允許", "暫時允許", "短暫允許"]
        let style = ["無", "橫幅", "提示"]
        let toggle = ["不支援", "關閉", "開啟"]
        print("通知權限：\(status[safe: settings.authorizationStatus.rawValue])")
        print("提示樣式：\(style[safe: settings.alertStyle.rawValue])・橫幅／提示：\(toggle[safe: settings.alertSetting.rawValue])・通知中心：\(toggle[safe: settings.notificationCenterSetting.rawValue])・聲音：\(toggle[safe: settings.soundSetting.rawValue])")
        done.signal()
    }
    done.wait()
    exit(0)
}

if CommandLine.arguments.contains("--dump-hardware") {
    DumpCommand.runHardware()
    exit(0)
}

if CommandLine.arguments.contains("--dump") {
    DumpCommand.run()
    exit(0)
}

if let index = CommandLine.arguments.firstIndex(of: "--screenshots"), index + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolatedCompat {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        ScreenshotCommand.run(directory: CommandLine.arguments[index + 1])
    }
    exit(0)
}

if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolatedCompat {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        SnapshotCommand.run(directory: CommandLine.arguments[index + 1])
    }
    exit(0)
}

MainActor.assumeIsolatedCompat {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

private extension Array where Element == String {
    subscript(safe index: Int) -> String { indices.contains(index) ? self[index] : "未知（\(index)）" }
}
