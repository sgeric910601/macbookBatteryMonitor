import AppKit
import CoreGraphics

/// 視窗縮圖：背景擷取、縮小後放進快取。需要「螢幕錄製」權限；沒有權限時不擷取，切換器改顯示 App 圖示。
/// 同時最多兩個擷取在進行（系統一次只處理一個，多排只會讓每個等更久），快取讓再次打開切換器時立刻有圖
final class WindowThumbnails: @unchecked Sendable {
    static let shared = WindowThumbnails()

    private static let cacheLimit = 96

    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.kuan.batterymonitor.thumbnails"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private let lock = NSLock()
    private var images: [UInt32: CGImage] = [:]
    private var recentlyUsed: [UInt32] = []
    private var pending = Set<UInt32>()

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() { _ = CGRequestScreenCaptureAccess() }

    func cached(_ id: UInt32) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return images[id]
    }

    /// 擷取這些視窗（已經在排隊的不重複排）；每張擷取完成時在主執行緒呼叫 done
    func request(_ ids: [UInt32], maxPixelWidth: Int, done: @escaping @MainActor (UInt32, CGImage) -> Void) {
        guard Self.hasPermission, SkyLight.canCapture else { return }
        for id in ids {
            lock.lock()
            let inserted = pending.insert(id).inserted
            lock.unlock()
            guard inserted else { continue }
            queue.addOperation { [self] in
                defer {
                    lock.lock()
                    pending.remove(id)
                    lock.unlock()
                }
                let started = Date()
                defer { InputTap.log.notice("擷取視窗 \(id)：等待 + 擷取 \(Int(Date().timeIntervalSince(started) * 1000)) ms") }
                guard let full = SkyLight.capture(id), let small = Self.scaled(full, maxPixelWidth: maxPixelWidth) else { return }
                store(small, for: id)
                DispatchQueue.main.async { MainActor.assumeIsolated { done(id, small) } }
            }
        }
    }

    /// 單張高解析度擷取（預覽用，不進快取）；完成時在主執行緒呼叫 done，抓不到不呼叫
    func captureOnce(_ id: UInt32, maxPixelWidth: Int, done: @escaping @MainActor (CGImage) -> Void) {
        guard Self.hasPermission, SkyLight.canCapture else { return }
        queue.addOperation {
            guard let full = SkyLight.capture(id), let image = Self.scaled(full, maxPixelWidth: maxPixelWidth) else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { done(image) } }
        }
    }

    /// 全部釋放：功能停用時不把其他 App 的畫面留在記憶體裡
    func purge() {
        lock.lock()
        defer { lock.unlock() }
        images.removeAll()
        recentlyUsed.removeAll()
    }

    /// 視窗關掉後釋放它的縮圖
    func forget(_ ids: Set<UInt32>) {
        lock.lock()
        defer { lock.unlock() }
        for id in ids { images[id] = nil }
        recentlyUsed.removeAll { ids.contains($0) }
    }

    private func store(_ image: CGImage, for id: UInt32) {
        lock.lock()
        defer { lock.unlock() }
        images[id] = image
        recentlyUsed.removeAll { $0 == id }
        recentlyUsed.append(id)
        while recentlyUsed.count > Self.cacheLimit { images[recentlyUsed.removeFirst()] = nil }
    }

    static func scaled(_ image: CGImage, maxPixelWidth: Int) -> CGImage? {
        guard image.width > 0, image.height > 0 else { return nil }
        guard image.width > maxPixelWidth else { return image }
        let height = max(1, image.height * maxPixelWidth / image.width)
        guard let context = CGContext(data: nil, width: maxPixelWidth, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: maxPixelWidth, height: height))
        return context.makeImage()
    }
}
