import Foundation

/// 寫成和 powerd 一樣的 ChargeCtrlPolicy 封存格式
@objc(TestChargeCtrlPolicy)
private final class FakeChargePolicy: NSObject, NSCoding {
    let soclimit: Int
    let reason: String?
    let terminated: Bool

    init(_ soclimit: Int, _ reason: String?, terminated: Bool = false) {
        self.soclimit = soclimit
        self.reason = reason
        self.terminated = terminated
    }

    required init?(coder: NSCoder) { nil }

    func encode(with coder: NSCoder) {
        coder.encode(soclimit, forKey: "soclimit")
        coder.encode(reason, forKey: "reason")
        coder.encode(terminated, forKey: "terminated")
    }
}

/// 系統更新改了輸出格式時，這些解析會悄悄變成空白；用假資料固定目前認得的格式
struct ParserTests {
    private func chargingPlist(_ policies: [FakeChargePolicy]) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.setClassName("ChargeCtrlPolicy", for: FakeChargePolicy.self)
        archiver.encode(policies as NSArray, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        return try! PropertyListSerialization.data(fromPropertyList: ["policies": archiver.encodedData], format: .binary, options: 0)
    }

    /// 取生效中、使用者手動設定的最低上限；暫停中、其他原因、100% 的都不算
    func testChargeLimitPicksLowestManualPolicy() {
        let data = chargingPlist([
            FakeChargePolicy(85, "manualChargeLimit"),
            FakeChargePolicy(80, "manualChargeLimit"),
            FakeChargePolicy(60, "manualChargeLimit", terminated: true),
            FakeChargePolicy(50, "optimizedBatteryCharging"),
        ])
        XCTAssertEqual(ChargeLimitReader.parse(data), ChargeLimit(limit: 80, reason: "manualChargeLimit"))
        XCTAssertEqual(ChargeLimitReader.parse(chargingPlist([FakeChargePolicy(100, "manualChargeLimit")])), nil)
        XCTAssertEqual(ChargeLimitReader.parse(chargingPlist([])), nil)
    }

    /// 檔案損壞或沒有 policies 時不當成有上限
    func testChargeLimitRejectsUnexpectedData() {
        XCTAssertEqual(ChargeLimitReader.parse(Data("not a plist".utf8)), nil)
        let empty = try! PropertyListSerialization.data(fromPropertyList: ["other": 1], format: .binary, options: 0)
        XCTAssertEqual(ChargeLimitReader.parse(empty), nil)
    }

    /// top 印兩次取樣：只用最後一段；略過 top 自己、耗電 0 和格式不符的行；依耗電排序並截斷
    func testProcessEnergyUsesLastSample() {
        // PID 超過 macOS 上限（99998），查不到 App 與程序名稱，名稱就是 top 的 COMMAND 欄
        let output = """
        Processes: 500 total
        PID        COMMAND          POWER
        99999901   Finder           0.0
        99999902   Safari           0.0

        Processes: 500 total
        PID        COMMAND          POWER
        99999901   Finder           1.5
        99999902   Google Chrome He 12.3
        99999903   top              9.9
        99999904   kernel_task      0.0
        garbage line
        99999905   WindowServer     4.0
        """
        let all = ProcessEnergy.parse(output, limit: 5)
        XCTAssertEqual(all.map(\.name), ["Google Chrome He", "WindowServer", "Finder"])
        XCTAssertEqual(all.map(\.power), [12.3, 4.0, 1.5])
        XCTAssertEqual(all.first?.id, "pid:99999902")
        XCTAssertEqual(ProcessEnergy.parse(output, limit: 2).count, 2)
    }

    /// 沒有輸出或沒有標題列時是空的
    func testProcessEnergyEmpty() {
        XCTAssertEqual(ProcessEnergy.parse(nil, limit: 5), [])
        XCTAssertEqual(ProcessEnergy.parse("no header here", limit: 5), [])
    }
}
