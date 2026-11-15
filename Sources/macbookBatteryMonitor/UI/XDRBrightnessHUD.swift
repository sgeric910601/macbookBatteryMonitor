import AppKit
import SwiftUI
import Observation

/// 和系統亮度提示框同大小（macOS 27 實測 308 × 66 點），疊在同一個位置
private let xdrHUDSize = CGSize(width: 308, height: 66)

@MainActor @Observable
private final class XDRBrightnessHUDState {
    var gain = 1.0
    var maximumGain = 1.6
    var progress: Double {
        guard maximumGain > 1 else { return 0 }
        return min(1, max(0, (gain - 1) / (maximumGain - 1)))
    }
    var nits: Int?
    var shown = false
}

private struct XDRBrightnessHUDView: View {
    let state: XDRBrightnessHUDState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 27, weight: .regular))
                .frame(width: 27)
            VStack(alignment: .leading, spacing: 5) {
                XDRBrightnessSegments(progress: state.progress)
                    .frame(height: 4)
                    .accessibilityLabel("XDR 增亮")
                    .accessibilityValue("\(Int((state.gain * 100).rounded()))%")
                // 估算亮度放在格子下方，和格子同一個框裡
                Text(nitsText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .padding(.top, 15)
        }
        .foregroundStyle(Color.white)
        .padding(.leading, 24)
        .padding(.trailing, 31)
        .frame(width: xdrHUDSize.width, height: xdrHUDSize.height)
        .background { capsuleBackground }
        .environment(\.colorScheme, .dark)
        .opacity(state.shown ? 1 : 0)
        .animation(.easeOut(duration: 0.1), value: state.gain)
        .animation(.easeOut(duration: 0.18), value: state.shown)
    }

    @ViewBuilder private var capsuleBackground: some View {
        // 執行階段 availability 無法讓舊 SDK 認得新 API，另以編譯器版本隔離。
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.clear, in: Capsule())
        } else {
            Capsule().fill(.ultraThinMaterial)
        }
        #else
        Capsule().fill(.ultraThinMaterial)
        #endif
    }

    private var nitsText: String {
        if let nits = state.nits { return "估算 \(nits) nits" }
        return "XDR \(Int((state.gain * 100).rounded()))%"
    }
}

private struct XDRBrightnessSegments: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                segments(in: geometry.size)
                    .fill(Color.white)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: geometry.size.width * progress)
                    }
            }
            .clipShape(Capsule())
        }
    }

    private func segments(in size: CGSize) -> Path {
        let segmentWidth: CGFloat = (size.width - 15) / 16
        return Path { path in
            for index in 0..<16 {
                let x: CGFloat = CGFloat(index) * (segmentWidth + 1)
                path.addRect(CGRect(x: x, y: 0, width: segmentWidth, height: size.height))
            }
        }
    }
}

@MainActor
final class XDRBrightnessHUD {
    private let state = XDRBrightnessHUDState()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var alignmentTask: Task<Void, Never>?
    /// 最近一次量到的系統亮度提示框（全域座標、左上為原點）；之後我們的提示框疊在同一個位置
    private var nativeFrame: (display: UInt32, screenFrame: CGRect, rect: CGRect)?
    private var lastNativeKey = -Double.infinity
    private var lastNativeDismissal = -Double.infinity
    var geometryStatus: String {
        "frame=\(panel.map { NSStringFromRect($0.frame) } ?? "none"), native=\(nativeFrame.map { NSStringFromRect($0.rect) } ?? "fallback")"
    }

