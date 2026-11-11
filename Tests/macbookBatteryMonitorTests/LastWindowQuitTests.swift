import Foundation

struct LastWindowQuitTests {
    private let app: Int32 = 42

    private func check(_ logic: LastWindowQuit, server: Int = 0, ax: Int = 0, bundleID: String? = "com.example.Editor",
                       excluded: Set<String> = [], hidden: Bool = false, regular: Bool = true, runningFor: Double? = 60) -> Bool {
        logic.shouldQuit(pid: app, bundleID: bundleID, serverWindows: server, axWindows: ax, excluded: excluded, isHidden: hidden,
                         isRegularApp: regular, runningFor: runningFor)
    }

    /// 原本有視窗、關掉最後一個（兩邊都說沒有視窗了）：結束
    func testQuitsAfterLastWindowCloses() {
        var logic = LastWindowQuit()
        logic.saw(pid: app, windows: 1)
        XCTAssertTrue(check(logic))
    }

    /// 兩邊只要有一邊還看得到視窗就不結束：別的 Space 上的視窗、輔助使用還在回報的視窗
    func testKeepsAppWithWindowsAnywhere() {
        var logic = LastWindowQuit()
        logic.saw(pid: app, windows: 2)
        XCTAssertTrue(!check(logic, server: 1, ax: 0))
        XCTAssertTrue(!check(logic, server: 0, ax: 1))
    }

    /// 從來沒看過它有視窗（選單列工具、剛啟動還沒開視窗）：不結束
    func testNeverQuitsAppsThatHadNoWindows() {
        var logic = LastWindowQuit()
        XCTAssertTrue(!check(logic))
        logic.saw(pid: app, windows: 0)
        XCTAssertTrue(!check(logic))
    }

    /// Finder、例外清單、隱藏中的 App、沒有識別碼的：不結束
    func testExclusions() {
        var logic = LastWindowQuit()
        logic.saw(pid: app, windows: 1)
        XCTAssertTrue(!check(logic, bundleID: "com.apple.finder"))
        XCTAssertTrue(!check(logic, excluded: ["com.example.Editor"]))
        XCTAssertTrue(!check(logic, hidden: true))
        XCTAssertTrue(!check(logic, bundleID: nil))
    }

    /// App 結束後忘掉它；同一個 pid 之後被別的程式用到也不會誤判
    func testForgetsEndedApps() {
        var logic = LastWindowQuit()
        logic.saw(pid: app, windows: 1)
        logic.forget(pid: app)
        XCTAssertTrue(!check(logic))
    }

    /// 通話與虛擬機器一律不結束（接聽來電時電話 App 被結束會掛斷）；背景 App（例如 Raycast 的設定視窗）也不結束
    func testNeverQuitsCallsVirtualMachinesOrBackgroundApps() {
        var logic = LastWindowQuit()
        logic.saw(pid: app, windows: 1)
        for id in ["com.apple.FaceTime", "com.apple.mobilephone", "us.zoom.xos", "com.microsoft.teams2", "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.parallels.desktop.console", "com.vmware.fusion", "com.utmapp.UTM"] {
            XCTAssertTrue(!check(logic, bundleID: id))
        }
        XCTAssertTrue(!check(logic, regular: false))
    }

    /// 還沒啟動完成、或剛啟動不久（啟動畫面關掉、主視窗還沒出現）：不結束
    func testNeverQuitsAppsStillLaunching() {
        var logic = LastWindowQuit()
        logic.saw(pid: app, windows: 1)
        XCTAssertTrue(!check(logic, runningFor: nil))
        XCTAssertTrue(!check(logic, runningFor: 3))
        XCTAssertTrue(check(logic, runningFor: LastWindowQuit.minimumRunTime))
    }
}
