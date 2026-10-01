import Foundation

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

    /// Worth trying again later on its own: dropped connections, timeouts, server errors.
    static func isTransient(_ error: Error) -> Bool {
        switch error {
        case let e as DownloadError:
            switch e {
            case .truncated, .throttled: return true
            case .http(let code): return code >= 500 || code == 408 || code == 429
            default: return false
            }
        case let e as URLError:
            return [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
                    .cannotFindHost, .dnsLookupFailed, .badServerResponse, .dataNotAllowed].contains(e.code)
        default:
            return false
        }
    }

    /// Maps a failing response to the most useful error, recognising sign-in challenges.
    static func response(_ http: HTTPURLResponse) -> DownloadError {
        if http.statusCode == 401, let challenge = http.value(forHTTPHeaderField: "WWW-Authenticate") {
            let lower = challenge.lowercased()
            if lower.hasPrefix("basic") || lower.hasPrefix("digest") || lower.contains(", basic") || lower.contains(", digest") {
                let realm = challenge.firstMatch(of: /realm="([^"]*)"/).map { String($0.1) }
                return .signInRequired(realm: realm, digest: !lower.contains("basic"))
            }
        }
        return status(http.statusCode)
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
    static func run(_ url: URL) async throws -> Info {
        for attempt in 1...3 {
            do {
                return try await once(url)
            } catch DownloadError.throttled(let wait, let status) {
                if attempt == 3 { throw DownloadError.http(status) }
                try await Task.sleep(for: .seconds(wait))
            }
        }
        throw URLError(.unknown)
    }

    private static func once(_ url: URL) async throws -> Info {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        bytes.task.cancel()
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 429 || http.statusCode == 503 {
            let wait = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 5
            throw DownloadError.throttled(retryAfter: min(30, max(1, wait)), status: http.statusCode)
        }
        guard (200..<300).contains(http.statusCode) else { throw DownloadError.response(http) }

        var size: Int64?
        var ranges = false
        if http.statusCode == 206,
           let total = http.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last,
           let n = Int64(total) {
            size = n
            ranges = true
        } else if http.expectedContentLength >= 0 {
            size = http.expectedContentLength
        }
        let fallback = url.lastPathComponent.isEmpty || url.lastPathComponent == "/" ? (url.host() ?? "download") : url.lastPathComponent
        let name = (http.suggestedFilename ?? fallback).replacingOccurrences(of: "/", with: "-")
        // Weak ETags (W/"…") aren't allowed in If-Range, so only keep strong ones.
        let etag = http.value(forHTTPHeaderField: "ETag").flatMap { $0.hasPrefix("W/") ? nil : $0 }
        return Info(name: name, size: size, acceptsRanges: ranges, etag: etag,
                    lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
                    isWebPage: ["text/html", "application/xhtml+xml"].contains(http.mimeType?.lowercased() ?? ""))
    }
}

extension Probe {
    /// Where URLSession looks up saved credentials for a sign-in challenge. Requests use the
    /// shared credential storage, so a credential saved here is sent automatically.
    static func protectionSpace(for url: URL, realm: String?, digest: Bool) -> URLProtectionSpace {
        let scheme = url.scheme?.lowercased() ?? "https"
        return URLProtectionSpace(host: url.host() ?? "", port: url.port ?? (scheme == "https" ? 443 : 80),
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
            if newRate != rate { rate = newRate; tokens = 0; last = Date() }
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

/// Downloads one file over several ranged HTTP connections into a partial file,
/// writing each segment at its own offset.
///
/// Segments wait in a queue and run up to `maxParallel` at a time. When a server
/// refuses extra connections (429/503), the limit drops to what it accepted and the
/// refused segments wait their turn instead of failing the download.
nonisolated final class SegmentedDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let url: URL
    private let partURL: URL
    private let ifRange: String?
    private let limiter: RateLimiter
    private let completion: @Sendable (Result<Void, Error>) -> Void

    // Shared with the main thread (snapshots); guarded by `lock`.
    private let lock = NSLock()
    private var segments: [Segment]
    private var stopped = false
    private var live = 0
    private var serverLimit: Int?

    // Only touched on `queue`.
    private let queue = OperationQueue()
    private var session: URLSession?
    private var handle: FileHandle?
    private var tasks: [Int: Int] = [:]
    private var pending: [Int] = []
    private var sleeping = 0
    private var maxParallel: Int
    private var rejected: [Int: Error] = [:]
    private var attempts: [Int: Int] = [:]
    private var throttles: [Int: Int] = [:]

    /// `ifRange` is the ETag or Last-Modified captured when the download started; ranged
    /// requests carry it so a server whose file has changed answers 200 instead of a mismatched range.
    init(url: URL, partURL: URL, segments: [Segment], ifRange: String?, limiter: RateLimiter,
         completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        self.url = url
        self.partURL = partURL
        self.ifRange = ifRange
        self.segments = segments
        self.limiter = limiter
        self.completion = completion
        maxParallel = max(1, segments.count)
        queue.maxConcurrentOperationCount = 1
        super.init()
    }

    func snapshot() -> [Segment] { lock.withLock { segments } }

    /// Connections currently open, and the cap the server imposed (if it pushed back).
    func connectionState() -> (live: Int, serverLimit: Int?) { lock.withLock { (live, serverLimit) } }

    func start() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 32
        config.timeoutIntervalForRequest = 60
        session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
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
            let current = snapshot()
            pending = current.indices.filter { !current[$0].isComplete }
            if pending.isEmpty { finish(.success(())) } else { pump() }
        }
    }

