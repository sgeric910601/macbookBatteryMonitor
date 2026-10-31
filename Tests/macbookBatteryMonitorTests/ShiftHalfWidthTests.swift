import Foundation

final class ShiftHalfWidthTests {
    private let a = 0, one = 18, space = 49

    func testShiftLetterSwitchesOnceAndRestoresOnRelease() {
        var logic = ShiftHalfWidth()
        XCTAssertEqual(logic.handle(.keyDown(keyCode: a, shift: true, otherModifiers: false), imeActive: true), .switchToASCII)
        // 還按著 Shift 的下一個字母：已經是英文鍵盤，不再切
        XCTAssertEqual(logic.handle(.keyDown(keyCode: a, shift: true, otherModifiers: false), imeActive: false), .pass)
        XCTAssertEqual(logic.handle(.shiftReleased, imeActive: false), .restore)
        XCTAssertEqual(logic.handle(.shiftReleased, imeActive: true), .pass)
    }

    func testLeavesOtherKeysAlone() {
        var logic = ShiftHalfWidth()
        // 沒按 Shift、數字、空白、Cmd/Ctrl/Option 組合、英文鍵盤下：都不切
        XCTAssertEqual(logic.handle(.keyDown(keyCode: a, shift: false, otherModifiers: false), imeActive: true), .pass)
        XCTAssertEqual(logic.handle(.keyDown(keyCode: one, shift: true, otherModifiers: false), imeActive: true), .pass)
        XCTAssertEqual(logic.handle(.keyDown(keyCode: space, shift: true, otherModifiers: false), imeActive: true), .pass)
        XCTAssertEqual(logic.handle(.keyDown(keyCode: a, shift: true, otherModifiers: true), imeActive: true), .pass)
        XCTAssertEqual(logic.handle(.keyDown(keyCode: a, shift: true, otherModifiers: false), imeActive: false), .pass)
        // 只按 Shift 放開（切換大小寫、選字）：沒切過就不切回
        XCTAssertEqual(logic.handle(.shiftReleased, imeActive: true), .pass)
        XCTAssertEqual(logic.switched, false)
    }

    func testMissedShiftReleaseRestoresOnNextUnshiftedKey() {
        var logic = ShiftHalfWidth()
        XCTAssertEqual(logic.handle(.keyDown(keyCode: a, shift: true, otherModifiers: false), imeActive: true), .switchToASCII)
        XCTAssertEqual(logic.handle(.keyDown(keyCode: a, shift: false, otherModifiers: false), imeActive: false), .restore)
        XCTAssertEqual(logic.switched, false)
    }
}
