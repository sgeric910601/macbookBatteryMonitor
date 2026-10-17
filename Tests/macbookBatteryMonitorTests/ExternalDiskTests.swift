import Foundation

final class ExternalDiskTests {
    private func traits(_ mount: String, node: String = "/dev/disk4s1", internal isInternal: Bool = false,
                        proto: String? = "USB") -> ExternalMountTraits {
        ExternalMountTraits(mountPoint: mount, deviceNode: node, isInternal: isInternal, protocolName: proto)
    }

    func testExternalDriveIsListed() {
        XCTAssertTrue(ExternalDisk.isExternal(traits("/Volumes/Backup")))
        XCTAssertTrue(ExternalDisk.isExternal(traits("/Volumes/SD", proto: "Secure Digital")))
        XCTAssertTrue(ExternalDisk.isExternal(traits("/Volumes/SSD", proto: nil)))
    }

    func testInternalSystemDiskImageAndNetworkAreExcluded() {
        XCTAssertTrue(!ExternalDisk.isExternal(traits("/", node: "/dev/disk3s1s1", internal: true, proto: "Apple Fabric")))
        XCTAssertTrue(!ExternalDisk.isExternal(traits("/System/Volumes/Data", node: "/dev/disk3s5", internal: true)))
        XCTAssertTrue(!ExternalDisk.isExternal(traits("/Volumes/Internal2", internal: true)))
        XCTAssertTrue(!ExternalDisk.isExternal(traits("/Volumes/Installer", proto: "Disk Image")))
        XCTAssertTrue(!ExternalDisk.isExternal(traits("/Volumes/share", node: "//user@server/share")))
        XCTAssertTrue(!ExternalDisk.isExternal(traits("/Volumes/NFS", node: "server:/export")))
    }

    func testUsedSpaceNeverUnderflows() {
        XCTAssertEqual(ExternalVolume(mountPoint: "/Volumes/A", name: "A", total: 100, available: 30).used, 70)
        XCTAssertEqual(ExternalVolume(mountPoint: "/Volumes/A", name: "A", total: 100, available: 130).used, 0)
    }

    func testDeviceNodeValidationAndHealthParsing() {
        XCTAssertTrue(ExternalDisk.isValidDeviceNode("/dev/disk5"))
        XCTAssertTrue(ExternalDisk.isValidDeviceNode("/dev/disk5s2"))
        XCTAssertTrue(ExternalDisk.isValidDeviceNode("/dev/disk12s1s3"))
        XCTAssertTrue(!ExternalDisk.isValidDeviceNode("/dev/disk"))
        XCTAssertTrue(!ExternalDisk.isValidDeviceNode("/dev/disk5s"))
        XCTAssertTrue(!ExternalDisk.isValidDeviceNode("/dev/disk5; rm -rf /"))
        XCTAssertTrue(!ExternalDisk.isValidDeviceNode("//server/share"))
        XCTAssertTrue(!ExternalDisk.isValidDeviceNode("/dev/rdisk5"))
        XCTAssertEqual(DiskHealth.parse("Verified"), .verified)
        XCTAssertEqual(DiskHealth.parse("Failing"), .failing)
        XCTAssertEqual(DiskHealth.parse("About to Fail"), .failing)
        XCTAssertEqual(DiskHealth.parse("Not Supported"), .unsupported)
        XCTAssertEqual(DiskHealth.parse(nil), .unsupported)
    }

    func testLifetimeParsing() {
        var log = [UInt8](repeating: 0, count: 512)
        log[3] = 100; log[4] = 99; log[5] = 3
        // 讀取 287,021,377 單位、寫入 212,659,173 單位（每單位 512,000 位元組）
        func put(_ value: UInt64, at offset: Int) { for i in 0..<8 { log[offset + i] = UInt8((value >> (8 * UInt64(i))) & 0xFF) } }
        put(287_021_377, at: 32)
        put(212_659_173, at: 48)
        put(2306, at: 128)
        let lifetime = DiskLifetime.parse(log)
        XCTAssertEqual(lifetime?.healthPercent, 97)
        XCTAssertEqual(lifetime?.bytesRead, 287_021_377 * 512_000)
        XCTAssertEqual(lifetime?.bytesWritten, 212_659_173 * 512_000)
        XCTAssertEqual(lifetime?.powerOnHours, 2306)
        XCTAssertEqual(lifetime?.isFailing, false)
        // 用超過設計壽命：健康度停在 0%
        log[5] = 140
        XCTAssertEqual(DiskLifetime.parse(log)?.healthPercent, 0)
        // 嚴重警告或備用區塊低於門檻都算異常
        log[5] = 3; log[0] = 0x04
        XCTAssertEqual(DiskLifetime.parse(log)?.isFailing, true)
        log[0] = 0; log[3] = 5; log[4] = 10
        XCTAssertEqual(DiskLifetime.parse(log)?.isFailing, true)
        // 128 位元計數器的高位不是 0，或乘上單位會溢位：用最大值，不會崩潰
        log[56] = 1
        XCTAssertEqual(DiskLifetime.parse(log)?.bytesWritten, .max)
        put(.max / 1000, at: 32)
        XCTAssertEqual(DiskLifetime.parse(log)?.bytesRead, .max)
        XCTAssertNil(DiskLifetime.parse([UInt8](repeating: 0, count: 100)))
    }

    func testNonASCIIDigitsAndLabelSanitizing() {
        XCTAssertTrue(!ExternalDisk.isValidDeviceNode("/dev/disk\u{0665}"))
        XCTAssertTrue(!ExternalDisk.isValidDeviceNode("/dev/disk5s\u{00B2}"))
        XCTAssertTrue(!ExternalDisk.isValidDeviceNode("/dev/disk" + String(repeating: "x", count: 3)))
        XCTAssertEqual(ExternalDisk.displayName("Photo\u{202E}_1T\u{0007}"), "Photo_1T")
        XCTAssertEqual(ExternalDisk.displayName("\u{202E}\u{0000}"), "外接磁碟")
        XCTAssertEqual(ExternalDisk.displayName(String(repeating: "a", count: 200)).count, 64)
    }
}
