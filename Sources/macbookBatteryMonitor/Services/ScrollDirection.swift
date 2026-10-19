import AppKit
import ApplicationServices
import OSLog

/// 分開設定滑鼠與觸控板的捲動方向。macOS 的「自然捲動」是兩者共用一個設定，這裡攔截捲動事件，
/// 把選了「反向」的那一種的方向反過來（例如觸控板維持自然捲動、滑鼠滾輪改回傳統方向）。
/// 兩指以上在觸控板上捲動算觸控板，其他（一般滾輪、Magic Mouse）算滑鼠。
/// 攔截並修改事件需要「輔助使用」權限；沒有開任何反向時完全不攔截。
/// 攔截本身在 ScrollTap 自己的執行緒上跑，這裡負責開關與每 5 秒的檢查
@MainActor
final class ScrollDirection {
    static let shared = ScrollDirection()

    private let tap = ScrollTap()
    private var wanted = false
    private var watchdog: Timer?
    /// 上次記錄的權限狀態；改變時才留紀錄
    private var loggedTrust: Bool?
    /// 攔截開始或停止、權限改變時通知（設定頁的狀態跟著更新）
    var onChange: (() -> Void)?

    /// 有沒有「輔助使用」權限
    static var trusted: Bool { AXIsProcessTrusted() }

    var isRunning: Bool { tap.isRunning }

    /// 依設定開始或停止攔截；需要攔截但沒有權限時回傳 false
    @discardableResult
    func apply(reverseMouse: Bool, reverseTrackpad: Bool) -> Bool {
        // 開發用：`defaults write com.kuan.batterymonitor scrollDebug -bool true` 後重新打開 App，
        // 每個捲動事件的判斷與改寫前後的值會寫進系統記錄
        tap.configure(.init(reverseMouse: reverseMouse, reverseTrackpad: reverseTrackpad,
                            debug: UserDefaults.standard.bool(forKey: "scrollDebug"),
                            rebuild: UserDefaults.standard.object(forKey: "scrollRebuild") as? Bool ?? true))
        wanted = reverseMouse || reverseTrackpad
        guard wanted else {
            watchdog?.invalidate()
            watchdog = nil
            if tap.isRunning {
                tap.stop()
                ScrollTap.log.notice("兩個開關都關掉，停止攔截")
            }
            onChange?()
            return true
        }
        startIfTrusted(reason: "設定改變或啟動")
        if watchdog == nil {
            // 系統會在回應逾時、睡眠喚醒或權限變動時暫停甚至作廢攔截，攔截自己不一定收得到通知：
            // 每 5 秒檢查一次，暫停了就打開、作廢了就重建
            watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                MainActor.assumeIsolatedCompat { ScrollDirection.shared.check() }
            }
        }
        return tap.isRunning
    }

    private func check() {
        guard wanted else { return }
        switch tap.health() {
        case .ok: return
        case .disabled: tap.reenable(reason: "檢查時發現被暫停")
        case .invalid:
            tap.stop()
            ScrollTap.log.notice("事件攔截已失效")
            startIfTrusted(reason: "失效後重建")
        case .stopped:
            // 例如剛重新允許「輔助使用」
            startIfTrusted(reason: "定時檢查")
        }
    }

    /// 有權限才開始攔截；權限狀態改變、開始成功或失敗都留紀錄，查「突然失效」時用得到
    private func startIfTrusted(reason: String) {
        let trusted = Self.trusted
        if trusted != loggedTrust {
            loggedTrust = trusted
            ScrollTap.log.notice("輔助使用權限：\(trusted ? "有" : "沒有", privacy: .public)（\(reason, privacy: .public)）")
        }
        if trusted, !tap.isRunning {
            let started = tap.start()
            ScrollTap.log.notice("開始攔截（\(reason, privacy: .public)）：\(started ? "成功" : "失敗，系統不讓建立事件攔截", privacy: .public)")
        }
        onChange?()
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
}

/// 捲動事件的攔截：在自己的高優先執行緒上跑 run loop，主執行緒忙著畫畫面或取樣時捲動事件也不用等，
/// 系統就不會因為回應逾時暫停攔截。設定與最近一次兩指觸碰的時間跨執行緒使用，用鎖保護；其他判斷裝置用的狀態只在攔截執行緒使用
final class ScrollTap: @unchecked Sendable {
    struct Config {
        var reverseMouse = false
        var reverseTrackpad = false
        var debug = false
        /// 連續捲動（觸控板、Magic Mouse）改用新造的事件取代原本的；開發時可以用 scrollRebuild 關掉，比較兩種做法
        var rebuild = true
    }

