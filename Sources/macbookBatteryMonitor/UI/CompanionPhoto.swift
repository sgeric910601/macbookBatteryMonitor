import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// 照片外觀用的照片。「貓咪大頭照」是內建的貓咪照片（眼睛會動），「我的照片」是自己選的，兩者分開，換照片不影響貓咪大頭照。
/// 自己選的照片裁成正方形、縮小並重新編碼（不留拍攝地點等照片資訊），存在 Application Support
@MainActor
enum CompanionPhoto {
    /// 存檔的邊長（像素）：桌面寵物的照片在 Retina 螢幕上約 220 像素寬
    private static let pixels = 256

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BatteryMonitor/companion-photo.jpg")
    }

    /// 224 像素、四角填平均色的 HEIC（約 5 KB），桌面寵物最大時也夠清楚
    private static var bundledURL: URL? { Bundle.main.url(forResource: "companion-photo", withExtension: "heic") }

    /// 內建的貓咪照片，與它的像素（做會動的眼睛用）
    static let bundledImage: NSImage? = bundledURL.flatMap { NSImage(contentsOf: $0) }
    static let bundledCGImage: CGImage? = loadCGImage(bundledURL)
    /// 自己選的照片，還沒選時是 nil；換照片後畫面要讀 AppSettings.companionPhotoVersion 才會重畫
    private(set) static var customImage: NSImage? = NSImage(contentsOf: fileURL)
    /// 截圖時不畫出使用者自己的照片
    private static var screenshotMode = false

    /// 選過自己的照片
    static var hasCustom: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    /// custom 為 true 是「我的照片」，否則是貓咪大頭照；截圖時一律用貓咪大頭照
    static func image(custom: Bool) -> NSImage? {
        custom && !screenshotMode ? customImage : bundledImage
    }

    private static func loadCGImage(_ url: URL?) -> CGImage? {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// 選一張自己的照片；換成功時 completion(true)。從桌面寵物或面板打開時 App 不一定在前景，先帶到前景
    static func choose(completion: @escaping (Bool) -> Void) {
        NSApp.activateCompat()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "選一張照片，會從中間裁成圓形"
        panel.prompt = "使用這張照片"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return completion(false) }
            completion(save(from: url))
        }
    }

    /// 刪掉自己的照片
    static func removeCustom() {
        try? FileManager.default.removeItem(at: fileURL)
        customImage = nil
    }

    /// 截圖（README、開發用快照）只用內建的貓咪照片，不畫出使用者自己的照片
    static func useBundledForScreenshots() {
        screenshotMode = true
    }

    private static func save(from url: URL) -> Bool {
        // 依照片的方向轉正，先縮到不超過 2048 像素再裁切，大照片也不會吃太多記憶體
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: 2048] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let photo = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return false }
        let side = min(photo.width, photo.height)
        let crop = CGRect(x: (photo.width - side) / 2, y: (photo.height - side) / 2, width: side, height: side)
        let target = min(side, pixels)
        guard let square = photo.cropping(to: crop),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: target, height: target, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        context.interpolationQuality = .high
        context.draw(square, in: CGRect(x: 0, y: 0, width: target, height: target))
        guard let output = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: output).representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        else { return false }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return false
        }
        customImage = NSImage(data: data)
        return true
    }
}

/// 照片外觀：照片裁成圓形，外圈是電量環（顏色跟著狀態），右上角和其他外觀一樣有狀態徽章；寬度決定大小。
/// 貓咪大頭照在桌面寵物（liveEyes）上眼睛會跟著游標、眨眼，睡覺時閉眼；我的照片（custom）眼睛不會動
struct CompanionPhotoFigure: View {
    let presentation: ChargingJourneyPresentation
    var width: CGFloat = 48
    var custom = false
    var liveEyes = false
    var mood: CatMood = .awake
    var followsCursor = true

    var body: some View {
        let unit = width / 48
        ZStack {
            Group {
                if let image = CompanionPhoto.image(custom: custom) {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
                } else {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 16 * unit))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 38 * unit, height: 38 * unit)
            .overlay(alignment: .center) { eyesOverlay }
            .background(Color.secondary.opacity(0.15))
            .clipShape(Circle())
            Circle()
                .stroke(presentation.color.opacity(0.22), lineWidth: 3 * unit)
                .frame(width: 44 * unit, height: 44 * unit)
            Circle()
                .trim(from: 0, to: max(0.02, presentation.progress))
                .stroke(presentation.color, style: StrokeStyle(lineWidth: 3 * unit, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 44 * unit, height: 44 * unit)
        }
        .frame(width: width, height: width * 50 / 48)
        .overlay(alignment: .topTrailing) {
            if let badge = presentation.badge {
                CompanionBadgeIcon(badge: badge, tint: presentation.color, size: 14 * unit)
                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).padding(1 * unit))
            } else if presentation.onPad {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 14 * unit, weight: .semibold))
                    .foregroundStyle(.white, presentation.color)
                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).padding(1 * unit))
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var eyesOverlay: some View {
        if liveEyes, !custom, let photo = CompanionPhoto.bundledCGImage {
            CatEyesOverlay(photo: photo, eyes: CatEye.bundled, key: 0, mood: mood, followsCursor: followsCursor)
        }
    }
}

extension AppSettings {
    /// 選一張自己的照片，選好就改用「我的照片」外觀
    func chooseCompanionPhoto() {
        CompanionPhoto.choose { [weak self] chosen in
            guard let self, chosen else { return }
            companionPhotoVersion += 1
            chargingAppearance = .customPhoto
        }
    }

    /// 刪掉自己的照片；正在用「我的照片」時改回貓咪大頭照
    func removeCompanionPhoto() {
        CompanionPhoto.removeCustom()
        companionPhotoVersion += 1
        if chargingAppearance == .customPhoto { chargingAppearance = .photo }
    }

    /// 從外觀選單換外觀：還沒選過照片就選「我的照片」時，先請使用者選一張（取消就維持原本的外觀）
    func selectAppearance(_ appearance: ChargingAppearance) {
        if appearance == .customPhoto, !CompanionPhoto.hasCustom {
            chooseCompanionPhoto()
        } else {
            chargingAppearance = appearance
        }
    }
}
