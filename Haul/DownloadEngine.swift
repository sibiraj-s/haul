import Foundation
import Network

nonisolated enum DownloadError: LocalizedError {
    case http(Int)
    case noRangeSupport
    case truncated
    case throttled(retryAfter: Double, status: Int)
    /// 401/403/404/410: typical of signed or time-limited links that have expired.
    case linkExpired(Int)
    /// Resume was refused because the file on the server is no longer the one we started.
    case fileChanged
    /// The link leads to an HTML page rather than a file ("Skip web pages" is on).
    case webPage
    /// 401 with a Basic or Digest challenge: the server wants a username and password.
    case signInRequired(realm: String?, digest: Bool)
    /// Not enough free space; the message says how much is needed and free.
    case diskFull(String)
    /// A 206 reply whose Content-Range is missing or starts somewhere other than the byte asked for.
    case wrongRange
    /// Every connection finished, but the partial file doesn't hold every byte of the file.
    case incomplete

    /// Worth trying again later on its own: dropped connections, timeouts, server errors.
    static func isTransient(_ error: Error) -> Bool {
        switch error {
        case let e as DownloadError:
            switch e {
            case .truncated, .throttled, .wrongRange: return true
            case .http(let code): return code >= 500 || code == 408 || code == 429
            default: return false
            }
        case let e as URLError:
            return [
                .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
                .cannotFindHost, .dnsLookupFailed, .badServerResponse, .dataNotAllowed,
            ].contains(e.code)
        default:
            return false
        }
    }

    /// Maps a failing response to the most useful error, recognising sign-in challenges.
    static func response(_ http: HTTPURLResponse) -> DownloadError {
        if http.statusCode == 401, let challenge = http.value(forHTTPHeaderField: "WWW-Authenticate") {
            let offered = challenges(challenge)
            // Basic is preferred when the server offers both.
            if let c = offered.first(where: { $0.scheme == "basic" }) ?? offered.first(where: { $0.scheme == "digest" }) {
                return .signInRequired(realm: c.realm, digest: c.scheme == "digest")
            }
        }
        return status(http.statusCode)
    }

    /// The schemes in a WWW-Authenticate header, lowercased, each with its realm. Quoted values
    /// are read as a whole, so text inside a realm can't be mistaken for a scheme.
    static func challenges(_ header: String) -> [(scheme: String, realm: String?)] {
        let tokens = header.matches(of: /"(?:[^"\\]|\\.)*"|[,=]|[^\s,="]+/).map { String($0.output) }
        var result: [(scheme: String, realm: String?)] = []
        var afterComma = true
        for (i, token) in tokens.enumerated() {
            if token == "," {
                afterComma = true
                continue
            }
            defer { afterComma = false }
            let next = i + 1 < tokens.count ? tokens[i + 1] : nil
            // A scheme starts the header or follows a comma; a parameter name is followed by "=".
            if afterComma, next != "=", !token.hasPrefix("\"") {
                result.append((token.lowercased(), nil))
            } else if token.lowercased() == "realm", next == "=", i + 2 < tokens.count, !result.isEmpty,
                result[result.count - 1].realm == nil
            {
                var value = tokens[i + 2]
                if value.hasPrefix("\""), value.count >= 2 {
                    value = String(value.dropFirst().dropLast()).replacing(/\\(.)/) { String($0.1) }
                }
                result[result.count - 1].realm = value
            }
        }
        return result
    }

    /// Maps a failing HTTP status to the most useful error.
    static func status(_ code: Int) -> DownloadError {
        [401, 403, 404, 410].contains(code) ? .linkExpired(code) : .http(code)
    }

    var isLinkProblem: Bool {
        if case .linkExpired = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .linkExpired(let code): "Link expired or no longer valid (HTTP \(code))"
        case .fileChanged: "The file changed on the server, so the partial download can't be continued"
        case .webPage: "The link opens a web page, not a file"
        case .signInRequired: "The server needs a username and password"
        case .diskFull(let message): message
        case .http(let code): "Server responded with HTTP \(code) (\(HTTPURLResponse.localizedString(forStatusCode: code)))"
        case .noRangeSupport: "Server doesn't support resuming"
        case .truncated: "Connection closed before the file finished"
        case .wrongRange: "Server sent a different part of the file than was asked for"
        case .incomplete: "Parts of the file were missing, so it wasn't saved. Retry downloads it again"
        case .throttled(_, let status): DownloadError.http(status).errorDescription
        }
    }
}

