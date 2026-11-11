import AppKit
import SwiftUI
import Observation
import ApplicationServices

private let xdrHUDSize = CGSize(width: 308, height: 92)

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
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 27, weight: .regular))
                    .frame(width: 27)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.22))
                        Path { path in
                            let segmentWidth = (geometry.size.width - 15) / 16
                            for index in 0..<16 {
                                path.addRect(CGRect(x: CGFloat(index) * (segmentWidth + 1), y: 0,
                                                    width: segmentWidth, height: geometry.size.height))
                            }
                        }
                        .fill(Color.white)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: geometry.size.width * state.progress)
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 4)
                .accessibilityLabel("XDR 增亮")
                .accessibilityValue("\(Int((state.gain * 100).rounded()))%")
            }
            .foregroundStyle(Color.white)
            .padding(.leading, 24)
            .padding(.trailing, 31)
            .frame(width: xdrHUDSize.width, height: 66)
            .background {
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(.clear, in: Capsule())
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            Group {
                if let nits = state.nits {
                    Text("估算 \(nits) nits")
                } else {
                    Text("XDR \(Int((state.gain * 100).rounded()))%")
                }
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .frame(width: xdrHUDSize.width, height: xdrHUDSize.height)
        .environment(\.colorScheme, .dark)
        .opacity(state.shown ? 1 : 0)
        .animation(.easeOut(duration: 0.1), value: state.gain)
        .animation(.easeOut(duration: 0.18), value: state.shown)
    }
}

@MainActor
final class XDRBrightnessHUD {
    private let state = XDRBrightnessHUDState()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var alignmentTask: Task<Void, Never>?
    private var lastAlignmentRequest = -Double.infinity
    private var menuAnchor: (display: UInt32, screenFrame: CGRect, x: CGFloat)?
    private var lastNativeKey = -Double.infinity
    private var lastNativeDismissal = -Double.infinity
    var geometryStatus: String {
        "frame=\(panel.map { NSStringFromRect($0.frame) } ?? "none"), anchor=\(menuAnchor?.x.description ?? "fallback")"
    }

    func prepareAlignment(on screen: NSScreen, afterNativeKey: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        if afterNativeKey { lastNativeKey = now }
        guard alignmentTask == nil, now - lastAlignmentRequest >= 0.5,
              let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return }
        lastAlignmentRequest = now
        let frame = screen.frame
        let bounds = CGDisplayBounds(display)
        let processes = ["com.apple.controlcenter", "com.apple.systemuiserver"].flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).map(\.processIdentifier)
        }
        alignmentTask = Task { [weak self] in
            if afterNativeKey { try? await Task.sleep(for: .milliseconds(120)) }
            let x = await Task.detached(priority: .userInitiated) {
                XDRHUDMenuAnchor.centerX(processes: processes, screenBounds: bounds)
            }.value
            guard let self else { return }
            alignmentTask = nil
            guard !Task.isCancelled, let x, screen.frame == frame else { return }
            menuAnchor = (display, frame, x)
            if state.shown, panel?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 == display {
                positionPanel(on: screen)
            }
        }
    }

    private func positionPanel(on screen: NSScreen) {
        let frame = screen.visibleFrame
        let origin: NSPoint
        if #available(macOS 26.0, *) {
            let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
            let anchor = menuAnchor.flatMap { $0.display == display && $0.screenFrame == screen.frame ? $0.x : nil }
                ?? screen.frame.maxX - 196
            let x = min(screen.frame.maxX - xdrHUDSize.width - 10,
                        max(screen.frame.minX + 10, anchor - xdrHUDSize.width / 2))
            origin = NSPoint(x: x, y: frame.maxY - xdrHUDSize.height - 10)
        } else {
            origin = NSPoint(x: screen.frame.midX - xdrHUDSize.width / 2, y: frame.minY + 100)
        }
        panel?.setFrameOrigin(origin)
    }

    func show(screen: NSScreen, gain: Double, maximumGain: Double, nits: Int?) {
        hideTask?.cancel()
        prepareAlignment(on: screen)
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


private enum XDRHUDMenuAnchor {
    static func centerX(processes: [pid_t], screenBounds: CGRect) -> CGFloat? {
        var clockLeft: CGFloat?
        for pid in processes {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.05)
            for attribute in [kAXExtrasMenuBarAttribute, kAXMenuBarAttribute] {
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(application, attribute as CFString, &value) == .success,
                      let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { continue }
                let menu = value as! AXUIElement
                for item in AX.array(menu, kAXChildrenAttribute) {
                    let identifier = (AX.string(item, kAXIdentifierAttribute) ?? "").lowercased()
                    let description = AX.string(item, kAXDescriptionAttribute) ?? ""
                    let isDisplay = identifier.contains("menuextra.display") || identifier.hasSuffix(".display")
                        || identifier == "display" || ["顯示器", "Display", "Displays"].contains(description)
                    let isClock = identifier.contains("menuextra.clock") || identifier.hasSuffix(".clock") || identifier == "clock"
                    guard isDisplay || isClock, let rect = frame(of: item), rect.width > 0,
                          screenBounds.contains(CGPoint(x: rect.midX, y: rect.midY)) else { continue }
                    if isDisplay { return rect.midX }
                    clockLeft = rect.minX
                }
            }
        }
        // The beta displays its temporary display item immediately before the clock.
        return clockLeft.map { $0 - 24 }
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
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
