import Foundation
import Observation
import AppKit

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case iconAndPercent
    case iconOnly
    case percentOnly
    case iconAndTime
    case iconPercentAndTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iconAndPercent: return "圖示 + 百分比"
        case .iconOnly: return "只有圖示"
        case .percentOnly: return "只有百分比"
        case .iconAndTime: return "圖示 + 剩餘時間"
        case .iconPercentAndTime: return "圖示內百分比 + 剩餘時間"
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var chargingIconText: String {
        didSet { defaults.set(chargingIconText, forKey: "chargingIconText"); onChange?() }
    }
    var chargingIconNativeColor: Bool {
        didSet { defaults.set(chargingIconNativeColor, forKey: "chargingIconNativeColor"); onChange?() }
    }
    var chargingIconColorData: Data? {
        didSet { defaults.set(chargingIconColorData, forKey: "chargingIconColorData"); onChange?() }
    }
    var chargingIconFlow: Bool {
        didSet { defaults.set(chargingIconFlow, forKey: "chargingIconFlow"); onChange?() }
    }
    var chargingIconPreset: String {
        didSet { defaults.set(chargingIconPreset, forKey: "chargingIconPreset"); onChange?() }
    }
    var chargingIconOpacity: Double {
        didSet { defaults.set(chargingIconOpacity, forKey: "chargingIconOpacity"); onChange?() }
    }
    var chargingIconBaseColor: NSColor {
        switch chargingIconPreset {
        case "mint": return NSColor(srgbRed: 0.25, green: 0.85, blue: 0.65, alpha: 1)
        case "emerald": return NSColor(srgbRed: 0.12, green: 0.68, blue: 0.38, alpha: 1)
        case "lime": return NSColor(srgbRed: 0.55, green: 0.85, blue: 0.20, alpha: 1)
        case "custom": break
        default: return .systemGreen
        }
        guard let data = chargingIconColorData,
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) else {
            return .systemGreen
        }
        return color
    }
    var chargingIconColor: NSColor {
        chargingIconBaseColor.withAlphaComponent(chargingIconOpacity.isFinite
            ? min(1, max(0, chargingIconOpacity)) : 1)
    }
    var chargingIconTextColor: NSColor {
        switch chargingIconText {
        case "black": return .black
        case "automatic": return .labelColor
        default: return .white
        }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    /// 影響選單列圖示的設定改變時呼叫
    @ObservationIgnored var onChange: (() -> Void)?
    /// 系統監控模組開關改變時呼叫
    @ObservationIgnored var onMonitorsChange: (() -> Void)?
    /// 更新頻率或省電模式改變時呼叫（重設所有取樣間隔）
    @ObservationIgnored var onIntervalChange: (() -> Void)?
    /// 智慧充電的精準喚醒開關改變時呼叫
    @ObservationIgnored var onChargingWakeChange: (() -> Void)?
    /// 桌面寵物開關改變時
    /// 捲動方向的設定改變時
    @ObservationIgnored var onScrollDirectionChange: (() -> Void)?
    /// 視窗切換的開關改變時
    @ObservationIgnored var onWindowSwitcherChange: (() -> Void)?
    /// 中文輸入法的 Caps Lock 延遲或 Shift 半形開關改變時
    @ObservationIgnored var onInputSourceFixChange: (() -> Void)?
    @ObservationIgnored var onDesktopPetChange: (() -> Void)?
    /// 加入或移除擴充功能時（參數是改變的功能）
    @ObservationIgnored var onFeatureInstallChange: ((ExtensionFeature) -> Void)?

    /// 亮度鍵自動啟用設定改變時，重新同步 XDR 監聽狀態
    @ObservationIgnored var onXDRBrightnessChange: (() -> Void)?

    /// 保留實驗版的儲存鍵，加入 XDR 功能前不會因此啟動
    var xdrAutomaticActivation: Bool {
        didSet { defaults.set(xdrAutomaticActivation, forKey: Keys.xdrAutomaticActivation); onXDRBrightnessChange?() }
    }

    /// 已加入的擴充功能；沒加入的不啟動，設定裡也看不到
    private(set) var installedFeatures: Set<ExtensionFeature> = []

    func isInstalled(_ feature: ExtensionFeature) -> Bool { installedFeatures.contains(feature) }

    /// 可以匯出、帶到另一台 Mac 的設定。不含要另外安裝系統服務的（管理員 CPU 取樣、精準喚醒）、一次性的轉換標記，
    /// 也不含周邊設備的低電量門檻（以藍牙裝置的硬體位址為鍵，匯出檔可能被分享）
    static let backupSchema: [String: SettingsBackup.Kind] = {
        var schema: [String: SettingsBackup.Kind] = [
            Keys.xdrAutomaticActivation: .bool,
            Keys.display: .string, Keys.lowAlertEnabled: .bool, Keys.lowThreshold: .int, Keys.fullAlertEnabled: .bool,
            Keys.fullThreshold: .int, Keys.monitorCPU: .bool, Keys.monitorMemory: .bool, Keys.monitorDisk: .bool,
            Keys.monitorNetwork: .bool, Keys.mergeMemoryDisk: .bool, Keys.networkSpeedTest: .bool, Keys.systemMonitors: .bool,
            Keys.alertCPU: .bool, Keys.alertMemory: .bool, Keys.alertDisk: .bool, Keys.menuBarCombined: .bool,
            Keys.powerSaving: .bool, Keys.powerSavingOnBatteryOnly: .bool, Keys.bluetoothOffDuringSleep: .bool, Keys.keepAwakeApps: .strings, Keys.quitGuardQuit: .bool, Keys.quitGuardClose: .bool, Keys.quitGuardDuration: .double, Keys.lastWindowQuitExcluded: .strings, Keys.dockClickMode: .string, Keys.keyboardCleaningSeconds: .int, Keys.mouseBackButton: .string, Keys.mouseForwardButton: .string, Keys.updateInterval: .int,
            Keys.hiddenFlowItems: .strings, Keys.hiddenDetailFields: .strings,
            Keys.appIconColor: .string, Keys.autoCheckUpdates: .bool, Keys.updateNotification: .bool,
            Keys.chargingAppearance: .string, Keys.desktopPet: .bool, Keys.desktopPetOnWallpaper: .bool,
            Keys.desktopPetScale: .double, Keys.desktopPetLiveEyes: .bool, Keys.desktopPetFollowCursor: .bool,
            Keys.scrollReverseMouse: .bool, Keys.scrollReverseTrackpad: .bool, Keys.scrollReverseHorizontal: .bool, Keys.scrollLinearLines: .int, Keys.scrollHorizontalKey: .string, Keys.scrollSmooth: .bool, Keys.windowSwitcher: .bool,
            Keys.switcher: .dictionary, Keys.capsLockNoDelay: .bool, Keys.shiftHalfWidth: .bool,
            Keys.chargingTargetPercent: .int, Keys.chargingHoldPercent: .int, Keys.chargingSleepStrategy: .string,
        ]
        for feature in ExtensionFeature.allCases { schema[feature.installedKey] = .bool }
        return schema
    }()

    func exportBackup() throws -> Data {
        var values: [String: Any] = [:]
        for key in Self.backupSchema.keys { values[key] = defaults.object(forKey: key) }
        // 加入狀態用實際的值：從舊版更新、沒存過的也要帶過去，否則在全新安裝的 Mac 匯入後功能會變成沒加入
        values.merge(ExtensionFeature.installedValues(isInstalled)) { _, actual in actual }
        values[Keys.xdrAutomaticActivation] = xdrAutomaticActivation
        return try SettingsBackup.export(values, schema: Self.backupSchema)
    }

    /// 讀取並檢查設定檔，還不寫入。turnsOn：匯入後會從關閉變成打開的項目（擴充功能、睡眠時關閉藍牙、指定 App 防止休眠），
    /// 要先讓使用者確認：其中有需要「輔助使用」或會記錄剪貼簿的功能
    func readBackup(_ data: Data) throws -> (values: [String: Any], turnsOn: [String]) {
        var values = try SettingsBackup.read(data, schema: Self.backupSchema)
        // 舊版匯出的備份只有 networkSpeedTest：轉成測速擴充功能的加入狀態，不讓舊備份的測速設定被丟掉
        if let legacy = values.removeValue(forKey: Keys.networkSpeedTest) as? Bool, values[ExtensionFeature.speedTest.installedKey] == nil {
            values[ExtensionFeature.speedTest.installedKey] = legacy
        }
        var turnsOn = ExtensionFeature.allCases.filter { values[$0.installedKey] as? Bool == true && !isInstalled($0) }.map(\.title)
        // 功能自己的開關：加入了但開關關著時，匯入一樣會讓它開始攔截按鍵或滑鼠
        let switches: [(String, String)] = [
            (Keys.bluetoothOffDuringSleep, "睡眠時關閉藍牙"), (Keys.windowSwitcher, "視窗切換"),
            (Keys.xdrAutomaticActivation, "XDR 亮度鍵自動啟用"),
            (Keys.capsLockNoDelay, "Caps Lock 切換中英不延遲"), (Keys.shiftHalfWidth, "按住 Shift 打半形"),
            (Keys.quitGuardQuit, "⌘Q 防誤觸"), (Keys.quitGuardClose, "⌘W 防誤觸"),
            (Keys.scrollReverseMouse, "滑鼠滾輪反向"), (Keys.scrollReverseTrackpad, "觸控板反向"), (Keys.scrollSmooth, "滑鼠滾輪平滑捲動"),
        ]
        for (key, title) in switches where values[key] as? Bool == true && !defaults.bool(forKey: key) {
            turnsOn.append(title)
        }
        if let apps = values[Keys.keepAwakeApps] as? [String], !apps.isEmpty, apps != (defaults.stringArray(forKey: Keys.keepAwakeApps) ?? []) {
            turnsOn.append("指定 App 執行時防止休眠（\(apps.count) 個 App）")
        }
        // 不是開關的設定：從「不處理／關閉」變成有作用，一樣會開始攔截滑鼠。用和讀設定時同樣的解讀，無效的值算關閉。
        // 只有所屬的擴充功能匯入後是加入的才會作用
        let options: [(ExtensionFeature, String, String, (Any?) -> Bool)] = [
            (.mouseButtons, Keys.mouseBackButton, "滑鼠第 4 鍵", { MouseButtons.Action(stored: $0 as? String) != .none }),
            (.mouseButtons, Keys.mouseForwardButton, "滑鼠第 5 鍵", { MouseButtons.Action(stored: $0 as? String) != .none }),
            (.scrollDirection, Keys.scrollLinearLines, "滑鼠滾輪固定捲動行數", { ScrollLinear.valid($0 as? Int ?? 0) != 0 }),
            (.scrollDirection, Keys.scrollHorizontalKey, "按住修飾鍵左右捲動", { ScrollHorizontalKey(stored: $0 as? String) != .off }),
        ]
        for (feature, key, title, isOn) in options
        where values[feature.installedKey] as? Bool ?? isInstalled(feature)
            && values[key] != nil && isOn(values[key]) && !isOn(defaults.object(forKey: key)) {
            turnsOn.append(title)
        }
        return (values, turnsOn)
    }

    /// 寫入 readBackup 檢查過的設定，回傳寫入幾項；檔案裡沒有的設定維持原樣。重新開啟 App 後全部生效
    func importBackup(_ values: [String: Any]) -> Int {
        for (key, value) in values {
            // 視窗切換的設定先整理成認得的欄位再存，不把檔案裡的原始內容整包存進去
            let clean = key == Keys.switcher ? (value as? [String: Any]).map { SwitcherSettings(stored: $0).stored } ?? value : value
            defaults.set(clean, forKey: key)
        }
        return values.count
    }

    func setInstalled(_ feature: ExtensionFeature, _ installed: Bool) {
        guard isInstalled(feature) != installed else { return }
        if installed { installedFeatures.insert(feature) } else { installedFeatures.remove(feature) }
        // 只改加入狀態，功能自己的設定都不動，重新加入時照舊
        defaults.set(installed, forKey: feature.installedKey)
        onFeatureInstallChange?(feature)
    }

    /// 可選的更新頻率（秒）
    static let updateIntervals = [1, 2, 5, 10]

    /// 更新頻率（秒），預設每秒
    var updateInterval: Int {
        didSet { defaults.set(updateInterval, forKey: Keys.updateInterval); onIntervalChange?() }
    }

    /// 省電模式：電力流向改用靜態圖示、不播放動畫，更新頻率至少每 2 秒
    var powerSaving: Bool {
        didSet { defaults.set(powerSaving, forKey: Keys.powerSaving); onIntervalChange?() }
    }

    /// 只在使用電池時套用省電模式，接上電源就恢復一般模式
    var powerSavingOnBatteryOnly: Bool {
        didSet { defaults.set(powerSavingOnBatteryOnly, forKey: Keys.powerSavingOnBatteryOnly); onIntervalChange?() }
    }

    /// ⌘Q／⌘W 防誤觸：要按住幾秒、各自開不開（見 QuitGuard）
    var quitGuardQuit: Bool {
        didSet { defaults.set(quitGuardQuit, forKey: Keys.quitGuardQuit); onQuitGuardChange?() }
    }
    var quitGuardClose: Bool {
        didSet { defaults.set(quitGuardClose, forKey: Keys.quitGuardClose); onQuitGuardChange?() }
    }
    var quitGuardDuration: Double {
        didSet { defaults.set(quitGuardDuration, forKey: Keys.quitGuardDuration); onQuitGuardChange?() }
    }
    static let quitGuardDurations: [Double] = [0.5, 1, 1.5]
    @ObservationIgnored var onQuitGuardChange: (() -> Void)?

    /// 關閉最後視窗時不結束的 App（識別碼；Finder 一律不結束，不用列）
    var lastWindowQuitExcluded: Set<String> {
        didSet {
            defaults.set(lastWindowQuitExcluded.sorted(), forKey: Keys.lastWindowQuitExcluded)
            onLastWindowQuitChange?()
        }
    }
    @ObservationIgnored var onLastWindowQuitChange: (() -> Void)?

    /// 滑鼠第 4、5 鍵的動作
    var mouseBackButton: MouseButtons.Action {
        didSet { defaults.set(mouseBackButton.rawValue, forKey: Keys.mouseBackButton); onMouseButtonsChange?() }
    }
    var mouseForwardButton: MouseButtons.Action {
        didSet { defaults.set(mouseForwardButton.rawValue, forKey: Keys.mouseForwardButton); onMouseButtonsChange?() }
    }
    @ObservationIgnored var onMouseButtonsChange: (() -> Void)?

    /// 鍵盤清潔模式的時間（秒）
    var keyboardCleaningSeconds: Int {
        didSet { defaults.set(keyboardCleaningSeconds, forKey: Keys.keyboardCleaningSeconds) }
    }

    /// 點 Dock 圖示時縮到 Dock 還是隱藏 App
    var dockClickMode: DockClick.Mode {
        didSet { defaults.set(dockClickMode.rawValue, forKey: Keys.dockClickMode); onLastWindowQuitChange?() }
    }

    /// 這些 App 執行中時自動防止休眠（識別碼）
    var keepAwakeApps: Set<String> {
        didSet {
            defaults.set(keepAwakeApps.sorted(), forKey: Keys.keepAwakeApps)
            onKeepAwakeAppsChange?()
        }
    }
    @ObservationIgnored var onKeepAwakeAppsChange: (() -> Void)?

    /// 睡眠時關閉藍牙、醒來打開（見 BluetoothSleep）
    var bluetoothOffDuringSleep: Bool {
        didSet { defaults.set(bluetoothOffDuringSleep, forKey: Keys.bluetoothOffDuringSleep) }
    }

    /// 這次睡眠的藍牙是我們關掉的（不匯出；睡眠中 App 被結束時，下次啟動靠它打開）
    var bluetoothTurnedOffForSleep: Bool {
        get { defaults.bool(forKey: Keys.bluetoothTurnedOffForSleep) }
        set { defaults.set(newValue, forKey: Keys.bluetoothTurnedOffForSleep) }
    }

    /// 目前是否接著電源（不存檔，由 AppDelegate 每次更新時帶入；桌上型 Mac 一律視為接著電源）
    var onACPower = false {
        didSet { if onACPower != oldValue, powerSaving, powerSavingOnBatteryOnly { onIntervalChange?() } }
    }

    /// 省電模式現在是否生效：開關打開，且（沒有限定電池，或目前用電池）
    var powerSavingActive: Bool { powerSaving && !(powerSavingOnBatteryOnly && onACPower) }

    /// 電池、系統監控、耗電排行共用的取樣間隔（秒）
    var sampleInterval: TimeInterval { TimeInterval(powerSavingActive ? max(2, updateInterval) : updateInterval) }

    /// 介面上顯示的更新頻率
    var updateText: String { Self.updateText(seconds: Int(sampleInterval)) }

    static func updateText(seconds: Int) -> String { seconds <= 1 ? "每秒更新" : "每 \(seconds) 秒更新" }

    /// 每個系統監控模組是否在選單列顯示（並依取樣間隔更新）
    var monitorCPU: Bool {
        didSet { defaults.set(monitorCPU, forKey: Keys.monitorCPU); onMonitorsChange?() }
    }
    var monitorMemory: Bool {
        didSet { defaults.set(monitorMemory, forKey: Keys.monitorMemory); onMonitorsChange?() }
    }
    var monitorDisk: Bool {
        didSet { defaults.set(monitorDisk, forKey: Keys.monitorDisk); onMonitorsChange?() }
    }
    var monitorNetwork: Bool {
        didSet { defaults.set(monitorNetwork, forKey: Keys.monitorNetwork); onMonitorsChange?() }
    }
    /// 記憶體與磁碟合併成一個選單列圖示（像 CPU／GPU 一樣兩行），面板也合在一起
    var mergeMemoryDisk: Bool {
        didSet { defaults.set(mergeMemoryDisk, forKey: Keys.mergeMemoryDisk); onMonitorsChange?() }
    }
    /// 合併現在是否生效：開關打開，且記憶體與磁碟都有開
    var memoryDiskMerged: Bool {
        MonitorKind.mergesMemoryDisk(merge: mergeMemoryDisk, memory: isMonitorEnabled(.memory), disk: isMonitorEnabled(.disk))
    }

    /// 系統監控總開關：關閉時選單列只有電池（桌上型為耗電）圖示，四個模組都不取樣，和以前的電池版一樣省電
    var systemMonitors: Bool {
        didSet { defaults.set(systemMonitors, forKey: Keys.systemMonitors); onMonitorsChange?() }
    }
    /// 合併顯示：選單列只留電池（桌上型為耗電）一個圖示，點一下在下方展開第二條狀態列，列出所有圖示。
    /// 選單列圖示太多時，macOS 會把放不下的藏起來（尤其有瀏海的 MacBook）
    var menuBarCombined: Bool {
        didSet { defaults.set(menuBarCombined, forKey: Keys.menuBarCombined); onMonitorsChange?() }
    }
    /// 監控警示（預設關閉）：只在該模組有取樣時（選單列有它的圖示）才會判斷
    var alertCPU: Bool {
        didSet { defaults.set(alertCPU, forKey: Keys.alertCPU) }
    }
    var alertMemory: Bool {
        didSet { defaults.set(alertMemory, forKey: Keys.alertMemory) }
    }
    var alertDisk: Bool {
        didSet { defaults.set(alertDisk, forKey: Keys.alertDisk) }
    }
    /// 全新安裝、還沒選過要不要開系統監控（第一次啟動時詢問）
    private(set) var needsModeChoice = false

    func chooseMode(systemMonitors: Bool) {
        needsModeChoice = false
        self.systemMonitors = systemMonitors
    }

    func isMonitorEnabled(_ kind: MonitorKind) -> Bool {
        guard systemMonitors else { return false }
        switch kind {
        case .cpu: return monitorCPU
        case .memory: return monitorMemory
        case .disk: return monitorDisk
        case .network: return monitorNetwork
        }
    }

    /// 選用的管理員 CPU 取樣（預設關閉）。開啟時安裝系統服務，關閉時移除；由 AdminCPUSampler 在下一次更新時套用
    var adminCPUSampling: Bool {
        didSet { defaults.set(adminCPUSampling, forKey: Keys.adminCPUSampling) }
    }

    /// 智慧充電：主面板那一列左邊顯示充電夥伴（貓咪）或電量條
    var chargingAppearance: ChargingAppearance {
        didSet { defaults.set(chargingAppearance.rawValue, forKey: Keys.chargingAppearance) }
    }
    /// 換「我的照片」時加一，讓用到照片的畫面重畫（照片本身在 CompanionPhoto）
    var companionPhotoVersion = 0
    /// 桌面寵物：把充電夥伴放在桌面上（只有 MacBook 有）
    var desktopPet: Bool {
        didSet {
            defaults.set(desktopPet, forKey: Keys.desktopPet)
            if desktopPet != oldValue { onDesktopPetChange?() }
        }
    }
    /// 桌面寵物放在桌布上（會被視窗蓋住）；關閉時浮在所有視窗上方
    var desktopPetOnWallpaper: Bool {
        didSet {
            defaults.set(desktopPetOnWallpaper, forKey: Keys.desktopPetOnWallpaper)
            if desktopPetOnWallpaper != oldValue { onDesktopPetChange?() }
        }
    }
    /// 桌面寵物貓咪大頭照的眼睛會動：眨眼、睡覺時閉眼
    var desktopPetLiveEyes: Bool {
        didSet { defaults.set(desktopPetLiveEyes, forKey: Keys.desktopPetLiveEyes) }
    }
    /// 眼睛跟著游標：關掉就完全不監聽滑鼠移動
    var desktopPetFollowCursor: Bool {
        didSet { defaults.set(desktopPetFollowCursor, forKey: Keys.desktopPetFollowCursor) }
    }
    /// 捲動方向：滑鼠與觸控板各自反向（macOS 的「自然捲動」兩者共用一個設定）
    var scrollReverseMouse: Bool {
        didSet {
            defaults.set(scrollReverseMouse, forKey: Keys.scrollReverseMouse)
            if scrollReverseMouse != oldValue { onScrollDirectionChange?() }
        }
    }
    /// 左右捲動也反向（預設打開，和以前一樣上下左右一起反）；關掉時只反轉上下
    var scrollReverseHorizontal: Bool {
        didSet {
            defaults.set(scrollReverseHorizontal, forKey: Keys.scrollReverseHorizontal)
            if scrollReverseHorizontal != oldValue { onScrollDirectionChange?() }
        }
    }
    /// 線性捲動：一般滾輪每格固定捲幾行，0 是關閉（見 ScrollLinear）
    var scrollLinearLines: Int {
        didSet {
            defaults.set(scrollLinearLines, forKey: Keys.scrollLinearLines)
            if scrollLinearLines != oldValue { onScrollDirectionChange?() }
        }
    }
    /// 按住這個鍵時一般滾輪改成左右捲動（見 ScrollHorizontalKey）
    var scrollHorizontalKey: ScrollHorizontalKey {
        didSet {
            defaults.set(scrollHorizontalKey.rawValue, forKey: Keys.scrollHorizontalKey)
            if scrollHorizontalKey != oldValue { onScrollDirectionChange?() }
        }
    }
    /// 一般滑鼠滾輪平滑捲動（見 SmoothScroll）
    var scrollSmooth: Bool {
        didSet {
            defaults.set(scrollSmooth, forKey: Keys.scrollSmooth)
            if scrollSmooth != oldValue { onScrollDirectionChange?() }
        }
    }
    var scrollReverseTrackpad: Bool {
        didSet {
            defaults.set(scrollReverseTrackpad, forKey: Keys.scrollReverseTrackpad)
            if scrollReverseTrackpad != oldValue { onScrollDirectionChange?() }
        }
    }
    /// 用視窗切換取代 Cmd+Tab（預設關閉）
    var windowSwitcher: Bool {
        didSet {
            defaults.set(windowSwitcher, forKey: Keys.windowSwitcher)
            if windowSwitcher != oldValue { onWindowSwitcherChange?() }
        }
    }
    /// 視窗切換的所有選項（快捷鍵、大小、篩選、排序、例外清單）
    var switcher: SwitcherSettings {
        didSet {
            defaults.set(switcher.stored, forKey: Keys.switcher)
            if switcher != oldValue { onWindowSwitcherChange?() }
        }
    }
    /// Caps Lock 切換中英不延遲
    var capsLockNoDelay: Bool {
        didSet {
            defaults.set(capsLockNoDelay, forKey: Keys.capsLockNoDelay)
            if capsLockNoDelay != oldValue { onInputSourceFixChange?() }
        }
    }
    /// 中文輸入法按住 Shift 打半形英文
    var shiftHalfWidth: Bool {
        didSet {
            defaults.set(shiftHalfWidth, forKey: Keys.shiftHalfWidth)
            if shiftHalfWidth != oldValue { onInputSourceFixChange?() }
        }
    }
    /// 桌面寵物的大小：1 是和日曆小工具差不多大，範圍 0.5～2（設定的地方用 clampPetScale 限制）
    var desktopPetScale: Double {
        didSet {
            defaults.set(desktopPetScale, forKey: Keys.desktopPetScale)
            if desktopPetScale != oldValue { onDesktopPetChange?() }
        }
    }
    static let desktopPetScaleRange: ClosedRange<Double> = 0.5...2

    static func clampPetScale(_ value: Double) -> Double {
        value.isFinite ? min(max(value, desktopPetScaleRange.lowerBound), desktopPetScaleRange.upperBound) : 1
    }
    /// 智慧充電的完成目標與保養上限（建立排程時的預設值）。完成目標預設是「原本的上限」（存成 0）：
    /// 建立排程時的系統充電上限，充好後就停在平常的上限，不會多充到 100%
    var chargingTargetPercent: Int {
        didSet {
            defaults.set(chargingTargetPercent, forKey: Keys.chargingTargetPercent)
            if chargingTargetPercent != Self.originalLimitTarget, chargingHoldPercent > chargingTargetPercent {
                chargingHoldPercent = chargingTargetPercent
            }
        }
    }
    static let originalLimitTarget = 0
    var chargingHoldPercent: Int {
        didSet { defaults.set(chargingHoldPercent, forKey: Keys.chargingHoldPercent) }
    }
    var chargingSleepStrategy: ChargingSleepStrategy {
        didSet { defaults.set(chargingSleepStrategy.rawValue, forKey: Keys.chargingSleepStrategy) }
    }
    /// 精準喚醒（需要管理員授權一次，與管理員 CPU 取樣共用服務）
    var chargingWakeEnabled: Bool {
        didSet {
            defaults.set(chargingWakeEnabled, forKey: Keys.chargingWakeEnabled)
            if chargingWakeEnabled != oldValue { onChargingWakeChange?() }
        }
    }

    /// 電力流向細項中隱藏的項目（FlowItem.rawValue）
    var hiddenFlowItems: Set<String> {
        didSet { defaults.set(hiddenFlowItems.sorted(), forKey: Keys.hiddenFlowItems) }
    }
    /// 詳細資訊分頁中隱藏的欄位（DetailField.rawValue）
    var hiddenDetailFields: Set<String> {
        didSet { defaults.set(hiddenDetailFields.sorted(), forKey: Keys.hiddenDetailFields) }
    }
    /// 每個周邊設備的低電量通知門檻（設備 id → %，0 表示關閉）；沒設定過的設備用預設值
    var peripheralThresholds: [String: Int] {
        didSet { defaults.set(peripheralThresholds, forKey: Keys.peripheralThresholds) }
    }
    static let defaultPeripheralThreshold = 20
    static let peripheralThresholdChoices = [0, 10, 15, 20, 30, 50]

    func isVisible(_ item: FlowItem) -> Bool { !hiddenFlowItems.contains(item.rawValue) }
    func isVisible(_ field: DetailField) -> Bool { !hiddenDetailFields.contains(field.rawValue) }
    func setVisible(_ item: FlowItem, _ visible: Bool) {
        if visible { hiddenFlowItems.remove(item.rawValue) } else { hiddenFlowItems.insert(item.rawValue) }
    }
    func setVisible(_ field: DetailField, _ visible: Bool) {
        if visible { hiddenDetailFields.remove(field.rawValue) } else { hiddenDetailFields.insert(field.rawValue) }
    }
    func peripheralThreshold(for id: String) -> Int { peripheralThresholds[id] ?? Self.defaultPeripheralThreshold }
    func setPeripheralThreshold(_ value: Int, for id: String) { peripheralThresholds[id] = value }

    /// App 圖示的背景色；改變時立刻套用到 App 本身（失敗原因放在 appIconError）
    var appIconColor: AppIconColor {
        didSet {
            defaults.set(appIconColor.rawValue, forKey: Keys.appIconColor)
            appIconError = AppIconChanger.apply(appIconColor)
        }
    }
    private(set) var appIconError: String?

    /// 每天自動檢查一次 GitHub 上有沒有新版本（只檢查，不會自動安裝）
    var autoCheckUpdates: Bool {
        didSet { defaults.set(autoCheckUpdates, forKey: Keys.autoCheckUpdates) }
    }
    /// 自動檢查發現新版本時發通知（每個版本只通知一次）
    var updateNotification: Bool {
        didSet { defaults.set(updateNotification, forKey: Keys.updateNotification) }
    }

    var display: MenuBarDisplay {
        didSet { defaults.set(display.rawValue, forKey: Keys.display); onChange?() }
    }
    var lowAlertEnabled: Bool {
        didSet { defaults.set(lowAlertEnabled, forKey: Keys.lowAlertEnabled) }
    }
    var lowThreshold: Int {
        didSet { defaults.set(lowThreshold, forKey: Keys.lowThreshold); onChange?() }
    }
    var fullAlertEnabled: Bool {
        didSet { defaults.set(fullAlertEnabled, forKey: Keys.fullAlertEnabled) }
    }
    var fullThreshold: Int {
        didSet { defaults.set(fullThreshold, forKey: Keys.fullThreshold) }
    }

    private enum Keys {
        static let display = "menuBarDisplay"
        static let lowAlertEnabled = "lowAlertEnabled"
        static let lowThreshold = "lowThreshold"
        static let fullAlertEnabled = "fullAlertEnabled"
        static let fullThreshold = "fullThreshold"
        static let monitorCPU = "monitorCPU"
        static let monitorMemory = "monitorMemory"
        static let monitorDisk = "monitorDisk"
        static let monitorNetwork = "monitorNetwork"
        static let mergeMemoryDisk = "mergeMemoryDisk"
        static let networkSpeedTest = "networkSpeedTest"
        static let systemMonitors = "systemMonitors"
        static let alertCPU = "alertCPU"
        static let alertMemory = "alertMemory"
        static let alertDisk = "alertDisk"
        static let menuBarCombined = "menuBarCombined"
        static let powerSaving = "powerSaving"
        static let powerSavingOnBatteryOnly = "powerSavingOnBatteryOnly"
        static let bluetoothOffDuringSleep = "bluetoothOffDuringSleep"
        static let keepAwakeApps = "keepAwakeApps"
        static let quitGuardQuit = "quitGuardQuit"
        static let lastWindowQuitExcluded = "lastWindowQuitExcluded"
        static let dockClickMode = "dockClickMode"
        static let keyboardCleaningSeconds = "keyboardCleaningSeconds"
        static let mouseBackButton = "mouseBackButton"
        static let mouseForwardButton = "mouseForwardButton"
        static let quitGuardClose = "quitGuardClose"
        static let quitGuardDuration = "quitGuardDuration"
        static let bluetoothTurnedOffForSleep = "bluetoothTurnedOffForSleep"
        static let updateInterval = "updateInterval"
        static let hiddenFlowItems = "hiddenFlowItems"
        static let hiddenDetailFields = "hiddenDetailFields"
        static let peripheralThresholds = "peripheralThresholds"
        static let appIconColor = "appIconColor"
        static let autoCheckUpdates = "autoCheckUpdates"
        static let updateNotification = "updateNotification"
        static let adminCPUSampling = "adminCPUSampling"
        static let chargingAppearance = "chargingAppearance"
        /// v1.7.3 起「照片」分成貓咪大頭照與我的照片；舊設定只轉換一次
        static let photoAppearanceSplit = "photoAppearanceSplit"
        static let desktopPet = "desktopPet"
        static let desktopPetOnWallpaper = "desktopPetOnWallpaper"
        static let desktopPetScale = "desktopPetScale"
        static let desktopPetLiveEyes = "desktopPetLiveEyes"
        static let desktopPetFollowCursor = "desktopPetFollowCursor"
        static let scrollReverseMouse = "scrollReverseMouse"
        static let scrollReverseTrackpad = "scrollReverseTrackpad"
        static let scrollReverseHorizontal = "scrollReverseHorizontal"
        static let scrollLinearLines = "scrollLinearLines"
        static let scrollHorizontalKey = "scrollHorizontalKey"
        static let scrollSmooth = "scrollSmooth"
        static let windowSwitcher = "windowSwitcher"
        static let switcher = "windowSwitcherSettings"
        static let capsLockNoDelay = "capsLockNoDelay"
        static let shiftHalfWidth = "shiftHalfWidth"
        static let chargingTargetPercent = "chargingTargetPercent"
        static let chargingHoldPercent = "chargingHoldPercent"
        static let chargingSleepStrategy = "chargingSleepStrategy"
        static let xdrAutomaticActivation = "xdrAutomaticActivation"
        static let chargingWakeEnabled = "chargingWakeEnabled"
    }

    /// 這台 Mac 以前用過這個 App（有設定或電量歷史）
    private static func usedBefore(_ defaults: UserDefaults) -> Bool {
        if let id = Bundle.main.bundleIdentifier, let domain = defaults.persistentDomain(forName: id), !domain.isEmpty { return true }
        let history = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BatteryMonitor/history.json")
        return FileManager.default.fileExists(atPath: history.path)
    }

    private init() {
        defaults.register(defaults: ["chargingIconNativeColor": true, "chargingIconFlow": true,
                                     "chargingIconOpacity": 1.0])
        chargingIconText = defaults.string(forKey: "chargingIconText") ?? "white"
        chargingIconNativeColor = defaults.bool(forKey: "chargingIconNativeColor")
        chargingIconFlow = defaults.bool(forKey: "chargingIconFlow")
        chargingIconColorData = defaults.data(forKey: "chargingIconColorData")
        chargingIconPreset = defaults.string(forKey: "chargingIconPreset")
            ?? (defaults.bool(forKey: "chargingIconNativeColor") ? "native" : "custom")
        let savedOpacity = defaults.double(forKey: "chargingIconOpacity")
        chargingIconOpacity = savedOpacity.isFinite ? min(1, max(0, savedOpacity)) : 1
        defaults.register(defaults: [
            Keys.xdrAutomaticActivation: true,
            Keys.display: MenuBarDisplay.iconAndPercent.rawValue,
            Keys.lowAlertEnabled: true,
            Keys.lowThreshold: 20,
            Keys.fullAlertEnabled: true,
            Keys.fullThreshold: 100,
            Keys.monitorCPU: true,
            Keys.monitorMemory: true,
            Keys.monitorDisk: true,
            Keys.monitorNetwork: true,
            Keys.mergeMemoryDisk: false,
            Keys.powerSaving: false,
            Keys.powerSavingOnBatteryOnly: false,
            Keys.bluetoothOffDuringSleep: false,
            Keys.quitGuardQuit: true,
            Keys.quitGuardClose: false,
            Keys.quitGuardDuration: 1.0,
            Keys.updateInterval: 1,
            Keys.adminCPUSampling: false,
            Keys.autoCheckUpdates: true,
            Keys.updateNotification: true,
            Keys.chargingAppearance: ChargingAppearance.companion.rawValue,
            Keys.desktopPet: false,
            Keys.menuBarCombined: false,
            Keys.desktopPetOnWallpaper: false,
            Keys.desktopPetScale: 1.0,
            Keys.desktopPetLiveEyes: true,
            Keys.desktopPetFollowCursor: true,
            Keys.chargingTargetPercent: 0,
            Keys.chargingHoldPercent: 80,
            Keys.chargingSleepStrategy: ChargingSleepStrategy.readinessFirst.rawValue,
            Keys.chargingWakeEnabled: false,
        ])
        // 要在寫入任何設定之前判斷（下面寫入安裝狀態後就判斷不出來）；從舊版更新的不算全新安裝，原本的功能都保留
        let usedBefore = Self.usedBefore(defaults)
        if !usedBefore {
            for (key, installed) in ExtensionFeature.freshInstallChoices { defaults.set(installed, forKey: key) }
        }
        var installed = Set<ExtensionFeature>()
        // 功能自己的開關有沒有打開過：舊版就用著的功能，更新後也要在
        let switchedOn: [ExtensionFeature: Bool] = [
            .windowSwitcher: defaults.bool(forKey: Keys.windowSwitcher),
            .inputMethod: defaults.bool(forKey: Keys.capsLockNoDelay) || defaults.bool(forKey: Keys.shiftHalfWidth),
            .speedTest: defaults.bool(forKey: Keys.networkSpeedTest),
        ]
        for feature in ExtensionFeature.allCases {
            let stored = defaults.object(forKey: feature.installedKey) as? Bool
            let isInstalled = feature.isInstalled(stored: stored, switchedOn: switchedOn[feature] ?? false)
            if isInstalled { installed.insert(feature) }
            // 第一次推算完就存起來：之後關掉功能自己的開關（例如視窗切換）再重開 App，頁面不會因為重新推算而消失
            if stored == nil { defaults.set(isInstalled, forKey: feature.installedKey) }
        }
        installedFeatures = installed
        xdrAutomaticActivation = defaults.bool(forKey: Keys.xdrAutomaticActivation)
        adminCPUSampling = defaults.bool(forKey: Keys.adminCPUSampling)
        display = MenuBarDisplay(rawValue: defaults.string(forKey: Keys.display) ?? "") ?? .iconAndPercent
        lowAlertEnabled = defaults.bool(forKey: Keys.lowAlertEnabled)
        lowThreshold = min(max(defaults.integer(forKey: Keys.lowThreshold), 5), 50)
        fullAlertEnabled = defaults.bool(forKey: Keys.fullAlertEnabled)
        fullThreshold = min(max(defaults.integer(forKey: Keys.fullThreshold), 50), 100)
        monitorCPU = defaults.bool(forKey: Keys.monitorCPU)
        monitorMemory = defaults.bool(forKey: Keys.monitorMemory)
        monitorDisk = defaults.bool(forKey: Keys.monitorDisk)
        monitorNetwork = defaults.bool(forKey: Keys.monitorNetwork)
        mergeMemoryDisk = defaults.bool(forKey: Keys.mergeMemoryDisk)
        alertCPU = defaults.bool(forKey: Keys.alertCPU)
        alertMemory = defaults.bool(forKey: Keys.alertMemory)
        alertDisk = defaults.bool(forKey: Keys.alertDisk)
        if defaults.object(forKey: Keys.systemMonitors) != nil {
            systemMonitors = defaults.bool(forKey: Keys.systemMonitors)
        } else if usedBefore, AppEdition.current == .battery || AppEdition.current == .status {
            // 用舊檔名的 zip 從 v1.6.2 以前一鍵更新：電池版維持只看電池，系統監控版維持開著，不再詢問。
            // 手動下載通用版升級的看不出原本是哪一版，和全新安裝一樣詢問
            let previous = AppEdition.current == .status
            systemMonitors = previous
            defaults.set(previous, forKey: Keys.systemMonitors)
        } else {
            systemMonitors = true
            needsModeChoice = true
        }
        powerSaving = defaults.bool(forKey: Keys.powerSaving)
        powerSavingOnBatteryOnly = defaults.bool(forKey: Keys.powerSavingOnBatteryOnly)
        bluetoothOffDuringSleep = defaults.bool(forKey: Keys.bluetoothOffDuringSleep)
        // 只收合法的識別碼、有上限（匯入的設定也走這裡）
        keepAwakeApps = Set((defaults.stringArray(forKey: Keys.keepAwakeApps) ?? [])
            .filter(SwitcherSettings.isValidBundleID).prefix(SwitcherSettings.maxExcludedApps))
        quitGuardQuit = defaults.bool(forKey: Keys.quitGuardQuit)
        mouseBackButton = MouseButtons.Action(stored: defaults.string(forKey: Keys.mouseBackButton))
        mouseForwardButton = MouseButtons.Action(stored: defaults.string(forKey: Keys.mouseForwardButton))
        keyboardCleaningSeconds = KeyboardCleaning.validDuration(defaults.integer(forKey: Keys.keyboardCleaningSeconds))
        dockClickMode = DockClick.Mode(rawValue: defaults.string(forKey: Keys.dockClickMode) ?? "") ?? .minimize
        // 只收合法的識別碼、最多 SwitcherSettings.maxExcludedApps 個（匯入的設定也走這裡）
        lastWindowQuitExcluded = Set((defaults.stringArray(forKey: Keys.lastWindowQuitExcluded) ?? [])
            .filter(SwitcherSettings.isValidBundleID).prefix(SwitcherSettings.maxExcludedApps))
        quitGuardClose = defaults.bool(forKey: Keys.quitGuardClose)
        // 只收選單上的值，其他（包括匯入的設定）退回 1 秒
        let duration = defaults.double(forKey: Keys.quitGuardDuration)
        quitGuardDuration = Self.quitGuardDurations.contains(duration) ? duration : 1
        let interval = defaults.integer(forKey: Keys.updateInterval)
        updateInterval = Self.updateIntervals.contains(interval) ? interval : 1
        hiddenFlowItems = Set(defaults.stringArray(forKey: Keys.hiddenFlowItems) ?? [])
        hiddenDetailFields = Set(defaults.stringArray(forKey: Keys.hiddenDetailFields) ?? [])
        peripheralThresholds = defaults.dictionary(forKey: Keys.peripheralThresholds) as? [String: Int] ?? [:]
        appIconColor = AppIconColor(rawValue: defaults.string(forKey: Keys.appIconColor) ?? "") ?? .mint
        autoCheckUpdates = defaults.bool(forKey: Keys.autoCheckUpdates)
        updateNotification = defaults.bool(forKey: Keys.updateNotification)
        var appearance = ChargingAppearance(rawValue: defaults.string(forKey: Keys.chargingAppearance) ?? "") ?? .companion
        // v1.7.2 的「照片」外觀換成自己照片的人，改用「我的照片」；貓咪大頭照另外保留
        if !defaults.bool(forKey: Keys.photoAppearanceSplit) {
            if appearance == .photo, CompanionPhoto.hasCustom {
                appearance = .customPhoto
                defaults.set(appearance.rawValue, forKey: Keys.chargingAppearance)
            }
            defaults.set(true, forKey: Keys.photoAppearanceSplit)
        }
        chargingAppearance = appearance
        desktopPet = defaults.bool(forKey: Keys.desktopPet)
        menuBarCombined = defaults.bool(forKey: Keys.menuBarCombined)
        desktopPetOnWallpaper = defaults.bool(forKey: Keys.desktopPetOnWallpaper)
        desktopPetScale = Self.clampPetScale(defaults.double(forKey: Keys.desktopPetScale))
        desktopPetLiveEyes = defaults.bool(forKey: Keys.desktopPetLiveEyes)
        desktopPetFollowCursor = defaults.bool(forKey: Keys.desktopPetFollowCursor)
        scrollReverseMouse = defaults.bool(forKey: Keys.scrollReverseMouse)
        scrollReverseTrackpad = defaults.bool(forKey: Keys.scrollReverseTrackpad)
        scrollReverseHorizontal = defaults.object(forKey: Keys.scrollReverseHorizontal) as? Bool ?? true
        scrollLinearLines = ScrollLinear.valid(defaults.integer(forKey: Keys.scrollLinearLines))
        scrollHorizontalKey = ScrollHorizontalKey(stored: defaults.string(forKey: Keys.scrollHorizontalKey))
        scrollSmooth = defaults.bool(forKey: Keys.scrollSmooth)
        windowSwitcher = defaults.bool(forKey: Keys.windowSwitcher)
        switcher = SwitcherSettings(stored: defaults.dictionary(forKey: Keys.switcher) ?? [:])
        capsLockNoDelay = defaults.bool(forKey: Keys.capsLockNoDelay)
        shiftHalfWidth = defaults.bool(forKey: Keys.shiftHalfWidth)
        let storedTarget = defaults.integer(forKey: Keys.chargingTargetPercent)
        let target = storedTarget == Self.originalLimitTarget ? Self.originalLimitTarget : ChargingPlan.clamp(storedTarget)
        chargingTargetPercent = target
        let hold = ChargingPlan.clamp(defaults.integer(forKey: Keys.chargingHoldPercent))
        chargingHoldPercent = target == Self.originalLimitTarget ? hold : min(hold, target)
        chargingSleepStrategy = ChargingSleepStrategy(rawValue: defaults.string(forKey: Keys.chargingSleepStrategy) ?? "") ?? .readinessFirst
        chargingWakeEnabled = defaults.bool(forKey: Keys.chargingWakeEnabled)
    }
}

/// 主面板智慧充電那一列左邊的樣子
enum ChargingAppearance: String, CaseIterable, Identifiable {
    /// 充電夥伴：會動的貓咪（充電時躺在充電墊上）
    case companion
    /// 電池夥伴：有表情的電池（等待時睡覺、充電時微笑、充好時開心、延遲時擔心）
    case mascot
    /// 電力流動：電量條
    case energy
    /// 貓咪大頭照：內建的貓咪照片，桌面寵物的眼睛會跟著游標、眨眼
    case photo
    /// 我的照片：自己選的照片（眼睛不會動），和貓咪大頭照分開存
    case customPhoto

    var id: String { rawValue }
    var title: String {
        switch self {
        case .companion: return "充電夥伴（貓咪）"
        case .mascot: return "電池夥伴"
        case .energy: return "電力流動"
        case .photo: return "貓咪大頭照"
        case .customPhoto: return "我的照片"
        }
    }

    /// 智慧充電頁上方切換外觀用的短名稱
    var shortTitle: String {
        switch self {
        case .companion: return "貓咪"
        case .mascot: return "電池夥伴"
        case .energy: return "電量條"
        case .photo: return "大頭照"
        case .customPhoto: return "我的照片"
        }
    }
}
