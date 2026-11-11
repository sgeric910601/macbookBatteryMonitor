import AppKit
import SwiftUI
import Observation

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
        HStack(spacing: 13) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 23, weight: .medium))
            VStack(spacing: 7) {
                HStack {
                    Text("XDR 亮度").font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 8)
                    if let nits = state.nits {
                        Text("估算 \(nits) nits")
                            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    } else {
                        Text("\(Int((state.gain * 100).rounded()))%")
                            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    }
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.16))
                        Capsule().fill(Color.primary)
                            .frame(width: geometry.size.width * state.progress)
                    }
                }
                .frame(height: 5)
                .animation(.easeOut(duration: 0.1), value: state.gain)
                .accessibilityLabel("XDR 增亮")
                .accessibilityValue("\(Int((state.gain * 100).rounded()))%")
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 320, height: 72)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .opacity(state.shown ? 1 : 0)
        .animation(.easeOut(duration: 0.18), value: state.shown)
    }
}

@MainActor
final class XDRBrightnessHUD {
    private let state = XDRBrightnessHUDState()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(screen: NSScreen, gain: Double, maximumGain: Double, nits: Int?) {
        hideTask?.cancel()
        state.maximumGain = maximumGain
        state.gain = XDRBrightnessPolicy.clamp(gain, maximum: maximumGain)
        state.nits = nits
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 72),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
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
        let frame = screen.visibleFrame
        let origin: NSPoint
        if #available(macOS 26.0, *) {
            origin = NSPoint(x: frame.maxX - 338, y: frame.maxY - 90)
        } else {
            origin = NSPoint(x: frame.midX - 160, y: frame.minY + 100)
        }
        panel.setFrameOrigin(origin)
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
