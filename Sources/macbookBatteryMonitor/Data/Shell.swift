import Foundation

enum Shell {
    /// timeout 指定時，超過秒數就結束子行程並回傳 nil，避免卡住的外接裝置讓 diskutil 無限期等待
    static func runSync(_ path: String, _ arguments: [String], timeout: TimeInterval? = nil) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        var timedOut = false
        let lock = NSLock()
        if let timeout {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                lock.lock()
                defer { lock.unlock() }
                if process.isRunning {
                    timedOut = true
                    process.terminate()
                }
            }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        lock.lock()
        defer { lock.unlock() }
        return timedOut ? nil : String(data: data, encoding: .utf8)
    }
}
