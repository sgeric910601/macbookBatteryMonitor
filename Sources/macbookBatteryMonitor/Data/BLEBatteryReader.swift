import CoreBluetooth
import Foundation

/// 藍牙低功耗滑鼠、鍵盤（羅技、Razer 等非 Apple 設備）的電量。
/// macOS 不會把它們的電量放進 IORegistry，系統藍牙選單是向設備的標準電池服務（0x180F）讀「電池電量」（0x2A19）；
/// 這裡用 CoreBluetooth 向「已經連著系統」的設備讀同一個值，不會另外配對，也不影響原本的連線。
/// 第一次使用會詢問藍牙權限，所以只在使用者打開周邊設備分頁、或已經允許過時才啟動
final class BLEBatteryReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    struct Reading: Equatable {
        var id: String
        var name: String
        var level: Int
        var date: Date
    }

    static let shared = BLEBatteryReader()
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")
    /// 讀不到新值超過這麼久（例如設備已經關機）就不再顯示
    private static let maxAge: TimeInterval = 180

    /// 電量有新值時呼叫（在背景佇列）
    var onUpdate: (() -> Void)?

    private let queue = DispatchQueue(label: "com.kuan.batterymonitor.ble")
    // 以下只在 queue 上讀寫
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var readings: [UUID: Reading] = [:]

    /// 已經允許過藍牙權限（啟動時不會跳出詢問）
    static var authorized: Bool { CBManager.authorization == .allowedAlways }
    /// 使用者拒絕了藍牙權限
    static var denied: Bool { CBManager.authorization == .denied || CBManager.authorization == .restricted }

    /// 建立 CoreBluetooth；權限還沒決定時 macOS 會跳出詢問
    func start() {
        queue.async { [self] in
            guard central == nil else { return }
            central = CBCentralManager(delegate: self, queue: queue,
                                       options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
    }

    var started: Bool { queue.sync { central != nil } }

    /// 目前讀到的電量，同時觸發下一次讀取（新值由 onUpdate 通知）
    func currentReadings() -> [Reading] {
        queue.sync {
            refreshOnQueue()
            let fresh = Date().addingTimeInterval(-Self.maxAge)
            return readings.values.filter { $0.date > fresh }.sorted { $0.name < $1.name }
        }
    }

    private func refreshOnQueue() {
        guard let central, central.state == .poweredOn else { return }
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
        let ids = Set(connected.map(\.identifier))
        // 已經斷線的設備不再顯示
        for id in peripherals.keys where !ids.contains(id) {
            peripherals[id] = nil
            readings[id] = nil
        }
        for peripheral in connected {
            peripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            if peripheral.state == .connected {
                readBattery(peripheral)
            } else if peripheral.state == .disconnected {
                // 設備已經連著系統，這裡只是讓本 App 也能讀它的資料，不會建立新的藍牙連線
                central.connect(peripheral)
            }
        }
    }

    private func readBattery(_ peripheral: CBPeripheral) {
        let characteristic = peripheral.services?.first { $0.uuid == Self.batteryService }?
            .characteristics?.first { $0.uuid == Self.batteryLevel }
        if let characteristic {
            peripheral.readValue(for: characteristic)
        } else {
            peripheral.discoverServices([Self.batteryService])
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        refreshOnQueue()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        readBattery(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == Self.batteryService {
            peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] where characteristic.uuid == Self.batteryLevel {
            peripheral.readValue(for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.batteryLevel, error == nil,
              let level = PeripheralParse.bluetoothLELevel(characteristic.value) else { return }
        let reading = Reading(id: "ble-" + peripheral.identifier.uuidString.lowercased(),
                              name: peripheral.name ?? "藍牙設備", level: level, date: Date())
        let changed = readings[peripheral.identifier].map { $0.level != level || $0.name != reading.name } ?? true
        readings[peripheral.identifier] = reading
        if changed { onUpdate?() }
    }
}
