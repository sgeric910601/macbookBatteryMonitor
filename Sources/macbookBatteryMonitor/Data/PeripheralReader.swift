import CoreAudio
import Foundation
import IOKit

/// 讀周邊設備電量。在背景執行緒呼叫。
enum PeripheralReader {
    /// includeAllBluetooth：面板停在周邊設備分頁時為 true，一定查 system_profiler；
    /// 背景定時更新時，只有連著藍牙音訊裝置（耳機）才查，其餘只讀很快的 IORegistry
    static func read(includeAllBluetooth: Bool, includeBluetoothLE: Bool = true) -> [PeripheralBattery] {
        let hid = PeripheralParse.hid(hidServices())
        var bluetooth: [PeripheralBattery] = []
        if includeAllBluetooth || bluetoothAudioConnected(),
           let output = Shell.runSync("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]),
           let data = output.data(using: .utf8) {
            bluetooth = PeripheralParse.bluetooth(json: data)
        }
        let merged = PeripheralParse.merge(hid: hid, bluetooth: bluetooth)
        return includeBluetoothLE ? PeripheralParse.merge(merged, bluetoothLE: bluetoothLE()) : merged
    }

    /// 藍牙低功耗設備（羅技、Razer 等）的電量；藍牙權限還沒允許時是空的
    static func bluetoothLE() -> [PeripheralBattery] {
        let reader = BLEBatteryReader.shared
        guard reader.started else { return [] }
        let usages = bluetoothLEUsages()
        return reader.currentReadings().map { reading in
            PeripheralBattery(id: reading.id, name: reading.name,
                              kind: PeripheralParse.kind(name: reading.name, usages: usages[reading.name] ?? []),
                              level: reading.level)
        }
    }

    /// IORegistry 中藍牙低功耗 HID 設備的用途（名稱 → [(用途頁, 用途)]），名稱看不出是滑鼠還是鍵盤時用來判斷
    static func bluetoothLEUsages() -> [String: [(page: Int, usage: Int)]] {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOHIDDevice") as NSMutableDictionary
        matching["IOPropertyMatch"] = ["Transport": "Bluetooth Low Energy"]
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }
        var result: [String: [(page: Int, usage: Int)]] = [:]
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func number(_ key: String) -> Int? {
                (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
            }
            guard let name = IORegistryEntryCreateCFProperty(service, "Product" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? String,
                  let page = number("PrimaryUsagePage"), let usage = number("PrimaryUsage") else { continue }
            result[name, default: []].append((page, usage))
        }
        return result
    }

    /// IORegistry 中所有帶 BatteryPercent 的服務（藍牙鍵盤、滑鼠、觸控板等）；只讀需要的幾個屬性
    static func hidServices() -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        let matching = ["IOPropertyExistsMatch": "BatteryPercent"] as CFDictionary
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [[String: Any]] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var properties: [String: Any] = [:]
            for key in ["BatteryPercent", "Product", "DeviceAddress", "SerialNumber"] {
                if let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                    properties[key] = value
                }
            }
            result.append(properties)
        }
        return result
    }

    /// 有沒有藍牙音訊裝置（AirPods 等耳機）連著；只問 CoreAudio 的裝置清單，不需要麥克風權限
    static func bluetoothAudioConnected() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return false }
        var transportAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                          mScope: kAudioObjectPropertyScopeGlobal,
                                                          mElement: kAudioObjectPropertyElementMain)
        for device in devices {
            var transport: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &transportAddress, 0, nil, &transportSize, &transport) == noErr,
               transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE {
                return true
            }
        }
        return false
    }
}

/// 周邊設備清單：每 60 秒更新一次，打開周邊設備分頁時立即更新；每個設備依自己的門檻發低電量通知
@MainActor
final class PeripheralStore: ObservableObject {
    @Published private(set) var devices: [PeripheralBattery] = []
    @Published private(set) var updated: Date?
    @Published private(set) var loading = false
    private var alerts = PeripheralAlerts()

    static let interval: TimeInterval = 60

    /// 藍牙低功耗設備讀到新電量時，只重新合併這一部分（不再跑 system_profiler）
    private var base: [PeripheralBattery] = []
    private var listening = false

    /// 已經允許藍牙權限時，背景也讀藍牙低功耗設備（第一次啟動時才會詢問權限，見 AppDelegate）
    func startBluetoothLE() {
        let reader = BLEBatteryReader.shared
        if !listening {
            listening = true
            reader.onUpdate = { [weak self] in
                DispatchQueue.main.async { self?.mergeBluetoothLE() }
            }
        }
        reader.start()
    }

    private func mergeBluetoothLE() {
        guard !loading else { return }
        let ble = PeripheralReader.bluetoothLE()
        apply(PeripheralParse.merge(base, bluetoothLE: ble))
    }

    private func apply(_ found: [PeripheralBattery]) {
        devices = found
        updated = Date()
        let settings = AppSettings.shared
        let due = alerts.evaluate(found) { settings.peripheralThreshold(for: $0) }
        for device in due {
            Notifier.shared.notifyPeripheralLow(device, threshold: settings.peripheralThreshold(for: device.id))
        }
    }

    func refresh(includeAllBluetooth: Bool = false) {
        guard !loading else { return }
        loading = true
        Task {
            let (found, base) = await Task.detached(priority: .utility) { () -> ([PeripheralBattery], [PeripheralBattery]) in
                let base = PeripheralReader.read(includeAllBluetooth: includeAllBluetooth, includeBluetoothLE: false)
                return (PeripheralParse.merge(base, bluetoothLE: PeripheralReader.bluetoothLE()), base)
            }.value
            self.base = base
            loading = false
            apply(found)
        }
    }

    /// 打開分頁時：超過幾秒沒更新就立即查（含所有藍牙設備）
    func refreshIfStale() {
        if updated.map({ Date().timeIntervalSince($0) > 5 }) ?? true { refresh(includeAllBluetooth: true) }
    }

    /// 截圖用的示範數據，不含使用者的真實設備
    func loadPreview(now: Date = Date()) {
        devices = [
            PeripheralBattery(id: "preview-airpods", name: "AirPods Pro - 我的耳機", kind: .headphones, left: 100, right: 100, caseLevel: 70),
            PeripheralBattery(id: "preview-keyboard", name: "Magic Keyboard", kind: .keyboard, level: 88),
            PeripheralBattery(id: "preview-mouse", name: "Magic Mouse", kind: .mouse, level: 14),
        ]
        updated = now
    }
}
