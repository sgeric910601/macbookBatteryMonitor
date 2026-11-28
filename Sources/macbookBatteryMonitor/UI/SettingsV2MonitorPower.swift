import AppKit
import SwiftUI

/// 新版設定 →「系統監控」：常用的開關＋選單列預覽；合併圖示、管理員取樣收進「進階」（網路測速在「網路與螢幕」）。
/// 警示的開關在這頁（門檻和模組放一起），「一般」的通知卡片有捷徑
struct SettingsV2MonitorPage: View {
    let settings: AppSettings
    let adminCPU: AdminCPUSampler
    let hasBattery: Bool
    let state: SettingsV2State

    private typealias SwitchRow = SettingsView.SwitchRow

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SwitchRow("在選單列顯示系統監控", isOn: binding(\.systemMonitors))
                HStack(spacing: 8) {
                    V2ToggleTile(title: "CPU／GPU", symbol: "cpu", isOn: binding(\.monitorCPU))
                    V2ToggleTile(title: "記憶體", symbol: "memorychip", isOn: binding(\.monitorMemory))
                    V2ToggleTile(title: "磁碟", symbol: "internaldrive", isOn: binding(\.monitorDisk))
                    V2ToggleTile(title: "網路", symbol: "network", isOn: binding(\.monitorNetwork))
                }
                .disabled(!settings.systemMonitors)
                V2Tiles(title: "標籤樣式", options: [(false, "彩色底塊"), (true, "不加底色（標籤在上）")],
                        selection: binding(\.monitorPlainLabels), minWidth: 150, graphicHeight: 26) { plain in
                    Image(nsImage: plain
                          ? MonitorMenuBarRenderer.columns([("CPU", "29%", nil), ("GPU", "79%", nil)], valueTemplate: "100%")
                          : MonitorMenuBarRenderer.twoLines([("CPU", "29%", MonitorMenuBarRenderer.green),
                                                             ("GPU", "79%", MonitorMenuBarRenderer.orange)], valueTemplate: MonitorMenuBarRenderer.plainTemplate))
                }
                .disabled(!settings.systemMonitors)
                preview
            }
        }
        Card {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle("警示", systemImage: "exclamationmark.triangle")
                SwitchRow("CPU 持續滿載（90% 以上 5 分鐘）", isOn: binding(\.alertCPU))
                    .disabled(!settings.isMonitorEnabled(.cpu))
                SwitchRow("記憶體壓力嚴重", isOn: binding(\.alertMemory))
                    .disabled(!settings.isMonitorEnabled(.memory))
                SwitchRow("開機磁碟剩不到 10 GB", isOn: binding(\.alertDisk))
                    .disabled(!settings.isMonitorEnabled(.disk))
                V2Note(settings.menuBarCombined
                       ? "每種只通知一次，回到正常後才會再通知。合併成一個圖示時，只在展開狀態列時判斷。"
                       : "每種只通知一次，回到正常後才會再通知。該模組在選單列有圖示時才會判斷，不另外取樣。")
            }
        }
        Card {
            V2Disclosure(title: "進階", id: "monitor.advanced", state: state) {
                VStack(alignment: .leading, spacing: 10) {
                    SwitchRow("記憶體與磁碟放在同一個圖示", isOn: binding(\.mergeMemoryDisk))
                        .disabled(!settings.systemMonitors || !settings.monitorMemory || !settings.monitorDisk || settings.monitorPlainLabels)
                    if settings.monitorPlainLabels {
                        V2Note("標籤不加底色時每個數值各自一個圖示，不合併。")
                    } else if !settings.monitorMemory || !settings.monitorDisk {
                        V2Note("記憶體和磁碟都開著時才能合併。")
                    }
                    SwitchRow("所有監控合併成一個圖示", isOn: binding(\.menuBarCombined))
                        .disabled(!settings.systemMonitors)
                    V2Note("選單列只留一個圖示，點一下在下方展開所有圖示；選單列太擠時用。")
                    // Intel 直接由 SMC 讀 CPU 功耗，不需要管理員取樣
                    if !ChipInfo.isIntel {
                        Divider()
                        SwitchRow("管理員 CPU 取樣（顯示各核心功耗）", isOn: binding(\.adminCPUSampling))
                        V2Note("需要輸入一次管理員密碼；只在面板開著時取樣，關閉後會移除服務。目前：\(adminCPU.status)")
                    }
                }
            }
        }
    }

    /// 選單列上的樣子：用和選單列相同的繪圖程式、固定的範例數字，不另外取樣
    @ViewBuilder private var preview: some View {
        // 實際選單列由左到右是 網路、磁碟、記憶體、GPU、CPU（後建立的圖示排在左邊），預覽照同樣的順序排
        let images = Array(previewImages.reversed())
        VStack(alignment: .leading, spacing: 6) {
            Text("選單列預覽").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if images.isEmpty {
                    Text(!settings.systemMonitors ? "只顯示\(hasBattery ? "電池" : "耗電")圖示，四個模組都不取樣，最省電"
                         : settings.menuBarCombined ? "已合併成一個圖示：點\(hasBattery ? "電池" : "耗電")圖示時在下方展開"
                         : "沒有開啟任何模組")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(images.indices, id: \.self) { Image(nsImage: images[$0]) }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("選單列預覽")
        }
    }

    private var previewImages: [NSImage] {
        guard settings.systemMonitors else { return [] }
        // 合併時選單列只有電池圖示，點了才在下方展開
        if settings.menuBarCombined { return [] }
        var images: [NSImage] = []
        if settings.monitorPlainLabels { return plainPreviewImages }
        if settings.monitorCPU {
            images.append(MonitorMenuBarRenderer.twoLines([("CPU", "29%", MonitorMenuBarRenderer.green),
                                                           ("GPU", "79%", MonitorMenuBarRenderer.orange)], valueTemplate: MonitorMenuBarRenderer.plainTemplate))
        }
        if settings.memoryDiskMerged {
            images.append(MonitorMenuBarRenderer.twoLines([("MEM", "62%", MonitorMenuBarRenderer.green),
                                                           ("DISK", "48%", MonitorMenuBarRenderer.orange)], valueTemplate: MonitorMenuBarRenderer.plainTemplate))
        } else {
            if settings.monitorMemory {
                images.append(MonitorMenuBarRenderer.symbolValue(symbol: "memorychip", value: "62%", valueTemplate: MonitorMenuBarRenderer.plainTemplate))
            }
            if settings.monitorDisk {
                images.append(MonitorMenuBarRenderer.symbolValue(symbol: "internaldrive", value: "48%", valueTemplate: MonitorMenuBarRenderer.plainTemplate))
            }
        }
        if settings.monitorNetwork {
            images.append(MonitorMenuBarRenderer.twoLines([("↑", "12K", MonitorMenuBarRenderer.orange),
                                                           ("↓", "1.2M", MonitorMenuBarRenderer.green)], valueTemplate: "999K"))
        }
        return images
    }

    /// 不加底色時的預覽（和 ModuleCoordinator 的畫法相同）
    private var plainPreviewImages: [NSImage] {
        typealias R = MonitorMenuBarRenderer
        var images: [NSImage] = []
        if settings.monitorCPU {
            images.append(R.columns([("CPU", "29%", nil)], valueTemplate: MonitorMenuBarRenderer.plainTemplate))
            images.append(R.columns([("GPU", "79%", nil)], valueTemplate: MonitorMenuBarRenderer.plainTemplate))
        }
        if settings.memoryDiskMerged {
            images.append(R.columns([("MEM", "62%", nil), ("DISK", "48%", nil)], valueTemplate: MonitorMenuBarRenderer.plainTemplate))
        } else {
            if settings.monitorMemory { images.append(R.columns([("MEM", "62%", nil)], valueTemplate: "100%")) }
            if settings.monitorDisk { images.append(R.columns([("DISK", "48%", nil)], valueTemplate: "100%")) }
        }
        if settings.monitorNetwork {
            images.append(R.twoLines([("", "12 KB/s", R.orange), ("", "1.2 MB/s", R.green)], valueTemplate: "999 KB/s", plain: true))
        }
        return images
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }
}

