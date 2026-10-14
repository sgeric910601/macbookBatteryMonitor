import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: PanelState
    @ObservedObject var adminCPU: AdminCPUSampler
    @ObservedObject var updater: Updater
    @ObservedObject var chargeLimit: SystemChargeLimit
    /// 桌上型 Mac 沒有電池：不顯示電池通知與充電上限
    var hasBattery = true

    private var powerSavingNote: String {
        let base = "省電模式：電力流向改用靜態圖示、不播放動畫，更新頻率至少每 2 秒。"
        if settings.powerSaving, settings.powerSavingOnBatteryOnly, settings.onACPower, hasBattery {
            return base + "目前接著電源，已暫時恢復一般模式。"
        }
        if settings.powerSavingActive, settings.updateInterval < 2 {
            return base + "（目前\(settings.updateText)）"
        }
        return base + "更新越慢越省電。"
    }

    private var limitText: String {
        if chargeLimit.supported { return chargeLimit.limit >= 100 ? "不限制（100%）" : "\(chargeLimit.limit)%" }
        return ChargeLimitReader.lastKnown().map { "\($0.limit)%" } ?? "未設定"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Text("設定").font(.headline)
                HStack {
                    Button {
                        ui.page = .main
                    } label: {
                        Label("返回", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("選單列", systemImage: "menubar.rectangle")
                    Picker("顯示方式", selection: binding(\.display)) {
                        ForEach(MenuBarDisplay.allCases) { Text($0.title).tag($0) }
                    }
                    if !hasBattery {
                        Text("這台 Mac 沒有電池：選單列顯示系統耗電（瓦數），有百分比或時間的選項都會改顯示瓦數，「只有圖示」則不顯示數字。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("選擇面板顯示的項目…") { ui.page = .displayItems }
                        .help("電力流向細項（螢幕背光、晶片、CPU／GPU／ANE）與詳細資訊欄位")
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("App 圖示", systemImage: "app.badge")
                    HStack(spacing: 14) {
                        ForEach(AppIconColor.allCases) { color in
                            Button {
                                settings.appIconColor = color
                            } label: {
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(LinearGradient(colors: color.swatch, startPoint: .top, endPoint: .bottom))
                                        .frame(width: 40, height: 40)
                                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(settings.appIconColor == color ? Color.accentColor : Color.primary.opacity(0.15),
                                                          lineWidth: settings.appIconColor == color ? 2.5 : 1))
                                    Text(color.title)
                                        .font(.caption)
                                        .foregroundStyle(settings.appIconColor == color ? .primary : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("App 圖示：\(color.title)")
                        }
                    }
                    Text(settings.appIconError ?? "應用程式資料夾、Finder、Launchpad 裡的圖示；通知與登入項目仍顯示內建的薄荷綠。")
                        .font(.caption)
                        .foregroundStyle(settings.appIconError == nil ? Color.secondary : Color.orange)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("更新頻率與省電", systemImage: "leaf")
                    Picker("更新頻率", selection: binding(\.updateInterval)) {
                        ForEach(AppSettings.updateIntervals, id: \.self) { Text(AppSettings.updateText(seconds: $0)).tag($0) }
                    }
                    SwitchRow("省電模式", isOn: binding(\.powerSaving))
                    // 桌上型 Mac 一直接著電源，沒有「只在使用電池時」的情況
                    if hasBattery {
                        Toggle("只在使用電池時啟用", isOn: binding(\.powerSavingOnBatteryOnly))
                            .disabled(!settings.powerSaving)
                    }
                    Text(powerSavingNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("系統監控", systemImage: SymbolCompat.name("gauge.with.dots.needle.33percent"))
                    SwitchRow("在選單列顯示系統監控", isOn: binding(\.systemMonitors))
                    VStack(alignment: .leading, spacing: 6) {
                        TwoColumns {
                            SwitchRow("CPU／GPU", isOn: binding(\.monitorCPU))
                        } right: {
                            SwitchRow("記憶體", isOn: binding(\.monitorMemory))
                        }
                        TwoColumns {
                            SwitchRow("磁碟", isOn: binding(\.monitorDisk))
                        } right: {
                            SwitchRow("網路", isOn: binding(\.monitorNetwork))
                        }
                    }
                    .disabled(!settings.systemMonitors)
                    Text(settings.systemMonitors
                         ? "開啟的模組在選單列各有一個圖示，\(settings.updateText)。"
                         : "關閉時選單列只有\(hasBattery ? "電池" : "耗電")圖示，四個模組都不會取樣，最省電。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Intel 直接由 SMC 讀 CPU 功耗，不需要管理員取樣
            if !ChipInfo.isIntel {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        CardTitle("CPU 功耗", systemImage: "cpu")
                        SwitchRow("管理員 CPU 取樣", isOn: binding(\.adminCPUSampling))
                        Text("選用功能，預設關閉。開啟時需輸入管理員密碼，安裝只讀取 CPU 功耗的系統服務；只在主面板開啟時取樣（\(settings.updateText)），面板關閉後不通訊，服務閒置會自行結束。關閉此選項會移除服務。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(adminCPU.status).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("通知", systemImage: "bell")
                    if hasBattery {
                        SwitchRow("低電量提醒", isOn: binding(\.lowAlertEnabled))
                        Stepper("電量低於 \(settings.lowThreshold)% 時提醒", value: binding(\.lowThreshold), in: 5...50, step: 5)
                            .disabled(!settings.lowAlertEnabled)
                        Divider()
                        SwitchRow("充電完成提醒", isOn: binding(\.fullAlertEnabled))
                        Stepper("充到 \(settings.fullThreshold)% 時提醒", value: binding(\.fullThreshold), in: 50...100, step: 5)
                            .disabled(!settings.fullAlertEnabled)
                    } else {
                        Text("這台 Mac 沒有電池，只會有周邊設備低電量與新版本通知。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if ui.notificationsBlocked {
                        Text("macOS 已關閉這個 App 的通知，低電量、充電完成、周邊設備與新版本通知都不會出現。請到系統設定 → 通知找到「\(AppEdition.appName)」，打開「允許通知」。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("打開系統設定的通知") {
                            NSWorkspace.shared.open(Notifier.settingsURL)
                        }
                    } else {
                        Button("傳送測試通知") {
                            Notifier.shared.sendTest()
                        }
                    }
                }
            }

            // 桌上型 Mac 沒有電池，也沒有充電上限
            if hasBattery {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        CardTitle("充電上限", systemImage: "checkmark.shield")
                        HStack {
                            Text("系統充電上限")
                            Spacer()
                            Text(limitText)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        if chargeLimit.supported {
                            Text("可在主面板電量下方的滑桿調整（80–100%），與系統設定「電池」裡的充電上限是同一個設定，改哪一邊都會同步。實際停在上限由 macOS 控制；只有設定了智慧充電時，App 才會依排程調整這個上限。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Divider()
                            Picker("滑桿旁顯示", selection: binding(\.chargingAppearance)) {
                                ForEach(ChargingAppearance.allCases) { Text($0.title).tag($0) }
                            }
                            Text("主面板充電上限滑桿的左邊顯示充電夥伴（會動的貓咪，充電時躺在充電墊上）、電池夥伴（有表情的電池，會跟著充電狀態換表情）或電量條，點一下打開智慧充電；面板關閉或省電模式時不播放動畫。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("設定智慧充電…") { ui.page = .chargingPlan }
                        } else {
                            if ChargeLimitReader.lastKnown()?.active == false {
                                Text("用電池時 macOS 不會套用上限，數值是上次接電時讀到的。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("這台 Mac 或系統版本無法從 App 調整充電上限，這裡只讀取並顯示。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Divider()
                            Picker("面板上方顯示", selection: binding(\.chargingAppearance)) {
                                ForEach(ChargingAppearance.allCases) { Text($0.title).tag($0) }
                            }
                            Text("主面板資訊卡最上方顯示充電夥伴（會動的貓咪，充電時躺在充電墊上）、電池夥伴或電量條；面板關閉或省電模式時不播放動畫。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button("在系統設定中修改") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("啟動", systemImage: "power")
                    SwitchRow("開機時自動啟動", isOn: Binding(
                        get: { ui.loginStatus != .disabled },
                        set: { setLoginItem($0) }
                    ))
                    if ui.loginStatus == .requiresApproval {
                        Text("需要在系統設定的「登入項目」中允許。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("打開「登入項目」設定") {
                            LoginItem.openSystemSettings()
                        }
                    }
                    if !LoginItem.isInApplications {
                        Text("建議先把 App 放到「應用程式」資料夾，再開啟這個選項。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let loginError = ui.loginError {
                        Text(loginError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            UpdateCard(updater: updater, settings: settings, notificationsBlocked: ui.notificationsBlocked, ui: ui)

            HStack {
                Text("\(AppEdition.appName) \(updater.currentVersion)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("結束\(AppEdition.appName)") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .onAppear {
            Notifier.shared.checkBlocked { ui.notificationsBlocked = $0 }
            ui.loginStatus = LoginItem.status
        }
    }

    private struct SwitchRow: View {
        let title: String
        let isOn: Binding<Bool>

        init(_ title: String, isOn: Binding<Bool>) {
            self.title = title
            self.isOn = isOn
        }

        var body: some View {
            HStack {
                Text(title)
                Spacer()
                Toggle(title, isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }

    private func setLoginItem(_ enabled: Bool) {
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
