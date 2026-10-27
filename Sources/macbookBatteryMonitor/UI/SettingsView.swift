import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: PanelState
    @ObservedObject var adminCPU: AdminCPUSampler
    @ObservedObject var updater: Updater
    @ObservedObject var chargeLimit: SystemChargeLimit
    /// 桌上型 Mac 沒有電池：不顯示電池通知與充電上限
    var hasBattery = true
    /// 設定視窗目前的分類：只顯示屬於它的卡片
    var section: SettingsSection = .general
    /// 智慧充電進行中：充電上限滑桿的提示不同
    var planActive = false

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
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("選單列", systemImage: "menubar.rectangle")
                    Picker("顯示方式", selection: binding(\.display)) {
                        ForEach(MenuBarDisplay.allCases) { Text($0.title).tag($0) }
                    }
                    if !hasBattery {
                        Text("沒有電池的 Mac 改顯示系統耗電瓦數。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .settingsSection(.display, shown: section)

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
            .settingsSection(.general, shown: section)

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
            .settingsSection(.monitors, shown: section)

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
                    SwitchRow("記憶體與磁碟放在同一個圖示", isOn: binding(\.mergeMemoryDisk))
                        .disabled(!settings.systemMonitors || !settings.monitorMemory || !settings.monitorDisk)
                    if settings.systemMonitors {
                        Text(settings.monitorMemory && settings.monitorDisk
                             ? "像 CPU／GPU 一樣上下兩行，上面記憶體、下面磁碟；點開的面板也合在一起。"
                             : "記憶體和磁碟都開著時才能使用。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    SwitchRow("在網路面板顯示測速", isOn: binding(\.networkSpeedTest))
                        .disabled(!settings.systemMonitors || !settings.monitorNetwork)
                    if settings.systemMonitors {
                        Text(settings.monitorNetwork
                             ? "打開後網路面板最下面才有「開始測速」。測一次約 20～30 秒、會用掉數百 MB 流量，預設關閉以免誤按。"
                             : "網路模組開著時才能使用。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    SwitchRow("合併成一個圖示", isOn: binding(\.menuBarCombined))
                        .disabled(!settings.systemMonitors)
                    Text(!settings.systemMonitors
                         ? "關閉時選單列只有\(hasBattery ? "電池" : "耗電")圖示，四個模組都不會取樣，最省電。"
                         : settings.menuBarCombined
                         ? "選單列只留一個圖示，點一下在下方展開所有圖示；選單列太擠時用。"
                         : "開啟的模組在選單列各有一個圖示\(settings.memoryDiskMerged ? "（記憶體與磁碟共用一個）" : "")，\(settings.updateText)。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .settingsSection(.monitors, shown: section)

            // Intel 直接由 SMC 讀 CPU 功耗，不需要管理員取樣
            if !ChipInfo.isIntel {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        CardTitle("CPU 功耗", systemImage: "cpu")
                        SwitchRow("管理員 CPU 取樣", isOn: binding(\.adminCPUSampling))
                        Text("需要輸入一次管理員密碼；只在面板開著時取樣，關閉後會移除服務。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(adminCPU.status).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .settingsSection(.monitors, shown: section)
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
                        Text("macOS 已關閉這個 App 的通知。請到系統設定 → 通知 →「\(AppEdition.appName)」打開「允許通知」。")
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
            .settingsSection(.general, shown: section)

            // 桌上型 Mac 沒有電池，也沒有充電上限
            if hasBattery {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        if chargeLimit.supported {
                            // 和主面板的滑桿是同一個設定（滑桿自己有「充電上限」標題）
                            ChargeLimitSlider(control: chargeLimit, planActive: planActive)
                            Text("和主面板的滑桿、系統設定「電池」裡的充電上限同步。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            CardTitle("充電上限", systemImage: "checkmark.shield")
                            HStack {
                                Text("系統充電上限")
                                Spacer()
                                Text(limitText)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Text(ChargeLimitReader.lastKnown()?.active == false
                                 ? "這台 Mac 無法從 App 調整；用電池時顯示的是上次接電時的數值。"
                                 : "這台 Mac 無法從 App 調整，只顯示目前的設定。")
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
                .settingsSection(.charging, shown: section)

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        CardTitle("充電夥伴", systemImage: "pawprint")
                        Picker("外觀", selection: Binding(get: { settings.chargingAppearance },
                                                        set: { settings.selectAppearance($0) })) {
                            ForEach(ChargingAppearance.allCases) { Text($0.title).tag($0) }
                        }
                        photoRow
                        SwitchRow("在桌面顯示", isOn: binding(\.desktopPet))
                        if settings.desktopPet {
                            Picker("位置", selection: binding(\.desktopPetOnWallpaper)) {
                                Text("浮在視窗上方").tag(false)
                                Text("放在桌布上").tag(true)
                            }
                            if settings.chargingAppearance == .photo {
                                SwitchRow("眼睛跟著游標", isOn: binding(\.desktopPetFollowCursor))
                                    .help("貓咪大頭照：眼珠看著滑鼠游標；關掉就完全不監聽滑鼠移動")
                                SwitchRow("會眨眼、睡覺", isOn: binding(\.desktopPetLiveEyes))
                                    .help("貓咪大頭照：偶爾眨眼，等智慧充電時閉眼睡覺（滑鼠移過去會醒來）")
                            }
                            HStack(spacing: 8) {
                                Text("大小")
                                // 不用 step：每 5% 一格會畫出一整排刻度；放開時取到 5% 的倍數
                                Slider(value: Binding(get: { settings.desktopPetScale },
                                                      set: { settings.desktopPetScale = AppSettings.clampPetScale(($0 * 20).rounded() / 20) }),
                                       in: AppSettings.desktopPetScaleRange)
                                    .controlSize(.small)
                                Text("\(Int((settings.desktopPetScale * 100).rounded()))%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                        Text("滑鼠移過去看狀態、點一下聊天、來回移動是摸牠；可以拖曳，右鍵可以換大小或隱藏。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .settingsSection(.companion, shown: section)
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
            .settingsSection(.general, shown: section)

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("捲動方向", systemImage: "arrow.up.arrow.down")
                    SwitchRow("滑鼠滾輪反向", isOn: binding(\.scrollReverseMouse))
                    SwitchRow("觸控板反向", isOn: binding(\.scrollReverseTrackpad))
                    Text("macOS 的「自然捲動」是滑鼠和觸控板一起變；這裡可以只反轉其中一種，例如觸控板維持自然捲動、滑鼠滾輪改回傳統方向。兩指在觸控板上捲動算觸控板，其他（包括 Magic Mouse）算滑鼠。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if settings.scrollReverseMouse || settings.scrollReverseTrackpad {
                        if ui.scrollRunning {
                            Label("運作中", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if ui.scrollTrusted {
                            // 有權限、還沒開始：每 5 秒會再試一次
                            Label("啟動中…", systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("需要允許「輔助使用」：系統設定 → 隱私權與安全性 → 輔助使用，打開「\(AppEdition.appName)」。清單裡已經有它、開關也開著的話，那是 v1.7.3 以前版本的允許，先按「－」移除再加一次；之後更新都會保留。")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("打開輔助使用設定") { ScrollDirection.openAccessibilitySettings() }
                        }
                    }
                }
            }
            .settingsSection(.input, shown: section)

            UpdateCard(updater: updater, settings: settings, notificationsBlocked: ui.notificationsBlocked, ui: ui)
                .settingsSection(.update, shown: section)
        }
        .onAppear {
            Notifier.shared.checkBlocked { ui.notificationsBlocked = $0 }
            ui.loginStatus = LoginItem.status
        }
    }

    /// 「我的照片」外觀用的照片：預覽與選擇（選好就改用我的照片）。貓咪大頭照是另一個外觀，換照片不影響它
    private var photoRow: some View {
        // 換照片時重畫
        let _ = settings.companionPhotoVersion
        return HStack(spacing: 10) {
            Text("我的照片")
            Spacer()
            if CompanionPhoto.hasCustom {
                CompanionPhotoFigure(presentation: .init(title: "", detail: "", progress: 1, tint: .green, onPad: false, badge: nil,
                                                         animatedFlow: false), width: 36, custom: true)
            }
            Button(CompanionPhoto.hasCustom ? "換照片…" : "選擇照片…") { settings.chooseCompanionPhoto() }
                .help("選一張自己的照片，會改用「我的照片」外觀；貓咪大頭照會保留")
            if CompanionPhoto.hasCustom {
                Button("移除") { settings.removeCompanionPhoto() }
                    .help("刪掉這張照片（只存在這台 Mac）")
            }
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
