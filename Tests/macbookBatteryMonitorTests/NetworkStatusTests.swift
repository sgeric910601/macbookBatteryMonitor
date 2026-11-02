import Foundation

struct NetworkStatusTests {
    private func addr(_ name: String, _ address: String) -> NetworkStatus.Address { .init(interface: name, address: address) }

    /// VPN：utun、ipsec、ppp 等通道介面上有可用的位址才算；系統自己的 utun（只有 fe80 本機連結位址）不算
    func testDetectsVPN() {
        XCTAssertEqual(NetworkStatus.vpnInterfaces([addr("en0", "192.168.1.20"), addr("utun3", "10.8.0.2")]), ["utun3"])
        XCTAssertEqual(NetworkStatus.vpnInterfaces([addr("ipsec0", "172.16.0.5"), addr("ppp0", "10.0.0.9")]), ["ipsec0", "ppp0"])
        XCTAssertEqual(NetworkStatus.vpnInterfaces([addr("utun0", "fe80::1%utun0"), addr("utun1", "fe80::abcd%utun1")]), [])
        XCTAssertEqual(NetworkStatus.vpnInterfaces([addr("utun4", "fd00:1234::2")]), ["utun4"])
        XCTAssertEqual(NetworkStatus.vpnInterfaces([addr("en0", "10.8.0.2"), addr("bridge0", "10.0.0.1")]), [])
        // 同一個介面有好幾個位址只列一次
        XCTAssertEqual(NetworkStatus.vpnInterfaces([addr("utun3", "10.8.0.2"), addr("utun3", "fd00::2")]), ["utun3"])
    }

    /// 面板上的說明：低數據模式、按流量計費、沒有網路
    func testSummary() {
        XCTAssertEqual(NetworkStatus.notes(available: true, constrained: true, expensive: true), ["低數據模式", "按流量計費（例如手機熱點）"])
        XCTAssertEqual(NetworkStatus.notes(available: true, constrained: false, expensive: false), [])
        XCTAssertEqual(NetworkStatus.notes(available: false, constrained: false, expensive: false), ["系統判斷目前沒有可用的網路"])
    }
}
