import AppKit
import SwiftUI

/// 新版設定 →「一般」：通知集中一張卡（監控警示、周邊設備的門檻留在各自的頁面，這裡放捷徑）、
/// 啟動、更新（原本的「更新」頁）、App 圖示（大預覽）、設定備份
struct SettingsV2GeneralPage: View {
    let settings: AppSettings
    let ui: PanelState
    let updater: Updater
    let hasBattery: Bool
    let state: SettingsV2State

    private typealias SwitchRow = SettingsView.SwitchRow

    var body: some View {
        notifications
        startup
        UpdateCard(updater: updater, settings: settings, notificationsBlocked: ui.notificationsBlocked, ui: ui)
        appIcon
        backup
    }

    private var notifications: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle("通知", systemImage: "bell")
                if hasBattery {
                    thresholdRow("低電量提醒", isOn: binding(\.lowAlertEnabled), value: binding(\.lowThreshold),
                                 range: 5...50, text: { "低於 \($0)%" })
                    thresholdRow("充電完成提醒", isOn: binding(\.fullAlertEnabled), value: binding(\.fullThreshold),
                                 range: 50...100, text: { "充到 \($0)%" })
                }
                shortcut("系統監控警示", detail: monitorAlertsText, to: .monitor)
                shortcut("周邊設備低電量", detail: "每個裝置分別設定", to: .peripherals)
                Divider()
                if ui.notificationsBlocked {
                    Text("macOS 已關閉這個 App 的通知。請到系統設定 → 通知 →「\(AppEdition.appName)」打開「允許通知」。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("打開系統設定的通知") { NSWorkspace.shared.open(Notifier.settingsURL) }
                } else {
                    Button("傳送測試通知") { Notifier.shared.sendTest() }
                }
            }
        }
    }

    private var monitorAlertsText: String {
        let on = [settings.alertCPU, settings.alertMemory, settings.alertDisk].filter { $0 }.count
        return on == 0 ? "全部關閉" : "開啟 \(on) 項"
    }

    /// 開關＋門檻：關掉時門檻變灰
    private func thresholdRow(_ title: String, isOn: Binding<Bool>, value: Binding<Int>,
                              range: ClosedRange<Int>, text: @escaping (Int) -> String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            V2Stepper(title: "\(title)的門檻", text: text(value.wrappedValue), value: value, range: range, step: 5)
                .disabled(!isOn.wrappedValue)
                .opacity(isOn.wrappedValue ? 1 : 0.5)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(SettingsSwitchStyle())
        }
    }

    /// 設定在別頁的通知：顯示目前狀態，點了跳過去
    private func shortcut(_ title: String, detail: String, to page: SettingsV2Page) -> some View {
        Button { state.page = page } label: {
            HStack {
                Text(title)
                Spacer()
                Text(detail).foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)：\(detail)，前往「\(page.title)」")
    }

    private var startup: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle("啟動", systemImage: "power")
                SwitchRow("開機時自動啟動", isOn: Binding(get: { ui.loginStatus != .disabled },
                                                   set: { SettingsActions.setLoginItem($0, ui: ui) }))
                if ui.loginStatus == .requiresApproval {
                    HStack {
                        Text("需要在系統設定的「登入項目」中允許。").font(.caption).foregroundStyle(.secondary)
                        Button("打開「登入項目」設定") { LoginItem.openSystemSettings() }.controlSize(.small)
                    }
                }
                if !LoginItem.isInApplications {
                    Text("建議先把 App 放到「應用程式」資料夾，再開啟這個選項。").font(.caption).foregroundStyle(.orange)
                }
                if let loginError = ui.loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private var appIcon: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle("App 圖示", systemImage: "app.badge")
                HStack(spacing: 16) {
                    AppIconPreview(color: settings.appIconColor, size: 72)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            ForEach(AppIconColor.allCases) { color in
                                swatch(color)
                            }
                        }
                        Text(settings.appIconColor.title).font(.callout)
                    }
                }
                Text(settings.appIconError ?? "應用程式資料夾、Finder、Launchpad 裡的圖示；通知與登入項目仍顯示內建的薄荷綠。")
                    .font(.caption)
                    .foregroundStyle(settings.appIconError == nil ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func swatch(_ color: AppIconColor) -> some View {
        let selected = settings.appIconColor == color
        return Button { settings.appIconColor = color } label: {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.swatch.last ?? .gray)
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: selected ? 2.5 : 1))
        }
        .buttonStyle(.plain)
        .help(color.title)
        .accessibilityLabel("App 圖示：\(color.title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var backup: some View {
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    CardTitle("設定備份", systemImage: "square.and.arrow.up.on.square")
                    Text("換 Mac 或重灌時，把設定存成一個檔案帶過去。不含管理員 CPU 取樣、精準喚醒（要在新的 Mac 重新開啟）、自己的照片與周邊設備的低電量門檻。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 6) {
                    Button("匯出…") { SettingsActions.exportSettings(settings) }
                    Button("匯入…") { SettingsActions.importSettings(settings) }
                }
            }
        }
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }
}

/// App 圖示的實際樣子：薄荷綠是內建的 AppIcon.icns，其他顏色是打包進去的 icon-<顏色>.png；
/// 開發用的執行檔沒有這些檔案時改畫色塊
private struct AppIconPreview: View {
    let color: AppIconColor
    let size: CGFloat

    private var image: NSImage? {
        let url = color == .mint
            ? Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            : Bundle.main.url(forResource: "icon-\(color.rawValue)", withExtension: "png")
        return url.flatMap(NSImage.init(contentsOf:))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(color.swatch.last ?? .gray)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("App 圖示預覽：\(color.title)")
    }
}
