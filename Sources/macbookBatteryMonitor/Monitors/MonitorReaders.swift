import Darwin
import DiskArbitration
import Foundation
import IOKit
import SystemConfiguration

/// 系統資料讀取；都是公開的系統介面，不需要管理員權限
enum CPUReader {
    private static let host = mach_host_self()

    /// 節能核心與效能核心數。Apple Silicon 上核心編號由節能核心開始
    static let coreLayout: (efficiency: Int, performance: Int) = {
        func value(_ name: String) -> Int {
            var v: Int32 = 0
            var size = MemoryLayout<Int32>.size
            return sysctlbyname(name, &v, &size, nil, 0) == 0 ? Int(v) : 0
        }
        let performance = value("hw.perflevel0.logicalcpu")
        let efficiency = value("hw.perflevel1.logicalcpu")
        return (efficiency, performance)
    }()

    static func ticks() -> [CPUTicks]? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(count)).map { i in
            func tick(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[i * stride + Int(state)])) }
            return CPUTicks(user: tick(CPU_STATE_USER), system: tick(CPU_STATE_SYSTEM),
                            idle: tick(CPU_STATE_IDLE), nice: tick(CPU_STATE_NICE))
        }
    }

    static func loadAverage() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) == 3 ? loads : []
    }
}

enum GPUReader {
    /// 使用率（0～1）與 GPU 佔用的記憶體
    static func read() -> (utilization: Double?, memory: UInt64?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator"))
        guard service != IO_OBJECT_NULL else { return (nil, nil) }
        defer { IOObjectRelease(service) }
        guard let performance = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] else { return (nil, nil) }
        let utilization = (performance["Device Utilization %"] as? NSNumber).map { min(1, max(0, $0.doubleValue / 100)) }
        // Apple 晶片是 "In use system memory"，Intel 內顯是 inUseSysMemoryBytes；
        // Intel 負載時偶爾會讀到負數被當成極大值（實測 2⁶⁴ − 1.7 億），超過實體記憶體就當成讀不到
        let raw = (performance["In use system memory"] ?? performance["inUseSysMemoryBytes"]) as? NSNumber
        let memory = raw.map { $0.uint64Value }.flatMap { $0 <= ProcessInfo.processInfo.physicalMemory ? $0 : nil }
        return (utilization, memory)
    }
}

enum MemoryReader {
    private static let host = mach_host_self()

    private static let total: UInt64 = {
        var v: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        return sysctlbyname("hw.memsize", &v, &size, nil, 0) == 0 ? v : 0
    }()

    static func read() -> MemoryUsage? {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) != 0 { swap = xsw_usage() }

        var level: Int32 = 1
        var levelSize = MemoryLayout<Int32>.size
        _ = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0)

        return MemoryMath.usage(
            pageSize: UInt64(vm_kernel_page_size),
            internalPages: UInt64(vm.internal_page_count), purgeablePages: UInt64(vm.purgeable_count),
            wiredPages: UInt64(vm.wire_count), compressedPages: UInt64(vm.compressor_page_count),
            externalPages: UInt64(vm.external_page_count), total: total,
            swapUsed: swap.xsu_used, swapTotal: swap.xsu_total,
            pressure: MemoryPressure(rawValue: Int(level)) ?? .normal
        )
    }
}

enum DiskReader {
    struct Volume: Equatable {
        var name: String
        var total: UInt64
        var available: UInt64
        var used: UInt64 { total > available ? total - available : 0 }
        /// 例如 /dev/disk3s3s1，用來對應 IOKit 的讀寫統計與 SMART
        var deviceNode: String = ""
        var fileSystem: String = ""
        var connection: String = ""
    }

    /// 開機磁碟的裝置協定（"Apple Fabric"…）；只問一次 DiskArbitration。只在主執行緒讀寫
    private static var startupConnection: (node: String, protocolName: String)?

