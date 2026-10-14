import Foundation
final class ChargingPresentationTests {
    func testFullPriorityAndBriefFlagChanges() {
        var filter = ChargingPresentation()
        var s = BatterySnapshot(percent: 100, externalConnected: true, fullyCharged: true,
            voltage_mV: 12000, amperage_mA: 0)
        s.applyLivePower(battery: 0.9, adapter: 12, system: 13.1)
        XCTAssertEqual(filter.state(s, uptime: 0), .full)
        for t in 1...12 {
            s.isCharging = t % 2 == 0
            s.fullyCharged = t % 3 == 0
            XCTAssertEqual(filter.state(s, uptime: Double(t)), .full)
        }
        let e = Estimator.estimates(s, avgDischarge_mA: nil, avgCharge_mA: nil, displayState: .full)
        XCTAssertEqual(e.state, .full)
        XCTAssertTrue(abs(e.batteryWatts + 1.1) < 0.001)
        XCTAssertEqual(e.flowKind, .adapter)
        XCTAssertNil(e.toFull)
    }
    func testFullHysteresisAndSustainedRecharge() {
        var filter = ChargingPresentation()
        var s = BatterySnapshot(percent: 100, externalConnected: true, fullyCharged: true)
        XCTAssertEqual(filter.state(s, uptime: 0), .full)
        s.percent = 99; s.fullyCharged = false
        XCTAssertEqual(filter.state(s, uptime: 1), .full)
        s.isCharging = true
        XCTAssertEqual(filter.state(s, uptime: 2), .full)
        XCTAssertEqual(filter.state(s, uptime: 11), .full)
        XCTAssertEqual(filter.state(s, uptime: 12), .charging)
        s.isCharging = false
        XCTAssertEqual(filter.state(s, uptime: 13), .charging)
        XCTAssertEqual(filter.state(s, uptime: 23), .full)
        s.percent = 98
        XCTAssertEqual(filter.state(s, uptime: 24), .full)
        s.percent = 97
        XCTAssertEqual(filter.state(s, uptime: 25), .pluggedIdle)
    }
    func testInterruptedConfirmationAndUnplugAreImmediate() {
        var filter = ChargingPresentation()
        var s = BatterySnapshot(percent: 100, externalConnected: true)
        XCTAssertEqual(filter.state(s, uptime: 0), .full)
        s.percent = 99; s.isCharging = true
        XCTAssertEqual(filter.state(s, uptime: 1), .full)
        s.isCharging = false
        XCTAssertEqual(filter.state(s, uptime: 9), .full)
        s.isCharging = true
        XCTAssertEqual(filter.state(s, uptime: 10), .full)
        XCTAssertEqual(filter.state(s, uptime: 19), .full)
        s.externalConnected = false
        XCTAssertEqual(filter.state(s, uptime: 19.1), .discharging)
        let e = Estimator.estimates(s, avgDischarge_mA: nil, avgCharge_mA: nil, displayState: .full)
        XCTAssertEqual(e.state, .discharging)
        XCTAssertEqual(e.flowKind, .battery)
        s.externalConnected = true
        XCTAssertEqual(filter.state(s, uptime: 20), .charging)
    }
    func testRealMixedSupplyAtFullIsNotHidden() {
        var filter = ChargingPresentation()
        var s = BatterySnapshot(percent: 100, externalConnected: true, fullyCharged: true,
            voltage_mV: 12000, amperage_mA: 0)
        XCTAssertEqual(filter.state(s, uptime: 0), .full)
        s.amperage_mA = -1000
        XCTAssertEqual(filter.state(s, uptime: 1), .full)
        XCTAssertEqual(filter.state(s, uptime: 11), .full)
        var flow = PowerFlowPresentation()
        XCTAssertEqual(flow.kind(connected: true, watts: 0, holding: true, uptime: 0), .adapter)
        XCTAssertEqual(flow.kind(connected: true, watts: -12, holding: true, uptime: 1), .adapter)
        XCTAssertEqual(flow.kind(connected: true, watts: -12, holding: true, uptime: 11), .mixed)
        var e = Estimator.estimates(s, avgDischarge_mA: nil, avgCharge_mA: nil, displayState: .full)
        e.displayFlow = .mixed
        XCTAssertEqual(e.state, .full)
        XCTAssertEqual(e.flowKind, .mixed)
        XCTAssertEqual(e.batteryWatts, -12)
    }
    func testInitialNearFullSpikeAlsoNeedsConfirmation() {
        var flow = PowerFlowPresentation()
        XCTAssertEqual(flow.kind(connected: true, watts: 7, holding: true, uptime: 0), .adapter)
        XCTAssertEqual(flow.kind(connected: true, watts: -5, holding: true, uptime: 1), .adapter)
        XCTAssertEqual(flow.kind(connected: true, watts: 0.2, holding: true, uptime: 2), .adapter)
        XCTAssertEqual(flow.kind(connected: true, watts: -12, holding: true, uptime: 3), .adapter)
        XCTAssertEqual(flow.kind(connected: true, watts: -12, holding: true, uptime: 13), .mixed)
    }
    func testMinorAssistAndFlowConfirmation() {
        var flow = PowerFlowPresentation()
        XCTAssertEqual(flow.kind(connected: true, watts: 0, holding: true, uptime: 0), .adapter)
        for t in 1...20 {
            XCTAssertEqual(flow.kind(connected: true, watts: t % 2 == 0 ? 1.9 : -1.9,
                                     holding: true, uptime: Double(t)), .adapter)
        }
        XCTAssertEqual(flow.kind(connected: true, watts: -3, holding: true, uptime: 21), .adapter)
        XCTAssertEqual(flow.kind(connected: true, watts: -3, holding: true, uptime: 30), .adapter)
        XCTAssertEqual(flow.kind(connected: true, watts: -3, holding: true, uptime: 31), .mixed)
        XCTAssertEqual(flow.kind(connected: true, watts: 4, holding: true, uptime: 32), .mixed)
        XCTAssertEqual(flow.kind(connected: true, watts: 4, holding: true, uptime: 42), .charging)
        XCTAssertEqual(flow.kind(connected: true, watts: -1, holding: true, uptime: 43), .charging)
        XCTAssertEqual(flow.kind(connected: true, watts: -1, holding: true, uptime: 53), .adapter)
        XCTAssertEqual(flow.kind(connected: false, watts: -1, holding: true, uptime: 53.1), .battery)
        XCTAssertEqual(flow.kind(connected: true, watts: -1, holding: true, uptime: 53.2), .adapter)
        XCTAssertEqual(flow.kind(connected: true, watts: -1, holding: false, uptime: 53.3), .mixed)
        var filter = ChargingPresentation()
        var s = BatterySnapshot(percent: 100, externalConnected: true, fullyCharged: true,
            voltage_mV: 12000, amperage_mA: -100)
        XCTAssertEqual(filter.state(s, uptime: 0), .full)
        s.fullyCharged = false
        XCTAssertEqual(filter.state(s, uptime: 20), .full)
    }
    func testChargeLimitAndMixedSupplyOutsideFullArePreserved() {
        var filter = ChargingPresentation()
        var s = BatterySnapshot(percent: 100, externalConnected: true, fullyCharged: true)
        XCTAssertEqual(filter.state(s, uptime: 0), .full)
        s.chargeLimit = ChargeLimit(limit: 80, reason: "manualChargeLimit")
        s.amperage_mA = -1000; s.voltage_mV = 12000
        XCTAssertEqual(filter.state(s, uptime: 1), .limitReached)
        s.chargeLimit = nil; s.fullyCharged = false; s.percent = 75
        XCTAssertEqual(filter.state(s, uptime: 2), .pluggedIdle)
        let e = Estimator.estimates(s, avgDischarge_mA: nil, avgCharge_mA: nil)
        XCTAssertEqual(e.flowKind, .mixed)
        s.isCharging = true
        XCTAssertEqual(filter.state(s, uptime: 3), .pluggedIdle)
        XCTAssertEqual(filter.state(s, uptime: 13), .charging)
    }

