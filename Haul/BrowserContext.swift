import Foundation

/// What the browser would have sent with a link: the page it was on, its User-Agent, and the
/// site's cookies. The Safari extension passes it along so links that need the user's sign-in
/// download as they would in Safari. It comes in a haul://add link, which any web page can
/// open, so it's checked here, and it only ever goes to the link it came with.
nonisolated struct BrowserContext: Codable, Equatable, Sendable {
    /// The page the link was on; sent as the Referer.
    var page: URL?
    var userAgent: String?
    var cookies: [Cookie] = []

    struct Cookie: Codable, Equatable, Sendable {
        var name: String
        var value: String
        var domain: String
        var path: String?
        var secure: Bool?
        /// Sent only to `domain` itself, not its subdomains.
        var hostOnly: Bool?
        /// Seconds since 1970; nil for a cookie that lasts the browser session.
        var expires: Double?
    }

    static let maxCookies = 300

    var isEmpty: Bool { page == nil && userAgent == nil && cookies.isEmpty }

    /// Reads the `context` item of a haul://add link: JSON from the extension. Anything that
    /// isn't safe to send as a header is dropped.
    static func decode(_ json: String) -> BrowserContext? {
        guard var context = try? JSONDecoder().decode(BrowserContext.self, from: Data(json.utf8)) else { return nil }
        if let page = context.page, !["http", "https"].contains(page.scheme?.lowercased() ?? "") { context.page = nil }
        if let agent = context.userAgent, agent.count > 512 || !isHeaderSafe(agent) { context.userAgent = nil }
        context.cookies = Array(context.cookies.filter { [$0.name, $0.value, $0.domain, $0.path ?? ""].allSatisfy(isHeaderSafe) }
            .prefix(maxCookies))
        return context.isEmpty ? nil : context
    }

    /// No line breaks or other control characters, which could start another header.
    static func isHeaderSafe(_ text: String) -> Bool {
        !text.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    var httpCookies: [HTTPCookie] {
        cookies.compactMap { c in
            // A domain cookie also covers subdomains, which HTTPCookie marks with a leading dot.
            let domain = c.hostOnly == false && !c.domain.hasPrefix(".") ? "." + c.domain : c.domain
            var properties: [HTTPCookiePropertyKey: Any] = [.name: c.name, .value: c.value, .domain: domain, .path: c.path ?? "/"]
            if c.secure == true { properties[.secure] = "TRUE" }
            if let expires = c.expires { properties[.expires] = Date(timeIntervalSince1970: expires) }
            return HTTPCookie(properties: properties)
        }
    }

    /// What Safari sends as the Referer by default (strict-origin-when-cross-origin): the whole
    /// page address to the same site, only its origin to another one, and nothing from an
    /// https page to an http link.
    func referer(for url: URL) -> String? {
        guard let page, let pageScheme = page.scheme?.lowercased() else { return nil }
        if pageScheme == "https" && url.scheme?.lowercased() != "https" { return nil }
        var components = URLComponents(url: page, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        components?.user = nil
        components?.password = nil
        let sameOrigin = page.scheme?.lowercased() == url.scheme?.lowercased() && page.host()?.lowercased() == url.host()?.lowercased()
            && page.port == url.port
        if !sameOrigin {
            components?.path = "/"
            components?.query = nil
        }
        return components?.string
    }

    /// Gives the session its own store holding just these cookies, so they go only where the
    /// browser would send them (redirects to other sites included) and never reach Haul's own.
    func apply(to config: URLSessionConfiguration) {
        guard !cookies.isEmpty, let store = URLSessionConfiguration.ephemeral.httpCookieStorage else { return }
        httpCookies.forEach(store.setCookie)
        config.httpCookieStorage = store
    }

    func apply(to request: inout URLRequest) {
        if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        if let url = request.url, let referer = referer(for: url) { request.setValue(referer, forHTTPHeaderField: "Referer") }
    }
}