    private static func connection(forDevice node: String) -> String {
        if let cached = startupConnection, cached.node == node { return cached.protocolName }
        var name = ""
        if let arbitration, let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, arbitration, node),
           let info = DADiskCopyDescription(disk) as? [String: Any] {
            name = (info[kDADiskDescriptionDeviceProtocolKey as String] as? String) ?? ""
        }
        startupConnection = (node, name)
        return name
    }

    /// 系統可清出的空間（快取、可清除檔案）與磁碟名稱；查一次要十幾毫秒（有時更久），變化又慢，
    /// 每 5 分鐘在背景校正一次。這兩個變數只在主執行緒讀寫
    private static var purgeable: (bytes: UInt64, name: String, date: Date)?
    private static var calibrating = false

    /// 開機磁碟的容量；「可用」包含系統可以清出的空間，與 Finder 一致。
    /// 每秒用 statfs()（只需幾微秒）讀實際剩餘空間，再加上定期校正的可清出空間
    static func startupVolume() -> Volume? {
        var fs = statfs()
        guard statfs("/", &fs) == 0 else { return nil }
        let blockSize = UInt64(fs.f_bsize)
        let total = UInt64(fs.f_blocks) * blockSize
        let free = UInt64(fs.f_bavail) * blockSize
        if !calibrating, purgeable.map({ Date().timeIntervalSince($0.date) > 300 }) ?? true {
            calibrating = true
            let previousName = purgeable?.name
            DispatchQueue.global(qos: .utility).async {
                let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey, .volumeAvailableCapacityForImportantUsageKey])
                var now = statfs()
                let freeNow = statfs("/", &now) == 0 ? UInt64(now.f_bavail) * UInt64(now.f_bsize) : free
                let important = values?.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) } ?? freeNow
                let result = (important > freeNow ? important - freeNow : 0, values?.volumeName ?? previousName ?? "Macintosh HD", Date())
                DispatchQueue.main.async {
                    purgeable = result
                    calibrating = false
                }
            }
        }
        let extra = purgeable?.bytes ?? 0
        let deviceNode = withUnsafePointer(to: &fs.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        let fileSystem = withUnsafePointer(to: &fs.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
        }
        return Volume(name: purgeable?.name ?? "Macintosh HD", total: total, available: min(total, free + extra),
                      deviceNode: deviceNode, fileSystem: fileSystem,
                      connection: ExternalDisk.isValidDeviceNode(deviceNode) ? connection(forDevice: String(deviceNode.dropFirst("/dev/".count))) : "")
    }

    private static let arbitration = DASessionCreate(kCFAllocatorDefault)
    /// 掛載項目 → 是否為外接磁碟；同一個掛載只問一次 DiskArbitration。只在主執行緒讀寫
    private static var externalCache: [String: (isExternal: Bool, connection: String)] = [:]

    private static func externalMount(mountPoint: String, deviceNode: String) -> (isExternal: Bool, connection: String) {
        let key = mountPoint + "|" + deviceNode
        if let cached = externalCache[key] { return cached }
        var traits = ExternalMountTraits(mountPoint: mountPoint, deviceNode: deviceNode, isInternal: true, protocolName: nil)
        if let arbitration, ExternalDisk.isValidDeviceNode(deviceNode),
           let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, arbitration, String(deviceNode.dropFirst("/dev/".count))),
           let info = DADiskCopyDescription(disk) as? [String: Any] {
            traits.isInternal = (info[kDADiskDescriptionDeviceInternalKey as String] as? Bool) ?? true
            traits.protocolName = info[kDADiskDescriptionDeviceProtocolKey as String] as? String
        }
        let result = (ExternalDisk.isExternal(traits), traits.protocolName ?? "")
        externalCache[key] = result
        return result
    }

    /// 目前掛載的外接磁碟與容量。用 getfsstat(MNT_NOWAIT) 讀核心已有的資料，不會被離線的網路磁碟卡住
    static func externalVolumes() -> [ExternalVolume] {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return [] }
        var buffer = Array(repeating: Darwin.statfs(), count: Int(count))
        let size = Int32(buffer.count * MemoryLayout<statfs>.stride)
        let filled = getfsstat(&buffer, size, MNT_NOWAIT)
        guard filled > 0 else { return [] }
        var volumes: [ExternalVolume] = []
        var liveKeys: Set<String> = []
        for var fs in buffer.prefix(Int(filled)) {
            let mountPoint = withUnsafePointer(to: &fs.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            let deviceNode = withUnsafePointer(to: &fs.f_mntfromname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            guard mountPoint.hasPrefix("/Volumes/") else { continue }
            liveKeys.insert(mountPoint + "|" + deviceNode)
            let mount = externalMount(mountPoint: mountPoint, deviceNode: deviceNode)
            guard mount.isExternal else { continue }
            let fileSystem = withUnsafePointer(to: &fs.f_fstypename) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
            }
            // 第三方檔案系統驅動可能回報任意值，乘法溢位時略過這顆磁碟，不能讓 App 崩潰
            let blockSize = UInt64(fs.f_bsize)
            let (total, totalOverflow) = UInt64(fs.f_blocks).multipliedReportingOverflow(by: blockSize)
            let (free, freeOverflow) = UInt64(fs.f_bavail).multipliedReportingOverflow(by: blockSize)
            guard !totalOverflow, !freeOverflow, total > 0 else { continue }
            volumes.append(ExternalVolume(mountPoint: mountPoint,
                                          name: ExternalDisk.displayName((mountPoint as NSString).lastPathComponent),
                                          total: total, available: min(total, free), deviceNode: deviceNode,
                                          fileSystem: fileSystem, connection: mount.connection))
        }
        // 已經卸載的掛載不再保留判斷結果，編號與標籤被別的裝置重用時才不會沿用舊結果
        externalCache = externalCache.filter { liveKeys.contains($0.key) }
        return volumes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 單一磁碟自接上以來的累計讀寫位元組：從該分割區的 IOMedia 沿著 IORegistry 往上找到 IOBlockStorageDriver
    /// 裝置節點 → 找到的 IOBlockStorageDriver（已 retain）。每秒都要讀，記住位置就不必每次搜尋 IORegistry。只在主執行緒讀寫
    private static var driverCache: [String: io_service_t] = [:]

    static func ioBytes(forDevice deviceNode: String) -> (read: UInt64, written: UInt64)? {
        if let driver = driverCache[deviceNode] {
            if let bytes = statistics(of: driver) { return bytes }
            // 裝置已移除或重新列舉：放掉舊的，重新找
            IOObjectRelease(driver)
            driverCache[deviceNode] = nil
        }
        guard let driver = findDriver(forDevice: deviceNode) else { return nil }
        driverCache[deviceNode] = driver
        return statistics(of: driver)
    }

    /// 只保留仍掛載中的裝置，其餘釋放
    static func pruneDriverCache(keeping nodes: Set<String>) {
        for (node, driver) in driverCache where !nodes.contains(node) {
            IOObjectRelease(driver)
            driverCache[node] = nil
        }
    }

    private static func statistics(of driver: io_service_t) -> (read: UInt64, written: UInt64)? {
        guard let counters = IORegistryEntryCreateCFProperty(driver, "Statistics" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] else { return nil }
        return ((counters["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0, (counters["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0)
    }

    /// 從分割區的 IOMedia 沿著 IORegistry 往上找到 IOBlockStorageDriver；回傳的物件由呼叫端負責釋放
    private static func findDriver(forDevice deviceNode: String) -> io_service_t? {
        guard ExternalDisk.isValidDeviceNode(deviceNode) else { return nil }
        let bsdName = String(deviceNode.dropFirst("/dev/".count))
        let media = IOServiceGetMatchingService(kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, bsdName))
        guard media != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(media) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(media, kIOServicePlane,
                                            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents),
                                            &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var entry = IOIteratorNext(iterator)
        while entry != IO_OBJECT_NULL {
            if IOObjectConformsTo(entry, "IOBlockStorageDriver") != 0 { return entry }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return nil
    }

    /// SMART 整體狀態；會啟動 diskutil，只能在背景執行
    static func smartStatus(forDevice deviceNode: String) -> DiskHealth {
        guard ExternalDisk.isValidDeviceNode(deviceNode),
              let output = Shell.runSync("/usr/sbin/diskutil", ["info", "-plist", deviceNode], timeout: 10),
              let plist = try? PropertyListSerialization.propertyList(from: Data(output.utf8), format: nil) as? [String: Any]
        else { return .unknown }
        return DiskHealth.parse(plist["SMARTStatus"] as? String)
    }

    enum LifetimeRead {
        case data(DiskLifetime)
        /// 這顆不是 NVMe 或不支援 SMART（SATA 硬碟、多數 USB 外接盒）
        case unsupported
        /// 支援但這次沒讀到，下次再試
        case failed
    }

    /// NVMe 硬碟自己記錄的 SMART 資料（出廠以來的讀寫量、已用壽命）。從分割區沿著 IORegistry 往上找到支援 NVMe SMART 的裝置，
    /// 透過系統內建的 NVMeSMARTLib 外掛讀取，不需要管理員權限，一次約 0.2 毫秒。可以在背景執行緒呼叫
    static func lifetime(forDevice deviceNode: String) -> LifetimeRead {
        guard ExternalDisk.isValidDeviceNode(deviceNode) else { return .unsupported }
        let bsdName = String(deviceNode.dropFirst("/dev/".count))
        let media = IOServiceGetMatchingService(kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, bsdName))
        guard media != IO_OBJECT_NULL else { return .failed }
        defer { IOObjectRelease(media) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(media, kIOServicePlane,
                                            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents),
                                            &iterator) == KERN_SUCCESS else { return .failed }
        defer { IOObjectRelease(iterator) }
        var entry = IOIteratorNext(iterator)
        while entry != IO_OBJECT_NULL {
            let capable = IORegistryEntryCreateCFProperty(entry, "NVMe SMART Capable" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Bool
            if capable == true {
                defer { IOObjectRelease(entry) }
                return NVMeSMART.read(entry).flatMap(DiskLifetime.parse).map(LifetimeRead.data) ?? .failed
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return .unsupported
    }

    /// 所有內建與外接儲存裝置自開機以來的累計讀寫位元組
    static func ioBytes() -> (read: UInt64, written: UInt64)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0, written: UInt64 = 0
        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            if let counters = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                read += (counters["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                written += (counters["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return (read, written)
    }
}

/// NVMe 硬碟的 SMART 記錄。系統的 NVMeSMARTLib 外掛（IOKit/storage/nvme/NVMeSMARTLibExternal.h）沒有對 Swift 公開，
/// 這裡照標頭檔的 UUID 與函式表位置呼叫
private enum NVMeSMART {
    private static let userClientType: CFUUID = CFUUIDGetConstantUUIDWithBytes(
        nil, 0xAA, 0x0F, 0xA6, 0xF9, 0xC2, 0xD6, 0x45, 0x7F, 0xB1, 0x0B, 0x59, 0xA1, 0x32, 0x53, 0x29, 0x2F)
    private static let interfaceID: CFUUID = CFUUIDGetConstantUUIDWithBytes(
        nil, 0xCC, 0xD1, 0xDB, 0x19, 0xFD, 0x9A, 0x4D, 0xAF, 0xBF, 0x95, 0x12, 0x45, 0x4B, 0x23, 0x0A, 0xB6)
    /// kIOCFPlugInInterfaceID
    private static let plugInInterface: CFUUID = CFUUIDGetConstantUUIDWithBytes(
        nil, 0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4, 0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)

    private typealias Release = @convention(c) (UnsafeMutableRawPointer?) -> ULONG
    private typealias ReadData = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> IOReturn

    /// 512 位元組的 SMART／健康資訊記錄；讀不到時回傳 nil
    static func read(_ device: io_service_t) -> [UInt8]? {
        var plugIn: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        guard IOCreatePlugInInterfaceForService(device, userClientType, plugInInterface, &plugIn, &score) == KERN_SUCCESS,
              let plugIn, let plugInTable = plugIn.pointee else { return nil }
        defer { _ = plugInTable.pointee.Release(plugIn) }
        var object: LPVOID?
        guard plugInTable.pointee.QueryInterface(plugIn, CFUUIDGetUUIDBytes(interfaceID), &object) == S_OK,
              let object else { return nil }
        // 函式表依序是 IUnknown 的保留欄位、QueryInterface、AddRef、Release，兩個 UInt16 版本號（補齊到一格），接著是 SMARTReadData
        let table = object.load(as: UnsafeRawPointer.self)
        let slot = MemoryLayout<UnsafeRawPointer>.size
        let release = table.load(fromByteOffset: 3 * slot, as: Release.self)
        let readData = table.load(fromByteOffset: 5 * slot, as: ReadData.self)
        defer { _ = release(object) }
        var log = [UInt8](repeating: 0, count: 512)
        let result = log.withUnsafeMutableBytes { readData(object, $0.baseAddress) }
        return result == kIOReturnSuccess ? log : nil
    }
}

enum NetworkReader {
    private static let store = SCDynamicStoreCreate(nil, "macbookBatteryMonitor" as CFString, nil, nil)

    /// 指定介面自開機以來的累計收發位元組（64 位元計數器，不會在 4 GB 回繞）。
    /// 只查這一個介面，不必每秒掃過所有虛擬介面
    static func counters(for interface: String) -> (received: UInt64, sent: UInt64)? {
        let index = if_nametoindex(interface)
        guard index > 0 else { return nil }
        return counters(index: Int32(index)).first?.value
    }

    /// 各介面自開機以來的累計收發位元組；index 為 0 時列出所有介面
    static func counters(index: Int32 = 0) -> [String: (received: UInt64, sent: UInt64)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, index]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return [:] }

        var result: [String: (UInt64, UInt64)] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(message.ifm_index), &name) != nil {
                        result[String(cString: name)] = (message.ifm_data.ifi_ibytes, message.ifm_data.ifi_obytes)
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return result
    }

    /// 目前預設路由使用的介面（例如 en0）
    static func primaryInterface() -> String? {
        guard let store,
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else { return nil }
        return value["PrimaryInterface"] as? String
    }

    static func ipv4Address(of interface: String) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: entry.ifa_name) == interface else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }

    /// 介面類型：Wi-Fi、乙太網路等
    static func kind(of interface: String) -> String {
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        guard let match = interfaces.first(where: { SCNetworkInterfaceGetBSDName($0) as String? == interface }),
              let type = SCNetworkInterfaceGetInterfaceType(match) as String? else { return interface }
        if type == kSCNetworkInterfaceTypeIEEE80211 as String { return "Wi-Fi" }
        if type == kSCNetworkInterfaceTypeEthernet as String { return "乙太網路" }
        return (SCNetworkInterfaceGetLocalizedDisplayName(match) as String?) ?? interface
    }
}

/// 把程序歸到所屬的 App（取最外層的 .app），讓 helper 程序合併到主程式
enum ProcessOwner {
    static func appBundle(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    static func group(_ rows: [TopParse.Row], value: (String) -> Double?, limit: Int) -> [TopProcess] {
        var groups: [String: TopProcess] = [:]
        for row in rows where row.command != "top" {
            guard let v = value(row.value), v > 0 else { continue }
            let app = appBundle(for: row.pid)
            let key = app ?? "pid:\(row.pid)"
            let name = app.map { FileManager.default.displayName(atPath: $0) } ?? row.command
            groups[key, default: TopProcess(id: key, name: name, value: 0, appPath: app)].value += v
        }
        return Array(groups.values.sorted { $0.value > $1.value }.prefix(limit))
    }
}

/// 持續執行的 top，每秒交回一段完整取樣的文字
final class TopStream {
    private static let marker = Data("Processes:".utf8)
    private let arguments: [String]
    private let onSample: (String) -> Void
    private var process: Process?
    private var buffer = Data()

    init(arguments: [String], onSample: @escaping (String) -> Void) {
        self.arguments = arguments
        self.onSample = onSample
    }

    var isRunning: Bool { process != nil }

    func start() {
        guard process == nil else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // top 結束了（被強制結束或閃退）：不停止監聽的話會不停收到空資料，讓 CPU 跑滿
                handle.readabilityHandler = nil
                DispatchQueue.main.async { if let self, self.process === process { self.stop() } }
                return
            }
            DispatchQueue.main.async { if let self, self.process === process { self.append(data) } }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    func stop() {
        guard let process else { return }
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        self.process = nil
        buffer = Data()
    }

    private func append(_ data: Data) {
        guard process != nil else { return }
        buffer.append(data)
        var markers: [Data.Index] = []
        var from = buffer.startIndex
        while let range = buffer.range(of: Self.marker, in: from..<buffer.endIndex) {
            markers.append(range.lowerBound)
            from = range.upperBound
        }
        guard markers.count >= 2 else { return }
        let complete = buffer[markers[markers.count - 2]..<markers[markers.count - 1]]
        buffer = Data(buffer[markers[markers.count - 1]...])
        onSample(String(decoding: complete, as: UTF8.self))
    }
}
