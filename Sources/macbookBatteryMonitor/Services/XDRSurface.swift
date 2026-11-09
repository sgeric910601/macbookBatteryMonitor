import AppKit
import MetalKit

// EDR multiply overlay adapted from XDR Boost, Copyright (c) 2026 Pieter Levels, MIT.
// Full license: docs/licenses/xdr-boost.txt.
@MainActor
final class XDRSurface: NSObject, MTKViewDelegate {
    private let window: NSWindow
    private let view: MTKView
    private let queue: MTLCommandQueue
    private(set) var renderedFrames = 0
    private(set) var completedFrames = 0
    var visible: Bool { window.isVisible }

    init?(screen: NSScreen) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.level = .screenSaver
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .canJoinAllApplications, .fullScreenAuxiliary]
        view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size), device: device)
        view.colorPixelFormat = .rgba16Float
        view.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        view.preferredFramesPerSecond = 5
        view.clearColor = MTLClearColor(red: 1.15, green: 1.15, blue: 1.15, alpha: 1)
        guard let layer = view.layer as? CAMetalLayer else { return nil }
        layer.isOpaque = false
        layer.wantsExtendedDynamicRangeContent = true
        layer.compositingFilter = "multiply"
        window.contentView = view
        super.init()
        view.delegate = self
        view.isPaused = true
    }

    func start() {
        window.orderFrontRegardless()
        view.isPaused = false
        view.draw()
    }

    func setGain(_ value: Double) {
        let gain = XDRBrightnessPolicy.clamp(value)
        view.clearColor = MTLClearColor(red: gain, green: gain, blue: gain, alpha: 1)
        view.draw()
    }

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        command.present(drawable)
        command.addCompletedHandler { [weak self] buffer in
            let success = buffer.status == .completed
            Task { @MainActor in
                if success { self?.completedFrames += 1 }
            }
        }
        command.commit()
        renderedFrames += 1
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func stop() {
        view.isPaused = true
        window.orderOut(nil)
    }
}
