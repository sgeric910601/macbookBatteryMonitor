import AppKit
import SwiftUI

/// 設定視窗「登入項目」分頁
struct StartupItemsView: View {
    let manager: StartupItemsManager
    @State private var pendingRemoval: StartupItem?
    @State private var pendingToggle: (item: StartupItem, enabled: Bool)?
    /// 目前打開詳細頁的項目；nil 時顯示清單
    @State private var selectedID: String?

    private var selected: StartupItem? { manager.items.first { $0.id == selectedID } }

    var body: some View {
        Group {
            if let item = selected { detailPage(item) } else { listPage }
        }
        .onAppear { manager.reload() }
        // 回到設定視窗（例如從 Finder 刪完檔案回來）時重新讀取
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if (note.object as? NSWindow)?.title == "設定" { manager.reload() }
        }
        .confirmationDialog("移除登入項目？", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("移除", role: .destructive) { if let item = pendingRemoval { manager.remove(item) }; pendingRemoval = nil }
            Button("取消", role: .cancel) { pendingRemoval = nil }
        } message: {
            if let item = pendingRemoval, item.kind != .loginItem {
                Text("「\(item.name)」的程式已經不存在。設定檔會移到垃圾桶，之後可以放回去。" + (item.kind == .userAgent ? "" : "系統層級的項目需要輸入管理員密碼。"))
            } else {
                Text("「\(pendingRemoval?.name ?? "")」不會再於登入時打開，App 本身不會被刪除。")
            }
        }
        .confirmationDialog("變更這個項目？", isPresented: Binding(get: { pendingToggle != nil }, set: { if !$0 { pendingToggle = nil } })) {
            Button(pendingToggle?.enabled == true ? "啟用" : "停用") {
                if let change = pendingToggle { manager.setEnabled(change.item, change.enabled) }
                pendingToggle = nil
            }
            Button("取消", role: .cancel) { pendingToggle = nil }
        } message: { Text("「\(pendingToggle?.item.name ?? "")」") }
    }

    private func detailPage(_ item: StartupItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { selectedID = nil } label: { Label("返回清單", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Button("重新檢查") { manager.reload() }.controlSize(.small)
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(nsImage: icon(for: item)).resizable().frame(width: 40, height: 40).opacity(item.missing ? 0.5 : 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.headline)
                            Text(item.kind.title + (item.enabled ? "" : "・已停用") + (item.missing ? "・程式已不存在" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    detailsBody(item)
                        .task(id: manager.reloadCount) { manager.loadDetails(item) }
                }
            }
            if let label = item.label, let url = StartupItemInfoLogic.searchURL(for: label) {
                Button("上網搜尋「\(label)」") { NSWorkspace.shared.open(url) }
                    .help("用瀏覽器開啟搜尋引擎，只會送出這個識別名稱")
            }
            if item.canRemove {
                Button(item.kind == .loginItem ? "移除這個登入項目" : "把設定檔移到垃圾桶", role: .destructive) { pendingRemoval = item }
            }
            Text("這裡只提供資訊與檔案位置。名稱相似的檔案可能屬於其他軟體，請自行確認後再處理。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var listPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("共 \(manager.items.count) 個項目").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if manager.loading { ProgressView().controlSize(.small) }
                        Button("重新整理") { manager.reload() }.controlSize(.small)
                    }
                    if manager.items.isEmpty && !manager.loading {
                        Text("沒有找到項目。").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(manager.items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            row(item)
                        }
                        if item.id != manager.items.last?.id { Divider() }
                    }
                }
            }
            HStack {
                Button("新增登入項目⋯", action: chooseApp)
                Spacer()
                Button("打開系統設定") { manager.openSystemSettings() }
            }
            if let message = manager.message {
                Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Text("「背景 App 活動」與系統層級的項目只能在系統設定開關，這裡僅列出。停用使用者代理程式會在下次登入生效，並立刻停止目前執行中的那一份。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ item: StartupItem) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: icon(for: item))
                .resizable().frame(width: 28, height: 28)
                .opacity(item.missing ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1)
                Text(item.kind.title + (item.enabled ? "" : "・已停用") + (item.missing ? "・程式已不存在" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { selectedID = item.id } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless).help("詳細資訊")
            if item.canToggle {
                Toggle("", isOn: Binding(get: { item.enabled }, set: { pendingToggle = (item, $0) }))
                    .labelsHidden().toggleStyle(.switch)
            }
            if item.canRemove {
                Button { pendingRemoval = item } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).help("移除")
            }
        }
    }

    @ViewBuilder private func detailsBody(_ item: StartupItem) -> some View {
        if let info = manager.details[item.id] {
            VStack(alignment: .leading, spacing: 4) {
                if !item.path.isEmpty { field("程式", item.path) }
                if let label = item.label { field("識別名稱", label) }
                if let signer = info.signer { field("簽署者", signer) }
                else if info.programExists { field("簽署者", "沒有簽章或讀不到") }
                if let vendor = info.vendorHint { field("可能的開發者", vendor) }
                if !info.relatedBundleIDs.isEmpty {
                    field("相關的 App", info.relatedBundleIDs.map { id in
                        (info.appNames[id] ?? id) + (info.installedRelatedIDs.contains(id) ? "（已安裝）" : "（找不到）")
                    }.joined(separator: "、"))
                }
                if !info.inferredAppIDs.isEmpty {
                    field("推測的 App", info.inferredAppIDs.map { id in
                        (info.appNames[id] ?? id) + (info.installedInferredIDs.contains(id) ? "（已安裝）" : "（找不到）")
                    }.joined(separator: "、"))
                    Text("從殘留的偏好設定等檔名推測，不一定正確。").foregroundStyle(.secondary)
                }
                if !info.programExists { Text("這個項目指向的程式已經不存在。").foregroundStyle(.orange) }
                else if info.ownerMissing { Text("相關的 App 都找不到，這個項目可能是移除 App 後留下的。").foregroundStyle(.orange) }
                if info.leftovers.isEmpty {
                    Text("沒有找到其他相關檔案。").foregroundStyle(.secondary)
                } else {
                    Text("可能相關的檔案（只供參考，請自行確認再處理）").foregroundStyle(.secondary)
                    ForEach(info.leftovers, id: \.self) { path in
                        HStack(spacing: 6) {
                            Text(path).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                            Spacer(minLength: 4)
                            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } label: { Image(systemName: "folder") }
                                .buttonStyle(.borderless).help("在 Finder 中顯示")
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(path, forType: .string)
                            } label: { Image(systemName: "doc.on.doc") }
                                .buttonStyle(.borderless).help("複製路徑")
                        }
                    }
                }
            }
            .padding(.top, 4)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func field(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(title).foregroundStyle(.secondary).lineLimit(1).fixedSize().frame(width: 100, alignment: .leading)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 程式不存在時 NSWorkspace 會回傳通用圖示
    private func icon(for item: StartupItem) -> NSImage {
        NSWorkspace.shared.icon(forFile: item.iconPath)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        manager.addLoginItem(path: url.path)
    }
}
