import AppKit
import ApplicationServices
import Carbon
import OSLog
import SwiftUI

/// ⌘Q／⌘W 防誤觸（判斷在 QuitGuard）。按鍵攔截在自己的執行緒上跑；按滿時間後把 ⌘Q／⌘W 直接送給按下時最前面的
/// 那個 App（CGEvent.postToPid），不是送給當下最前面的 App，所以中途換了視窗也不會關錯。
/// ⌘W 再多確認一次：那個 App 有焦點的視窗沒換過。需要「輔助使用」權限；沒加入或開關都關掉時完全不攔截
@MainActor
final class QuitGuardController {
    static let shared = QuitGuardController()
    nonisolated static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "quitGuard")

    private let tap = QuitGuardTap()
    private var frameTimer: Timer?
    private var watchdog: Timer?
    private var activationObserver: NSObjectProtocol?
    private var hud: NSPanel?
    private let progress = HoldProgress()
    /// ⌘W 按下時那個 App 有焦點的視窗；送出前比對
    private var focusedWindow: AXUIElement?

    var isRunning: Bool { tap.isRunning }

    /// 開始或停止攔截；需要攔截但沒有權限時回傳 false
    @discardableResult
    func apply(quit: Bool, close: Bool, duration: Double) -> Bool {
        tap.configure(quit: quit, close: close, duration: duration)
        guard quit || close else {
            stop()
            return true
        }
        // 權限被收回：舊的攔截已經收不到事件，停掉；重新允許後 AppDelegate 的定時檢查會再呼叫這裡重新開始
        guard AXIsProcessTrusted() else {
            stop()
            return false
        }
        KeyboardLetters.shared.start()
        if activationObserver == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { _ in MainActor.assumeIsolated { QuitGuardController.shared.updateFrontApp() } }
        }
        updateFrontApp()
        if tap.onBegin == nil {
            // 只設定一次、之後不再改：攔截執行緒讀的時候不會讀到改到一半的值
            tap.onBegin = { kind, app in
                DispatchQueue.main.async { MainActor.assumeIsolated { QuitGuardController.shared.began(kind, app: app) } }
            }
        }
        if !tap.isRunning {
            // 被暫停或作廢的攔截先清掉再重建
            tap.stop()
            let started = tap.start()
            Self.log.notice("⌘Q／⌘W 防誤觸攔截：\(started ? "開始" : "失敗", privacy: .public)")
        }
        if watchdog == nil {
            // 和其他攔截一樣：系統可能暫停或作廢攔截，每 5 秒檢查一次
            watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                MainActor.assumeIsolated { QuitGuardController.shared.tap.keepAlive() }
            }
        }
        return tap.isRunning
    }

    private func stop() {
        watchdog?.invalidate()
        watchdog = nil
        tap.stop()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        finish()
    }

    private func updateFrontApp() {
        // 我們自己的視窗不攔：要問自己「輔助使用」會等到逾時，而且主執行緒正在等
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        tap.setFrontApp(front == getpid() ? 0 : front)
    }

    private func began(_ kind: QuitGuard.Kind, app: pid_t) {
        guard let running = NSRunningApplication(processIdentifier: app) else { return }
        focusedWindow = kind == .close ? Self.focusedWindow(of: app) : nil
        progress.text = kind == .quit ? "繼續按住 ⌘Q 結束「\(running.localizedName ?? "App")」" : "繼續按住 ⌘W 關閉"
        progress.value = 0
        showHUD()
        frameTimer?.invalidate()
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
            MainActor.assumeIsolated { QuitGuardController.shared.tick() }
        }
    }

    private func tick() {
        updateFrontApp()
        switch tap.poll(now: CACurrentMediaTime()) {
        case let .holding(value): progress.value = value
        case .cancelled: finish()
        case let .completed(hold):
            // 先送出再收尾：收尾會清掉按下時記住的焦點視窗
            send(hold)
            finish()
        }
    }

    private func send(_ hold: QuitGuard.Hold) {
        // 送出前再確認一次：最前面還是它；⌘W 時有焦點的視窗也沒換
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == hold.app else { return }
        if hold.kind == .close {
            guard let window = focusedWindow, let now = Self.focusedWindow(of: hold.app), CFEqual(window, now) else {
                Self.log.notice("⌘W 焦點視窗已改變，取消")
                return
            }
        }
        tap.post(keyCode: hold.kind == .quit ? QuitGuard.quitKey : QuitGuard.closeKey, to: hold.app)
    }

    private func finish() {
        frameTimer?.invalidate()
        frameTimer = nil
        focusedWindow = nil
        hud?.orderOut(nil)
    }

    private static func focusedWindow(of app: pid_t) -> AXUIElement? {
        var value: CFTypeRef?
        let element = AXUIElementCreateApplication(app)
        // 在主執行緒上問，App 沒回應時最多等 0.1 秒（預設要等好幾秒）
        AXUIElementSetMessagingTimeout(element, 0.1)
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// 畫面正中央的進度環；不搶焦點、滑鼠點不到
    private func showHUD() {
        let panel = hud ?? {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 150), styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: true)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.ignoresMouseEvents = true
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.contentView = NSHostingView(rootView: HoldHUD(progress: progress))
            hud = panel
            return panel
        }()
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - panel.frame.width / 2, y: screen.frame.midY - panel.frame.height / 2))
        }
        panel.orderFrontRegardless()
    }
}

