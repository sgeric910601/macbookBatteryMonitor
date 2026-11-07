import Foundation

struct TapAccessTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    /// 第一次偵測到、或上次重開已經很久：重新開啟 App
    func testRelaunchesWhenNotRecentlyRelaunched() {
        XCTAssertEqual(TapAccess.recovery(trustedReported: true, lastRelaunch: nil, now: now), .relaunch)
        XCTAssertEqual(TapAccess.recovery(trustedReported: true, lastRelaunch: now.addingTimeInterval(-TapAccess.relaunchCooldown), now: now), .relaunch)
        XCTAssertEqual(TapAccess.recovery(trustedReported: true, lastRelaunch: now.addingTimeInterval(-3600), now: now), .relaunch)
    }

    /// 剛為了這個重開過又偵測到：可能是誤判，不再重開，避免一直重開
    func testDoesNotRelaunchAgainRightAway() {
        XCTAssertEqual(TapAccess.recovery(trustedReported: true, lastRelaunch: now.addingTimeInterval(-5), now: now), .disable)
        XCTAssertEqual(TapAccess.recovery(trustedReported: true, lastRelaunch: now.addingTimeInterval(-(TapAccess.relaunchCooldown - 1)), now: now), .disable)
        // 時鐘被往回調：當成很久以前，照常重開
        XCTAssertEqual(TapAccess.recovery(trustedReported: true, lastRelaunch: now.addingTimeInterval(60), now: now), .relaunch)
    }

    /// 權限 API 也說沒權限（關掉開關）：只放掉攔截等重新允許，不重開 App，剛重開過也一樣
    func testSwitchedOffWaitsInsteadOfRelaunching() {
        XCTAssertEqual(TapAccess.recovery(trustedReported: false, lastRelaunch: nil, now: now), .waitForPermission)
        XCTAssertEqual(TapAccess.recovery(trustedReported: false, lastRelaunch: now.addingTimeInterval(-5), now: now), .waitForPermission)
    }

    /// 只有剛重開完的那次啟動才說明原因
    func testAnnouncesOnlyRightAfterRelaunch() {
        XCTAssertTrue(TapAccess.shouldAnnounce(lastRelaunch: now.addingTimeInterval(-3), now: now))
        XCTAssertTrue(!TapAccess.shouldAnnounce(lastRelaunch: now.addingTimeInterval(-TapAccess.announceWindow), now: now))
        XCTAssertTrue(!TapAccess.shouldAnnounce(lastRelaunch: nil, now: now))
        XCTAssertTrue(!TapAccess.shouldAnnounce(lastRelaunch: now.addingTimeInterval(10), now: now))
    }
}
