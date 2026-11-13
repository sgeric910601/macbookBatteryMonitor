import AppKit
import MetalKit

// EDR 乘算覆蓋層改編自 XDR Boost，Copyright (c) 2026 Pieter Levels，MIT 授權。
// 完整授權：docs/licenses/xdr-boost.txt。
@MainActor
final class XDRSurface: NSObject, MTKViewDelegate {
    private let window: NSWindow
    private let view: MTKView
    private let queue: MTLCommandQueue
    private var presentation = XDRPresentationGate()
    private var presentationToken: UUID?
    private(set) var presentedFrames = 0
    private(set) var revealed = false
    private(set) var renderedFrames = 0
    private(set) var completedFrames = 0
    var visible: Bool { window.isVisible && revealed }
    var drawableStatus: String { "\(Int(view.drawableSize.width))×\(Int(view.drawableSize.height))" }

    init?(screen: NSScreen, gain: Double = 1.15) {
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
        // 畫面是均勻純色，不需依螢幕解析度配置浮點紋理，由合成器放大即可。
        view.autoResizeDrawable = false
        view.drawableSize = CGSize(width: 2, height: 2)
        let initialGain = XDRBrightnessPolicy.clamp(gain, maximum: XDRBrightnessPolicy.absoluteMaximumGain)
        view.clearColor = MTLClearColor(red: initialGain, green: initialGain, blue: initialGain, alpha: 1)
        guard let layer = view.layer as? CAMetalLayer else { return nil }
        layer.isOpaque = false
        layer.wantsExtendedDynamicRangeContent = true
        // 首張 drawable 尚未呈現時，Metal 圖層保持透明；白色乘算底層是亮度的單位值。
        // 讓全螢幕視窗先有安全內容，避免未初始化的黑色畫面參與桌面乘算。
        let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.white.cgColor
        content.layer?.compositingFilter = "multiply"
        view.alphaValue = 0
        view.autoresizingMask = [.width, .height]
        content.addSubview(view)
        window.contentView = content
        super.init()
        view.delegate = self
        view.isPaused = true
    }

    func start() {
        presentationToken = presentation.begin()
        revealed = false
        view.alphaValue = 0
        window.orderFrontRegardless()
        view.isPaused = false
        view.draw()
    }

    func setGain(_ value: Double) {
        let gain = XDRBrightnessPolicy.clamp(value, maximum: XDRBrightnessPolicy.absoluteMaximumGain)
        view.clearColor = MTLClearColor(red: gain, green: gain, blue: gain, alpha: 1)
        view.draw()
    }

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        if let token = presentationToken {
            drawable.addPresentedHandler { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.presentation.canReveal(token) else { return }
                    self.presentedFrames += 1
                    guard !self.revealed else { return }
                    // 不做淡入：乘算畫面只在首張已呈現後一次切入，避免中間亮度跳動。
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    self.view.alphaValue = 1
                    self.revealed = true
                    CATransaction.commit()
                }
            }
        }
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
        presentation.stop()
        presentationToken = nil
        revealed = false
        view.alphaValue = 0
        view.isPaused = true
        window.orderOut(nil)
    }
}
