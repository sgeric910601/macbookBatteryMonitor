/// 網路面板的連線狀態：VPN、低數據模式、按流量計費。只看本機的介面與系統的網路路徑，不連到任何外部伺服器
enum NetworkStatus {
    struct Address: Equatable {
        let interface: String
        /// 位址字串（IPv6 本機連結位址會帶 %介面）
        let address: String
    }

    /// 通道介面的名稱開頭：WireGuard、OpenVPN 等用 utun，IPSec 用 ipsec，PPTP／L2TP 用 ppp
    private static let tunnelPrefixes = ["utun", "ipsec", "ppp", "tun", "tap"]

    /// 有可用位址的通道介面。系統自己也會開 utun（iCloud 私密轉送、接續互通），只有 fe80 本機連結位址，不算 VPN
    static func vpnInterfaces(_ addresses: [Address]) -> [String] {
        var seen: [String] = []
        for entry in addresses where tunnelPrefixes.contains(where: entry.interface.hasPrefix) {
            guard !entry.address.lowercased().hasPrefix("fe80"), !seen.contains(entry.interface) else { continue }
            seen.append(entry.interface)
        }
        return seen
    }

    static func notes(available: Bool, constrained: Bool, expensive: Bool) -> [String] {
        guard available else { return ["系統判斷目前沒有可用的網路"] }
        var notes: [String] = []
        if constrained { notes.append("低數據模式") }
        if expensive { notes.append("按流量計費（例如手機熱點）") }
        return notes
    }
}
