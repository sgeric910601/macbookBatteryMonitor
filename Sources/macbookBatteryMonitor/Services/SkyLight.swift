import AppKit
import ApplicationServices
import OSLog

/// 跟 WindowServer 打交道的地方：Space 清單、某些 Space 上有哪些視窗、截圖、把指定視窗的行程帶到前面。
/// 能用公開 API 的就用公開 API（CGWindowListCopyWindowInfo 給擁有者、層級、透明度、位置、名稱）；
/// 公開 API 沒有的（Space、縮小與隱藏的標記、父視窗、截圖、把行程帶到前面並指定視窗）才用 SkyLight 私有函式；
/// 切 Space 本身靠啟用 App，由 macOS 處理。
/// 私有函式一律在第一次用到時以 dlsym 載入，缺哪一個就只停用依賴它的功能。
/// 每個私有符號、常數的出處與實測結果見 docs/design/window-server-provenance.md；macOS 大版本更新後要重跑實測
enum SkyLight {
    private static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "windowserver")

    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    /// <dlfcn.h> 的 RTLD_DEFAULT（(void *)-2）：在已載入的所有映像檔裡找
    private static let anyImage = UnsafeMutableRawPointer(bitPattern: -2)

    private static func resolve<Signature>(_ name: String, in image: UnsafeMutableRawPointer?, as _: Signature.Type) -> Signature? {
        guard let image, let address = dlsym(image, name) else {
            log.error("找不到 \(name, privacy: .public)，依賴它的功能停用")
            return nil
        }
        return unsafeBitCast(address, to: Signature.self)
    }

    // MARK: - 函式型別（參數依 yabai src/misc/extern.h 的宣告）

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CopyArrayForConnection = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CurrentSpaceForDisplay = @convention(c) (Int32, CFString) -> UInt64
    private typealias SpaceKind = @convention(c) (Int32, UInt64) -> Int32
    private typealias CopyWindowsInSpaces = @convention(c) (Int32, UInt32, CFArray, UInt32, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>) -> Unmanaged<CFArray>?
    private typealias CopySpacesOfWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias StartWindowQuery = @convention(c) (Int32, CFArray, Int32) -> Unmanaged<CFTypeRef>?
    private typealias CopyQueryWindows = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
    private typealias CursorStep = @convention(c) (CFTypeRef) -> Bool
    private typealias CursorWord = @convention(c) (CFTypeRef) -> UInt32
    private typealias CursorFlags = @convention(c) (CFTypeRef) -> UInt64
    private typealias HardwareCapture = @convention(c) (Int32, UnsafeMutablePointer<UInt32>, Int32, UInt32) -> Unmanaged<CFArray>?
    private typealias BringProcessForward = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> Int32
    private typealias SerialNumberForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

    private static let connectionID = resolve("SLSMainConnectionID", in: skyLight, as: MainConnectionID.self)
    private static let copyDisplaySpaces = resolve("SLSCopyManagedDisplaySpaces", in: skyLight, as: CopyArrayForConnection.self)
    private static let currentSpace = resolve("SLSManagedDisplayGetCurrentSpace", in: skyLight, as: CurrentSpaceForDisplay.self)
    private static let spaceKind = resolve("SLSSpaceGetType", in: skyLight, as: SpaceKind.self)
    private static let copyWindowsInSpaces = resolve("SLSCopyWindowsWithOptionsAndTags", in: skyLight, as: CopyWindowsInSpaces.self)
    private static let copySpacesOfWindows = resolve("SLSCopySpacesForWindows", in: skyLight, as: CopySpacesOfWindows.self)
    private static let startQuery = resolve("SLSWindowQueryWindows", in: skyLight, as: StartWindowQuery.self)
    private static let queryWindows = resolve("SLSWindowQueryResultCopyWindows", in: skyLight, as: CopyQueryWindows.self)
    private static let cursorAdvance = resolve("SLSWindowIteratorAdvance", in: skyLight, as: CursorStep.self)
    private static let cursorWindowID = resolve("SLSWindowIteratorGetWindowID", in: skyLight, as: CursorWord.self)
    private static let cursorParentID = resolve("SLSWindowIteratorGetParentID", in: skyLight, as: CursorWord.self)
    private static let cursorAttributes = resolve("SLSWindowIteratorGetAttributes", in: skyLight, as: CursorFlags.self)
    private static let cursorTags = resolve("SLSWindowIteratorGetTags", in: skyLight, as: CursorFlags.self)
    private static let hardwareCapture = resolve("SLSHWCaptureWindowList", in: skyLight, as: HardwareCapture.self)
    private static let bringForward = resolve("_SLPSSetFrontProcessWithOptions", in: skyLight, as: BringProcessForward.self)
    // 公開標頭 HIServices/Processes.h 有宣告，但 Swift 不匯入 10.9 以前就淘汰的函式，只好動態找
    private static let serialNumberForPID = resolve("GetProcessForPID", in: anyImage, as: SerialNumberForPID.self)

    private static let connection: Int32? = connectionID?()

    // MARK: - Space

    struct Display: Equatable {
        /// 螢幕的 UUID 字串；「顯示器有各自的 Space」關閉時所有螢幕合成一個
        var identifier: String
        var spaces: [UInt64]
        var current: UInt64?
    }

    static func displays() -> [Display] {
        guard let connection, let copyDisplaySpaces,
              let list = copyDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let identifier = entry["Display Identifier"] as? String else { return nil }
            let spaces = (entry["Spaces"] as? [[String: Any]] ?? []).compactMap { ($0["id64"] as? NSNumber)?.uint64Value }
            let shown = currentSpace.map { $0(connection, identifier as CFString) }
            return Display(identifier: identifier, spaces: spaces, current: shown.flatMap { $0 == 0 ? nil : $0 })
        }
    }

    /// 這個視窗所在的 Space；選擇子 0x7 依 yabai window.c 的用法（包含所有種類的 Space）
    static func spaces(ofWindow id: UInt32) -> [UInt64] {
        guard let connection, let copySpacesOfWindows,
              let list = copySpacesOfWindows(connection, 0x7, [NSNumber(value: id)] as CFArray)?.takeRetainedValue() as? [NSNumber] else { return [] }
        return list.map(\.uint64Value)
    }

    // MARK: - 視窗

    /// 這些 Space 上、屬於 owners 這些行程的視窗，順序跟 WindowServer 給的一樣。
    /// 不會問任何 App，所以忙碌的 App 拖不慢它
    static func windows(in spaces: [UInt64], ownedBy owners: Set<pid_t>) -> [ServerWindowRecord] {
        guard let connection, let copyWindowsInSpaces, !spaces.isEmpty else { return [] }
        var setMask: UInt64 = 0, clearMask: UInt64 = 0
        // 選項 0x7：連縮到 Dock 的視窗也列出（yabai space.c 的 include_minimized）
        guard let numbers = copyWindowsInSpaces(connection, 0, spaces as CFArray, 0x7, &setMask, &clearMask)?.takeRetainedValue() as? [NSNumber],
              !numbers.isEmpty else { return [] }
        let described = publicDescriptions()
        let flags = rawFlags(numbers)
        var kindOfSpace: [UInt64: Int32] = [:]
        return numbers.compactMap { number -> ServerWindowRecord? in
            let id = number.uint32Value
            guard let info = described[id], let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, owners.contains(pid) else { return nil }
            var record = ServerWindowRecord(windowID: id, ownerPID: pid, orderedIn: false)
            record.layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            record.opacity = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            if let rect = info[kCGWindowBounds as String] as? NSDictionary { record.bounds = CGRect(dictionaryRepresentation: rect) ?? .zero }
            record.name = info[kCGWindowName as String] as? String ?? ""
            if let raw = flags[id] {
                let state = ServerWindowBits.decode(attributes: raw.attributes, tags: raw.tags)
                record.parentID = raw.parent
                record.orderedIn = state.orderedIn
                record.minimized = state.minimized
                record.hiddenWithApp = state.hiddenWithApp
            } else {
                // 私有查詢不能用時退回公開的「在畫面上」
                record.orderedIn = info[kCGWindowIsOnscreen as String] as? Bool ?? false
            }
            record.spaces = Self.spaces(ofWindow: id)
            record.onFullscreenSpace = record.spaces.contains { space in
                if kindOfSpace[space] == nil { kindOfSpace[space] = spaceKind?(connection, space) ?? -1 }
                return kindOfSpace[space] == fullscreenSpaceKind
            }
            return record
        }
    }

    /// SLSSpaceGetType 對全螢幕 Space 回傳 4（yabai space.c 的 space_is_fullscreen，並經本機實測）
    private static let fullscreenSpaceKind: Int32 = 4

    /// 公開 API 的視窗描述（包含畫面外的視窗），以視窗編號索引
    private static func publicDescriptions() -> [UInt32: [String: Any]] {
        let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        var byID: [UInt32: [String: Any]] = [:]
        for info in all {
            if let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value { byID[id] = info }
        }
        return byID
    }

    /// 一次批次查詢取得父視窗與原始旗標
    private static func rawFlags(_ numbers: [NSNumber]) -> [UInt32: (parent: UInt32, attributes: UInt64, tags: UInt64)] {
        guard let connection, let startQuery, let queryWindows, let cursorAdvance, let cursorWindowID, let cursorParentID,
              let cursorAttributes, let cursorTags,
              let query = startQuery(connection, numbers as CFArray, Int32(numbers.count))?.takeRetainedValue(),
              let cursor = queryWindows(query)?.takeRetainedValue() else { return [:] }
        var result: [UInt32: (parent: UInt32, attributes: UInt64, tags: UInt64)] = [:]
        // 走完游標之前查詢本身不能先被釋放
        withExtendedLifetime(query) {
            while cursorAdvance(cursor) {
                result[cursorWindowID(cursor)] = (cursorParentID(cursor), cursorAttributes(cursor), cursorTags(cursor))
            }
        }
        return result
    }

    /// 現在畫在畫面上的視窗編號，由前到後（公開 API，CGWindow.h 保證這個順序）
    static func onScreenFrontToBack() -> [UInt32] {
        let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
    }

    // MARK: - 截圖

    static var canCapture: Bool { connection != nil && hardwareCapture != nil }

    /// 單一視窗的畫面；選項 (1 << 11) | (1 << 8) 與 yabai window_manager.c 擷取視窗代理圖時相同
    static func capture(_ windowID: UInt32) -> CGImage? {
        guard let connection, let hardwareCapture else { return nil }
        var id = windowID
        guard let images = hardwareCapture(connection, &id, 1, (1 << 11) | (1 << 8))?.takeRetainedValue() as? [CGImage] else { return nil }
        return images.first
    }

    // MARK: - 帶到前面

    /// kCPSUserGenerated（yabai window_manager.h）：當作使用者自己切換
    private static let userInitiated: UInt32 = 0x200

    /// 把行程帶到前面，並告訴系統要的是哪個視窗。實測只呼叫它不會切 Space：切 Space 靠呼叫的地方再啟用 App，
    /// 視窗成為作用中則用「輔助使用」處理。做不到回傳 false
    static func focus(windowID: UInt32, pid: pid_t) -> Bool {
        guard let bringForward, let serialNumberForPID else { return false }
        var process = ProcessSerialNumber()
        guard serialNumberForPID(pid, &process) == noErr, bringForward(&process, windowID, userInitiated) == 0 else { return false }
        return true
    }
}

extension AX {
    private typealias WindowNumberOfElement = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> AXError
    // 私有但穩定多年的 HIServices 函式；動態載入，找不到時所有視窗都視為沒有編號
    private static let windowNumberOfElement: WindowNumberOfElement? = {
        guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(address, to: WindowNumberOfElement.self)
    }()

    /// 「輔助使用」視窗物件對應的 WindowServer 視窗編號
    static func windowID(of element: AXUIElement) -> UInt32? {
        guard let windowNumberOfElement else { return nil }
        var id: UInt32 = 0
        return windowNumberOfElement(element, &id) == .success && id != 0 ? id : nil
    }
}
