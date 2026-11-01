import Foundation

struct ExtensionFeatureTests {
    /// 原始值存在設定裡（加入狀態的鍵），改名會讓所有人的選擇失效；基本功能不在清單裡
    func testRawValuesAreStable() {
        XCTAssertEqual(ExtensionFeature.allCases.map(\.rawValue), ["scrollDirection", "windowSwitcher", "inputMethod"])
        XCTAssertEqual(ExtensionFeature.windowSwitcher.installedKey, "feature.windowSwitcher.installed")
    }

    /// 從舊版更新：沒存過加入狀態時，舊版就有的功能保留，新功能不會自己出現；存過的照存的
    func testUpgradeKeepsReleasedFeatures() {
        XCTAssertTrue(ExtensionFeature.scrollDirection.isInstalled(stored: nil))
        XCTAssertTrue(!ExtensionFeature.windowSwitcher.isInstalled(stored: nil))
        XCTAssertTrue(!ExtensionFeature.inputMethod.isInstalled(stored: nil))
        for feature in ExtensionFeature.allCases {
            XCTAssertTrue(feature.isInstalled(stored: true))
            XCTAssertTrue(!feature.isInstalled(stored: false))
        }
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
