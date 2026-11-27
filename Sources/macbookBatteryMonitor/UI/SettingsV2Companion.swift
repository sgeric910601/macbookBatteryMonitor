import SwiftUI

/// 新版設定 →「充電夥伴」：外觀直接畫出每種充電夥伴、桌面寵物的位置用小圖表示
struct SettingsV2CompanionPage: View {
    let settings: AppSettings

    private typealias SwitchRow = SettingsView.SwitchRow
    /// 預覽用的範例：充電中 62%
    private let sample = ChargingJourneyPresentation.make(percent: 62, charging: true, decision: nil, now: Date())

    var body: some View {
        // 換照片時重畫
        let _ = settings.companionPhotoVersion
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardTitle("外觀", systemImage: "pawprint")
                V2Tiles(title: "外觀", options: ChargingAppearance.allCases.map { ($0, $0.shortTitle) },
                        selection: Binding(get: { settings.chargingAppearance }, set: { settings.selectAppearance($0) }),
                        minWidth: 92, graphicHeight: 52) { appearance in
                    CompanionFigure(presentation: sample, appearance: appearance, animated: false, width: 48)
                }
                HStack(spacing: 10) {
                    Text("我的照片")
                    Spacer()
                    Button(CompanionPhoto.hasCustom ? "換照片…" : "選擇照片…") { settings.chooseCompanionPhoto() }
                        .help("選一張自己的照片，會改用「我的照片」外觀；貓咪大頭照會保留")
                    if CompanionPhoto.hasCustom {
                        Button("移除") { settings.removeCompanionPhoto() }
                            .help("刪掉這張照片（只存在這台 Mac）")
                    }
                }
            }
        }
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SwitchRow("在桌面顯示", isOn: Binding(get: { settings.desktopPet }, set: { settings.desktopPet = $0 }))
                if settings.desktopPet {
                    V2Tiles(title: "位置", options: [(false, "浮在視窗上方"), (true, "放在桌布上")],
                            selection: Binding(get: { settings.desktopPetOnWallpaper }, set: { settings.desktopPetOnWallpaper = $0 }),
                            minWidth: 140, graphicHeight: 52) { onWallpaper in
                        PetPositionGraphic(onWallpaper: onWallpaper, selected: settings.desktopPetOnWallpaper == onWallpaper)
                    }
                    HStack(spacing: 8) {
                        Text("大小")
                        // 不用 step：每 5% 一格會畫出一整排刻度；放開時取到 5% 的倍數
                        Slider(value: Binding(get: { settings.desktopPetScale },
                                              set: { settings.desktopPetScale = AppSettings.clampPetScale(($0 * 20).rounded() / 20) }),
                               in: AppSettings.desktopPetScaleRange)
                            .controlSize(.small)
                            .accessibilityLabel("桌面寵物大小")
                        Text("\(Int((settings.desktopPetScale * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    if settings.chargingAppearance == .photo {
                        SwitchRow("眼睛跟著游標", isOn: Binding(get: { settings.desktopPetFollowCursor }, set: { settings.desktopPetFollowCursor = $0 }))
                            .help("貓咪大頭照：眼珠看著滑鼠游標；關掉就完全不監聽滑鼠移動")
                        SwitchRow("會眨眼、睡覺", isOn: Binding(get: { settings.desktopPetLiveEyes }, set: { settings.desktopPetLiveEyes = $0 }))
                            .help("貓咪大頭照：偶爾眨眼，等智慧充電時閉眼睡覺（滑鼠移過去會醒來）")
                    }
                }
                V2Note("滑鼠移過去看狀態、點一下聊天、來回移動是摸牠；可以拖曳，右鍵可以換大小或隱藏。")
            }
        }
    }
}

/// 桌面寵物的位置示意：一個螢幕、一個視窗，貓掌在視窗前面（浮在上方）或被視窗蓋住（放在桌布上）
private struct PetPositionGraphic: View {
    let onWallpaper: Bool
    let selected: Bool

    var body: some View {
        let accent = selected ? V2Theme.on : Color.secondary
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.5)
                .frame(width: 78, height: 50)
            if onWallpaper { paw(accent) }
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.2))
                .frame(width: 40, height: 28)
                .offset(x: -8, y: 2)
            if !onWallpaper { paw(accent) }
        }
        .accessibilityHidden(true)
    }

    private func paw(_ color: Color) -> some View {
        Image(systemName: "pawprint.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color)
            .offset(x: 10, y: 6)
    }
}
