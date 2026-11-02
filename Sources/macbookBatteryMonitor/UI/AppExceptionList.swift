import AppKit
import SwiftUI

/// 例外 App 清單：列出、移除、從執行中的 App 或磁碟加入。識別碼都經過 SwitcherSettings.isValidBundleID，最多 limit 個
struct AppExceptionList: View {
    @Binding var ids: Set<String>
    let limit: Int

    var body: some View {
        let sorted = ids.sorted()
        if sorted.isEmpty {
            Text("目前沒有").font(.caption).foregroundStyle(.secondary)
        }
        ForEach(sorted, id: \.self) { id in
            HStack {
                Text(Self.appName(for: id))
                Text(id).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("移除") { ids.remove(id) }
                    .controlSize(.small)
            }
        }
        HStack {
            Menu("加入執行中的 App") {
                ForEach(runningCandidates(), id: \.id) { candidate in
                    Button(candidate.name) { add(candidate.id) }
                }
            }
            Button("從磁碟選擇…") { chooseFromDisk() }
        }
        .disabled(ids.count >= limit)
    }

    private func runningCandidates() -> [(id: String, name: String)] {
        let me = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .compactMap { app -> (id: String, name: String)? in
                guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != me, !ids.contains(id),
                      SwitcherSettings.isValidBundleID(id) else { return nil }
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func chooseFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        add(id)
    }

    private func add(_ id: String) {
        guard SwitcherSettings.isValidBundleID(id), ids.count < limit else { return }
        ids.insert(id)
    }

    static func appName(for id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
