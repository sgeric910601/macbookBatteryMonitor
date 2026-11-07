import AppKit

/// 選到某個視窗時，在它原本的位置顯示它的畫面，放在切換器後面、其他視窗前面，讓使用者先看到會切到什麼。
/// 只是一張圖，不接收滑鼠與鍵盤；切換器結束就收起來
@MainActor
final class WindowPreview {
    static let shared = WindowPreview()

    private let panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        let view = NSImageView()
        view.imageScaling = .scaleAxesIndependently
        panel.contentView = view
        return panel
    }()
    private var shownID: UInt32?

    private var imageView: NSImageView? { panel.contentView as? NSImageView }

    /// frame 是左上角為原點的全域座標；畫面換成這個視窗的（同一個視窗再呼叫只更新圖片）
    func show(id: UInt32, frame: CGRect, image: CGImage) {
        guard frame.width > 1, frame.height > 1, let primary = NSScreen.screens.first else { return }
        var cocoa = frame
        cocoa.origin.y = primary.frame.maxY - frame.maxY
        panel.setFrame(cocoa, display: false)
        imageView?.image = NSImage(cgImage: image, size: cocoa.size)
        if shownID != id || !panel.isVisible {
            shownID = id
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }
    }

    /// 選到的視窗換了、新的畫面還沒到：先收起舊的，免得顯示別的視窗
    func hide() {
        shownID = nil
        panel.orderOut(nil)
        imageView?.image = nil
    }
}
