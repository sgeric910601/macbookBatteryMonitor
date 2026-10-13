import SwiftUI

/// 設定 → 顯示項目：電力流向細項與詳細資訊欄位要不要顯示
struct DisplayItemsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: PanelState
    /// 主面板有充電上限滑桿（充電上限不列在詳細資訊）
    var limitSlider = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Text("顯示項目").font(.headline)
                HStack {
                    Button {
                        ui.page = .settings
                    } label: {
                        Label("設定", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("電力流向細項", systemImage: "arrow.triangle.branch")
                    checkboxes(FlowItem.systemLevel)
                    Text("晶片運算展開後").font(.caption).foregroundStyle(.secondary)
                    checkboxes(FlowItem.chipLevel)
                        .disabled(!settings.isVisible(.chip))
                    Text(settings.isVisible(.chip)
                         ? "讀不到的項目會自動隱藏：例如 M1 MacBook Air 沒有 ANE 通道與螢幕背光感測器，背光改算在「其他」裡。"
                         : "隱藏晶片運算後無法展開 CPU、GPU、ANE。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("詳細資訊欄位", systemImage: "list.bullet.rectangle")
                    VStack(alignment: .leading, spacing: 6) {
                        let fields = DetailField.available(limitSlider: limitSlider)
                        ForEach(Array(stride(from: 0, to: fields.count, by: 2)), id: \.self) { index in
                            TwoColumns {
                                checkbox(fields[index])
                            } right: {
                                if index + 1 < fields.count { checkbox(fields[index + 1]) }
                            }
                        }
                    }
                    if limitSlider {
                        Text("充電上限顯示在主面板的滑桿上，這裡不再重複。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                Button("全部顯示") {
                    settings.hiddenFlowItems = []
                    settings.hiddenDetailFields = []
                }
                .disabled(settings.hiddenFlowItems.isEmpty && settings.hiddenDetailFields.isEmpty)
            }
        }
        .padding(14)
    }

    private func checkboxes(_ items: [FlowItem]) -> some View {
        HStack(spacing: 16) {
            ForEach(items) { item in
                Toggle(item.title, isOn: Binding(get: { settings.isVisible(item) }, set: { settings.setVisible(item, $0) }))
                    .toggleStyle(.checkbox)
            }
        }
    }

    private func checkbox(_ field: DetailField) -> some View {
        Toggle(field.title, isOn: Binding(get: { settings.isVisible(field) }, set: { settings.setVisible(field, $0) }))
            .toggleStyle(.checkbox)
    }
}
