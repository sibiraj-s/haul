import Foundation
import Testing
@testable import Haul

struct BrowserContextTests {
    private let page = URL(string: "https://site.example/files/list?id=7#top")!

    @Test func refererFollowsSafarisDefaultPolicy() {
        let context = BrowserContext(page: page)
        #expect(context.referer(for: URL(string: "https://site.example/get/a.zip")!) == "https://site.example/files/list?id=7")
        #expect(context.referer(for: URL(string: "https://cdn.example/a.zip")!) == "https://site.example/")
        #expect(context.referer(for: URL(string: "http://site.example/a.zip")!) == nil)
        #expect(BrowserContext(page: URL(string: "http://site.example/p")!).referer(for: URL(string: "https://x.example/a")!) == "http://site.example/")
        #expect(BrowserContext().referer(for: URL(string: "https://site.example/a")!) == nil)
    }

    @Test func decodeDropsUnsafeValues() {
        let json = #"""
        {"page": "javascript:alert(1)", "userAgent": "Agent\r\nX-Evil: 1",
         "cookies": [{"name": "ok", "value": "1", "domain": ".site.example"},
                     {"name": "bad", "value": "1\r\nX: y", "domain": "site.example"}]}
        """#
        let context = BrowserContext.decode(json)
        #expect(context?.page == nil)
        #expect(context?.userAgent == nil)
        #expect(context?.cookies.map(\.name) == ["ok"])
        #expect(BrowserContext.decode("not json") == nil)
        #expect(BrowserContext.decode("{}") == nil)
    }

    @Test func decodeCapsCookies() {
        let cookies = (0..<400).map { #"{"name": "c\#($0)", "value": "v", "domain": "site.example"}"# }.joined(separator: ",")
        #expect(BrowserContext.decode(#"{"cookies": [\#(cookies)]}"#)?.cookies.count == BrowserContext.maxCookies)
    }

    @Test func domainCookiesCoverSubdomains() {
        // Within the 400 days HTTPCookie caps a lifetime at.
        let expires = Date.now.timeIntervalSince1970.rounded() + 86_400
        let context = BrowserContext(cookies: [
            .init(name: "domain", value: "1", domain: "site.example", hostOnly: false),
            .init(name: "host", value: "2", domain: "site.example", hostOnly: true),
            .init(name: "dotted", value: "3", domain: ".site.example", secure: true, expires: expires),
        ])
        let cookies = context.httpCookies
        #expect(cookies.map(\.domain) == [".site.example", "site.example", ".site.example"])
        #expect(cookies[2].isSecure)
        #expect(cookies[2].expiresDate == Date(timeIntervalSince1970: expires))
        #expect(cookies.allSatisfy { $0.path == "/" })
    }

    @Test func cookiesGoInTheirOwnStore() {
        let config = URLSessionConfiguration.default
        BrowserContext(cookies: [.init(name: "sid", value: "abc", domain: ".site.example")]).apply(to: config)
        let store = config.httpCookieStorage
        #expect(store != nil && store !== HTTPCookieStorage.shared)
        #expect(store?.cookies(for: URL(string: "https://dl.site.example/a.zip")!)?.map(\.name) == ["sid"])
        #expect(store?.cookies(for: URL(string: "https://other.example/")!)?.isEmpty ?? true)
        #expect(HTTPCookieStorage.shared.cookies(for: URL(string: "https://dl.site.example/")!)?.isEmpty ?? true)

        let plain = URLSessionConfiguration.default
        BrowserContext(userAgent: "UA").apply(to: plain)
        #expect(plain.httpCookieStorage === URLSessionConfiguration.default.httpCookieStorage)
    }

    @Test func headersOnTheRequest() {
        var request = URLRequest(url: URL(string: "https://cdn.example/a.zip")!)
        BrowserContext(page: page, userAgent: "Safari UA").apply(to: &request)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Safari UA")
        #expect(request.value(forHTTPHeaderField: "Referer") == "https://site.example/")
    }

    @Test func readFromAddLink() {
        let json = #"{"page":"https://site.example/p","userAgent":"UA","cookies":[{"name":"a","value":"b=c&d","domain":".site.example"}]}"#
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#?")
        let url = URL(string: "haul://add?url=https%3A%2F%2Fsite.example%2Fa.zip&context=\(json.addingPercentEncoding(withAllowedCharacters: allowed)!)")!
        #expect(IncomingLinks.links(in: url) == [URL(string: "https://site.example/a.zip")!])
        let context = IncomingLinks.browserContext(in: url)
        #expect(context?.userAgent == "UA")
        #expect(context?.cookies.first?.value == "b=c&d")
        #expect(IncomingLinks.browserContext(in: URL(string: "haul://add?url=https://a.com/x")!) == nil)
        // No links, no context.
        #expect(IncomingLinks.browserContext(in: URL(string: "haul://add?context=%7B%22userAgent%22%3A%22UA%22%7D")!) == nil)
    }
}
