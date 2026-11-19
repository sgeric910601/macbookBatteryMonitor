import Foundation

/// 判斷捲動事件來自觸控板還是滑鼠。
/// - 一般滾輪（不連續）一定是滑鼠，而且不會改到觸控板那邊的判斷：觸控板的慣性還在跑時轉一下滾輪，
///   之後的慣性事件仍算觸控板（以前會被改判成滑鼠，跟著滑鼠的設定反向，畫面突然往反方向滑）
/// - 放開手指後的慣性沿用同一段手勢的判斷
/// - 手勢開始時（或沒有階段的連續捲動）看最近觸控板上有沒有兩指；同一段手勢中途只會從滑鼠改成觸控板、
///   不會反過來，主執行緒慢一點、一時沒數到手指也不會中途改判
struct ScrollSource {
    /// 連續捲動的這段手勢（含放開手指後的慣性）是不是觸控板；一般滾輪的事件不會改到它
    private(set) var gestureIsTrackpad = false

    /// - Parameters:
    ///   - scrollPhase: scrollWheelEventScrollPhase（1 放上手指、2 移動中、4 放開、8 取消、128 可能開始，0 沒有階段）
    ///   - recentTouches: 最近 0.3 秒內觸控板上有沒有兩指；只在需要時才讀
    mutating func isTrackpad(continuous: Bool, momentumPhase: Int64, scrollPhase: Int64,
                             recentTouches: @autoclosure () -> Bool) -> Bool {
        guard continuous else { return false }
        if momentumPhase != 0 { return gestureIsTrackpad }
        switch scrollPhase {
        case 2, 4, 8:   // 手指移動中、放開、取消：同一段手勢
            gestureIsTrackpad = gestureIsTrackpad || recentTouches()
        default:        // 剛放上手指（1、128）或沒有階段：新的一段
            gestureIsTrackpad = recentTouches()
        }
        return gestureIsTrackpad
    }
}
