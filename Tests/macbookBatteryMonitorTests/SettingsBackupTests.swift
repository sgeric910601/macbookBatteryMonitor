import Foundation

struct SettingsBackupTests {
    private let schema: [String: SettingsBackup.Kind] = [
        "flag": .bool, "count": .int, "scale": .double, "name": .string,
        "items": .strings, "limits": .intMap, "nested": .dictionary,
    ]

    private func file(_ settings: [String: Any], format: String = SettingsBackup.format, version: Int = SettingsBackup.version) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: ["format": format, "version": version, "settings": settings],
                                            format: .xml, options: 0)
    }

    /// 匯出再匯入：值與型別都一樣；不在清單裡的設定不會匯出
    func testRoundTrip() {
        let values: [String: Any] = ["flag": true, "count": 3, "scale": 1.25, "name": "mint", "items": ["a", "b"],
                                     "limits": ["mouse": 20], "nested": ["vimKeys": false], "secret": "x"]
        let data = try! SettingsBackup.export(values, schema: schema)
        let back = try! SettingsBackup.read(data, schema: schema)
        XCTAssertEqual(Set(back.keys), Set(schema.keys))
        XCTAssertEqual(back["flag"] as? Bool, true)
        XCTAssertEqual(back["count"] as? Int, 3)
        XCTAssertEqual(back["scale"] as? Double, 1.25)
        XCTAssertEqual(back["items"] as? [String], ["a", "b"])
        XCTAssertEqual(back["limits"] as? [String: Int], ["mouse": 20])
        XCTAssertNil(back["secret"])
    }

    /// 型別不對、不認得的設定都略過，其他照常匯入
    func testSkipsWrongTypesAndUnknownKeys() {
        let back = try! SettingsBackup.read(file(["flag": 1, "count": true, "scale": "big", "name": 5, "items": ["a", 2],
                                                  "limits": ["mouse": "low"], "nested": [1], "unknown": true, "other": "y"]),
                                            schema: schema)
        XCTAssertTrue(back.isEmpty)
        // 整數當小數可以；小數當整數不行
        let numbers = try! SettingsBackup.read(file(["scale": 2, "count": 2.5]), schema: schema)
        XCTAssertEqual(numbers["scale"] as? Double, 2)
        XCTAssertNil(numbers["count"])
        // NaN、無限大會讓用到的地方當掉，不收
        let nan = Data("""
            <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>format</key><string>\(SettingsBackup.format)</string>
            <key>version</key><integer>1</integer><key>settings</key><dict><key>scale</key><real>nan</real></dict></dict></plist>
            """.utf8)
        XCTAssertTrue(try! SettingsBackup.read(nan, schema: schema).isEmpty)
        XCTAssertTrue(try! SettingsBackup.read(file(["scale": Double.infinity]), schema: schema).isEmpty)
    }

    /// 不是這個 App 的檔案、比較新的版本、太大或壞掉的檔案：整份拒絕
    func testRejectsForeignOrBrokenFiles() {
        func error(_ data: Data) -> SettingsBackup.ReadError? {
            do { _ = try SettingsBackup.read(data, schema: schema); return nil } catch { return error as? SettingsBackup.ReadError }
        }
        XCTAssertEqual(error(file(["flag": true], format: "something-else")), .notOurs)
        XCTAssertEqual(error(file(["flag": true], version: SettingsBackup.version + 1)), .newerVersion)
        XCTAssertEqual(error(Data("not a plist".utf8)), .unreadable)
        XCTAssertEqual(error(Data(count: SettingsBackup.maxSize + 1)), .tooLarge)
    }
}
