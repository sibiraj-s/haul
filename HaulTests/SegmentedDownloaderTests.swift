import Foundation
import Testing
@testable import Haul

/// Serves a generated file to ranged requests on `rangetest://<host>/`, with each host's
/// behaviour set up by the test that owns it.
nonisolated final class RangeServer: URLProtocol, @unchecked Sendable {
    final class Host: @unchecked Sendable {
        let size: Int64
        /// Seconds to wait before each chunk, by the request's first byte.
        let delay: @Sendable (Int64) -> Double
        /// Requests starting at these bytes are refused with 429, this many times each.
        var refuse: [Int64: Int]
        /// Requests beyond this many at once are refused with 429.
        var limit = Int.max
        /// The Retry-After sent with each refusal, in seconds.
        var retryAfter = 1

        let lock = NSLock()
        var requests: [(start: Int64, status: Int, at: Date)] = []
        var active = 0
        var maxActive = 0

        init(size: Int64, refuse: [Int64: Int] = [:], delay: @escaping @Sendable (Int64) -> Double) {
            self.size = size
            self.refuse = refuse
            self.delay = delay
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var hosts: [String: Host] = [:]

    static func serve(_ host: Host) -> URL {
        let name = UUID().uuidString.lowercased()
        lock.withLock { hosts[name] = host }
        return URL(string: "rangetest://\(name)/file.bin")!
    }

    /// Repeats every 65521 bytes, a prime, so a segment written at the wrong offset doesn't match.
    private static let pattern = Data((0..<65521).map { UInt8(truncatingIfNeeded: $0 ^ ($0 >> 8)) })

    static func content(_ range: ClosedRange<Int64>) -> Data {
        var data = Data(capacity: range.count)
        var i = range.lowerBound
        while i <= range.upperBound {
            let from = Int(i % Int64(pattern.count))
            let count = min(pattern.count - from, Int(range.upperBound - i + 1))
            data.append(pattern[from..<from + count])
            i += Int64(count)
        }
        return data
    }

    private let stopLock = NSLock()
    private var stopped = false
    private var host: Host?

    override class func canInit(with request: URLRequest) -> Bool { request.url?.scheme == "rangetest" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = Self.lock.withLock({ Self.hosts[url.host() ?? ""] }) else {
            return client!.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        }
        self.host = host
        let bounds = (request.value(forHTTPHeaderField: "Range") ?? "bytes=0-")
            .dropFirst("bytes=".count).split(separator: "-", omittingEmptySubsequences: false)
        let start = Int64(bounds[0]) ?? 0
        let end = bounds.count > 1 ? Int64(bounds[1]) ?? host.size - 1 : host.size - 1

        let throttled = host.lock.withLock {
            let refused = host.refuse[start, default: 0] > 0
            if refused { host.refuse[start]! -= 1 }
            let throttled = refused || host.active >= host.limit
            host.requests.append((start, throttled ? 429 : 206, Date()))
            if !throttled {
                host.active += 1
                host.maxActive = max(host.maxActive, host.active)
            }
            return throttled
        }
        if throttled {
            // Never counted as open, so stopping it mustn't count it as closed.
            stopLock.withLock { stopped = true }
            let response = HTTPURLResponse(url: url, statusCode: 429, httpVersion: "HTTP/1.1",
                                           headerFields: ["Retry-After": "\(host.retryAfter)"])!
            client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client!.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Range": "bytes \(start)-\(end)/\(host.size)",
            "Content-Length": "\(end - start + 1)",
        ])!
        client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        send(from: start, to: end, wait: host.delay(start))
    }

    private func send(from offset: Int64, to end: Int64, wait: Double) {
        DispatchQueue.global().asyncAfter(deadline: .now() + wait) { [self] in
            guard !stopLock.withLock({ stopped }) else { return }
            let last = min(end, offset + 256 * 1024 - 1)
            client!.urlProtocol(self, didLoad: Self.content(offset...last))
            if last == end {
                finish()
                client!.urlProtocolDidFinishLoading(self)
            } else {
                send(from: last + 1, to: end, wait: wait)
            }
        }
    }

    private func finish() {
        let first = stopLock.withLock {
            defer { stopped = true }
            return !stopped
        }
        if first, let host { host.lock.withLock { host.active -= 1 } }
    }

    override func stopLoading() { finish() }
}

struct SegmentedDownloaderTests {
    private static let mb: Int64 = 1024 * 1024

    /// Downloads to the end; also returns the connection limit the engine settled on, if the server pushed back.
    private func download(_ url: URL, segments: [Segment], connections: Int, partURL: URL)
        async -> (Result<Void, Error>, [Segment], serverLimit: Int?) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RangeServer.self]
        var engine: SegmentedDownloader?
        let result = await withCheckedContinuation { continuation in
            engine = SegmentedDownloader(url: url, partURL: partURL, segments: segments, connections: connections,
                                         ifRange: nil, browser: nil, limiter: RateLimiter(), configuration: config) {
                continuation.resume(returning: $0)
            }
            engine!.start()
        }
        return (result, engine!.snapshot(), engine!.connectionState().serverLimit)
    }

    private func partURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "haul-test-\(UUID().uuidString).part")
    }

    private func expectWhole(_ segments: [Segment], size: Int64) {
        #expect(segments.first?.start == 0)
        #expect(segments.last?.end == size - 1)
        for (a, b) in zip(segments, segments.dropFirst()) { #expect(a.end.map { $0 + 1 } == b.start) }
        #expect(segments.allSatisfy { $0.isComplete })
    }

    @Test func freeConnectionsTakeOverTheSlowestSegment() async throws {
        let size = 48 * Self.mb
        let host = RangeServer.Host(size: size) { $0 == 0 ? 0.02 : 0.003 }
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }

        let (result, segments, _) = await download(RangeServer.serve(host), segments: Segment.split(size: size, connections: 3, resumable: true),
                                                connections: 3, partURL: part)
        try result.get()
        #expect(segments.count > 3)
        expectWhole(segments, size: size)
        #expect(try Data(contentsOf: part) == RangeServer.content(0...size - 1))
        #expect(host.maxActive <= 3)
    }

    @Test func refusedPartsTakeTheNextConnectionToFinish() async throws {
        let size = 64 * Self.mb
        let host = RangeServer.Host(size: size) { _ in 0.003 }
        host.limit = 3
        host.retryAfter = 60
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }

        let started = Date()
        let (result, segments, _) = await download(RangeServer.serve(host), segments: Segment.split(size: size, connections: 8, resumable: true),
                                                connections: 8, partURL: part)
        try result.get()
        // Waiting out the minute-long Retry-After would leave every connection idle once the first three parts were done.
        #expect(Date().timeIntervalSince(started) < 10)
        #expect(host.maxActive <= 3)
        expectWhole(segments, size: size)
        #expect(try Data(contentsOf: part) == RangeServer.content(0...size - 1))
    }

    @Test func refusedAgainOnTheFreedConnectionWaitsOutRetryAfter() async throws {
        let size = 48 * Self.mb
        let third = 16 * Self.mb
        let host = RangeServer.Host(size: size, refuse: [third: 3]) { $0 == 0 ? 0.02 : 0.003 }
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }

        let (result, segments, serverLimit) = await download(RangeServer.serve(host),
                                                             segments: Segment.split(size: size, connections: 3, resumable: true),
                                                             connections: 3, partURL: part)
        try result.get()
        let tries = host.lock.withLock { host.requests.filter { $0.start == third }.map(\.at) }
        try #require(tries.count == 4)
        // Sent again as soon as a connection freed up; refused again, it waits out the 1 s Retry-After
        // every time after, until the server takes it.
        #expect(tries[1].timeIntervalSince(tries[0]) < 0.9)
        #expect(tries[2].timeIntervalSince(tries[1]) >= 0.9)
        #expect(tries[3].timeIntervalSince(tries[2]) >= 0.9)
        // Only the first refusal set the limit: the two connections it found open.
        #expect(serverLimit == 2)
        expectWhole(segments, size: size)
    }

    @Test func reportsWhereEachAcceptedConnectionWrites() async throws {
        let size = 48 * Self.mb
        // Slow enough that no part finishes while the test looks; the middle part is refused for a while.
        let host = RangeServer.Host(size: size, refuse: [16 * Self.mb: 1]) { _ in 0.1 }
        host.retryAfter = 60
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RangeServer.self]
        let engine = SegmentedDownloader(url: RangeServer.serve(host), partURL: part,
                                         segments: Segment.split(size: size, connections: 3, resumable: true), connections: 3,
                                         ifRange: nil, browser: nil, limiter: RateLimiter(), configuration: config) { _ in }
        engine.start()
        defer { engine.cancel() }
        var at: [Int64] = []
        for _ in 0..<250 where at.count < 2 || !at.allSatisfy({ $0 % (16 * Self.mb) > 0 }) {
            try await Task.sleep(for: .milliseconds(20))
            at = engine.connectionState().writingAt
        }
        // Two connections are partway into the first and last parts; the refused middle one isn't writing.
        #expect(at.map { $0 / (16 * Self.mb) }.sorted() == [0, 2])
    }

    @Test func resumeFillsConnectionsLeftFree() async throws {
        let size = 64 * Self.mb
        let host = RangeServer.Host(size: size) { _ in 0.003 }
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }
        var segments = Segment.split(size: size, connections: 8, resumable: true)
        for i in 0..<6 { segments[i].done = segments[i].length! }
        try RangeServer.content(0...size - 1).write(to: part)

        let (result, after, _) = await download(RangeServer.serve(host), segments: segments, connections: 8, partURL: part)
        try result.get()
        // Two segments were left, but splitting them fills more of the eight connections.
        #expect(host.maxActive > 2)
        expectWhole(after, size: size)
        #expect(try Data(contentsOf: part) == RangeServer.content(0...size - 1))
    }

    @Test func throttledSegmentGetsTheNextFreeConnection() async throws {
        let size = 48 * Self.mb
        let third = 16 * Self.mb
        let host = RangeServer.Host(size: size, refuse: [third: 1]) { $0 == 0 ? 0.02 : 0.003 }
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }

        let (result, segments, _) = await download(RangeServer.serve(host), segments: Segment.split(size: size, connections: 3, resumable: true),
                                                connections: 3, partURL: part)
        try result.get()
        // While the refused segment waits for a connection, no split takes the slot it's waiting for.
        let requests = host.lock.withLock { host.requests }
        let retry = try #require(requests.lastIndex { $0.start == third })
        #expect(requests[..<retry].allSatisfy { [0, third, 2 * third].contains($0.start) })
        expectWhole(segments, size: size)
        #expect(try Data(contentsOf: part) == RangeServer.content(0...size - 1))
    }
}
