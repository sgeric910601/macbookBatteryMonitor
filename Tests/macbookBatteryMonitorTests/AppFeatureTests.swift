import Foundation

struct AppFeatureTests {
    /// 原始值存在設定裡（加入狀態的鍵），改名會讓所有人的選擇失效；基本功能不在清單裡
    func testRawValuesAreStable() {
        XCTAssertEqual(AppFeature.allCases.map(\.rawValue), ["scrollDirection", "windowSwitcher"])
        XCTAssertEqual(AppFeature.windowSwitcher.installedKey, "feature.windowSwitcher.installed")
    }

    /// 從舊版更新：沒有存過加入狀態，原本有的功能全部保留
    func testUpgradeKeepsEveryFeature() {
        XCTAssertTrue(AppFeature.isInstalled(stored: nil))
        XCTAssertTrue(AppFeature.isInstalled(stored: true))
        XCTAssertTrue(!AppFeature.isInstalled(stored: false))
    }

    /// 全新安裝：擴充功能都不預先加入
    func testFreshInstallAddsNothing() {
        let choices = AppFeature.freshInstallChoices
        XCTAssertEqual(choices.count, AppFeature.allCases.count)
        XCTAssertTrue(choices.values.allSatisfy { !$0 })
    }

    /// 每個功能都有名稱、圖示、分組、標籤與說明，「功能管理」頁才不會出現空白
    func testEveryFeatureIsDescribed() {
        for feature in AppFeature.allCases {
            XCTAssertTrue(!feature.title.isEmpty && !feature.symbol.isEmpty && !feature.detail.isEmpty && !feature.group.isEmpty && !feature.badge.isEmpty)
        }
    }
}
