import AppKit
import CoreAudio
import Observation
import OSLog

/// 各 App 分開調音量（判斷與混音在 AppVolume）。
/// 用 macOS 14.2 起的程序音訊擷取（Core Audio process tap），不裝驅動程式：
/// 只有調低或靜音的 App 才擷取：先接上我們這一路（0 音量），收到聲音後才靜音它原本的聲音、改由我們乘上音量後從目前的輸出裝置播出；
/// 回到 100% 時先讓原本的聲音回來，我們這一路淡出後拆掉。
/// 做法參考 fader（MIT，https://github.com/pantafive/fader）的說明與流程，程式自己寫。
/// 讀寫 Core Audio 都是同步的程序間呼叫，全部放在 queue 上，不卡主執行緒
@MainActor
@Observable
final class AppVolumeController {
    static let shared = AppVolumeController()
    nonisolated static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "appVolume")

    struct PlayingApp: Equatable, Identifiable {
        var bundleID: String
        var name: String
        /// false：調整過但現在沒在播（例如暫停），留在清單上才能調回
        var isPlaying = true
        var id: String { bundleID }
    }

    /// 正在發出聲音、或調整過而且還開著的 App（面板打開時更新）
    private(set) var playing: [PlayingApp] = []
    private(set) var settings: [String: AppVolume.Setting] = [:]
    /// 建立擷取時被拒絕（沒有「系統錄音」權限），或還沒收到過任何聲音前連續三個 App 的擷取都只收到無聲資料：已經全部停掉，App 恢復原本的音量
    private(set) var problem = false
    /// 還沒確認權限，已經有一個 App 的擷取一直收不到聲音：先提示可能沒有權限（連續三次才停掉，見 problem）
    private(set) var mayLackPermission = false

    @ObservationIgnored private let engine = AppVolumeEngine()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var panelVisible = false
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored var onSettingsChange: (([String: AppVolume.Setting]) -> Void)?

    static var supported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    /// 打開或關掉功能；settings 是存起來的各 App 音量
    func apply(enabled: Bool, settings stored: [String: AppVolume.Setting]) {
        // 剛調的音量還在等 saveSoon 寫回時，存起來的是舊值：不要用它蓋掉控制器裡較新的設定
        if saveWork == nil { settings = stored }
        self.enabled = enabled && Self.supported
        guard self.enabled else {
            timer?.invalidate()
            timer = nil
            playing = []
            problem = false
            mayLackPermission = false
            engine.queue.async { [engine] in
                engine.removeAll()
                engine.resetProblem()
            }
            return
        }
        if wakeObserver == nil {
            // 喚醒後輸出裝置可能換了：馬上和一秒後各同步一次
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    AppVolumeController.shared.sync()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated { AppVolumeController.shared.sync() } }
                }
            }
            engine.queue.async { [engine] in engine.listenForDeviceChanges() }
        }
        sync()
        updateTimer()
    }

    /// 面板打開時列出正在播放的 App；關掉後只在有調整過的 App 時才繼續檢查
    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        if visible { sync() }
        updateTimer()
    }

    func setting(for bundleID: String) -> AppVolume.Setting { settings[bundleID] ?? AppVolume.Setting() }

    func setVolume(_ volume: Double, for bundleID: String) {
        var setting = self.setting(for: bundleID)
        setting.volume = AppVolume.clamp(volume)
        update(setting, for: bundleID)
    }

    func toggleMute(_ bundleID: String) {
        var setting = self.setting(for: bundleID)
        setting.muted.toggle()
        update(setting, for: bundleID)
    }

    /// 權限或無聲資料的問題處理後再試一次
    func retry() {
        problem = false
        engine.queue.async { [engine] in engine.resetProblem() }
        sync()
    }

    /// App 結束前拆掉所有擷取，被擷取的 App 立刻恢復原本的聲音
    /// 最多等 1 秒：Core Audio 卡住時不讓 App 卡在結束（本程序結束時系統會收回私有的擷取，被 kill 時聲音也會恢復，實測）
    func stopAll() {
        let done = DispatchSemaphore(value: 0)
        engine.queue.async { [engine] in
            engine.removeAll()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 1)
    }

    private func update(_ setting: AppVolume.Setting, for bundleID: String) {
        let wasTapped = settings[bundleID]?.needsTap ?? false
        if setting.needsTap { settings[bundleID] = setting } else { settings[bundleID] = nil }
        // 拖動滑桿時每一格都會進來：只改音量；要開始或停止擷取時才重新同步
        let gain = setting.gain
        engine.queue.async { [engine] in engine.setGain(gain, for: bundleID) }
        if wasTapped != setting.needsTap {
            sync()
            updateTimer()
        }
        saveSoon()
    }

    /// 拖動停下來 0.5 秒後才存
    private func saveSoon() {
        saveWork?.cancel()
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                let controller = AppVolumeController.shared
                controller.saveWork = nil
                controller.onSettingsChange?(controller.settings)
            }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func updateTimer() {
        let needed = enabled && (panelVisible || settings.values.contains(where: \.needsTap))
        if needed, timer == nil {
            // shortcut: 每 2 秒輪詢一次程序清單（Core Audio 的「正在輸出」通知在 macOS 26 起不會觸發）；有通知可靠的版本再改成事件驅動
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                MainActor.assumeIsolated { AppVolumeController.shared.sync() }
            }
            timer?.tolerance = 0.5
        } else if !needed {
            timer?.invalidate()
            timer = nil
        }
    }

    private func sync() {
        guard enabled else { return }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy != .prohibited }
        let names = Dictionary(apps.compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }, uniquingKeysWith: { first, _ in first })
        let pidOwners = Dictionary(apps.compactMap { app in app.bundleIdentifier.map { (app.processIdentifier, $0) } }, uniquingKeysWith: { first, _ in first })
        let regularApps = Set(apps.filter { $0.activationPolicy == .regular }.compactMap(\.bundleIdentifier))
        let targets = settings.filter { $0.value.needsTap }.mapValues(\.gain)
        engine.queue.async { [engine] in
            let result = engine.sync(targets: targets, pidOwners: pidOwners, appIDs: Set(names.keys), regularApps: regularApps)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let controller = AppVolumeController.shared
                    // 排隊中的結果晚到：功能已經關掉就不顯示
                    guard controller.enabled else { return }
                    let list = AppVolume.listed(playing: result.playing, adjusted: Set(targets.keys), running: Set(names.keys))
                        .map { PlayingApp(bundleID: $0.bundleID, name: names[$0.bundleID] ?? $0.bundleID, isPlaying: $0.isPlaying) }
                    if controller.playing != list { controller.playing = list }
                    if controller.problem != result.problem { controller.problem = result.problem }
                    if controller.mayLackPermission != result.mayLackPermission { controller.mayLackPermission = result.mayLackPermission }
                }
            }
        }
    }
}

