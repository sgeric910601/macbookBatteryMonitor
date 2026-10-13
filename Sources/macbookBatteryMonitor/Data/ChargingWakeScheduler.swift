import Foundation
import Combine
import CPUPowerShared

/// 智慧充電的「精準喚醒」：在該開始充電前一分鐘叫醒 Mac，讓 App 把充電上限提高到目標。
/// 喚醒事件由管理員服務（與管理員 CPU 取樣共用）排定；只有使用者打開選項時才要求授權，
/// 關掉選項會取消事件，管理員 CPU 取樣也沒開時一併移除服務
@MainActor
final class ChargingWakeScheduler: ObservableObject {
    @Published private(set) var status = "未開啟"
    /// 已經排好的喚醒時間
    @Published private(set) var scheduledAt: Date?
    @Published private(set) var authorizing = false

    private var connection: NSXPCConnection?
    private var process: Process?
    private var installLease: URL?
    /// 已送出、還沒回覆的喚醒時間
    private var requested: Date?
    private var cancelled = false
    private var lastEnabled: Bool?
    private var helperReady = false
    private var helperCheckedAt: Date?
    private let helperBundle: Bundle
    private let log: (String) -> Void
    /// 只有正式打包的 App 才會安裝或連線管理員服務（開發用指令讀的是另一組設定）
    private let enabledInThisProcess: Bool

    init(bundle: Bundle = .main, log: @escaping (String) -> Void = { ChargingPlanLog.shared.write($0) }) {
        helperBundle = bundle
        self.log = log
        enabledInThisProcess = bundle.bundleIdentifier == "com.kuan.batterymonitor"
            && !CommandLine.arguments.contains { $0.hasPrefix("--snapshot") || $0.hasPrefix("--screenshots") }
    }

    /// 喚醒已經排好、而且還在未來：睡眠前不必先提高上限
    var ready: Bool { scheduledAt.map { $0.timeIntervalSinceNow > 30 } ?? false }

    /// 每次判斷排程後呼叫：依選項與排程決定排定、改排或取消喚醒
    func sync(wakeAt: Date?, enabled: Bool) {
        guard enabledInThisProcess else { return }
        let launching = lastEnabled == nil
        let changed = lastEnabled != enabled
        lastEnabled = enabled
        guard enabled else {
            // 開 App 時選項本來就關著：不連線、不動系統裡的任何東西
            if changed && !launching { cancel(removeHelperIfUnused: true) }
            setStatus("未開啟")
            return
        }
        // 服務是否可用不必每秒查檔案：選項改變、授權完成或每分鐘才重新確認
        if changed || helperCheckedAt.map({ Date().timeIntervalSince($0) > 60 }) ?? true {
            helperReady = CPUHelperInstaller.supportsChargingWake
            helperCheckedAt = Date()
        }
        guard helperReady else {
            if launching {
                // 開 App 時不跳出授權：服務不在、或是只有 CPU 取樣的舊服務，就關掉選項
                AppSettings.shared.chargingWakeEnabled = false
                lastEnabled = false
                status = "管理員服務已更新或不存在，已改用優先準時完成；需要時請重新選擇精準喚醒並授權"
                onUnavailable?()
            } else if process == nil {
                install()
            }
            return
        }
        guard let wakeAt, wakeAt.timeIntervalSinceNow >= ChargingWakePolicy.earliest else {
            if !cancelled { cancel(removeHelperIfUnused: false) }
            setStatus("已授權，目前不需要喚醒")
            return
        }
        guard ChargingWakePolicy.shouldReplace(existing: requested ?? scheduledAt, with: wakeAt) else { return }
        schedule(wakeAt)
    }

    /// 每秒都會呼叫 sync：狀態文字沒變就不寫，畫面不必重畫
    private func setStatus(_ text: String) {
        if status != text { status = text }
    }

    func stop() {
        connection?.invalidate()
        connection = nil
        if let installLease { try? FileManager.default.removeItem(at: installLease) }
        installLease = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        authorizing = false
    }

