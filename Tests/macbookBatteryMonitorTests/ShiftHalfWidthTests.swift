import Foundation

final class ShiftHalfWidthTests {
    private let a = 0, j = 38, one = 18, space = 49, comma = 43

    private func down(_ code: Int, shift: Bool = true, other: Bool = false) -> ShiftHalfWidth.Event {
        .keyDown(keyCode: code, shift: shift, otherModifiers: other)
    }

    /// 按住 Shift 的第一個字先送出組字，同一次按住的後面幾個字直接轉成半形；放開後下一次按住又從頭
    func testFirstKeyOfAHoldCommitsCompositionFirst() {
        var logic = ShiftHalfWidth()
        XCTAssertEqual(logic.handle(down(a), imeActive: true), .halfWidth(commitFirst: true))
        XCTAssertEqual(logic.handle(.keyUp(keyCode: a, shift: true), imeActive: true), .halfWidth(commitFirst: false))
        XCTAssertEqual(logic.handle(down(one), imeActive: true), .halfWidth(commitFirst: false))
        XCTAssertEqual(logic.handle(.shiftReleased, imeActive: true), .pass)
        XCTAssertEqual(logic.holding, false)
        XCTAssertEqual(logic.handle(down(comma), imeActive: true), .halfWidth(commitFirst: true))
    }

    /// 送出組字時會短暫切到英文鍵盤，那時讀到的「不是中文輸入法」不能中斷同一次按住
    func testKeepsConvertingWhileTheCommitSwitchesSources() {
        var logic = ShiftHalfWidth()
        XCTAssertEqual(logic.handle(down(a), imeActive: true), .halfWidth(commitFirst: true))
        XCTAssertEqual(logic.handle(down(j), imeActive: false), .halfWidth(commitFirst: false))
        XCTAssertEqual(logic.handle(.keyUp(keyCode: j, shift: true), imeActive: false), .halfWidth(commitFirst: false))
    }

    func testLeavesOtherKeysAlone() {
        var logic = ShiftHalfWidth()
        // 沒按 Shift、空白（注音的全半形切換）、Cmd/Ctrl/Option 組合、非中文輸入法：都不動
        XCTAssertEqual(logic.handle(down(a, shift: false), imeActive: true), .pass)
        XCTAssertEqual(logic.handle(down(space), imeActive: true), .pass)
        XCTAssertEqual(logic.handle(down(a, other: true), imeActive: true), .pass)
        XCTAssertEqual(logic.handle(down(a), imeActive: false), .pass)
        // 沒在按住期間的放開：不轉換
        XCTAssertEqual(logic.handle(.keyUp(keyCode: a, shift: true), imeActive: true), .pass)
        XCTAssertEqual(logic.handle(.shiftReleased, imeActive: true), .pass)
        XCTAssertEqual(logic.holding, false)
    }

    /// 漏掉放開 Shift 的事件時，下一個沒按 Shift 的字照常交給輸入法，下次按住重新送出組字
    func testMissedShiftReleaseEndsTheHold() {
        var logic = ShiftHalfWidth()
        XCTAssertEqual(logic.handle(down(a), imeActive: true), .halfWidth(commitFirst: true))
        XCTAssertEqual(logic.handle(down(j, shift: false), imeActive: true), .pass)
        XCTAssertEqual(logic.holding, false)
        XCTAssertEqual(logic.handle(down(j), imeActive: true), .halfWidth(commitFirst: true))
    }

    /// 和美式鍵盤按 Shift 打出來的一樣
    func testHalfWidthCharacters() {
        let expected: [Int: String] = [0: "A", 6: "Z", 38: "J", 46: "M",
                                       18: "!", 19: "@", 20: "#", 21: "$", 23: "%", 22: "^",
                                       26: "&", 28: "*", 25: "(", 29: ")", 27: "_", 24: "+",
                                       50: "~", 33: "{", 30: "}", 42: "|", 41: ":", 39: "\"", 43: "<", 47: ">", 44: "?"]
        for (code, text) in expected { XCTAssertEqual(ShiftHalfWidth.halfWidthText(keyCode: code), text) }
        let letters = (0..<128).compactMap { ShiftHalfWidth.halfWidthText(keyCode: $0) }.filter { $0.first!.isLetter }
        XCTAssertEqual(Set(letters).count, 26)
        // 空白、Return、方向鍵、數字鍵盤：不轉換
        for code in [49, 36, 123, 124, 82, 65] { XCTAssertEqual(ShiftHalfWidth.halfWidthText(keyCode: code), nil) }
    }

    /// 只有中文輸入法算：俄文、韓文、日文、英文鍵盤都不處理
    func testOnlyChineseInputMethods() {
        XCTAssertTrue(ShiftHalfWidth.isChineseInputMethod(languages: ["zh-Hant"], asciiCapable: false))
        XCTAssertTrue(ShiftHalfWidth.isChineseInputMethod(languages: ["zh-Hans", "en"], asciiCapable: false))
        XCTAssertTrue(!ShiftHalfWidth.isChineseInputMethod(languages: ["ru"], asciiCapable: false))
        XCTAssertTrue(!ShiftHalfWidth.isChineseInputMethod(languages: ["ko"], asciiCapable: false))
        XCTAssertTrue(!ShiftHalfWidth.isChineseInputMethod(languages: ["ja"], asciiCapable: false))
        XCTAssertTrue(!ShiftHalfWidth.isChineseInputMethod(languages: ["zh-Hant"], asciiCapable: true))
        XCTAssertTrue(!ShiftHalfWidth.isChineseInputMethod(languages: [], asciiCapable: false))
    }
}
