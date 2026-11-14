import Foundation

struct ExtensionFeatureTests {
    /// 原始值存在設定裡（加入狀態的鍵），改名會讓所有人的選擇失效；基本功能不在清單裡
    func testRawValuesAreStable() {
        XCTAssertEqual(ExtensionFeature.allCases.map(\.rawValue), ["scrollDirection", "windowSwitcher", "inputMethod", "quitGuard", "lastWindowQuit", "dockClick", "keyboardCleaning", "mouseButtons", "audioSwitch", "greenButton", "windowSnap", "finderKeys", "quickMenu", "portManager", "clipboardHistory", "xdrBrightness", "speedTest", "startupItems"])
        XCTAssertEqual(ExtensionFeature.xdrBrightness.installedKey, "feature.xdrBrightness.installed")
        XCTAssertTrue(ExtensionFeature.xdrBrightness.needsAccessibility)
        XCTAssertEqual(AppPermission.accessibility.users(isInstalled: { $0 == .xdrBrightness }), [ExtensionFeature.xdrBrightness.title])
        XCTAssertEqual(AppPermission.accessibility.users(isInstalled: { _ in false }), [])
        XCTAssertEqual(ExtensionFeature.windowSwitcher.installedKey, "feature.windowSwitcher.installed")
    }

    /// 登入項目沒啟用時，權限頁不把「自動化」算成它在用
    func testAutomationPermissionFollowsLoginItems() {
        XCTAssertEqual(AppPermission.automation.users(isInstalled: { _ in false }), [])
        XCTAssertEqual(AppPermission.automation.users(isInstalled: { $0 == .startupItems }).count, 1)
    }

    /// 從舊版更新：沒存過加入狀態時，捲動方向和已經打開過的功能保留，沒用過的新功能不會自己出現；存過的照存的
    func testUpgradeKeepsReleasedFeatures() {
        XCTAssertTrue(!ExtensionFeature.xdrBrightness.isInstalled(stored: nil, switchedOn: false))
        XCTAssertTrue(ExtensionFeature.scrollDirection.isInstalled(stored: nil, switchedOn: false))
        XCTAssertTrue(ExtensionFeature.startupItems.isInstalled(stored: nil, switchedOn: false))
        XCTAssertTrue(!ExtensionFeature.speedTest.isInstalled(stored: nil, switchedOn: false))
        XCTAssertTrue(ExtensionFeature.speedTest.isInstalled(stored: nil, switchedOn: true))
        XCTAssertTrue(!ExtensionFeature.windowSwitcher.isInstalled(stored: nil, switchedOn: false))
        XCTAssertTrue(!ExtensionFeature.inputMethod.isInstalled(stored: nil, switchedOn: false))
        for feature in ExtensionFeature.allCases {
            XCTAssertTrue(feature.isInstalled(stored: true, switchedOn: false))
            XCTAssertTrue(!feature.isInstalled(stored: false, switchedOn: true))
        }
    }

    /// 已經發布過、使用者也打開了的功能（例如舊版就開著視窗切換），更新後不會消失
    func testUpgradeKeepsFeaturesInUse() {
        XCTAssertTrue(ExtensionFeature.windowSwitcher.isInstalled(stored: nil, switchedOn: true))
        XCTAssertTrue(ExtensionFeature.inputMethod.isInstalled(stored: nil, switchedOn: true))
    }

    /// 匯出設定時寫出每個功能實際的加入狀態，沒存過、靠規則算出來的也要寫，換到全新安裝的 Mac 才不會變成沒加入
    func testBackupWritesEveryInstalledState() {
        let values = ExtensionFeature.installedValues { $0 != .inputMethod }
        XCTAssertEqual(values.count, ExtensionFeature.allCases.count)
        XCTAssertEqual(values["feature.scrollDirection.installed"], true)
        XCTAssertEqual(values["feature.windowSwitcher.installed"], true)
        XCTAssertEqual(values["feature.inputMethod.installed"], false)
    }

    /// 全新安裝：擴充功能都不預先加入
    func testFreshInstallAddsNothing() {
        let choices = ExtensionFeature.freshInstallChoices
        XCTAssertEqual(choices.count, ExtensionFeature.allCases.count)
        XCTAssertTrue(choices.values.allSatisfy { !$0 })
    }

    /// 每個功能都有名稱、圖示、分組、標籤與說明，「功能管理」頁才不會出現空白
    func testEveryFeatureIsDescribed() {
        for feature in ExtensionFeature.allCases {
            XCTAssertTrue(!feature.title.isEmpty && !feature.symbol.isEmpty && !feature.detail.isEmpty && !feature.group.isEmpty && !feature.badge.isEmpty)
        }
    }
}
