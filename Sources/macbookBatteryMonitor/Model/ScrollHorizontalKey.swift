/// 按住某個鍵時，一般滑鼠滾輪改成左右捲動。觸控板本來就能左右滑，不處理
enum ScrollHorizontalKey: String, CaseIterable {
    case off, shift, option, control

    init(stored: String?) { self = stored.flatMap(Self.init(rawValue:)) ?? .off }

    /// CGEventFlags 的原始值
    private var mask: UInt64 {
        switch self {
        case .off: return 0
        case .shift: return 0x20000
        case .option: return 0x80000
        case .control: return 0x40000
        }
    }

    var title: String {
        switch self {
        case .off: return "關閉"
        case .shift: return "按住 Shift"
        case .option: return "按住 Option"
        case .control: return "按住 Control"
        }
    }

    func swaps(flags: UInt64, continuous: Bool) -> Bool {
        self != .off && !continuous && flags & mask != 0
    }

    /// 轉換後拿掉這個鍵：App 自己也會把 Shift＋滾輪轉成左右，留著會再轉回上下
    func flagsAfterSwap(_ flags: UInt64) -> UInt64 { flags & ~mask }
}