/// What the server tells us about a link before we commit to downloading it.
nonisolated enum Probe {
    struct Info: Sendable {
        var name: String
        var size: Int64?
        var acceptsRanges: Bool
        /// Validators identifying this exact version of the file; sent back as If-Range on resume.
        var etag: String?
        var lastModified: String?
        /// The server sent an HTML page rather than a file.
        var isWebPage = false
    }

    /// Requests the first byte only: a 206 reply tells us both the total size and that
    /// ranged (multi-connection, resumable) downloads will work.
    static func run(_ url: URL, browser: BrowserContext? = nil) async throws -> Info {
        for attempt in 1...3 {
            do {
                return try await once(url, browser: browser)
            } catch DownloadError.throttled(let wait, let status) {
                if attempt == 3 { throw DownloadError.http(status) }
                try await Task.sleep(for: .seconds(wait))
            }
        }
        throw URLError(.unknown)
    }

    private static func once(_ url: URL, browser: BrowserContext?) async throws -> Info {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue(acceptEncoding, forHTTPHeaderField: "Accept-Encoding")
        browser?.apply(to: &request)
        let config = ProxySettings.sessionConfiguration()
        browser?.apply(to: config)
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let (bytes, response) = try await session.bytes(for: request)
        bytes.task.cancel()
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 429 || http.statusCode == 503 {
            let wait = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 5
            throw DownloadError.throttled(retryAfter: min(30, max(1, wait)), status: http.statusCode)
        }
        guard (200..<300).contains(http.statusCode) else { throw DownloadError.response(http) }

        let (size, ranges) = sizeAndRanges(http)
        let fallback = url.lastPathComponent.isEmpty || url.lastPathComponent == "/" ? (url.host() ?? "download") : url.lastPathComponent
        let name = (http.suggestedFilename ?? fallback).replacingOccurrences(of: "/", with: "-")
        // Weak ETags (W/"…") aren't allowed in If-Range, so only keep strong ones.
        let etag = http.value(forHTTPHeaderField: "ETag").flatMap { $0.hasPrefix("W/") ? nil : $0 }
        return Info(
            name: name, size: size, acceptsRanges: ranges, etag: etag,
            lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
            isWebPage: ["text/html", "application/xhtml+xml"].contains(http.mimeType?.lowercased() ?? ""))
    }
}

extension Probe {
    /// The file's total size and whether ranged requests work, from the reply to a `bytes=0-0` request.
    nonisolated static func sizeAndRanges(_ http: HTTPURLResponse) -> (size: Int64?, ranges: Bool) {
        // Ranges and lengths would count compressed bytes, but URLSession hands over decompressed ones,
        // so the file is read in one go to its end.
        if isEncoded(http) { return (nil, false) }
        if http.statusCode == 206 {
            // "bytes 0-0/*" means the total is unknown. The body's length is just the one byte asked for.
            let size = http.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last.flatMap { Int64($0) }
            return (size, size != nil)
        }
        return (http.expectedContentLength >= 0 ? http.expectedContentLength : nil, false)
    }

    /// Requests ask for the file's own bytes, never a compressed transfer of them.
    nonisolated static let acceptEncoding = "identity"

    /// Whether the server compressed the reply despite `acceptEncoding`.
    nonisolated static func isEncoded(_ http: HTTPURLResponse) -> Bool {
        guard let encoding = http.value(forHTTPHeaderField: "Content-Encoding")?.trimmingCharacters(in: .whitespaces) else { return false }
        return !encoding.isEmpty && encoding.lowercased() != "identity"
    }

    /// Where URLSession looks up saved credentials for a sign-in challenge. Requests use the
    /// shared credential storage, so a credential saved here is sent automatically.
    static func protectionSpace(for url: URL, realm: String?, digest: Bool) -> URLProtectionSpace {
        let scheme = url.scheme?.lowercased() ?? "https"
        return URLProtectionSpace(
            host: url.host() ?? "", port: url.port ?? (scheme == "https" ? 443 : 80),
            protocol: scheme, realm: realm,
            authenticationMethod: digest ? NSURLAuthenticationMethodHTTPDigest : NSURLAuthenticationMethodHTTPBasic)
    }
}

/// Token bucket shared by every download so the speed limit applies to the total.
nonisolated final class RateLimiter: @unchecked Sendable {
    private let lock = NSLock()
    private var rate: Double = 0
    private var tokens: Double = 0
    private var last = Date()

    /// Bytes per second; 0 disables the limit.
    func setRate(_ newRate: Double) {
        lock.withLock {
            if newRate != rate {
                rate = newRate
                tokens = 0
                last = Date()
            }
        }
    }

    /// Blocks the calling (delegate) queue long enough to keep throughput under the limit.
    /// Stalling the delegate queue makes URLSession stop reading, so TCP backpressure does the rest.
    func throttle(_ bytes: Int) {
        let wait: Double = lock.withLock {
            guard rate > 0 else { return 0 }
            let now = Date()
            // Bucket holds up to 1 s of allowance (as curl's does). CFNetwork delivers data in
            // bursts, and with a smaller bucket the idle gaps between them forfeit allowance, so
            // throughput falls well short of the limit.
            tokens = min(rate, tokens + rate * now.timeIntervalSince(last))
            last = now
            tokens -= Double(bytes)
            return tokens < 0 ? -tokens / rate : 0
        }
        if wait > 0 { Thread.sleep(forTimeInterval: min(wait, 2)) }
    }
}

/// Where a connection slot's requests go.
nonisolated struct Route: Equatable, Sendable {
    /// nil goes over the Mac's default route, through URLSession; otherwise the connection is
    /// pinned to this interface.
    var interface: NWInterface?
    /// The interface's name, such as en0; for the default route, the one it goes over, if known.
    var name: String

    static let standard = Route(interface: nil, name: "")
}

