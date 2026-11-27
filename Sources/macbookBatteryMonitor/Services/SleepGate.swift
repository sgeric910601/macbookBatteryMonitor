import Foundation
import IOKit.pwr_mgt

/// 系統即將睡眠時，讓智慧充電有時間把充電上限寫好再睡（最多延後 5 秒）。
/// NSWorkspace 的睡眠通知不能延後睡眠，這裡用 IOKit 的系統電源通知：回覆 IOAllowPowerChange 之前系統會等
final class SleepGate {
    /// 收到「即將睡眠」時呼叫；做完要呼叫傳入的 allow（沒呼叫也會在 5 秒後自動允許）
    var onWillSleep: ((@escaping () -> Void) -> Void)?

    private var root: io_connect_t = 0
    private var port: IONotificationPortRef?
    private var notifier: io_object_t = 0
    static let timeout: TimeInterval = 5
    /// 還沒回覆的「即將睡眠」：回覆前不能取消註冊，否則系統等不到同意
    private var pendingReplies = 0
    private var stopWhenAnswered = false

    // IOKit/IOMessage.h 的 iokit_common_msg(...)，Swift 不會匯入這些巨集
    private static let canSystemSleep: natural_t = 0xE000_0270
    private static let systemWillSleep: natural_t = 0xE000_0280

    func start() {
        stopWhenAnswered = false
        guard root == 0 else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        root = IORegisterForSystemPower(context, &port, { context, _, message, argument in
            guard let context else { return }
            Unmanaged<SleepGate>.fromOpaque(context).takeUnretainedValue().handle(message, argument)
        }, &notifier)
        guard root != 0, let port else { return }
        IONotificationPortSetDispatchQueue(port, .main)
    }

    /// 沒有排程時不需要延後睡眠：取消系統電源通知
    func stop() {
        // 睡眠回覆還沒送出：等回覆完再取消
        guard pendingReplies == 0 else {
            stopWhenAnswered = true
            return
        }
        guard root != 0 else { return }
        IODeregisterForSystemPower(&notifier)
        notifier = 0
        if let port { IONotificationPortDestroy(port) }
        port = nil
        IOServiceClose(root)
        root = 0
    }

    private func handle(_ message: natural_t, _ argument: UnsafeMutableRawPointer?) {
        let id = Int(bitPattern: argument)
        switch message {
        case Self.canSystemSleep:
            IOAllowPowerChange(root, id)
        case Self.systemWillSleep:
            var answered = false
            let root = self.root
            pendingReplies += 1
            let allow = { [weak self] in
                guard let self, !answered else { return }
                answered = true
                IOAllowPowerChange(root, id)
                pendingReplies -= 1
                if pendingReplies == 0, stopWhenAnswered {
                    stopWhenAnswered = false
                    stop()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) { allow() }
            if let onWillSleep { onWillSleep { DispatchQueue.main.async { allow() } } } else { allow() }
        default:
            break
        }
    }
}
