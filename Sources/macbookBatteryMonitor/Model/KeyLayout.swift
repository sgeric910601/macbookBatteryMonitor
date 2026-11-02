/// ⌘Q／⌘W 防誤觸與 Finder 加強用鍵碼（按鍵的位置）判斷，鍵碼是 US 鍵盤的位置。
/// 只有那個位置打出來的字母真的是那個字母時才算（ABC、US、注音、拼音、德文 QWERTZ 等）；
/// 字母在別的位置的配置（法文 AZERTY 的 Q、W，Dvorak）不處理，照原本的按鍵放行，不會改到別的快捷鍵
enum KeyLayout {
    /// 各鍵碼在 US 配置打出來的字母
    static let usLetters: [Int: Character] = [12: "q", 13: "w", 7: "x", 8: "c", 9: "v"]

    /// character：這個位置在目前配置（按著 ⌘ 時）打出來的字，由 KeyboardLetters 算。
    /// 字母鍵的位置和字母對不上時回傳 nil（不處理）；不是字母鍵（F2、Return）原樣回傳
    static func usKeyCode(_ keyCode: Int, character: String?) -> Int? {
        guard let letter = usLetters[keyCode] else { return keyCode }
        return character?.lowercased().first == letter ? keyCode : nil
    }
}
