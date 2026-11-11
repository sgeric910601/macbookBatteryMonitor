/// Finder 加強：⌘X 剪下、⌘V 搬移到這裡，F2 重新命名。只在 Finder 是最前面的 App、而且不是在打字（改檔名、搜尋框）時轉換。
/// ⌘X 變成 ⌘C 並記下「要剪下」；下一次 ⌘V 變成 ⌥⌘V（Finder 的「搬移項目到這裡」）。剪貼簿在那之後被換掉
/// （又複製了別的東西）就取消剪下，⌘V 照常拷貝，不會誤把檔案搬走。只做判斷，攔截與改寫按鍵在 FinderKeysController
struct FinderKeys {
    enum Action: Equatable {
        case pass
        /// 改成這個鍵；option：加上 Option（⌘V → ⌥⌘V）。Command 維持原本的狀態
        case remap(keyCode: Int, option: Bool)
    }

    static let xKey = 7, cKey = 8, vKey = 9, f2Key = 120, returnKey = 36

    /// 可能被改寫的只有 ⌘X／⌘C／⌘V 和不按 ⌘ 的 F2：其他（例如改檔名時打一般的 x、c、v）不必問 Finder 焦點在哪
    static func mayRewrite(keyCode: Int, command: Bool) -> Bool { command != (keyCode == f2Key) }

    private(set) var pendingCut = false
    /// 剪下時拷貝完成後的剪貼簿變更次數；之後不一樣就代表又複製了別的
    private var cutPasteboard: Int?
    /// 按 ⌘X 當下的剪貼簿變更次數；拷貝後沒變就代表沒拷貝到東西（例如沒選取），不能剪下
    private var cutStart: Int?

    /// pasteboardChange：目前剪貼簿的變更次數（NSPasteboard.changeCount）
    mutating func keyDown(keyCode: Int, command: Bool, otherModifiers: Bool, finderFront: Bool, editingText: Bool, pasteboardChange: Int) -> Action {
        guard finderFront, !editingText, !otherModifiers else { return .pass }
        switch (keyCode, command) {
        case (Self.xKey, true):
            pendingCut = true
            cutPasteboard = nil
            cutStart = pasteboardChange
            return .remap(keyCode: Self.cKey, option: false)
        case (Self.cKey, true):
            pendingCut = false
            return .pass
        case (Self.vKey, true):
            defer { pendingCut = false }
            // 剪貼簿從按 ⌘X 之後沒變過：⌘C 沒拷貝到東西，貼上的會是之前複製的檔案，不能搬
            guard pendingCut, pasteboardChange != cutStart, cutPasteboard == nil || cutPasteboard == pasteboardChange else { return .pass }
            return .remap(keyCode: Self.vKey, option: true)
        case (Self.f2Key, false):
            return .remap(keyCode: Self.returnKey, option: false)
        default:
            return .pass
        }
    }

    /// 剪下用的 ⌘C 做完後，記下當時的剪貼簿變更次數
    mutating func copied(pasteboardChange: Int) {
        guard pendingCut else { return }
        if pasteboardChange == cutStart {
            pendingCut = false
        } else {
            cutPasteboard = pasteboardChange
        }
    }
}
