import Carbon
import Foundation

/// 目前的鍵盤配置按著 ⌘ 時，US 鍵盤 Q、W、X、C、V 那幾個位置打出來的字母（⌘Q／⌘W 防誤觸與 Finder 加強用，判斷在 KeyLayout）。
/// 用 ASCII 鍵盤配置（注音、拼音底下是 ABC）按著 ⌘ 的對照表算，和 App 認快捷鍵的方式一樣（Dvorak - QWERTY ⌘ 也對）。
/// 在主執行緒算、切換輸入法時重算；攔截執行緒只讀結果
final class KeyboardLetters: @unchecked Sendable {
    static let shared = KeyboardLetters()

    private let lock = NSLock()
    /// 還沒算出來之前當作 US
    private var letters: [Int: Character] = KeyLayout.usLetters
    private var observer: NSObjectProtocol?

    func letter(at keyCode: Int) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return letters[keyCode].map(String.init)
    }

    /// 開始跟著輸入法更新；重複呼叫沒有影響
    @MainActor
    func start() {
        guard observer == nil else { return }
        update()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { _ in MainActor.assumeIsolatedCompat { KeyboardLetters.shared.update() } }
    }

    @MainActor
    private func update() {
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            // 讀不到配置：不知道字母在哪，全部放行，不猜 US
            lock.lock()
            letters = [:]
            lock.unlock()
            return
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var result: [Int: Character] = [:]
        data.withUnsafeBytes { buffer in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for code in KeyLayout.usLetters.keys {
                var dead: UInt32 = 0, length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), UInt32((cmdKey >> 8) & 0xFF), UInt32(LMGetKbdType()),
                                            OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
                if status == noErr, length > 0, let letter = String(utf16CodeUnits: chars, count: length).lowercased().first {
                    result[code] = letter
                }
            }
        }
        lock.lock()
        letters = result
        lock.unlock()
    }
}
