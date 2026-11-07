import Foundation

struct ScrollHorizontalKeyTests {
    private let shift: UInt64 = 0x20000, control: UInt64 = 0x40000, option: UInt64 = 0x80000, command: UInt64 = 0x100000

    /// 按住設定的鍵轉一般滾輪：改成左右；觸控板、沒按那個鍵、關閉時不動
    func testWhenToSwap() {
        XCTAssertTrue(ScrollHorizontalKey.shift.swaps(flags: shift, continuous: false))
        XCTAssertTrue(ScrollHorizontalKey.option.swaps(flags: option | shift, continuous: false))
        XCTAssertTrue(!ScrollHorizontalKey.shift.swaps(flags: shift, continuous: true))
        XCTAssertTrue(!ScrollHorizontalKey.option.swaps(flags: shift, continuous: false))
        XCTAssertTrue(!ScrollHorizontalKey.off.swaps(flags: shift | option | control, continuous: false))
    }

    /// 轉換後拿掉那個鍵（App 自己也會把 Shift＋滾輪轉成左右，留著會轉回上下）；其他按鍵保留
    func testClearsOnlyItsModifier() {
        XCTAssertEqual(ScrollHorizontalKey.shift.flagsAfterSwap(shift | command), command)
        XCTAssertEqual(ScrollHorizontalKey.control.flagsAfterSwap(control | shift), shift)
    }

    /// 存在設定裡的值不認得時當作關閉（包括匯入的設定）
    func testStoredValues() {
        XCTAssertEqual(ScrollHorizontalKey.allCases.map(\.rawValue), ["off", "shift", "option", "control"])
        XCTAssertEqual(ScrollHorizontalKey(stored: "option"), .option)
        XCTAssertEqual(ScrollHorizontalKey(stored: "command"), .off)
        XCTAssertEqual(ScrollHorizontalKey(stored: nil), .off)
    }
}
