import Foundation

struct FinderKeysTests {
    private let x = 7, v = 9, c = 8, f2 = 120

    private func press(_ keys: inout FinderKeys, _ code: Int, command: Bool = true, finder: Bool = true, text: Bool = false,
                       pasteboard: Int = 1) -> FinderKeys.Action {
        keys.keyDown(keyCode: code, command: command, otherModifiers: false, finderFront: finder, editingText: text, pasteboardChange: pasteboard)
    }

    /// ⌘X 在 Finder 裡變成 ⌘C 並記下「要剪下」；接著的 ⌘V 變成 ⌥⌘V（搬移到這裡），之後恢復
    func testCutThenPasteMoves() {
        var keys = FinderKeys()
        XCTAssertEqual(press(&keys, x), .remap(keyCode: c, option: false))
        XCTAssertEqual(press(&keys, v, pasteboard: 2), .remap(keyCode: v, option: true))
        XCTAssertEqual(press(&keys, v, pasteboard: 2), .pass)
    }

    /// 剪下之後剪貼簿又被換掉（又複製了別的）：⌘V 恢復成一般的拷貝，不會誤把檔案搬走
    func testPasteboardChangeCancelsCut() {
        var keys = FinderKeys()
        _ = press(&keys, x, pasteboard: 1)
        // 剪下時 ⌘C 讓剪貼簿變成 2；之後又被別的程式改成 3
        keys.copied(pasteboardChange: 2)
        XCTAssertEqual(press(&keys, v, pasteboard: 3), .pass)
        // 剪下後在 Finder 裡又按 ⌘C：取消剪下
        var again = FinderKeys()
        _ = press(&again, x)
        again.copied(pasteboardChange: 2)
        XCTAssertEqual(press(&again, c, pasteboard: 2), .pass)
        XCTAssertEqual(press(&again, v, pasteboard: 3), .pass)
    }

    /// F2 在 Finder 裡變成 Return（重新命名）
    func testF2Renames() {
        var keys = FinderKeys()
        XCTAssertEqual(press(&keys, f2, command: false), .remap(keyCode: 36, option: false))
    }

    /// 不在 Finder、正在改檔名或在搜尋框打字、加了其他修飾鍵：都不轉換
    func testLeavesOthersAlone() {
        var keys = FinderKeys()
        XCTAssertEqual(press(&keys, x, finder: false), .pass)
        XCTAssertEqual(press(&keys, x, text: true), .pass)
        XCTAssertEqual(press(&keys, f2, command: false, text: true), .pass)
        XCTAssertEqual(keys.keyDown(keyCode: x, command: true, otherModifiers: true, finderFront: true, editingText: false, pasteboardChange: 1), .pass)
        XCTAssertEqual(press(&keys, v), .pass)
    }
}
