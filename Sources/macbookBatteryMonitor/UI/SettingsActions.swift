import AppKit
import UniformTypeIdentifiers

/// 設定頁的動作（匯出／匯入設定、開機自動啟動）
@MainActor
enum SettingsActions {
    static func exportSettings(_ settings: AppSettings) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(AppEdition.appName)設定.plist"
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.exportBackup().write(to: url, options: .atomic)
        } catch {
            showAlert("無法匯出設定", "請換一個位置再試一次。")
        }
    }

    static func importSettings(_ settings: AppSettings) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // 只讀一般檔案，最多讀到上限多一個位元組：太大的檔案由 read 判斷，不會整個讀進記憶體
        let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        let handle = isFile ? try? FileHandle(forReadingFrom: url) : nil
        let data = (try? handle?.read(upToCount: SettingsBackup.maxSize + 1)) ?? nil
        try? handle?.close()
        let backup: (values: [String: Any], turnsOn: [String])
        do {
            backup = try settings.readBackup(data ?? Data())
        } catch SettingsBackup.ReadError.newerVersion {
            return showAlert("無法匯入設定", "這個檔案是較新版本匯出的，請先更新\(AppEdition.appName)。")
        } catch {
            return showAlert("無法匯入設定", "這不是\(AppEdition.appName)匯出的設定檔，或檔案已損壞。")
        }
        if !backup.turnsOn.isEmpty {
            // 會打開原本關著的功能（有的需要「輔助使用」、會記錄剪貼簿）：先列出來讓使用者確認
            let confirm = NSAlert()
            confirm.messageText = "匯入後會打開這些功能"
            confirm.informativeText = backup.turnsOn.map { "・\($0)" }.joined(separator: "\n")
            confirm.addButton(withTitle: "匯入")
            confirm.addButton(withTitle: "取消")
            guard confirm.runModal() == .alertFirstButtonReturn else { return }
        }
        let count = settings.importBackup(backup.values)
        let alert = NSAlert()
        alert.messageText = "已匯入 \(count) 項設定"
        alert.informativeText = "重新開啟\(AppEdition.appName)後全部生效。"
        alert.addButton(withTitle: "立即重新開啟")
        alert.addButton(withTitle: "稍後")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if (try? AppLocation.reopenAfterExit(Bundle.main.bundleURL)) != nil { NSApp.terminate(nil) }
    }

    private static func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    static func setLoginItem(_ enabled: Bool, ui: PanelState) {
        UserDefaults.standard.set(!enabled, forKey: LoginItem.disabledByUserKey)
        do {
            try LoginItem.setEnabled(enabled)
            ui.loginError = nil
        } catch {
            ui.loginError = "設定失敗：\(error.localizedDescription)"
        }
        ui.loginStatus = LoginItem.status
    }
}
