/// 捲動量欄位屬於哪一軸，以及反向時要乘上多少。上下一律反向，左右可以選擇維持原方向
enum ScrollAxes {
    enum Axis { case vertical, horizontal }

    /// CGEventField 的原始值：11／12 行數、96／97 像素、93／94 精細值，
    /// 以及沒有公開文件的 175～178（實測 176／178 垂直、175／177 水平）
    static func axis(ofField raw: Int) -> Axis? {
        switch raw {
        case 11, 96, 93, 176, 178: return .vertical
        case 12, 97, 94, 175, 177: return .horizontal
        default: return nil
        }
    }

    static func multiplier(_ axis: Axis, reverseHorizontal: Bool) -> Double {
        axis == .horizontal && !reverseHorizontal ? 1 : -1
    }
}
