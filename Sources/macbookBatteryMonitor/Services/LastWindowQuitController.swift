import AppKit
import ApplicationServices
import OSLog

/// 關閉最後一個視窗時自動結束 App（判斷在 LastWindowQuit）。只監聽最前面那個 App 的視窗建立與關閉，不輪詢；
/// 視窗關掉後等一下（讓 App 做完動畫、或接著開新視窗）再用 WindowServer（跨所有 Space）與「輔助使用」兩邊確認。
/// 需要「輔助使用」權限
@MainActor
final class LastWindowQuitController {
    static let shared = LastWindowQuitController()
    nonisolated static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "lastWindowQuit")

    /// 例外清單（不自動結束的 App），由 AppDelegate 設定
    var excluded: Set<String> = []
    private(set) var isRunning = false

    private var logic = LastWindowQuit()
    private var tokens: [NSObjectProtocol] = []
    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var pendingCheck: DispatchWorkItem?
    private static let settleDelay: TimeInterval = 0.6
    private static let confirmDelay: TimeInterval = 1.0

    @discardableResult
    func apply(enabled: Bool) -> Bool {
        guard enabled else {
            stop()
            return true
        }
        guard AXIsProcessTrusted() else { return false }
        guard !isRunning else { return true }
        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        tokens = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { if let app { LastWindowQuitController.shared.observe(app) } }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated { if let pid { LastWindowQuitController.shared.logic.forget(pid: pid) } }
            },
        ]
        if let front = NSWorkspace.shared.frontmostApplication { observe(front) }
        Self.log.notice("開始監聽最後一個視窗")
        return true
    }

    private func stop() {
        guard isRunning else { return }
        isRunning = false
        for token in tokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        tokens = []
        pendingCheck?.cancel()
        detach()
        logic = LastWindowQuit()
    }

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != observedPID else { return }
        detach()
        guard app.activationPolicy == .regular, pid != getpid() else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, lastWindowCallback, &created) == .success, let created else { return }
        let element = AXUIElementCreateApplication(pid)
        // 關掉視窗的通知有些 App 不會從 App 物件送出；焦點視窗改變（關掉後焦點移走）也觸發同一個檢查，多檢查一次沒有副作用
        for name in [kAXWindowCreatedNotification, kAXUIElementDestroyedNotification, kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(created, element, name as CFString, nil)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        observedPID = pid
        // 記下現在有幾個視窗：之後才知道「原本有視窗」
        logic.saw(pid: pid, windows: Self.windowCounts(pid).server)
    }

    private func detach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
        observedPID = 0
    }

    fileprivate func windowsChangedForObservedApp() {
        let pid = observedPID
        guard pid != 0 else { return }
        pendingCheck?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { LastWindowQuitController.shared.check(pid) } }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    /// confirming：第一次判斷沒有視窗後 1 秒的再確認。兩次都沒有視窗才結束：切換全螢幕途中系統會短暫回報沒有視窗
    private func check(_ pid: pid_t, confirming: Bool = false) {
        guard isRunning, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
        let counts = Self.windowCounts(pid)
        guard logic.shouldQuit(pid: pid, bundleID: app.bundleIdentifier, serverWindows: counts.server, axWindows: counts.ax,
                               excluded: excluded, isHidden: app.isHidden, isRegularApp: app.activationPolicy == .regular) else {
            logic.saw(pid: pid, windows: max(counts.server, counts.ax))
            return
        }
        guard confirming else {
            let work = DispatchWorkItem { MainActor.assumeIsolated { LastWindowQuitController.shared.check(pid, confirming: true) } }
            pendingCheck = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmDelay, execute: work)
            return
        }
        Self.log.notice("最後一個視窗關閉，結束 \(app.bundleIdentifier ?? "?", privacy: .public)")
        logic.forget(pid: pid)
        app.terminate()
    }

    /// 兩邊各算一次視窗數。WindowServer 跨所有 Space、包括縮到 Dock 的，只算真的視窗；
    /// 「輔助使用」算 App 自己回報的所有視窗（含對話框，多算只會讓它不結束）。讀不到時當作還有視窗
    private static func windowCounts(_ pid: pid_t) -> (server: Int, ax: Int) {
        let displays = SkyLight.displays()
        let current = Set(displays.compactMap(\.current))
        let server = SkyLight.windows(in: displays.flatMap(\.spaces), ownedBy: [pid])
            .filter { WindowCandidacy.of($0, visibleSpaces: current) == .listed }.count
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return (server, 1) }
        // 查不到任何 Space（私有查詢不能用）時不能相信 0
        return (displays.isEmpty ? 1 : server, windows.count)
    }
}

/// 被關掉的視窗已經銷毀，不從它讀 pid；只監聽最前面那一個 App，用它的 pid
private func lastWindowCallback(observer _: AXObserver, element _: AXUIElement, notification _: CFString, refcon _: UnsafeMutableRawPointer?) {
    MainActor.assumeIsolated { LastWindowQuitController.shared.windowsChangedForObservedApp() }
}
