import Foundation
import AppKit

/// 磁碟深度分析、快取分類與空間回收服務。
/// 結合 Mole 的 mo clean、mo analyze、mo installer 與 APFS clone 演算法，
/// 提供多分類快取掃描、孤立殘留偵測、大型檔案搜尋與安全釋放能力。
public final class DiskCleanerService {

    public enum CategoryType: String, CaseIterable, Identifiable {
        case developer = "開發者快取"
        case installers = "安裝包與磁碟映像"
        case orphanLeftovers = "已卸載 App 殘留"
        case systemLogs = "日誌與崩潰診斷"

        public var id: String { rawValue }
        public var icon: String {
            switch self {
            case .developer: return "hammer"
            case .installers: return "shippingbox"
            case .orphanLeftovers: return "trash.slash"
            case .systemLogs: return "doc.text.magnifyingglass"
            }
        }
    }

    public struct CleanableItem: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let path: String
        public let category: CategoryType
        public let associatedProcess: String?
        public var sizeBytes: UInt64
        public var itemCount: Int

        public var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
        }
    }

    public struct LargeFile: Identifiable, Equatable {
        public let id: String
        public let name: String
        public let path: String
        public let sizeBytes: UInt64
        public let modifiedDate: Date?

        public var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
        }
    }

    public struct ScanResult: Equatable {
        public var itemsByCategory: [CategoryType: [CleanableItem]]
        public var largeFiles: [LargeFile]
        public var totalCleanableBytes: UInt64

        public var formattedTotal: String {
            ByteCountFormatter.string(fromByteCount: Int64(totalCleanableBytes), countStyle: .file)
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

    // MARK: - 1. 開發者快取定義
    public func developerTargets() -> [CleanableItem] {
        let home = NSHomeDirectory()
        return [
            CleanableItem(id: "xcode.deriveddata", name: "Xcode DerivedData",
                          path: "\(home)/Library/Developer/Xcode/DerivedData",
                          category: .developer, associatedProcess: "Xcode", sizeBytes: 0, itemCount: 0),
            CleanableItem(id: "xcode.simulator", name: "iOS Simulator 快取",
                          path: "\(home)/Library/Developer/CoreSimulator/Caches",
                          category: .developer, associatedProcess: "Simulator", sizeBytes: 0, itemCount: 0),
            CleanableItem(id: "homebrew.downloads", name: "Homebrew 下載封包",
                          path: "\(home)/Library/Caches/Homebrew/downloads",
                          category: .developer, associatedProcess: "brew", sizeBytes: 0, itemCount: 0),
            CleanableItem(id: "npm.cache", name: "npm 快取",
                          path: "\(home)/.npm/_cacache",
                          category: .developer, associatedProcess: "node", sizeBytes: 0, itemCount: 0),
            CleanableItem(id: "cargo.cache", name: "Rust Cargo 下載庫",
                          path: "\(home)/.cargo/registry/cache",
                          category: .developer, associatedProcess: "cargo", sizeBytes: 0, itemCount: 0)
        ]
    }

    // MARK: - 2. 下載目錄中的過期安裝封包
    public func scanInstallerPackages() -> [CleanableItem] {
        let downloads = "\(NSHomeDirectory())/Downloads"
        guard fileManager.fileExists(atPath: downloads) else { return [] }

        let allowedExtensions: Set<String> = ["dmg", "pkg", "iso", "xip"]
        var results: [CleanableItem] = []

        guard let contents = try? fileManager.contentsOfDirectory(atPath: downloads) else { return [] }
        for file in contents {
            let ext = (file as NSString).pathExtension.lowercased()
            if allowedExtensions.contains(ext) {
                let fullPath = (downloads as NSString).appendingPathComponent(file)
                if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
                   let size = attrs[.size] as? UInt64 {
                    // 只統計大於 20MB 的安裝封包
                    if size > 20 * 1024 * 1024 {
                        results.append(CleanableItem(
                            id: "installer.\(file)",
                            name: file,
                            path: fullPath,
                            category: .installers,
                            associatedProcess: nil,
                            sizeBytes: size,
                            itemCount: 1
                        ))
                    }
                }
            }
        }
        return results
    }

    // MARK: - 3. 已解除安裝 App 的孤立殘留偵測
    public func scanOrphanLeftovers() -> [CleanableItem] {
        let appSupport = "\(NSHomeDirectory())/Library/Application Support"
        guard fileManager.fileExists(atPath: appSupport) else { return [] }

        var orphans: [CleanableItem] = []
        guard let dirs = try? fileManager.contentsOfDirectory(atPath: appSupport) else { return [] }

        // 受保護的系統目錄與主要常駐名單
        let protected: Set<String> = [
            "Apple", "CrashReporter", "Dock", "com.apple.sharedfilelist", "SyncServices", "Google", "Microsoft"
        ]

        for dir in dirs {
            if protected.contains(dir) || dir.hasPrefix(".") { continue }
            let fullPath = (appSupport as NSString).appendingPathComponent(dir)

            // 判斷是否看起來像 bundle id (例如 com.example.app)
            if dir.contains(".") && !dir.hasPrefix("com.apple.") {
                // 檢查該 App 是否已不存在
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: dir) == nil {
                    let (size, count) = calculateSize(for: fullPath)
                    if size > 10 * 1024 * 1024 { // 超過 10MB 的殘留
                        orphans.append(CleanableItem(
                            id: "orphan.\(dir)",
                            name: "已卸載 App 殘留: \(dir)",
                            path: fullPath,
                            category: .orphanLeftovers,
                            associatedProcess: nil,
                            sizeBytes: size,
                            itemCount: count
                        ))
                    }
                }
            }
        }
        return orphans
    }

    // MARK: - 4. 系統日誌與診斷日誌
    public func systemLogsTargets() -> [CleanableItem] {
        let home = NSHomeDirectory()
        return [
            CleanableItem(id: "diag.reports", name: "使用者崩潰診斷報告",
                          path: "\(home)/Library/Logs/DiagnosticReports",
                          category: .systemLogs, associatedProcess: nil, sizeBytes: 0, itemCount: 0)
        ]
    }

    // MARK: - 5. 查找 Top 5 大型檔案
    public func findTopLargeFiles(limit: Int = 5) -> [LargeFile] {
        let home = NSHomeDirectory()
        let scanRoots = ["\(home)/Downloads", "\(home)/Movies", "\(home)/Documents"]
        var allFiles: [LargeFile] = []

        for root in scanRoots {
            guard fileManager.fileExists(atPath: root) else { continue }
            let url = URL(fileURLWithPath: root)
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                                         options: [.skipsPackageDescendants, .skipsHiddenFiles]) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      let size = values.fileSize,
                      size > 100 * 1024 * 1024 else { // 大於 100MB
                    continue
                }

                // 排除 APFS 區塊共享克隆檔，避免重複展示
                if APFSCloneResolver.isSharedClone(at: fileURL.path) {
                    continue
                }

                allFiles.append(LargeFile(
                    id: fileURL.path,
                    name: fileURL.lastPathComponent,
                    path: fileURL.path,
                    sizeBytes: UInt64(size),
                    modifiedDate: values.contentModificationDate
                ))
            }
        }

        // 依大小由大到小排序取前 N 名
        allFiles.sort { $0.sizeBytes > $1.sizeBytes }
        return Array(allFiles.prefix(limit))
    }

    // MARK: - 計算大小（整合 APFS Clone 排除）
    public func calculateSize(for path: String) -> (bytes: UInt64, count: Int) {
        guard fileManager.fileExists(atPath: path) else { return (0, 0) }

        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue {
            // 單一檔案
            let size = (try? fileManager.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
            return (size, 1)
        }

        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: Array(keys),
                                                     options: [.skipsHiddenFiles]) else {
            return (0, 0)
        }

        var totalBytes: UInt64 = 0
        var fileCount = 0

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }

            if APFSCloneResolver.isSharedClone(at: fileURL.path) { continue }

            totalBytes += UInt64(size)
            fileCount += 1
        }

        return (totalBytes, fileCount)
    }

    // MARK: - 完整深度掃描
    public func performDeepScan() -> ScanResult {
        var items: [CategoryType: [CleanableItem]] = [:]
        var totalBytes: UInt64 = 0

        // 1. 開發者快取
        var dev = developerTargets()
        for i in 0..<dev.count {
            if fileManager.fileExists(atPath: dev[i].path) {
                let (bytes, count) = calculateSize(for: dev[i].path)
                dev[i].sizeBytes = bytes
                dev[i].itemCount = count
                totalBytes += bytes
            }
        }
        items[.developer] = dev.filter { $0.sizeBytes > 0 }

        // 2. 安裝包
        let installers = scanInstallerPackages()
        for inst in installers { totalBytes += inst.sizeBytes }
        items[.installers] = installers

        // 3. 孤立殘留
        let orphans = scanOrphanLeftovers()
        for orphan in orphans { totalBytes += orphan.sizeBytes }
        items[.orphanLeftovers] = orphans

        // 4. 日誌
        var logs = systemLogsTargets()
        for i in 0..<logs.count {
            if fileManager.fileExists(atPath: logs[i].path) {
                let (bytes, count) = calculateSize(for: logs[i].path)
                logs[i].sizeBytes = bytes
                logs[i].itemCount = count
                totalBytes += bytes
            }
        }
        items[.systemLogs] = logs.filter { $0.sizeBytes > 0 }

        // 5. 大型檔案
        let large = findTopLargeFiles(limit: 5)

        return ScanResult(itemsByCategory: items, largeFiles: large, totalCleanableBytes: totalBytes)
    }

    // MARK: - 清理單一項目
    public func clean(item: CleanableItem) -> CleanResult {
        let (safe, reason) = ProcessGuard.isSafeToClean(path: item.path, associatedProcess: item.associatedProcess)
        guard safe else {
            return CleanResult(targetId: item.id, targetName: item.name, success: false, freedBytes: 0,
                               message: reason ?? "安全性檢查未通過")
        }

        guard fileManager.fileExists(atPath: item.path) else {
            return CleanResult(targetId: item.id, targetName: item.name, success: true, freedBytes: 0,
                               message: "目標不存在")
        }

        var isDir: ObjCBool = false
        fileManager.fileExists(atPath: item.path, isDirectory: &isDir)

        do {
            if isDir.boolValue {
                let (bytesToDelete, _) = calculateSize(for: item.path)
                let contents = try fileManager.contentsOfDirectory(atPath: item.path)
                for sub in contents {
                    let subpath = (item.path as NSString).appendingPathComponent(sub)
                    try fileManager.removeItem(atPath: subpath)
                }
                return CleanResult(targetId: item.id, targetName: item.name, success: true, freedBytes: bytesToDelete,
                                   message: "已釋放 \(ByteCountFormatter.string(fromByteCount: Int64(bytesToDelete), countStyle: .file))")
            } else {
                let size = (try? fileManager.attributesOfItem(atPath: item.path)[.size] as? UInt64) ?? 0
                try fileManager.removeItem(atPath: item.path)
                return CleanResult(targetId: item.id, targetName: item.name, success: true, freedBytes: size,
                                   message: "已刪除")
            }
        } catch {
            return CleanResult(targetId: item.id, targetName: item.name, success: false, freedBytes: 0,
                               message: "清理失敗：\(error.localizedDescription)")
        }
    }

    // MARK: - 清理單一類別全部
    public func cleanCategory(_ items: [CleanableItem]) -> [CleanResult] {
        return items.map { clean(item: $0) }
    }
}
