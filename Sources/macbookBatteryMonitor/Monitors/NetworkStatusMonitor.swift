import Foundation
import Network
import Combine

/// 網路面板的連線狀態（判斷在 NetworkStatus）。面板打開時才開始監看系統的網路路徑，關掉就停，不連到外部伺服器
@MainActor
final class NetworkStatusMonitor: ObservableObject {
    static let shared = NetworkStatusMonitor()

    @Published private(set) var vpnInterfaces: [String] = []
    @Published private(set) var notes: [String] = []
    private var monitor: NWPathMonitor?
    /// 正在顯示的卡片數：面板關掉又馬上打開時，舊卡片晚到的 onDisappear 不會把新卡片的監看停掉
    private var viewers = 0

    func start() {
        viewers += 1
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let available = path.status == .satisfied, constrained = path.isConstrained, expensive = path.isExpensive
            DispatchQueue.main.async {
                MainActor.assumeIsolatedCompat { NetworkStatusMonitor.shared.update(available: available, constrained: constrained, expensive: expensive) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.kuan.batterymonitor.networkStatus", qos: .utility))
        self.monitor = monitor
    }

    func stop() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        monitor?.cancel()
        monitor = nil
    }

    private func update(available: Bool, constrained: Bool, expensive: Bool) {
        notes = NetworkStatus.notes(available: available, constrained: constrained, expensive: expensive)
        vpnInterfaces = NetworkStatus.vpnInterfaces(Self.addresses())
    }

    /// 每個介面的 IPv4／IPv6 位址
    nonisolated static func addresses() -> [NetworkStatus.Address] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var result: [NetworkStatus.Address] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let sockaddr = entry.ifa_addr, [AF_INET, AF_INET6].contains(Int32(sockaddr.pointee.sa_family)) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sockaddr, socklen_t(sockaddr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            result.append(.init(interface: String(cString: entry.ifa_name), address: String(cString: host)))
        }
        return result
    }
}