/// 在自己的 queue 上管理每個 App 的擷取（只能在 queue 上呼叫）
final class AppVolumeEngine: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.kuan.batterymonitor.appVolume", qos: .userInitiated)
    private var taps: [String: AppTap] = [:]
    private var problem = false
    private var listening = false
    /// 收到過真正的聲音：權限沒問題，之後擷取到無聲只代表那個 App 正好沒聲音
    private var verified = false
    /// 還沒確認權限前，擷取一直無聲而先放掉的次數；連續幾次都這樣多半是沒有權限
    private var silentStrikes = 0
    /// 建立失敗（例如輸出格式不支援）或無聲而放掉的 App：程序或輸出裝置沒變之前不再試，免得每 2 秒被靜音一下
    private var skipped: [String: (objects: Set<AudioObjectID>, output: String, until: Date)] = [:]

    struct Result {
        var playing: Set<String>
        var problem: Bool
        var mayLackPermission = false
    }

    func resetProblem() {
        problem = false
        silentStrikes = 0
        skipped = [:]
    }

    func setGain(_ gain: Float, for bundleID: String) { taps[bundleID]?.setGain(gain) }

    func removeAll() {
        for tap in taps.values { tap.invalidate() }
        taps = [:]
    }

    /// 依目前的程序清單建立、重建或拆掉擷取，回傳正在發出聲音的 App
    func sync(targets: [String: Float], pidOwners: [pid_t: String], appIDs: Set<String>, regularApps: Set<String>) -> Result {
        let processes = AudioProcess.all()
        var objects: [String: Set<AudioObjectID>] = [:]
        var playing = Set<String>()
        for process in processes where process.pid != getpid() {
            guard let owner = AppVolume.resolveOwner(pidOwner: pidOwners[process.pid], processBundleID: process.bundleID,
                                                     apps: appIDs, regularApps: regularApps) else { continue }
            objects[owner, default: []].insert(process.objectID)
            if process.isRunningOutput { playing.insert(owner) }
        }
        // 不再需要、或 App 已經沒有程序的：拆掉，聲音回到原本的樣子
        for (bundleID, tap) in taps where targets[bundleID] == nil || objects[bundleID] == nil {
            taps[bundleID] = nil
            if objects[bundleID] == nil {
                tap.invalidate()
            } else {
                // 回到 100%：先讓 App 原本的聲音回來，我們這一路淡出後再拆，中間不會斷
                tap.release()
                queue.asyncAfter(deadline: .now() + 0.1) { tap.invalidate() }
            }
        }
        if taps.values.contains(where: \.heardSound) {
            verified = true
            silentStrikes = 0
        }
        // 還沒確認有權限：擷取一直收到無聲資料的先放掉（App 恢復原本的聲音），連續三次就當成沒有權限
        if !verified {
            for (bundleID, tap) in taps where tap.receivesOnlySilence {
                tap.invalidate()
                taps[bundleID] = nil
                skipped[bundleID] = (tap.processObjects, tap.outputUID, Date().addingTimeInterval(30))
                silentStrikes += 1
                AppVolumeController.log.error("擷取一直收到無聲資料，先放掉這個 App（第 \(self.silentStrikes, privacy: .public) 次）")
            }
            if silentStrikes >= 3 { problem = true }
        }
        if problem {
            removeAll()
            return Result(playing: playing, problem: true)
        }
        guard let output = AudioProcess.defaultOutputUID() else { return Result(playing: playing, problem: false) }
        for (bundleID, gain) in targets {
            guard let ids = objects[bundleID] else { continue }
            var old = taps[bundleID]
            if let old, old.processObjects == ids, old.outputUID == output, old.isAlive {
                old.setGain(gain)
                continue
            }
            // 上一個新的還在等聲音時又要重建：它還沒接手，App 是被更早那個靜音的，改成接手更早那個（不然它被拆掉時 App 會回到 100%）
            if let pending = old, !pending.armed, let earlier = pending.replacing {
                pending.replacing = nil
                taps[bundleID] = earlier
                pending.invalidate()
                old = earlier
            }
            if let skip = skipped[bundleID], skip.objects == ids, skip.output == output, skip.until > Date() { continue }
            skipped[bundleID] = nil
            // 程序清單（例如瀏覽器新開了 Helper）或輸出裝置變了：先建好新的再拆舊的，中間不會冒出原本音量的聲音
            let tap = AppTap(processObjects: ids, outputUID: output, gain: gain)
            switch tap.activate() {
            case .ok:
                taps[bundleID] = tap
                tap.replacing = old
                armWhenReady(tap, bundleID: bundleID, started: Date())
            case .permissionDenied:
                AppVolumeController.log.error("沒有系統錄音權限，停止各 App 音量")
                tap.invalidate()
                problem = true
                removeAll()
                return Result(playing: playing, problem: true)
            case .failed:
                tap.invalidate()
                // 舊的還能用才留著；它綁在別的輸出裝置或已失效時，App 會被靜音卻沒聲音，要拆掉讓聲音回到原本的樣子
                if let old, old.outputUID != output || !old.isAlive {
                    taps[bundleID] = nil
                    old.release()
                    queue.asyncAfter(deadline: .now() + 0.1) { old.invalidate() }
                }
                // 不再每 2 秒重試同一個組合
                skipped[bundleID] = (ids, output, .distantFuture)
            }
        }
        return Result(playing: playing, problem: false, mayLackPermission: !verified && silentStrikes > 0)
    }

    /// 新的擷取一開始不靜音 App、我們這一路是 0 音量：收到聲音（確定接上了）才靜音原本的聲音並接手，離開 100% 時不會斷一下。
    /// 重建時舊的擷取還在靜音 App：新的接手後才淡出舊的
    private func armWhenReady(_ tap: AppTap, bundleID: String, started: Date) {
        let old = tap.replacing
        guard taps[bundleID] === tap else {
            tap.replacing = nil
            if let old { retire(old) }
            return
        }
        let waited = Date().timeIntervalSince(started)
        // 只有舊的已經接手時 App 才是被靜音的；舊的還在等聲音時，App 其實是 100%
        switch AppVolume.armDecision(heardSound: tap.heardSound, oldArmed: old?.armed == true, waited: waited) {
        case .wait: break
        case let .arm(fromFullVolume):
            tap.replacing = nil
            if tap.arm(fromFullVolume: fromFullVolume) {
                if let old { retire(old) }
            } else {
                // 切換靜音失敗：不接手（否則會聽到兩路重疊、音量沒作用），舊的還能用就留著，這個組合不再重試
                AppVolumeController.log.error("無法靜音 App 原本的聲音，不調整這個 App")
                tap.invalidate()
                taps[bundleID] = old
                skipped[bundleID] = (tap.processObjects, tap.outputUID, .distantFuture)
            }
            return
        }
        queue.asyncAfter(deadline: .now() + (waited < 1 ? 0.02 : 0.1)) { [weak self] in
            self?.armWhenReady(tap, bundleID: bundleID, started: started)
        }
    }

    /// 新的擷取已經在播：舊的先轉成無聲，0.15 秒後拆掉，兩個重疊時不會變大聲
    private func retire(_ tap: AppTap) {
        tap.setGain(0)
        queue.asyncAfter(deadline: .now() + 0.15) { tap.invalidate() }
    }

    /// 預設輸出裝置換了：下一次同步依新的裝置重建；Core Audio 重新啟動：所有編號都失效，全部拆掉重來
    func listenForDeviceChanges() {
        guard !listening else { return }
        listening = true
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyServiceRestarted] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue) { [weak self] _, _ in
                if selector == kAudioHardwarePropertyServiceRestarted { self?.removeAll() }
                self?.skipped = [:]
                DispatchQueue.main.async { MainActor.assumeIsolated { AppVolumeController.shared.retryAfterDeviceChange() } }
            }
        }
    }
}

