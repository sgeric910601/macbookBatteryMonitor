import Foundation
import Network
import Observation

/// 網路面板的連線狀態（判斷在 NetworkStatus）。面板打開時才開始監看系統的網路路徑，關掉就停，不連到外部伺服器
@MainActor
@Observable
final class NetworkStatusMonitor {
    static let shared = NetworkStatusMonitor()

    private(set) var vpnInterfaces: [String] = []
    private(set) var notes: [String] = []
    @ObservationIgnored private var monitor: NWPathMonitor?

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let available = path.status == .satisfied, constrained = path.isConstrained, expensive = path.isExpensive
            DispatchQueue.main.async {
                MainActor.assumeIsolated { NetworkStatusMonitor.shared.update(available: available, constrained: constrained, expensive: expensive) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.kuan.batterymonitor.networkStatus", qos: .utility))
        self.monitor = monitor
    }

    func stop() {
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
