import AppKit
import Observation
import OSLog

struct XDRGammaSnapshot {
    var display: CGDirectDisplayID
    var red: [Float]
    var green: [Float]
    var blue: [Float]

    static func capture(_ display: CGDirectDisplayID) -> XDRGammaSnapshot? {
        var r = [Float](repeating: 0, count: 1024), g = r, b = r
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, 1024, &r, &g, &b, &count) == .success,
              count > 1, count <= 1024 else { return nil }
        return .init(display: display, red: Array(r.prefix(Int(count))),
                     green: Array(g.prefix(Int(count))), blue: Array(b.prefix(Int(count))))
    }
}

@MainActor @Observable
final class XDRBrightnessController {
    static let shared = XDRBrightnessController()
    private(set) var enabled = false
    private(set) var preparing = false
    private(set) var gain = 1.0
    private(set) var maximumGain = 1.6
    private(set) var targetNits: Int?
    private(set) var status = "未開啟"
    var automaticActivation: Bool { AppSettings.shared.xdrAutomaticActivation }
    private static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "XDR")
    @ObservationIgnored private var displayID: CGDirectDisplayID?
    @ObservationIgnored private var screenFrame: NSRect?
    @ObservationIgnored private var surface: XDRSurface?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var deadline: Date?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var inputAvailable = true
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var keys: XDRBrightnessKeys?
    @ObservationIgnored private var safetyTimer: Timer?
    private let hud = XDRBrightnessHUD()
    @ObservationIgnored private var sampleTask: Task<Void, Never>?
    /// 取樣進行中又有人要新的（例如按亮度鍵剛把系統亮度推到頂）：這次結束後馬上再取一次，不用等下一秒
    @ObservationIgnored private var snapshotPending = false
    @ObservationIgnored private var keySnapshot = XDRKeySnapshot(nativeBrightness: nil, allowed: false, sampledAt: 0)
    @ObservationIgnored private var keyGain = 1.0
    @ObservationIgnored private var cachedKeyAllowed = false
    @ObservationIgnored private var keyTask: Task<Void, Never>?
    @ObservationIgnored private var displaySignature: String?
    @ObservationIgnored private var lifecycleSuspended = false
    @ObservationIgnored private var capturePaused = false
    /// 截圖程式最近一次啟動（或按下截圖快捷鍵）的時間。截圖程式截完後常會在背景留好幾分鐘，
    /// 所以只看「剛啟動」：只擋按下快捷鍵到選取框出現之間的空檔，之後交給 captureUIOnScreen 判斷
    @ObservationIgnored private var captureStartedAt = -Double.infinity
    private var captureRecent: Bool { ProcessInfo.processInfo.systemUptime - captureStartedAt < 1.5 }
    @ObservationIgnored private var captureMonitor: Any?
    @ObservationIgnored private var localCaptureMonitor: Any?
    @ObservationIgnored private var nativeRefreshTask: Task<Void, Never>?


    var screen: NSScreen? {
        NSScreen.screens.first {
            guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) != 0 && $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 1
        }
    }
    var supported: Bool { screen != nil && maximumGain > 1 }

    /// 功能管理與貓咪選單用：重新讀顯示器規格，回答這台 Mac 現在有沒有支援的內建 XDR 螢幕。
    /// 沒有時不能加入；已加入的仍可移除，而且不建立計時器、取樣或按鍵攔截
    func checkSupport() -> Bool {
        refreshDisplayLimits()
        return supported
    }

    /// 打包自測確認移除功能後所有工作都停止，且週期檢查不會偷偷重新啟動。
    var completelyStopped: Bool {
        !started && !enabled && !preparing && safetyTimer == nil && keys == nil
            && surface == nil && captureMonitor == nil && localCaptureMonitor == nil && sampleTask == nil
            && nativeRefreshTask == nil && keyTask == nil
    }

    var renderingHealthy: Bool { surface?.visible == true && (surface?.completedFrames ?? 0) > 0 }
    var renderingStatus: String {
        "visible=\(surface?.visible ?? false), submitted=\(surface?.renderedFrames ?? 0), completed=\(surface?.completedFrames ?? 0), presented=\(surface?.presentedFrames ?? 0), revealed=\(surface?.revealed ?? false), drawable=\(surface?.drawableStatus ?? "none"), HUD \(hud.geometryStatus)"
    }
    var keysStatus: String { keys?.status ?? "亮度鍵自動啟用已關閉" }

    func start() {
        guard !started, Bundle.main.bundleIdentifier == "com.kuan.batterymonitor",
              !CommandLine.arguments.contains(where: { $0.hasPrefix("--snapshot") || $0.hasPrefix("--screenshots") }) else { return }
        started = true
        lifecycleSuspended = false
        capturePaused = false
        refreshDisplayLimits()
        updateKeyMonitoring()
        Self.log.notice("Automatic XDR: \(self.automaticActivation, privacy: .public), keys: \(self.keysStatus, privacy: .public)")
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspend(reason: "螢幕已鎖定，已還原亮度") }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspend(reason: "睡眠或鎖定，已還原亮度") }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.resume() } })
        observers.append(workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                               object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      Self.isCaptureApplication(app) else { return }
                self?.captureStartedAt = ProcessInfo.processInfo.systemUptime
                self?.pauseForCapture()
            }
        })
        // 接上或拔掉螢幕、闔上或打開筆電時馬上重新判斷，不用等下一次重新整理
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.reconcile() } })
        updateSafetyTimer()
    }

    /// 需要背景檢查與取樣的時候：增亮中、正在啟動，或亮度鍵攔截真的在運作（要用最新的快照判斷）。
    /// 只是加入功能、從滑桿手動開啟、或沒有輔助使用權限建不起攔截時，平常不檢查，按下開啟時才讀一次
    private var needsMonitoring: Bool { enabled || preparing || keys?.isRunning == true }

    /// 每秒的檢查只在有支援的螢幕、而且需要時才跑；沒有支援的 Mac（或闔上筆電只接外接螢幕時）不在背景查詢
    private func updateSafetyTimer() {
        guard started, supported, needsMonitoring else {
            safetyTimer?.invalidate(); safetyTimer = nil
            return
        }
        guard safetyTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
        safetyTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        guard started else { return }
        started = false
        sampleTask?.cancel(); sampleTask = nil
        snapshotPending = false
        nativeRefreshTask?.cancel(); nativeRefreshTask = nil
        safetyTimer?.invalidate(); safetyTimer = nil
        disable(reason: "功能未加入")
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        displaySignature = nil
        keySnapshot = XDRKeySnapshot(nativeBrightness: nil, allowed: false, sampledAt: 0)
    }

    private func suspend(reason: String) {
        lifecycleSuspended = true
        keySnapshot = XDRKeySnapshot(nativeBrightness: nil, allowed: false, sampledAt: 0)
        disable(reason: reason)
    }

    private func resume() {
        guard started else { return }
        lifecycleSuspended = false
        updateKeyMonitoring()
    }

    func setAutomaticActivation(_ allowed: Bool) {
        AppSettings.shared.xdrAutomaticActivation = allowed
        updateKeyMonitoring()
    }

    func setInputAvailable(_ available: Bool) {
        inputAvailable = available
        updateKeyMonitoring()
    }

    private func updateKeyMonitoring() {
        // 自動啟用、增亮狀態改變時，每秒檢查與取樣跟著開始或停止
        defer {
            updateSafetyTimer()
            requestSnapshot()
        }
        guard inputAvailable, !lifecycleSuspended, started, supported, automaticActivation || enabled else {
            keys?.stop()
            keys = nil
            return
        }
        if keys == nil { keys = XDRBrightnessKeys { [weak self] up in self?.handleKey(up: up) ?? false } }
        keys?.start()
    }

    private func refreshDisplayLimits() {
        guard let screen,
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            maximumGain = 1.6
            targetNits = nil
            displaySignature = nil
            return
        }
        let potential = Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
        let signature = "\(id):\(potential)"
        guard signature != displaySignature else { return }
        displaySignature = signature
        maximumGain = XDRLuminanceReader.maximumGain(display: id, potentialHeadroom: potential)
        targetNits = XDRLuminanceReader.targetNits(display: id, potentialHeadroom: potential)
        if enabled && gain > maximumGain { setGain(maximumGain) }
    }

    func reconcile() {
        guard started else { return }
        refreshDisplayLimits()
        updateSafetyTimer()
        updateKeyMonitoring()
        reconcileActiveState()
        cachedKeyAllowed = unavailableReason == nil
    }

    private func requestSnapshot() {
        // 沒有支援的螢幕、或不需要背景檢查時不取樣（手動開啟時在 enable 裡同步讀一次）
        guard started, supported, needsMonitoring else { return }
        guard sampleTask == nil else {
            snapshotPending = true
            return
        }
        let id = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        sampleTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { XDRSystemQuery.snapshot(display: id) }.value
            guard let self, !Task.isCancelled, started else { return }
            sampleTask = nil
            keySnapshot = result
            cachedKeyAllowed = unavailableReason == nil
            reconcileActiveState()
            if snapshotPending {
                snapshotPending = false
                requestSnapshot()
            }
        }
    }

    private func reconcileActiveState() {
        guard enabled else { return }
        if let reason = unavailableReason { disable(reason: reason) }
        else if let deadline, Date() >= deadline { disable(reason: "30 分鐘已到，已還原亮度") }
        else if let id = displayID,
                screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID != id {
            disable(reason: "顯示器已變更，已還原亮度")
        } else if screen?.frame != screenFrame {
            disable(reason: "顯示尺寸已變更，已還原亮度")
        } else if Self.captureUIOnScreen() {
            // 截圖快捷鍵被系統攔走、截圖程式又早就在背景時收不到任何事件：每秒檢查與調整亮度時看畫面上有沒有選取框
            pauseForCapture()
        }
    }

    private var unavailableReason: String? {
        let age = ProcessInfo.processInfo.systemUptime - keySnapshot.sampledAt
        let locked = lifecycleSuspended || !keySnapshot.allowed || age < 0 || age > 2.5
        return XDRBrightnessPolicy.blockReason(supported: supported,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled || AppSettings.shared.powerSavingActive,
            hot: [.serious, .critical].contains(ProcessInfo.processInfo.thermalState), locked: locked)
    }

    func enable(initialGain: Double = 1.15) {
        guard started, !enabled, !preparing else { return }
        capturePaused = false
        guard Bundle.main.bundleIdentifier == "com.kuan.batterymonitor",
              !CommandLine.arguments.contains(where: { $0.hasPrefix("--snapshot") || $0.hasPrefix("--screenshots") }) else {
            status = "僅在正式打包 App 中開啟"; return
        }
        refreshDisplayLimits()
        // 平常不取樣時快照是舊的：按下開啟這一刻同步讀一次（只查鎖定狀態與目前亮度，很快）
        if ProcessInfo.processInfo.systemUptime - keySnapshot.sampledAt > 2.5 {
            keySnapshot = XDRSystemQuery.snapshot(display: screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
            cachedKeyAllowed = unavailableReason == nil
        }
        if let reason = unavailableReason { status = reason; return }
        let conflicts = ["fyi.lunar.Lunar", "com.niklasr22.BrightIntosh", "me.guillaumeb.CosmicNitor"]
        if captureRecent || Self.captureUIOnScreen() {
            status = "請先完成截圖／錄影，再啟用 XDR"
            return
        }
        if NSWorkspace.shared.runningApplications.contains(where: { conflicts.contains($0.bundleIdentifier ?? "") }) {
            status = "請先退出其他亮度／色彩增強工具"; return
        }
        let requestedGain = XDRBrightnessPolicy.clamp(initialGain, maximum: maximumGain)
        guard let screen,
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let surface = XDRSurface(screen: screen, gain: requestedGain) else {
            status = "無法建立 EDR 畫面"; return
        }
        displayID = id
        screenFrame = screen.frame
        self.surface = surface
        enabled = true
        preparing = true
        deadline = Date().addingTimeInterval(30 * 60)
        // 螢幕剛回來、還沒輪到重新判斷時也要有每秒檢查，30 分鐘上限與其他還原條件才會生效
        updateSafetyTimer()
        let token = UUID()
        generation = token
        surface.start()
        installCaptureMonitor()
        status = "正在啟動 EDR…"
        Task { [self] in
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(100))
                guard generation == token, enabled else { return }
                if screen.maximumExtendedDynamicRangeColorComponentValue > 1.01,
                   surface.completedFrames > 0, surface.visible {
                    preparing = false
                    setGain(requestedGain)
                    guard enabled else { return }
                    updateKeyMonitoring()
                    Self.log.notice("XDR activated, gain: \(self.gain, privacy: .public)")
                    return
                }
            }
            disable(reason: "系統未完成 EDR 呈現，已還原")
        }
    }

    func setGain(_ value: Double) {
        reconcileActiveState()
        guard enabled, !preparing, surface != nil else { return }
        let requested = XDRBrightnessPolicy.clamp(value, maximum: maximumGain)
        guard XDRBrightnessPolicy.needsOverlay(gain: requested) else {
            disable(reason: "一般亮度；到頂後可再按亮度增加鍵")
            return
        }
        surface?.setGain(requested)
        gain = requested
        keyGain = requested
        if let screen, let displayID {
            let nits = XDRLuminanceReader.estimatedNits(display: displayID, gain: requested,
                headroom: screen.maximumExtendedDynamicRangeColorComponentValue)
            hud.show(screen: screen, gain: requested, maximumGain: maximumGain, nits: nits)
        }
        status = requested > 1 ? "增亮設定 \(Int((requested * 100).rounded()))%（實際效果由系統限制）" : "一般亮度；到頂後可再按亮度增加鍵"
    }

    /// 會擋輸入的回呼只讀取記憶體快取；系統查詢、視窗與呈現都排到回呼結束後。
    private func handleKey(up: Bool) -> Bool {
        // 截圖／錄影時暫停過：過了空檔再按亮度鍵就解除；真的開啟前 enable() 還會確認截圖程式沒有在畫面上
        if capturePaused, !captureRecent { capturePaused = false }
        guard started, inputAvailable, !lifecycleSuspended, !capturePaused, !preparing else { return false }
        let allowed = cachedKeyAllowed && keySnapshot.allowed
        let snapshot = XDRKeySnapshot(nativeBrightness: keySnapshot.nativeBrightness,
                                      allowed: allowed, sampledAt: keySnapshot.sampledAt)
        let action = snapshot.action(up: up, gain: keyGain, active: enabled,
            automatic: automaticActivation, maximum: maximumGain, now: ProcessInfo.processInfo.systemUptime)
        switch action {
        case .system:
            // 系統套用原生亮度後，再到背景更新讀值，避免快取落後整整一秒。
            if nativeRefreshTask == nil {
                nativeRefreshTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(60))
                    guard let self, !Task.isCancelled else { return }
                    nativeRefreshTask = nil
                    guard started else { return }
                    hud.hide()
                    if let screen { hud.prepareAlignment(on: screen, afterNativeKey: true) }
                    requestSnapshot()
                }
            }
            return false
        case .activate(let value):
            let token = UUID()
            generation = token
            preparing = true
            keyTask = Task { [weak self] in
                guard let self, started, generation == token, !Task.isCancelled else { return }
                preparing = false
                guard automaticActivation, inputAvailable, !lifecycleSuspended, !capturePaused else { return }
                enable(initialGain: value)
            }
            return true
        case .adjust(let value):
            keyGain = value
            let token = generation
            keyTask?.cancel()
            keyTask = Task { [weak self] in
                guard let self, started, generation == token, !Task.isCancelled else { return }
                setGain(value)
            }
            return true
        }
    }

    /// 截圖程式有畫面上的視窗（選取框、錄影工具列、截完的縮圖）：正在截圖或錄影。
    /// 截完後只留在背景、沒有視窗的不算（它常會留好幾分鐘）
    private static func captureUIOnScreen() -> Bool {
        let pids = Set(NSWorkspace.shared.runningApplications.filter(isCaptureApplication).map(\.processIdentifier))
        guard !pids.isEmpty else { return false }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { pids.contains(($0[kCGWindowOwnerPID as String] as? pid_t) ?? -1) }
    }

    private static func isCaptureApplication(_ app: NSRunningApplication) -> Bool {
        let identifier = app.bundleIdentifier ?? ""
        return identifier == "com.apple.screencaptureui" || identifier == "com.apple.screenshot"
            || (app.executableURL?.path.lowercased().contains("screencaptureui") == true)
    }

    private func installCaptureMonitor() {
        guard captureMonitor == nil else { return }
        captureMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains([.command, .shift]), [UInt16(20), 21, 23, 22].contains(event.keyCode) else { return }
            Task { @MainActor in self?.pauseForCapture() }
        }
        localCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains([.command, .shift]), [UInt16(20), 21, 23, 22].contains(event.keyCode) {
                Task { @MainActor in self?.pauseForCapture() }
            }
            return event
        }
    }

    private func pauseForCapture() {
        captureStartedAt = ProcessInfo.processInfo.systemUptime
        guard enabled || preparing else { return }
        capturePaused = true
        disable(reason: "截圖／錄影時已還原亮度；完成後再按亮度鍵或重新啟用即可")
    }

    @discardableResult
    func disable(reason: String = "已還原一般亮度") -> Bool {
        generation = UUID()
        keyTask?.cancel(); keyTask = nil
        hud.hide()
        if let captureMonitor { NSEvent.removeMonitor(captureMonitor) }
        if let localCaptureMonitor { NSEvent.removeMonitor(localCaptureMonitor) }
        captureMonitor = nil
        localCaptureMonitor = nil
        surface?.stop(); surface = nil
        displayID = nil
        screenFrame = nil
        enabled = false
        preparing = false
        gain = 1
        keyGain = 1
        deadline = nil
        status = reason
        updateKeyMonitoring()
        return true
    }
}
