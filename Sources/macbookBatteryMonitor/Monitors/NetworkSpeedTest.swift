import Foundation

/// 用 macOS 內建的 networkQuality 測速（連到 Apple 的測速伺服器），只在使用者按下按鈕時執行。
/// networkQuality 測完才輸出結果，所以測速中改用目前網路介面的收發計數器顯示即時速率
@MainActor
final class NetworkSpeedTest: ObservableObject {
    enum Phase: Equatable {
        case idle
        case running
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var result: SpeedTestResult?
    /// 測速中的即時速率（位元組／秒）：整個網路介面的流量，包含其他程式
    @Published private(set) var liveDownload: Double = 0
    @Published private(set) var liveUpload: Double = 0

    /// networkQuality 的測試時間上限（秒）；再多給一些餘裕，超過就強制結束，避免卡住
    private static let maxRuntime = 30
    private static let liveInterval: TimeInterval = 0.5
    private static let toolURL = URL(fileURLWithPath: "/usr/bin/networkQuality")

    /// 這台的 networkQuality 支援哪些參數：看一次說明就記住（說明是立刻印出的，不會連網）
    private static let arguments: [String] = {
        let process = Process()
        process.executableURL = toolURL
        process.arguments = ["-h"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else { return SpeedTestResult.arguments(help: "", maxRuntime: maxRuntime) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return SpeedTestResult.arguments(help: String(decoding: data, as: UTF8.self), maxRuntime: maxRuntime)
    }()

    private var process: Process?
    private var cancelled = false
    private var timer: Timer?
    private var last: (interface: String, received: UInt64, sent: UInt64, date: Date)?

    var isRunning: Bool { phase == .running }

    func start() {
        guard process == nil else { return }
        let process = Process()
        process.executableURL = Self.toolURL
        process.arguments = Self.arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            phase = .failed("無法啟動系統的測速工具")
            return
        }
        self.process = process
        cancelled = false
        phase = .running
        liveDownload = 0
        liveUpload = 0
        startLiveSampling()

        // 輸出可能有數十 KB（各次延遲量測的明細），要在背景一路讀到結束，管線才不會塞住
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let succeeded = process.terminationReason == .exit && process.terminationStatus == 0
            Task { @MainActor in self?.finish(process, data: succeeded ? data : nil) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(Self.maxRuntime + 30)) { [weak process] in
            if let process, process.isRunning { process.terminate() }
        }
    }

    func cancel() {
        guard let process else { return }
        cancelled = true
        if process.isRunning { process.terminate() }
    }

    private func finish(_ finished: Process, data: Data?) {
        // 已經開始新的一次測速時，不要拿舊的結果蓋過去
        guard process === finished else { return }
        process = nil
        stopLiveSampling()
        if cancelled {
            phase = .idle
        } else if let data, let result = SpeedTestResult.parse(data, at: Date()) {
            self.result = result
            phase = .idle
        } else {
            // 不留上一次的結果，免得和失敗訊息擺在一起被誤認為這次的數字
            result = nil
            phase = .failed("測速失敗，請確認網路連線後再試一次")
        }
    }

    // MARK: - 即時速率

    private func startLiveSampling() {
        last = nil
        sampleLive()
        let timer = Timer(timeInterval: Self.liveInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolatedCompat { self?.sampleLive() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopLiveSampling() {
        timer?.invalidate()
        timer = nil
        last = nil
    }

    private func sampleLive() {
        let now = Date()
        guard let interface = NetworkReader.primaryInterface(), let counter = NetworkReader.counters(for: interface) else {
            last = nil
            return
        }
        if let last, last.interface == interface {
            let interval = now.timeIntervalSince(last.date)
            liveDownload = RateMath.perSecond(old: last.received, new: counter.received, interval: interval)
            liveUpload = RateMath.perSecond(old: last.sent, new: counter.sent, interval: interval)
        }
        last = (interface, counter.received, counter.sent, now)
    }
}
