import AppKit
import SwiftUI

/// 開發用：`--dump-monitors` 取樣兩次（間隔 1 秒）並把四個模組的讀數印成 JSON
@MainActor
enum MonitorDebug {
    static func dump() {
        let cpu = CPUMonitor(), memory = MemoryMonitor(), disk = DiskMonitor(), network = NetworkMonitor()
        cpu.setThermalActive(true)
        for _ in 0..<2 {
            let now = Date()
            cpu.sample(at: now)
            memory.sample(at: now)
            disk.sample(at: now)
            network.sample(at: now)
            RunLoop.main.run(until: Date().addingTimeInterval(1))
        }
        let m = memory.usage
        func stat(_ s: TemperatureSummary.Stat?) -> Any { s.map { ["average": $0.average, "maximum": $0.maximum] } ?? NSNull() }
        let thermalInfo: [String: Any] = [
            "fans": cpu.fans.map { ["name": $0.name, "rpm": $0.rpm, "min": $0.minRPM, "max": $0.maxRPM, "fraction": $0.fraction] },
            "cpu": stat(cpu.temperatures.cpu), "gpu": stat(cpu.temperatures.gpu), "soc": stat(cpu.temperatures.soc),
            "battery": stat(cpu.temperatures.battery), "storage": stat(cpu.temperatures.storage),
        ]
        // 分成幾個有型別標註的字典，避免單一大型字面值讓編譯器型別推斷逾時
        let cpuInfo: [String: Any] = [
            "total": cpu.usage?.total ?? -1, "user": cpu.usage?.user ?? -1, "system": cpu.usage?.system ?? -1,
            "cores": cpu.cores.map { ($0.total * 1000).rounded() / 1000 },
            "efficiencyCores": cpu.layout.efficiency, "performanceCores": cpu.layout.performance,
            "gpu": cpu.gpu ?? -1, "gpuMemory": cpu.gpuMemory ?? 0, "load": cpu.load,
        ]
        let memoryInfo: [String: Any] = [
            "total": m?.total ?? 0, "used": m?.used ?? 0, "app": m?.app ?? 0, "wired": m?.wired ?? 0,
            "compressed": m?.compressed ?? 0, "cached": m?.cached ?? 0, "free": m?.free ?? 0,
            "swapUsed": m?.swapUsed ?? 0, "pressure": m?.pressure.rawValue ?? 0,
        ]
        let diskInfo: [String: Any] = [
            "name": disk.volume?.name ?? "", "total": disk.volume?.total ?? 0, "available": disk.volume?.available ?? 0,
            "readRate": disk.readRate, "writeRate": disk.writeRate,
            "totalRead": disk.totalRead, "totalWritten": disk.totalWritten,
            "lifetime": lifetimeInfo(disk.volume?.deviceNode ?? ""),
            "external": disk.externalVolumes.map { volume -> [String: Any] in
                let usage = disk.externalStats[volume.id]
                return ["name": volume.name, "total": volume.total, "available": volume.available, "device": volume.deviceNode,
                        "lifetime": lifetimeInfo(volume.deviceNode),
                        "fileSystem": volume.fileSystem, "connection": volume.connection,
                        "totalRead": usage?.totalRead ?? 0, "totalWritten": usage?.totalWritten ?? 0,
                        "readRate": usage?.readRate ?? 0, "writeRate": usage?.writeRate ?? 0]
            },
        ]
        let networkInfo: [String: Any] = [
            "interface": network.interface ?? "", "kind": network.kind ?? "", "address": network.address ?? "",
            "downloadRate": network.downloadRate, "uploadRate": network.uploadRate,
            "totalReceived": network.totalReceived, "totalSent": network.totalSent,
        ]
        let output: [String: Any] = ["thermal": thermalInfo, "cpu": cpuInfo, "memory": memoryInfo, "disk": diskInfo, "network": networkInfo]
        if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    /// 選單列小圖（截圖用），與 ModuleCoordinator 顯示的內容相同
    /// 硬碟自己記錄的 SMART 資料；不支援時寫 unsupported
    private static func lifetimeInfo(_ node: String) -> Any {
        switch DiskReader.lifetime(forDevice: node) {
        case .data(let l):
            return ["health": l.healthPercent, "percentageUsed": l.percentageUsed, "availableSpare": l.availableSpare,
                    "spareThreshold": l.spareThreshold, "criticalWarning": Int(l.criticalWarning), "bytesRead": l.bytesRead,
                    "bytesWritten": l.bytesWritten, "powerOnHours": l.powerOnHours, "mediaErrors": l.mediaErrors] as [String: Any]
        case .unsupported: return "unsupported"
        case .failed: return "failed"
        }
    }

    static func menuBarImages(cpu: CPUMonitor, memory: MemoryMonitor, disk: DiskMonitor, network: NetworkMonitor) -> [NSImage] {
        let diskFraction = disk.volume.map { $0.total > 0 ? Double($0.used) / Double($0.total) : 0 }
        return [
            MonitorMenuBarRenderer.twoLines([("CPU", cpu.usage.map { ByteFormat.percent($0.total) } ?? "—", MonitorMenuBarRenderer.green),
                                             ("GPU", cpu.gpu.map(ByteFormat.percent) ?? "—", MonitorMenuBarRenderer.orange)], valueTemplate: "100%"),
            MonitorMenuBarRenderer.symbolValue(symbol: "memorychip", value: memory.usage.map { ByteFormat.percent($0.usedFraction) } ?? "—", valueTemplate: "100%"),
            MonitorMenuBarRenderer.symbolValue(symbol: "internaldrive", value: diskFraction.map(ByteFormat.percent) ?? "—", valueTemplate: "100%"),
            MonitorMenuBarRenderer.twoLines([("↑", ByteFormat.compactRate(network.uploadRate), MonitorMenuBarRenderer.orange),
                                             ("↓", ByteFormat.compactRate(network.downloadRate), MonitorMenuBarRenderer.green)], valueTemplate: "999K"),
        ]
    }
}
