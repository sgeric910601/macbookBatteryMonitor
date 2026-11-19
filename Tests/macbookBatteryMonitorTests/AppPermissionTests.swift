import Foundation

struct AppPermissionTests {
    /// 輔助使用：列出加入了的擴充功能；都沒加入時沒有用到
    func testAccessibilityFollowsAddedFeatures() {
        XCTAssertEqual(AppPermission.accessibility.users(isInstalled: { _ in true }), ["捲動方向", "視窗切換", "中文輸入法", "⌘Q／⌘W 防誤觸", "關閉最後視窗時結束 App", "點 Dock 圖示縮到 Dock", "鍵盤清潔模式", "滑鼠側鍵", "綠色按鈕放大", "視窗吸附", "Finder 加強", "XDR 額外增亮"])
        XCTAssertEqual(AppPermission.accessibility.users(isInstalled: { $0 == .windowSwitcher }), ["視窗切換"])
        XCTAssertEqual(AppPermission.accessibility.users(isInstalled: { _ in false }), [])
        // 螢幕錄製只有視窗切換的縮圖用到
        XCTAssertEqual(AppPermission.screenRecording.users(isInstalled: { $0 == .scrollDirection }), [])
        XCTAssertEqual(AppPermission.screenRecording.users(isInstalled: { $0 == .windowSwitcher }), ["視窗切換的縮圖（選用）"])
    }

    /// 基本功能用到的權限一直都有人用；每一項都有名稱、說明與系統設定的位置
    func testEveryPermissionIsDescribed() {
        for permission in [AppPermission.notifications, .bluetooth] {
            XCTAssertTrue(!permission.users(isInstalled: { _ in false }).isEmpty)
        }
        for permission in AppPermission.allCases {
            XCTAssertTrue(!permission.title.isEmpty && !permission.symbol.isEmpty)
            XCTAssertTrue(permission.settingsURL.absoluteString.hasPrefix("x-apple.systempreferences:"))
        }
    }
}