    /// 實測情境：充電上限 95%、電量 90%，晶片回報「未充電、電流 0」，SMC 卻顯示約 14 W 充入電池
    func testStaleRegistryFlagUsesLivePower() {
        var s = BatterySnapshot(percent: 90, externalConnected: true, voltage_mV: 12600, amperage_mA: 0)
        s.fullCharge_mAh = 4700
        s.chargeLimit = ChargeLimit(limit: 95, reason: "manualChargeLimit")
        s.applyLivePower(battery: nil, adapter: 20.7, system: 6.3)
        XCTAssertTrue(s.chargingNow)
        XCTAssertEqual(Estimator.state(s), .charging)
        let e = Estimator.estimates(s, avgDischarge_mA: nil, avgCharge_mA: 1100)
        XCTAssertEqual(e.state, .charging)
        XCTAssertEqual(e.flowKind, .charging)
        XCTAssertTrue(e.toLimit != nil)
        // 晶片說在充電，但 SMC 幾乎沒有電流進電池：以功率為準，視為暫停
        s.isCharging = true
        s.applyLivePower(battery: nil, adapter: 6.5, system: 6.3)
        XCTAssertTrue(!s.chargingNow)
        XCTAssertEqual(Estimator.state(s), .pluggedIdle)
        // 0.5～3 W 模糊區間才看晶片旗標
        s.applyLivePower(battery: nil, adapter: 8.0, system: 6.3)
        XCTAssertTrue(s.chargingNow)
        s.isCharging = false
        XCTAssertTrue(!s.chargingNow)
        // 實測：到達 95% 上限後 SMC 偶爾出現 +4.5 W 的單筆雜訊，晶片旗標為未充電，不算充電
        s.percent = 95
        s.applyLivePower(battery: nil, adapter: 10.8, system: 6.3)
        XCTAssertTrue(!s.chargingNow)
        XCTAssertEqual(Estimator.state(s), .limitReached)
    }

