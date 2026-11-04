import Foundation
import Network
import Testing

@testable import Haul

struct ProxyTests {
    private func custom(_ host: String, port: Int = 8080) -> ProxySettings {
        ProxySettings(mode: .custom, host: host, port: port)
    }

    @Test func bypassListSplitsOnCommasAndSpaces() {
        #expect(ProxySettings.hosts("localhost, example.com\nintranet  ,,") == ["localhost", "example.com", "intranet"])
        #expect(ProxySettings.hosts("  ").isEmpty)
    }

    @Test func endpointNeedsServerAndValidPort() {
        #expect(custom("proxy.example.com").endpoint != nil)
        #expect(custom(" proxy.example.com ").endpoint != nil)
        #expect(custom("").endpoint == nil)
        #expect(custom("   ").endpoint == nil)
        #expect(custom("proxy.example.com", port: 0).endpoint == nil)
        #expect(custom("proxy.example.com", port: 70_000).endpoint == nil)
    }

    @Test func goesThroughProxyOnlyWhenOneIsUsed() {
        let systemProxy: [String: Any] = ["HTTPSEnable": 1]
        #expect(custom("proxy.example.com").goesThroughProxy(system: [:]))
        #expect(!custom("").goesThroughProxy(system: [:]))
        #expect(!ProxySettings(mode: .none).goesThroughProxy(system: systemProxy))
        #expect(ProxySettings(mode: .system).goesThroughProxy(system: systemProxy))
        // A custom proxy that isn't filled in leaves the system's in place, so that one counts.
        #expect(custom("").goesThroughProxy(system: systemProxy))
    }

    @Test func systemProxyCountsAnyKindTurnedOn() {
        #expect(!ProxySettings.hasProxy([:]))
        #expect(!ProxySettings.hasProxy(["HTTPEnable": 0, "HTTPSEnable": 0, "ExceptionsList": ["*.local"]]))
        #expect(ProxySettings.hasProxy(["HTTPSEnable": 1]))
        #expect(ProxySettings.hasProxy(["SOCKSEnable": 1]))
        #expect(ProxySettings.hasProxy(["ProxyAutoConfigEnable": 1]))
        #expect(ProxySettings.hasProxy(["ProxyAutoDiscoveryEnable": 1]))
    }

    @Test func systemLeavesSessionAlone() {
        let config = URLSessionConfiguration.default
        ProxySettings().apply(to: config)
        #expect(config.connectionProxyDictionary == nil)
        #expect(config.proxyConfigurations.isEmpty)
    }

    @Test func noneTurnsEveryProxyOff() {
        let config = URLSessionConfiguration.default
        ProxySettings(mode: .none).apply(to: config)
        let proxies = config.connectionProxyDictionary ?? [:]
        #expect(proxies[kCFNetworkProxiesHTTPEnable as String] as? Bool == false)
        #expect(proxies[kCFNetworkProxiesHTTPSEnable as String] as? Bool == false)
        #expect(proxies[kCFNetworkProxiesSOCKSEnable as String] as? Bool == false)
        #expect(proxies[kCFNetworkProxiesProxyAutoConfigEnable as String] as? Bool == false)
    }

    @Test func customSetsOneProxy() {
        for kind in ProxyKind.allCases {
            let config = URLSessionConfiguration.default
            var proxy = custom("proxy.example.com")
            proxy.kind = kind
            proxy.username = "me"
            proxy.password = "secret"
            proxy.bypass = ["localhost"]
            proxy.apply(to: config)
            #expect(config.proxyConfigurations.count == 1)
            #expect(config.proxyConfigurations.first.map(excluded) == ["localhost"])
        }
    }

    /// Read through the C API: the Swift `excludedDomains` getter always returns [], though setting it works.
    private func excluded(_ proxy: ProxyConfiguration) -> [String] {
        var domains: [String] = []
        nw_proxy_config_enumerate_excluded_domains(proxy._nw) { domains.append(String(cString: $0)) }
        return domains
    }

    @Test func unfinishedCustomFallsBackToSystem() {
        let config = URLSessionConfiguration.default
        custom("").apply(to: config)
        #expect(config.proxyConfigurations.isEmpty)
        #expect(config.connectionProxyDictionary == nil)
    }
}
