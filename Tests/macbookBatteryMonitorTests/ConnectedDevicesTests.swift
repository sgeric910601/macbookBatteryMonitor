import Foundation

struct ConnectedDevicesTests {
    /// USB：不列 Hub（類別 9）與 Mac 內建的裝置；沒有名稱的用廠商補；同名的只列一次
    func testUSBFiltering() {
        let raw = [
            ConnectedDevices.USB(name: "USB2.0 Hub", vendor: "GenericHub", deviceClass: 9, builtIn: false),
            ConnectedDevices.USB(name: "Example Keyboard", vendor: "Example Co", deviceClass: 0, builtIn: false),
            ConnectedDevices.USB(name: "Example Keyboard", vendor: "Example Co", deviceClass: 0, builtIn: false),
            ConnectedDevices.USB(name: "", vendor: "Sample Labs", deviceClass: 0, builtIn: false),
            ConnectedDevices.USB(name: "Internal Camera", vendor: "Apple Inc.", deviceClass: 0, builtIn: true),
        ]
        XCTAssertEqual(ConnectedDevices.usbItems(raw), [
            ConnectedDevices.Item(kind: .usb, name: "Example Keyboard", detail: "Example Co"),
            ConnectedDevices.Item(kind: .usb, name: "Sample Labs 的裝置", detail: "Sample Labs"),
        ])
    }

    /// Thunderbolt：深度 0 是 Mac 自己的控制器，不列
    func testThunderboltFiltering() {
        let raw = [
            ConnectedDevices.Thunderbolt(name: "iOS", vendor: "Apple Inc.", depth: 0),
            ConnectedDevices.Thunderbolt(name: "Example Dock", vendor: "Example Co", depth: 1),
        ]
        XCTAssertEqual(ConnectedDevices.thunderboltItems(raw), [ConnectedDevices.Item(kind: .thunderbolt, name: "Example Dock", detail: "Example Co")])
    }

    /// 螢幕：內建的不列
    func testDisplays() {
        XCTAssertEqual(ConnectedDevices.displayItems([("Built-in Retina Display", true), ("Example Monitor", false)]),
                       [ConnectedDevices.Item(kind: .display, name: "Example Monitor", detail: nil)])
    }
}
