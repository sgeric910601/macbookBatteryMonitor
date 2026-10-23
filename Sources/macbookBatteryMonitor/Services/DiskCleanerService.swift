import Foundation

/// 磁碟快取與開發者檔案清理服務。
/// 借鑑 Mole 的 lib/clean/dev.sh、lib/clean/app_caches.sh 與 APFS clone 演算法，
/// 提供精準計算、防崩潰進程檢查、以及安全的磁碟空間釋放能力。
public final class DiskCleanerService {

    public struct CacheTarget: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let path: String
        public let associatedProcess: String?
        public var sizeBytes: UInt64
        public var itemCount: Int

        public var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
        }
    }

    public struct CleanResult: Equatable {
        public let targetId: String
        public let targetName: String
        public let success: Bool
        public let freedBytes: UInt64
        public let message: String
    }

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// 取得所有預先定義的清理目標清單
    public func defaultTargets() -> [CacheTarget] {
        let home = NSHomeDirectory()
        return [
            CacheTarget(
                id: "xcode.deriveddata",
                name: "Xcode DerivedData",
                path: "\(home)/Library/Developer/Xcode/DerivedData",
                associatedProcess: "Xcode",
                sizeBytes: 0,
                itemCount: 0
            ),
            CacheTarget(
                id: "xcode.simulator",
                name: "iOS Simulator Caches",
                path: "\(home)/Library/Developer/CoreSimulator/Caches",
                associatedProcess: "Simulator",
                sizeBytes: 0,
                itemCount: 0
            ),
            CacheTarget(
                id: "homebrew.downloads",
                name: "Homebrew 下載快取",
                path: "\(home)/Library/Caches/Homebrew/downloads",
                associatedProcess: "brew",
                sizeBytes: 0,
                itemCount: 0
            ),
            CacheTarget(
                id: "npm.cache",
                name: "npm 快取",
                path: "\(home)/.npm/_cacache",
                associatedProcess: "node",
                sizeBytes: 0,
                itemCount: 0
            ),
            CacheTarget(
                id: "cargo.cache",
                name: "Rust Cargo 下載快取",
                path: "\(home)/.cargo/registry/cache",
                associatedProcess: "cargo",
                sizeBytes: 0,
                itemCount: 0
            )
        ]
    }

    /// 掃描目標目錄的實際佔用大小與檔案數（利用 APFSCloneResolver 排除區塊共享克隆）
    public func calculateSize(for path: String) -> (bytes: UInt64, count: Int) {
        guard fileManager.fileExists(atPath: path) else { return (0, 0) }

        let url = URL(fileURLWithPath: path)
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return (0, 0)
        }

        var totalBytes: UInt64 = 0
        var fileCount = 0

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true,
                  let size = values.fileSize else {
                continue
            }

            // APFS 區塊克隆排查：若為已全區塊共享的克隆檔案，不計入重複空間
            if APFSCloneResolver.isSharedClone(at: fileURL.path) {
                continue
            }

            totalBytes += UInt64(size)
            fileCount += 1
        }

        return (totalBytes, fileCount)
    }

    /// 掃描所有目標並回傳更新大小後的清單
    public func scanTargets() -> [CacheTarget] {
        var targets = defaultTargets()
        for i in 0..<targets.count {
            let path = targets[i].path
            if fileManager.fileExists(atPath: path) {
                let (bytes, count) = calculateSize(for: path)
                targets[i].sizeBytes = bytes
                targets[i].itemCount = count
            }
        }
        return targets
    }

    /// 安全清理指定快取目標
    public func clean(target: CacheTarget) -> CleanResult {
        let (safe, reason) = ProcessGuard.isSafeToClean(path: target.path, associatedProcess: target.associatedProcess)
        guard safe else {
            return CleanResult(
                targetId: target.id,
                targetName: target.name,
                success: false,
                freedBytes: 0,
                message: reason ?? "安全性檢查未通過"
            )
        }

        guard fileManager.fileExists(atPath: target.path) else {
            return CleanResult(
                targetId: target.id,
                targetName: target.name,
                success: true,
                freedBytes: 0,
                message: "目標目錄不存在或已被清空"
            )
        }

        // 先計算要刪除的大小
        let (bytesToDelete, _) = calculateSize(for: target.path)
        guard bytesToDelete > 0 else {
            return CleanResult(
                targetId: target.id,
                targetName: target.name,
                success: true,
                freedBytes: 0,
                message: "快取目前為空，無需清理"
            )
        }

        do {
            // 清理目錄底下的內容而非根目錄自身
            let contents = try fileManager.contentsOfDirectory(atPath: target.path)
            for item in contents {
                let subpath = (target.path as NSString).appendingPathComponent(item)
                try fileManager.removeItem(atPath: subpath)
            }
            return CleanResult(
                targetId: target.id,
                targetName: target.name,
                success: true,
                freedBytes: bytesToDelete,
                message: "已釋放 \(ByteCountFormatter.string(fromByteCount: Int64(bytesToDelete), countStyle: .file))"
            )
        } catch {
            return CleanResult(
                targetId: target.id,
                targetName: target.name,
                success: false,
                freedBytes: 0,
                message: "清理失敗：\(error.localizedDescription)"
            )
        }
    }

    /// 一鍵清理所有安全項目
    public func cleanAll(targets: [CacheTarget]) -> [CleanResult] {
        return targets.map { clean(target: $0) }
    }
}
