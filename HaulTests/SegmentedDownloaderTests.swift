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
        /// Requests starting at these bytes are answered from byte 0 instead, this many times each.
        var misplace: [Int64: Int] = [:]
        /// The total sent in Content-Range, when it should differ from `size` (another version of the file).
        var reportedSize: Int64?
        /// Sent as Content-Encoding, as if the server compressed the reply anyway.
        var encoding: String?
        /// This many connections drop after sending `dropAfter` bytes, as on a flaky network.
        var drops = 0
        var dropAfter: Int64 = 1024 * 1024
        /// Ignores Range and answers every request with the whole file and a 200.
        var ignoreRange = false

        let lock = NSLock()
        /// The Accept-Encoding of every request, in order.
        var acceptEncodings: [String?] = []
        /// The task identifier of every request, in order. Each session numbers its tasks from 1.
        var taskIDs: [Int?] = []
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
    /// Bytes this request has sent so far.
    private var sent: Int64 = 0

    override class func canInit(with request: URLRequest) -> Bool { request.url?.scheme == "rangetest" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = Self.lock.withLock({ Self.hosts[url.host() ?? ""] }) else {
            return client!.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        }
        self.host = host
        let bounds = (request.value(forHTTPHeaderField: "Range") ?? "bytes=0-")
            .dropFirst("bytes=".count).split(separator: "-", omittingEmptySubsequences: false)
        var start = Int64(bounds[0]) ?? 0
        var end = bounds.count > 1 ? Int64(bounds[1]) ?? host.size - 1 : host.size - 1
        let misplaced = host.lock.withLock {
            guard host.misplace[start, default: 0] > 0 else { return false }
            host.misplace[start]! -= 1
            return true
        }
        if misplaced { (start, end) = (0, end - start) }
        if host.ignoreRange { (start, end) = (0, host.size - 1) }

        let throttled = host.lock.withLock {
            let refused = host.refuse[start, default: 0] > 0
            if refused { host.refuse[start]! -= 1 }
            let throttled = refused || host.active >= host.limit
            host.requests.append((start, throttled ? 429 : 206, Date()))
            host.acceptEncodings.append(request.value(forHTTPHeaderField: "Accept-Encoding"))
            host.taskIDs.append(task?.taskIdentifier)
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
        var headers = ["Content-Length": "\(end - start + 1)"]
        if !host.ignoreRange { headers["Content-Range"] = "bytes \(start)-\(end)/\(host.reportedSize ?? host.size)" }
        if let encoding = host.encoding { headers["Content-Encoding"] = encoding }
        let response = HTTPURLResponse(url: url, statusCode: host.ignoreRange ? 200 : 206, httpVersion: "HTTP/1.1",
                                       headerFields: headers)!
        client!.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        send(from: start, to: end, wait: host.delay(start))
    }

    private func send(from offset: Int64, to end: Int64, wait: Double) {
        DispatchQueue.global().asyncAfter(deadline: .now() + wait) { [self] in
            guard !stopLock.withLock({ stopped }) else { return }
            let last = min(end, offset + 256 * 1024 - 1)
            client!.urlProtocol(self, didLoad: Self.content(offset...last))
            sent += last - offset + 1
            if let host, last < end, host.lock.withLock({
                guard host.drops > 0, sent >= host.dropAfter else { return false }
                host.drops -= 1
                return true
            }) {
                // A moment after the data, so it's delivered before the error rather than discarded with it.
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { [self] in
                    guard !stopLock.withLock({ stopped }) else { return }
                    finish()
                    client!.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                }
            } else if last == end {
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
        // The first part is far slower than the rest, so it's still going when they finish on any machine.
        let host = RangeServer.Host(size: size) { $0 == 0 ? 0.05 : 0.001 }
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
        // Waiting out the minute-long Retry-After would leave every connection idle once the first three parts were
        // done; half of it leaves room for a slow machine.
        #expect(Date().timeIntervalSince(started) < 30)
        #expect(host.maxActive <= 3)
        expectWhole(segments, size: size)
        #expect(try Data(contentsOf: part) == RangeServer.content(0...size - 1))
    }

    @Test func refusedAgainOnTheFreedConnectionWaitsOutRetryAfter() async throws {
        let size = 48 * Self.mb
        let third = 16 * Self.mb
        let host = RangeServer.Host(size: size, refuse: [third: 3]) { $0 == 0 ? 0.02 : 0.003 }
        // Well above the time the last part takes to free its connection, even on a slow machine.
        host.retryAfter = 3
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }

        let (result, segments, serverLimit) = await download(RangeServer.serve(host),
                                                             segments: Segment.split(size: size, connections: 3, resumable: true),
                                                             connections: 3, partURL: part)
        try result.get()
        let tries = host.lock.withLock { host.requests.filter { $0.start == third }.map(\.at) }
        try #require(tries.count == 4)
        // Sent again as soon as a connection freed up; refused again, it waits out the 3 s Retry-After
        // every time after, until the server takes it.
        #expect(tries[1].timeIntervalSince(tries[0]) < 2.5)
        #expect(tries[2].timeIntervalSince(tries[1]) >= 2.9)
        #expect(tries[3].timeIntervalSince(tries[2]) >= 2.9)
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
        // Slow enough that the two parts left are still going when their split halves start.
        let host = RangeServer.Host(size: size) { _ in 0.02 }
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

    @Test func replyFromTheWrongOffsetIsRetriedNotWritten() async throws {
        let size = 32 * Self.mb
        let half = 16 * Self.mb
        let host = RangeServer.Host(size: size) { _ in 0.003 }
        host.misplace = [half: 2]
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }

        let (result, segments, _) = await download(RangeServer.serve(host), segments: Segment.split(size: size, connections: 2, resumable: true),
                                                connections: 2, partURL: part)
        try result.get()
        expectWhole(segments, size: size)
        #expect(try Data(contentsOf: part) == RangeServer.content(0...size - 1))
    }

    @Test func replyFromTheWrongOffsetFailsOnceRetriesRunOut() async {
        let size = 8 * Self.mb
        let host = RangeServer.Host(size: size) { _ in 0.003 }
        host.misplace = [4 * Self.mb: 100]
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }

        let (result, _, _) = await download(RangeServer.serve(host), segments: Segment.split(size: size, connections: 2, resumable: true),
                                         connections: 2, partURL: part)
        guard case .failure(let error) = result, case .wrongRange? = error as? DownloadError else {
            Issue.record("expected wrongRange, got \(result)")
            return
        }
    }

    @Test func differentTotalSizeFailsAsFileChangedWithoutRetrying() async {
        let size = 8 * Self.mb
        let host = RangeServer.Host(size: size) { _ in 0.003 }
        host.reportedSize = size + 1
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }

        let (result, segments, _) = await download(RangeServer.serve(host), segments: Segment.split(size: size, connections: 2, resumable: true),
                                                connections: 2, partURL: part)
        guard case .failure(let error) = result, case .fileChanged? = error as? DownloadError else {
            Issue.record("expected fileChanged, got \(result)")
            return
        }
        // Rejected before writing: nothing from the other version reached the file.
        #expect(segments.allSatisfy { $0.done == 0 })
        // Not retried: one request per segment at most.
        #expect(host.lock.withLock { host.requests.count } <= 2)
    }

    @Test func partialFileMissingBytesIsNotReportedDone() async throws {
        let size = 4 * Self.mb
        let host = RangeServer.Host(size: size) { _ in 0.003 }
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }
        // The segments say everything is downloaded, but the partial file holds only half.
        try RangeServer.content(0...size / 2 - 1).write(to: part)
        let segments = [Segment(start: 0, end: size - 1, done: size)]

        let (result, _, _) = await download(RangeServer.serve(host), segments: segments, connections: 1, partURL: part)
        guard case .failure(let error) = result, case .incomplete? = error as? DownloadError else {
            Issue.record("expected incomplete, got \(result)")
            return
        }
    }

    @Test func bytesPastTheEndOfTheFileAreCutOff() async throws {
        let size = 4 * Self.mb
        let host = RangeServer.Host(size: size) { _ in 0.003 }
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }
        // Left over from an earlier, longer attempt.
        try (RangeServer.content(0...size - 1) + Data(repeating: 0xFF, count: 1000)).write(to: part)
        let segments = [Segment(start: 0, end: size - 1, done: size)]

        let (result, _, _) = await download(RangeServer.serve(host), segments: segments, connections: 1, partURL: part)
        try result.get()
        #expect(try Data(contentsOf: part) == RangeServer.content(0...size - 1))
    }

    @Test func connectionsThatDropAfterProgressKeepRetrying() async throws {
        let size = 8 * Self.mb
        // More drops than a segment may retry in a row; each one comes after a megabyte of progress.
        let host = RangeServer.Host(size: size) { _ in 0.003 }
        host.drops = 6
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }

        let (result, segments, _) = await download(RangeServer.serve(host), segments: Segment.split(size: size, connections: 1, resumable: true),
                                                connections: 1, partURL: part)
        try result.get()
        #expect(host.lock.withLock { host.drops } == 0)
        expectWhole(segments, size: size)
        #expect(try Data(contentsOf: part) == RangeServer.content(0...size - 1))
    }

    @Test func connectionsCutOffAfterAFewBytesRunOutOfRetries() async {
        let size = 8 * Self.mb
        // Every connection drops after one 256 KB chunk: too little progress to refill the retries.
        let host = RangeServer.Host(size: size) { _ in 0.003 }
        host.drops = 10
        host.dropAfter = 256 * 1024
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }

        let (result, _, _) = await download(RangeServer.serve(host), segments: Segment.split(size: size, connections: 1, resumable: true),
                                         connections: 1, partURL: part)
        guard case .failure(let error) = result, (error as? URLError)?.code == .networkConnectionLost else {
            Issue.record("expected the dropped connection's error, got \(result)")
            return
        }
        // The first try and five retries.
        #expect(host.lock.withLock { host.requests.count } == 6)
    }

    @Test func compressedWholeFileFromTheStartIsWritten() async throws {
        let size = 4 * Self.mb
        // Asked for a range, the server sends the whole file compressed; decompressed, it's the file.
        let host = RangeServer.Host(size: size) { _ in 0.003 }
        host.ignoreRange = true
        host.encoding = "gzip"
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }

        let (result, segments, _) = await download(RangeServer.serve(host), segments: Segment.split(size: size, connections: 1, resumable: true),
                                                connections: 1, partURL: part)
        try result.get()
        expectWhole(segments, size: size)
        #expect(try Data(contentsOf: part) == RangeServer.content(0...size - 1))
    }

    @Test func eachConnectionRunsOnItsOwnSession() async throws {
        let size = 32 * Self.mb
        let host = RangeServer.Host(size: size) { _ in 0.003 }
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }

        let (result, segments, _) = await download(RangeServer.serve(host), segments: Segment.split(size: size, connections: 4, resumable: true),
                                                connections: 4, partURL: part)
        try result.get()
        let ids = host.lock.withLock { host.taskIDs }
        // A shared session would number the first four 1, 2, 3, 4; separate sessions, each never sharing
        // a connection, all start at 1. Requests running at the same time never share a session, so
        // the same identifier on all four also proves the engine tells their tasks apart.
        #expect(ids.prefix(4) == [1, 1, 1, 1])
        expectWhole(segments, size: size)
        #expect(try Data(contentsOf: part) == RangeServer.content(0...size - 1))
    }

    @Test func asksForUncompressedBytes() async throws {
        let size = 8 * Self.mb
        let host = RangeServer.Host(size: size) { _ in 0.003 }
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }

        let (result, _, _) = await download(RangeServer.serve(host), segments: Segment.split(size: size, connections: 2, resumable: true),
                                         connections: 2, partURL: part)
        try result.get()
        let sent = host.lock.withLock { host.acceptEncodings }
        #expect(!sent.isEmpty && sent.allSatisfy { $0 == "identity" })
    }

    @Test func compressedRangedReplyIsNotWritten() async {
        let size = 8 * Self.mb
        let host = RangeServer.Host(size: size) { _ in 0.003 }
        host.encoding = "gzip"
        let part = partURL()
        defer { try? FileManager.default.removeItem(at: part) }

        let (result, segments, _) = await download(RangeServer.serve(host), segments: Segment.split(size: size, connections: 2, resumable: true),
                                                connections: 2, partURL: part)
        guard case .failure(let error) = result, case .noRangeSupport? = error as? DownloadError else {
            Issue.record("expected noRangeSupport, got \(result)")
            return
        }
        #expect(segments.allSatisfy { $0.done == 0 })
    }

    @Test func rangeProblem() {
        func check(_ header: String?, _ from: Int64, _ size: Int64?) -> String {
            switch SegmentedDownloader.rangeProblem(header, from: from, size: size) {
            case nil: "ok"
            case .wrongRange?: "wrongRange"
            case .fileChanged?: "fileChanged"
            case let other?: "\(other)"
            }
        }
        #expect(check("bytes 100-199/1000", 100, 1000) == "ok")
        #expect(check("bytes 100-199/*", 100, 1000) == "ok")
        #expect(check("bytes 100-199/1000", 100, nil) == "ok")
        #expect(check("bytes 0-99/1000", 100, 1000) == "wrongRange")
        #expect(check(nil, 100, 1000) == "wrongRange")
        #expect(check("garbage", 100, 1000) == "wrongRange")
        #expect(check("bytes 199-100/1000", 199, 1000) == "wrongRange")
        #expect(check("bytes 100-1000/1000", 100, 1000) == "wrongRange")
        #expect(check("bytes 100-199/2000", 100, 1000) == "fileChanged")
    }
}
