import Foundation
import Network
import Synchronization
import Testing

@testable import Haul

/// One download spread over several routes, against a real server on loopback: the default route
/// goes through URLSession, and the other is pinned to lo0 as another network would be.
struct MultiNetworkTests {
    private static let mb: Int64 = 1024 * 1024
    private static let defaultRoute = Route(interface: nil, name: "default")

    private struct Outcome {
        var result: Result<Void, Error>
        var byRoute: [String: Int64]
        var serverLimit: Int?
        var file: Data
    }

    private func download(
        _ server: LocalHTTPServer, size: Int64, routes: [Route], connections: Int = 8,
        etag: String? = nil, lastModified: String? = nil
    ) async -> Outcome {
        let part = FileManager.default.temporaryDirectory.appending(path: "haul-test-\(UUID().uuidString).part")
        defer { try? FileManager.default.removeItem(at: part) }
        var engine: SegmentedDownloader?
        let result = await withCheckedContinuation { continuation in
            engine = SegmentedDownloader(
                url: server.base.appending(path: "file.bin"), partURL: part,
                segments: [Segment(start: 0, end: size - 1)], connections: connections,
                etag: etag, lastModified: lastModified, routes: routes, browser: nil,
                limiter: RateLimiter(), configuration: .ephemeral
            ) { continuation.resume(returning: $0) }
            engine!.start()
        }
        let state = engine!.connectionState()
        return Outcome(
            result: result, byRoute: state.byRoute, serverLimit: state.serverLimit, file: (try? Data(contentsOf: part)) ?? Data())
    }

    private func pinned() async -> Route {
        Route(interface: await loopback(), name: "lo0")
    }

    /// Requests from URLSession say CFNetwork in their User-Agent; pinned ones don't.
    nonisolated private static func isPinned(_ head: String) -> Bool { !head.contains("CFNetwork") }

    @Test func pinnedConnectionsDownloadTheWholeFile() async throws {
        let size = 20 * Self.mb
        let server = try await LocalHTTPServer.file(size: size)
        let outcome = await download(server, size: size, routes: [await pinned()], connections: 4)
        try outcome.result.get()
        #expect(outcome.file == RangeServer.content(0...(size - 1)))
        #expect(outcome.byRoute["lo0"] == size)
    }

    @Test func connectionsSpreadOverEveryRoute() async throws {
        let size = 40 * Self.mb
        let server = try await LocalHTTPServer.file(size: size)
        let outcome = await download(server, size: size, routes: [Self.defaultRoute, await pinned()])
        try outcome.result.get()
        #expect(outcome.file == RangeServer.content(0...(size - 1)))
        #expect((outcome.byRoute["default"] ?? 0) > 0)
        #expect((outcome.byRoute["lo0"] ?? 0) > 0)
        #expect(outcome.byRoute.values.reduce(0, +) == size)
    }

    @Test func aNetworkTakesItsShareOnceChecked() async throws {
        let size = 40 * Self.mb
        // Slow enough that every connection is still busy when the check passes.
        let server = try await LocalHTTPServer.file(size: size, pause: 0.004)
        let outcome = await download(server, size: size, routes: [Self.defaultRoute, await pinned()])
        try outcome.result.get()
        #expect(outcome.file == RangeServer.content(0...(size - 1)))
        // Half the connections are its own, handed over from the default route once it passed.
        #expect((outcome.byRoute["lo0"] ?? 0) > size / 4)
    }

