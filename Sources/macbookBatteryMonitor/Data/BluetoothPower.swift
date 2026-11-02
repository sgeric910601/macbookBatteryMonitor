import AppKit
import IOKit.hid
import OSLog

/// 藍牙電源的讀取與開關。macOS 沒有公開的介面，用 IOBluetooth 框架裡的
/// IOBluetoothPreferenceGetControllerPowerState／SetControllerPowerState（1 開、0 關，本機實測 macOS 27）。
/// 執行時才載入，找不到就當作不支援，設定頁不顯示這個選項
enum BluetoothPower {
    private typealias Get = @convention(c) () -> Int32
    private typealias Set = @convention(c) (Int32) -> Void

    private static let framework = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY)
    private static let getter = framework.flatMap { dlsym($0, "IOBluetoothPreferenceGetControllerPowerState") }
        .map { unsafeBitCast($0, to: Get.self) }
    private static let setter = framework.flatMap { dlsym($0, "IOBluetoothPreferenceSetControllerPowerState") }
        .map { unsafeBitCast($0, to: Set.self) }

    static var isAvailable: Bool { getter != nil && setter != nil }

    static var isOn: Bool { getter?() == 1 }

    private static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "bluetooth")

    static func setOn(_ on: Bool) {
        setter?(on ? 1 : 0)
        log.notice("睡眠時關閉藍牙：\(on ? "打開" : "關閉", privacy: .public)")
    }

    /// 螢幕闔上、接著外接螢幕使用（闔蓋模式）。只是闔上螢幕讓 Mac 睡眠不算：那是最常見的睡眠方式，照樣要關藍牙
    @MainActor
    static func lidClosedWithExternalDisplay() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let closed = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool ?? false
        let external = NSScreen.screens.contains { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDisplayIsBuiltin($0.uint32Value) == 0 } ?? false
        }
        return closed && external
    }

    /// 連著藍牙鍵盤、滑鼠或觸控板（見 BluetoothSleep.isWakeInput）
    static func wakeInputConnected() -> Bool {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOHIDDeviceKey), &iterator) == KERN_SUCCESS else {
            // 讀不到時當作有連著，寧可不關
            return true
        }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard let transport = property(kIOHIDTransportKey) as? String,
                  let page = (property(kIOHIDPrimaryUsagePageKey) as? NSNumber)?.intValue,
                  let usage = (property(kIOHIDPrimaryUsageKey) as? NSNumber)?.intValue else { continue }
            if BluetoothSleep.isWakeInput(transport: transport, usagePage: page, usage: usage) { return true }
        }
        return false
    }
}
