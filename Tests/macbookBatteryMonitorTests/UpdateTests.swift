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

    func testBetaVersionsAndChannel() {
        XCTAssertEqual(AppVersion("v1.7.0-beta.1"), AppVersion(numbers: [1, 7, 0], beta: 1))
        XCTAssertEqual(AppVersion("1.7.0-beta.12")?.text, "1.7.0 beta 12")
        XCTAssertEqual(AppVersion("v1.6.3")?.text, "1.6.3")
        XCTAssertNil(AppVersion("v1.7.0-rc.1"))
        XCTAssertNil(AppVersion("v1.7.0-beta"))
        XCTAssertNil(AppVersion("v1.7.0-beta.0"))
        XCTAssertNil(AppVersion("v1.7.0-"))
        // 1.6.3 < 1.7.0 beta 1 < 1.7.0 beta 2 < 1.7.0 < 1.7.1 beta 1
        let order = ["v1.6.3", "v1.7.0-beta.1", "v1.7.0-beta.2", "v1.7.0", "v1.7.1-beta.1"].compactMap(AppVersion.init)
        XCTAssertEqual(order.count, 5)
        for (lower, higher) in zip(order, order.dropFirst()) {
            XCTAssertTrue(lower < higher)
            XCTAssertTrue(!(higher < lower))
        }
        XCTAssertEqual(AppVersion.current(info: ["CFBundleShortVersionString": "1.7.0", "MBMPrerelease": "beta.1"]),
                       AppVersion(numbers: [1, 7, 0], beta: 1))
        XCTAssertEqual(AppVersion.current(info: ["CFBundleShortVersionString": "1.6.3"]), AppVersion(numbers: [1, 6, 3]))

        func entry(_ tag: String, prerelease: Bool) -> String {
            """
            {"tag_name":"\(tag)","html_url":"https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/\(tag)",
             "draft":false,"prerelease":\(prerelease),"assets":[
              {"name":"macbookBatteryMonitor-\(tag)-macOS-universal.zip","size":1,
               "browser_download_url":"https://github.com/sgeric910601/macbookBatteryMonitor/releases/download/\(tag)/macbookBatteryMonitor-\(tag)-macOS-universal.zip"}]}
            """
        }
        func list(_ entries: [String]) -> [ReleaseInfo] {
            UpdateLogic.releases(json: Data("[\(entries.joined(separator: ","))]".utf8), edition: "universal")
        }
        // 預先發行一定要帶 Beta 序號、正式版不能帶，不符的略過
        let parsed = list([entry("v1.7.0-beta.1", prerelease: true), entry("v1.6.3", prerelease: false),
                           entry("v1.8.0", prerelease: true), entry("v1.9.0-beta.1", prerelease: false)])
        XCTAssertEqual(parsed.map(\.tag), ["v1.7.0-beta.1", "v1.6.3"])
        XCTAssertEqual(parsed.first?.beta, 1)
        XCTAssertEqual(parsed.first?.versionText, "1.7.0 beta 1")
        // 單一 Release 的解析（舊的 releases/latest）不接受 Beta
        XCTAssertNil(UpdateLogic.release(json: Data(entry("v1.7.0-beta.1", prerelease: true).utf8), edition: "universal"))

        let releases = list([entry("v1.7.0-beta.2", prerelease: true), entry("v1.7.0-beta.1", prerelease: true),
                             entry("v1.6.3", prerelease: false), entry("v1.6.2", prerelease: false)])
        // 正式版使用者：有比目前新的正式版就用正式版；Beta 另外列出（是否顯示由手動檢查決定）
        var found = UpdateLogic.choose(releases, current: AppVersion(numbers: [1, 6, 2]))
        XCTAssertEqual(found.stable?.tag, "v1.6.3")
        XCTAssertEqual(found.beta?.tag, "v1.7.0-beta.2")
        found = UpdateLogic.choose(releases, current: AppVersion(numbers: [1, 6, 3]))
        XCTAssertNil(found.stable)
        XCTAssertEqual(found.beta?.tag, "v1.7.0-beta.2")
        // Beta 使用者：下一個 Beta、以及同版本號的正式版都算新版本
        found = UpdateLogic.choose(releases, current: AppVersion(numbers: [1, 7, 0], beta: 1))
        XCTAssertNil(found.stable)
        XCTAssertEqual(found.beta?.tag, "v1.7.0-beta.2")
        let final = list([entry("v1.7.0", prerelease: false), entry("v1.7.0-beta.2", prerelease: true)])
        found = UpdateLogic.choose(final, current: AppVersion(numbers: [1, 7, 0], beta: 2))
        XCTAssertEqual(found.stable?.tag, "v1.7.0")
        XCTAssertNil(found.beta)
        // 比最新正式版舊的 Beta 不列出
        found = UpdateLogic.choose(final, current: AppVersion(numbers: [1, 6, 3]))
        XCTAssertEqual(found.stable?.tag, "v1.7.0")
        XCTAssertNil(found.beta)
        found = UpdateLogic.choose(final, current: AppVersion(numbers: [1, 7, 0]))
        XCTAssertNil(found.stable)
        XCTAssertNil(found.beta)
    }

    /// 舊系統版本的 Release 清單：macOS 12、13 只找 macOS12 檔，沒有附 macOS12 檔的版本（包含 Beta）不列出；
    /// 系統已升級到 macOS 14 以上時改裝主版本的通用版
    func testLegacyReleaseList() {
        func entry(_ tag: String, prerelease: Bool, legacy: Bool) -> String {
            let base = "https://github.com/sgeric910601/macbookBatteryMonitor/releases/download/\(tag)/"
            var assets = ["{\"name\":\"macbookBatteryMonitor-\(tag)-macOS-universal.zip\",\"size\":1,"
                          + "\"browser_download_url\":\"\(base)macbookBatteryMonitor-\(tag)-macOS-universal.zip\"}"]
            if legacy {
                assets.append("{\"name\":\"macbookBatteryMonitor-\(tag)-macOS12.zip\",\"size\":2,"
                              + "\"browser_download_url\":\"\(base)macbookBatteryMonitor-\(tag)-macOS12.zip\"}")
            }
            return """
            {"tag_name":"\(tag)","html_url":"https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/\(tag)",
             "draft":false,"prerelease":\(prerelease),"assets":[\(assets.joined(separator: ","))]}
            """
        }
        let entries = [entry("v1.7.1-beta.1", prerelease: true, legacy: false), entry("v1.7.0-beta.1", prerelease: true, legacy: true),
                       entry("v1.6.3", prerelease: false, legacy: true)]
        let json = Data("[\(entries.joined(separator: ","))]".utf8)
        // macOS 12、13：只有附 macOS12 檔的版本
        let old = UpdateLogic.releases(json: json, edition: "legacy", mainSupported: false)
        XCTAssertEqual(old.map(\.tag), ["v1.7.0-beta.1", "v1.6.3"])
        XCTAssertEqual(old.map(\.assetName), ["macbookBatteryMonitor-v1.7.0-beta.1-macOS12.zip", "macbookBatteryMonitor-v1.6.3-macOS12.zip"])
        var found = UpdateLogic.choose(old, current: AppVersion(numbers: [1, 6, 3]))
        XCTAssertNil(found.stable)
        XCTAssertEqual(found.beta?.tag, "v1.7.0-beta.1")
        XCTAssertEqual(found.beta?.assetSize, 2)
        // 已升級到 macOS 14 以上：全部改用通用版，只有通用版的 Beta 也列出
        let upgraded = UpdateLogic.releases(json: json, edition: "legacy", mainSupported: true)
        XCTAssertEqual(upgraded.map(\.assetSize), [1, 1, 1])
        found = UpdateLogic.choose(upgraded, current: AppVersion(numbers: [1, 7, 0], beta: 1))
        XCTAssertNil(found.stable)
        XCTAssertEqual(found.beta?.assetName, "macbookBatteryMonitor-v1.7.1-beta.1-macOS-universal.zip")
        // 單一 Release（releases/latest）的解析同樣只接受正式版
        XCTAssertEqual(UpdateLogic.release(json: Data(entries[2].utf8), edition: "legacy", mainSupported: false)?.assetSize, 2)
        XCTAssertNil(UpdateLogic.release(json: Data(entries[1].utf8), edition: "legacy", mainSupported: false))
    }
}