    /// Stops all connections; progress so far stays in the partial file and in `snapshot()`.
    func cancel() {
        lock.withLock { stopped = true; live = 0 }
        session?.invalidateAndCancel()
        queue.addOperation { [self] in
            try? handle?.close()
            handle = nil
        }
    }

    private var isStopped: Bool { lock.withLock { stopped } }

    private func finish(_ result: Result<Void, Error>) {
        guard !isStopped else { return }
        lock.withLock { stopped = true; live = 0 }
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
        session?.invalidateAndCancel()
        completion(result)
    }

    /// Starts queued segments while there are free connection slots.
    private func pump() {
        while tasks.count < maxParallel, !pending.isEmpty {
            launch(pending.removeFirst())
        }
        lock.withLock { live = tasks.count }
        if tasks.isEmpty && pending.isEmpty && sleeping == 0 && snapshot().allSatisfy(\.isComplete) {
            finish(.success(()))
        }
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

    private func launch(_ index: Int) {
        guard !isStopped, let session else { return }
        let s = snapshot()[index]
        var request = URLRequest(url: url)
        let from = s.start + s.done
        if let end = s.end {
            request.setValue("bytes=\(from)-\(end)", forHTTPHeaderField: "Range")
        } else if from > 0 {
            request.setValue("bytes=\(from)-", forHTTPHeaderField: "Range")
        }
        if let ifRange, request.value(forHTTPHeaderField: "Range") != nil {
            request.setValue(ifRange, forHTTPHeaderField: "If-Range")
        }
        let task = session.dataTask(with: request)
        tasks[task.taskIdentifier] = index
        task.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let index = tasks[dataTask.taskIdentifier] else { return completionHandler(.cancel) }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 || http.statusCode == 503 {
                let wait = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 5
                rejected[dataTask.taskIdentifier] = DownloadError.throttled(retryAfter: min(60, max(1, wait)), status: http.statusCode)
                return completionHandler(.cancel)
            }
            if !(200..<300).contains(http.statusCode) {
                rejected[dataTask.taskIdentifier] = DownloadError.response(http)
                return completionHandler(.cancel)
            }
            // Server ignored our Range header and is sending the whole file. That's only
            // usable when this is the sole segment and it starts at byte zero.
            let ranged = dataTask.originalRequest?.value(forHTTPHeaderField: "Range") != nil
            let s = snapshot()
            if ranged && http.statusCode != 206 && !(s.count == 1 && s[index].start + s[index].done == 0) {
                // With If-Range, a full 200 reply means the validator no longer matches.
                rejected[dataTask.taskIdentifier] = ifRange != nil ? DownloadError.fileChanged : DownloadError.noRangeSupport
                return completionHandler(.cancel)
            }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let index = tasks[dataTask.taskIdentifier], let handle, !isStopped else { return }
        let s = snapshot()[index]
        let offset = s.start + s.done
        var chunk = data
        if let end = s.end {
            let remaining = end - offset + 1
            if remaining <= 0 { return dataTask.cancel() }
            if Int64(chunk.count) > remaining { chunk = chunk.prefix(Int(remaining)) }
        }
        do {
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: chunk)
        } catch {
            rejected[dataTask.taskIdentifier] = error
            return dataTask.cancel()
        }
        lock.withLock { segments[index].done += Int64(chunk.count) }
        limiter.throttle(chunk.count)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let index = tasks.removeValue(forKey: task.taskIdentifier), !isStopped else { return }
        let rejection = rejected.removeValue(forKey: task.taskIdentifier)
        defer { pump() }

        // Unknown-length stream ended cleanly: now we know where it ends.
        if error == nil, rejection == nil {
            lock.withLock {
                if segments[index].end == nil { segments[index].end = segments[index].start + segments[index].done - 1 }
            }
        }
        if snapshot()[index].isComplete { return }

        if case .throttled(let wait, let status) = rejection as? DownloadError {
            // The connections still open are what this server allows.
            maxParallel = max(1, min(maxParallel, tasks.count))
            lock.withLock { serverLimit = maxParallel }
            let count = (throttles[index] ?? 0) + 1
            throttles[index] = count
            // Keep waiting for a slot for up to ~10 minutes before giving up.
            guard count <= 120 else { return finish(.failure(DownloadError.http(status))) }
            return requeue(index, after: wait)
        }
        if let rejection { return finish(.failure(rejection)) }

        let attempt = (attempts[index] ?? 0) + 1
        attempts[index] = attempt
        guard attempt <= 5 else { return finish(.failure(error ?? DownloadError.truncated)) }
        requeue(index, after: Double(attempt))
    }
}