/// 新版設定 →「省電與睡眠」：App 多久更新一次、省電模式；睡眠時防止休眠的 App 與關閉藍牙獨立成「睡眠」卡片
struct SettingsV2PowerPage: View {
    let settings: AppSettings
    let hasBattery: Bool

    private typealias SwitchRow = SettingsView.SwitchRow

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardTitle("更新頻率與省電", systemImage: "leaf")
                HStack {
                    Text("數字多久更新一次")
                    Spacer(minLength: 12)
                    V2Segmented(title: "更新頻率",
                                options: AppSettings.updateIntervals.map { ($0, $0 <= 1 ? "每秒" : "\($0) 秒") },
                                selection: binding(\.updateInterval))
                        .frame(width: 240)
                }
                SwitchRow("省電模式", isOn: binding(\.powerSaving))
                // 桌上型 Mac 一直接著電源，沒有「只在使用電池時」的情況
                if hasBattery {
                    SwitchRow("只在使用電池時啟用", isOn: binding(\.powerSavingOnBatteryOnly))
                        .disabled(!settings.powerSaving)
                        .padding(.leading, 16)
                }
                V2Note(powerSavingNote)
            }
        }
        Card {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle("睡眠", systemImage: "moon.zzz")
                Text("這些 App 開著時防止休眠")
                AppExceptionList(ids: binding(\.keepAwakeApps), limit: SwitcherSettings.maxExcludedApps)
                V2Note("清單裡有任何一個 App 在執行，Mac 就不會自己睡著（螢幕照常會關），全部結束就恢復。用電池而且電量到 10% 以下時自動停止。")
                if BluetoothPower.isAvailable, hasBattery {
                    Divider()
                    SwitchRow("睡眠時關閉藍牙", isOn: binding(\.bluetoothOffDuringSleep))
                    V2Note("醒來後再打開；你自己關掉的藍牙醒來後維持關閉。連著藍牙鍵盤、滑鼠或觸控板時不關，免得叫不醒 Mac。睡眠期間藍牙耳機等裝置會斷線，醒來後要重新連上。")
                }
            }
        }
    }

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

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }
}
