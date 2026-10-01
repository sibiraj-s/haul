import Foundation
import Testing
@testable import Haul

struct ResponseErrorTests {
    private func response(_ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.com/f")!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    @Test func basicChallengeAsksForSignIn() {
        guard case .signInRequired(let realm, let digest) = DownloadError.response(response(401, ["WWW-Authenticate": #"Basic realm="Members""#])) else {
            Issue.record("expected signInRequired"); return
        }
        #expect(realm == "Members")
        #expect(!digest)
    }

    @Test func digestChallengeAsksForSignIn() {
        let error = DownloadError.response(response(401, ["WWW-Authenticate": #"Digest realm="Files", qop="auth", nonce="abc""#]))
        guard case .signInRequired(let realm, let digest) = error else { Issue.record("expected signInRequired"); return }
        #expect(realm == "Files")
        #expect(digest)
    }

    @Test func unauthorizedWithoutChallengeIsAnExpiredLink() {
        guard case .linkExpired(401) = DownloadError.response(response(401)) else { Issue.record("expected linkExpired"); return }
    }

    @Test(arguments: [403, 404, 410])
    func goneLinksAreExpired(_ status: Int) {
        guard case .linkExpired(status) = DownloadError.response(response(status)) else { Issue.record("expected linkExpired"); return }
    }

    @Test func serverErrorsAreHTTPErrors() {
        guard case .http(500) = DownloadError.response(response(500)) else { Issue.record("expected http(500)"); return }
    }
}

struct RetryTests {
    nonisolated static let downloadErrorCases: [(DownloadError, Bool)] = [
        (.truncated, true),
        (.throttled(retryAfter: 5, status: 429), true),
        (.http(500), true),
        (.http(503), true),
        (.http(408), true),
        (.http(400), false),
        (.linkExpired(404), false),
        (.fileChanged, false),
        (.webPage, false),
        (.diskFull("full"), false),
        (.signInRequired(realm: nil, digest: false), false),
    ]

    nonisolated static let networkErrorCases: [(URLError.Code, Bool)] = [
        (.timedOut, true),
        (.networkConnectionLost, true),
        (.notConnectedToInternet, true),
        (.cannotFindHost, true),
        (.cancelled, false),
        (.badURL, false),
    ]

    @Test(arguments: downloadErrorCases)
    func downloadErrors(_ error: DownloadError, _ transient: Bool) {
        #expect(DownloadError.isTransient(error) == transient)
    }

    @Test(arguments: networkErrorCases)
    func networkErrors(_ code: URLError.Code, _ transient: Bool) {
        #expect(DownloadError.isTransient(URLError(code)) == transient)
    }

    @Test func otherErrorsAreNotRetried() {
        #expect(!DownloadError.isTransient(CocoaError(.fileWriteOutOfSpace)))
    }
}

struct ProtectionSpaceTests {
    @Test func defaultPorts() {
        let https = Probe.protectionSpace(for: URL(string: "https://files.example.com/a.zip")!, realm: "R", digest: false)
        #expect(https.host == "files.example.com")
        #expect(https.port == 443)
        #expect(https.protocol == "https")
        #expect(https.realm == "R")
        #expect(https.authenticationMethod == NSURLAuthenticationMethodHTTPBasic)

        let http = Probe.protectionSpace(for: URL(string: "http://example.com/a")!, realm: nil, digest: true)
        #expect(http.port == 80)
        #expect(http.authenticationMethod == NSURLAuthenticationMethodHTTPDigest)
    }

    @Test func explicitPort() {
        #expect(Probe.protectionSpace(for: URL(string: "https://example.com:8443/a")!, realm: nil, digest: false).port == 8443)
    }
}
