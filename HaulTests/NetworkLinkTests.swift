import Foundation
import Network
import Testing

@testable import Haul

struct NetworkLinkTests {
    private let wifi = NetworkLink(name: "en0", type: .wifi, metered: false, router: "68:7f:f0:1d:34:0")
    /// A Pixel on USB tethering: wired, and metered only by its DHCP lease.
    private let pixel = NetworkLink(name: "en9", type: .wiredEthernet, metered: true, router: "7a:bd:56:d6:75:e6")
    private let ethernet = NetworkLink(name: "en7", type: .wiredEthernet, metered: false, router: "a4:91:b1:2:c3:7")

    private func names(_ links: [NetworkLink], vpn: Bool = false, proxy: Bool = false, allowMetered: Bool = false) -> [String] {
        NetworkLink.usable(links, vpn: vpn, proxy: proxy, allowMetered: allowMetered).map(\.name)
    }

    @Test func meteredLinksNeedPermission() {
        #expect(names([pixel, wifi]) == ["en0"])
        #expect(names([pixel, wifi], allowMetered: true) == ["en9", "en0"])
    }

    @Test func unmeteredLinksAreAllUsed() {
        #expect(names([ethernet, wifi]) == ["en7", "en0"])
    }

    @Test func noneBehindAVPNOrProxy() {
        #expect(names([ethernet, wifi], vpn: true).isEmpty)
        #expect(names([ethernet, wifi], proxy: true).isEmpty)
    }

    @Test func oneLinkPerRouter() {
        let sameRouter = NetworkLink(name: "en7", type: .wiredEthernet, metered: false, router: "68:7f:f0:1d:34:0")
        #expect(names([sameRouter, wifi]) == ["en7"])
    }

    @Test func linksWithoutALeaseAreKept() {
        let staticAddress = NetworkLink(name: "en7", type: .wiredEthernet, metered: false, router: nil)
        let other = NetworkLink(name: "en8", type: .wiredEthernet, metered: false, router: nil)
        #expect(names([staticAddress, other, wifi]) == ["en7", "en8", "en0"])
    }

    @Test func eachInterfaceCountsOnce() {
        #expect(names([wifi, wifi, ethernet]) == ["en0", "en7"])
    }

    @Test func onlyWiFiAndWiredLinks() {
        let tunnel = NetworkLink(name: "utun4", type: .other, metered: false, router: nil)
        let loopback = NetworkLink(name: "lo0", type: .loopback, metered: false, router: nil)
        #expect(names([tunnel, loopback, wifi]) == ["en0"])
    }
}

struct NetworkLeaseTests {
    @Test func androidLeaseIsMetered() {
        let output = """
            op = BOOTREPLY
            router (ip_mult): {10.205.163.8}
            vendor_specific (opaque):\u{20}
            0000  41 4e 44 52 4f 49 44 5f  4d 45 54 45 52 45 44     ANDROID_METERED\u{20}

            end (none):\u{20}
            """
        let lease = NetworkLease.parse(output)
        #expect(lease.router == "10.205.163.8")
        #expect(lease.metered)
    }

    @Test func markerWrappedAcrossLinesIsFound() {
        let output = """
            vendor_specific (opaque):
            0000  00 41 4e 44 52 4f 49 44  5f 4d 45 54 45 52 45 44   .ANDROID_METERE
            0010  00                                                 .
            """
        #expect(NetworkLease.parse(output).metered)
    }

    @Test func routerHardwareAddressFromARP() {
        let output = """
            ? (192.168.1.1) at 68:7f:f0:1d:34:0 on en0 ifscope [ethernet]
            ? (192.168.1.10) at (incomplete) on en0 ifscope [ethernet]
            ? (192.168.1.100) at 3c:22:fb:1:2:3 on en0 ifscope [ethernet]
            """
        #expect(NetworkLease.hardwareAddress(of: "192.168.1.1", in: output) == "68:7f:f0:1d:34:0")
        #expect(NetworkLease.hardwareAddress(of: "192.168.1.10", in: output) == nil)
        #expect(NetworkLease.hardwareAddress(of: "192.168.1.2", in: output) == nil)
    }

    @Test func homeRouterLeaseIsNotMetered() {
        let lease = NetworkLease.parse("router (ip_mult): {192.168.1.1}\ndomain_name_server (ip_mult): {192.168.1.1}")
        #expect(lease.router == "192.168.1.1")
        #expect(!lease.metered)
    }
}