@MainActor
@Observable
private final class HoldProgress {
    var value = 0.0
    var text = ""
}

private struct HoldHUD: View {
    let progress: HoldProgress

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 6)
                Circle().trim(from: 0, to: progress.value)
                    .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 54, height: 54)
            Text(progress.text)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(width: 260, height: 150)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black.opacity(0.72)))
        .accessibilityElement(children: .combine)
    }
}

/// 按鍵攔截：在自己的高優先執行緒上跑，判斷用的狀態都在鎖裡
final class QuitGuardTap: @unchecked Sendable {
    /// 自己送出的 ⌘Q／⌘W 帶這個標記，攔截時直接放行
    private static let postedMark: Int64 = 0x5147_5541_5244 // "QGUARD"

    enum Poll { case holding(Double), cancelled, completed(QuitGuard.Hold) }

    private let lock = NSLock()
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    private var logic = QuitGuard(holdQuit: false, holdClose: false, duration: 1)
    private var frontApp: pid_t = 0
    /// 只在攔截還沒啟動時設定
    var onBegin: ((QuitGuard.Kind, pid_t) -> Void)?

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var isRunning: Bool {
        guard let port = locked({ self.port }) else { return false }
        return CFMachPortIsValid(port) && CGEvent.tapIsEnabled(tap: port)
    }

    func configure(quit: Bool, close: Bool, duration: Double) {
        locked {
            logic.holdQuit = quit
            logic.holdClose = close
            logic.duration = duration
        }
    }

    func setFrontApp(_ pid: pid_t) { locked { frontApp = pid } }

    func poll(now: Double) -> Poll {
        locked {
            guard logic.holding != nil else { return .cancelled }
            if let hold = logic.complete(now: now, frontApp: frontApp) { return .completed(hold) }
            return logic.holding == nil ? .cancelled : .holding(logic.progress(now: now))
        }
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
            CGEvent.tapEnable(tap: port, enable: true)
        }
    }

    func post(keyCode: Int, to pid: pid_t) {
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down) else { continue }
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: Self.postedMark)
            event.postToPid(pid)
        }
    }

    func start() -> Bool {
        guard locked({ port }) == nil else { return isRunning }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                               eventsOfInterest: mask, callback: quitGuardCallback,
                                               userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
                ready.signal()
                return
            }
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            locked {
                self.port = port
                self.runLoop = loop
            }
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "⌘Q 防誤觸"
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
                // 停止時完全重設：之後重新開始時不會記著舊的按鍵
                logic = QuitGuard(holdQuit: logic.holdQuit, holdClose: logic.holdClose, duration: logic.duration)
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
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // 暫停期間可能漏掉放開：放棄這次按住
            locked { logic.cancelHold() }
            if type == .tapDisabledByTimeout, AXIsProcessTrusted(), let port = locked({ self.port }) { CGEvent.tapEnable(tap: port, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.postedMark { return pass }
        // 密碼欄等安全輸入：不開始新的按住；放開還是要處理，否則之前攔下的鍵狀態會卡住
        if IsSecureEventInputEnabled(), type != .keyUp { return pass }
        let flags = event.flags
        // 鍵碼是 US 的位置：字母不在那個位置的配置（AZERTY、Dvorak）不當成 Q、W，免得保護到別的快捷鍵
        let rawCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let keyCode = KeyLayout.usKeyCode(rawCode, character: KeyboardLetters.shared.letter(at: rawCode)) ?? -1
        let input: QuitGuard.Event
        switch type {
        case .keyDown:
            input = .keyDown(keyCode: keyCode, command: flags.contains(.maskCommand),
                             otherModifiers: !flags.intersection([.maskShift, .maskControl, .maskAlternate]).isEmpty,
                             isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                             time: CACurrentMediaTime(), frontApp: locked { frontApp },
                             switcherOpen: InputTap.shared.activeHold() != nil)
        case .keyUp:
            // 放開不看字：按下時攔下的是哪個鍵碼，放開就認那個鍵碼，狀態才不會卡住
            input = .keyUp(keyCode: rawCode)
        case .flagsChanged where !flags.contains(.maskCommand):
            input = .commandReleased
        default:
            return pass
        }
        let (action, began) = locked { () -> (QuitGuard.Action, QuitGuard.Hold?) in
            let before = logic.holding
            let action = logic.handle(input)
            // 新的一次按住（包括 ⌘W 換成 ⌘Q）：通知主執行緒更新提示與記住的視窗
            return (action, logic.holding != before ? logic.holding : nil)
        }
        if let began { onBegin?(began.kind, began.app) }
        return action == .swallow ? nil : pass
    }
}

private func quitGuardCallback(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<QuitGuardTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}
