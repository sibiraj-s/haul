import Foundation
import Network
import Security
import Synchronization

/// How downloads reach the internet.
nonisolated enum ProxyMode: String, CaseIterable, Sendable {
    /// Whatever System Settings → Network says, including automatic proxy configuration.
    case system
    /// Connect directly, even when the system has a proxy set.
    case none
    case custom
}

nonisolated enum ProxyKind: String, CaseIterable, Sendable {
    case http, socks

    var defaultPort: Int { self == .http ? 8080 : 1080 }
}

/// The proxy settings as the download sessions see them. `AppSettings` publishes a fresh
/// copy whenever one changes; sessions read it when they're made, so a change applies to
/// downloads as they start or resume.
nonisolated struct ProxySettings: Sendable, Equatable {
    var mode: ProxyMode = .system
    var kind: ProxyKind = .http
    var host = ""
    var port = ProxyKind.http.defaultPort
    var username = ""
    var password = ""
    /// Hosts that skip the proxy.
    var bypass: [String] = []

    private static let stored = Mutex(ProxySettings())

    static var current: ProxySettings {
        get { stored.withLock { $0 } }
        set { stored.withLock { $0 = newValue } }
    }

    /// The bypass list as typed: hosts separated by commas, spaces or new lines.
    static func hosts(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
    }

    /// The custom proxy's address; nil while the server or port isn't filled in properly.
    var endpoint: NWEndpoint? {
        let host = host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, (1...65535).contains(port), let port = NWEndpoint.Port(rawValue: UInt16(port)) else { return nil }
        return .hostPort(host: .init(host), port: port)
    }

    /// Points a session at the proxy. A custom proxy that isn't filled in yet leaves the
    /// system's settings in place rather than failing every download.
    func apply(to config: URLSessionConfiguration) {
        switch mode {
        case .system:
            break
        case .none:
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: false,
                kCFNetworkProxiesHTTPSEnable as String: false,
                kCFNetworkProxiesSOCKSEnable as String: false,
                kCFNetworkProxiesProxyAutoConfigEnable as String: false,
                kCFNetworkProxiesProxyAutoDiscoveryEnable as String: false,
            ]
        case .custom:
            guard let endpoint else { return }
            var proxy = kind == .http ? ProxyConfiguration(httpCONNECTProxy: endpoint) : ProxyConfiguration(socksv5Proxy: endpoint)
            if !username.isEmpty { proxy.applyCredential(username: username, password: password) }
            proxy.excludedDomains = bypass
            config.proxyConfigurations = [proxy]
        }
    }

    /// A session configuration for downloads, going through the current proxy.
    static func sessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        current.apply(to: config)
        return config
    }
}

/// The custom proxy's password, kept in the Keychain rather than in preferences.
nonisolated enum ProxyPassword {
    private static let item: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "\(Bundle.main.bundleIdentifier ?? "dev.sibiraj.haul").proxy",
        kSecAttrAccount as String: "proxy",
    ]

    static func read() -> String {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Saves the password; an empty one removes it.
    static func save(_ password: String) {
        SecItemDelete(item as CFDictionary)
        guard !password.isEmpty else { return }
        var add = item
        add[kSecAttrLabel as String] = "Haul proxy password"
        add[kSecValueData as String] = Data(password.utf8)
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess { NSLog("Haul: couldn't save the proxy password: \(status)") }
    }
}
