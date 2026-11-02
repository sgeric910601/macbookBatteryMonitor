import CoreGraphics

/// 視窗吸附：拖著視窗碰到螢幕邊緣，放開後排成半邊、填滿或四分之一。座標是左上角為原點的全域座標。
/// 只做判斷，監聽滑鼠、預覽與移動視窗在 WindowSnapController
enum WindowSnap {
    enum Zone: Equatable { case left, right, top, topLeft, topRight, bottomLeft, bottomRight }

    /// 離邊緣幾點以內算碰到
    static let edge: CGFloat = 6
    /// 角落：離上下緣這麼近又碰到左右邊時算角落
    static let corner: CGFloat = 60

    /// 底部邊緣不吸附：Dock 常在那裡，拖到底部多半只是要放開
    static func zone(at point: CGPoint, screen: CGRect) -> Zone? {
        let left = point.x <= screen.minX + edge, right = point.x >= screen.maxX - 1 - edge
        let top = point.y <= screen.minY + edge
        let nearTop = point.y <= screen.minY + corner, nearBottom = point.y >= screen.maxY - corner
        if left { return nearTop ? .topLeft : nearBottom ? .bottomLeft : .left }
        if right { return nearTop ? .topRight : nearBottom ? .bottomRight : .right }
        return top ? .top : nil
    }

    static func target(_ zone: Zone, visible: CGRect) -> CGRect {
        let halfWidth = (visible.width / 2).rounded(.down), halfHeight = (visible.height / 2).rounded(.down)
        let rightX = visible.minX + halfWidth, lowerY = visible.minY + halfHeight
        switch zone {
        case .left: return CGRect(x: visible.minX, y: visible.minY, width: halfWidth, height: visible.height)
        case .right: return CGRect(x: rightX, y: visible.minY, width: visible.width - halfWidth, height: visible.height)
        case .top: return visible
        case .topLeft: return CGRect(x: visible.minX, y: visible.minY, width: halfWidth, height: halfHeight)
        case .topRight: return CGRect(x: rightX, y: visible.minY, width: visible.width - halfWidth, height: halfHeight)
        case .bottomLeft: return CGRect(x: visible.minX, y: lowerY, width: halfWidth, height: visible.height - halfHeight)
        case .bottomRight: return CGRect(x: rightX, y: lowerY, width: visible.width - halfWidth, height: visible.height - halfHeight)
        }
    }

    /// 視窗位置跟著動、大小沒變，才是在拖視窗（拖選文字時視窗不動；拉邊緣改大小時尺寸會變）
    static func isWindowDrag(from start: CGRect, to now: CGRect) -> Bool {
        start.origin != now.origin && abs(start.width - now.width) < 1 && abs(start.height - now.height) < 1
    }

    /// 系統內建的「拖到螢幕邊緣排版」明確關掉時才由我們吸附；沒設定過是系統預設的開
    static func systemTilingOff(stored: Int?) -> Bool { stored == 0 }
}
