import AppKit
import ApplicationServices
import OSLog

/// 分開設定滑鼠與觸控板的捲動方向。macOS 的「自然捲動」是兩者共用一個設定，這裡攔截捲動事件，
/// 把選了「反向」的那一種的方向反過來（例如觸控板維持自然捲動、滑鼠滾輪改回傳統方向）。
/// 兩指以上在觸控板上捲動算觸控板，其他（一般滾輪、Magic Mouse）算滑鼠。
/// 攔截並修改事件需要「輔助使用」權限；沒有開任何反向時完全不攔截
@MainActor
final class ScrollDirection {
    static let shared = ScrollDirection()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    fileprivate var reverseMouse = false
    fileprivate var reverseTrackpad = false
    /// 最近一次觸控板上有兩指以上的時間；捲動在這之後 0.3 秒內開始就算觸控板
    private var lastTrackpadTouches: TimeInterval = 0
    /// 一段捲動（含放開手指後的慣性）從頭到尾算同一種裝置
    private var currentIsTrackpad = false
    /// 開發用：`defaults write com.kuan.batterymonitor scrollDebug -bool true` 後重新打開 App，每個捲動事件的判斷與改寫前後的值
    /// 會寫進系統記錄（`log stream --predicate 'subsystem == "com.kuan.batterymonitor" AND category == "scroll"'`）
    private var debug = false
    private var lastLoggedTouches = -1
    private static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "scroll")

    /// 有沒有「輔助使用」權限
    static var trusted: Bool { AXIsProcessTrusted() }

    var isRunning: Bool { tap != nil }

    /// 依設定開始或停止攔截；需要攔截但沒有權限時回傳 false
    @discardableResult
    func apply(reverseMouse: Bool, reverseTrackpad: Bool) -> Bool {
        self.reverseMouse = reverseMouse
        self.reverseTrackpad = reverseTrackpad
        debug = UserDefaults.standard.bool(forKey: "scrollDebug")
        guard reverseMouse || reverseTrackpad else {
            stop()
            return true
        }
        if tap == nil, Self.trusted { start() }
        return tap != nil
    }

    /// 跳出系統的詢問，請使用者到「輔助使用」打開這個 App
    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func start() {
        // 觸控板手指的事件（NSEvent.EventType.gesture，數值 29）用來分辨是不是觸控板
        let mask: CGEventMask = (1 << CGEventType.scrollWheel.rawValue) | (1 << 29)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: scrollTapCallback, userInfo: nil) else { return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    private func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    fileprivate func lastTrackpadTouchesForTest() { lastTrackpadTouches = CACurrentMediaTime() }
    fileprivate func resetTouchesForTest() { lastTrackpadTouches = 0 }

    /// 系統覺得回呼太慢或使用者操作時會暫停攔截，再打開
    fileprivate func reenable() {
        if debug { Self.log.notice("事件攔截被系統暫停，重新打開") }
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent {
        let now = CACurrentMediaTime()
        if type.rawValue == 29 {
            let count = NSEvent(cgEvent: event)?.touches(matching: .touching, in: nil).count ?? 0
            if count >= 2 { lastTrackpadTouches = now }
            if debug, count != lastLoggedTouches {
                lastLoggedTouches = count
                Self.log.notice("手指事件：\(count) 指")
            }
            return event
        }
        guard type == .scrollWheel else { return event }
        // 新的一段捲動才重新判斷裝置；放開手指後的慣性沿用
        if event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0 {
            let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            currentIsTrackpad = continuous && now - lastTrackpadTouches < 0.3
        }
        if debug { logScroll(event, label: "收到") }
        guard currentIsTrackpad ? reverseTrackpad : reverseMouse else { return event }
        let axes: [(CGEventField, CGEventField, CGEventField)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1),
            (.scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2),
        ]
        for (lines, points, fixed) in axes {
            // 先讀出原本的值再寫：改行數時系統會順便重算像素與精細值
            let original = (event.getIntegerValueField(lines), event.getIntegerValueField(points), event.getDoubleValueField(fixed))
            event.setIntegerValueField(lines, value: -original.0)
            event.setIntegerValueField(points, value: -original.1)
            event.setDoubleValueField(fixed, value: -original.2)
        }
        if debug { logScroll(event, label: "改成") }
        return event
    }

    private func logScroll(_ event: CGEvent, label: String) {
        let lines = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let points = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let fixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let ns = NSEvent(cgEvent: event)
        Self.log.notice("""
            \(label, privacy: .public) \(self.currentIsTrackpad ? "觸控板" : "滑鼠", privacy: .public) \
            連續=\(event.getIntegerValueField(.scrollWheelEventIsContinuous)) \
            階段=\(event.getIntegerValueField(.scrollWheelEventScrollPhase)) 慣性=\(event.getIntegerValueField(.scrollWheelEventMomentumPhase)) \
            行=\(lines) 點=\(points) 精細=\(fixed) NSEvent=\(ns.map { "\($0.scrollingDeltaY)" } ?? "-", privacy: .public)
            """)
    }
}

extension ScrollDirection {
    /// 開發用：`--selftest-scroll` 造出滾輪、觸控板、慣性與 Magic Mouse 的捲動事件，走同一段判斷，印出有沒有反向（不需要權限）
    func selfTest() {
        func scroll(continuous: Bool, momentum: Int64 = 0, touchesJustNow: Bool) -> String {
            if touchesJustNow { lastTrackpadTouchesForTest() }
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 10, wheel2: 4, wheel3: 0) else { return "無法建立事件" }
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
            let out = handle(.scrollWheel, event)
            let v = out.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), h = out.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            return v < 0 && h < 0 ? "反向" : v > 0 && h > 0 ? "不變" : "異常（\(v), \(h)）"
        }
        for (mouse, trackpad) in [(true, false), (false, true), (true, true)] {
            reverseMouse = mouse
            reverseTrackpad = trackpad
            print("selftest-scroll: 滑鼠反向 \(mouse)、觸控板反向 \(trackpad)")
            print("  一般滾輪：\(scroll(continuous: false, touchesJustNow: false))")
            print("  觸控板兩指：\(scroll(continuous: true, touchesJustNow: true))")
            print("  觸控板放開後的慣性：\(scroll(continuous: true, momentum: 1, touchesJustNow: false))")
            resetTouchesForTest()
            print("  Magic Mouse（連續、沒有兩指）：\(scroll(continuous: true, touchesJustNow: false))")
        }
        reverseMouse = false
        reverseTrackpad = false
    }
}

/// 事件攔截的回呼：加在主執行緒的 run loop 上，所以在主執行緒執行
private func scrollTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                               userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    MainActor.assumeIsolatedCompat {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            ScrollDirection.shared.reenable()
            return Unmanaged.passUnretained(event)
        }
        return Unmanaged.passUnretained(ScrollDirection.shared.handle(type, event))
    }
}
