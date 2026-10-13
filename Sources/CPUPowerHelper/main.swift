import Foundation
import CPUPowerShared
import Darwin
import IOKit.pwr_mgt

/// 所有子程序與租約狀態都只在同一個 queue 存取。
final class CPUSampler {
    let queue = DispatchQueue(label: "com.kuan.batterymonitor.cpu.sampler")
    private var leases = CPUSamplingLeases()
    private var timer: DispatchSourceTimer?
    private var process: Process?
    private var pipe: Pipe?
    private var parser = CPUPowerStream()
    private var reading: CPUPowerReading?
    private var error: String?
    private var disabled = false
    private var stopping = false
    private var token = UUID()
    /// powermetrics 的取樣間隔（秒），只會是 1、2、5、10
    private var interval = 1
    private var idleExit: DispatchWorkItem?

    func sample(client: UUID, active: Bool, interval requested: Int, reply: @escaping (Data) -> Void) {
        queue.async {
            let now = ProcessInfo.processInfo.systemUptime
            if active && !self.disabled { self.setInterval(CPUHelperConstants.samplingInterval(requested)) }
            self.leases.set(client, active: active && !self.disabled, at: now,
                            duration: CPUHelperConstants.leaseDuration(interval: requested))
            self.reconcile()
            let value = active && !self.disabled ? self.reading : nil
            let payload = CPUHelperReply(reading: value, error: self.disabled ? "服務已停用" : self.error)
            reply((try? JSONEncoder().encode(payload)) ?? Data())
        }
    }

    func disconnect(_ client: UUID) {
        queue.async { self.leases.remove(client); self.reconcile() }
    }

    /// 間隔改變（更新頻率或省電模式）時重新啟動 powermetrics；結束後由 terminationHandler 依新間隔啟動
    private func setInterval(_ seconds: Int) {
        guard seconds != interval else { return }
        interval = seconds
        if let process, process.isRunning, !stopping {
            stopping = true
            process.terminate()
        }
    }

    private func reconcile() {
        let active = !disabled && leases.isActive(at: ProcessInfo.processInfo.systemUptime)
        if active {
            idleExit?.cancel(); idleExit = nil
            if timer == nil {
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
                timer.setEventHandler { [weak self] in self?.reconcile() }
                self.timer = timer
                timer.resume()
            }
            if process == nil && error == nil { start() }
        } else {
            timer?.cancel(); timer = nil
            reading = nil
            error = nil
            if let process, process.isRunning, !stopping {
                stopping = true
                process.terminate()
            }
            scheduleIdleExit()
        }
    }

    func startIdleCountdown() { reconcile() }

    /// 沒有任何租約一段時間後自行結束，不常駐；App 下次需要取樣時 launchd 會再啟動服務
    private func scheduleIdleExit() {
        guard idleExit == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.idleExit = nil
            // powermetrics 還在結束中時，等 terminationHandler 呼叫 reconcile 再重新排程
            guard !self.leases.isActive(at: ProcessInfo.processInfo.systemUptime), self.process == nil else { return }
            exit(0)
        }
        idleExit = work
        queue.asyncAfter(deadline: .now() + CPUHelperConstants.idleExit, execute: work)
    }

    private func start() {
        let task = Process(), stream = Pipe(), generation = UUID()
        token = generation
        stopping = false
        parser = CPUPowerStream()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        task.arguments = ["--samplers", "cpu_power", "-i", "\(interval * 1000)", "-b", "1"]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = stream
        task.standardError = FileHandle.nullDevice
        stream.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            self?.queue.async { [weak self] in
                guard let self, self.token == generation, !self.stopping else { return }
                if let watts = self.parser.append(String(decoding: data, as: UTF8.self)) {
                    self.reading = CPUPowerReading(watts: watts, uptime: ProcessInfo.processInfo.systemUptime)
                }
            }
        }
        task.terminationHandler = { [weak self] task in
            self?.queue.async { [weak self] in
                guard let self, self.token == generation else { return }
                self.pipe?.fileHandleForReading.readabilityHandler = nil
                try? self.pipe?.fileHandleForReading.close()
                self.pipe = nil
                self.process = nil
                self.reading = nil
                if !self.stopping { self.error = "系統 CPU 取樣意外停止，請重新啟用功能。" }
                self.stopping = false
                self.reconcile()
            }
        }
        process = task; pipe = stream
        do { try task.run() }
        catch {
            stream.fileHandleForReading.readabilityHandler = nil
            process = nil; pipe = nil
            self.error = "無法啟動系統 CPU 取樣。"
        }
    }

    func uninstall(reply: @escaping (String?) -> Void) {
        queue.async {
            self.disabled = true
            self.reconcile()
            ChargingWake.cancel()
            do {
                // 固定 root 管理的位置，不從客戶端接受任何檔案路徑。
                let fm = FileManager.default
                for path in [CPUHelperConstants.launchDaemon, CPUHelperConstants.configuration,
                             CPUHelperConstants.chargingWakeRecord, CPUHelperConstants.executable] {
                    if fm.fileExists(atPath: path) { try fm.removeItem(atPath: path) }
                }
                try fm.removeItem(atPath: CPUHelperConstants.directory)
                reply(nil)
                self.queue.asyncAfter(deadline: .now() + 0.5) {
                    let bootout = Process()
                    bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                    bootout.arguments = ["bootout", "system/" + CPUHelperConstants.label]
                    bootout.standardInput = FileHandle.nullDevice
                    bootout.standardOutput = FileHandle.nullDevice
                    bootout.standardError = FileHandle.nullDevice
                    try? bootout.run()
                }
            } catch { reply("服務移除失敗：\(error.localizedDescription)") }
        }
    }
}