    /// 按了交給系統的亮度鍵後呼叫：系統提示框出現時讀它的位置（只讀視窗清單，不需要權限）
    func prepareAlignment(on screen: NSScreen, afterNativeKey: Bool = false) {
        guard afterNativeKey else { return }
        lastNativeKey = ProcessInfo.processInfo.systemUptime
        guard alignmentTask == nil,
              let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return }
        let frame = screen.frame
        let bounds = CGDisplayBounds(display)
        alignmentTask = Task { [weak self] in
            // 系統提示框要一點時間才出現
            try? await Task.sleep(for: .milliseconds(120))
            let rect = await Task.detached(priority: .userInitiated) { XDRNativeOSDFrame.capsule(on: bounds) }.value
            guard let self else { return }
            alignmentTask = nil
            guard !Task.isCancelled, let rect, screen.frame == frame else { return }
            nativeFrame = (display, frame, rect)
            if state.shown, panel?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 == display {
                positionPanel(on: screen)
            }
        }
    }

    private func positionPanel(on screen: NSScreen) {
        let origin: NSPoint
        if #available(macOS 26.0, *) {
            let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
            if let native = nativeFrame, native.display == display, native.screenFrame == screen.frame {
                // 全域座標（左上原點）換成 AppKit 座標（主螢幕左下原點）
                let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.maxY
                origin = NSPoint(x: native.rect.minX, y: primaryHeight - native.rect.maxY)
            } else {
                // 還沒看過系統提示框：macOS 27 實測右邊離螢幕邊緣 9.5 點、上邊在選單列下方 10 點
                origin = NSPoint(x: screen.frame.maxX - 9.5 - xdrHUDSize.width,
                                 y: screen.visibleFrame.maxY - 10 - xdrHUDSize.height)
            }
        } else {
            origin = NSPoint(x: screen.frame.midX - xdrHUDSize.width / 2, y: screen.visibleFrame.minY + 100)
        }
        panel?.setFrameOrigin(origin)
    }

    func show(screen: NSScreen, gain: Double, maximumGain: Double, nits: Int?) {
        hideTask?.cancel()
        if lastNativeKey > lastNativeDismissal,
           ProcessInfo.processInfo.systemUptime - lastNativeKey < 2,
           let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 {
            XDRNativeOSD.dismiss(display: display)
            lastNativeDismissal = lastNativeKey
        }
        state.maximumGain = maximumGain
        state.gain = XDRBrightnessPolicy.clamp(gain, maximum: maximumGain)
        state.nits = nits
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: xdrHUDSize),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.appearance = NSAppearance(named: .darkAqua)
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle,
                                        .canJoinAllApplications, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: XDRBrightnessHUDView(state: state))
            self.panel = panel
        }
        guard let panel else { return }
        positionPanel(on: screen)
        state.shown = true
        panel.orderFrontRegardless()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1250))
            guard !Task.isCancelled else { return }
            self?.state.shown = false
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        state.shown = false
        panel?.orderOut(nil)
    }
}

/// 系統亮度提示框所在的視窗（macOS 27：MenuBarAgent 的 367 × 160 視窗，提示框在裡面左 29.5、上 10 點）
private enum XDRNativeOSDFrame {
    static func capsule(on screenBounds: CGRect) -> CGRect? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows where window[kCGWindowOwnerName as String] as? String == "MenuBarAgent" {
            guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"], let height = bounds["Height"],
                  abs(width - 367) < 2, abs(height - 160) < 2 else { continue }
            let rect = CGRect(x: x + 29.5, y: y + 10, width: xdrHUDSize.width, height: xdrHUDSize.height)
            guard screenBounds.contains(CGPoint(x: rect.midX, y: rect.midY)) else { continue }
            return rect
        }
        return nil
    }
}

@MainActor
private enum XDRNativeOSD {
    private static let manager: NSObject? = {
        guard dlopen("/System/Library/PrivateFrameworks/OSD.framework/OSD", RTLD_LAZY) != nil,
              let type = NSClassFromString("OSDManager") as? NSObject.Type else { return nil }
        return type.perform(NSSelectorFromString("sharedManager"))?.takeUnretainedValue() as? NSObject
    }()

    static func dismiss(display: UInt32) {
        let selector = NSSelectorFromString("fadeClassicImageOnDisplay:")
        guard let manager, manager.responds(to: selector) else { return }
        typealias Fade = @convention(c) (NSObject, Selector, UInt32) -> Void
        let fade = unsafeBitCast(manager.method(for: selector), to: Fade.self)
        fade(manager, selector, display)
    }
}