extension AppVolumeController {
    fileprivate func retryAfterDeviceChange() { sync() }
}

/// 一個 App 的擷取：擷取（接手後才靜音原本的聲音）→ 私有聚合裝置（擷取＋實際的輸出裝置）→ 音訊回呼
final class AppTap: @unchecked Sendable {
    enum Activation { case ok, permissionDenied, failed }

    let processObjects: Set<AudioObjectID>
    let outputUID: String
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(label: "com.kuan.batterymonitor.appVolume.io", qos: .userInteractive)
    private let started = Date()
    // 音訊執行緒只讀寫這幾個值：32 位元對齊的讀寫不會讀到一半
    private var targetGain: Float = 0
    private var currentGain: Float = 0
    private var ramp: Float = 1
    private(set) var heardSound = false
    /// 使用者設定的音量；接手（arm）前我們這一路維持 0，App 原本的聲音照常
    private var wanted: Float
    private(set) var armed = false
    /// 還沒接手前，正在靜音 App 的舊擷取；接手後淡出它（只在 AppVolumeEngine.queue 上讀寫）
    var replacing: AppTap?
    private var description: AnyObject?

    init(processObjects: Set<AudioObjectID>, outputUID: String, gain: Float) {
        self.processObjects = processObjects
        self.outputUID = outputUID
        wanted = gain
    }

