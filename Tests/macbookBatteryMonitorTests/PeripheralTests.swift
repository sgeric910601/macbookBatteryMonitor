import Foundation

final class PeripheralTests {
    /// system_profiler SPBluetoothDataType -json 的格式（示範數據）
    private let sample = """
    {"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on"},
     "device_connected":[
      {"AirPods Pro":{"device_address":"A1:B2:C3:D4:E5:F6","device_batteryLevelCase":"45%",
        "device_batteryLevelLeft":"80%","device_batteryLevelRight":"76%","device_minorType":"Headphones"}},
      {"Magic Mouse":{"device_address":"11:22:33:44:55:66","device_batteryLevelMain":"64%","device_minorType":"Mouse"}},
      {"Speaker":{"device_address":"99:88:77:66:55:44","device_minorType":"Speaker"}}],
     "device_not_connected":[{"Old Keyboard":{"device_address":"AA:AA:AA:AA:AA:AA","device_batteryLevelMain":"50%"}}]}]}
    """

    func testBluetoothParsing() {
        let devices = PeripheralParse.bluetooth(json: Data(sample.utf8))
        // 只列連線中、有回報電量的設備
        XCTAssertEqual(devices.map(\.name), ["AirPods Pro", "Magic Mouse"])
        let pods = devices[0]
        XCTAssertEqual(pods.kind, .headphones)
        XCTAssertEqual(pods.left, 80)
        XCTAssertEqual(pods.right, 76)
        XCTAssertEqual(pods.caseLevel, 45)
        XCTAssertEqual(pods.lowest, 76)
        XCTAssertEqual(pods.detailText, "左 80%・右 76%・盒 45%")
        XCTAssertEqual(pods.symbol, "airpodspro")
        XCTAssertEqual(devices[1].level, 64)
        XCTAssertEqual(devices[1].id, "11:22:33:44:55:66")
        XCTAssertTrue(PeripheralParse.bluetooth(json: Data("not json".utf8)).isEmpty)
    }

    func testHIDMergeAndDedupe() {
        let hid = PeripheralParse.hid([
            ["Product": "Magic Mouse", "BatteryPercent": 63, "DeviceAddress": "11-22-33-44-55-66"],
            // 同一個設備的第二個 HID 服務
            ["Product": "Magic Mouse", "BatteryPercent": 63, "DeviceAddress": "11-22-33-44-55-66"],
            ["Product": "Magic Keyboard", "BatteryPercent": 88, "DeviceAddress": "77-77-77-77-77-77"],
            ["Product": "Broken", "BatteryPercent": 140],
        ])
        XCTAssertEqual(hid.count, 2)
        XCTAssertEqual(hid[1].kind, .keyboard)
        let merged = PeripheralParse.merge(hid: hid, bluetooth: PeripheralParse.bluetooth(json: Data(sample.utf8)))
        XCTAssertEqual(merged.map(\.name), ["AirPods Pro", "Magic Keyboard", "Magic Mouse"])
        // 兩邊都有時用 system_profiler 的電量與名稱，不重複列出
        XCTAssertEqual(merged.first { $0.name == "Magic Mouse" }?.level, 64)
        XCTAssertEqual(PeripheralParse.normalizedAddress("AA-bb-CC-dd-EE-ff"), "aa:bb:cc:dd:ee:ff")
    }

    func testPerDeviceAlerts() {
        var alerts = PeripheralAlerts()
        var mouse = PeripheralBattery(id: "mouse", name: "Magic Mouse", kind: .mouse, level: 25)
        let pods = PeripheralBattery(id: "pods", name: "AirPods", kind: .headphones, left: 9, right: 40)
        let thresholds = ["mouse": 20, "pods": 10]
        func run(_ devices: [PeripheralBattery]) -> [String] {
            alerts.evaluate(devices) { thresholds[$0] ?? 20 }.map(\.id)
        }
        // 耳機以左右耳較低的那一邊判斷
        XCTAssertEqual(run([mouse, pods]), ["pods"])
        XCTAssertEqual(run([mouse, pods]), [])
        mouse.level = 20
        XCTAssertEqual(run([mouse, pods]), ["mouse"])
        mouse.level = 15
        XCTAssertEqual(run([mouse]), [])
        // 充電回到門檻以上（多 2%）才會再通知
        mouse.level = 22
        XCTAssertEqual(run([mouse]), [])
        mouse.level = 23
        XCTAssertEqual(run([mouse]), [])
        mouse.level = 19
        XCTAssertEqual(run([mouse]), ["mouse"])
        // 門檻設為 0 表示不通知
        var silent = PeripheralAlerts()
        XCTAssertTrue(silent.evaluate([mouse]) { _ in 0 }.isEmpty)
    }

    func testBluetoothLEBattery() {
        // 電池電量是一個位元組 0～100；空值或超出範圍視為讀不到
        XCTAssertEqual(PeripheralParse.bluetoothLELevel(Data([85])), 85)
        XCTAssertEqual(PeripheralParse.bluetoothLELevel(Data([100, 7])), 100)
        XCTAssertNil(PeripheralParse.bluetoothLELevel(Data([101])))
        XCTAssertNil(PeripheralParse.bluetoothLELevel(Data()))
        XCTAssertNil(PeripheralParse.bluetoothLELevel(nil))
        // 名稱看不出種類時用 HID 用途：Razer Basilisk 是滑鼠
        XCTAssertEqual(PeripheralParse.kind(name: "Basilisk X HyperSpeed", usages: [(1, 2), (1, 6)]), .mouse)
        XCTAssertEqual(PeripheralParse.kind(name: "K380", usages: [(1, 6), (12, 1)]), .keyboard)
        XCTAssertEqual(PeripheralParse.kind(name: "MX Anywhere 3S", usages: []), .other)
        XCTAssertEqual(PeripheralParse.kind(name: "MX Master Mouse", usages: [(1, 6)]), .mouse)
        // 同名設備已經由系統資料列出（例如 Apple 的設備）時以原本的為準，不重複
        let existing = [PeripheralBattery(id: "aa:bb", name: "Magic Mouse", kind: .mouse, level: 50)]
        let ble = [PeripheralBattery(id: "ble-1", name: "magic mouse", kind: .mouse, level: 49),
                   PeripheralBattery(id: "ble-2", name: "Basilisk X HyperSpeed", kind: .mouse, level: 72)]
        let merged = PeripheralParse.merge(existing, bluetoothLE: ble)
        XCTAssertEqual(merged.map(\.id), ["ble-2", "aa:bb"])
        XCTAssertEqual(merged.first { $0.id == "aa:bb" }?.level, 50)
    }

    func testDuplicateAirPodsMerge() {
        // 截圖的情況：同一副 AirPods Pro 3 列兩次，一筆只有右耳與充電盒
        let partial = PeripheralBattery(id: "aa", name: "harekaze的AirPods Pro 3", kind: .headphones, right: 78, caseLevel: 66)
        let full = PeripheralBattery(id: "bb", name: "harekaze的AirPods Pro 3", kind: .headphones, left: 75, right: 78, caseLevel: 66)
        let merged = PeripheralParse.mergeSameName([partial, full])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.id, "bb")
        XCTAssertEqual(merged.first?.left, 75)
        XCTAssertEqual(merged.first?.right, 78)
        XCTAssertEqual(merged.first?.caseLevel, 66)
        // 不同名稱的設備不合併
        let mouse = PeripheralBattery(id: "cc", name: "Magic Mouse", kind: .mouse, level: 40)
        XCTAssertEqual(PeripheralParse.mergeSameName([partial, mouse]).count, 2)
    }
}
