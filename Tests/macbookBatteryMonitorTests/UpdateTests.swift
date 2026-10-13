import Foundation

final class UpdateTests {
    func testVersionParsingAndComparison() {
        XCTAssertEqual(UpdateLogic.version("v1.4.1"), [1, 4, 1])
        XCTAssertEqual(UpdateLogic.version("1.10.0"), [1, 10, 0])
        XCTAssertNil(UpdateLogic.version("v1.4.1-beta"))
        XCTAssertNil(UpdateLogic.version(""))
        XCTAssertTrue(UpdateLogic.isNewer([1, 4, 2], than: [1, 4, 1]))
        XCTAssertTrue(UpdateLogic.isNewer([1, 10, 0], than: [1, 9, 9]))
        XCTAssertTrue(!UpdateLogic.isNewer([1, 4], than: [1, 4, 0]))
        XCTAssertTrue(!UpdateLogic.isNewer([1, 4, 0], than: [1, 4, 1]))
        XCTAssertTrue(UpdateLogic.isNewer([2], than: [1, 99, 99]))
    }

    func testNotifyOncePerVersion() {
        // 沒通知過、或比上次通知的版本新才通知
        XCTAssertTrue(UpdateLogic.shouldNotify([1, 6, 2], lastNotified: nil))
        XCTAssertTrue(UpdateLogic.shouldNotify([1, 6, 2], lastNotified: "v1.6.1"))
        XCTAssertTrue(UpdateLogic.shouldNotify([1, 7, 0], lastNotified: "v1.6.2"))
        XCTAssertTrue(!UpdateLogic.shouldNotify([1, 6, 2], lastNotified: "v1.6.2"))
        XCTAssertTrue(!UpdateLogic.shouldNotify([1, 6, 1], lastNotified: "v1.6.2"))
        // 記錄壞掉時當作沒通知過
        XCTAssertTrue(UpdateLogic.shouldNotify([1, 6, 2], lastNotified: "garbage"))
    }

    func testReleaseParsingPicksEditionAndChecksum() {
        let json = """
        {"tag_name":"v1.5.0","html_url":"https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.5.0",
         "draft":false,"prerelease":false,"assets":[
          {"name":"macbookBatteryMonitor-v1.5.0-battery-macOS-arm64.zip","size":100,
           "browser_download_url":"https://github.com/sgeric910601/macbookBatteryMonitor/releases/download/v1.5.0/macbookBatteryMonitor-v1.5.0-battery-macOS-arm64.zip"},
          {"name":"macbookBatteryMonitor-v1.5.0-status-macOS-arm64.zip","size":200,
           "browser_download_url":"https://github.com/sgeric910601/macbookBatteryMonitor/releases/download/v1.5.0/macbookBatteryMonitor-v1.5.0-status-macOS-arm64.zip"},
          {"name":"SHA256SUMS.txt","size":10,
           "browser_download_url":"https://github.com/sgeric910601/macbookBatteryMonitor/releases/download/v1.5.0/SHA256SUMS.txt"}]}
        """
        let status = UpdateLogic.release(json: Data(json.utf8), edition: "status")
        XCTAssertEqual(status?.version, [1, 5, 0])
        XCTAssertEqual(status?.assetSize, 200)
        XCTAssertEqual(status?.assetName, "macbookBatteryMonitor-v1.5.0-status-macOS-arm64.zip")
        XCTAssertTrue(status?.checksumURL != nil)
        XCTAssertEqual(UpdateLogic.release(json: Data(json.utf8), edition: "battery")?.assetSize, 100)
        // 沒有通用版的 Release：通用版（或不認得的版本別）改用系統監控版的舊檔名
        XCTAssertEqual(UpdateLogic.release(json: Data(json.utf8), edition: "universal")?.assetSize, 200)
        // 有通用版就優先用通用版，不管目前是哪個版本別
        let universal = json.replacingOccurrences(of: "{\"name\":\"SHA256SUMS.txt\"", with: """
          {"name":"macbookBatteryMonitor-v1.5.0-macOS-universal.zip","size":300,
           "browser_download_url":"https://github.com/sgeric910601/macbookBatteryMonitor/releases/download/v1.5.0/macbookBatteryMonitor-v1.5.0-macOS-universal.zip"},
          {"name":"SHA256SUMS.txt"
        """)
        XCTAssertEqual(UpdateLogic.release(json: Data(universal.utf8), edition: "battery")?.assetName, "macbookBatteryMonitor-v1.5.0-macOS-universal.zip")
        XCTAssertEqual(UpdateLogic.release(json: Data(universal.utf8), edition: "universal")?.assetSize, 300)
        // 舊系統版本：只找 macOS12 檔；系統已升級到 macOS 14 以上時改裝主版本的通用版
        let legacy = universal.replacingOccurrences(of: "{\"name\":\"SHA256SUMS.txt\"", with: """
          {"name":"macbookBatteryMonitor-v1.5.0-macOS12.zip","size":400,
           "browser_download_url":"https://github.com/sgeric910601/macbookBatteryMonitor/releases/download/v1.5.0/macbookBatteryMonitor-v1.5.0-macOS12.zip"},
          {"name":"SHA256SUMS.txt"
        """)
        XCTAssertEqual(UpdateLogic.release(json: Data(legacy.utf8), edition: "legacy", mainSupported: false)?.assetSize, 400)
        XCTAssertEqual(UpdateLogic.release(json: Data(legacy.utf8), edition: "legacy", mainSupported: true)?.assetSize, 300)
        XCTAssertNil(UpdateLogic.release(json: Data(universal.utf8), edition: "legacy", mainSupported: false))
        // 預覽版、或下載網址不是 GitHub，都不更新
        XCTAssertNil(UpdateLogic.release(json: Data(json.replacingOccurrences(of: "\"prerelease\":false", with: "\"prerelease\":true").utf8), edition: "status"))
        XCTAssertNil(UpdateLogic.release(json: Data(json.replacingOccurrences(of: "https://github.com/sgeric910601/macbookBatteryMonitor/releases/download/v1.5.0/macbookBatteryMonitor-v1.5.0-status", with: "https://evil.example.com/x").utf8), edition: "status"))
        XCTAssertTrue(UpdateLogic.isTrusted(URL(string: "https://objects.githubusercontent.com/a")!))
        XCTAssertTrue(!UpdateLogic.isTrusted(URL(string: "http://github.com/a")!))
        XCTAssertTrue(!UpdateLogic.isTrusted(URL(string: "https://github.com.evil.com/a")!))
    }

    func testChecksumFileParsing() {
        let hash = String(repeating: "a1", count: 32)
        let text = "\(hash)  macbookBatteryMonitor-v1.5.0-status-macOS-arm64.zip\n\(String(repeating: "b2", count: 32))  other.zip\n"
        XCTAssertEqual(UpdateLogic.checksum(in: text, for: "macbookBatteryMonitor-v1.5.0-status-macOS-arm64.zip"), hash)
        XCTAssertNil(UpdateLogic.checksum(in: text, for: "missing.zip"))
        XCTAssertNil(UpdateLogic.checksum(in: "zzzz  file.zip", for: "file.zip"))
    }
}
