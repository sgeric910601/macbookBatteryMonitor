import Foundation

struct BluetoothSleepTests {
    /// 睡眠時關藍牙、醒來打開；只開回自己關掉的
    func testTurnsOffOnSleepAndBackOnWake() {
        var logic = BluetoothSleep(turnedOff: false)
        XCTAssertEqual(logic.willSleep(enabled: true, poweredOn: true, wakeInputConnected: false), .powerOff)
        XCTAssertTrue(logic.turnedOff)
        XCTAssertEqual(logic.didWake(), .powerOn)
        // 還沒確認打開前標記留著
        XCTAssertTrue(logic.turnedOff)
        XCTAssertEqual(logic.confirm(poweredOn: true), .none)
        XCTAssertTrue(!logic.turnedOff)
        // 再醒來一次（例如連續的喚醒通知）：不重複打開
        XCTAssertEqual(logic.didWake(), .none)
    }

    /// 沒打開功能、藍牙本來就關著、連著藍牙鍵盤滑鼠（關了就叫不醒 Mac）：都不動，醒來也不打開
    func testLeavesBluetoothAlone() {
        var logic = BluetoothSleep(turnedOff: false)
        XCTAssertEqual(logic.willSleep(enabled: false, poweredOn: true, wakeInputConnected: false), .none)
        XCTAssertEqual(logic.willSleep(enabled: true, poweredOn: false, wakeInputConnected: false), .none)
        XCTAssertEqual(logic.willSleep(enabled: true, poweredOn: true, wakeInputConnected: true), .none)
        // 闔上螢幕接外接螢幕：內建鍵盤用不到，不關
        XCTAssertEqual(logic.willSleep(enabled: true, poweredOn: true, wakeInputConnected: false, lidClosed: true), .none)
        XCTAssertEqual(logic.didWake(), .none)
    }

    /// 睡眠中 App 被結束、沒等到醒來：下次啟動時把自己關掉的藍牙打開
    func testLaunchRestoresAfterMissedWake() {
        var crashed = BluetoothSleep(turnedOff: true)
        XCTAssertEqual(crashed.didLaunch(), .powerOn)
        XCTAssertEqual(crashed.confirm(poweredOn: true), .none)
        XCTAssertTrue(!crashed.turnedOff)
        let normal = BluetoothSleep(turnedOff: false)
        XCTAssertEqual(normal.didLaunch(), .none)
    }

    /// 送出打開後還是關著：標記留著、再試一次
    func testRetriesUntilPoweredOn() {
        var logic = BluetoothSleep(turnedOff: true)
        XCTAssertEqual(logic.confirm(poweredOn: false), .powerOn)
        XCTAssertTrue(logic.turnedOff)
        XCTAssertEqual(logic.confirm(poweredOn: true), .none)
        XCTAssertEqual(logic.confirm(poweredOn: false), .none)
    }

    /// 喚醒 Mac 用得到的藍牙輸入裝置：鍵盤、滑鼠、觸控板。耳機、手把以外的其他裝置不算
    func testWakeInputDevices() {
        XCTAssertTrue(BluetoothSleep.isWakeInput(transport: "Bluetooth", usagePage: 1, usage: 6))
        XCTAssertTrue(BluetoothSleep.isWakeInput(transport: "Bluetooth Low Energy", usagePage: 1, usage: 2))
        XCTAssertTrue(BluetoothSleep.isWakeInput(transport: "Bluetooth", usagePage: 0x0D, usage: 5))
        XCTAssertTrue(BluetoothSleep.isWakeInput(transport: "BT-AACP", usagePage: 1, usage: 6))
        XCTAssertTrue(!BluetoothSleep.isWakeInput(transport: "BT-AACP", usagePage: 0xFF00, usage: 53))
        XCTAssertTrue(!BluetoothSleep.isWakeInput(transport: "USB", usagePage: 1, usage: 6))
        XCTAssertTrue(!BluetoothSleep.isWakeInput(transport: "Bluetooth", usagePage: 0x0C, usage: 1))
        XCTAssertTrue(!BluetoothSleep.isWakeInput(transport: "Bluetooth", usagePage: 1, usage: 5))
    }
}
