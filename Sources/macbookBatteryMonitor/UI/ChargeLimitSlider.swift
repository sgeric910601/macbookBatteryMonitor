import SwiftUI

/// 主面板資訊卡最上方的充電上限滑桿：拖動後直接改 macOS 系統設定裡的充電上限
struct ChargeLimitSlider: View {
    @ObservedObject var control: SystemChargeLimit
    /// 智慧充電進行中：手動調整會結束排程
    var planActive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                CardTitle("充電上限", systemImage: SymbolCompat.name("battery.100percent.bolt"))
                    .fixedSize()
                Slider(value: position, in: 0...Double(max(1, control.options.count - 1)), step: 1) { editing in
                    control.setEditing(editing)
                }
                .controlSize(.small)
                .help(planActive ? "智慧充電正在調整這個上限；手動拖動會結束目前的排程" : "與系統設定「電池」裡的充電上限是同一個設定，放開後套用")
                Text("\(control.shown)%")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(control.draft == nil ? .primary : .secondary)
                    .frame(width: 42, alignment: .trailing)
            }
            if let note {
                Text(note.text)
                    .font(.caption)
                    .foregroundStyle(note.warning ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var position: Binding<Double> {
        Binding(
            get: { Double(ChargeLimitLogic.index(of: control.shown, in: control.options)) },
            set: { if let limit = ChargeLimitLogic.limit(atIndex: $0, in: control.options) { control.drag(to: limit) } }
        )
    }

    private var note: (text: String, warning: Bool)? {
        if case .failed(let message) = control.status { return (message, true) }
        if !control.enabled, control.limit < 100 { return ("macOS 目前暫時沒有套用這個上限。", false) }
        return nil
    }
}
