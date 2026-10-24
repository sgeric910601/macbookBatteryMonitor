import AppKit
import ApplicationServices
import OSLog

/// 系統私有的 SkyLight（WindowServer 的介面）：列出所有 Space 的視窗、視窗在哪個 Space、視窗截圖、指定視窗帶到最前面。
/// 全部用 dlsym 取得；任何一個找不到（系統更新移除了）對應功能就停用，其他功能照常運作，不會崩潰。
/// 這些是私有介面，macOS 大版本更新後要重新驗證
enum SkyLight {
    static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "skylight")

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias ManagedSpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias SpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias WindowsWithOptions = @convention(c) (Int32, Int32, CFArray, Int32, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>) -> Unmanaged<CFArray>?
    private typealias HWCapture = @convention(c) (Int32, UnsafeMutablePointer<UInt32>, UInt32, UInt32) -> Unmanaged<CFArray>?
    private typealias SetFrontProcess = @convention(c) (UnsafeMutableRawPointer, UInt32, UInt32) -> Int32
    private typealias QueryWindows = @convention(c) (Int32, CFArray, Int32) -> Unmanaged<CFTypeRef>?
    private typealias QueryResultWindows = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
    private typealias IteratorAdvance = @convention(c) (CFTypeRef) -> Bool
    private typealias IteratorUInt32 = @convention(c) (CFTypeRef) -> UInt32
    private typealias IteratorInt32 = @convention(c) (CFTypeRef) -> Int32
    private typealias IteratorUInt64 = @convention(c) (CFTypeRef) -> UInt64
    private typealias IteratorFloat = @convention(c) (CFTypeRef) -> Float
    private typealias IteratorTitle = @convention(c) (CFTypeRef) -> Unmanaged<CFString>?
    /// 回傳 CGRect 這種 32 位元組的結構：x86_64 用隱藏的指標回傳、arm64 用暫存器，一定要用 C 的呼叫慣例綁定，
    /// 否則 Intel 上下一次呼叫會在 SkyLight 裡崩潰
    private typealias IteratorBounds = @convention(c) (UnsafeRawPointer) -> CGRect
    private typealias ProcessForPID = @convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32
    private typealias PostEventRecord = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt8>) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

    /// 預設只在 SkyLight 裡找；SkyLight 載不進來就全部停用。anywhere 為 true 時才在所有已載入的框架裡找
    /// （GetProcessForPID 在 ApplicationServices），只限這種明確列出的名稱，避免同名符號解析到別處
    private static func function<T>(_ name: String, _ type: T.Type, anywhere: Bool = false) -> T? {
        let symbol: UnsafeMutableRawPointer?
        if let handle {
            symbol = dlsym(handle, name) ?? (anywhere ? dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) : nil)
        } else {
            symbol = nil
        }
        guard let symbol else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    private static let mainConnection = function("SLSMainConnectionID", MainConnection.self)
    private static let managedSpaces = function("SLSCopyManagedDisplaySpaces", ManagedSpaces.self)
    private static let spacesForWindows = function("SLSCopySpacesForWindows", SpacesForWindows.self)
    private static let windowsWithOptions = function("SLSCopyWindowsWithOptionsAndTags", WindowsWithOptions.self)
    private static let hwCapture = function("CGSHWCaptureWindowList", HWCapture.self)
    private static let setFrontProcess = function("_SLPSSetFrontProcessWithOptions", SetFrontProcess.self)
    private static let queryWindows = function("SLSWindowQueryWindows", QueryWindows.self)
    private static let queryResultWindows = function("SLSWindowQueryResultCopyWindows", QueryResultWindows.self)
    private static let iteratorAdvance = function("SLSWindowIteratorAdvance", IteratorAdvance.self)
    private static let iteratorID = function("SLSWindowIteratorGetWindowID", IteratorUInt32.self)
    private static let iteratorPID = function("SLSWindowIteratorGetPID", IteratorInt32.self)
    private static let iteratorAttributes = function("SLSWindowIteratorGetAttributes", IteratorUInt64.self)
    private static let iteratorTags = function("SLSWindowIteratorGetTags", IteratorUInt64.self)
    private static let iteratorLevel = function("SLSWindowIteratorGetLevel", IteratorInt32.self)
    private static let iteratorSpaceTypeMask = function("SLSWindowIteratorGetSpaceTypeMask", IteratorUInt64.self)
    private static let iteratorAlpha = function("SLSWindowIteratorGetAlpha", IteratorFloat.self)
    private static let iteratorParent = function("SLSWindowIteratorGetParentID", IteratorUInt32.self)
    private static let iteratorTitle = function("SLSWindowIteratorCopyTitle", IteratorTitle.self)
    private static let iteratorBounds = function("SLSWindowIteratorGetBounds", IteratorBounds.self)
    private static let processForPID = function("GetProcessForPID", ProcessForPID.self, anywhere: true)
    private static let postEventRecord = function("SLPSPostEventRecordTo", PostEventRecord.self)

    private static let connection: Int32? = mainConnection?()

    /// 截圖選項：最佳解析度、忽略全域裁切（視窗被別的視窗蓋住也拍整個）
    private static let captureOptions: UInt32 = (1 << 8) | (1 << 11)

    static var canListSpaces: Bool { connection != nil && managedSpaces != nil && windowsWithOptions != nil && spacesForWindows != nil }
    static var canQueryWindows: Bool {
        connection != nil && queryWindows != nil && queryResultWindows != nil && iteratorAdvance != nil && iteratorID != nil && iteratorPID != nil
            && iteratorAttributes != nil && iteratorTags != nil && iteratorLevel != nil && iteratorSpaceTypeMask != nil && iteratorAlpha != nil
            && iteratorParent != nil && iteratorTitle != nil && iteratorBounds != nil
    }
    static var canCapture: Bool { connection != nil && hwCapture != nil }
    static var canFocusAcrossSpaces: Bool { setFrontProcess != nil && postEventRecord != nil && processForPID != nil }

    struct Display: Equatable {
        var identifier: String
        var spaces: [UInt64]
        var current: UInt64?
    }

    /// 每個螢幕的 Space 與目前顯示的那個。「顯示器有各自的 Space」關閉時所有螢幕合成一個，識別碼是 "Main"
    static func displays() -> [Display] {
        guard let connection, let managedSpaces, let raw = managedSpaces(connection)?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return raw.map { display in
            let spaces = (display["Spaces"] as? [[String: Any]] ?? []).compactMap { ($0["id64"] as? NSNumber)?.uint64Value }
            let current = ((display["Current Space"] as? [String: Any])?["id64"] as? NSNumber)?.uint64Value
            return Display(identifier: display["Display Identifier"] as? String ?? "", spaces: spaces, current: current)
        }
    }

    /// 所有 Space（包括沒在顯示的）上的視窗編號，由前到後。includeInvisible 連沒排進畫面的視窗（縮到 Dock、隱藏、幻影）一起列出
    static func windowIDs(inSpaces spaces: [UInt64], includeInvisible: Bool = false) -> [UInt32] {
        guard let connection, let windowsWithOptions, !spaces.isEmpty else { return [] }
        var set: UInt64 = 0, clear: UInt64 = 0
        let options: Int32 = includeInvisible ? 0x2 | 0x1 | 0x4 : 0x2
        let result = windowsWithOptions(connection, 0, spaces.map { NSNumber(value: $0) } as CFArray, options, &set, &clear)?.takeRetainedValue()
        return (result as? [NSNumber])?.map(\.uint32Value) ?? []
    }

    /// 一次向 WindowServer 查詢一批視窗的所有欄位；必須在主執行緒以外呼叫更理想（WindowServer 忙的時候會等），
    /// 但閒置時整個畫面約 0.1 毫秒
    static func query(_ ids: [UInt32]) -> [WindowServerWindow] {
        guard canQueryWindows, !ids.isEmpty, let connection, let queryWindows, let queryResultWindows, let advance = iteratorAdvance,
              let id = iteratorID, let pid = iteratorPID, let attributes = iteratorAttributes, let tags = iteratorTags, let level = iteratorLevel,
              let mask = iteratorSpaceTypeMask, let alpha = iteratorAlpha, let parent = iteratorParent, let title = iteratorTitle,
              let bounds = iteratorBounds,
              let query = queryWindows(connection, ids.map { NSNumber(value: $0) } as CFArray, 1)?.takeRetainedValue(),
              let iterator = queryResultWindows(query)?.takeRetainedValue() else { return [] }
        let wanted = Set(ids)
        var rows: [WindowServerWindow] = []
        var guardrail = ids.count * 2 + 16
        while guardrail > 0, advance(iterator) {
            guardrail -= 1
            let windowID = id(iterator)
            guard wanted.contains(windowID) else { continue }
            rows.append(WindowServerWindow(id: windowID, pid: pid(iterator), attributes: attributes(iterator), tags: tags(iterator),
                                           level: level(iterator), spaceTypeMask: mask(iterator), alpha: alpha(iterator), parent: parent(iterator),
                                           frame: bounds(Unmanaged.passUnretained(iterator).toOpaque()),
                                           title: title(iterator)?.takeRetainedValue() as String? ?? ""))
        }
        return rows
    }

    /// 視窗所在的 Space；縮到 Dock 的視窗不屬於任何 Space
    static func spaces(of windowID: UInt32) -> [UInt64] {
        guard let connection, let spacesForWindows else { return [] }
        let result = spacesForWindows(connection, 0x7, [NSNumber(value: windowID)] as CFArray)?.takeRetainedValue()
        return (result as? [NSNumber])?.map(\.uint64Value) ?? []
    }

    /// 視窗截圖（原始大小）；沒有「螢幕錄製」權限、視窗不存在或在別的 Space 抓不到時回傳 nil
    static func capture(_ windowID: UInt32) -> CGImage? {
        guard let connection, let hwCapture else { return nil }
        var id = windowID
        let result = hwCapture(connection, &id, 1, captureOptions)?.takeRetainedValue()
        return (result as? [CGImage])?.first
    }

    /// 把某個 App 的某個視窗帶到最前面，包括在別的 Space 的視窗（macOS 會切過去）。
    /// 只用在沒有「輔助使用」視窗物件可以操作的時候
    static func focus(windowID: UInt32, pid: pid_t) -> Bool {
        guard let setFrontProcess, let postEventRecord, let processForPID else { return false }
        var psn = [UInt32](repeating: 0, count: 2)
        let found = psn.withUnsafeMutableBytes { processForPID(pid, $0.baseAddress!) }
        guard found == 0 else { return false }
        return psn.withUnsafeMutableBytes { raw -> Bool in
            let base = raw.baseAddress!
            guard setFrontProcess(base, windowID, 0x200) == 0 else { return false }
            // 通知該 App 這個視窗成為主要視窗：固定長度 0xf8 的事件記錄，位元組 0x04 = 0xf8、0x08 = 0x01（按下）／0x02（放開）、
            // 0x3a 起放視窗編號
            var record = [UInt8](repeating: 0, count: 0xf8)
            record[0x04] = 0xf8
            record[0x3a] = 0x10
            for index in 0x20..<0x30 { record[index] = 0xff }
            withUnsafeBytes(of: windowID.littleEndian) { record.replaceSubrange(0x3c..<0x40, with: $0) }
            for flag: UInt8 in [0x01, 0x02] {
                record[0x08] = flag
                _ = postEventRecord(base, &record)
            }
            return true
        }
    }
}

/// 視窗編號：用「輔助使用」視窗物件對到 WindowServer 的視窗（私有函式，只有這個方向）
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<UInt32>) -> AXError

extension AX {
    static func windowID(of element: AXUIElement) -> UInt32? {
        var id: UInt32 = 0
        return _AXUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
    }
}
