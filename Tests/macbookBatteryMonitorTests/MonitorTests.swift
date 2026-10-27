import Foundation

final class MonitorTests {
    func testMemoryDiskMergeNeedsBothModules() {
        XCTAssertTrue(MonitorKind.mergesMemoryDisk(merge: true, memory: true, disk: true))
        XCTAssertTrue(!MonitorKind.mergesMemoryDisk(merge: true, memory: true, disk: false))
        XCTAssertTrue(!MonitorKind.mergesMemoryDisk(merge: true, memory: false, disk: true))
        XCTAssertTrue(!MonitorKind.mergesMemoryDisk(merge: false, memory: true, disk: true))
    }

    func testMergedMemoryDiskDropsDiskIcon() {
        let all = MonitorKind.allCases
        XCTAssertEqual(MonitorKind.shown(all, memoryDiskMerged: false), all)
        XCTAssertEqual(MonitorKind.shown(all, memoryDiskMerged: true), [.cpu, .memory, .network])
    }

    func testCPUUsageFromTickDeltas() {
        let old = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let new = CPUTicks(user: 160, system: 70, idle: 1070, nice: 0)
        let usage = CPUMath.usage(from: old, to: new)!
        XCTAssertTrue(abs(usage.user - 0.2) < 1e-9)
        XCTAssertTrue(abs(usage.system - 0.0666667) < 1e-6)
        XCTAssertTrue(abs(usage.total - 0.2666667) < 1e-6)
    }

    func testCPUCounterWrapReturnsNil() {
        let old = CPUTicks(user: 4_000_000_000, system: 10, idle: 10, nice: 0)
        let new = CPUTicks(user: 5, system: 20, idle: 20, nice: 0)
        XCTAssertNil(CPUMath.usage(from: old, to: new))
    }

    func testPerCoreAndTotal() {
        let old = [CPUTicks(user: 0, system: 0, idle: 0, nice: 0), CPUTicks(user: 0, system: 0, idle: 0, nice: 0)]
        let new = [CPUTicks(user: 100, system: 0, idle: 0, nice: 0), CPUTicks(user: 0, system: 0, idle: 100, nice: 0)]
        let result = CPUMath.usages(from: old, to: new)!
        XCTAssertEqual(result.cores.map(\.total), [1, 0])
        XCTAssertEqual(result.total.total, 0.5)
    }

    func testMemoryCategoriesMatchActivityMonitor() {
        let usage = MemoryMath.usage(pageSize: 16384, internalPages: 200_000, purgeablePages: 10_000, wiredPages: 80_000,
                                     compressedPages: 140_000, externalPages: 90_000, total: 8 * 1024 * 1024 * 1024,
                                     swapUsed: 0, swapTotal: 0, pressure: .normal)
        XCTAssertEqual(usage.app, 190_000 * 16384)
        XCTAssertEqual(usage.cached, 100_000 * 16384)
        XCTAssertEqual(usage.used, (190_000 + 80_000 + 140_000) * 16384)
        XCTAssertEqual(usage.free, 8 * 1024 * 1024 * 1024 - usage.used - usage.cached)
    }

    func testRateHandlesResetAndInterval() {
        XCTAssertEqual(RateMath.perSecond(old: 1000, new: 3000, interval: 2), 1000)
        XCTAssertEqual(RateMath.perSecond(old: 3000, new: 1000, interval: 1), 0)
        XCTAssertEqual(RateMath.perSecond(old: 0, new: 1000, interval: 0), 0)
    }

    func testByteFormats() {
        XCTAssertEqual(ByteFormat.size(494_384_795_648), "494 GB")
        XCTAssertEqual(ByteFormat.memory(5_952_618_496), "5.5 GB")
        XCTAssertEqual(ByteFormat.rate(1_234_000), "1.2 MB/s")
        XCTAssertEqual(ByteFormat.compactRate(0), "0K")
        XCTAssertEqual(ByteFormat.compactRate(340_000), "340K")
        XCTAssertEqual(ByteFormat.compactRate(1_234_000), "1.2M")
        XCTAssertEqual(ByteFormat.compactRate(25_000_000), "25M")
        XCTAssertEqual(ByteFormat.percent(0.195), "20%")
    }

    func testTopParsing() {
        let text = """
        Processes: 566 total, 3 running
        Load Avg: 2.18, 2.39, 2.49

        PID    COMMAND          %CPU
        407    WindowServer     43.6
        13286  Safari Web Conten 12.3
        """
        let rows = TopParse.rows(text)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1], TopParse.Row(pid: 13286, command: "Safari Web Conten", value: "12.3"))
        XCTAssertEqual(TopParse.memoryBytes("523M"), 523 * 1024 * 1024)
        XCTAssertEqual(TopParse.memoryBytes("1024K+"), 1024 * 1024)
        XCTAssertEqual(TopParse.memoryBytes("2G-"), 2 * 1024 * 1024 * 1024)
    }

    func testHistoryKeepsLastPoints() {
        var history = MonitorHistory()
        for i in 0..<(MonitorHistory.capacity + 30) { history.append(Double(i)) }
        XCTAssertEqual(history.points.count, MonitorHistory.capacity)
        XCTAssertEqual(history.points.first?.a, 30)
    }

    func testHistoryKeepsTwoMinutesInPowerSaving() {
        // 省電模式每 2 秒一點：只保留最近 2 分鐘，圖表的「最近 2 分鐘」才正確
        let start = Date(timeIntervalSince1970: 1_000_000)
        var history = MonitorHistory()
        for i in 0..<100 { history.append(Double(i), at: start.addingTimeInterval(Double(i) * 2)) }
        XCTAssertEqual(history.points.count, 61)
        XCTAssertEqual(history.points.first?.a, 39)
        // 每秒一點時仍以 120 個為上限
        var everySecond = MonitorHistory()
        for i in 0..<200 { everySecond.append(Double(i), at: start.addingTimeInterval(Double(i))) }
        XCTAssertEqual(everySecond.points.count, MonitorHistory.capacity)
    }
}

