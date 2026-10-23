import Foundation

final class DiskCleanerTests {

    func testAPFSCloneResolverOnStandardFile() {
        // 驗證對於標準檔案的 clone 狀態讀取（至少不應當崩潰，且回傳預期的 boolean/nil）
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("apfs_test_\(UUID().uuidString).txt")
        try? "test data".write(to: testFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let info = APFSCloneResolver.cloneInfo(for: testFile.path)
        // 在 APFS 卷軸上應能讀出 info，在一般單獨建立的檔案上 sharesAllBlocks 應為 false
        if let info = info {
            assert(!info.sharesAllBlocks, "一般新建檔案不應是共享區塊克隆")
        }

        // 不存在檔案應回傳 nil
        assert(APFSCloneResolver.cloneInfo(for: "/non/existent/path/file.dat") == nil)
        assert(!APFSCloneResolver.isSharedClone(at: "/non/existent/path/file.dat"))
    }

    func testProcessGuardSensitivePaths() {
        // 敏感路徑防護測試
        assert(ProcessGuard.isSensitivePath("/Users/user/.ssh/id_rsa"), "SSH 金鑰必須被攔截")
        assert(ProcessGuard.isSensitivePath("/Users/user/.gnupg/secring.gpg"), "GPG 金鑰必須被攔截")
        assert(ProcessGuard.isSensitivePath("/Users/user/.aws/credentials"), "AWS 憑證必須被攔截")
        assert(ProcessGuard.isSensitivePath("/Users/user/Library/Keychains/login.keychain-db"), "Keychain 必須被攔截")
        assert(ProcessGuard.isSensitivePath("/Users/user/Library/Cookies/Cookies.binarycookies"), "Cookies 必須被攔截")
        assert(ProcessGuard.isSensitivePath("/Users/user/Desktop/secret.txt"), "Desktop 檔案必須被保護")
        assert(ProcessGuard.isSensitivePath("/Users/user/Documents/report.pdf"), "Documents 必須被保護")

        // 安全快取路徑應通過敏感檢查
        assert(!ProcessGuard.isSensitivePath("/Users/user/Library/Developer/Xcode/DerivedData"), "Xcode DerivedData 不應被標記為敏感")
        assert(!ProcessGuard.isSensitivePath("/Users/user/Library/Caches/Homebrew/downloads"), "Homebrew 快取不應被標記為敏感")
    }

    func testProcessGuardSystemPaths() {
        assert(ProcessGuard.isProtectedSystemPath("/System"), "/System 必須受保護")
        assert(ProcessGuard.isProtectedSystemPath("/System/Library"), "/System/Library 必須受保護")
        assert(ProcessGuard.isProtectedSystemPath("/bin"), "/bin 必須受保護")
        assert(ProcessGuard.isProtectedSystemPath("/usr/bin/git"), "/usr/bin 必須受保護")

        assert(!ProcessGuard.isProtectedSystemPath("/Users/user/Library/Caches"), "使用者快取不應是系統保護路徑")
    }

    func testProcessGuardSafeToCleanCheck() {
        // 敏感路徑拒絕清理
        let (safe1, reason1) = ProcessGuard.isSafeToClean(path: "/Users/user/.ssh/id_rsa")
        assert(!safe1, "敏感路徑必須禁止清理")
        assert(reason1 != nil)

        // 系統路徑拒絕清理
        let (safe2, reason2) = ProcessGuard.isSafeToClean(path: "/System/Library/Caches")
        assert(!safe2, "系統目錄必須禁止清理")
        assert(reason2 != nil)

        // 合法快取路徑應允許（當沒有進程佔用時）
        let (safe3, reason3) = ProcessGuard.isSafeToClean(path: "/Users/user/Library/Developer/Xcode/DerivedData", associatedProcess: "NonExistentDummyApp99999")
        assert(safe3, "合法快取且無進程運作時應允許清理")
        assert(reason3 == nil)
    }

    func testDiskCleanerCalculationAndClean() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cleaner_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 建立假快取檔案
        let file1 = tempDir.appendingPathComponent("cache1.dat")
        let file2 = tempDir.appendingPathComponent("cache2.dat")
        let data = Data(repeating: 0x41, count: 1024) // 1 KB
        try? data.write(to: file1)
        try? data.write(to: file2)

        let service = DiskCleanerService()
        let (bytes, count) = service.calculateSize(for: tempDir.path)
        assert(bytes == 2048, "總大小應為 2048 bytes，實際為 \(bytes)")
        assert(count == 2, "檔案數應為 2，實際為 \(count)")

        // 執行清理測試
        let target = DiskCleanerService.CacheTarget(
            id: "test.target",
            name: "測試快取",
            path: tempDir.path,
            associatedProcess: "NonExistentDummyApp99999",
            sizeBytes: bytes,
            itemCount: count
        )

        let result = service.clean(target: target)
        assert(result.success, "清理應成功：\(result.message)")
        assert(result.freedBytes == 2048, "釋放大小應為 2048")

        // 清理後再次計算應為 0
        let (afterBytes, afterCount) = service.calculateSize(for: tempDir.path)
        assert(afterBytes == 0, "清理後大小應為 0")
        assert(afterCount == 0, "清理後檔案數應為 0")
    }

    func testSystemMaintenanceStructure() {
        // 驗證 SystemMaintenanceService 回傳結構
        let outcome = SystemMaintenanceService.MaintenanceOutcome(
            operation: "測試操作",
            success: true,
            details: "無錯誤"
        )
        assert(outcome.operation == "測試操作")
        assert(outcome.success)
    }
}
