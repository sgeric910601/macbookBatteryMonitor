import Foundation

struct LastWindowQuitTests {
    private let app: Int32 = 42

    private func check(_ logic: LastWindowQuit, server: Int = 0, ax: Int = 0, bundleID: String? = "com.example.Editor",
                       excluded: Set<String> = [], hidden: Bool = false) -> Bool {
        logic.shouldQuit(pid: app, bundleID: bundleID, serverWindows: server, axWindows: ax, excluded: excluded, isHidden: hidden)
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
}
