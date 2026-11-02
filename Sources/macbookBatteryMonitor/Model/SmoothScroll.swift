/// 平滑捲動：一般滾輪每一格的捲動量拆成很多小步，每個畫格送出剩下的四分之一（至少 1 點），先快後慢。
/// 用整數點計算，加總剛好等於原本的量。只做計算，畫格的計時與送出事件在 ScrollTap
struct SmoothScroll {
    /// 每格送出剩下的幾分之幾
    static let fraction = 0.25
    /// 一次動畫最多幾個畫格（120 Hz 下約半秒）；只用來限制測試
    static let maxFrames = 60

    private var remainingX = 0
    private var remainingY = 0

    var isIdle: Bool { remainingX == 0 && remainingY == 0 }

    /// 加入一格的捲動量（點）。同方向接著累加；反方向丟掉剩下的，直接改成新方向
    mutating func add(dx: Double, dy: Double) {
        remainingX = Self.merge(remainingX, Int(dx.rounded()))
        remainingY = Self.merge(remainingY, Int(dy.rounded()))
    }

    private static func merge(_ remaining: Int, _ new: Int) -> Int {
        if new == 0 { return remaining }
        return remaining == 0 || (remaining > 0) == (new > 0) ? remaining + new : new
    }

    /// 這個畫格要送出的量；沒有剩下時回傳 nil
    mutating func step() -> (dx: Double, dy: Double)? {
        guard !isIdle else { return nil }
        let x = Self.take(remainingX), y = Self.take(remainingY)
        remainingX -= x
        remainingY -= y
        return (Double(x), Double(y))
    }

    private static func take(_ remaining: Int) -> Int {
        guard remaining != 0 else { return 0 }
        let size = max(1, Int((Double(abs(remaining)) * fraction).rounded(.up)))
        return remaining > 0 ? min(size, remaining) : -min(size, -remaining)
    }
}
