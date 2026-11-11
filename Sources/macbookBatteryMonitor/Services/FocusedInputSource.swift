import AppKit
import Carbon

/// 像選單列「輸入法」選單那樣切換：請有鍵盤焦點的 App 自己切。
/// 從背景程式呼叫 TISSelectInputSource 時，系統只先改全系統的設定，前景 App 常常沒跟上：
/// 選單列顯示注音，打出來卻還是英文。改送 Text Services Manager 的切換要求給焦點 App 就會生效。
/// 做法參考 macism（MIT，https://github.com/laishulu/macism）的說明；用到的都是私有符號，執行時才載入，
/// 找不到或失敗時，select 退回 TISSelectInputSource，selectInFocusedApp 回傳 false 交給呼叫端處理
enum FocusedInputSource {
    private typealias KeyFocus = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<DarwinBoolean>) -> Int32
    private typealias ProcessPID = @convention(c) (UnsafePointer<ProcessSerialNumber>, UnsafeMutablePointer<pid_t>) -> OSStatus
    private typealias RemotePort = @convention(c) (CFAllocator?, CFString, CFIndex) -> Unmanaged<CFMessagePort>?
    private typealias Flatten = @convention(c) (TISInputSource, UnsafeMutablePointer<Unmanaged<AnyObject>?>) -> DarwinBoolean

    private static func symbol<T>(_ name: String, as _: T.Type) -> T? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name).map { unsafeBitCast($0, to: T.self) }
    }

    private static let keyFocus = symbol("CPSGetKeyFocusProcess", as: KeyFocus.self)
    private static let processPID = symbol("GetProcessPID", as: ProcessPID.self)
    private static let remotePort = symbol("CFMessagePortCreatePerProcessRemote", as: RemotePort.self)
    private static let flatten = symbol("_CreateFlattenedInputSource", as: Flatten.self)

    /// 私有函式的參數格式是依實測假設的，系統改了會當掉而不是失敗，所以只在實測過的 macOS 主版本走這條路
    static let testedMajorVersions: Set<Int> = [27]

    /// 先請焦點 App 切換，不行再用 TISSelectInputSource。回傳 noErr 表示切換已送出
    @discardableResult
    static func select(_ source: TISInputSource) -> OSStatus {
        selectInFocusedApp(source) ? noErr : TISSelectInputSource(source)
    }

    /// 只請焦點 App 切換，不退回 TISSelectInputSource；沒送出回傳 false
    static func selectInFocusedApp(_ source: TISInputSource) -> Bool {
        testedMajorVersions.contains(ProcessInfo.processInfo.operatingSystemVersion.majorVersion) && askFocusedApp(source)
    }

    /// 接收按鍵的程式（不一定是最前面的 App，例如可以打字的浮動面板）
    private static func focusedPID() -> pid_t? {
        guard let keyFocus, let processPID else { return nil }
        var psn = ProcessSerialNumber()
        var ignored: DarwinBoolean = false
        var pid: pid_t = -1
        guard keyFocus(&psn, &ignored) == 0, processPID(&psn, &pid) == noErr, pid > 0 else { return nil }
        return pid
    }

    private static func askFocusedApp(_ source: TISInputSource) -> Bool {
        // 焦點在本 App 自己（例如設定視窗在最前面）：主執行緒等不到自己的回覆，回傳 false 交給呼叫端
        guard let remotePort, let flatten, let pid = focusedPID(), pid != getpid() else { return false }
        var flattened: Unmanaged<AnyObject>?
        guard flatten(source, &flattened).boolValue, let flat = flattened?.takeRetainedValue() else { return false }
        let request = ["tsmInputSourceSelectedInpSrcKey": flat] as CFDictionary
        guard let data = CFPropertyListCreateData(nil, request, .xmlFormat_v1_0, 0, nil)?.takeRetainedValue(),
              let port = remotePort(nil, "com.apple.tsm.portname" as CFString, CFIndex(pid))?.takeRetainedValue() else { return false }
        // 同步送出：回來時 App 已經切好，接著送出的按鍵就會進新的輸入法。App 沒回應時送出、等回覆各最多 0.15 秒。
        // 等回覆時用自己的 run loop mode：用預設 mode 會在等待中處理下一個按鍵，順序會亂
        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(port, 7, data, 0.15, 0.15, "com.kuan.batterymonitor.tsmReply" as CFString, &reply)
        // 等回覆逾時：要求已經送到，App 忙完還是會切，當成已送出（否則呼叫端以為沒切、不會切回）
        if status == kCFMessagePortReceiveTimeout { return true }
        guard status == kCFMessagePortSuccess else { return false }
        // 回覆來自對方 App，只看大小合理的
        if let replyData = reply?.takeRetainedValue(), CFDataGetLength(replyData) < 4096,
           let dict = CFPropertyListCreateWithData(nil, replyData, 0, nil, nil)?.takeRetainedValue() as? [String: Any],
           let error = dict["tsmInputModeReplyToServerErrorKey"] as? Int, error != 0 {
            return false
        }
        return true
    }
}
