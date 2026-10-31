import Foundation

final class StartupItemsTests {
    func testLabelAndPathValidation() {
        XCTAssertTrue(StartupItemLogic.isValidLabel("com.example.helper-1_a"))
        XCTAssertTrue(!StartupItemLogic.isValidLabel(""))
        XCTAssertTrue(!StartupItemLogic.isValidLabel("a b"))
        XCTAssertTrue(!StartupItemLogic.isValidLabel("a/b"))
        XCTAssertTrue(!StartupItemLogic.isValidLabel("a;b"))
        XCTAssertTrue(StartupItemLogic.isValidAppPath("/Applications/Example.app"))
        XCTAssertTrue(!StartupItemLogic.isValidAppPath("Example.app"))
        XCTAssertTrue(!StartupItemLogic.isValidAppPath("/Applications/Example.txt"))
        XCTAssertTrue(!StartupItemLogic.isValidAppPath("/Applications/../tmp/Example.app"))
        XCTAssertTrue(!StartupItemLogic.isValidAppPath("/Applications/Ex\nample.app"))
    }

    func testParseAgentPlist() {
        let plist: [String: Any] = ["Label": "com.example.sync", "ProgramArguments": ["/Applications/Example Sync.app/Contents/MacOS/sync", "--x"]]
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let item = StartupItemLogic.parseAgent(plist: data, fileName: "com.example.sync.plist", kind: .userAgent, disabledLabels: ["com.example.sync"])!
        XCTAssertEqual(item.name, "Example Sync")
        XCTAssertEqual(item.label, "com.example.sync")
        XCTAssertTrue(!item.enabled)
        XCTAssertTrue(item.canToggle)
        let apple = StartupItemLogic.parseAgent(plist: try! PropertyListSerialization.data(fromPropertyList: ["Label": "com.apple.x", "Program": "/usr/bin/x"], format: .xml, options: 0),
                                                fileName: "x.plist", kind: .userAgent, disabledLabels: [])!
        XCTAssertEqual(apple.name, "com.apple.x")
        XCTAssertTrue(!apple.canToggle)
        let system = StartupItemLogic.parseAgent(plist: data, fileName: "a.plist", kind: .systemDaemon, disabledLabels: [])!
        XCTAssertTrue(!system.canToggle)
        XCTAssertNil(StartupItemLogic.parseAgent(plist: Data("garbage".utf8), fileName: "a.plist", kind: .userAgent, disabledLabels: []))
        let bad = try! PropertyListSerialization.data(fromPropertyList: ["Label": "bad label;rm"], format: .xml, options: 0)
        XCTAssertNil(StartupItemLogic.parseAgent(plist: bad, fileName: "a.plist", kind: .userAgent, disabledLabels: []))
    }

    func testParseLoginItemsAndDisabled() {
        let items = StartupItemLogic.parseLoginItems("Alpha\t/Applications/Alpha.app\nBeta\t/Applications/Beta.app\n\nbroken\n")
        XCTAssertEqual(items.map(\.name), ["Alpha", "Beta"])
        XCTAssertTrue(items[0].canRemove)
        let disabled = StartupItemLogic.parseDisabled("disabled services = {\n\t\"com.example.a\" => disabled\n\t\"com.example.b\" => enabled\n\t\"com.example.c\" => true\n}")
        XCTAssertEqual(disabled, ["com.example.a", "com.example.c"])
    }
}

extension StartupItemsTests {
    func testIdentifiersStayUniqueForDuplicates() {
        let items = StartupItemLogic.parseLoginItems("Alpha\t/Applications/Alpha.app\nAlpha\t/Applications/Alpha.app\n")
        XCTAssertEqual(Set(items.map(\.id)).count, 2)
    }
}

extension StartupItemsTests {
    func testMissingProgramAndRemoval() {
        let plist: [String: Any] = ["Label": "com.example.gone", "ProgramArguments": ["/Applications/Gone.app/Contents/MacOS/gone"]]
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let gone = StartupItemLogic.parseAgent(plist: data, fileName: "com.example.gone.plist", kind: .systemAgent, disabledLabels: [],
                                               plistPath: "/Library/LaunchAgents/com.example.gone.plist", exists: { _ in false })!
        XCTAssertTrue(gone.missing)
        // Label 與檔名不一致：不給移除
        let spoof = StartupItemLogic.parseAgent(plist: data, fileName: "other.plist", kind: .systemAgent, disabledLabels: [],
                                                plistPath: "/Library/LaunchAgents/other.plist", exists: { _ in false })!
        XCTAssertTrue(!spoof.labelMatchesFile)
        XCTAssertTrue(!spoof.canRemove)
        XCTAssertTrue(gone.canRemove)
        XCTAssertEqual(gone.iconPath, "/Applications/Gone.app")
        let present = StartupItemLogic.parseAgent(plist: data, fileName: "x.plist", kind: .systemAgent, disabledLabels: [],
                                                  plistPath: "/Library/LaunchAgents/com.example.gone.plist", exists: { _ in true })!
        XCTAssertTrue(!present.missing)
        XCTAssertTrue(!present.canRemove)
        let home = "/Users/example"
        XCTAssertTrue(StartupItemLogic.isRemovablePlistPath("/Library/LaunchDaemons/a.plist", home: home))
        XCTAssertTrue(StartupItemLogic.isRemovablePlistPath("/Users/example/Library/LaunchAgents/a.plist", home: home))
        XCTAssertTrue(!StartupItemLogic.isRemovablePlistPath("/Library/LaunchDaemons/../../etc/a.plist", home: home))
        XCTAssertTrue(!StartupItemLogic.isRemovablePlistPath("/Library/LaunchDaemons/sub/a.plist", home: home))
        XCTAssertTrue(!StartupItemLogic.isRemovablePlistPath("/etc/a.plist", home: home))
        XCTAssertTrue(!StartupItemLogic.isRemovablePlistPath("/Library/LaunchDaemons/a.txt", home: home))
    }
}

