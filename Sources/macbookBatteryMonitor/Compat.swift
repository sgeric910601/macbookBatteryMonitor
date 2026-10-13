import AppKit
import SwiftUI

// 舊系統版本（macOS 12 起）用的相容寫法：主版本用到的 macOS 13／14 API，在這裡依系統版本分流

enum Compat {
    /// 測試用：啟動參數加 --macos12-paths（或環境變數 MBM_MACOS12_PATHS=1），
    /// 在較新的系統上也走 macOS 12 的備援寫法，不必真的裝 macOS 12 才能測
    static let forceMacOS12Paths = CommandLine.arguments.contains("--macos12-paths")
        || ProcessInfo.processInfo.environment["MBM_MACOS12_PATHS"] == "1"
}

extension MainActor {
    /// MainActor.assumeIsolated 要 macOS 14：呼叫端已確定在主執行緒上（主佇列的回呼、計時器）
    static func assumeIsolatedCompat<T>(_ operation: @MainActor () throws -> T) rethrows -> T {
        if #available(macOS 14, *), !Compat.forceMacOS12Paths { return try MainActor.assumeIsolated(operation) }
        precondition(Thread.isMainThread, "必須在主執行緒呼叫")
        return try withoutActuallyEscaping(operation) { operation in
            try unsafeBitCast(operation, to: (() throws -> T).self)()
        }
    }
}

extension NSApplication {
    /// activate() 要 macOS 14
    func activateCompat() {
        if #available(macOS 14, *), !Compat.forceMacOS12Paths {
            activate()
        } else {
            activate(ignoringOtherApps: true)
        }
    }
}

/// macOS 13 起可以設 sizingOptions，讓面板跟著 SwiftUI 內容大小改變；
/// macOS 12 沒有，每次排版後用內容的理想大小更新 preferredContentSize，面板才會跟著換頁變大變小
final class SizingHostingController<Content: View>: NSHostingController<Content> {
    override init(rootView: Content) {
        super.init(rootView: rootView)
        if #available(macOS 13, *), !Compat.forceMacOS12Paths { sizingOptions = [.preferredContentSize] }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLayout() {
        super.viewDidLayout()
        if #available(macOS 13, *), !Compat.forceMacOS12Paths { return }
        let size = view.fittingSize
        if size.width > 0, size.height > 0, preferredContentSize != size { preferredContentSize = size }
    }
}

extension View {
    /// scrollBounceBehavior 要 macOS 13.3：內容放得下時不回彈
    @ViewBuilder func bounceOnlyWhenScrollable() -> some View {
        if #available(macOS 13.3, *), !Compat.forceMacOS12Paths {
            scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }
}

/// ContentUnavailableView 要 macOS 14：圖示、標題與說明置中
struct UnavailableMessage: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(description)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// 有些 SF Symbols 名稱是 macOS 13／14 才加入（例如 battery.75percent），macOS 12 上會是空白：改用舊名稱
enum SymbolCompat {
    private static let fallbacks: [String: String] = [
        "battery.0percent": "battery.0", "battery.25percent": "battery.25", "battery.50percent": "battery.50",
        "battery.75percent": "battery.75", "battery.100percent": "battery.100", "battery.100percent.bolt": "battery.100.bolt",
        "gauge.with.dots.needle.33percent": "speedometer", "thermometer.medium": "thermometer",
    ]
    private static var resolved: [String: String] = [:]

    static func name(_ preferred: String) -> String {
        guard let fallback = fallbacks[preferred] else { return preferred }
        if let cached = resolved[preferred] { return cached }
        let available = !Compat.forceMacOS12Paths && NSImage(systemSymbolName: preferred, accessibilityDescription: nil) != nil
        let name = available ? preferred : fallback
        resolved[preferred] = name
        return name
    }
}
