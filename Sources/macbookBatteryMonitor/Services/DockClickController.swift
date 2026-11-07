import AppKit
import ApplicationServices
import OSLog

/// 點 Dock 圖示縮到 Dock（判斷在 DockClick）。只監聽滑鼠（listenOnly），不攔截，Dock 原本的點擊與拖曳都照常。
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
        var front: pid_t?
        var clicked: pid_t?
        var hadVisibleWindows: Bool
        var minimizedByUs: Bool
    }
    /// 我們縮下去、還沒叫回的視窗；再點一次時只叫回這些
    private var minimizedByUs: [pid_t: [AXUIElement]] = [:]
    private var press: Press?
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
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
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
    }

    fileprivate func handle(_ type: CGEventType, location: CGPoint, modified: Bool, clickState: Int64) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port, AXIsProcessTrusted() { CGEvent.tapEnable(tap: port, enable: true) }
        case .leftMouseDown:
            press = nil
            // ⌘ 點（在 Finder 顯示）、⌥ 點（隱藏其他）等 Dock 自己的操作不插手；
            // 雙擊背景 App 的圖示時，第二下它已經在最前面，不能當成「再點一次最前面的 App」
            guard !modified, clickState <= 1, Self.nearScreenEdge(location) else { return }
            let front = NSWorkspace.shared.frontmostApplication
            let clicked = Self.dockApp(at: location)
            // 只有點到最前面那個 App 時才需要知道它有沒有開著的視窗
            let visible = clicked != nil && clicked == front?.processIdentifier && front.map(Self.hasVisibleWindows) == true
            let ours = clicked.map { pid in (minimizedByUs[pid] ?? []).contains(where: Self.isMinimized) } ?? false
            press = Press(location: location, front: front?.processIdentifier, clicked: clicked, hadVisibleWindows: visible, minimizedByUs: ours)
        case .leftMouseUp:
            guard let press else { return }
            self.press = nil
            let distance = hypot(location.x - press.location.x, location.y - press.location.y)
            let action = DockClick.decide(frontAppAtMouseDown: press.front, clickedApp: press.clicked,
                                          hadVisibleWindows: press.hadVisibleWindows, dragDistance: distance, mode: mode,
                                          minimizedByUs: press.minimizedByUs)
            guard action != .none, let pid = press.clicked else { return }
            // 讓 Dock 先處理完這次點擊，再收起來
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MainActor.assumeIsolated { DockClickController.shared.perform(action, pid: pid) } }
        default:
            return
        }
    }

    private func perform(_ action: DockClick.Action, pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            minimizedByUs[pid] = nil
            return
        }
        switch action {
        case .none: return
        case .hide: app.hide()
        case .minimize:
            let shown = Self.windows(of: pid).filter { !Self.isMinimized($0) }
            for window in shown { AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) }
            // 和之前縮下去、還沒叫回的合併，「再點一次」才全部叫得回來
            let merged = (minimizedByUs[pid] ?? []).filter(Self.isMinimized) + shown
            minimizedByUs[pid] = merged.isEmpty ? nil : merged
        case .restore:
            for window in minimizedByUs.removeValue(forKey: pid) ?? [] where Self.isMinimized(window) {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
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
        return attribute(element, kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        attribute(window, kAXMinimizedAttribute) as? Bool ?? false
    }

    private static func hasVisibleWindows(_ app: NSRunningApplication) -> Bool {
        !app.isHidden && windows(of: app.processIdentifier).contains { !isMinimized($0) }
    }
}

private func dockClickCallback(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo _: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let location = event.location
    let modified = !event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty
    let clickState = event.getIntegerValueField(.mouseEventClickState)
    MainActor.assumeIsolated { DockClickController.shared.handle(type, location: location, modified: modified, clickState: clickState) }
    return Unmanaged.passUnretained(event)
}
