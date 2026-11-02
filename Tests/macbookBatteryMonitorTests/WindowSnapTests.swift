import Foundation

struct WindowSnapTests {
    /// 螢幕（左上角為原點的全域座標）與可用範圍（扣掉選單列）
    private let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    private let visible = CGRect(x: 0, y: 39, width: 1800, height: 1130)

    /// 碰到哪個邊緣：左右邊、上緣（選單列也算）、四個角；離邊緣還有距離時不吸附
    func testZones() {
        XCTAssertEqual(WindowSnap.zone(at: CGPoint(x: 0, y: 500), screen: screen), .left)
        XCTAssertEqual(WindowSnap.zone(at: CGPoint(x: 1799, y: 500), screen: screen), .right)
        XCTAssertEqual(WindowSnap.zone(at: CGPoint(x: 900, y: 2), screen: screen), .top)
        XCTAssertEqual(WindowSnap.zone(at: CGPoint(x: 2, y: 30), screen: screen), .topLeft)
        XCTAssertEqual(WindowSnap.zone(at: CGPoint(x: 1798, y: 1160), screen: screen), .bottomRight)
        XCTAssertEqual(WindowSnap.zone(at: CGPoint(x: 900, y: 500), screen: screen), nil)
        XCTAssertEqual(WindowSnap.zone(at: CGPoint(x: 40, y: 500), screen: screen), nil)
        // 底部邊緣不吸附（Dock 在那裡，拖到底部常常只是要放開）
        XCTAssertEqual(WindowSnap.zone(at: CGPoint(x: 900, y: 1168), screen: screen), nil)
    }

    /// 每個位置對應的排版：半邊、填滿、四分之一，都在可用範圍內
    func testTargets() {
        XCTAssertEqual(WindowSnap.target(.left, visible: visible), CGRect(x: 0, y: 39, width: 900, height: 1130))
        XCTAssertEqual(WindowSnap.target(.right, visible: visible), CGRect(x: 900, y: 39, width: 900, height: 1130))
        XCTAssertEqual(WindowSnap.target(.top, visible: visible), visible)
        XCTAssertEqual(WindowSnap.target(.topLeft, visible: visible), CGRect(x: 0, y: 39, width: 900, height: 565))
        XCTAssertEqual(WindowSnap.target(.bottomRight, visible: visible), CGRect(x: 900, y: 604, width: 900, height: 565))
    }

    /// 只有真的在拖視窗（視窗位置跟著動、大小沒變）才吸附；拖選文字、改視窗大小都不算
    func testIsWindowDrag() {
        let start = CGRect(x: 100, y: 100, width: 600, height: 400)
        XCTAssertTrue(WindowSnap.isWindowDrag(from: start, to: start.offsetBy(dx: 300, dy: 50)))
        XCTAssertTrue(!WindowSnap.isWindowDrag(from: start, to: start))
        XCTAssertTrue(!WindowSnap.isWindowDrag(from: start, to: CGRect(x: 100, y: 100, width: 700, height: 400)))
    }

    /// 系統內建的「拖到邊緣排版」：明確關掉才由我們吸附；沒設定過時是系統預設的開
    func testRespectsSystemTiling() {
        XCTAssertTrue(WindowSnap.systemTilingOff(stored: 0))
        XCTAssertTrue(!WindowSnap.systemTilingOff(stored: 1))
        XCTAssertTrue(!WindowSnap.systemTilingOff(stored: nil))
    }
}