    enum Health { case ok, disabled, invalid, stopped }

    static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "scroll")

    private let lock = NSLock()
    private var config = Config()
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?
    /// 最近一次觸控板上有兩指以上的時間（主執行緒寫入）；捲動在這之後 0.3 秒內就算觸控板
    private var lastTrackpadTouches: TimeInterval = 0
    /// 連續捲動的這段手勢（含放開手指後的慣性）是不是觸控板；一般滾輪的事件不會改到它
    private var gestureIsTrackpad = false
    /// 這個事件判斷成哪一種（記錄用）
    private var currentIsTrackpad = false
    /// 只在主執行緒使用
    private var lastLoggedTouches = -1

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    var isRunning: Bool { locked { port != nil } }

    func configure(_ new: Config) { locked { config = new } }

    /// 建立攔截並開一條執行緒跑它；沒有權限時回傳 false
    func start() -> Bool {
        guard !isRunning else { return true }
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            // 觸控板手指的事件（NSEvent.EventType.gesture，數值 29）用來分辨是不是觸控板
            let mask: CGEventMask = (1 << CGEventType.scrollWheel.rawValue) | (1 << 29)
            guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                               eventsOfInterest: mask, callback: scrollTapCallback,
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
            // stop() 作廢攔截、停掉 run loop 後，這條執行緒就結束
            CFRunLoopRun()
        }
        thread.name = "捲動方向"
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

    func health() -> Health {
        guard let port = locked({ self.port }) else { return .stopped }
        guard CFMachPortIsValid(port) else { return .invalid }
        return CGEvent.tapIsEnabled(tap: port) ? .ok : .disabled
    }

    /// 系統覺得回呼太慢或使用者操作時會暫停攔截，再打開。每次都留紀錄，失效時查得到原因
    func reenable(reason: String) {
        guard let port = locked({ self.port }) else { return }
        Self.log.notice("事件攔截被暫停（\(reason, privacy: .public)），重新打開")
        CGEvent.tapEnable(tap: port, enable: true)
    }

    fileprivate func markTouchesForTest() { locked { lastTrackpadTouches = CACurrentMediaTime() } }
    fileprivate func resetTouchesForTest() { locked { lastTrackpadTouches = 0 } }

    /// 在主執行緒數觸控板上的手指：NSEvent 的觸碰資訊在其他執行緒讀不到（永遠是 0 指）
    @MainActor
    private func countTouches(_ event: CGEvent, debug: Bool) {
        let count = NSEvent(cgEvent: event)?.touches(matching: .touching, in: nil).count ?? 0
        if count >= 2 { locked { lastTrackpadTouches = CACurrentMediaTime() } }
        if debug, count != lastLoggedTouches {
            lastLoggedTouches = count
            Self.log.notice("手指事件：\(count) 指")
        }
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent {
        let config = locked { self.config }
        let now = CACurrentMediaTime()
        if type.rawValue == 29 {
            // 複製一份交給主執行緒數手指；捲動的判斷每個事件都會重看，主執行緒慢一點只影響一段捲動最開頭的幾個事件
            if let copy = event.copy() {
                let debug = config.debug
                DispatchQueue.main.async { MainActor.assumeIsolatedCompat { self.countTouches(copy, debug: debug) } }
            }
            return event
        }
        guard type == .scrollWheel else { return event }
        currentIsTrackpad = classify(event, now: now)
        if config.debug { logScroll(event, label: "收到") }
        guard currentIsTrackpad ? config.reverseTrackpad : config.reverseMouse else { return event }
        if config.rebuild, event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0, let replaced = Self.rebuilt(from: event) {
            if config.debug { logScroll(replaced, label: "改成") }
            return replaced
        }
        Self.reverse(event)
        if config.debug { logScroll(event, label: "改成") }
        return event
    }

    /// 判斷這個捲動事件來自觸控板還是滑鼠。
    /// - 一般滾輪（不連續）一定是滑鼠，而且不會改到觸控板那邊的判斷：觸控板的慣性還在跑時轉一下滾輪，
    ///   之後的慣性事件仍算觸控板（以前會被改判成滑鼠，跟著滑鼠的設定反向，畫面突然往反方向滑）
    /// - 放開手指後的慣性沿用同一段手勢的判斷
    /// - 手勢開始時（或沒有階段的連續捲動）看最近 0.3 秒內觸控板上有沒有兩指；同一段手勢中途只會從滑鼠改成觸控板、
    ///   不會反過來，主執行緒慢一點、一時沒數到手指也不會中途改判
    private func classify(_ event: CGEvent, now: TimeInterval) -> Bool {
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 else { return false }
        if event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 { return gestureIsTrackpad }
        let recentTouches = now - locked { lastTrackpadTouches } < 0.3
        switch event.getIntegerValueField(.scrollWheelEventScrollPhase) {
        case 2, 4, 8:   // 手指移動中、放開、取消：同一段手勢
            gestureIsTrackpad = gestureIsTrackpad || recentTouches
        default:        // 剛放上手指（1、128）或沒有階段：新的一段
            gestureIsTrackpad = recentTouches
        }
        return gestureIsTrackpad
    }

    /// 捲動量的欄位：公開的行數、像素、精細值，加上沒有公開文件、但也帶著同一份捲動量的 175～178
    /// （實測 macOS 13 與 27 的觸控板事件都有：176／178 是垂直、175／177 是水平，小數欄位）。網頁等 App 用它們算放開手指後的慣性，
    /// 只改公開的欄位時，拖動的方向反了、慣性卻照原方向，網頁就會一直往回彈
    private static let integerDeltaFields: [CGEventField] = [
        .scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
        .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2,
    ]
    private static let fixedDeltaFields: [CGEventField] = [.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2]
    private static let rawDeltaFields: [CGEventField] = [175, 176, 177, 178].map { CGEventField(rawValue: $0)! }
    /// 新造的事件要從原本的事件抄過來的其他欄位：連續與否、手指階段、慣性階段、捲動次數，以及慣性相關的 137、173（沒有公開文件）
    private static let copiedFields: [CGEventField] = [
        .scrollWheelEventIsContinuous, .scrollWheelEventScrollPhase, .scrollWheelEventMomentumPhase,
        .scrollWheelEventScrollCount, .scrollWheelEventInstantMouser,
        CGEventField(rawValue: 137)!, CGEventField(rawValue: 173)!,
    ]

    /// 在原本的事件上反向（一般滾輪用）。177、178 是系統從原始觸控資料算出來的，改不了，寫入時還會把 175、176 重設回原值，
    /// 所以這裡只改其他欄位
    static func reverse(_ event: CGEvent) {
        let fields = fixedDeltaFields + rawDeltaFields.prefix(2)
        let integers = integerDeltaFields.map { event.getIntegerValueField($0) }
        let doubles = fields.map { event.getDoubleValueField($0) }
        for (field, value) in zip(integerDeltaFields, integers) { event.setIntegerValueField(field, value: -value) }
        for (field, value) in zip(fields, doubles) { event.setDoubleValueField(field, value: -value) }
    }

    /// 連續捲動改用新造的事件取代：原本的事件附帶系統的原始觸控資料，177、178 由它算出來、改不掉，網頁拿來算慣性就會往回彈。
    /// 新事件沒有那份資料，所有捲動量（包括 175～178）都是這裡設定的反向值，其他欄位照抄
    static func rebuilt(from event: CGEvent) -> CGEvent? {
        guard let new = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: 0, wheel3: 0) else { return nil }
        new.location = event.location
        new.flags = event.flags
        new.timestamp = event.timestamp
        for field in copiedFields { new.setDoubleValueField(field, value: event.getDoubleValueField(field)) }
        for field in copiedFields.prefix(5) { new.setIntegerValueField(field, value: event.getIntegerValueField(field)) }
        let integers = integerDeltaFields.map { event.getIntegerValueField($0) }
        let doubles = (fixedDeltaFields + rawDeltaFields).map { event.getDoubleValueField($0) }
        for (field, value) in zip(integerDeltaFields, integers) { new.setIntegerValueField(field, value: -value) }
        for (field, value) in zip(fixedDeltaFields + rawDeltaFields, doubles) { new.setDoubleValueField(field, value: -value) }
        return new
    }

    private func logScroll(_ event: CGEvent, label: String) {
        let lines = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let points = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let fixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let raw = event.getDoubleValueField(CGEventField(rawValue: 178)!)
        let ns = NSEvent(cgEvent: event)
        Self.log.notice("""
            \(label, privacy: .public) \(self.currentIsTrackpad ? "觸控板" : "滑鼠", privacy: .public) \
            連續=\(event.getIntegerValueField(.scrollWheelEventIsContinuous)) \
            階段=\(event.getIntegerValueField(.scrollWheelEventScrollPhase)) 慣性=\(event.getIntegerValueField(.scrollWheelEventMomentumPhase)) \
            行=\(lines) 點=\(points) 精細=\(fixed) 原始=\(raw) NSEvent=\(ns.map { "\($0.scrollingDeltaY)" } ?? "-", privacy: .public)
            """)
    }
}