    @Test func aBusyServerDoesntFailTheCheck() async throws {
        let size = 40 * Self.mb
        // A server allowing a few connections per account refuses the check while the others hold them.
        let refusedOnce = Mutex(false)
        let server = try await LocalHTTPServer.file(
            size: size, pause: 0.02,
            headers: { head in
                guard Self.isPinned(head), head.contains("Range: bytes=0-65535"),
                    !refusedOnce.withLock({
                        defer { $0 = true }
                        return $0
                    })
                else { return nil }
                return ("429 Too Many Requests", ["Retry-After": "1"])
            })
        let outcome = await download(server, size: size, routes: [Self.defaultRoute, await pinned()])
        try outcome.result.get()
        #expect(outcome.file == RangeServer.content(0...(size - 1)))
        #expect((outcome.byRoute["lo0"] ?? 0) > 0)
        // Asked again once Retry-After had passed, not straight away.
        let checks = server.lock.withLock { server.requests.filter { Self.isPinned($0.head) && $0.head.contains("Range: bytes=0-65535") } }
        #expect(checks.count == 2)
        if checks.count == 2 { #expect(checks[1].at.timeIntervalSince(checks[0].at) >= 0.9) }
    }

    @Test func aServerAlwaysBusyOverANetworkIsDropped() async throws {
        let size = 8 * Self.mb
        // Slow enough to outlast every check the network gets.
        let server = try await LocalHTTPServer.file(
            size: size, pause: 0.4,
            headers: { head in
                Self.isPinned(head) ? ("429 Too Many Requests", ["Retry-After": "1"]) : nil
            })
        let outcome = await download(server, size: size, routes: [Self.defaultRoute, await pinned()])
        try outcome.result.get()
        #expect(outcome.file == RangeServer.content(0...(size - 1)))
        #expect(outcome.byRoute["lo0"] == nil)
        // Asked busyLimit times, then left alone.
        #expect(server.lock.withLock { server.heads.filter(Self.isPinned).count } == SegmentedDownloader.busyLimit)
    }

    @Test func aServerLimitOnOneNetworkLeavesTheOthersAlone() async throws {
        let size = 20 * Self.mb
        // As a server limiting each address: the other network's first part is refused while the
        // default route's connection is open.
        let refused = Mutex(false)
        let server = try await LocalHTTPServer.file(
            size: size, pause: 0.01,
            headers: { head in
                guard Self.isPinned(head), !head.contains("Range: bytes=0-65535"),
                    !refused.withLock({
                        defer { $0 = true }
                        return $0
                    })
                else { return nil }
                return ("429 Too Many Requests", ["Retry-After": "1"])
            })
        let outcome = await download(server, size: size, routes: [Self.defaultRoute, await pinned()], connections: 2)
        try outcome.result.get()
        #expect(outcome.file == RangeServer.content(0...(size - 1)))
        // One connection over each network still, not one in all.
        #expect(outcome.serverLimit == 2)
        #expect((outcome.byRoute["lo0"] ?? 0) > 0)
    }

    @Test func onlyTheDefaultRouteSendsIfRange() async throws {
        let size = 20 * Self.mb
        let server = try await LocalHTTPServer.file(size: size, headers: { _ in ("206", ["ETag": "\"v1\""]) })
        let outcome = await download(server, size: size, routes: [Self.defaultRoute, await pinned()], etag: "\"v1\"")
        try outcome.result.get()
        let heads = server.lock.withLock { server.heads }
        #expect(heads.contains { !Self.isPinned($0) && $0.contains("If-Range: \"v1\"") })
        #expect(heads.contains { Self.isPinned($0) })
        #expect(!heads.contains { Self.isPinned($0) && $0.contains("If-Range") })
    }

    @Test func aNetworkThatRefusesIsDroppedAndTheOthersFinish() async throws {
        let size = 20 * Self.mb
        // As a signed link bound to the address it was made for refuses every other network.
        let server = try await LocalHTTPServer.file(size: size, headers: { Self.isPinned($0) ? ("403 Forbidden", [:]) : nil })
        let outcome = await download(server, size: size, routes: [Self.defaultRoute, await pinned()])
        try outcome.result.get()
        #expect(outcome.file == RangeServer.content(0...(size - 1)))
        #expect(outcome.byRoute["lo0"] == nil)
        // Dropped after its first refusals, not asked again for every part.
        #expect(server.lock.withLock { server.heads.filter(Self.isPinned).count } <= 4)
    }

    @Test func anotherVersionOnANetworkIsDropped() async throws {
        let size = 20 * Self.mb
        let server = try await LocalHTTPServer.file(
            size: size,
            headers: { head in
                (
                    "206",
                    Self.isPinned(head)
                        ? ["ETag": "\"v2\"", "Last-Modified": "Tue, 02 Jun 2026 10:00:00 GMT"]
                        : ["ETag": "\"v1\"", "Last-Modified": "Mon, 01 Jun 2026 10:00:00 GMT"]
                )
            })
        let outcome = await download(
            server, size: size, routes: [Self.defaultRoute, await pinned()],
            etag: "\"v1\"", lastModified: "Mon, 01 Jun 2026 10:00:00 GMT")
        try outcome.result.get()
        #expect(outcome.byRoute["lo0"] == nil)
    }

    @Test func theSameFileTaggedDifferentlyIsUsed() async throws {
        let size = 40 * Self.mb
        // Mirrors that build their ETags from the file's inode tag the same file differently.
        let server = try await LocalHTTPServer.file(
            size: size,
            headers: { head in
                ("206", ["ETag": Self.isPinned(head) ? "\"inode-2\"" : "\"inode-1\"", "Last-Modified": "Mon, 01 Jun 2026 10:00:00 GMT"])
            })
        let outcome = await download(
            server, size: size, routes: [Self.defaultRoute, await pinned()],
            etag: "\"inode-1\"", lastModified: "Mon, 01 Jun 2026 10:00:00 GMT")
        try outcome.result.get()
        #expect(outcome.file == RangeServer.content(0...(size - 1)))
        #expect((outcome.byRoute["lo0"] ?? 0) > 0)
    }

    @Test func aDifferentSizeOnANetworkIsDropped() async throws {
        let size = 20 * Self.mb
        let server = try await LocalHTTPServer.file(
            size: size,
            headers: { head in
                Self.isPinned(head) ? ("206", ["Content-Range": "bytes 0-0/\(size + 1)"]) : nil
            })
        let outcome = await download(server, size: size, routes: [Self.defaultRoute, await pinned()])
        try outcome.result.get()
        #expect(outcome.file == RangeServer.content(0...(size - 1)))
        #expect(outcome.byRoute["lo0"] == nil)
    }

    @Test func repliesInFlightOnADroppedNetworkAreStillCheckedAsItsOwn() async throws {
        let size = 40 * Self.mb
        // The network passes its check, then one of its connections is refused, dropping it while the
        // others still wait for their replies, which then come with another version of the file.
        let pinnedSeen = Mutex(0)
        let server = try await LocalHTTPServer.file(
            size: size,
            wait: { head in
                guard Self.isPinned(head) else { return 0 }
                return head.contains("Range: bytes=0-65535") ? 0 : 0.3
            },
            headers: { head in
                guard Self.isPinned(head) else { return ("206", ["ETag": "\"v1\""]) }
                if head.contains("Range: bytes=0-65535") { return ("206", ["ETag": "\"v1\""]) }
                let n = pinnedSeen.withLock {
                    $0 += 1
                    return $0
                }
                return n == 1 ? ("403 Forbidden", [:]) : ("206", ["ETag": "\"v2\""])
            })
        let outcome = await download(server, size: size, routes: [Self.defaultRoute, await pinned()], etag: "\"v1\"")
        try outcome.result.get()
        #expect(pinnedSeen.withLock { $0 } > 1)
        #expect(outcome.file == RangeServer.content(0...(size - 1)))
        #expect(outcome.byRoute["lo0"] == nil)
    }

    @Test func aNetworkSendingOtherBytesIsDropped() async throws {
        let size = 20 * Self.mb
        // Same size, ETag and date, but not the same bytes, as from a mirror that rebuilt the file.
        let server = try await LocalHTTPServer.file(size: size, corrupt: Self.isPinned, headers: { _ in ("206", ["ETag": "\"v1\""]) })
        let outcome = await download(server, size: size, routes: [Self.defaultRoute, await pinned()], etag: "\"v1\"")
        try outcome.result.get()
        #expect(outcome.file == RangeServer.content(0...(size - 1)))
        #expect(outcome.byRoute["lo0"] == nil)
        #expect(server.lock.withLock { server.heads.filter(Self.isPinned).count } == 1)
    }

    @Test func aNetworkThatMissesOnceIsKept() async throws {
        let size = 40 * Self.mb
        // One connection closes before replying, as on a passing hiccup; the rest are served.
        let dropped = Mutex(false)
        let server = try await LocalHTTPServer.file(
            size: size,
            headers: { head in
                guard Self.isPinned(head),
                    !dropped.withLock({
                        defer { $0 = true }
                        return $0
                    })
                else { return nil }
                return ("drop", [:])
            })
        // The only network, so dropping it would fail the download.
        let outcome = await download(server, size: size, routes: [await pinned()], connections: 4)
        try outcome.result.get()
        #expect(outcome.file == RangeServer.content(0...(size - 1)))
    }

    @Test func aNetworkThatNeverAnswersIsDropped() async throws {
        let size = 20 * Self.mb
        let server = try await LocalHTTPServer.file(size: size, headers: { Self.isPinned($0) ? ("drop", [:]) : nil })
        let outcome = await download(server, size: size, routes: [Self.defaultRoute, await pinned()])
        try outcome.result.get()
        #expect(outcome.file == RangeServer.content(0...(size - 1)))
        #expect(outcome.byRoute["lo0"] == nil)
    }

    @Test func losingTheOnlyNetworkFailsTheDownload() async throws {
        let size = 8 * Self.mb
        let server = try await LocalHTTPServer.file(size: size, headers: { _ in ("403 Forbidden", [:]) })
        let outcome = await download(server, size: size, routes: [await pinned()], connections: 2)
        guard case .failure(DownloadError.linkExpired(403)) = outcome.result else {
            Issue.record("expected linkExpired(403), got \(outcome.result)")
            return
        }
    }

    @Test func sameFile() {
        func reply(_ headers: [String: String]) -> HTTPURLResponse {
            HTTPURLResponse(url: URL(string: "https://example.com/f")!, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: headers)!
        }
        let date = "Mon, 01 Jun 2026 10:00:00 GMT"
        #expect(SegmentedDownloader.sameFile(reply(["ETag": "\"a\""]), etag: "\"a\"", lastModified: nil))
        #expect(!SegmentedDownloader.sameFile(reply(["ETag": "\"b\""]), etag: "\"a\"", lastModified: nil))
        #expect(SegmentedDownloader.sameFile(reply(["ETag": "\"b\"", "Last-Modified": date]), etag: "\"a\"", lastModified: date))
        #expect(!SegmentedDownloader.sameFile(reply(["ETag": "\"b\"", "Last-Modified": "Tue"]), etag: "\"a\"", lastModified: date))
        #expect(!SegmentedDownloader.sameFile(reply([:]), etag: nil, lastModified: date))
        #expect(SegmentedDownloader.sameFile(reply([:]), etag: nil, lastModified: nil))
    }
}

struct RouteChoiceTests {
    private func links() async -> [NetworkLink] {
        let lo = await loopback()
        return [
            NetworkLink(name: "en0", type: .wifi, metered: false, router: "192.168.1.1", interface: lo),
            NetworkLink(name: "en7", type: .wiredEthernet, metered: false, router: "172.16.0.1", interface: lo),
        ]
    }

