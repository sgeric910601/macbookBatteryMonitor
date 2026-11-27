import CoreBluetooth
import Foundation

/// 藍牙低功耗滑鼠、鍵盤（羅技、Razer 等非 Apple 設備）的電量。
/// macOS 不會把它們的電量放進 IORegistry，系統藍牙選單是向設備的標準電池服務（0x180F）讀「電池電量」（0x2A19）；
/// 這裡用 CoreBluetooth 向「已經連著系統」的設備讀同一個值，不會另外配對，也不影響原本的連線。
/// 透過接續互通連著的 iPhone 也提供這個服務；另外讀一次裝置資訊（0x180A）的型號（0x2A24）來辨認機型。
/// 第一次使用會詢問藍牙權限，所以只在使用者打開周邊設備分頁、或已經允許過時才啟動
final class BLEBatteryReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    struct Reading: Equatable {
        var id: String
        var name: String
        var level: Int
        var date: Date
        /// 型號代號（例如 "iPhone14,2"）；設備沒提供時是 nil
        var model: String?
    }

    static let shared = BLEBatteryReader()
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")
    private static let deviceInfoService = CBUUID(string: "180A")
    private static let modelNumber = CBUUID(string: "2A24")
    /// 讀不到新值超過這麼久（例如設備已經關機）就不再顯示
    private static let maxAge: TimeInterval = 180

    /// 電量有新值時呼叫（在背景佇列）
    var onUpdate: (() -> Void)?

    private let queue = DispatchQueue(label: "com.kuan.batterymonitor.ble")
    // 以下只在 queue 上讀寫
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var readings: [UUID: Reading] = [:]
    /// 型號不會變：每次連線只讀一次（成功或失敗都記在 modelDone）
    private var models: [UUID: String] = [:]
    // shortcut: 讀失敗就不重試，該次連線不顯示機型；真的常見失敗時再加有上限的重試
    private var modelDone: Set<UUID> = []
    /// 正在讀型號的設備與開始時間
    private var modelPending: [UUID: Date] = [:]
    private static let modelTimeout: TimeInterval = 10
    /// 關掉「顯示 iPhone」時為 true：型號讀完（或失敗、逾時）前不列出電量，
    /// 否則手機會先以「其他」種類出現並發低電量通知。預設開著時不等，其他設備不會因此延後出現
    private var holdUntilModel = false

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

    func setHoldUntilModel(_ hold: Bool) { queue.async { self.holdUntilModel = hold } }

    /// 目前讀到的電量，同時觸發下一次讀取（新值由 onUpdate 通知）
    func currentReadings() -> [Reading] {
        queue.sync {
            refreshOnQueue()
            let fresh = Date().addingTimeInterval(-Self.maxAge)
            return readings.filter { $0.value.date > fresh && !isWithheld($0.key) }.map(\.value).sorted { $0.name < $1.name }
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
            models[id] = nil
            modelPending[id] = nil
            modelDone.remove(id)
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
            peripheral.discoverServices([Self.batteryService, Self.deviceInfoService])
        }
    }

    private func isWithheld(_ id: UUID) -> Bool {
        holdUntilModel && (modelPending[id].map { Date().timeIntervalSince($0) < Self.modelTimeout } ?? false)
    }

    /// 開始讀型號；逾時還沒讀完就當作失敗，讓電量照常列出
    private func startModel(_ peripheral: CBPeripheral, service: CBService) {
        let id = peripheral.identifier
        guard !modelDone.contains(id), modelPending[id] == nil else { return }
        let started = Date()
        modelPending[id] = started
        peripheral.discoverCharacteristics([Self.modelNumber], for: service)
        queue.asyncAfter(deadline: .now() + Self.modelTimeout) { [weak self, weak peripheral] in
            guard let self, let peripheral, self.modelPending[id] == started else { return }
            self.finishModel(peripheral, model: nil)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        refreshOnQueue()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        readBattery(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            if service.uuid == Self.batteryService {
                peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
            } else if service.uuid == Self.deviceInfoService {
                startModel(peripheral, service: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? []
        where characteristic.uuid == Self.batteryLevel || characteristic.uuid == Self.modelNumber {
            peripheral.readValue(for: characteristic)
        }
        // 裝置資訊服務裡沒有型號：不用再等
        if service.uuid == Self.deviceInfoService, service.characteristics?.contains(where: { $0.uuid == Self.modelNumber }) != true {
            finishModel(peripheral, model: nil)
        }
    }

    /// 型號讀完（nil 表示失敗）：不再擋住電量，有讀過電量就通知更新。每次連線只會生效一次
    private func finishModel(_ peripheral: CBPeripheral, model: String?) {
        let id = peripheral.identifier
        guard modelPending.removeValue(forKey: id) != nil else { return }
        modelDone.insert(id)
        if let model { models[id] = model }
        if var reading = readings[id] {
            reading.model = models[id]
            readings[id] = reading
            onUpdate?()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == Self.modelNumber {
            finishModel(peripheral, model: error == nil ? PeripheralParse.bluetoothLEText(characteristic.value) : nil)
            return
        }
        guard error == nil, characteristic.uuid == Self.batteryLevel,
              let level = PeripheralParse.bluetoothLELevel(characteristic.value) else { return }
        let reading = Reading(id: "ble-" + peripheral.identifier.uuidString.lowercased(),
                              name: peripheral.name ?? "藍牙設備", level: level, date: Date(),
                              model: models[peripheral.identifier])
        let changed = readings[peripheral.identifier].map { $0.level != level || $0.name != reading.name || $0.model != reading.model } ?? true
        readings[peripheral.identifier] = reading
        // 型號還在讀時先不通知，等 finishModel 一起通知
        if changed, !isWithheld(peripheral.identifier) { onUpdate?() }
    }
}
