import AppKit
import SwiftUI
import Observation

private let xdrHUDSize = CGSize(width: 290, height: 62)

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
        VStack(spacing: 5) {
            HStack {
                Text("XDR 亮度").font(.system(size: 12, weight: .medium))
                Spacer(minLength: 8)
                if let nits = state.nits {
                    Text("估算 \(nits) nits")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                } else {
                    Text("\(Int((state.gain * 100).rounded()))%")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "sun.min.fill")
                    .foregroundStyle(.secondary)
                Slider(value: .constant(state.progress), in: 0...1)
                    .controlSize(.small)
                    .tint(Color.primary)
                    .accessibilityLabel("XDR 增亮")
                    .accessibilityValue("\(Int((state.gain * 100).rounded()))%")
                Image(systemName: "sun.max.fill")
            }
            .font(.system(size: 13, weight: .medium))
            .frame(height: 20)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .frame(width: xdrHUDSize.width, height: xdrHUDSize.height)
        .background {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial)
            }
        }
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

    func show(screen: NSScreen, gain: Double, maximumGain: Double, nits: Int?) {
        hideTask?.cancel()
        state.maximumGain = maximumGain
        state.gain = XDRBrightnessPolicy.clamp(gain, maximum: maximumGain)
        state.nits = nits
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: xdrHUDSize),
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
            origin = NSPoint(x: screen.frame.maxX - xdrHUDSize.width - 10,
                             y: frame.maxY - xdrHUDSize.height - 10)
        } else {
            origin = NSPoint(x: screen.frame.midX - xdrHUDSize.width / 2, y: frame.minY + 100)
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
