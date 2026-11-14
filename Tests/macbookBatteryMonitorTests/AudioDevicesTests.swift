import Foundation

struct AudioDevicesTests {
    private let devices = [
        AudioDevices.Device(id: 3, name: "外接螢幕", outputs: true, inputs: false),
        AudioDevices.Device(id: 1, name: "MacBook Pro 揚聲器", outputs: true, inputs: false),
        AudioDevices.Device(id: 2, name: "MacBook Pro 麥克風", outputs: false, inputs: true),
        AudioDevices.Device(id: 4, name: "耳機", outputs: true, inputs: true),
    ]

    /// 輸出選單只列有輸出的裝置，依名稱排序，標出目前使用的
    func testOutputMenu() {
        let menu = AudioDevices.outputs(devices, current: 4)
        // 順序跟著系統語言的排序規則，不寫死
        XCTAssertEqual(Set(menu.map(\.name)), ["MacBook Pro 揚聲器", "外接螢幕", "耳機"])
        XCTAssertTrue(zip(menu, menu.dropFirst()).allSatisfy { $0.name.localizedStandardCompare($1.name) != .orderedDescending })
        XCTAssertEqual(menu.filter(\.isCurrent).map(\.id), [4])
    }

    /// 麥克風靜音：裝置有靜音開關就用它；沒有的話把音量調到 0，取消時還原原本的音量（原本就是 0 時還原成一半，免得取消後還是聽不到）
    func testMutePlan() {
        XCTAssertEqual(AudioDevices.mutePlan(hasMuteSwitch: true, volume: 0.6), .muteSwitch)
        XCTAssertEqual(AudioDevices.mutePlan(hasMuteSwitch: false, volume: 0.6), .volume(restoreTo: 0.6))
        XCTAssertEqual(AudioDevices.mutePlan(hasMuteSwitch: false, volume: 0), .volume(restoreTo: 0.5))
        XCTAssertEqual(AudioDevices.mutePlan(hasMuteSwitch: false, volume: nil), .unsupported)
    }

    /// 只有需要「輔助使用」的擴充功能才列在權限頁的輔助使用底下
    func testAccessibilityNeeds() {
        XCTAssertTrue(!ExtensionFeature.audioSwitch.needsAccessibility && !ExtensionFeature.quickMenu.needsAccessibility && !ExtensionFeature.portManager.needsAccessibility && !ExtensionFeature.clipboardHistory.needsAccessibility && !ExtensionFeature.speedTest.needsAccessibility && !ExtensionFeature.startupItems.needsAccessibility)
        XCTAssertTrue(ExtensionFeature.allCases.filter { ![.audioSwitch, .quickMenu, .portManager, .clipboardHistory, .speedTest, .startupItems].contains($0) }.allSatisfy(\.needsAccessibility))
        XCTAssertEqual(AppPermission.accessibility.users(isInstalled: { $0 == .audioSwitch }), [])
    }
}
