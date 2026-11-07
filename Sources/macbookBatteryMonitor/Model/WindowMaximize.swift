import CoreGraphics

/// 綠色按鈕改成放大，視窗沒有縮放指令時的備用做法：第一次按填滿螢幕的可用範圍（不含選單列與 Dock），記下原本的位置大小；再按一次還原。
/// 座標都是「輔助使用」的全域座標（左上角為原點）。只做計算，攔截與移動視窗在 WindowMaximizeController
struct WindowMaximize {
    /// 差幾點以內算已經填滿（有些 App 會把尺寸對齊到格線或限制最大值）
    static let tolerance: CGFloat = 12

    private var previous: [UInt32: CGRect] = [:]

    static func isFilling(_ frame: CGRect, _ visible: CGRect) -> Bool {
        abs(frame.minX - visible.minX) <= tolerance && abs(frame.minY - visible.minY) <= tolerance
            && abs(frame.width - visible.width) <= tolerance && abs(frame.height - visible.height) <= tolerance
    }

    /// 回傳視窗要變成的位置大小
    mutating func toggle(window: UInt32, frame: CGRect, visible: CGRect) -> CGRect {
        if Self.isFilling(frame, visible) {
            // 已經填滿：有記過原本的就還原；沒記過（使用者自己拉滿的）就維持
            return previous.removeValue(forKey: window) ?? visible
        }
        previous[window] = frame
        return visible
    }

    mutating func forget(window: UInt32) { previous[window] = nil }

    /// 紅黃綠按鈕所在的左上角範圍（點）：一般標題列約在 (8～72, 4～24)，有工具列的視窗按鈕會往下移，所以放寬
    static let trafficLightZone = CGSize(width: 110, height: 64)

    /// 點的位置是否在視窗左上角紅黃綠按鈕那一塊（座標都是左上角為原點）
    static func isNearTrafficLights(_ point: CGPoint, window: CGRect) -> Bool {
        point.x >= window.minX && point.x < window.minX + trafficLightZone.width
            && point.y >= window.minY && point.y < window.minY + trafficLightZone.height
    }
}
