import AppKit
import IOKit

/// 讀目前連著的外接裝置（判斷在 ConnectedDevices）。全是公開的 IOKit 與 AppKit 資訊，不需要權限；打開設定頁時才讀
enum ConnectedDeviceReader {
    @MainActor
    static func read() -> [ConnectedDevices.Item] {
        ConnectedDevices.displayItems(displays()) + ConnectedDevices.thunderboltItems(thunderbolt()) + ConnectedDevices.usbItems(usb())
    }

    @MainActor
    private static func displays() -> [(name: String, builtIn: Bool)] {
        NSScreen.screens.map { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return (screen.localizedName, CGDisplayIsBuiltin(id) != 0)
        }
    }

    private static func services(_ className: String, _ body: (io_service_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            body(service)
            IOObjectRelease(service)
        }
    }

    private static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func usb() -> [ConnectedDevices.USB] {
        var result: [ConnectedDevices.USB] = []
        services("IOUSBHostDevice") { service in
            result.append(ConnectedDevices.USB(
                name: property(service, "USB Product Name") as? String ?? "",
                vendor: property(service, "USB Vendor Name") as? String ?? "",
                deviceClass: (property(service, "bDeviceClass") as? NSNumber)?.intValue ?? 0,
                builtIn: (property(service, "Built-In") as? Bool) ?? false))
        }
        return result
    }

    private static func thunderbolt() -> [ConnectedDevices.Thunderbolt] {
        var result: [ConnectedDevices.Thunderbolt] = []
        services("IOThunderboltSwitch") { service in
            result.append(ConnectedDevices.Thunderbolt(
                name: property(service, "Device Model Name") as? String ?? "",
                vendor: property(service, "Device Vendor Name") as? String ?? "",
                depth: (property(service, "Depth") as? NSNumber)?.intValue ?? 0))
        }
        return result
    }
}