extension MonitorTests {
    func testSpeedTestParsing() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let json = """
        {"dl_throughput": 52000000, "ul_throughput": 8400000, "responsiveness": 612.5, "base_rtt": 18.25,
         "interface_name": "en9", "il_h2_req_resp": [20, 21], "other": {}}
        """
        let result = SpeedTestResult.parse(Data(json.utf8), at: date)
        XCTAssertEqual(result, SpeedTestResult(download: 52_000_000, upload: 8_400_000, responsiveness: 612.5,
                                               idleLatency: 18.25, date: date))
        // 只測下載、欄位型別錯誤或負值：該欄留空，不當掉
        let partial = SpeedTestResult.parse(Data(#"{"dl_throughput": 1000000, "ul_throughput": "x", "base_rtt": -1}"#.utf8), at: date)
        XCTAssertEqual(partial, SpeedTestResult(download: 1_000_000, upload: nil, responsiveness: nil, idleLatency: nil, date: date))
        // 失敗時的輸出、非 JSON、空資料
        XCTAssertNil(SpeedTestResult.parse(Data(#"{"error_code": -1009, "error_domain": "NSURLErrorDomain"}"#.utf8), at: date))
        // 上傳的連線全部逾時時 networkQuality 仍回報 0：當作沒測到，不是 0 Mbps
        let timedOut = SpeedTestResult.parse(Data(#"{"dl_throughput": 81088184, "ul_throughput": 0, "error_code": -1001}"#.utf8), at: date)
        XCTAssertEqual(timedOut?.download, 81_088_184)
        XCTAssertNil(timedOut?.upload)
        XCTAssertEqual(timedOut?.missingPart, "上傳")
        XCTAssertNil(SpeedTestResult.parse(Data(#"{"dl_throughput": 0, "ul_throughput": 0}"#.utf8), at: date))
        XCTAssertNil(result?.missingPart)
        XCTAssertNil(SpeedTestResult.parse(Data("Downlink: 50 Mbps".utf8), at: date))
        XCTAssertNil(SpeedTestResult.parse(Data(), at: date))
        XCTAssertNil(SpeedTestResult.parse(Data("[1, 2]".utf8), at: date))
    }

    /// macOS 12 的 networkQuality 沒有 -M，輸出也沒有閒置延遲（base_rtt）
    func testSpeedTestOnOlderSystems() {
        let monterey = """
        USAGE: networkQuality [-C <configuration_url>] [-c] [-h] [-I <interfaceName>] [-s] [-v]
            -C: override Configuration URL
            -c: Produce computer-readable output
            -h: Show help (this message)
            -I: Bind test to interface (e.g., en0, pdp_ip0,...)
            -s: Run tests sequentially instead of parallel upload/download
            -v: Verbose output
        """
        let current = """
            -k: Disable certificate validation
            -M: Provide maximum runtime in seconds
            -p: Use iCloud Private Relay
        """
        XCTAssertEqual(SpeedTestResult.arguments(help: monterey, maxRuntime: 30), ["-c"])
        XCTAssertEqual(SpeedTestResult.arguments(help: current, maxRuntime: 30), ["-c", "-M", "30"])
        XCTAssertEqual(SpeedTestResult.arguments(help: "", maxRuntime: 30), ["-c"])

        let date = Date(timeIntervalSince1970: 1_000_000)
        let json = """
        {"dl_flows": 12, "dl_throughput": 507593504, "lud_foreign_h2_req_resp": [74, 67], "lud_self_dl_h2": [58.5, 26.1],
         "responsiveness": 1075, "ul_flows": 20, "ul_throughput": 68901384}
        """
        XCTAssertEqual(SpeedTestResult.parse(Data(json.utf8), at: date),
                       SpeedTestResult(download: 507_593_504, upload: 68_901_384, responsiveness: 1075, idleLatency: nil, date: date))
    }

    func testBitRateFormat() {
        XCTAssertEqual(SpeedTestResult.bitRate(0), "0 Mbps")
        XCTAssertEqual(SpeedTestResult.bitRate(-5), "0 Mbps")
        XCTAssertEqual(SpeedTestResult.bitRate(850_000), "850 Kbps")
        XCTAssertEqual(SpeedTestResult.bitRate(999_700), "1.0 Mbps")
        XCTAssertEqual(SpeedTestResult.bitRate(17_221_336), "17.2 Mbps")
        XCTAssertEqual(SpeedTestResult.bitRate(345_600_000), "346 Mbps")
        XCTAssertEqual(SpeedTestResult.bitRate(1_234_000_000), "1.2 Gbps")
    }
}
