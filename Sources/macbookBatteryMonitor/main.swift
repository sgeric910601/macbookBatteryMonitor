import AppKit
import CPUPowerShared
import UserNotifications

// 開發用的自我測試多半在背景執行、最後被結束：輸出改成逐行寫出，才不會留在緩衝區裡遺失
if CommandLine.arguments.contains(where: { $0.hasPrefix("--selftest") }) {
    setvbuf(stdout, nil, _IOLBF, 0)
}

if CommandLine.arguments.contains("--dump-monitors") {
    MainActor.assumeIsolatedCompat { MonitorDebug.dump() }
    exit(0)
}

/// 開發用：讀一次周邊設備電量（含所有藍牙設備）並印出
if CommandLine.arguments.contains("--dump-peripherals") {
    let start = Date()
    let services = PeripheralReader.hidServices()
    let audio = PeripheralReader.bluetoothAudioConnected()
    // 藍牙低功耗設備（羅技、Razer 等）：要從 .app 啟動才會用這個 App 的藍牙權限；最多等 6 秒讀到電量
    if !BLEBatteryReader.denied {
        BLEBatteryReader.shared.start()
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline, BLEBatteryReader.shared.currentReadings().isEmpty { Thread.sleep(forTimeInterval: 0.3) }
    }
    print("藍牙權限：\(BLEBatteryReader.authorized ? "已允許" : BLEBatteryReader.denied ? "已拒絕" : "尚未決定")・藍牙低功耗電量 \(BLEBatteryReader.shared.currentReadings().count) 個")
    let devices = PeripheralReader.read(includeAllBluetooth: true)
    print("HID 電量服務 \(services.count) 個・藍牙音訊裝置連線中：\(audio)・耗時 \(Int(Date().timeIntervalSince(start) * 1000)) ms")
    for device in devices {
        print("\(device.name)（\(device.kind.rawValue)）\(device.lowest.map { "\($0)%" } ?? "—") \(device.detailText ?? "")")
    }
    if devices.isEmpty { print("沒有連線中、會回報電量的周邊設備") }
    exit(0)
}

/// 檢查智慧充電：印出排程、目前的系統充電上限與電量、排定的喚醒事件，以及最近的事件紀錄（只讀，不寫入任何設定）。
/// 要執行 .app 裡的執行檔，才會讀到 App 的設定
if CommandLine.arguments.contains("--charging-plan-status") {
    if let plan = DefaultsChargingPlanStorage().load() {
        print("排程：\(plan.schedule.isWeekly ? "每週" : "一次")，\(plan.deadline.formatted(date: .abbreviated, time: .standard)) 前充到 \(plan.targetPercent)%，"
              + "保養上限 \(plan.holdPercent)%，原本上限 \(plan.restoreLimit)%，睡眠策略 \(plan.sleepStrategy.title)"
              + (plan.restoring ? "（還原中）" : "") + (plan.completedAt.map { "，已於 \($0.formatted(date: .omitted, time: .standard)) 達到目標" } ?? ""))
    } else {
        print("排程：沒有")
    }
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        let reading = await PowerUIChargeLimit().read()
        print("系統充電上限：\(reading.map { "\($0.limit)%（\($0.enabled ? "套用中" : "暫時沒有套用")），可選 \($0.options.map(String.init).joined(separator: "、"))" } ?? "讀不到")")
        done.signal()
    }
    done.wait()
    if let s = BatteryReader.read(includeTemperature: false) {
        print("電量：\(s.percent)%・\(s.externalConnected ? "接著電源" : "使用電池")・\(s.isCharging ? "充電中" : "沒在充電")")
    }
    let sched = Shell.runSync("/usr/bin/pmset", ["-g", "sched"]) ?? ""
    let wakes = sched.split(separator: "\n").filter { $0.contains(CPUHelperConstants.chargingWakeIdentifier) }
    print("精準喚醒事件：\(wakes.isEmpty ? "沒有" : wakes.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "；"))")
    print("事件紀錄：\(ChargingPlanLog.shared.url.path)")
    for line in ChargingPlanLog.shared.tail(25) { print("  \(line)") }
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