    func setGain(_ gain: Float) {
        wanted = gain
        if armed { targetGain = gain }
    }

    /// 接手：靜音 App 原本的聲音，同一刻把我們這一路調到原本聽到的音量（第一次是 100%，重建時是目前的設定），再滑到設定值
    /// 回傳 false：靜音切換失敗，維持 0 音量、沒有接手
    func arm(fromFullVolume: Bool) -> Bool {
        guard !armed else { return true }
        currentGain = fromFullVolume ? 1 : wanted
        targetGain = wanted
        guard setMuted(true) else {
            currentGain = 0
            targetGain = 0
            return false
        }
        armed = true
        return true
    }

    /// 回到 100%：先讓 App 原本的聲音回來，我們這一路淡出（切換失敗也沒關係：0.1 秒後拆掉擷取，App 一樣會恢復）
    func release() {
        guard armed else { return }
        _ = setMuted(false)
        targetGain = 0
    }

    private func setMuted(_ muted: Bool) -> Bool {
        guard #available(macOS 14.2, *), let description = description as? CATapDescription, tapID != kAudioObjectUnknown else { return false }
        description.muteBehavior = muted ? .mutedWhenTapped : .unmuted
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyDescription, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var reference = Unmanaged.passUnretained(description).toOpaque()
        let status = withUnsafePointer(to: &reference) {
            AudioObjectSetPropertyData(tapID, &address, 0, nil, UInt32(MemoryLayout<UnsafeMutableRawPointer>.size), $0)
        }
        if status != noErr { AppVolumeController.log.error("無法切換擷取的靜音：\(status, privacy: .public)") }
        return status == noErr
    }