    private func install() {
        do {
            let lease = FileManager.default.temporaryDirectory.appendingPathComponent("wake-install-\(UUID().uuidString)")
            try Data().write(to: lease, options: .atomic)
            installLease = lease
            let task = try CPUHelperInstaller.makeProcess(bundle: helperBundle, lease: lease)
            task.terminationHandler = { [weak self] task in
                let succeeded = task.terminationStatus == 0
                Task { @MainActor in
                    guard let self else { return }
                    self.process = nil
                    if let lease = self.installLease { try? FileManager.default.removeItem(at: lease) }
                    self.installLease = nil
                    self.authorizing = false
                    guard AppSettings.shared.chargingWakeEnabled else { return }
                    guard succeeded, CPUHelperInstaller.supportsChargingWake else {
                        AppSettings.shared.chargingWakeEnabled = false
                        self.lastEnabled = false
                        self.status = "授權已取消或安裝失敗，已改用優先準時完成"
                        self.log("精準喚醒：授權取消或安裝失敗")
                        self.onUnavailable?()
                        return
                    }
                    self.status = "已授權"
                    self.helperReady = true
                    self.helperCheckedAt = Date()
                    self.log("精準喚醒：已授權")
                    self.onAuthorized?()
                }
            }
            process = task
            authorizing = true
            status = "等待系統管理員授權"
            try task.run()
        } catch {
            process = nil
            authorizing = false
            AppSettings.shared.chargingWakeEnabled = false
            lastEnabled = false
            status = "無法安裝管理員服務：\(error.localizedDescription)"
            onUnavailable?()
        }
    }

    /// 授權完成後重新判斷一次（排定喚醒）
    var onAuthorized: (() -> Void)?
    /// 服務無法使用（授權取消、安裝失敗、開 App 時服務不在）：改回優先準時完成
    var onUnavailable: (() -> Void)?

    private func proxy() -> CPUHelperProtocol? {
        if connection == nil {
            let client = NSXPCConnection(machServiceName: CPUHelperConstants.label, options: .privileged)
            client.remoteObjectInterface = NSXPCInterface(with: CPUHelperProtocol.self)
            client.invalidationHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            connection = client
            client.resume()
        }
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.connection?.invalidate()
                self.connection = nil
                self.requested = nil
                self.scheduledAt = nil
                self.status = "無法連線到管理員服務，睡眠前會改用優先準時完成"
                self.log("精準喚醒：無法連線到管理員服務（\(error.localizedDescription)）")
            }
        } as? CPUHelperProtocol
    }

    private func schedule(_ date: Date) {
        guard let helper = proxy() else { return }
        requested = date
        cancelled = false
        helper.scheduleChargingWake(at: date.timeIntervalSince1970) { [weak self] error in
            Task { @MainActor in
                guard let self, self.requested == date else { return }
                self.requested = nil
                if let error {
                    self.scheduledAt = nil
                    self.status = "\(error)，睡眠前會改用優先準時完成"
                    self.log("精準喚醒：排定 \(date.formatted(date: .omitted, time: .shortened)) 失敗（\(error)）")
                } else {
                    self.scheduledAt = date
                    self.status = "已排定 \(date.formatted(date: .abbreviated, time: .shortened)) 喚醒"
                    self.log("精準喚醒：已排定 \(date.formatted(date: .abbreviated, time: .standard))")
                }
            }
        }
    }

    private func cancel(removeHelperIfUnused: Bool) {
        let hadWake = scheduledAt != nil || requested != nil
        requested = nil
        scheduledAt = nil
        cancelled = true
        guard CPUHelperInstaller.present, let helper = proxy() else { return }
        helper.cancelChargingWake { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if hadWake { self.log("精準喚醒：已取消") }
                guard removeHelperIfUnused,
                      !ChargingWakePolicy.keepsHelper(cpuSampling: AppSettings.shared.adminCPUSampling,
                                                      chargingWake: AppSettings.shared.chargingWakeEnabled) else { return }
                helper.uninstall { _ in }
                self.log("精準喚醒：已關閉，移除管理員服務")
            }
        }
    }
}
