import Foundation

struct CapsLockDelayTests {
    /// 取最多的數字，略過標題和 (null)
    func testReadsMostCommonValue() {
        let output = """
        RegistryID  Key                   Value
        1000005df   CapsLockDelayOverride   120
        100000b1d   CapsLockDelayOverride   (null)
        10000093f   CapsLockDelayOverride   120
        100000b0c   CapsLockDelayOverride   0
        """
        XCTAssertEqual(CapsLockDelay.original(fromHidutil: output), 120)
    }

    /// 0 和 30 是本 App 改過留下的；讀不到數字時是 nil（改用 fallback）
    func testIgnoresOurOwnValues() {
        XCTAssertNil(CapsLockDelay.original(fromHidutil: "a CapsLockDelayOverride 30\nb CapsLockDelayOverride 30"))
        XCTAssertNil(CapsLockDelay.original(fromHidutil: "a CapsLockDelayOverride 0"))
        XCTAssertNil(CapsLockDelay.original(fromHidutil: "a CapsLockDelayOverride (null)"))
        XCTAssertNil(CapsLockDelay.original(fromHidutil: ""))
        // 大部分是我們設的 30，少數鍵盤還留著使用者原本的值：用那個值
        XCTAssertEqual(CapsLockDelay.original(fromHidutil: "a CapsLockDelayOverride 30\nb CapsLockDelayOverride 30\nc CapsLockDelayOverride 90"), 90)
    }

    /// 寫回前檢查範圍：負數、極大值或沒有值都用 fallback
    func testRestoreValueIsBounded() {
        XCTAssertEqual(CapsLockDelay.restoreValue(saved: 120), 120)
        XCTAssertEqual(CapsLockDelay.restoreValue(saved: -1), CapsLockDelay.fallback)
        XCTAssertEqual(CapsLockDelay.restoreValue(saved: 99_999_999), CapsLockDelay.fallback)
        XCTAssertEqual(CapsLockDelay.restoreValue(saved: nil), CapsLockDelay.fallback)
        XCTAssertNil(CapsLockDelay.original(fromHidutil: "a CapsLockDelayOverride -1"))
    }
}
