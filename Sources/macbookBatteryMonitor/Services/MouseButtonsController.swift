import AppKit
import OSLog

/// 滑鼠側鍵（判斷在 MouseButtons）。只攔「其他按鈕」（左右鍵不在範圍），而且只接手設定了動作的第 4、5 鍵：
/// 按下時送出對應的快捷鍵、放開也攔下；其他按鈕照常交給 App。沒設定任何動作時不攔截。需要「輔助使用」權限
@MainActor
final class MouseButtonsController {
    static let shared = MouseButtonsController()
    nonisolated static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "mouseButtons")
    /// 自己送出的快捷鍵帶這個標記（看得到的話直接放行）
    private static let postedMark: Int64 = 0x4D42_5554_544E // "MBUTTN"

    private var buttons = MouseButtons(back: .none, forward: .none)
    private var port: CFMachPort?
    private var watchdog: Timer?
    /// 按下時被接手的按鈕：放開時也要攔下
    private var swallowed = Set<Int64>()

    var isRunning: Bool { port.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } ?? false }

    @discardableResult
    func apply(_ new: MouseButtons) -> Bool {
        buttons = new
        guard new.isActive else {
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
        let mask: CGEventMask = (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
        guard let port = EventTapAccess.shared.createTap(place: .headInsertEventTap,
                                           mask: mask, callback: mouseButtonsCallback, userInfo: nil, loop: CFRunLoopGetMain()) else { return false }
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated {
                MouseButtonsController.shared.keepAlive()
            }
        }
        Self.log.notice("開始攔截滑鼠側鍵")
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
            apply(buttons)
        } else if !CGEvent.tapIsEnabled(tap: port) {
            EventTapAccess.shared.reenable(port)
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
        swallowed = []
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let number = event.getIntegerValueField(.mouseEventButtonNumber)
        switch type {
        case .otherMouseDown:
            // 按著修飾鍵時照原本的按鍵放行（其他 App 可能有自己的組合）
            guard event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty,
                  let action = buttons.action(forButton: Int(number)), let shortcut = action.shortcut else { return false }
            // 「上一頁、下一頁」送給最前面的 App：游標下不是它的視窗時放行原本的按鍵；Mission Control 不分 App
            if action != .missionControl, !Self.pointerOverFrontApp(event.location) { return false }
            swallowed.insert(number)
            Self.post(shortcut)
            return true
        case .otherMouseUp:
            return swallowed.remove(number) != nil
        default:
            return false
        }
    }

    fileprivate func reenable() {
        if let port, AXIsProcessTrusted() { EventTapAccess.shared.reenable(port) }
    }

    private static func pointerOverFrontApp(_ point: CGPoint) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let windows = list.compactMap { info -> MouseButtons.Window? in
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) }) else { return nil }
            return MouseButtons.Window(pid: pid, layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0, bounds: bounds)
        }
        return MouseButtons.pointerOverFrontApp(point, windows: windows, front: front)
    }

    /// 送給最前面的 App，和按鍵盤一樣
    private static func post(_ shortcut: MouseButtons.Shortcut) {
        let source = CGEventSource(stateID: .privateState)
        var flags = CGEventFlags()
        if shortcut.command { flags.insert(.maskCommand) }
        if shortcut.control { flags.insert(.maskControl) }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: postedMark)
            event.post(tap: .cgSessionEventTap)
        }
    }
}

private func mouseButtonsCallback(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo _: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    MainActor.assumeIsolated {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            MouseButtonsController.shared.reenable()
            return Unmanaged.passUnretained(event)
        }
        return MouseButtonsController.shared.handle(type, event) ? nil : Unmanaged.passUnretained(event)
    }
}
