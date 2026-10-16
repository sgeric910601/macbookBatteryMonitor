import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// 「照片」外觀用的照片：預設是內建的貓咪照片，也可以換成自己的。
/// 自己選的照片裁成正方形、縮小並重新編碼（不留拍攝地點等照片資訊），存在 Application Support
@MainActor
enum CompanionPhoto {
    /// 存檔的邊長（像素）：桌面寵物的照片在 Retina 螢幕上約 220 像素寬
    private static let pixels = 256

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BatteryMonitor/companion-photo.jpg")
    }

    private static var bundled: NSImage? {
        // 224 像素、四角填平均色的 HEIC（約 5 KB），桌面寵物最大時也夠清楚
        Bundle.main.url(forResource: "companion-photo", withExtension: "heic").flatMap { NSImage(contentsOf: $0) }
    }

    /// 目前的照片；換照片後畫面要讀 AppSettings.companionPhotoVersion 才會重畫
    private(set) static var image: NSImage? = NSImage(contentsOf: fileURL) ?? bundled

    /// 用的是自己選的照片
    static var isCustom: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    /// 選一張照片；換成功時 completion(true)。從桌面寵物或面板打開時 App 不一定在前景，先帶到前景
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

    /// 截圖（README、開發用快照）只用內建的貓咪照片，不畫出使用者自己的照片
    static func useBundledForScreenshots() {
        image = bundled
    }

    static func reset() {
        try? FileManager.default.removeItem(at: fileURL)
        image = bundled
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
        image = NSImage(data: data)
        return true
    }
}

/// 照片外觀：照片裁成圓形，外圈是電量環（顏色跟著狀態），右上角和其他外觀一樣有狀態徽章；寬度決定大小
struct CompanionPhotoFigure: View {
    let presentation: ChargingJourneyPresentation
    var width: CGFloat = 48

    var body: some View {
        let unit = width / 48
        ZStack {
            Group {
                if let image = CompanionPhoto.image {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
                } else {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 16 * unit))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 38 * unit, height: 38 * unit)
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
                Image(systemName: badge.symbol)
                    .font(.system(size: 14 * unit, weight: .semibold))
                    .foregroundStyle(.white, presentation.color)
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
}

extension AppSettings {
    /// 選一張自己的照片，選好就改用照片外觀
    func chooseCompanionPhoto() {
        CompanionPhoto.choose { [weak self] chosen in
            guard let self, chosen else { return }
            companionPhotoVersion += 1
            chargingAppearance = .photo
        }
    }

    /// 改回內建的貓咪照片
    func resetCompanionPhoto() {
        CompanionPhoto.reset()
        companionPhotoVersion += 1
    }
}
