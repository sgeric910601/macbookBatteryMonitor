/// 目前連著的外接裝置：螢幕、USB、Thunderbolt。Mac 內建的元件與 Hub 不列。
/// 只做過濾與排序，讀取在 ConnectedDeviceReader；名稱只顯示在畫面上，不存檔、不記錄
enum ConnectedDevices {
    enum Kind: Equatable { case display, usb, thunderbolt }

    struct Item: Equatable, Identifiable {
        let kind: Kind
        let name: String
        let detail: String?
        var id: String { "\(kind)-\(name)-\(detail ?? "")" }
    }

    struct USB: Equatable {
        let name: String
        let vendor: String
        /// USB 裝置類別；9 是 Hub
        let deviceClass: Int
        let builtIn: Bool
    }

    struct Thunderbolt: Equatable {
        let name: String
        let vendor: String
        /// 0 是 Mac 自己的控制器
        let depth: Int
    }

    static func usbItems(_ raw: [USB]) -> [Item] {
        var items: [Item] = []
        for device in raw where device.deviceClass != 9 && !device.builtIn {
            let name = device.name.isEmpty ? "\(device.vendor) 的裝置" : device.name
            let item = Item(kind: .usb, name: name, detail: device.vendor.isEmpty ? nil : device.vendor)
            if !items.contains(item) { items.append(item) }
        }
        return items
    }

    static func thunderboltItems(_ raw: [Thunderbolt]) -> [Item] {
        raw.filter { $0.depth > 0 }.map { Item(kind: .thunderbolt, name: $0.name, detail: $0.vendor.isEmpty ? nil : $0.vendor) }
    }

    static func displayItems(_ raw: [(name: String, builtIn: Bool)]) -> [Item] {
        raw.filter { !$0.builtIn }.map { Item(kind: .display, name: $0.name, detail: nil) }
    }
}
