import AppKit
import ApplicationServices
import OSLog

/// 點 Dock 圖示縮到 Dock（判斷在 DockClick）。只監聽滑鼠（listenOnly），不攔截，Dock 原本的點擊與拖曳都照常。
/// 按下時判斷（Dock 在放開時才動作，這時讀到的是點擊前的狀態），放開時執行。
/// 只有點在螢幕邊緣附近（Dock 可能出現的地方）才去讀 Dock 的圖示位置，其他點擊不做事。需要「輔助使用」權限
@MainActor
final class DockClickController {
    static let shared = DockClickController()
    nonisolated static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "dockClick")

    var mode = DockClick.Mode.minimize
    /// 權限被撤銷或系統讓攔截失效時也會反映出來
    var isRunning: Bool { port.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } ?? false }

    private var port: CFMachPort?
    private var watchdog: Timer?
    private struct Press {
        var location: CGPoint
        /// 按下的時間（開機後秒數，和 ProcessInfo.systemUptime 同一個時鐘）
        var time: TimeInterval
        var front: pid_t?
        var clicked: pid_t?
        var visible: Bool
        var minimizedByUs: Bool
    }
    /// 我們縮下去、還沒叫回的視窗；再點一次時叫回這些
    private var minimizedByUs: [pid_t: [(element: AXUIElement, id: UInt32)]] = [:]
    private var press: Press?
    /// 每次按下加一：第二次縮小前使用者又點了，就不再把叫回的視窗縮回去
    private var clicks = 0
    /// 最近一次縮小是哪個 App、第幾次按下、那次縮了哪些視窗：雙擊不算縮小，第二下只叫回這些（之前縮的照舊留在 Dock）
    private var lastMinimize: (pid: pid_t, generation: Int, windows: Set<UInt32>)?
    /// 雙擊的第一下是第幾次按下
    private var doubleClickOf: Int?
    /// 切換 App 的紀錄（收到通知的時間），用來找出按下那一刻最前面的 App
    private var frontHistory: [(pid: pid_t, time: TimeInterval)] = []
    private var activationObserver: NSObjectProtocol?
    /// 長按是 Dock 的選單，不是點擊
    private static let maxPressDuration: TimeInterval = 0.5
    /// 放開時 Dock 會請 App「重新打開」，App 會叫回一個縮下去的視窗：稍等一下再縮，讓那個要求先完成；
    /// 有些 App（例如 Qt 的 LINE）回應得更晚，過一陣子再把被叫回的縮回去一次
    private static let reopenDelay: TimeInterval = 0.05
    private static let reopenGrace: TimeInterval = 0.4
    /// Dock 離螢幕邊緣最多這麼遠；Dock 放大效果會更高，抓寬一點
    private static let edgeBand: CGFloat = 220

    @discardableResult
    func apply(enabled: Bool) -> Bool {
        guard enabled else {
            stop()
            return true
        }
        // 權限被收回：舊的攔截已經收不到事件，停掉；重新允許後 AppDelegate 的定時檢查會再呼叫這裡重新開始
        guard AXIsProcessTrusted() else {
            stop()
            return false
        }
        // 作廢的攔截（重建失敗留下的）先清掉再重建
        if let port, !CFMachPortIsValid(port) { stop() }
        guard port == nil else { return isRunning }
        let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                           eventsOfInterest: mask, callback: dockClickCallback, userInfo: nil) else { return false }
        // 攔截剛好被作廢時建不出來源
        guard let source = CFMachPortCreateRunLoopSource(nil, port, 0) as CFRunLoopSource? else {
            CFMachPortInvalidate(port)
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        if let front = NSWorkspace.shared.frontmostApplication { activated(front) }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { DockClickController.shared.activated(app) }
        }
        // 系統可能暫停攔截：每 5 秒檢查一次
        watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated {
                DockClickController.shared.keepAlive()
            }
        }
        Self.log.notice("開始監聽 Dock 點擊")
        return true
    }

    /// 系統暫停攔截時重新打開；失效（例如權限被撤銷又給回）時重建
    private func keepAlive() {
        guard let port else { return }
        // 權限被撤銷：重新打開只會一直被系統逾時暫停，整台 Mac 的輸入跟著卡。停掉，權限回來後由 AppDelegate 每 5 秒的檢查重新開始
        if !AXIsProcessTrusted() {
            stop()
        } else if !CFMachPortIsValid(port) {
            stop()
            apply(enabled: true)
        } else if !CGEvent.tapIsEnabled(tap: port) {
            CGEvent.tapEnable(tap: port, enable: true)
        }
    }

    private func stop() {
        watchdog?.invalidate()
        watchdog = nil
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        port = nil
        press = nil
        minimizedByUs = [:]
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        frontHistory = []
    }

    /// shortcut: 記的是收到通知的時間，主執行緒很忙時會比實際切換晚；按下前一刻才切換的 App 可能被當成按下後才切換
    private func activated(_ app: NSRunningApplication) {
        frontHistory.append((app.processIdentifier, ProcessInfo.processInfo.systemUptime))
        if frontHistory.count > 16 { frontHistory.removeFirst(frontHistory.count - 16) }
    }

    fileprivate func handle(_ type: CGEventType, location: CGPoint, modified: Bool, clickState: Int64, time: TimeInterval) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port, AXIsProcessTrusted() { CGEvent.tapEnable(tap: port, enable: true) }
        case .leftMouseDown:
            press = nil
            clicks &+= 1
            if clickState >= 2 { doubleClickOf = clicks &- 1 }
            // ⌘ 點（在 Finder 顯示）、⌥ 點（隱藏其他）等 Dock 自己的操作不插手；
            // 雙擊背景 App 的圖示時，第二下它已經在最前面，不能當成「再點一次最前面的 App」
            guard !modified, clickState <= 1, Self.nearScreenEdge(location) else { return }
            // 回呼可能晚跑，Dock 已經切換了 App：用切換紀錄找按下那一刻的前景 App
            let front = DockClick.frontApp(at: time, history: frontHistory)
            let clicked = Self.dockApp(at: location)
            // 只有點到最前面那個 App 時才需要知道它的視窗狀態
            // Dock 放開才動作：左鍵已經放開，或按下之後放開過（使用者可能已經按了第二下），都當成 Dock 可能已經動作了
            let lastUp = ProcessInfo.processInfo.systemUptime
                - CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseUp)
            let late = !CGEventSource.buttonState(.combinedSessionState, button: .left) || lastUp > time
            let state = clicked != nil && clicked == front ? stateAtClick(of: front ?? 0, late: late) : (visible: false, minimizedByUs: false)
            let lag = Int((ProcessInfo.processInfo.systemUptime - time) * 1000)
            Self.log.debug("Dock 點擊：按下後 \(lag) ms 才處理，前景 \(front ?? 0)，點到 \(clicked ?? 0)，開著的視窗 \(state.visible)，我們縮的 \(state.minimizedByUs)")
            press = Press(location: location, time: time, front: front, clicked: clicked,
                          visible: state.visible, minimizedByUs: state.minimizedByUs)
        case .leftMouseUp:
            // 雙擊不算縮小：第二下放開時把第一下縮的叫回（Dock 自己只會叫回一個，早晚都沒關係）
            if clickState >= 2, let last = lastMinimize, last.generation == clicks &- 1 {
                lastMinimize = nil
                Self.log.debug("雙擊：叫回第一下縮的 \(last.windows.count) 個視窗")
                restore(last.windows, of: last.pid)
            }
            guard let press else { return }
            self.press = nil
            let distance = hypot(location.x - press.location.x, location.y - press.location.y)
            guard let pid = press.clicked, time - press.time <= Self.maxPressDuration else { return }
            let action = DockClick.decide(frontAppAtMouseDown: press.front, clickedApp: pid, hadVisibleWindows: press.visible,
                                          dragDistance: distance, mode: mode, minimizedByUs: press.minimizedByUs)
            Self.log.debug("Dock 點擊動作：\(String(describing: action), privacy: .public)")
            perform(action, pid: pid)
        default:
            return
        }
    }

    /// 按下那一刻的狀態（Dock 還沒動作）。有沒有開著的視窗問 WindowServer，不問 App，不會等
    /// late：回呼跑的時候左鍵已經放開或放開過，Dock 可能已經叫回我們縮的視窗，這時叫回的那些不算「按下前開著的視窗」
    private func stateAtClick(of pid: pid_t, late: Bool) -> (visible: Bool, minimizedByUs: Bool) {
        let recorded = minimizedByUs[pid] ?? []
        // 我們縮的視窗都已經不在 Dock 裡（使用者自己叫回了）：紀錄作廢
        let ours = recorded.filter { Self.isMinimized($0.element) != false }
        minimizedByUs[pid] = ours.isEmpty ? nil : ours
        let excluded = late ? recorded : ours
        let visible = DockClick.hasVisibleWindow(Self.screenWindows(), pid: pid, excluding: Set(excluded.map(\.id)))
        return (visible, !excluded.isEmpty)
    }

    private func perform(_ action: DockClick.Action, pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            minimizedByUs[pid] = nil
            return
        }
        switch action {
        case .none: return
        case .hide:
            // 本 App 是選單列 App，NSRunningApplication.hide() 第一次常沒作用：改用「輔助使用」
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.3)
            AXUIElementSetAttributeValue(element, kAXHiddenAttribute as CFString, kCFBooleanTrue)
        case .minimize:
            let generation = clicks
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.reopenDelay) {
                MainActor.assumeIsolated {
                    // 還沒縮就雙擊了：不縮
                    guard DockClickController.shared.doubleClickOf != generation else { return }
                    DockClickController.shared.minimize(pid, generation: generation)
                }
            }
            lastMinimize = (pid, generation, [])
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.reopenDelay + Self.reopenGrace) {
                MainActor.assumeIsolated {
                    let controller = DockClickController.shared
                    // 使用者又點了一下（可能就是要叫回）：不再縮
                    guard controller.clicks == generation else { return }
                    controller.minimizeRestored(pid)
                }
            }
        case .restore:
            for window in minimizedByUs.removeValue(forKey: pid) ?? [] where Self.isMinimized(window.element) != false {
                AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            app.activate()
        }
    }

    /// 縮下所有一般視窗；有焦點的最後縮，叫回時它也最後回來、在最上面
    /// 雙擊的第二下：只叫回指定的視窗，並移出紀錄
    private func restore(_ ids: Set<UInt32>, of pid: pid_t) {
        guard !ids.isEmpty, let recorded = minimizedByUs[pid] else { return }
        for window in recorded where ids.contains(window.id) && Self.isMinimized(window.element) != false {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        let rest = recorded.filter { !ids.contains($0.id) }
        minimizedByUs[pid] = rest.isEmpty ? nil : rest
    }

    private func minimize(_ pid: pid_t, generation: Int) {
        guard port != nil else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var targets = Self.windows(of: pid).filter {
            Self.attribute($0, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole && Self.isMinimized($0) != true
        }
        if let focused = Self.attribute(app, kAXFocusedWindowAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID(),
           let index = targets.firstIndex(where: { CFEqual($0, focused as! AXUIElement) }) {
            targets.append(targets.remove(at: index))
        }
        guard !targets.isEmpty else { return }
        for window in targets { AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) }
        let added = targets.map { ($0, AX.windowID(of: $0) ?? 0) }
        let addedIDs = Set(added.map(\.1))
        if lastMinimize?.generation == generation { lastMinimize?.windows = addedIDs }
        // 和之前縮下去、還沒叫回的合併，「再點一次」才全部叫得回來；這次又縮到的不重複記
        let earlier = (minimizedByUs[pid] ?? []).filter { !addedIDs.contains($0.id) && Self.isMinimized($0.element) != false }
        minimizedByUs[pid] = earlier + added
    }

    /// 剛縮下去又被 App 晚到的「重新打開」叫回的視窗，再縮一次
    private func minimizeRestored(_ pid: pid_t) {
        guard port != nil else { return }
        for window in minimizedByUs[pid] ?? [] where Self.isMinimized(window.element) == false {
            Self.log.debug("縮下去的視窗又被叫回，再縮一次")
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }
    }

    /// WindowServer 的畫面上視窗清單（目前桌面，不含隱藏與縮下去的）
    private static func screenWindows() -> [DockClick.ScreenWindow] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) }) else { return nil }
            return DockClick.ScreenWindow(pid: pid, id: id, layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                                          alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1, size: bounds.size)
        }
    }

    // MARK: - 讀取

    /// Dock 在螢幕的哪一邊（系統設定 → 桌面與 Dock 的「位置」），只檢查那一邊，其他點擊不去讀 Dock
    private static func dockEdge() -> String {
        UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
    }

    /// 事件座標是左上角為原點的全域座標，和「輔助使用」一樣
    private static func nearScreenEdge(_ point: CGPoint) -> Bool {
        let edge = dockEdge()
        guard let primary = NSScreen.screens.first else { return false }
        let height = primary.frame.height
        return NSScreen.screens.contains { screen in
            // NSScreen 是左下角為原點，換成左上角為原點
            let frame = CGRect(x: screen.frame.minX, y: height - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
            guard frame.contains(point) else { return false }
            switch edge {
            case "left": return point.x <= frame.minX + edgeBand
            case "right": return point.x >= frame.maxX - edgeBand
            default: return point.y >= frame.maxY - edgeBand
            }
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    /// 滑鼠下的 Dock App 圖示是哪個執行中的 App；不是 App 圖示、沒在執行、或是本 App 時為 nil。
    /// 在主執行緒上逐項問 Dock：一次查詢出錯（Dock 沒回應）就整個放棄，不會每項都等滿上限
    private static func dockApp(at point: CGPoint) -> pid_t? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let element = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.2)
        guard let list = (attribute(element, kAXChildrenAttribute) as? [AXUIElement])?.first,
              let items = attribute(list, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for item in items {
            var subrole: AnyObject?
            guard AXUIElementCopyAttributeValue(item, kAXSubroleAttribute as CFString, &subrole) == .success else { return nil }
            guard subrole as? String == "AXApplicationDockItem" else { continue }
            guard let frame = frame(of: item) else { return nil }
            guard frame.contains(point) else { continue }
            guard let url = attribute(item, kAXURLAttribute) as? URL else { return nil }
            // 比對路徑：Dock 給的網址結尾有斜線（…/TextEdit.app/），URL 直接比會不相等
            let path = url.resolvingSymlinksInPath().path
            let pid = NSWorkspace.shared.runningApplications.first { $0.bundleURL?.resolvingSymlinksInPath().path == path }?.processIdentifier
            // 本 App 開著設定視窗時也會出現在 Dock，不縮自己的視窗
            return pid == getpid() ? nil : pid
        }
        return nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    private static func windows(of pid: pid_t) -> [AXUIElement] {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.3)
        let windows = attribute(element, kAXWindowsAttribute) as? [AXUIElement] ?? []
        // 子元素不會沿用 App 元素的等待上限
        for window in windows { AXUIElementSetMessagingTimeout(window, 0.3) }
        return windows
    }

    /// nil：問不到（那個 App 很慢或沒回應、逾時）。問不到不能當成沒縮，否則還縮著的視窗會被移出紀錄、再也叫不回來
    /// 視窗已經關掉（invalidUIElement）算沒縮，紀錄會作廢
    private static func isMinimized(_ window: AXUIElement) -> Bool? {
        var value: AnyObject?
        switch AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) {
        case .success: return value as? Bool
        case .invalidUIElement: return false
        default: return nil
        }
    }
}

private func dockClickCallback(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo _: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let location = event.location
    let modified = !event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty
    let clickState = event.getIntegerValueField(.mouseEventClickState)
    MainActor.assumeIsolated {
        // NSEvent 的時間是開機後秒數，和 systemUptime 同一個時鐘（CGEvent.timestamp 在 Apple 晶片上的單位不是奈秒，不直接用）
        let time = NSEvent(cgEvent: event)?.timestamp ?? ProcessInfo.processInfo.systemUptime
        DockClickController.shared.handle(type, location: location, modified: modified, clickState: clickState, time: time)
    }
    return Unmanaged.passUnretained(event)
}
