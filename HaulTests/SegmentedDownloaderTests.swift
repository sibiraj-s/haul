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
        /// Requests starting at these bytes are refused once with 429.
        var throttleOnce: Set<Int64>

        let lock = NSLock()
        var requests: [(start: Int64, status: Int)] = []
        var active = 0
        var maxActive = 0

        init(size: Int64, throttleOnce: Set<Int64> = [], delay: @escaping @Sendable (Int64) -> Double) {
            self.size = size
            self.throttleOnce = throttleOnce
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
            let throttled = host.throttleOnce.remove(start) != nil
            host.requests.append((start, throttled ? 429 : 206))
            if !throttled {
                host.active += 1
                host.maxActive = max(host.maxActive, host.active)
            }
            return throttled
        }
        if throttled {
            let response = HTTPURLResponse(url: url, statusCode: 429, httpVersion: "HTTP/1.1", headerFields: ["Retry-After": "1"])!
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

    private func download(_ url: URL, segments: [Segment], connections: Int, partURL: URL) async -> (Result<Void, Error>, [Segment]) {
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
        return (result, engine!.snapshot())
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

        let (result, segments) = await download(RangeServer.serve(host), segments: Segment.split(size: size, connections: 3, resumable: true),
                                                connections: 3, partURL: part)
        try result.get()
        #expect(segments.count > 3)
        expectWhole(segments, size: size)
        #expect(try Data(contentsOf: part) == RangeServer.content(0...size - 1))
        #expect(host.maxActive <= 3)
    }

    @Test func resumeFillsConnectionsLeftFree() async throws {
        let size = 64 * Self.mb
        let host = RangeServer.Host(size: size) { _ in 0.003 }
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }
        var segments = Segment.split(size: size, connections: 8, resumable: true)
        for i in 0..<6 { segments[i].done = segments[i].length! }
        try RangeServer.content(0...size - 1).write(to: part)

        let (result, after) = await download(RangeServer.serve(host), segments: segments, connections: 8, partURL: part)
        try result.get()
        // Two segments were left, but splitting them fills more of the eight connections.
        #expect(host.maxActive > 2)
        expectWhole(after, size: size)
        #expect(try Data(contentsOf: part) == RangeServer.content(0...size - 1))
    }

    @Test func throttledSegmentGetsTheNextFreeConnection() async throws {
        let size = 48 * Self.mb
        let third = 16 * Self.mb
        let host = RangeServer.Host(size: size, throttleOnce: [third]) { $0 == 0 ? 0.02 : 0.003 }
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }

        let (result, segments) = await download(RangeServer.serve(host), segments: Segment.split(size: size, connections: 3, resumable: true),
                                                connections: 3, partURL: part)
        try result.get()
        // While the refused segment waits out Retry-After, no split takes the slot it's waiting for.
        let requests = host.lock.withLock { host.requests }
        let retry = try #require(requests.lastIndex { $0.start == third })
        #expect(requests[..<retry].allSatisfy { [0, third, 2 * third].contains($0.start) })
        expectWhole(segments, size: size)
        #expect(try Data(contentsOf: part) == RangeServer.content(0...size - 1))
    }
}
