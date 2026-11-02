import Foundation

struct SmoothScrollTests {
    /// 一格的捲動量拆成多個小步：總和剛好等於原本的量，一步比一步小（先快後慢），幾十個畫格內結束
    func testSplitsTickIntoEasingSteps() {
        var smooth = SmoothScroll()
        smooth.add(dx: 0, dy: 100)
        var steps: [Double] = []
        while let step = smooth.step() { steps.append(step.dy) }
        XCTAssertEqual(steps.reduce(0, +), 100)
        XCTAssertTrue(steps.count > 5 && steps.count < SmoothScroll.maxFrames)
        XCTAssertTrue(zip(steps, steps.dropFirst()).allSatisfy { $0 >= $1 })
        XCTAssertTrue(smooth.isIdle)
    }

    /// 動畫中又轉一格同方向：接著累加；轉反方向：丟掉剩下的，直接改成新方向
    func testAccumulatesAndReverses() {
        var same = SmoothScroll()
        same.add(dx: 0, dy: 40)
        _ = same.step()
        same.add(dx: 0, dy: 40)
        var total = 0.0
        while let step = same.step() { total += step.dy }
        XCTAssertTrue(total > 40 && total <= 80)
        var flip = SmoothScroll()
        flip.add(dx: 0, dy: 40)
        _ = flip.step()
        flip.add(dx: 0, dy: -30)
        var back = 0.0
        while let step = flip.step() { back += step.dy }
        XCTAssertEqual(back, -30)
    }

    /// 左右各自計算；沒有捲動量時不產生任何步
    func testAxesAndIdle() {
        var smooth = SmoothScroll()
        XCTAssertTrue(smooth.step() == nil)
        smooth.add(dx: -50, dy: 0)
        var dx = 0.0, dy = 0.0
        while let step = smooth.step() { dx += step.dx; dy += step.dy }
        XCTAssertEqual(dx, -50)
        XCTAssertEqual(dy, 0)
    }
}
