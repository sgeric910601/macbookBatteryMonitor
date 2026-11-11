/// 線性捲動：一般滑鼠滾輪每一格固定捲幾行，不隨轉動速度加速。觸控板與 Magic Mouse 的連續捲動不處理
enum ScrollLinear {
    struct Delta: Equatable {
        var lines: Int64
        var fixed: Double
        var points: Int64
    }

    /// 0 是關閉
    static let choices = [0, 1, 3, 5]
    /// 一行大約幾點（像素欄位用）
    static let pointsPerLine: Int64 = 10

    static func valid(_ lines: Int) -> Int { choices.contains(lines) ? lines : 0 }

    /// lines：系統給的行數（已經加速過）；只取方向，大小換成設定的行數。
    /// 行數是 0 時看小數行數與像素量（慢慢轉、或遠端桌面送的事件），三個都是 0 才算這一軸沒有捲動
    static func adjust(lines: Int64, fixed: Double = 0, points: Int64 = 0, lineSetting: Int) -> Delta {
        let direction = lines != 0 ? Double(lines) : fixed != 0 ? fixed : Double(points)
        let sign: Int64 = direction > 0 ? 1 : direction < 0 ? -1 : 0
        let fixed = sign * Int64(lineSetting)
        return Delta(lines: fixed, fixed: Double(fixed), points: fixed * pointsPerLine)
    }
}
