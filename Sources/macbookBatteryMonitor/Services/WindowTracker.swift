import AppKit
import ApplicationServices
import OSLog

/// 追蹤所有 App 的視窗，讓按下快捷鍵的當下不用再逐個 App 詢問「輔助使用」：
/// - 實體資訊（視窗存在、前後順序、在哪個 Space、在不在畫面上）按下時向 WindowServer 查，不會被卡住的 App 拖慢
/// - 語意資訊（標題、縮到 Dock、全螢幕、可操作的視窗物件）每個 App 一個「輔助使用」觀察者，有變化才在背景讀一次，存成快取
/// - 最近使用順序：App 切換、App 回報焦點視窗改變時才移動；自己切換視窗不直接改順序，等系統回報
@MainActor
final class WindowTracker {
    static let shared = WindowTracker()
    static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "tracker")

    struct AXWindow: @unchecked Sendable {
        var id: UInt32
        var element: AXUIElement
        var title: String
        var isMinimized: Bool
        var isFullscreen: Bool
        var isStandard: Bool
    }

    private let readQueue = DispatchQueue(label: "com.kuan.batterymonitor.tracker", qos: .userInitiated)
    private var cache: [pid_t: [UInt32: AXWindow]] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var refreshing = Set<pid_t>()
    private var refreshAgain = Set<pid_t>()
    private var recency = WindowRecency()
    private var workspaceTokens: [NSObjectProtocol] = []
    private(set) var isRunning = false

    private static let notifications = [
        kAXWindowCreatedNotification, kAXUIElementDestroyedNotification, kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
        kAXTitleChangedNotification,
    ]

    // MARK: - 開始與停止

    func start() {
        guard !isRunning, AXIsProcessTrusted() else { return }
        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { if let app { self?.track(app) } }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { if let app { self?.untrack(app.processIdentifier) } }
            },
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { if let app { self?.activated(app) } }
            },
        ]
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != me { track(app) }
        if let front = NSWorkspace.shared.frontmostApplication { activated(front) }
        Self.log.notice("開始追蹤視窗")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceTokens = []
        for pid in Array(observers.keys) { untrack(pid) }
        cache = [:]
        Self.log.notice("停止追蹤視窗")
    }

    // MARK: - App 與觀察者

    private func track(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular, pid != ProcessInfo.processInfo.processIdentifier, observers[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, trackerCallback, &observer) == .success, let observer else { return }
        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.notifications { AXObserverAddNotification(observer, element, name as CFString, refcon) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
        refresh(pid)
    }

    private func untrack(_ pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        if let removed = cache.removeValue(forKey: pid) {
            for id in removed.keys { recency.remove(id) }
        }
    }

    fileprivate func axEvent(_ notification: String, _ element: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return }
        if notification == kAXFocusedWindowChangedNotification || notification == kAXMainWindowChangedNotification {
            if let id = AX.windowID(of: element) { recency.focus(id) }
        }
        if notification == kAXUIElementDestroyedNotification, let id = cache[pid]?.first(where: { CFEqual($0.value.element, element) })?.key {
            cache[pid]?[id] = nil
            recency.remove(id)
        }
        refresh(pid)
    }

    private func activated(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        readQueue.async { [weak self] in
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.3)
            var value: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success, let value,
                  CFGetTypeID(value) == AXUIElementGetTypeID(), let id = AX.windowID(of: value as! AXUIElement) else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.recency.focus(id) } }
        }
    }

    /// 在背景重讀某個 App 的視窗；讀的途中又有變化就在讀完後再讀一次，不重疊
    func refresh(_ pid: pid_t) {
        guard refreshing.insert(pid).inserted else {
            refreshAgain.insert(pid)
            return
        }
        readQueue.async { [weak self] in
            let windows = Self.readWindows(pid)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.refreshing.remove(pid)
                    if self.observers[pid] != nil { self.cache[pid] = Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
                    if self.refreshAgain.remove(pid) != nil { self.refresh(pid) }
                }
            }
        }
    }

    private nonisolated static func readWindows(_ pid: pid_t) -> [AXWindow] {
        let app = AXUIElementCreateApplication(pid)
        // 沒有回應的 App 不要卡住背景佇列太久
        AXUIElementSetMessagingTimeout(app, 0.5)
        return AX.array(app, kAXWindowsAttribute).compactMap { window in
            guard let id = AX.windowID(of: window) else { return nil }
            var minimized: AnyObject?, fullscreen: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
            AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreen)
            return AXWindow(id: id, element: window, title: AX.string(window, kAXTitleAttribute) ?? "",
                            isMinimized: (minimized as? Bool) ?? false, isFullscreen: (fullscreen as? Bool) ?? false,
                            isStandard: AX.string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole)
        }
    }

    // MARK: - 快照

    struct Snapshot {
        var windows: [SwitcherWindow]
        var context: SwitcherFilter.Context
    }

    /// 按下快捷鍵時呼叫：只問 WindowServer，不等任何 App。
    /// 哪些視窗要列出、縮小與隱藏與全螢幕的狀態、標題，全部來自 WindowServer；「輔助使用」快取只補標題（App 自己給的比較貼近使用者看到的）
    /// 與可操作的視窗物件
    func snapshot() -> Snapshot {
        let me = ProcessInfo.processInfo.processIdentifier
        // 自己的視窗（例如設定視窗）也要能切過去；切換器自己的面板層級不是一般視窗，不會被列入
        let apps = Dictionary(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            .map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        let displays = SkyLight.displays()
        let currentSpaces = Set(displays.compactMap(\.current))
        let numberOfSpace = Dictionary(displays.flatMap { display in display.spaces.enumerated().map { ($1, $0 + 1) } }, uniquingKeysWith: { first, _ in first })
        let displayOfSpace = Dictionary(displays.flatMap { display in display.spaces.map { ($0, display.identifier) } }, uniquingKeysWith: { first, _ in first })
        let allSpaces = displays.flatMap(\.spaces)
        // 由前到後；沒排進畫面的視窗（縮到 Dock、隱藏、別的 Space、幻影）不在這份清單裡
        let stacking = SkyLight.windowIDs(inSpaces: allSpaces)
        let candidates = SkyLight.query(SkyLight.windowIDs(inSpaces: allSpaces, includeInvisible: true))
        var windows: [SwitcherWindow] = []
        for server in candidates {
            guard let app = apps[server.pid] else { continue }
            let spaces = SkyLight.spaces(of: server.id)
            guard WindowAdmission.verdict(server, spaces: spaces, currentSpaces: currentSpaces) == .admit else { continue }
            let ax = cache[server.pid]?[server.id]
            // 「輔助使用」明確說不是一般視窗（對話框、工具面板）就不列；沒有資料時相信 WindowServer
            if let ax, !ax.isStandard { continue }
            let title = ax?.title.isEmpty == false ? ax!.title : server.title
            windows.append(SwitcherWindow(id: server.id, pid: server.pid, appName: app.localizedName ?? "", bundleID: app.bundleIdentifier, title: title,
                                          isMinimized: WindowAdmission.isMinimized(server) || ax?.isMinimized == true,
                                          isHidden: app.isHidden || WindowAdmission.isAppHidden(server),
                                          isFullscreen: WindowAdmission.isFullscreen(server) || ax?.isFullscreen == true,
                                          spaces: spaces, displayID: spaces.first.flatMap { displayOfSpace[$0] },
                                          spaceNumber: Self.spaceNumber(of: spaces, current: currentSpaces, numbers: numberOfSpace),
                                          aspect: server.frame.height > 0 ? server.frame.width / server.frame.height : 1.6,
                                          frame: server.frame))
        }
        recency.prune(keeping: Set(windows.map(\.id)))
        let appsWithWindows = Set(windows.map(\.pid))
        // 還在執行但沒有視窗的 App 排在所有視窗之後
        let windowless = apps.values.filter { !appsWithWindows.contains($0.processIdentifier) && $0.processIdentifier != me }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
            .map { app in
                SwitcherWindow(id: SwitcherWindow.windowlessID(pid: app.processIdentifier), pid: app.processIdentifier, appName: app.localizedName ?? "",
                               bundleID: app.bundleIdentifier, title: "", isHidden: app.isHidden, isWindowless: true)
            }
        let context = SwitcherFilter.Context(currentSpaces: currentSpaces, activeDisplay: Self.displayUnderMouse())
        return Snapshot(windows: recency.sorted(windows, stacking: stacking) + windowless, context: context)
    }

    /// 只有視窗完全不在目前顯示的 Space 才標示它在第幾個 Space
    private static func spaceNumber(of spaces: [UInt64], current: Set<UInt64>, numbers: [UInt64: Int]) -> Int? {
        guard let first = spaces.first, current.isDisjoint(with: spaces) else { return nil }
        return numbers[first]
    }

    private static func displayUnderMouse() -> String? {
        let mouse = NSEvent.mouseLocation
        guard let number = NSScreen.screens.first(where: { $0.frame.contains(mouse) })?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    // MARK: - 操作

    /// 視窗的「輔助使用」物件。快取沒有時（剛換到全螢幕、剛開的視窗）現場讀一次，最多等 0.5 秒
    func axWindow(_ window: SwitcherWindow) -> AXWindow? {
        if let cached = cache[window.pid]?[window.id] { return cached }
        guard !window.isWindowless, observers[window.pid] != nil else { return nil }
        let fresh = Self.readWindows(window.pid)
        cache[window.pid] = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return cache[window.pid]?[window.id]
    }

    /// 切過去：有視窗物件就直接操作；在別的 Space 的視窗沒有物件，改用 WindowServer 的方式
    func focus(_ window: SwitcherWindow) {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return }
        if window.pid == ProcessInfo.processInfo.processIdentifier {
            focusOwn(window)
            return
        }
        if window.isWindowless {
            // 沒有視窗：叫出 App，並送「重新開啟」讓它自己開一個視窗（等同點 Dock 圖示）
            if app.isHidden { app.unhide() }
            if let url = app.bundleURL { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) } else { app.activate() }
            return
        }
        if let ax = axWindow(window) {
            Self.raise(ax.element, of: app)
            return
        }
        if app.isHidden { app.unhide() }
        if !SkyLight.focus(windowID: window.id, pid: window.pid) { app.activate() }
    }

    /// 這個 App 自己的視窗：不經過「輔助使用」，直接用 AppKit
    private func ownWindow(_ window: SwitcherWindow) -> NSWindow? {
        NSApp.windows.first { $0.windowNumber == Int(window.id) }
    }

    private func focusOwn(_ window: SwitcherWindow) {
        // macOS 14 起 activate() 是「合作式」：別的 App 在前景時系統可以不理會，第一次切過來就會沒反應。
        // 切換是使用者明確的要求，所以用強制啟用
        NSApp.activate(ignoringOtherApps: true)
        guard let target = ownWindow(window) else { return }
        if target.isMiniaturized { target.deminiaturize(nil) }
        target.makeKeyAndOrderFront(nil)
        target.orderFrontRegardless()
    }

    private func performOwn(_ action: SwitcherWindowAction, on window: SwitcherWindow) -> Outcome {
        let target = ownWindow(window)
        switch action {
        case .close:
            target?.performClose(nil)
            return .removed
        case .minimize:
            guard let target else { return .unchanged }
            if target.isMiniaturized { target.deminiaturize(nil) } else { target.miniaturize(nil) }
            return .updated(minimized: target.isMiniaturized)
        case .fullscreen:
            guard let target, target.collectionBehavior.contains(.fullScreenPrimary) else { return .unchanged }
            target.toggleFullScreen(nil)
            return .unchanged
        case .hide, .quit:
            // 結束或隱藏自己會連切換器一起消失，選到自己的視窗時不提供
            return .unchanged
        }
    }

    /// 隱藏的 App 先顯示、縮到 Dock 的先叫回來，再把這個視窗與它的 App 帶到最前面
    private static func raise(_ window: AXUIElement, of app: NSRunningApplication) {
        if app.isHidden { app.unhide() }
        var minimized: AnyObject?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized) == .success, minimized as? Bool == true {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        // 這個 App 不在前景時，系統可能不理會 activate；同時透過「輔助使用」設成最前面的 App
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate()
    }

    /// 動作之後清單上這個視窗的樣子
    enum Outcome: Equatable {
        case removed
        case unchanged
        /// 動作之後的真實狀態；nil 表示沒有改變。hidden 影響整個 App 的所有視窗
        case updated(minimized: Bool? = nil, fullscreen: Bool? = nil, hidden: Bool? = nil)
    }

    @discardableResult
    func perform(_ action: SwitcherWindowAction, on window: SwitcherWindow) -> Outcome {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return .removed }
        if window.pid == ProcessInfo.processInfo.processIdentifier { return performOwn(action, on: window) }
        // 沒有視窗可以關、縮小、全螢幕；只有隱藏與結束 App 有意義
        if window.isWindowless, ![.hide, .quit].contains(action) { return .unchanged }
        switch action {
        case .close:
            guard let ax = axWindow(window) else { return .unchanged }
            var button: AnyObject?
            guard AXUIElementCopyAttributeValue(ax.element, kAXCloseButtonAttribute as CFString, &button) == .success, let button,
                  CFGetTypeID(button) == AXUIElementGetTypeID() else { return .unchanged }
            AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
            refresh(window.pid)
            return .removed
        case .minimize:
            guard let ax = axWindow(window), let now = Self.toggle(ax.element, kAXMinimizedAttribute) else { return .unchanged }
            refresh(window.pid)
            return .updated(minimized: now)
        case .fullscreen:
            guard let ax = axWindow(window), let now = Self.toggle(ax.element, "AXFullScreen") else { return .unchanged }
            refresh(window.pid)
            return .updated(fullscreen: now)
        case .hide:
            if window.isHidden { app.unhide() } else { app.hide() }
            return .updated(hidden: !window.isHidden)
        case .quit:
            app.terminate()
            return .removed
        }
    }

    /// 讀目前的真實狀態再設成相反，不依賴按下快捷鍵時記下的狀態（那份在動作之間會過期）。回傳設定後的值；讀不到或設定失敗為 nil
    private static func toggle(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let current = value as? Bool else { return nil }
        let next = !current
        guard AXUIElementSetAttributeValue(element, attribute as CFString, next as CFBoolean) == .success else { return nil }
        return next
    }
}

private func trackerCallback(observer _: AXObserver, element: AXUIElement, notification: CFString, refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let name = notification as String
    MainActor.assumeIsolated {
        Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue().axEvent(name, element)
    }
}
