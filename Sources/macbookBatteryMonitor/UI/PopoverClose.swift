import AppKit

extension NSPopover {
    /// 關閉面板。App 不在前景時（例如從第二條狀態列、桌面寵物打開，或正在用別的 App），macOS 會把關閉動畫
    /// 延到 App 回到前景才做，performClose 與 close 都關不掉；這時關掉動畫直接關。
    /// animated: false 用在接著要切換 App 前景狀態的地方（例如打開設定視窗），動畫會被打斷
    func closeNow(animated: Bool = true) {
        guard isShown else { return }
        if animated, NSApp.isActive {
            performClose(nil)
        } else {
            animates = false
            close()
        }
    }
}