extension StartupItemsTests {
    func testOpenLauncherTargetsTheApp() {
        let plist: [String: Any] = ["Label": "com.example.drive", "ProgramArguments": ["/usr/bin/open", "-a", "/Applications/Gone Drive.app"]]
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let item = StartupItemLogic.parseAgent(plist: data, fileName: "com.example.drive.plist", kind: .userAgent, disabledLabels: [],
                                               plistPath: "/Users/example/Library/LaunchAgents/com.example.drive.plist",
                                               exists: { $0 == "/usr/bin/open" })!
        XCTAssertEqual(item.name, "Gone Drive")
        XCTAssertTrue(item.missing)
        XCTAssertTrue(item.canRemove)
        XCTAssertEqual(StartupItemLogic.realTarget(program: nil, arguments: ["/usr/bin/open", "https://example.com"]), "/usr/bin/open")
    }
}

extension StartupItemsTests {
    func testItemInfoMatching() {
        XCTAssertEqual(StartupItemInfoLogic.bundleID(fromRequirement: "identifier \"com.example.Cleaner\" and anchor apple generic"), "com.example.Cleaner")
        XCTAssertNil(StartupItemInfoLogic.bundleID(fromRequirement: "anchor apple"))
        XCTAssertNil(StartupItemInfoLogic.bundleID(fromRequirement: "identifier \"bad id;x\" and x"))
        XCTAssertEqual(StartupItemInfoLogic.vendorHint(label: "com.example.Tool.helper"), "example")
        XCTAssertNil(StartupItemInfoLogic.vendorHint(label: "helper"))
        XCTAssertEqual(StartupItemInfoLogic.guessedIDs(label: "com.example.Tool.helper"), ["com.example.Tool.helper", "com.example.Tool"])
        XCTAssertEqual(StartupItemInfoLogic.guessedIDs(label: "com.example.Tool"), ["com.example.Tool"])
        let ids = ["com.example.Tool"]
        XCTAssertTrue(StartupItemInfoLogic.matches(fileName: "com.example.Tool.plist", ids: ids))
        XCTAssertTrue(StartupItemInfoLogic.matches(fileName: "com.example.Tool.helper.plist", ids: ids))
        XCTAssertTrue(!StartupItemInfoLogic.matches(fileName: "com.example.ToolBox.plist", ids: ids))
        XCTAssertTrue(!StartupItemInfoLogic.matches(fileName: "com.other.Tool.plist", ids: ids))
        XCTAssertTrue(StartupItemInfoLogic.matchesVendor(fileName: "Example", vendor: "example"))
        XCTAssertTrue(!StartupItemInfoLogic.matchesVendor(fileName: "Examples", vendor: "example"))
        XCTAssertTrue(!StartupItemInfoLogic.matchesVendor(fileName: "ab", vendor: "ab"))
        XCTAssertTrue(!StartupItemInfoLogic.shouldScan(label: "com.apple.x"))
        XCTAssertEqual(StartupItemInfoLogic.containerBundlePath(of: "/usr/local/libexec/Helper.xpc/Contents/MacOS/Helper"), "/usr/local/libexec/Helper.xpc")
        XCTAssertNil(StartupItemInfoLogic.containerBundlePath(of: "/usr/bin/true"))
    }
}

extension StartupItemsTests {
    func testInferredAppsAndSearchURL() {
        let paths = ["/Library/LaunchDaemons/com.example.Tool.helper.plist",
                     "/Users/example/Library/Preferences/com.example.Tool.App.plist",
                     "/Users/example/Library/Containers/com.example.Tool.Widget",
                     "/Users/example/Library/Application Support/Example",
                     "/usr/local/libexec/Helper.xpc"]
        XCTAssertEqual(StartupItemInfoLogic.inferredAppIDs(fromPaths: paths, excluding: "com.example.Tool.helper"),
                       ["com.example.Tool.App", "com.example.Tool.Widget"])
        XCTAssertEqual(StartupItemInfoLogic.searchURL(for: "org.example.helper")?.absoluteString, "https://duckduckgo.com/?q=org.example.helper")
        XCTAssertNil(StartupItemInfoLogic.searchURL(for: "bad label&x=1"))
    }
}

extension StartupItemsTests {
    func testFriendlyAppNames() {
        XCTAssertEqual(StartupItemInfoLogic.friendlyName(fromIdentifier: "com.example.Tool.App"), "Tool")
        XCTAssertEqual(StartupItemInfoLogic.friendlyName(fromIdentifier: "com.example.CleanerPro.PrivilegedHelperTool"), "CleanerPro")
        XCTAssertEqual(StartupItemInfoLogic.friendlyName(fromIdentifier: "org.example.Tool"), "Tool")
        XCTAssertEqual(StartupItemInfoLogic.friendlyName(fromIdentifier: "Tool"), "Tool")
        XCTAssertEqual(StartupItemInfoLogic.friendlyName(fromIdentifier: "com.example.helper"), "helper")
    }
}
