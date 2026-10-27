import Foundation
import Combine

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
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    /// 影響選單列圖示的設定改變時呼叫
    var onChange: (() -> Void)?
    /// 系統監控模組開關改變時呼叫
    var onMonitorsChange: (() -> Void)?
    /// 更新頻率或省電模式改變時呼叫（重設所有取樣間隔）
    var onIntervalChange: (() -> Void)?
    /// 智慧充電的精準喚醒開關改變時呼叫
    var onChargingWakeChange: (() -> Void)?
    /// 桌面寵物開關改變時
    /// 捲動方向的設定改變時
    var onScrollDirectionChange: (() -> Void)?
    var onDesktopPetChange: (() -> Void)?

    /// 可選的更新頻率（秒）
    static let updateIntervals = [1, 2, 5, 10]

    /// 更新頻率（秒），預設每秒
    @Published var updateInterval: Int {
        didSet { defaults.set(updateInterval, forKey: Keys.updateInterval); onIntervalChange?() }
    }

    /// 省電模式：電力流向改用靜態圖示、不播放動畫，更新頻率至少每 2 秒
    @Published var powerSaving: Bool {
        didSet { defaults.set(powerSaving, forKey: Keys.powerSaving); onIntervalChange?() }
    }

    /// 只在使用電池時套用省電模式，接上電源就恢復一般模式
    @Published var powerSavingOnBatteryOnly: Bool {
        didSet { defaults.set(powerSavingOnBatteryOnly, forKey: Keys.powerSavingOnBatteryOnly); onIntervalChange?() }
    }

    /// 目前是否接著電源（不存檔，由 AppDelegate 每次更新時帶入；桌上型 Mac 一律視為接著電源）
    @Published var onACPower = false {
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
    @Published var monitorCPU: Bool {
        didSet { defaults.set(monitorCPU, forKey: Keys.monitorCPU); onMonitorsChange?() }
    }
    @Published var monitorMemory: Bool {
        didSet { defaults.set(monitorMemory, forKey: Keys.monitorMemory); onMonitorsChange?() }
    }
    @Published var monitorDisk: Bool {
        didSet { defaults.set(monitorDisk, forKey: Keys.monitorDisk); onMonitorsChange?() }
    }
    @Published var monitorNetwork: Bool {
        didSet { defaults.set(monitorNetwork, forKey: Keys.monitorNetwork); onMonitorsChange?() }
    }
    /// 記憶體與磁碟合併成一個選單列圖示（像 CPU／GPU 一樣兩行），面板也合在一起
    @Published var mergeMemoryDisk: Bool {
        didSet { defaults.set(mergeMemoryDisk, forKey: Keys.mergeMemoryDisk); onMonitorsChange?() }
    }
    /// 合併現在是否生效：開關打開，且記憶體與磁碟都有開
    var memoryDiskMerged: Bool {
        MonitorKind.mergesMemoryDisk(merge: mergeMemoryDisk, memory: isMonitorEnabled(.memory), disk: isMonitorEnabled(.disk))
    }
    /// 網路面板顯示測速卡片。預設關閉：測一次要用掉數百 MB 流量，避免誤按
    @Published var networkSpeedTest: Bool {
        didSet { defaults.set(networkSpeedTest, forKey: Keys.networkSpeedTest); onMonitorsChange?() }
    }

    /// 系統監控總開關：關閉時選單列只有電池（桌上型為耗電）圖示，四個模組都不取樣，和以前的電池版一樣省電
    @Published var systemMonitors: Bool {
        didSet { defaults.set(systemMonitors, forKey: Keys.systemMonitors); onMonitorsChange?() }
    }
    /// 合併顯示：選單列只留電池（桌上型為耗電）一個圖示，點一下在下方展開第二條狀態列，列出所有圖示。
    /// 選單列圖示太多時，macOS 會把放不下的藏起來（尤其有瀏海的 MacBook）
    @Published var menuBarCombined: Bool {
        didSet { defaults.set(menuBarCombined, forKey: Keys.menuBarCombined); onMonitorsChange?() }
    }
    /// 全新安裝、還沒選過要不要開系統監控（第一次啟動時詢問）
    @Published private(set) var needsModeChoice = false

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
    @Published var adminCPUSampling: Bool {
        didSet { defaults.set(adminCPUSampling, forKey: Keys.adminCPUSampling) }
    }

    /// 智慧充電：主面板那一列左邊顯示充電夥伴（貓咪）或電量條
    @Published var chargingAppearance: ChargingAppearance {
        didSet { defaults.set(chargingAppearance.rawValue, forKey: Keys.chargingAppearance) }
    }
    /// 換「我的照片」時加一，讓用到照片的畫面重畫（照片本身在 CompanionPhoto）
    @Published var companionPhotoVersion = 0
    /// 桌面寵物：把充電夥伴放在桌面上（只有 MacBook 有）
    @Published var desktopPet: Bool {
        didSet {
            defaults.set(desktopPet, forKey: Keys.desktopPet)
            if desktopPet != oldValue { onDesktopPetChange?() }
        }
    }
    /// 桌面寵物放在桌布上（會被視窗蓋住）；關閉時浮在所有視窗上方
    @Published var desktopPetOnWallpaper: Bool {
        didSet {
            defaults.set(desktopPetOnWallpaper, forKey: Keys.desktopPetOnWallpaper)
            if desktopPetOnWallpaper != oldValue { onDesktopPetChange?() }
        }
    }
    /// 桌面寵物貓咪大頭照的眼睛會動：眨眼、睡覺時閉眼
    @Published var desktopPetLiveEyes: Bool {
        didSet { defaults.set(desktopPetLiveEyes, forKey: Keys.desktopPetLiveEyes) }
    }
    /// 眼睛跟著游標：關掉就完全不監聽滑鼠移動
    @Published var desktopPetFollowCursor: Bool {
        didSet { defaults.set(desktopPetFollowCursor, forKey: Keys.desktopPetFollowCursor) }
    }
    /// 捲動方向：滑鼠與觸控板各自反向（macOS 的「自然捲動」兩者共用一個設定）
    @Published var scrollReverseMouse: Bool {
        didSet {
            defaults.set(scrollReverseMouse, forKey: Keys.scrollReverseMouse)
            if scrollReverseMouse != oldValue { onScrollDirectionChange?() }
        }
    }
    @Published var scrollReverseTrackpad: Bool {
        didSet {
            defaults.set(scrollReverseTrackpad, forKey: Keys.scrollReverseTrackpad)
            if scrollReverseTrackpad != oldValue { onScrollDirectionChange?() }
        }
    }
    /// 桌面寵物的大小：1 是和日曆小工具差不多大，範圍 0.5～2（設定的地方用 clampPetScale 限制）
    @Published var desktopPetScale: Double {
        didSet {
            defaults.set(desktopPetScale, forKey: Keys.desktopPetScale)
            if desktopPetScale != oldValue { onDesktopPetChange?() }
        }
    }
    static let desktopPetScaleRange: ClosedRange<Double> = 0.5...2

    static func clampPetScale(_ value: Double) -> Double {
        min(max(value, desktopPetScaleRange.lowerBound), desktopPetScaleRange.upperBound)
    }
    /// 智慧充電的完成目標與保養上限（建立排程時的預設值）。完成目標預設是「原本的上限」（存成 0）：
    /// 建立排程時的系統充電上限，充好後就停在平常的上限，不會多充到 100%
    @Published var chargingTargetPercent: Int {
        didSet {
            defaults.set(chargingTargetPercent, forKey: Keys.chargingTargetPercent)
            if chargingTargetPercent != Self.originalLimitTarget, chargingHoldPercent > chargingTargetPercent {
                chargingHoldPercent = chargingTargetPercent
            }
        }
    }
    static let originalLimitTarget = 0
    @Published var chargingHoldPercent: Int {
        didSet { defaults.set(chargingHoldPercent, forKey: Keys.chargingHoldPercent) }
    }
    @Published var chargingSleepStrategy: ChargingSleepStrategy {
        didSet { defaults.set(chargingSleepStrategy.rawValue, forKey: Keys.chargingSleepStrategy) }
    }
    /// 精準喚醒（需要管理員授權一次，與管理員 CPU 取樣共用服務）
    @Published var chargingWakeEnabled: Bool {
        didSet {
            defaults.set(chargingWakeEnabled, forKey: Keys.chargingWakeEnabled)
            if chargingWakeEnabled != oldValue { onChargingWakeChange?() }
        }
    }

    /// 電力流向細項中隱藏的項目（FlowItem.rawValue）
    @Published var hiddenFlowItems: Set<String> {
        didSet { defaults.set(hiddenFlowItems.sorted(), forKey: Keys.hiddenFlowItems) }
    }
    /// 詳細資訊分頁中隱藏的欄位（DetailField.rawValue）
    @Published var hiddenDetailFields: Set<String> {
        didSet { defaults.set(hiddenDetailFields.sorted(), forKey: Keys.hiddenDetailFields) }
    }
    /// 每個周邊設備的低電量通知門檻（設備 id → %，0 表示關閉）；沒設定過的設備用預設值
    @Published var peripheralThresholds: [String: Int] {
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
    @Published var appIconColor: AppIconColor {
        didSet {
            defaults.set(appIconColor.rawValue, forKey: Keys.appIconColor)
            appIconError = AppIconChanger.apply(appIconColor)
        }
    }
    @Published private(set) var appIconError: String?

    /// 每天自動檢查一次 GitHub 上有沒有新版本（只檢查，不會自動安裝）
    @Published var autoCheckUpdates: Bool {
        didSet { defaults.set(autoCheckUpdates, forKey: Keys.autoCheckUpdates) }
    }
    /// 自動檢查發現新版本時發通知（每個版本只通知一次）
    @Published var updateNotification: Bool {
        didSet { defaults.set(updateNotification, forKey: Keys.updateNotification) }
    }

    @Published var display: MenuBarDisplay {
        didSet { defaults.set(display.rawValue, forKey: Keys.display); onChange?() }
    }
    @Published var lowAlertEnabled: Bool {
        didSet { defaults.set(lowAlertEnabled, forKey: Keys.lowAlertEnabled) }
    }
    @Published var lowThreshold: Int {
        didSet { defaults.set(lowThreshold, forKey: Keys.lowThreshold); onChange?() }
    }
    @Published var fullAlertEnabled: Bool {
        didSet { defaults.set(fullAlertEnabled, forKey: Keys.fullAlertEnabled) }
    }
    @Published var fullThreshold: Int {
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
        static let menuBarCombined = "menuBarCombined"
        static let powerSaving = "powerSaving"
        static let powerSavingOnBatteryOnly = "powerSavingOnBatteryOnly"
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
        static let chargingTargetPercent = "chargingTargetPercent"
        static let chargingHoldPercent = "chargingHoldPercent"
        static let chargingSleepStrategy = "chargingSleepStrategy"
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
        defaults.register(defaults: [
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
            Keys.networkSpeedTest: false,
            Keys.powerSaving: false,
            Keys.powerSavingOnBatteryOnly: false,
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
        adminCPUSampling = defaults.bool(forKey: Keys.adminCPUSampling)
        display = MenuBarDisplay(rawValue: defaults.string(forKey: Keys.display) ?? "") ?? .iconAndPercent
        lowAlertEnabled = defaults.bool(forKey: Keys.lowAlertEnabled)
        lowThreshold = defaults.integer(forKey: Keys.lowThreshold)
        fullAlertEnabled = defaults.bool(forKey: Keys.fullAlertEnabled)
        fullThreshold = defaults.integer(forKey: Keys.fullThreshold)
        monitorCPU = defaults.bool(forKey: Keys.monitorCPU)
        monitorMemory = defaults.bool(forKey: Keys.monitorMemory)
        monitorDisk = defaults.bool(forKey: Keys.monitorDisk)
        monitorNetwork = defaults.bool(forKey: Keys.monitorNetwork)
        mergeMemoryDisk = defaults.bool(forKey: Keys.mergeMemoryDisk)
        networkSpeedTest = defaults.bool(forKey: Keys.networkSpeedTest)
        if defaults.object(forKey: Keys.systemMonitors) != nil {
            systemMonitors = defaults.bool(forKey: Keys.systemMonitors)
        } else if Self.usedBefore(defaults), AppEdition.current == .battery || AppEdition.current == .status {
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
