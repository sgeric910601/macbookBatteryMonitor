import SwiftUI

/// 設定 → 顯示項目：電力流向細項與詳細資訊欄位要不要顯示（接在選單列卡片下面）
struct DisplayItemsView: View {
    let settings: AppSettings
    /// 主面板有充電上限滑桿（充電上限不列在詳細資訊）
    var limitSlider = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("電力流向細項", systemImage: "arrow.triangle.branch")
                    checkboxes(FlowItem.systemLevel)
                    Text("晶片運算展開後").font(.caption).foregroundStyle(.secondary)
                    checkboxes(FlowItem.chipLevel)
                        .disabled(!settings.isVisible(.chip))
                    Text(settings.isVisible(.chip)
                         ? "這台 Mac 讀不到的項目會自動隱藏。"
                         : "隱藏晶片運算後無法展開 CPU、GPU、ANE。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("詳細資訊欄位", systemImage: "list.bullet.rectangle")
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        let fields = DetailField.available(limitSlider: limitSlider)
                        ForEach(Array(stride(from: 0, to: fields.count, by: 2)), id: \.self) { index in
                            GridRow {
                                checkbox(fields[index])
                                if index + 1 < fields.count { checkbox(fields[index + 1]) }
                            }
                        }
                    }
                    Toggle("顯示充電器規格", isOn: Binding(
                        get: { settings.showChargerSpecifications },
                        set: { settings.showChargerSpecifications = $0 }))
                    Text("顯示在詳細資訊欄位下方；未連接充電器時自動隱藏。")
                        .font(.caption).foregroundStyle(.secondary)
                    if !settings.chargerNames.isEmpty { namedChargers }
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

    /// 已命名的充電器：在面板的充電器規格按「命名…」加入，這裡只能刪除
    private var namedChargers: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("已命名的充電器").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
            // 同名的合成一行：同一顆充電器在不同供電情況（分給多個孔、接 MagSafe）會各存一筆
            ForEach(Dictionary(grouping: settings.chargerNames, by: \.value).sorted { $0.key < $1.key }, id: \.key) { name, entries in
                let keys = entries.map(\.key).sorted()
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name)
                        Text(keys.count == 1 ? AdapterInfo.describe(fingerprint: keys[0]) : "\(keys.count) 種供電組合 · " + AdapterInfo.vendorSummary(keys))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button(role: .destructive) { keys.forEach { settings.chargerNames[$0] = nil } } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("刪除這個名稱")
                    .accessibilityLabel("刪除 \(name)")
                }
            }
            Text("刪除會移除這個名稱的所有供電組合；改名請在面板的充電器規格按「改名…」。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