    /// 充到上限附近 macOS 反覆暫停／恢復充電：狀態要持續 10 秒才切換，流向圖跟著狀態
    func testChargeLimitFlappingIsConfirmed() {
        var filter = ChargingPresentation()
        var flow = PowerFlowPresentation()
        var s = BatterySnapshot(percent: 94, externalConnected: true, voltage_mV: 12600, amperage_mA: 0)
        s.chargeLimit = ChargeLimit(limit: 95, reason: "manualChargeLimit")
        s.applyLivePower(battery: nil, adapter: 7, system: 6.5)
        XCTAssertEqual(filter.state(s, uptime: 0), .limitReached)
        XCTAssertEqual(flow.kind(connected: true, watts: 0.5, holding: true, uptime: 0), .adapter)
        for t in 1...9 {
            s.applyLivePower(battery: nil, adapter: t % 3 == 0 ? 7 : 20, system: 6.5)
            XCTAssertEqual(filter.state(s, uptime: Double(t)), .limitReached)
        }
        // 持續充電 10 秒以上才顯示充電中
        s.applyLivePower(battery: nil, adapter: 20, system: 6.5)
        XCTAssertEqual(filter.state(s, uptime: 10), .limitReached)
        XCTAssertEqual(filter.state(s, uptime: 20), .charging)
        // 拔掉電源立即切換
        s.externalConnected = false
        XCTAssertEqual(filter.state(s, uptime: 20.5), .discharging)
    }

    /// Intel 剛插電時電池先放電（電池一起供電），十幾秒後才開始充電：狀態還在確認時，流向圖不能把充入的功率畫成負的電池供電
    func testPlugInFromBatteryAssistToChargingSwitchesAtOnce() {
        var flow = PowerFlowPresentation()
        XCTAssertEqual(flow.kind(connected: true, watts: -13, holding: false, uptime: 0), .mixed)
        XCTAssertEqual(flow.kind(connected: true, watts: 14, holding: true, uptime: 13), .charging)
        // 小幅的方向變化仍要確認 10 秒
        var held = PowerFlowPresentation()
        XCTAssertEqual(held.kind(connected: true, watts: -3, holding: false, uptime: 0), .mixed)
        XCTAssertEqual(held.kind(connected: true, watts: 4, holding: true, uptime: 1), .mixed)
        XCTAssertEqual(held.kind(connected: true, watts: 4, holding: true, uptime: 11), .charging)
    }