    /// 開始超過 5 秒，App 說它正在輸出，卻從來沒收到任何聲音
    var receivesOnlySilence: Bool { !heardSound && Date().timeIntervalSince(started) > 5 && AudioProcess.anyRunningOutput(processObjects) }

    var isAlive: Bool {
        guard aggregateID != kAudioObjectUnknown else { return false }
        return AudioProcess.read(aggregateID, kAudioDevicePropertyDeviceIsAlive, default: UInt32(0)) != 0
    }

    func activate() -> Activation {
        guard #available(macOS 14.2, *) else { return .failed }
        let description = CATapDescription(stereoMixdownOfProcesses: Array(processObjects))
        description.uuid = UUID()
        // 先不靜音 App：我們這一路接上、收到聲音後才靜音（arm），離開 100% 時不會斷一下
        description.muteBehavior = .unmuted
        description.isPrivate = true
        self.description = description
        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        if status == kAudioDevicePermissionsError { return .permissionDenied }
        guard status == noErr else {
            AppVolumeController.log.error("無法建立擷取：\(status, privacy: .public)")
            return .failed
        }
        tapID = tap
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "App 音量",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceClockDeviceKey: outputUID,
            // 私有：只有本程序看得到，不會出現在系統的聲音設定裡，本程序結束就消失
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        if status == kAudioDevicePermissionsError { return .permissionDenied }
        guard status == noErr else {
            AppVolumeController.log.error("無法建立聚合裝置：\(status, privacy: .public)")
            return .failed
        }
        aggregateID = device
        // 只處理 Float32：其他格式不擷取，免得 App 被靜音卻沒有聲音出來
        guard let rate = AudioProcess.float32SampleRate(device) else {
            AppVolumeController.log.error("輸出格式不是 Float32，不調整這個 App")
            return .failed
        }
        ramp = AppVolume.rampCoefficient(sampleRate: rate)
        var proc: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&proc, device, ioQueue) { @Sendable [unowned(unsafe) self] _, input, _, output, _ in
            self.render(input, output)
        }
        guard status == noErr, let proc else { return .failed }
        procID = proc
        guard AudioDeviceStart(device, proc) == noErr else { return .failed }
        AppVolumeController.log.notice("開始調整 \(self.processObjects.count) 個程序的音量")
        return .ok
    }

    /// 依序拆掉：停止 → 回呼 → 聚合裝置 → 擷取；拆掉擷取後 App 恢復原本的聲音
    func invalidate() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
                // 已經排進 ioQueue 的回呼跑完才放掉這個物件
                ioQueue.sync {}
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown, #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit { invalidate() }

    // 音訊執行緒：不配置記憶體、不上鎖、不寫記錄。
    // 聚合裝置的輸入是「輸出裝置自己的輸入（例如耳機麥克風）＋擷取」，擷取排在最後：只用最後一個輸入，不會把麥克風播出來
    private func render(_ input: UnsafePointer<AudioBufferList>, _ output: UnsafeMutablePointer<AudioBufferList>) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let source: AudioBuffer? = inputs.count > 0 ? inputs[inputs.count - 1] : nil
        let start = currentGain
        var gain = start
        for buffer in UnsafeMutableAudioBufferListPointer(output) {
            guard let out = buffer.mData else { continue }
            guard let source, let data = source.mData else {
                memset(out, 0, Int(buffer.mDataByteSize))
                continue
            }
            let result = AppVolume.mix(input: data.assumingMemoryBound(to: Float.self), inputChannels: Int(source.mNumberChannels),
                                       inputSamples: Int(source.mDataByteSize) / MemoryLayout<Float>.size,
                                       output: out.assumingMemoryBound(to: Float.self), outputChannels: Int(buffer.mNumberChannels),
                                       outputSamples: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size,
                                       gain: start, target: targetGain, ramp: ramp)
            gain = result.gain
            if result.peak > 0 { heardSound = true }
        }
        currentGain = gain
    }
}

