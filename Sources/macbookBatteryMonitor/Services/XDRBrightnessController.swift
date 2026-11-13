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
    private(set) var automaticActivation = true
    private static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "XDR")
    private static let automaticActivationKey = "xdrAutomaticActivation"
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

    var screen: NSScreen? {
        NSScreen.screens.first {
            guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) != 0 && $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 1
        }
    }
    var supported: Bool { screen != nil && maximumGain > 1 }
    var renderingHealthy: Bool { surface?.visible == true && (surface?.completedFrames ?? 0) > 0 }
    var renderingStatus: String {
        "visible=\(surface?.visible ?? false), submitted=\(surface?.renderedFrames ?? 0), completed=\(surface?.completedFrames ?? 0), HUD \(hud.geometryStatus)"
    }
    var keysStatus: String { keys?.status ?? "亮度鍵自動啟用已關閉" }

    func start() {
        guard !started, Bundle.main.bundleIdentifier == "com.kuan.batterymonitor",
              !CommandLine.arguments.contains(where: { $0.hasPrefix("--snapshot") || $0.hasPrefix("--screenshots") }) else { return }
        started = true
        automaticActivation = UserDefaults.standard.object(forKey: Self.automaticActivationKey) as? Bool ?? true
        refreshDisplayLimits()
        updateKeyMonitoring()
        if let screen { hud.prepareAlignment(on: screen) }
        Self.log.notice("Automatic XDR: \(self.automaticActivation, privacy: .public), keys: \(self.keysStatus, privacy: .public)")
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            _ = MainActor.assumeIsolated { self?.disable(reason: "螢幕已鎖定，已還原亮度") }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                _ = MainActor.assumeIsolated { self?.disable(reason: "睡眠或鎖定，已還原亮度") }
            })
        }
    }

    func setAutomaticActivation(_ allowed: Bool) {
        automaticActivation = allowed
        UserDefaults.standard.set(allowed, forKey: Self.automaticActivationKey)
        updateKeyMonitoring()
    }

    func setInputAvailable(_ available: Bool) {
        inputAvailable = available
        updateKeyMonitoring()
    }

    private func updateKeyMonitoring() {
        guard inputAvailable, started, supported, automaticActivation || enabled else {
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
            return
        }
        let potential = Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
        maximumGain = XDRLuminanceReader.maximumGain(display: id, potentialHeadroom: potential)
        targetNits = XDRLuminanceReader.targetNits(display: id, potentialHeadroom: potential)
        if enabled && gain > maximumGain { setGain(maximumGain) }
    }

    func reconcile() {
        refreshDisplayLimits()
        updateKeyMonitoring()
        reconcileActiveState()
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
        }
    }

    private var unavailableReason: String? {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = session == nil || session?["CGSSessionScreenIsLocked"] as? Bool == true
        return XDRBrightnessPolicy.blockReason(supported: supported,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled || AppSettings.shared.powerSavingActive,
            hot: [.serious, .critical].contains(ProcessInfo.processInfo.thermalState), locked: locked)
    }

    func enable(initialGain: Double = 1.15) {
        guard !enabled, !preparing else { return }
        guard Bundle.main.bundleIdentifier == "com.kuan.batterymonitor",
              !CommandLine.arguments.contains(where: { $0.hasPrefix("--snapshot") || $0.hasPrefix("--screenshots") }) else {
            status = "僅在正式打包 App 中開啟"; return
        }
        refreshDisplayLimits()
        if let reason = unavailableReason { status = reason; return }
        let conflicts = ["fyi.lunar.Lunar", "com.niklasr22.BrightIntosh", "me.guillaumeb.CosmicNitor"]
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
        let token = UUID()
        generation = token
        surface.start()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
        safetyTimer = timer
        RunLoop.main.add(timer, forMode: .common)
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
        surface?.setGain(requested)
        gain = requested
        if let screen, let displayID {
            let nits = XDRLuminanceReader.estimatedNits(display: displayID, gain: requested,
                headroom: screen.maximumExtendedDynamicRangeColorComponentValue)
            hud.show(screen: screen, gain: requested, maximumGain: maximumGain, nits: nits)
        }
        status = requested > 1 ? "增亮設定 \(Int((requested * 100).rounded()))%（實際效果由系統限制）" : "一般亮度；到頂後可再按亮度增加鍵"
    }

    private func handleKey(up: Bool) -> Bool {
        guard !preparing else { return false }
        reconcileActiveState()
        let id = displayID ?? screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        let action = XDRBrightnessPolicy.keyAction(up: up, gain: gain, active: enabled,
            automatic: automaticActivation, nativeBrightness: XDRBrightnessKeys.nativeBrightness(id), maximum: maximumGain)
        switch action {
        case .system:
            hud.hide()
            if let screen { hud.prepareAlignment(on: screen, afterNativeKey: true) }
            return false
        case .activate(let value):
            if let reason = unavailableReason { status = reason; return false }
            let token = UUID()
            generation = token
            preparing = true
            status = "正在準備 XDR…"
            Task { [weak self] in
                guard let self, generation == token else { return }
                preparing = false
                guard automaticActivation else { status = "已取消自動增亮"; return }
                enable(initialGain: value)
            }
            return true
        case .adjust(let value):
            setGain(value)
            return true
        }
    }

    @discardableResult
    func disable(reason: String = "已還原一般亮度") -> Bool {
        generation = UUID()
        hud.hide()
        safetyTimer?.invalidate(); safetyTimer = nil
        surface?.stop(); surface = nil
        displayID = nil
        screenFrame = nil
        enabled = false
        preparing = false
        gain = 1
        deadline = nil
        status = reason
        updateKeyMonitoring()
        return true
    }
}