    /// macOS 還在估算剩餘時間（-1）時不改用電池晶片的平均時間；沒有這個欄位才用
    func testSystemTimeWaitsForMacOSEstimate() {
        var s = BatterySnapshot(percent: 49, voltage_mV: 7580, amperage_mA: -2400)
        s.avgTimeToEmpty = 770
        s.psReportsTime = true
        XCTAssertEqual(Estimator.estimates(s, avgDischarge_mA: 2000, avgCharge_mA: nil).systemToEmpty, nil)
        s.psTimeToEmpty = 95
        XCTAssertEqual(Estimator.estimates(s, avgDischarge_mA: 2000, avgCharge_mA: nil).systemToEmpty, 95)
        s.psTimeToEmpty = nil
        s.psReportsTime = false
        XCTAssertEqual(Estimator.estimates(s, avgDischarge_mA: 2000, avgCharge_mA: nil).systemToEmpty, 770)
        // 充電中：macOS 還在估算時不用直線推算（沒考慮 80% 以上變慢，會太樂觀）
        var c = BatterySnapshot(percent: 70, isCharging: true, externalConnected: true, voltage_mV: 8200, amperage_mA: 3100)
        c.fullCharge_mAh = 6031
        c.remaining_mAh = 4222
        c.psReportsTime = true
        XCTAssertNil(Estimator.estimates(c, avgDischarge_mA: nil, avgCharge_mA: 3166, displayState: .charging).toFull)
        c.psTimeToFull = 80
        XCTAssertEqual(Estimator.estimates(c, avgDischarge_mA: nil, avgCharge_mA: 3166, displayState: .charging).toFull, 80)
        c.psTimeToFull = nil
        c.psReportsTime = false
        XCTAssertEqual(Estimator.estimates(c, avgDischarge_mA: nil, avgCharge_mA: 3166, displayState: .charging).toFull, 34)
    }

    /// Intel 快要充滿、充電電流很小時，SMC 推算的電池功率是小負值：晶片明確回報在充電就算充電，不顯示「供電不足」
    func testIntelTrickleChargeFollowsBatteryChip() {
        var s = BatterySnapshot(percent: 86, isCharging: true, externalConnected: true, voltage_mV: 8200, amperage_mA: 95)
        s.applyLivePower(battery: nil, adapter: 12, system: 15)
        // Apple 晶片照舊以 SMC 為準
        XCTAssertEqual(Estimator.state(s), .pluggedIdle)
        XCTAssertTrue(Estimator.estimates(s, avgDischarge_mA: nil, avgCharge_mA: nil).drainingOnAC)
        s.isIntel = true
        XCTAssertEqual(Estimator.state(s), .charging)
        XCTAssertEqual(s.effectiveAmperage_mA, 95)
        let e = Estimator.estimates(s, avgDischarge_mA: nil, avgCharge_mA: nil)
        XCTAssertTrue(!e.drainingOnAC)
        XCTAssertTrue(e.batteryWatts > 0)
        // 晶片沒說在充電時仍以 SMC 為準
        s.isCharging = false
        XCTAssertEqual(Estimator.state(s), .pluggedIdle)
    }

    /// 電量高於上限、macOS 讓電池放電到上限時，流向圖要畫出電池一起供電，與狀態文字一致
    func testDrainingAboveLimitIsNotHeld() {
        var s = BatterySnapshot(percent: 97, externalConnected: true, voltage_mV: 12600, amperage_mA: 0)
        s.chargeLimit = ChargeLimit(limit: 95, reason: "manualChargeLimit")
        s.applyLivePower(battery: nil, adapter: 4, system: 6.5)
        XCTAssertEqual(Estimator.state(s), .limitReached)
        XCTAssertTrue(s.drainingAboveLimit)
        // 小於 50 mA 的雜訊不算在放電
        s.applyLivePower(battery: nil, adapter: 6.2, system: 6.5)
        XCTAssertTrue(!s.drainingAboveLimit)
        s.percent = 95
        s.applyLivePower(battery: nil, adapter: 4, system: 6.5)
        XCTAssertTrue(!s.drainingAboveLimit)
    }
}
