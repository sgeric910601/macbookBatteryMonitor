import Foundation

struct ScrollSourceTests {
    /// 一般滾輪一定是滑鼠，而且不改到觸控板手勢的判斷：慣性中轉一下滾輪，之後的慣性仍算觸控板
    func testWheelDoesNotBreakTrackpadMomentum() {
        var source = ScrollSource()
        XCTAssertTrue(source.isTrackpad(continuous: true, momentumPhase: 0, scrollPhase: 1, recentTouches: true))
        XCTAssertTrue(!source.isTrackpad(continuous: false, momentumPhase: 0, scrollPhase: 0, recentTouches: true))
        XCTAssertTrue(source.isTrackpad(continuous: true, momentumPhase: 2, scrollPhase: 0, recentTouches: false))
    }

    /// 同一段手勢中途只會從滑鼠改成觸控板，不會反過來（一時沒數到手指不中途改判）
    func testGestureOnlyUpgradesToTrackpad() {
        var source = ScrollSource()
        XCTAssertTrue(source.isTrackpad(continuous: true, momentumPhase: 0, scrollPhase: 1, recentTouches: true))
        XCTAssertTrue(source.isTrackpad(continuous: true, momentumPhase: 0, scrollPhase: 2, recentTouches: false))
        XCTAssertTrue(source.isTrackpad(continuous: true, momentumPhase: 0, scrollPhase: 4, recentTouches: false))
        // 新的一段（例如 Magic Mouse）沒有兩指：滑鼠；中途數到兩指才改成觸控板
        XCTAssertTrue(!source.isTrackpad(continuous: true, momentumPhase: 0, scrollPhase: 1, recentTouches: false))
        XCTAssertTrue(!source.isTrackpad(continuous: true, momentumPhase: 0, scrollPhase: 2, recentTouches: false))
        XCTAssertTrue(source.isTrackpad(continuous: true, momentumPhase: 0, scrollPhase: 2, recentTouches: true))
    }

    /// 沒有階段的連續捲動每次都重新判斷；慣性沿用前一段
    func testNoPhaseStartsOverAndMomentumFollows() {
        var source = ScrollSource()
        XCTAssertTrue(source.isTrackpad(continuous: true, momentumPhase: 0, scrollPhase: 0, recentTouches: true))
        XCTAssertTrue(!source.isTrackpad(continuous: true, momentumPhase: 0, scrollPhase: 0, recentTouches: false))
        XCTAssertTrue(!source.isTrackpad(continuous: true, momentumPhase: 1, scrollPhase: 0, recentTouches: true))
    }

    /// 不連續或慣性中不讀手指時間（那要搶鎖）
    func testReadsTouchesOnlyWhenNeeded() {
        var source = ScrollSource()
        var reads = 0
        func touches() -> Bool { reads += 1; return true }
        _ = source.isTrackpad(continuous: false, momentumPhase: 0, scrollPhase: 1, recentTouches: touches())
        _ = source.isTrackpad(continuous: true, momentumPhase: 2, scrollPhase: 0, recentTouches: touches())
        XCTAssertEqual(reads, 0)
        _ = source.isTrackpad(continuous: true, momentumPhase: 0, scrollPhase: 1, recentTouches: touches())
        XCTAssertEqual(reads, 1)
    }
}
