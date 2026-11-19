import AppKit
import ApplicationServices
import OSLog

/// 綠色按鈕改成填滿（計算在 WindowMaximize）。左鍵按下時先問 WindowServer 滑鼠底下是哪個視窗，點在它左上角紅黃綠按鈕那一塊才問那個 App
/// 點到的是什麼，是視窗的全螢幕（綠色）按鈕才接手：攔下按下與放開，把視窗帶到最前面，按系統「視窗」選單的「填滿」，
/// 已填滿時按「返回上一個大小」（系統動畫，填滿視窗所在的螢幕）；選單沒有這些項目的 App 改用 App 自己的縮放。
/// macOS 14 沒有這些選單項目：照原本自己算大小填滿（沒有系統動畫）。
/// 全螢幕中的視窗與不能改大小的視窗照系統原本的行為（替它按下按鈕）。按著 Option 時照系統原本的 Option 點。
/// 查詢在自己的執行緒上做，最多等 15 毫秒，來不及就當作不是綠色按鈕、照常放行，不會拖慢點擊。
/// 等待上限設在各 App 的物件上；設在系統層級的物件上會變成整個 App 所有查詢的預設上限。需要「輔助使用」權限
@MainActor
final class WindowMaximizeController {
    static let shared = WindowMaximizeController()
    nonisolated static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "windowMaximize")

    private let tap = WindowMaximizeTap()
    private var activationObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?

    private func updateFrontApp() {
        tap.setFrontApp(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
    }
    private var memory = WindowMaximize()
    private var watchdog: Timer?

    var isRunning: Bool { tap.isRunning }

    @discardableResult
    func apply(enabled: Bool) -> Bool {
        // 沒有權限（包括被收回）時也停掉；重新允許後 AppDelegate 的定時檢查會再呼叫這裡重新開始
        guard enabled, AXIsProcessTrusted() else {
            watchdog?.invalidate()
            watchdog = nil
            tap.stop()
            for observer in [activationObserver, terminationObserver].compactMap({ $0 }) {
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
            }
            activationObserver = nil
            terminationObserver = nil
            // 停用期間結束的 App 收不到通知；pid 之後可能被別的 App 用，記錄一起清掉
            withoutFill.removeAll()
            return !enabled
        }
        if activationObserver == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { _ in MainActor.assumeIsolated { WindowMaximizeController.shared.updateFrontApp() } }
            terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
            ) { note in
                guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
                MainActor.assumeIsolated { _ = WindowMaximizeController.shared.withoutFill.remove(pid) }
            }
        }
        updateFrontApp()
        if tap.onButton == nil {
            // 只設定一次：攔截執行緒讀的時候不會讀到改到一半的值
            tap.onButton = { button in
                DispatchQueue.main.async { MainActor.assumeIsolated { WindowMaximizeController.shared.toggle(button) } }
            }
        }
        if !tap.isRunning {
            // 被暫停或作廢的攔截先清掉再重建
            tap.stop()
            let started = tap.start()
            Self.log.notice("綠色按鈕放大：\(started ? "開始" : "失敗", privacy: .public)")
        }
        if watchdog == nil {
            watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                MainActor.assumeIsolated { WindowMaximizeController.shared.tap.keepAlive() }
            }
        }
        return tap.isRunning
    }

    private func toggle(_ button: AXUIElement) {
        AXUIElementSetMessagingTimeout(button, 0.2)
        // 按鈕停用（例如不能放大的視窗）：系統本來也不會有反應
        guard Self.attribute(button, kAXEnabledAttribute) as? Bool != false, let window = Self.window(of: button) else { return }
        AXUIElementSetMessagingTimeout(window, 0.2)
        var sizeSettable: DarwinBoolean = false
        // 全螢幕中（要離開全螢幕）或不能改大小的視窗：照系統原本的行為按下去
        if Self.attribute(window, "AXFullScreen") as? Bool == true
            || AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &sizeSettable) != .success || !sizeSettable.boolValue {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
            return
        }
        guard let frame = Self.frame(of: window), let visible = Self.visibleFrame(containing: frame) else { return }
        let id = AX.windowID(of: window) ?? 0
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return }
        let wasFront = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        // 原生點背景視窗的綠色按鈕會把它帶到最前面；攔下點擊後要自己做。系統的「填滿」只對最前面的 App 的主視窗有效，
        // 點的是同一個 App 的另一個視窗時也要先把它設成主視窗
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        NSRunningApplication(processIdentifier: pid)?.activate()
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        // 上次縮放跳到別的螢幕、改成自己填滿的視窗：這次也自己還原
        if pinned.remove(id) != nil { return Self.move(window, to: memory.toggle(window: id, frame: frame, visible: visible)) }
        // macOS 14 沒有「填滿」：照原本自己算大小
        guard #available(macOS 15, *) else { return Self.move(window, to: memory.toggle(window: id, frame: frame, visible: visible)) }
        // 已知選單沒有「填滿」的 App（例如 Qt）：不再掃選單列
        if withoutFill.contains(pid) { return zoom(button: button, window: window, id: id, frame: frame, visible: visible) }
        tileGeneration &+= 1
        // 剛被帶到最前面的 App 選單項目還是停用的，要等一下；本來就在最前面就不用等
        systemTile(app: app, button: button, window: window, id: id, frame: frame, visible: visible,
                   generation: tileGeneration, triesLeft: wasFront ? 0 : 8)
    }

    /// 系統「視窗」選單的「填滿」和「移動與調整大小 → 返回上一個大小」（macOS 15 起每個 AppKit App 都有，代號不受語言影響）：
    /// 和自己點選單一樣是系統動畫，填滿視窗所在的螢幕
    private static let fillItem = "_zoomFill:", untileItem = "_zoomUntile:"
    /// 每次點擊加一：重試途中又點了一次，舊的那串就不再做
    private var tileGeneration = 0
    /// 選單沒有「填滿」的 App：直接用 App 自己的縮放，不必每次點都掃一遍選單列。App 結束時拿掉（pid 會被重複使用）
    private var withoutFill: Set<pid_t> = []

    /// 「返回上一個大小」能按代表視窗是系統排過的（例如上次填滿的）就還原，否則填滿。
    /// 用系統的狀態判斷，不看視窗大小：外接螢幕的選單列不算在可用範圍裡，填滿後的大小和可用範圍對不上。
    /// 選單項目停用（App 還沒到最前面）時每 0.05 秒再試，最多約 0.4 秒；沒有這些項目（例如 Qt）或一直停用就改用 App 自己的縮放
    private func systemTile(app: AXUIElement, button: AXUIElement, window: AXUIElement, id: UInt32,
                            frame: CGRect, visible: CGRect, generation: Int, triesLeft: Int) {
        guard generation == tileGeneration else { return }
        let (scanned, menu) = Self.windowMenu(of: app)
        let fill = menu.flatMap { Self.menuItem(Self.fillItem, in: $0, depth: 0) }
        if let fill, Self.attribute(fill, kAXEnabledAttribute) as? Bool == true {
            let untile = menu.flatMap { Self.menuItem(Self.untileItem, in: $0, depth: 0) }
            let target = untile.flatMap { Self.attribute($0, kAXEnabledAttribute) as? Bool == true ? $0 : nil } ?? fill
            let result = AXUIElementPerformAction(target, kAXPressAction as CFString)
            // 逾時（App 做動畫時才回覆）代表已經送到；其他錯誤代表沒按到，點擊已經被攔下，改用縮放才不會什麼都沒發生
            if result != .success, result != .cannotComplete {
                Self.log.notice("按下填滿失敗（\(result.rawValue)），改用縮放")
                zoom(button: button, window: window, id: id, frame: frame, visible: visible)
            }
            return
        }
        // 讀得到選單列卻沒有「填滿」才記住；讀不到（App 忙、逾時）下次再試
        if fill == nil, scanned {
            var pid: pid_t = 0
            if AXUIElementGetPid(app, &pid) == .success { withoutFill.insert(pid) }
        }
        if fill != nil, triesLeft > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                MainActor.assumeIsolated {
                    WindowMaximizeController.shared.systemTile(app: app, button: button, window: window, id: id, frame: frame,
                                                               visible: visible, generation: generation, triesLeft: triesLeft - 1)
                }
            }
            return
        }
        zoom(button: button, window: window, id: id, frame: frame, visible: visible)
    }

    /// 有「填滿」的那個選單（「視窗」選單通常在倒數第二個，從後面找比較快）
    /// 子元素不會沿用 App 元素的等待上限（會用全域預設約 6 秒），所以選單列、選單、選單項目各自設定
    private static let menuTimeout: Float = 0.1

    /// scanned：整條選單列都讀完了，每個查詢不是成功就是「沒有這個值」；有任何逾時或失敗時為 false，不能斷定沒有「填滿」
    private static func windowMenu(of app: AXUIElement) -> (scanned: Bool, menu: AXUIElement?) {
        var complete = true
        guard let bar = menuAttribute(app, kAXMenuBarAttribute, complete: &complete),
              CFGetTypeID(bar) == AXUIElementGetTypeID() else { return (false, nil) }
        let menuBar = bar as! AXUIElement
        AXUIElementSetMessagingTimeout(menuBar, menuTimeout)
        guard let menus = menuAttribute(menuBar, kAXChildrenAttribute, complete: &complete) as? [AXUIElement], !menus.isEmpty else {
            return (false, nil)
        }
        let menu = menus.reversed().first {
            AXUIElementSetMessagingTimeout($0, menuTimeout)
            return menuItem(fillItem, in: $0, depth: 0, complete: &complete) != nil
        }
        return (complete, menu)
    }

    private static func menuItem(_ id: String, in element: AXUIElement, depth: Int) -> AXUIElement? {
        var complete = true
        return menuItem(id, in: element, depth: depth, complete: &complete)
    }

    private static func menuItem(_ id: String, in element: AXUIElement, depth: Int, complete: inout Bool) -> AXUIElement? {
        guard depth < 4, let children = menuAttribute(element, kAXChildrenAttribute, complete: &complete) as? [AXUIElement] else { return nil }
        for child in children {
            AXUIElementSetMessagingTimeout(child, menuTimeout)
            if menuAttribute(child, "AXIdentifier", complete: &complete) as? String == id { return child }
            if let found = menuItem(id, in: child, depth: depth + 1, complete: &complete) { return found }
        }
        return nil
    }

    /// 和 attribute 一樣，但逾時或其他錯誤（不是「沒有這個值」）時把 complete 設成 false
    private static func menuAttribute(_ element: AXUIElement, _ name: String, complete: inout Bool) -> AnyObject? {
        var value: AnyObject?
        switch AXUIElementCopyAttributeValue(element, name as CFString, &value) {
        case .success: return value
        case .noValue, .attributeUnsupported: return nil
        default:
            complete = false
            return nil
        }
    }

    /// App 自己的縮放（和 Option 點綠色按鈕一樣，原生動畫，大小由 App 決定）。
    /// App 做完縮放動畫才回覆，常超過等待上限（回 cannotComplete），但指令已經送到：只有明確不支援才自己填滿（沒有動畫），
    /// 否則會在 App 縮回去的途中又被填滿
    private func zoom(button: AXUIElement, window: AXUIElement, id: UInt32, frame: CGRect, visible: CGRect) {
        let result = AXUIElementPerformAction(button, "AXZoomWindow" as CFString)
        guard result != .actionUnsupported else { return Self.move(window, to: memory.toggle(window: id, frame: frame, visible: visible)) }
        guard id != 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            MainActor.assumeIsolated { WindowMaximizeController.shared.keepOnScreen(window, id: id, original: frame, visible: visible) }
        }
    }

    /// 縮放後跳到別的螢幕的視窗（有些 App 在外接螢幕縮放時用主螢幕算大小）
    private var pinned: Set<UInt32> = []

    /// 縮放做完後視窗跑到別的螢幕：放回原本的螢幕並填滿，下次按自己還原（這種情況沒有動畫，但不會跳螢幕）
    private func keepOnScreen(_ window: AXUIElement, id: UInt32, original: CGRect, visible: CGRect) {
        guard let now = Self.frame(of: window), !visible.contains(CGPoint(x: now.midX, y: now.midY)) else { return }
        pinned.insert(id)
        Self.move(window, to: memory.toggle(window: id, frame: original, visible: visible))
    }

    /// 先移位置再改大小，最後再對一次位置：有些 App 改大小時會自己把視窗推回原位
    private static func move(_ window: AXUIElement, to target: CGRect) {
        set(window, position: target.origin)
        set(window, size: target.size)
        set(window, position: target.origin)
    }

    // MARK: - 「輔助使用」

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func window(of button: AXUIElement) -> AXUIElement? {
        guard let value = attribute(button, kAXWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let position = attribute(window, kAXPositionAttribute), let size = attribute(window, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    private static func set(_ window: AXUIElement, position: CGPoint) {
        var point = position
        if let value = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) }
    }

    private static func set(_ window: AXUIElement, size: CGSize) {
        var extent = size
        if let value = AXValueCreate(.cgSize, &extent) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) }
    }

    /// 視窗中心所在螢幕的可用範圍（不含選單列與 Dock），換成左上角為原點的全域座標
    private static func visibleFrame(containing frame: CGRect) -> CGRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        let height = primary.frame.height
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let converted = NSScreen.screens.map { screen -> (full: CGRect, visible: CGRect) in
            func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: height - r.maxY, width: r.width, height: r.height) }
            return (flip(screen.frame), flip(screen.visibleFrame))
        }
        return (converted.first { $0.full.contains(center) } ?? converted.first)?.visible
    }
}

