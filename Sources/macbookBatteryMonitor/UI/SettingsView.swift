import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let settings: AppSettings
    let ui: PanelState
    let adminCPU: AdminCPUSampler
    let updater: Updater
    let chargeLimit: SystemChargeLimit
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
                    if hasBattery {
                        Divider()
                        Text("充電圖示自訂").font(.callout.weight(.semibold))
                        HStack {
                            Text("充電預覽 · 68%").foregroundStyle(.secondary)
                            Spacer()
                            Image(nsImage: StatusIconRenderer.image(percent: 68, state: .charging, low: false,
                                showsPercent: true, chargingColor: settings.chargingIconColor,
                                chargingTextColor: settings.chargingIconTextColor))
                                .resizable().interpolation(.high).frame(width: 72, height: 30)
                        }
                        Picker("百分比文字", selection: binding(\.chargingIconText)) {
                            Text("白色").tag("white")
                            Text("黑色").tag("black")
                            Text("跟隨系統外觀").tag("automatic")
                        }
                        Picker("充電顏色預設", selection: binding(\.chargingIconPreset)) {
                            Text("Apple 原生綠").tag("native")
                            Text("薄荷綠").tag("mint")
                            Text("翡翠綠").tag("emerald")
                            Text("萊姆綠").tag("lime")
                            Text("自訂色盤").tag("custom")
                        }
                        if settings.chargingIconPreset == "custom" {
                            ColorPicker("自訂充電顏色", selection: Binding(
                                get: { Color(nsColor: settings.chargingIconBaseColor) },
                                set: { settings.chargingIconColorData = try? NSKeyedArchiver.archivedData(
                                    withRootObject: NSColor($0), requiringSecureCoding: true) }
                            ), supportsOpacity: false)
                        }
                        HStack {
                            Text("底色不透明度")
                            Slider(value: binding(\.chargingIconOpacity), in: 0...1, step: 0.01)
                                .accessibilityLabel("充電底色不透明度")
                            Text("\(Int((settings.chargingIconOpacity * 100).rounded()))%")
                                .monospacedDigit().frame(width: 42, alignment: .trailing)
                        }
                        Text("0% 完全透明，100% 不透明；不影響文字。")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("充電時顯示流光", isOn: binding(\.chargingIconFlow))
                        Text("依實際電量比例填充。省電模式與減少動態效果會停止流光。")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("還原圖示預設") {
                            settings.chargingIconText = "white"
                            settings.chargingIconNativeColor = true
                            settings.chargingIconPreset = "native"
                            settings.chargingIconOpacity = 1
                            settings.chargingIconColorData = nil
                            settings.chargingIconFlow = true
                        }
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

            if settings.isInstalled(.xdrBrightness), section == .xdrBrightness {
                XDRBrightnessCard(settings: settings)
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
                    Divider().padding(.vertical, 2)
                    Text("這些 App 執行中時防止休眠").font(.body)
                    AppExceptionList(ids: binding(\.keepAwakeApps), limit: SwitcherSettings.maxExcludedApps)
                    Text("清單裡有任何一個 App 在執行，Mac 就不會自己睡著（螢幕照常會關），全部結束就恢復，例如簡報、播放或下載時。用電池而且電量到 10% 以下時自動停止。只監聽 App 開啟與結束，不會一直檢查。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if BluetoothPower.isAvailable, hasBattery {
                        Divider().padding(.vertical, 2)
                        SwitchRow("睡眠時關閉藍牙", isOn: binding(\.bluetoothOffDuringSleep))
                        Text("Mac 睡眠時關掉藍牙，醒來後再打開；你自己關掉的藍牙醒來後維持關閉。連著藍牙鍵盤、滑鼠或觸控板時不關，免得用它們叫不醒 Mac。睡眠期間所有藍牙連線都會中斷，醒來後藍牙耳機等裝置要重新連上。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .settingsSection(.monitors, shown: section)

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("系統監控", systemImage: "gauge.with.dots.needle.33percent")
                    SwitchRow("在選單列顯示系統監控", isOn: binding(\.systemMonitors))
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            SwitchRow("CPU／GPU", isOn: binding(\.monitorCPU))
                            SwitchRow("記憶體", isOn: binding(\.monitorMemory))
                        }
                        GridRow {
                            SwitchRow("磁碟", isOn: binding(\.monitorDisk))
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
                    SwitchRow("在網路面板顯示測速", isOn: Binding(get: { settings.isInstalled(.speedTest) }, set: { settings.setInstalled(.speedTest, $0) }))
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

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("監控警示", systemImage: "exclamationmark.triangle")
                    SwitchRow("CPU 持續滿載（90% 以上 5 分鐘）", isOn: binding(\.alertCPU))
                        .disabled(!settings.isMonitorEnabled(.cpu))
                    SwitchRow("記憶體壓力嚴重", isOn: binding(\.alertMemory))
                        .disabled(!settings.isMonitorEnabled(.memory))
                    SwitchRow("開機磁碟剩不到 10 GB", isOn: binding(\.alertDisk))
                        .disabled(!settings.isMonitorEnabled(.disk))
                    Text(settings.menuBarCombined
                         ? "每種只通知一次，回到正常後才會再通知。合併成一個圖示時，只在展開狀態列時判斷。"
                         : "每種只通知一次，回到正常後才會再通知。該模組在選單列有圖示時才會判斷，不另外取樣。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                    CardTitle("設定備份", systemImage: "square.and.arrow.up.on.square")
                    HStack {
                        Button("匯出設定…") { exportSettings() }
                        Button("匯入設定…") { importSettings() }
                    }
                    Text("換 Mac 或重灌時，把設定存成一個檔案帶過去。不含管理員 CPU 取樣、精準喚醒（要在新的 Mac 重新開啟）、自己的照片與周邊設備的低電量門檻。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .settingsSection(.general, shown: section)

            if settings.isInstalled(.scrollDirection) {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        CardTitle("捲動方向", systemImage: "arrow.up.arrow.down")
                        SwitchRow("滑鼠滾輪反向", isOn: binding(\.scrollReverseMouse))
                        SwitchRow("觸控板反向", isOn: binding(\.scrollReverseTrackpad))
                        Toggle("左右捲動也反向", isOn: binding(\.scrollReverseHorizontal))
                            .disabled(!settings.scrollReverseMouse && !settings.scrollReverseTrackpad)
                        Picker("滑鼠滾輪每格", selection: binding(\.scrollLinearLines)) {
                            ForEach(ScrollLinear.choices, id: \.self) { Text($0 == 0 ? "照系統加速" : "固定 \($0) 行").tag($0) }
                        }
                        .fixedSize()
                        Toggle("滑鼠滾輪平滑捲動", isOn: binding(\.scrollSmooth))
                        Picker("滾輪改成左右捲動", selection: binding(\.scrollHorizontalKey)) {
                            ForEach(ScrollHorizontalKey.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .fixedSize()
                        Text("macOS 的「自然捲動」是滑鼠和觸控板一起變；這裡可以只反轉其中一種，例如觸控板維持自然捲動、滑鼠滾輪改回傳統方向。兩指在觸控板上捲動算觸控板，其他（包括 Magic Mouse）算滑鼠。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if settings.scrollReverseMouse || settings.scrollReverseTrackpad || settings.scrollLinearLines > 0 || settings.scrollHorizontalKey != .off || settings.scrollSmooth {
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
            }

            if settings.isInstalled(.inputMethod) {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        CardTitle("中文輸入法", systemImage: "keyboard")
                        SwitchRow("Caps Lock 切換中英不延遲", isOn: binding(\.capsLockNoDelay))
                        SwitchRow("按住 Shift 打半形英文與符號", isOn: binding(\.shiftHalfWidth))
                        Text("macOS 為了防誤觸，Caps Lock 要按住一下才切換；打開後按一下就切（只對外接鍵盤有效：macOS 27.2 實測，使用系統的「大寫鎖定鍵切換輸入法」時，內建鍵盤由 macOS 自己判斷）。注音等中文輸入法按住 Shift 打字會變全形「Ａ」「！」「，」；打開後按住 Shift 時和英文鍵盤一樣全部打出半形，放開 Shift 就繼續打中文（Shift + 逗號、句號會是 < >，中文標點請改用其他方式打）。關掉「不延遲」時恢復系統預設的延遲。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if settings.shiftHalfWidth {
                            if ui.shiftRunning {
                                Label("運作中", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else if !ui.scrollTrusted {
                                Text("「按住 Shift 打半形英文」需要允許「輔助使用」：系統設定 → 隱私權與安全性 → 輔助使用，打開「\(AppEdition.appName)」。")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("打開輔助使用設定") { ScrollDirection.openAccessibilitySettings() }
                            }
                        }
                    }
                }
                .settingsSection(.input, shown: section)
            }

            if settings.isInstalled(.mouseButtons) {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        CardTitle("滑鼠側鍵", systemImage: "computermouse")
                        Picker("第 4 鍵（後退）", selection: binding(\.mouseBackButton)) {
                            ForEach(MouseButtons.Action.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .fixedSize()
                        Picker("第 5 鍵（前進）", selection: binding(\.mouseForwardButton)) {
                            ForEach(MouseButtons.Action.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .fixedSize()
                        Text("多按鍵滑鼠拇指那兩顆。「上一頁、下一頁」送出 ⌘[、⌘]，Safari、Finder 等大部分 App 都能用；設成「不處理」的按鍵照常交給 App。左鍵、右鍵、中鍵不會被碰到。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if settings.mouseBackButton != .none || settings.mouseForwardButton != .none {
                            if ui.mouseButtonsRunning {
                                Label("運作中", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else if !ui.scrollTrusted {
                                Text("需要允許「輔助使用」：系統設定 → 隱私權與安全性 → 輔助使用，打開「\(AppEdition.appName)」。")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("打開輔助使用設定") { ScrollDirection.openAccessibilitySettings() }
                            }
                        }
                    }
                }
                .settingsSection(.input, shown: section)
            }

            if settings.isInstalled(.keyboardCleaning) {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        CardTitle("鍵盤清潔模式", systemImage: "sparkles")
                        HStack {
                            Picker("停手多久後恢復", selection: binding(\.keyboardCleaningSeconds)) {
                                ForEach(KeyboardCleaning.durations, id: \.self) { Text("\($0) 秒").tag($0) }
                            }
                            .fixedSize()
                            Button("開始清潔") {
                                if !KeyboardCleaningController.shared.start(seconds: settings.keyboardCleaningSeconds) {
                                    ScrollDirection.requestTrust()
                                }
                            }
                        }
                        Text("暫時停用整個鍵盤，包括功能列的亮度、音量鍵；滑鼠與觸控板照常；擦的時候按到鍵會重新倒數，停手滿設定的秒數或點畫面中央的「結束清潔」就恢復。Touch ID 指紋照常可以用，但它也是電源鍵，按下去 Mac 一樣會鎖定或睡眠，長按會強制關機，擦的時候輕一點。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !ui.scrollTrusted {
                            Text("需要允許「輔助使用」：系統設定 → 隱私權與安全性 → 輔助使用，打開「\(AppEdition.appName)」。")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("打開輔助使用設定") { ScrollDirection.openAccessibilitySettings() }
                        }
                    }
                }
                .settingsSection(.input, shown: section)
            }

            if settings.isInstalled(.quitGuard) {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        CardTitle("⌘Q／⌘W 防誤觸", systemImage: "hand.raised")
                        SwitchRow("按住 ⌘Q 才結束 App", isOn: binding(\.quitGuardQuit))
                        SwitchRow("按住 ⌘W 才關閉", isOn: binding(\.quitGuardClose))
                        Picker("要按住", selection: binding(\.quitGuardDuration)) {
                            ForEach(AppSettings.quitGuardDurations, id: \.self) { Text("\($0.formatted()) 秒").tag($0) }
                        }
                        Text("按下時記住最前面的 App，按滿時間才把 ⌘Q／⌘W 送給它；中途放開、換到別的 App 或按了別的鍵都會取消，不會關到後面的視窗。⌘W 送出前也會確認焦點視窗沒換。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if settings.quitGuardQuit || settings.quitGuardClose {
                            if ui.quitGuardRunning {
                                Label("運作中", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else if !ui.scrollTrusted {
                                Text("需要允許「輔助使用」：系統設定 → 隱私權與安全性 → 輔助使用，打開「\(AppEdition.appName)」。")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("打開輔助使用設定") { ScrollDirection.openAccessibilitySettings() }
                            }
                        }
                    }
                }
                .settingsSection(.input, shown: section)
            }

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

    struct SwitchRow: View {
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

    private func exportSettings() {
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

    private func importSettings() {
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

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
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