/// Downloads one file over several ranged HTTP connections into a partial file,
/// writing each segment at its own offset.
///
/// Segments wait in a queue and run up to `maxParallel` at a time. When a server
/// refuses extra connections (429/503), that network's limit drops to what it accepted
/// and the refused segments wait their turn instead of failing the download.
///
/// A connection that finishes while others are still going takes the back half of
/// the segment with the most left, so every connection stays busy until the end.
///
/// With several routes, the connection slots take turns among them, so one download uses
/// several networks at once. A network that fails a connection for reasons of its own (it's
/// unreachable, sends another version of the file, or refuses what the others serve) is
/// dropped for the rest of the download, and its slots go to the networks left.
nonisolated final class SegmentedDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let url: URL
    private let partURL: URL
    private let etag: String?
    private let lastModified: String?
    private let browser: BrowserContext?
    private let limiter: RateLimiter
    private let configuration: URLSessionConfiguration
    private let completion: @Sendable (Result<Void, Error>) -> Void

    // Shared with the main thread (snapshots); guarded by `lock`.
    private let lock = NSLock()
    private var segments: [Segment]
    private var stopped = false
    private var live = 0
    private var serverLimit: Int?
    /// Segments a connection the server accepted is downloading.
    private var writing: Set<Int> = []
    /// Bytes written from each route, by its name.
    private var receivedBy: [String: Int64] = [:]

    // Only touched on `queue`, whose operations and the pinned connections' callbacks run on `serial`.
    private let serial = DispatchQueue(label: "Haul.download")
    private let queue = OperationQueue()
    /// The route each connection slot uses.
    private var slots: [Route]
    /// One session per connection slot. Sessions don't share connections, so each slot gets its own
    /// TCP connection; one shared session would multiplex every request over a single HTTP/2 connection.
    /// Only made when a route uses URLSession, and only written in `start()`.
    private var sessions: [URLSession] = []
    private var handle: FileHandle?
    private var running: [ObjectIdentifier: Running] = [:]
    private var pending: [Int] = []
    private var sleeping = 0
    private let maxParallel: Int
    /// Connections the server accepts over each network, by route name, once it has refused one there.
    /// Kept per network, as a server may limit each address on its own; one that limits the whole
    /// account refuses on every network, so each ends up with its share.
    private var limits: [String: Int] = [:]
    private var rejected: [ObjectIdentifier: Error] = [:]
    private var attempts: [Int: Int] = [:]
    private var throttles: [Int: Int] = [:]
    /// Refused parts already sent again on the next free connection; refused once more, they wait
    /// out Retry-After until the server accepts them.
    private var retriedEarly: Set<Int> = []
    /// Requests the server answered with the range asked for; only these are split.
    private var confirmed: Set<ObjectIdentifier> = []
    /// Requests that got a reply at all.
    private var answered: Set<ObjectIdentifier> = []
    /// The range end each bounded request asked for, to tell when a split has moved its segment's end.
    private var requestedEnds: [ObjectIdentifier: Int64] = [:]
    /// Connections on each pinned network that failed before a reply since its last reply, by name.
    private var unreachable: [String: Int] = [:]
    /// Cookies for pinned requests, from the same store URLSession uses; set in `start()`.
    private var cookies: HTTPCookieStorage?
    /// Networks whose server has been shown to send the same bytes as the trusted route, by name; until
    /// then their slots go over a route that is. The default route is trusted, or the first route when
    /// it isn't used.
    private var checked: Set<String> = []
    /// Each pinned network's check: the start of the file fetched over it, to compare with the partial file.
    private var checks: [String: Check] = [:]
    /// Requests stopped to be sent again another way: to hand their slot back to the network that just
    /// passed its check, or without If-Range. Their parts carry on straight away, without counting as a retry.
    private var handedOver: Set<ObjectIdentifier> = []
    /// The server answers If-Range with the whole file though it still has the same version, as one
    /// that sends an ETag it can't match does. Requests then go without it, and each reply's validator
    /// is checked on arrival instead.
    private var ifRangeUnusable = false

    private struct Check {
        var request: PinnedRequest?
        var data = Data()
        /// The server refused or sent another version.
        var refused = false
        /// The server was busy (429 or 503), so the check is tried again after this many seconds.
        var busyFor: Double?
        /// All of it arrived, waiting for the partial file to have the same bytes to compare.
        var done = false
        /// After a busy server or a failed connection, when it may be tried again.
        var notBefore = Date.distantPast
        /// Busy answers in a row so far.
        var busy = 0
    }

    /// A request in flight: the segment it downloads, its slot and the route it went out on (the slot
    /// may change routes meanwhile), the byte it started at, and how to stop it.
    private struct Running {
        let segment: Int
        let slot: Int
        let route: Route
        let from: Int64
        let ranged: Bool
        /// Sent with If-Range.
        let conditional: Bool
        let cancel: () -> Void
    }

    /// Segments with less than this left aren't split further: a new connection's setup costs more than it saves.
    static let minimumSplit: Int64 = 4 * 1024 * 1024
    /// A dropped connection that got at least this far gives its segment a fresh run of retries.
    static let progressThatRefillsRetries: Int64 = 1024 * 1024
    /// How much of the file's start a pinned network's server must send identically before it's used.
    /// Validators and size can match while the bytes don't, as with a mirror that rebuilt the file.
    static let checkLength: Int64 = 64 * 1024
    /// Connections in a row on a pinned network that fail before a reply, before that network is dropped.
    /// One could be a passing hiccup; this many means the network can't reach the server.
    static let unreachableLimit = 3
    /// Busy answers in a row to a network's check before it's dropped: a server that stays this busy
    /// over that network (as one limiting each account is while the others hold its connections) has
    /// no room for it anyway.
    static let busyLimit = 5

    /// `etag` and `lastModified` identify the version of the file captured when the download started;
    /// ranged requests carry one as If-Range so a server whose file has changed answers 200 instead of
    /// a mismatched range. For a server that can't match its own validator, replies are checked against
    /// it instead. `connections` caps how many run at once; 1 for servers that can't serve ranges.
    /// `routes` are the networks to spread those connections over.
    init(
        url: URL, partURL: URL, segments: [Segment], connections: Int, etag: String? = nil, lastModified: String? = nil,
        routes: [Route] = [.standard], browser: BrowserContext?, limiter: RateLimiter,
        configuration: URLSessionConfiguration = ProxySettings.sessionConfiguration(),
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        self.url = url
        self.partURL = partURL
        self.etag = etag
        self.lastModified = lastModified
        self.browser = browser
        self.segments = segments
        self.limiter = limiter
        self.configuration = configuration
        self.completion = completion
        maxParallel = max(1, connections)
        let routes = routes.isEmpty ? [.standard] : routes
        slots = (0..<maxParallel).map { routes[$0 % routes.count] }
        if !routes.contains(where: { $0.interface == nil }) { checked = [routes[0].name] }
        queue.maxConcurrentOperationCount = 1
        queue.underlyingQueue = serial
        super.init()
    }

    /// The segments in file order. Splits append, so the engine's own indices aren't in that order.
    func snapshot() -> [Segment] { current.sorted { $0.start < $1.start } }

    private var current: [Segment] { lock.withLock { segments } }

    /// Connections currently open, the cap the server imposed (if it pushed back), the file
    /// offset each accepted connection will write next, and the bytes written from each route.
    func connectionState() -> (live: Int, serverLimit: Int?, writingAt: [Int64], byRoute: [String: Int64]) {
        lock.withLock {
            // A finished segment's connection may not have closed yet; its next byte belongs to the next segment.
            let at = writing.filter { !segments[$0].isComplete }.map { segments[$0].start + segments[$0].done }
            return (live, serverLimit, at, receivedBy)
        }
    }

    func start() {
        let config = configuration
        config.httpMaximumConnectionsPerHost = 32
        config.timeoutIntervalForRequest = 60
        browser?.apply(to: config)
        cookies = config.httpCookieStorage
        if slots.contains(where: { $0.interface == nil }) {
            sessions = slots.map { _ in URLSession(configuration: config, delegate: self, delegateQueue: queue) }
        }
        queue.addOperation { [self] in
            do {
                if !FileManager.default.fileExists(atPath: partURL.path) {
                    FileManager.default.createFile(atPath: partURL.path, contents: nil)
                }
                handle = try FileHandle(forWritingTo: partURL)
            } catch {
                finish(.failure(error))
                return
            }
            let segments = current
            pending = segments.indices.filter { !segments[$0].isComplete }
            // Without a known size there's no saying which bytes to compare; such downloads use one route anyway.
            if knownSize == nil { checked.formUnion(slots.map(\.name)) }
            if pending.isEmpty { finish(.success(())) } else { pump() }
        }
    }

    /// Stops all connections; progress so far stays in the partial file and in `snapshot()`.
    func cancel() {
        lock.withLock {
            stopped = true
            live = 0
        }
        for session in sessions { session.invalidateAndCancel() }
        queue.addOperation { [self] in
            for request in running.values { request.cancel() }
            for check in checks.values { check.request?.cancel() }
            try? handle?.close()
            handle = nil
        }
    }

    private var isStopped: Bool { lock.withLock { stopped } }

    private func finish(_ result: Result<Void, Error>) {
        guard !isStopped else { return }
        lock.withLock {
            stopped = true
            live = 0
        }
        var result = result
        if case .success = result, let problem = verifyPart() { result = .failure(problem) }
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
        for session in sessions { session.invalidateAndCancel() }
        for request in running.values { request.cancel() }
        for check in checks.values { check.request?.cancel() }
        completion(result)
    }

    /// Checks the finished partial file is exactly the file: every byte from 0 to the end downloaded,
    /// and nothing after it. Bytes past the end, left by an earlier attempt, are cut off.
    private func verifyPart() -> DownloadError? {
        guard let handle, let expected = Segment.downloadedLength(current) else { return .incomplete }
        do {
            let length = Int64(try handle.seekToEnd())
            if length < expected { return .incomplete }
            if length > expected { try handle.truncate(atOffset: UInt64(expected)) }
            return nil
        } catch {
            return .incomplete
        }
    }

    /// Starts queued segments while there are free connection slots, then fills any slots
    /// still free by splitting running segments.
    private func pump() {
        repeat {
            while !isStopped, let slot = freeSlot(), !pending.isEmpty || splitForIdleSlot() {
                launch(pending.removeFirst(), on: slot)
            }
        } while !isStopped && advanceChecks()
        lock.withLock { live = running.count }
        if running.isEmpty && pending.isEmpty && sleeping == 0 && current.allSatisfy(\.isComplete) {
            finish(.success(()))
        }
    }

    /// Queues the back half of the running segment with the most left, for a free slot.
    /// Segments waiting to retry get the slots first, and only connections the server has
    /// accepted are split, so a throttling server isn't sent more.
    private func splitForIdleSlot() -> Bool {
        guard maxParallel > 1, pending.isEmpty, sleeping == 0 else { return false }
        let accepted = running.filter { confirmed.contains($0.key) }.values.map(\.segment)
        guard let added = lock.withLock({ Segment.splitLargest(&segments, running: accepted, minimum: Self.minimumSplit) })
        else { return false }
        pending.append(added)
        return true
    }

    /// Puts a segment back in the queue after `delay` seconds.
    private func requeue(_ index: Int, after delay: Double) {
        sleeping += 1
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.queue.addOperation {
                guard let self else { return }
                self.sleeping -= 1
                self.pending.append(index)
                self.pump()
            }
        }
    }

    /// A slot free to start a request on: within the limit, and its network's, which the server may have set.
    private func freeSlot() -> Int? {
        guard running.count < maxParallel else { return nil }
        let used = Set(running.values.map(\.slot))
        return slots.indices.first { slot in
            guard !used.contains(slot), let route = route(for: slot) else { return false }
            return limits[route.name].map { limit in running.values.count { $0.route.name == route.name } < limit } ?? true
        }
    }

    /// The connections the server allows in all, once it has limited any network: each network's limit,
    /// or for one it hasn't limited, its slots.
    private var allowed: Int? {
        guard !limits.isEmpty else { return nil }
        let names = Set(slots.map(\.name))
        return names.reduce(0) { sum, name in sum + min(limits[name] ?? .max, slots.count { $0.name == name }) }
    }

    /// The route a request on `slot` goes out on: the slot's own, or until that network has passed its
    /// check, one that has, so the download keeps every connection meanwhile.
    private func route(for slot: Int) -> Route? {
        isUsable(slots[slot]) ? slots[slot] : slots.first(where: isUsable)
    }

    private func isUsable(_ route: Route) -> Bool { route.interface == nil || checked.contains(route.name) }

    /// The file's size, once every segment's end is known.
    private var knownSize: Int64? {
        let s = current
        let ends = s.compactMap(\.end)
        return !s.isEmpty && ends.count == s.count ? ends.max().map { $0 + 1 } : nil
    }

    private func launch(_ index: Int, on slot: Int) {
        let s = current[index]
        var request = URLRequest(url: url)
        request.setValue(Probe.acceptEncoding, forHTTPHeaderField: "Accept-Encoding")
        browser?.apply(to: &request)
        let from = s.start + s.done
        if let end = s.end {
            request.setValue("bytes=\(from)-\(end)", forHTTPHeaderField: "Range")
        } else if from > 0 {
            request.setValue("bytes=\(from)-", forHTTPHeaderField: "Range")
        }
        let ranged = request.value(forHTTPHeaderField: "Range") != nil
        guard let route = route(for: slot) else { return pending.insert(index, at: 0) }
        let id: ObjectIdentifier
        let cancel: () -> Void
        let start: () -> Void
        var conditional = false
        if let interface = route.interface {
            // Another server may tag the same file differently, so instead of If-Range each reply's
            // validators are checked on arrival (`sameFile`).
            let pinned = pinnedRequest(
                request, over: interface,
                onResponse: { [weak self] request, response in
                    guard let self else { return false }
                    let allow = received(response, ObjectIdentifier(request))
                    if allow { pump() }
                    return allow
                },
                onData: { [weak self] request, data in
                    self?.receivedData(data, ObjectIdentifier(request))
                },
                onComplete: { [weak self] request, error in
                    self?.completed(ObjectIdentifier(request), error)
                })
            id = ObjectIdentifier(pinned)
            cancel = { pinned.cancel() }
            start = { pinned.start() }
        } else {
            if ranged, !ifRangeUnusable, let ifRange = etag ?? lastModified {
                request.setValue(ifRange, forHTTPHeaderField: "If-Range")
                conditional = true
            }
            // Every slot has a session when any route uses URLSession.
            let task = sessions[slot].dataTask(with: request)
            id = ObjectIdentifier(task)
            cancel = { task.cancel() }
            start = { task.resume() }
        }
        running[id] = Running(
            segment: index, slot: slot, route: route, from: from, ranged: ranged, conditional: conditional, cancel: cancel)
        if let end = s.end { requestedEnds[id] = end }
        start()
    }

    /// A request over `interface`, with cookies from the store URLSession uses.
    private func pinnedRequest(
        _ request: URLRequest, over interface: NWInterface,
        onResponse: @escaping (PinnedRequest, HTTPURLResponse) -> Bool,
        onData: @escaping (PinnedRequest, Data) -> Void,
        onComplete: @escaping (PinnedRequest, Error?) -> Void
    ) -> PinnedRequest {
        let cookies = cookies
        return PinnedRequest(
            request, over: interface, queue: serial,
            cookies: { url in
                HTTPCookie.requestHeaderFields(with: cookies?.cookies(for: url) ?? [])
            }, onResponse: onResponse, onData: onData, onComplete: onComplete)
    }

    /// How long a busy server (429 or 503) asks to wait: Retry-After, kept between 1 and 60 seconds.
    private static func busyWait(_ http: HTTPURLResponse) -> Double? {
        guard http.statusCode == 429 || http.statusCode == 503 else { return nil }
        return min(60, max(1, http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 5))
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let allow = received(response, ObjectIdentifier(dataTask))
        completionHandler(allow ? .allow : .cancel)
        // Free slots may now be filled from this connection's segment.
        if allow { pump() }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData(data, ObjectIdentifier(dataTask))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        completed(ObjectIdentifier(task), error)
    }

    /// Whether to accept the reply to request `id`; a refused one is cancelled, with the reason in `rejected`.
    private func received(_ response: URLResponse, _ id: ObjectIdentifier) -> Bool {
        guard let request = running[id] else { return false }
        let index = request.segment
        answered.insert(id)
        let pinned = request.route.interface != nil
        if pinned { unreachable[request.route.name] = nil }
        if let http = response as? HTTPURLResponse {
            if let wait = Self.busyWait(http) {
                rejected[id] = DownloadError.throttled(retryAfter: wait, status: http.statusCode)
                return false
            }
            if !(200..<300).contains(http.statusCode) {
                rejected[id] = DownloadError.response(http)
                return false
            }
            // Server ignored our Range header and is sending the whole file. That's only
            // usable when this is the sole segment and it starts at byte zero.
            let s = current
            if request.ranged && http.statusCode != 206 && !(s.count == 1 && s[index].start + s[index].done == 0) {
                // With If-Range, a full 200 reply means the validator no longer matches. Unless the reply
                // still carries it: then the server can't match its own validator, and the part is sent
                // again without If-Range.
                let matches = validatorMatches(http)
                if request.conditional && matches == true {
                    ifRangeUnusable = true
                    handedOver.insert(id)
                } else {
                    // A pinned network's server may tag the same file differently, so its ETag isn't held against it.
                    let changed = request.conditional || (!pinned && matches == false)
                    rejected[id] = changed ? DownloadError.fileChanged : DownloadError.noRangeSupport
                }
                return false
            }
            // Offsets in a compressed partial reply don't match the bytes URLSession hands over after
            // decompressing. A whole-file 200 from byte 0 is fine: decompressed, it's the file. Pinned
            // connections don't decompress, so they take neither.
            if (http.statusCode == 206 || pinned) && Probe.isEncoded(http) {
                rejected[id] = DownloadError.noRangeSupport
                return false
            }
            if pinned && !Self.sameFile(http, etag: etag, lastModified: lastModified) {
                rejected[id] = DownloadError.fileChanged
                return false
            }
            // Without If-Range the server sends the range whatever version it has, so that's checked here.
            // A reply without that validator says nothing either way; its total size is still checked.
            if !pinned && request.ranged && !request.conditional && validatorMatches(http) == false {
                rejected[id] = DownloadError.fileChanged
                return false
            }
            if http.statusCode == 206 && request.ranged {
                // Nothing of this reply is written yet, so the segment's next byte is still where the request started.
                let ends = s.compactMap(\.end)
                let size = ends.count == s.count ? ends.max().map { $0 + 1 } : nil
                if let problem = Self.rangeProblem(
                    http.value(forHTTPHeaderField: "Content-Range"),
                    from: s[index].start + s[index].done, size: size)
                {
                    rejected[id] = problem
                    return false
                }
            }
            if http.statusCode == 206 { confirmed.insert(id) }
        }
        retriedEarly.remove(index)
        lock.withLock { _ = writing.insert(index) }
        return true
    }

    private func receivedData(_ data: Data, _ id: ObjectIdentifier) {
        guard let request = running[id], let handle, !isStopped else { return }
        let index = request.segment
        let s = current[index]
        let offset = s.start + s.done
        var chunk = data
        if let end = s.end {
            let remaining = end - offset + 1
            if remaining <= 0 { return request.cancel() }
            if Int64(chunk.count) > remaining { chunk = chunk.prefix(Int(remaining)) }
        }
        do {
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: chunk)
        } catch {
            rejected[id] = error
            return request.cancel()
        }
        let complete = lock.withLock {
            segments[index].done += Int64(chunk.count)
            receivedBy[request.route.name, default: 0] += Int64(chunk.count)
            return segments[index].isComplete
        }
        limiter.throttle(chunk.count)
        // A split moved this segment's end short of the range asked for; stop before reading into the other half.
        if complete, let asked = requestedEnds[id], asked != s.end { request.cancel() }
        // The start of the file a network's check waits on may have just arrived.
        if s.start == 0 && checks.values.contains(where: \.done) && advanceChecks() { pump() }
    }

    private func completed(_ id: ObjectIdentifier, _ error: Error?) {
        guard let request = running.removeValue(forKey: id), !isStopped else { return }
        let index = request.segment
        let from = request.from
        lock.withLock { _ = writing.remove(index) }
        let rejection = rejected.removeValue(forKey: id)
        let wasAnswered = answered.remove(id) != nil
        confirmed.remove(id)
        requestedEnds[id] = nil
        defer { pump() }

        // Unknown-length stream ended cleanly: now we know where it ends.
        if error == nil, rejection == nil {
            lock.withLock {
                if segments[index].end == nil { segments[index].end = segments[index].start + segments[index].done - 1 }
            }
        }
        if handedOver.remove(id) != nil {
            if !current[index].isComplete { pending.insert(index, at: 0) }
            return
        }
        if current[index].isComplete { return }

        if case .throttled(let wait, let status) = rejection as? DownloadError {
            // A first refusal shows what the server allows over that network: its connections still open.
            // A part refused again was only retrying a slot, so it leaves the limit alone.
            if !retriedEarly.contains(index) && throttles[index] == nil {
                let name = request.route.name
                let open = running.values.count { $0.route.name == name }
                limits[name] = max(1, min(limits[name] ?? maxParallel, open))
                lock.withLock { serverLimit = allowed }
            }
            // The server usually has room again as soon as one of the open connections ends, well before
            // Retry-After, so the part takes the next connection to free up. Refused again straight after,
            // the server is limiting how often rather than how many, so until it's accepted the part
            // waits Retry-After out.
            if !running.isEmpty && retriedEarly.insert(index).inserted { return pending.append(index) }
            let count = (throttles[index] ?? 0) + 1
            throttles[index] = count
            // Give up after 120 waits, however long the server's Retry-After makes them.
            guard count <= 120 else { return finish(.failure(DownloadError.http(status))) }
            return requeue(index, after: wait)
        }
        // Anything but a refusal, and the part may take the next free connection if it's refused later.
        retriedEarly.remove(index)

        // On another network, a refused reply is that network's problem, not the file's: drop the network
        // and give the part to the others. So is a connection that never got a reply, once it keeps happening.
        if request.route.interface != nil {
            let name = request.route.name
            var unusable = rejection is DownloadError || error is PinnedRequest.Failure
            if !unusable, rejection == nil, error != nil, !wasAnswered {
                unreachable[name, default: 0] += 1
                unusable = unreachable[name]! >= Self.unreachableLimit
                if !unusable { return requeue(index, after: 1) }
            }
            if unusable {
                guard drop(request.route) else { return finish(.failure(rejection ?? error ?? DownloadError.truncated)) }
                return pending.append(index)
            }
        }

        // A wrong range may come from one bad cache node, so it's retried like a dropped connection.
        let wrongRange = if case .wrongRange? = rejection as? DownloadError { true } else { false }
        if let rejection, !wrongRange { return finish(.failure(rejection)) }

        // A connection that moved its segment well forward before dropping starts a fresh run of retries:
        // the limit is for connections that keep failing, not for long downloads on a flaky network.
        // Only real progress counts, so one cut off after every few bytes still runs out.
        if current[index].start + current[index].done - from >= Self.progressThatRefillsRetries { attempts[index] = nil }
        let attempt = (attempts[index] ?? 0) + 1
        attempts[index] = attempt
        guard attempt <= 5 else { return finish(.failure(rejection ?? error ?? DownloadError.truncated)) }
        requeue(index, after: Double(attempt))
    }

    /// Starts a check on each pinned network that hasn't had one, and compares those that are done
    /// with the partial file. True when a network passed, so its slots can take requests.
    private func advanceChecks() -> Bool {
        guard let size = knownSize else { return false }
        let length = min(size, Self.checkLength)
        var names = Set<String>()
        for route in slots where !isUsable(route) && names.insert(route.name).inserted {
            if let check = checks[route.name], check.request != nil || check.done || check.notBefore > Date() { continue }
            startCheck(route, length: length, size: size)
        }
        // The partial file holds the start of the file once the segment from byte 0 has got that far.
        guard current.contains(where: { $0.start == 0 && $0.done >= length }) else { return false }
        var passed = false
        // Dropping a network that failed can drop others' checks too, so each is looked up as it comes.
        for name in checks.keys.sorted() {
            guard let check = checks[name], check.done else { continue }
            checks[name] = nil
            let reference = try? FileHandle(forReadingFrom: partURL).read(upToCount: Int(length))
            if reference == check.data {
                checked.insert(name)
                passed = true
                // The connections lent to the trusted route meanwhile move over to this network.
                let lent = running.filter { slots[$0.value.slot].name == name && $0.value.route.name != name }
                handedOver.formUnion(lent.keys)
                for request in lent.values { request.cancel() }
            } else if let route = slots.first(where: { $0.name == name }), !drop(route) {
                finish(.failure(DownloadError.fileChanged))
            }
        }
        return passed
    }

    /// Fetches the start of the file over `route`'s network, held in `checks` until it can be compared.
    private func startCheck(_ route: Route, length: Int64, size: Int64) {
        guard let interface = route.interface else { return }
        var request = URLRequest(url: url)
        request.setValue(Probe.acceptEncoding, forHTTPHeaderField: "Accept-Encoding")
        browser?.apply(to: &request)
        request.setValue("bytes=0-\(length - 1)", forHTTPHeaderField: "Range")
        let name = route.name
        let etag = etag
        let lastModified = lastModified
        let check = pinnedRequest(
            request, over: interface,
            onResponse: { [weak self] _, http in
                guard let self else { return false }
                // Busy, as a server that allows a few connections per account is while the others hold them.
                if let wait = Self.busyWait(http) {
                    checks[name]?.busyFor = wait
                    return false
                }
                let same =
                    http.statusCode == 206 && !Probe.isEncoded(http) && Self.sameFile(http, etag: etag, lastModified: lastModified)
                    && Self.rangeProblem(http.value(forHTTPHeaderField: "Content-Range"), from: 0, size: size) == nil
                if !same { checks[name]?.refused = true }
                return same
            },
            onData: { [weak self] _, data in
                self?.checks[name]?.data.append(data)
            },
            onComplete: { [weak self] _, error in
                self?.checkEnded(route, error, length: length)
            })
        checks[name] = Check(request: check, busy: checks[name]?.busy ?? 0)
        check.start()
    }

    private func checkEnded(_ route: Route, _ error: Error?, length: Int64) {
        guard !isStopped, var check = checks[route.name] else { return }
        check.request = nil
        if let wait = check.busyFor {
            guard check.busy + 1 >= Self.busyLimit else { return retryCheck(route, after: wait, busy: check.busy + 1) }
            checks[route.name] = nil
            if !drop(route) { finish(.failure(DownloadError.throttled(retryAfter: wait, status: 503))) }
            return pump()
        }
        if check.refused || error is PinnedRequest.Failure {
            checks[route.name] = nil
            if !drop(route) { finish(.failure(DownloadError.fileChanged)) }
        } else if error != nil || Int64(check.data.count) != length {
            // Cut off or never answered: tried again shortly, like any connection on that network.
            unreachable[route.name, default: 0] += 1
            guard unreachable[route.name]! >= Self.unreachableLimit else { return retryCheck(route, after: 1) }
            checks[route.name] = nil
            if !drop(route) { finish(.failure(error ?? DownloadError.truncated)) }
        } else {
            unreachable[route.name] = nil
            check.done = true
            checks[route.name] = check
        }
        pump()
    }

    /// Tries `route`'s check again once `delay` seconds have passed, and not before.
    private func retryCheck(_ route: Route, after delay: Double, busy: Int = 0) {
        checks[route.name] = Check(notBefore: Date() + delay, busy: busy)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in self?.queue.addOperation { self?.pump() } }
    }

    /// Stops using `dropped` for this download, handing its slots to the routes left. False when there
    /// are none; true when it was already dropped, as by another of its connections failing first.
    private func drop(_ dropped: Route) -> Bool {
        guard slots.contains(dropped) else { return true }
        checks.removeValue(forKey: dropped.name)?.request?.cancel()
        var left: [Route] = []
        for route in slots where route != dropped && !left.contains(route) { left.append(route) }
        guard !left.isEmpty else { return false }
        var next = 0
        for i in slots.indices where slots[i] == dropped {
            slots[i] = left[next % left.count]
            next += 1
        }
        // With the trusted route gone, nothing could fetch the start of the file the others are checked
        // against, so the first left takes its place; its replies' validators and size are still checked.
        if !left.contains(where: isUsable) { checked.insert(left[0].name) }
        return true
    }

    /// Whether a reply carries the validator sent as If-Range unchanged; nil when it has none of that
    /// kind. Stricter than `sameFile`: this is the server the validator came from, so another ETag
    /// means another version even when Last-Modified is the same.
    private func validatorMatches(_ http: HTTPURLResponse) -> Bool? {
        if let etag { return http.value(forHTTPHeaderField: "ETag").map { $0 == etag } }
        if let lastModified { return http.value(forHTTPHeaderField: "Last-Modified").map { $0 == lastModified } }
        return nil
    }

    /// Whether a reply from another network is for the version of the file the download started with.
    /// Mirrors often tag the same file with ETags of their own, so a matching Last-Modified also counts;
    /// the total size in Content-Range is checked separately.
    nonisolated static func sameFile(_ http: HTTPURLResponse, etag: String?, lastModified: String?) -> Bool {
        if let etag, http.value(forHTTPHeaderField: "ETag") == etag { return true }
        if let lastModified { return http.value(forHTTPHeaderField: "Last-Modified") == lastModified }
        return etag == nil
    }

    /// Why a 206 reply to a request starting at `from` can't be written there, or nil if it can.
    /// `size` is the file's total when known; a different total means the server has another version.
    nonisolated static func rangeProblem(_ header: String?, from: Int64, size: Int64?) -> DownloadError? {
        // "bytes first-last/total", where total may be "*".
        guard let header, let match = header.wholeMatch(of: /\s*bytes\s+(\d+)-(\d+)\/(\d+|\*)\s*/),
            let first = Int64(match.1), let last = Int64(match.2), first <= last
        else { return .wrongRange }
        if let total = Int64(match.3) {
            if last >= total { return .wrongRange }
            if let size, total != size { return .fileChanged }
        }
        return first == from ? nil : .wrongRange
    }
}