/// 綠色按鈕的攔截：在自己的高優先執行緒上跑
final class WindowMaximizeTap: @unchecked Sendable {
    private let lock = NSLock()
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    /// 攔下了按下、放開也要攔下（只在攔截執行緒使用）
    private var swallowingUp = false
    /// 最前面的 App 與它的「輔助使用」物件（等待上限 15 毫秒，只設在這個物件上）；只在攔截執行緒讀，換 App 時在鎖裡換
    private var frontApp: (pid: pid_t, element: AXUIElement)?

    func setFrontApp(_ pid: pid_t) {
        locked {
            guard frontApp?.pid != pid else { return }
            guard pid > 0, pid != getpid() else {
                frontApp = nil
                return
            }
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.015)
            frontApp = (pid, element)
        }
    }
    /// 只在攔截還沒啟動時設定
    var onButton: ((AXUIElement) -> Void)?

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var isRunning: Bool {
        guard let port = locked({ self.port }) else { return false }
        return CFMachPortIsValid(port) && CGEvent.tapIsEnabled(tap: port)
    }

    func keepAlive() {
        guard let port = locked({ self.port }) else { return }
        // 權限被撤銷：重新打開只會一直被系統逾時暫停，整台 Mac 的輸入跟著卡。停掉，權限回來後由 AppDelegate 每 5 秒的檢查重新開始
        if !AXIsProcessTrusted() {
            stop()
        } else if !CFMachPortIsValid(port) {
            stop()
            _ = start()
        } else if !CGEvent.tapIsEnabled(tap: port) {
            EventTapAccess.shared.reenable(port)
        }
    }

    func start() -> Bool {
        guard locked({ port }) == nil else { return isRunning }
        let mask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            let loop: CFRunLoop = CFRunLoopGetCurrent()
            guard let port = EventTapAccess.shared.createTap(place: .headInsertEventTap,
                                               mask: mask, callback: windowMaximizeCallback,
                                               userInfo: Unmanaged.passUnretained(self).toOpaque(), loop: loop) else {
                ready.signal()
                return
            }
            CGEvent.tapEnable(tap: port, enable: true)
            locked {
                self.port = port
                self.runLoop = loop
            }
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "綠色按鈕"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return isRunning
    }

    func stop() {
        let (port, loop) = locked { () -> (CFMachPort?, CFRunLoop?) in
            defer {
                self.port = nil
                self.runLoop = nil
            }
            return (self.port, self.runLoop)
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let loop { CFRunLoopStop(loop) }
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout:
            if AXIsProcessTrusted(), let port = locked({ self.port }) { EventTapAccess.shared.reenable(port) }
            return pass
        case .leftMouseDown:
            swallowingUp = false
            // 按著 Option：照系統原本的行為；連點（雙擊標題列等）也不碰
            guard !event.flags.contains(.maskAlternate), event.getIntegerValueField(.mouseEventClickState) <= 1,
                  let onButton else { return pass }
            let point = event.location
            // 先看滑鼠底下是誰的視窗、點的是不是左上角紅黃綠按鈕那一塊：不是就不去問任何 App（一般點擊不打擾 App），
            // 是背景視窗（例如直接點另一個螢幕上的視窗）就問那個 App，不然會照系統原本的行為進入全螢幕
            guard let owner = Self.trafficLightOwner(at: point) else { return pass }
            let front = locked { frontApp }
            let app: AXUIElement
            if let front, front.pid == owner {
                app = front.element
            } else {
                app = AXUIElementCreateApplication(owner)
                AXUIElementSetMessagingTimeout(app, 0.015)
            }
            var element: AXUIElement?
            guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &element) == .success, let element else { return pass }
            // 子元素不會沿用 App 元素的等待上限（預設約 6 秒）：那個 App 剛好卡住時，整台 Mac 的點擊都會等它
            AXUIElementSetMessagingTimeout(element, 0.015)
            var subrole: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success,
                  subrole as? String == kAXFullScreenButtonSubrole as String else { return pass }
            swallowingUp = true
            onButton(element)
            return nil
        case .leftMouseUp:
            guard swallowingUp else { return pass }
            swallowingUp = false
            return nil
        default:
            return pass
        }
    }

    /// 滑鼠底下最上層的一般視窗，點的位置落在它左上角紅黃綠按鈕那一塊時，回傳那個視窗的 App（只問 WindowServer，不打擾 App）
    private static func trafficLightOwner(at point: CGPoint) -> pid_t? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for info in list where info[kCGWindowLayer as String] as? Int == 0 {
            guard let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict), bounds.contains(point) else { continue }
            // 最上層的視窗就是點到的那個：不在按鈕那一塊就不是綠色按鈕
            guard WindowMaximize.isNearTrafficLights(point, window: bounds),
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != getpid() else { return nil }
            return pid
        }
        return nil
    }
}

private func windowMaximizeCallback(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<WindowMaximizeTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}