    private func routes(
        _ links: [NetworkLink], primary: String? = "en0", enabled: Bool = true, connections: Int = 8,
        resumable: Bool = true, signIn: Bool = false
    ) -> [Route] {
        DownloadStore.routes(links, primary: primary, enabled: enabled, connections: connections, resumable: resumable, signIn: signIn)
    }

    @Test func theDefaultNetworkUsesURLSessionAndTheOthersArePinned() async {
        let chosen = routes(await links())
        #expect(chosen.map(\.name) == ["en0", "en7"])
        #expect(chosen[0].interface == nil)
        #expect(chosen[1].interface != nil)
    }

    @Test func withoutTheDefaultNetworkEveryRouteIsPinned() async {
        // As when the default network is a metered phone that isn't allowed.
        #expect(routes(await links(), primary: "en9").allSatisfy { $0.interface != nil })
    }

    @Test func oneRouteUnlessEverythingAllowsMore() async {
        let links = await links()
        #expect(routes(links, enabled: false) == [.standard])
        #expect(routes(Array(links.prefix(1))) == [.standard])
        #expect(routes(links, connections: 1) == [.standard])
        #expect(routes(links, resumable: false) == [.standard])
        #expect(routes(links, signIn: true) == [.standard])
    }

    @Test func networkChanges() async {
        let lo = await loopback()
        let wifi = Route(interface: nil, name: "en0")
        let ethernet = Route(interface: lo, name: "en7")
        let now = Date()
        func change(_ old: [Route], _ wanted: [Route], since: Date? = nil, byUser: Bool = false) -> DownloadStore.NetworkChange {
            DownloadStore.networkChange(from: old, to: wanted, waitingSince: since, now: now, byUser: byUser)
        }
        #expect(change([wifi, ethernet], [wifi, ethernet]) == .none)
        // Losing a network, or a VPN coming on, applies at once.
        #expect(change([wifi, ethernet], [.standard]) == .restart)
        // Gaining one waits until it has stayed.
        #expect(change([.standard], [wifi, ethernet]) == .waiting(since: now))
        let earlier = now - 3
        #expect(change([.standard], [wifi, ethernet], since: earlier) == .waiting(since: earlier))
        #expect(change([.standard], [wifi, ethernet], since: now - DownloadStore.networkSettle) == .restart)
        // Unless it's the setting being turned on.
        #expect(change([.standard], [wifi, ethernet], byUser: true) == .restart)
    }
}