/// Core Audio 裡的程序與裝置（只能在 AppVolumeEngine.queue 上呼叫）
enum AudioProcess {
    struct Info {
        var objectID: AudioObjectID
        var pid: pid_t
        var bundleID: String
        var isRunningOutput: Bool
    }

    static func all() -> [Info] {
        guard #available(macOS 14.2, *) else { return [] }
        let ids: [AudioObjectID] = readArray(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
        return ids.map { id in
            Info(objectID: id, pid: read(id, kAudioProcessPropertyPID, default: pid_t(-1)),
                 bundleID: readString(id, kAudioProcessPropertyBundleID) ?? "",
                 isRunningOutput: read(id, kAudioProcessPropertyIsRunningOutput, default: UInt32(0)) != 0)
        }
    }

    static func anyRunningOutput(_ ids: Set<AudioObjectID>) -> Bool {
        guard #available(macOS 14.2, *) else { return false }
        return ids.contains { read($0, kAudioProcessPropertyIsRunningOutput, default: UInt32(0)) != 0 }
    }

    static func defaultOutputUID() -> String? {
        let device: AudioObjectID = read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID(kAudioObjectUnknown))
        guard device != kAudioObjectUnknown else { return nil }
        return readString(device, kAudioDevicePropertyDeviceUID)
    }

    /// 聚合裝置的輸出格式是 Float32 時回傳取樣率
    static func float32SampleRate(_ device: AudioObjectID) -> Double? {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamFormat, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &format) == noErr,
              format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32, format.mSampleRate > 0 else { return nil }
        return format.mSampleRate
    }

    static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, default value: T) -> T {
        var result = value
        var size = UInt32(MemoryLayout<T>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = withUnsafeMutablePointer(to: &result) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        return status == noErr ? result : value
    }

    static func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func readArray(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }
}