/// 智慧充電的喚醒事件：識別碼固定，時間只能在 1 分鐘後到 7 天內，同時只會有一個。
/// 排定的時間記在服務資料夾裡，改排或取消時用它找到舊的事件
enum ChargingWake {
    static let queue = DispatchQueue(label: "com.kuan.batterymonitor.cpu.wake")

    static func schedule(at epoch: Double) -> String? {
        queue.sync {
            guard ChargingWakePolicy.isAllowed(epoch, now: Date()) else { return "喚醒時間超出允許範圍" }
            cancelRecorded()
            let date = Date(timeIntervalSince1970: epoch)
            let result = IOPMSchedulePowerEvent(date as CFDate, CPUHelperConstants.chargingWakeIdentifier as CFString,
                                                kIOPMAutoWake as CFString)
            guard result == kIOReturnSuccess else { return "macOS 沒有接受喚醒排程（\(result)）" }
            try? Data(String(epoch).utf8).write(to: URL(fileURLWithPath: CPUHelperConstants.chargingWakeRecord), options: .atomic)
            return nil
        }
    }

    static func cancel() {
        queue.sync { cancelRecorded() }
    }

    private static func cancelRecorded() {
        let url = URL(fileURLWithPath: CPUHelperConstants.chargingWakeRecord)
        if let text = try? String(contentsOf: url, encoding: .utf8), let epoch = Double(text), epoch.isFinite {
            _ = IOPMCancelScheduledPowerEvent(Date(timeIntervalSince1970: epoch) as CFDate,
                                              CPUHelperConstants.chargingWakeIdentifier as CFString, kIOPMAutoWake as CFString)
        }
        try? FileManager.default.removeItem(at: url)
    }
}

final class CPUClient: NSObject, CPUHelperProtocol {
    let id = UUID()
    let sampler: CPUSampler
    init(sampler: CPUSampler) { self.sampler = sampler }
    func sample(active: Bool, interval: Int, withReply reply: @escaping (Data) -> Void) {
        sampler.sample(client: id, active: active, interval: interval, reply: reply)
    }
    func scheduleChargingWake(at epoch: Double, withReply reply: @escaping (String?) -> Void) {
        reply(ChargingWake.schedule(at: epoch))
    }
    func cancelChargingWake(withReply reply: @escaping (String?) -> Void) {
        ChargingWake.cancel()
        reply(nil)
    }
    func uninstall(withReply reply: @escaping (String?) -> Void) { sampler.uninstall(reply: reply) }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let sampler = CPUSampler()
    let allowedUID: UInt32
    init(uid: UInt32) { allowedUID = uid }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // UID 由 root 擁有的安裝設定決定；其他使用者不能啟停服務。
        guard connection.effectiveUserIdentifier == allowedUID else { return false }
        let client = CPUClient(sampler: sampler)
        connection.exportedInterface = NSXPCInterface(with: CPUHelperProtocol.self)
        connection.exportedObject = client
        connection.invalidationHandler = { [sampler] in sampler.disconnect(client.id) }
        connection.interruptionHandler = { [sampler] in sampler.disconnect(client.id) }
        connection.resume()
        return true
    }
}

guard geteuid() == 0,
      let attrs = try? FileManager.default.attributesOfItem(atPath: CPUHelperConstants.configuration),
      (attrs[.ownerAccountID] as? NSNumber)?.intValue == 0,
      (attrs[.posixPermissions] as? NSNumber)?.intValue == 0o644,
      let data = try? Data(contentsOf: URL(fileURLWithPath: CPUHelperConstants.configuration)),
      let configuration = try? JSONDecoder().decode(CPUHelperConfiguration.self, from: data),
      configuration.version == CPUHelperConstants.version, configuration.uid != 0 else { exit(1) }
let delegate = ListenerDelegate(uid: configuration.uid)
let listener = NSXPCListener(machServiceName: CPUHelperConstants.label)
listener.delegate = delegate
listener.resume()
// 被 launchd 啟動後若一直沒有取樣要求（例如只是來移除服務），閒置後同樣自行結束
delegate.sampler.queue.async { delegate.sampler.startIdleCountdown() }
RunLoop.current.run()
