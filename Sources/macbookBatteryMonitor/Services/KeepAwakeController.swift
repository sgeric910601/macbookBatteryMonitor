import AppKit
import Foundation
import IOKit.pwr_mgt
import Observation

/// 防止休眠：用公開的電源管理介面 IOPMAssertion。App 結束時系統會自動解除。
/// 只有啟用期間才每 30 秒檢查一次到期與電量，平常不跑計時器
@MainActor
@Observable
final class KeepAwakeController {
    static let shared = KeepAwakeController()

    private(set) var state = KeepAwake()
    /// 螢幕也保持亮著（預設只讓系統不睡，螢幕照常關）
    var keepDisplayOn = UserDefaults.standard.bool(forKey: "keepAwakeDisplay") {
        didSet {
            UserDefaults.standard.set(keepDisplayOn, forKey: "keepAwakeDisplay")
            if state.isActive { holdAssertions() }
        }
    }
    /// 目前的電量與是否用電池，由 AppDelegate 設定；桌上型 Mac 電量為 nil
    @ObservationIgnored var battery: () -> (percent: Int?, onBattery: Bool) = { (nil, false) }
    /// 面板上剩餘時間的文字跟著更新
    private(set) var now = Date()

    @ObservationIgnored private var assertions: [IOPMAssertionID] = []
    @ObservationIgnored private var timer: Timer?

    // MARK: 指定的 App 執行中時自動防止休眠

    /// 由 AppDelegate 依設定帶入；清單空的時候不監聽任何東西
    var autoApps: Set<String> = [] {
        didSet { if autoApps != oldValue { updateAuto() } }
    }
    /// 自動防止休眠中（面板的咖啡杯也顯示）
    private(set) var autoActive = false
    @ObservationIgnored private var autoAssertion: IOPMAssertionID?
    @ObservationIgnored private var autoObservers: [NSObjectProtocol] = []
    /// 自動防止休眠期間才每 60 秒看一次電量
    @ObservationIgnored private var autoTimer: Timer?

    /// App 開啟、結束時與電量檢查時重新判斷；只監聽 App 開關的通知，不輪詢
    func updateAuto() {
        guard !autoApps.isEmpty else {
            for token in autoObservers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
            autoObservers = []
            setAuto(false)
            return
        }
        if autoObservers.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            autoObservers = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification].map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { KeepAwakeController.shared.updateAuto() }
                }
            }
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let battery = battery()
        setAuto(KeepAwake.autoHolds(running: running, list: autoApps, batteryPercent: battery.percent, onBattery: battery.onBattery))
    }

    private func setAuto(_ hold: Bool) {
        if hold, autoAssertion == nil {
            var id = IOPMAssertionID(0)
            if IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           "macbookBatteryMonitor keep awake while apps run" as CFString, &id) == kIOReturnSuccess {
                autoAssertion = id
            }
            autoTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                MainActor.assumeIsolated { KeepAwakeController.shared.updateAuto() }
            }
        } else if !hold, let id = autoAssertion {
            IOPMAssertionRelease(id)
            autoAssertion = nil
            autoTimer?.invalidate()
            autoTimer = nil
        }
        autoActive = autoAssertion != nil
    }

    func start(_ duration: KeepAwake.Duration) {
        now = Date()
        state.start(duration, now: now)
        holdAssertions()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { KeepAwakeController.shared.check() }
        }
        check()
    }

    func stop() {
        state.stop()
        timer?.invalidate()
        timer = nil
        releaseAssertions()
    }

    private func check() {
        now = Date()
        let battery = battery()
        if state.shouldStop(now: now, batteryPercent: battery.percent, onBattery: battery.onBattery) { stop() }
    }

    private func holdAssertions() {
        releaseAssertions()
        var types = [kIOPMAssertionTypePreventUserIdleSystemSleep]
        if keepDisplayOn { types.append(kIOPMAssertionTypePreventUserIdleDisplaySleep) }
        for type in types {
            var id = IOPMAssertionID(0)
            // 名稱要用 ASCII：pmset 等系統工具不顯示中文名稱（實測顯示成空白）
            if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           "macbookBatteryMonitor keep awake" as CFString, &id) == kIOReturnSuccess {
                assertions.append(id)
            }
        }
    }

    private func releaseAssertions() {
        for id in assertions { IOPMAssertionRelease(id) }
        assertions = []
    }
}