extension ScrollDirection {
    /// 開發用：`--selftest-scroll` 造出滾輪、觸控板、慣性與 Magic Mouse 的捲動事件，走同一段判斷，印出有沒有反向（不需要權限）
    func selfTest() {
        let tap = ScrollTap()
        func scroll(continuous: Bool, momentum: Int64 = 0, touchesJustNow: Bool) -> String {
            if touchesJustNow { tap.markTouchesForTest() }
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 10, wheel2: 4, wheel3: 0) else { return "無法建立事件" }
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
            // 觸控板事件另外帶著的捲動量（沒有公開文件的 175～178，小數欄位）也要跟著反向。連續捲動換成新造的事件，四個都會反向；
            // 一般滾輪在原本的事件上改，177、178 改不了，只看 175、176
            let raw = [175, 176, 177, 178].map { CGEventField(rawValue: $0)! }
            for (field, value) in zip(raw, [0.5, 2, 3, 20]) { event.setDoubleValueField(field, value: value) }
            // 手指剛放上去（新的一段手勢）；慣性事件沒有手指階段
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: momentum == 0 && continuous ? 1 : 0)
            let out = tap.handle(.scrollWheel, event)
            let checked = continuous ? raw : Array(raw.prefix(2))
            let values = [Double(out.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)), Double(out.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))]
                + checked.map { out.getDoubleValueField($0) }
            // 換成新事件時，連續、手指階段、慣性階段要照抄
            if out !== event, out.getIntegerValueField(.scrollWheelEventIsContinuous) != 1
                || out.getIntegerValueField(.scrollWheelEventMomentumPhase) != momentum
                || out.getIntegerValueField(.scrollWheelEventScrollPhase) != event.getIntegerValueField(.scrollWheelEventScrollPhase) {
                return "異常（新事件的階段沒抄對）"
            }
            return values.allSatisfy { $0 < 0 } ? "反向" : values.allSatisfy { $0 > 0 } ? "不變" : "異常（\(values)）"
        }
        for (mouse, trackpad) in [(true, false), (false, true), (true, true)] {
            tap.configure(.init(reverseMouse: mouse, reverseTrackpad: trackpad))
            print("selftest-scroll: 滑鼠反向 \(mouse)、觸控板反向 \(trackpad)")
            print("  一般滾輪：\(scroll(continuous: false, touchesJustNow: false))")
            print("  觸控板兩指：\(scroll(continuous: true, touchesJustNow: true))")
            print("  觸控板放開後的慣性：\(scroll(continuous: true, momentum: 1, touchesJustNow: false))")
            tap.resetTouchesForTest()
            print("  Magic Mouse（連續、沒有兩指）：\(scroll(continuous: true, touchesJustNow: false))")
            // 觸控板的慣性還在跑時轉一下滾輪：滾輪照滑鼠的設定，之後的慣性仍照觸控板的設定
            _ = scroll(continuous: true, touchesJustNow: true)
            tap.resetTouchesForTest()
            let wheel = scroll(continuous: false, touchesJustNow: false)
            let momentum = scroll(continuous: true, momentum: 2, touchesJustNow: false)
            print("  觸控板慣性中間轉一下滾輪：滾輪\(wheel)、之後的慣性\(momentum)")
        }
        // 攔截執行緒：開始、檢查、停止都正常（需要「輔助使用」權限，沒有時只印出狀態）
        if ScrollDirection.trusted {
            let started = tap.start()
            print("selftest-scroll: 攔截執行緒開始 \(started)、狀態 \(tap.health())")
            tap.stop()
            print("selftest-scroll: 停止後 \(tap.health())、執行中 \(tap.isRunning)")
        } else {
            print("selftest-scroll: 沒有「輔助使用」權限，略過攔截執行緒的測試")
        }
    }
}

/// 事件攔截的回呼：在 ScrollTap 的執行緒上執行
private func scrollTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                               userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<ScrollTap>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        tap.reenable(reason: type == .tapDisabledByTimeout ? "回應逾時" : "使用者輸入")
        return Unmanaged.passUnretained(event)
    }
    let out = tap.handle(type, event)
    // 換成新造的事件時，交給系統的是我們建立的物件，要多保留一次（系統用完會釋放）
    return out === event ? Unmanaged.passUnretained(event) : Unmanaged.passRetained(out)
}
