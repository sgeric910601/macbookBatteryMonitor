import AppKit
import Carbon
import OSLog
import SwiftUI

/// 鍵盤清潔模式（判斷在 KeyboardCleaning）。清潔時才建立攔截，結束就拆掉，平常不攔截任何東西。
/// 擋下一般按鍵、修飾鍵與功能列的亮度音量等系統鍵（類型 14）；滑鼠與觸控板照常，點「結束清潔」或時間到就結束。
/// App 結束或當掉時系統會拆掉攔截，鍵盤一定會恢復。需要「輔助使用」權限
@MainActor
final class KeyboardCleaningController {
    static let shared = KeyboardCleaningController()
    nonisolated static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "keyboardCleaning")

    private var state = KeyboardCleaning()
    private var port: CFMachPort?
    private var timer: Timer?
    private var window: NSWindow?
    /// 開始清潔前最前面的 App；結束時叫回來，焦點才會回到原本的地方
    private var previousApp: NSRunningApplication?
    private let view = CleaningStatus()
    /// 系統事件（亮度、音量、媒體鍵）的類型，CGEventType 沒有列出
    private static let systemDefinedType: UInt32 = 14

    var isActive: Bool { state.isActive }

    /// 開始清潔；沒有權限或建立攔截失敗時回傳 false
    @discardableResult
    func start(seconds: Int) -> Bool {
        guard !state.isActive else { return true }
        guard AXIsProcessTrusted() else { return false }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventMask(Self.systemDefinedType))
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: cleaningCallback, userInfo: nil) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        state.start(seconds: KeyboardCleaning.validDuration(seconds), now: Date())
        view.secureInputWarning = IsSecureEventInputEnabled()
        showWindow()
        tick()
        // 加到 common 模式：選單列的選單開著時也要倒數、時間到也要恢復
        let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { KeyboardCleaningController.shared.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Self.log.notice("開始鍵盤清潔")
        return true
    }

    func stop() {
        guard state.isActive else { return }
        state.stop()
        timer?.invalidate()
        timer = nil
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        port = nil
        window?.orderOut(nil)
        if let previousApp, !previousApp.isTerminated { previousApp.activate() }
        previousApp = nil
        Self.log.notice("結束鍵盤清潔")
    }

    private func tick() {
        let now = Date()
        if state.isExpired(now: now) { return stop() }
        view.remaining = state.remainingSeconds(now: now)
        // 系統暫停了攔截（例如回應逾時）：重新打開，清潔中鍵盤才不會突然有作用。權限被撤銷時擋不住鍵盤，直接結束清潔
        if let port, !CGEvent.tapIsEnabled(tap: port) {
            guard AXIsProcessTrusted() else { return stop() }
            CGEvent.tapEnable(tap: port, enable: true)
        }
    }

    fileprivate func blocks(_ type: CGEventType, isRepeat: Bool) -> Bool {
        let kind: KeyboardCleaning.EventKind
        switch type {
        case .keyDown:
            kind = .keyDown
            if state.isActive { state.keyPressed(now: Date(), isRepeat: isRepeat) }
        case .keyUp: kind = .keyUp
        case .flagsChanged: kind = .flagsChanged
        default: kind = type.rawValue == Self.systemDefinedType ? .systemKey : .pointer
        }
        return state.blocks(kind)
    }

    fileprivate func reenable() {
        if let port, state.isActive, AXIsProcessTrusted() { CGEvent.tapEnable(tap: port, enable: true) }
    }

    /// 畫面中央的清潔視窗：拿到焦點，原本的密碼欄等安全輸入就不會讓按鍵繞過攔截
    private func showWindow() {
        let window = self.window ?? {
            let window = CleaningWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 230), styleMask: [.borderless],
                                        backing: .buffered, defer: true)
            window.level = .modalPanel
            window.isOpaque = false
            window.backgroundColor = .clear
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: CleaningView(status: view, stop: { KeyboardCleaningController.shared.stop() }))
            self.window = window
            return window
        }()
        window.center()
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == getpid() ? nil : front
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private final class CleaningWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
@Observable
private final class CleaningStatus {
    var remaining = 0
    var secureInputWarning = false
}

private struct CleaningView: View {
    let status: CleaningStatus
    let stop: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard").font(.system(size: 34, weight: .semibold))
            Text("鍵盤清潔中").font(.title3.weight(.semibold))
            Text("鍵盤已暫時停用，停手 \(status.remaining) 秒後自動恢復").font(.callout).foregroundStyle(.secondary)
            if status.secureInputWarning {
                Text("有 App 開著「安全輸入」，部分按鍵可能還是會送出").font(.caption).foregroundStyle(.orange)
            }
            Button("結束清潔", action: stop)
                .controlSize(.large)
        }
        .padding(24)
        .frame(width: 360, height: 230)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
    }
}

private func cleaningCallback(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo _: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    MainActor.assumeIsolated {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            KeyboardCleaningController.shared.reenable()
            return Unmanaged.passUnretained(event)
        }
        let isRepeat = type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        return KeyboardCleaningController.shared.blocks(type, isRepeat: isRepeat) ? nil : Unmanaged.passUnretained(event)
    }
}
