import Foundation
import Testing
@testable import Haul

struct RemoteServerTests {
    private func request(_ text: String) -> HTTPRequest.Parsed { HTTPRequest.parse(Data(text.utf8)) }

    private func post(_ body: String, headers: [String: String] = [:]) -> HTTPRequest {
        HTTPRequest(method: "POST", path: "/add", headers: headers, body: Data(body.utf8))
    }

    private func basic(_ credentials: String) -> String { "Basic " + Data(credentials.utf8).base64EncodedString() }

    // MARK: - Parsing

    @Test func parsesARequestWithABody() {
        let parsed = request("POST /add?x=1 HTTP/1.1\r\nHost: h\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello")
        #expect(parsed == .complete(HTTPRequest(method: "POST", path: "/add", headers: ["host": "h", "content-type": "text/plain", "content-length": "5"],
                                                body: Data("hello".utf8))))
    }

    @Test func waitsForTheRestOfTheRequest() {
        #expect(request("GET / HTTP/1.1\r\nHost: h\r\n") == .incomplete)
        #expect(request("POST /add HTTP/1.1\r\nContent-Length: 10\r\n\r\nhello") == .incomplete)
    }

    @Test func rejectsMalformedAndOversizedRequests() {
        #expect(request("nonsense\r\n\r\n") == .invalid)
        #expect(request("GET / HTTP/1.1\r\nno colon\r\n\r\n") == .invalid)
        #expect(request("POST /add HTTP/1.1\r\nContent-Length: -1\r\n\r\n") == .invalid)
        #expect(request("POST /add HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n") == .invalid)
        #expect(request("POST /add HTTP/1.1\r\nContent-Length: 999999999999999999\r\n\r\n") == .tooLarge)
        #expect(request(String(repeating: "a", count: HTTPRequest.maxSize + 1)) == .tooLarge)
    }

    // MARK: - Password

    @Test func acceptsThePasswordAsBearerOrBasic() {
        #expect(RemoteAPI.authorized(post("", headers: ["authorization": "Bearer s3cret"]), password: "s3cret"))
        #expect(RemoteAPI.authorized(post("", headers: ["authorization": basic(":s3cret")]), password: "s3cret"))
        #expect(RemoteAPI.authorized(post("", headers: ["authorization": basic("anyone:s3cret")]), password: "s3cret"))
        // Only the first colon separates the user name; the password may have its own.
        #expect(RemoteAPI.authorized(post("", headers: ["authorization": basic("me:a:b")]), password: "a:b"))
    }

    @Test func refusesWrongMissingOrEmptyPasswords() {
        #expect(!RemoteAPI.authorized(post("", headers: ["authorization": "Bearer nope"]), password: "s3cret"))
        #expect(!RemoteAPI.authorized(post("", headers: ["authorization": basic("s3cret")]), password: "s3cret"))
        #expect(!RemoteAPI.authorized(post(""), password: "s3cret"))
        #expect(!RemoteAPI.authorized(post("", headers: ["authorization": "Bearer "]), password: ""))
        #expect(!RemoteAPI.authorized(post("", headers: ["authorization": "Token s3cret"]), password: "s3cret"))
    }

    @Test func refusesOtherSitesInABrowser() {
        #expect(RemoteAPI.isCrossSite(post("", headers: ["sec-fetch-site": "cross-site"])))
        #expect(RemoteAPI.isCrossSite(post("", headers: ["sec-fetch-site": "same-site"])))
        #expect(!RemoteAPI.isCrossSite(post("", headers: ["sec-fetch-site": "same-origin"])))
        #expect(!RemoteAPI.isCrossSite(post("", headers: ["sec-fetch-site": "none"])))
        // curl and scripts don't say.
        #expect(!RemoteAPI.isCrossSite(post("")))
    }

    @Test func newPasswordsDiffer() {
        let password = RemoteAPI.newPassword()
        #expect(password.count == 16)
        #expect(password != RemoteAPI.newPassword())
    }

    // MARK: - Links

    @Test func readsLinksFromText() {
        let found = try? RemoteAPI.links(in: post("https://a.com/x.zip\nsee https://b.com/y.iso and https://a.com/x.zip")).get()
        #expect(found == [URL(string: "https://a.com/x.zip")!, URL(string: "https://b.com/y.iso")!])
    }

    @Test func readsLinksFromJSON() throws {
        let json = ["content-type": "application/json"]
        let urls = [URL(string: "https://a.com/x?sig=1&e=2")!, URL(string: "http://b.com/y")!]
        #expect(try RemoteAPI.links(in: post(#"{"urls": ["https://a.com/x?sig=1&e=2", "http://b.com/y", "file:///etc/hosts"]}"#, headers: json)).get() == urls)
        #expect(try RemoteAPI.links(in: post(#"["https://a.com/x?sig=1&e=2", "http://b.com/y"]"#, headers: json)).get() == urls)
        #expect(throws: RemoteAPI.Failure.self) { try RemoteAPI.links(in: post(#"{"links": []}"#, headers: json)).get() }
    }

    @Test func refusesNoLinksOrTooMany() {
        #expect(throws: RemoteAPI.Failure.self) { try RemoteAPI.links(in: post("nothing here, ftp://a.com/x")).get() }
        let many = (0...RemoteAPI.maxLinks).map { "https://a.com/\($0)" }.joined(separator: "\n")
        #expect(throws: RemoteAPI.Failure.self) { try RemoteAPI.links(in: post(many)).get() }
    }

    // MARK: - Throttle

    @Test func locksAfterTooManyWrongPasswords() {
        var throttle = RemoteAPI.Throttle()
        let start = Date()
        for n in 0..<(RemoteAPI.Throttle.limit - 1) { throttle.fail(at: start.addingTimeInterval(Double(n))) }
        #expect(!throttle.isLocked(at: start.addingTimeInterval(20)))
        throttle.fail(at: start.addingTimeInterval(20))
        #expect(throttle.isLocked(at: start.addingTimeInterval(21)))
        #expect(!throttle.isLocked(at: start.addingTimeInterval(20 + RemoteAPI.Throttle.lockout)))
    }

    @Test func forgetsOldFailures() {
        var throttle = RemoteAPI.Throttle()
        let start = Date()
        for _ in 0..<(RemoteAPI.Throttle.limit - 1) { throttle.fail(at: start) }
        throttle.fail(at: start.addingTimeInterval(RemoteAPI.Throttle.window + 1))
        #expect(!throttle.isLocked(at: start.addingTimeInterval(RemoteAPI.Throttle.window + 2)))
    }

    // MARK: - Routes

    @Test func routesRequests() {
        let id = UUID()
        #expect(RemoteAPI.route("GET", "/") == .page)
        #expect(RemoteAPI.route("GET", "/index.html") == .page)
        #expect(RemoteAPI.route("POST", "/auth") == .auth)
        #expect(RemoteAPI.route("POST", "/add") == .add)
        #expect(RemoteAPI.route("GET", "/downloads") == .list)
        #expect(RemoteAPI.route("GET", "/downloads/") == .list)
        #expect(RemoteAPI.route("POST", "/downloads/\(id)/pause") == .pause(id))
        #expect(RemoteAPI.route("POST", "/downloads/\(id.uuidString.lowercased())/resume") == .resume(id))
        #expect(RemoteAPI.route("DELETE", "/downloads/\(id)") == .remove(id))
    }

    @Test func refusesUnknownPathsAndMethods() {
        let id = UUID()
        #expect(RemoteAPI.route("GET", "/add") == .methodNotAllowed)
        #expect(RemoteAPI.route("POST", "/") == .methodNotAllowed)
        #expect(RemoteAPI.route("GET", "/downloads/\(id)/pause") == .methodNotAllowed)
        #expect(RemoteAPI.route("POST", "/downloads/\(id)") == .methodNotAllowed)
        #expect(RemoteAPI.route("DELETE", "/downloads/not-an-id") == .notFound)
        #expect(RemoteAPI.route("POST", "/downloads/\(id)/explode") == .notFound)
        #expect(RemoteAPI.route("GET", "/favicon.ico") == .notFound)
        #expect(RemoteAPI.route("GET", "/downloads/\(id)/pause/x") == .notFound)
    }

    @MainActor @Test func summarisesADownload() {
        var d = Download(url: URL(string: "https://a.com/x.zip")!, name: "x.zip", size: 100, status: .failed, connections: 4)
        d.error = "Gone"
        d.speed = 50
        let summary = RemoteAPI.summary(d)
        #expect(summary["name"] as? String == "x.zip")
        #expect(summary["status"] as? String == "failed")
        #expect(summary["size"] as? Int64 == 100)
        #expect(summary["error"] as? String == "Gone")
        // Speed only while downloading.
        #expect(summary["speed"] as? Int == 0)
        #expect(JSONSerialization.isValidJSONObject(summary))
    }

    // MARK: - Responses

    @Test func writesAResponse() {
        let text = String(decoding: HTTPResponse.json(401, error: "Wrong password.").data, as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 401 Unauthorized\r\n"))
        #expect(text.contains("Content-Type: application/json\r\n"))
        #expect(text.contains("Connection: close\r\n"))
        #expect(text.hasSuffix("\r\n\r\n" + #"{"error":"Wrong password.","ok":false}"# + "\n"))
    }
}
