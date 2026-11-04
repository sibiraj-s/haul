import Foundation
import Network

/// One HTTP/1.1 GET over a connection pinned to a network interface. On macOS URLSession can't
/// be told which interface to use, so a download's connections on its other networks go
/// through this instead.
///
/// It reports like a URLSession data task: the response, which may be refused, then the body,
/// then completion, which comes exactly once, also after `cancel()`, and like a data task's, later
/// rather than from inside `cancel()`, so a handler can cancel requests freely. The next read only starts
/// once `onData` returns, so a slow handler slows the connection, as the speed limit relies on.
/// Every callback runs on `queue`, which must be serial, and `start()` and `cancel()` must be
/// called on it too.
nonisolated final class PinnedRequest: @unchecked Sendable {
    /// Why a connection on that network didn't get as far as a reply.
    enum Failure: LocalizedError {
        /// The connection went out over another interface, as a VPN's kill switch makes it.
        case notOnInterface
        case badResponse

        var errorDescription: String? {
            switch self {
            case .notOnInterface: "The connection didn't go over the network it was meant for"
            case .badResponse: "The server's reply couldn't be read"
            }
        }
    }

    let onResponse: (PinnedRequest, HTTPURLResponse) -> Bool
    let onData: (PinnedRequest, Data) -> Void
    let onComplete: (PinnedRequest, Error?) -> Void
    /// The Cookie header for a URL, as URLSession would send it: asked again for each host a redirect leads to.
    private let cookies: (URL) -> [String: String]
    private let idleLimit: TimeInterval

    /// The request as it stands: redirects change its URL.
    private var request: URLRequest
    private var redirects = 0
    private let interface: NWInterface
    private let queue: DispatchQueue
    private var connection: NWConnection?
    private var finished = false
    /// Received but not yet handled: the head while it's incomplete, and chunked framing.
    private var buffer = Data()
    private var body: Body?
    private var waitTimeout: DispatchWorkItem?
    /// Fails a connection that has gone quiet, reset whenever something arrives.
    private var idleTimeout: DispatchWorkItem?

    private enum Body {
        case length(Int64)
        /// Reading a chunk-size line, or `left` bytes of a chunk followed by its CRLF.
        case chunked(left: Int64?)
        case trailers
        case untilClose
    }

    /// How long a connection may wait for its network before the network counts as unusable.
    static let waitLimit: TimeInterval = 8
    /// How long a connection may go without receiving anything; URLSession's request timeout for downloads.
    static let idleLimit: TimeInterval = 60
    /// As many redirects as a link may take before its reply is taken as it is.
    static let maxRedirects = 5
    /// The most a reply's head may take; servers send a few KB at most.
    static let maxHead = 64 * 1024

    init(
        _ request: URLRequest, over interface: NWInterface, queue: DispatchQueue,
        cookies: @escaping (URL) -> [String: String] = { _ in [:] }, idleLimit: TimeInterval = PinnedRequest.idleLimit,
        onResponse: @escaping (PinnedRequest, HTTPURLResponse) -> Bool, onData: @escaping (PinnedRequest, Data) -> Void,
        onComplete: @escaping (PinnedRequest, Error?) -> Void
    ) {
        self.request = request
        self.interface = interface
        self.queue = queue
        self.cookies = cookies
        self.idleLimit = idleLimit
        self.onResponse = onResponse
        self.onData = onData
        self.onComplete = onComplete
    }

    func start() {
        if let url = request.url {
            for (name, value) in cookies(url) where request.value(forHTTPHeaderField: name) == nil {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
        connect()
    }

    private func connect() {
        guard let url = request.url, let host = url.host(), let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http"
        else { return finish(URLError(.unsupportedURL)) }
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 15
        let parameters: NWParameters
        if scheme == "https" {
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
            parameters = NWParameters(tls: tls, tcp: tcp)
        } else {
            parameters = NWParameters(tls: nil, tcp: tcp)
        }
        parameters.requiredInterface = interface
        parameters.preferNoProxies = true
        let port = UInt16(url.port ?? (scheme == "https" ? 443 : 80))
        let connection = NWConnection(host: .init(host), port: .init(rawValue: port) ?? .https, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, connection === self.connection else { return }
            changed(state)
        }
        connection.start(queue: queue)
    }

    func cancel() { finish(URLError(.cancelled), later: true) }

    private func finish(_ error: Error?, later: Bool = false) {
        guard !finished else { return }
        finished = true
        waitTimeout?.cancel()
        idleTimeout?.cancel()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        if later {
            queue.async { self.onComplete(self, error) }
        } else {
            onComplete(self, error)
        }
    }

    private func changed(_ state: NWConnection.State) {
        guard !finished else { return }
        switch state {
        case .ready:
            waitTimeout?.cancel()
            waitTimeout = nil
            heardFrom()
            guard let connection, Self.isLocal(connection.currentPath?.localEndpoint, on: interface.name) else {
                return finish(Failure.notOnInterface)
            }
            connection.send(
                content: head(),
                completion: .contentProcessed { [weak self, weak connection] error in
                    guard let self, let error, connection === self.connection else { return }
                    finish(Self.urlError(error))
                })
            receive(on: connection)
        case .waiting(let error):
            // Waiting usually means the network is gone or blocked; it rarely comes back in time.
            // Already counting down; a cancelled one is from an earlier wait the connection got over.
            if let waitTimeout, !waitTimeout.isCancelled { return }
            let timeout = DispatchWorkItem { [weak self] in self?.finish(Self.urlError(error)) }
            waitTimeout = timeout
            queue.asyncAfter(deadline: .now() + Self.waitLimit, execute: timeout)
        case .failed(let error):
            finish(Self.urlError(error))
        default:
            break
        }
    }

    /// The request line and headers. Each request gets its own connection, closed after it.
    private func head() -> Data {
        let url = request.url!
        var target = url.path(percentEncoded: true)
        if target.isEmpty { target = "/" }
        if let query = url.query(percentEncoded: true) { target += "?" + query }
        var host = url.host(percentEncoded: true) ?? ""
        if host.contains(":") { host = "[\(host)]" }
        if let port = url.port { host += ":\(port)" }
        var fields = request.allHTTPHeaderFields ?? [:]
        fields["Host"] = host
        fields["Connection"] = "close"
        if fields["User-Agent"] == nil { fields["User-Agent"] = Self.userAgent }
        if fields["Accept"] == nil { fields["Accept"] = "*/*" }
        var text = "GET \(target) HTTP/1.1\r\n"
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) where BrowserContext.isHeaderSafe(name + value) {
            text += "\(name): \(value)\r\n"
        }
        return Data((text + "\r\n").utf8)
    }

    private static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
        return "Haul/\(version)"
    }()

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, complete, error in
            // A redirect moves on to another connection; anything still arriving on this one is stale.
            guard let self, !finished, connection === self.connection else { return }
            if let data, !data.isEmpty {
                heardFrom()
                consume(data)
            }
            guard !finished, connection === self.connection else { return }
            if let error { return finish(Self.urlError(error)) }
            if complete { return ended() }
            receive(on: connection)
        }
    }

    /// Restarts the idle timeout: the connection is alive.
    private func heardFrom() {
        idleTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in self?.finish(URLError(.timedOut)) }
        idleTimeout = timeout
        queue.asyncAfter(deadline: .now() + idleLimit, execute: timeout)
    }

    /// Follows a redirect as URLSession would, on a new connection over the same interface. Cookies
    /// and credentials were for the first host, so they don't go to another one, and https never
    /// gives way to http.
    private func redirect(_ response: HTTPURLResponse) -> Bool {
        guard [301, 302, 303, 307, 308].contains(response.statusCode), redirects < Self.maxRedirects,
            let location = response.value(forHTTPHeaderField: "Location"), let from = request.url,
            let to = URL(string: location, relativeTo: from)?.absoluteURL,
            to.scheme?.lowercased() == "https" || (to.scheme?.lowercased() == "http" && from.scheme?.lowercased() == "http")
        else { return false }
        redirects += 1
        if to.host()?.lowercased() != from.host()?.lowercased() {
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            // That host's own cookies, which may be none.
            request.setValue(nil, forHTTPHeaderField: "Cookie")
            for (name, value) in cookies(to) { request.setValue(value, forHTTPHeaderField: name) }
        }
        request.url = to
        waitTimeout?.cancel()
        waitTimeout = nil
        idleTimeout?.cancel()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        buffer = Data()
        body = nil
        connect()
        return true
    }

    /// The server closed the connection.
    private func ended() {
        switch body {
        case .untilClose: finish(nil)
        // Short of the length it gave, or before the last chunk: the reply was cut off.
        default: finish(URLError(.networkConnectionLost))
        }
    }

    private func consume(_ data: Data) {
        guard let body else {
            buffer.append(data)
            return readHead()
        }
        switch body {
        case .length(let left):
            let piece = data.prefix(Int(min(left, Int64(data.count))))
            let rest = left - Int64(piece.count)
            self.body = .length(rest)
            if !piece.isEmpty { onData(self, piece) }
            if rest == 0 && !finished { finish(nil) }
        case .untilClose:
            onData(self, data)
        case .chunked, .trailers:
            buffer.append(data)
            readChunks()
        }
    }

    private func readHead() {
        guard let end = buffer.firstRange(of: Data("\r\n\r\n".utf8)) else {
            if buffer.count > Self.maxHead { finish(Failure.badResponse) }
            return
        }
        let head = buffer[..<end.lowerBound]
        let rest = Data(buffer[end.upperBound...])
        buffer = Data()
        guard let (status, fields) = Self.parseHead(head), let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: fields)
        else { return finish(Failure.badResponse) }
        // An interim reply; the real one follows.
        if (100..<200).contains(status) { return consume(rest) }
        if redirect(response) { return }
        guard onResponse(self, response), !finished else { return finish(URLError(.cancelled)) }

        if status == 204 || status == 304 { return finish(nil) }
        if response.value(forHTTPHeaderField: "Transfer-Encoding")?.lowercased().contains("chunked") == true {
            body = .chunked(left: nil)
        } else if let length = response.value(forHTTPHeaderField: "Content-Length").flatMap({
            Int64($0.trimmingCharacters(in: .whitespaces))
        }), length >= 0 {
            if length == 0 { return finish(nil) }
            body = .length(length)
        } else {
            body = .untilClose
        }
        if !rest.isEmpty { consume(rest) }
    }

    /// Hands on whole chunks' data as it arrives, leaving any partial framing in `buffer`.
    private func readChunks() {
        let crlf = Data("\r\n".utf8)
        while !finished {
            switch body {
            case .chunked(left: nil):
                guard let line = buffer.firstRange(of: crlf) else {
                    if buffer.count > 1024 { finish(Failure.badResponse) }
                    return
                }
                // The size is hex, optionally followed by ";extensions".
                let text = String(decoding: buffer[..<line.lowerBound], as: UTF8.self)
                buffer.removeSubrange(..<line.upperBound)
                guard let size = Int64(text.split(separator: ";").first?.trimmingCharacters(in: .whitespaces) ?? "", radix: 16),
                    size >= 0
                else { return finish(Failure.badResponse) }
                body = size == 0 ? .trailers : .chunked(left: size)
            case .chunked(left: let left?):
                if left > 0 {
                    guard !buffer.isEmpty else { return }
                    let piece = buffer.prefix(Int(min(left, Int64(buffer.count))))
                    buffer.removeFirst(piece.count)
                    body = .chunked(left: left - Int64(piece.count))
                    onData(self, Data(piece))
                } else {
                    guard buffer.count >= 2 else { return }
                    guard buffer.prefix(2) == crlf else { return finish(Failure.badResponse) }
                    buffer.removeFirst(2)
                    body = .chunked(left: nil)
                }
            case .trailers:
                guard let line = buffer.firstRange(of: crlf) else { return }
                let empty = line.lowerBound == buffer.startIndex
                buffer.removeSubrange(..<line.upperBound)
                if empty { return finish(nil) }
            default:
                return
            }
        }
    }

    /// The status and header fields of a reply's head. Repeated fields are joined with commas.
    static func parseHead(_ head: Data) -> (status: Int, fields: [String: String])? {
        let lines = String(decoding: head, as: UTF8.self).components(separatedBy: "\r\n")
        let status = lines.first?.split(separator: " ", maxSplits: 2)
        guard let status, status.count >= 2, status[0].hasPrefix("HTTP/1."), let code = Int(status[1]) else { return nil }
        var fields: [String: String] = [:]
        var names: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            // Header names aren't case-sensitive; keep the first spelling.
            let key = names[name.lowercased(), default: name]
            names[name.lowercased()] = key
            fields[key] = fields[key].map { "\($0), \(value)" } ?? value
        }
        return (code, fields)
    }

    /// Whether the connection's local address belongs to interface `name`.
    static func isLocal(_ endpoint: NWEndpoint?, on name: String) -> Bool {
        guard case .hostPort(let host, _)? = endpoint else { return false }
        let address: Data
        switch host {
        case .ipv4(let a): address = a.rawValue
        case .ipv6(let a): address = a.rawValue
        default: return false
        }
        return addresses(of: name).contains(address)
    }

    /// The IPv4 and IPv6 addresses interface `name` has, as raw bytes.
    static func addresses(of name: String) -> Set<Data> {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var result = Set<Data>()
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard String(cString: entry.pointee.ifa_name) == name, let addr = entry.pointee.ifa_addr else { continue }
            switch Int32(addr.pointee.sa_family) {
            case AF_INET:
                addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    var a = $0.pointee.sin_addr
                    result.insert(Data(bytes: &a, count: MemoryLayout<in_addr>.size))
                }
            case AF_INET6:
                addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                    var a = $0.pointee.sin6_addr
                    result.insert(Data(bytes: &a, count: MemoryLayout<in6_addr>.size))
                }
            default:
                break
            }
        }
        return result
    }

    /// Network errors as the URLError a URLSession task would fail with, so retries treat them alike.
    private static func urlError(_ error: NWError) -> URLError {
        switch error {
        case .posix(.ETIMEDOUT): URLError(.timedOut)
        case .posix(.ECONNREFUSED), .posix(.EHOSTUNREACH), .posix(.ENETUNREACH), .posix(.ENETDOWN): URLError(.cannotConnectToHost)
        case .dns: URLError(.cannotFindHost)
        case .tls: URLError(.secureConnectionFailed)
        default: URLError(.networkConnectionLost)
        }
    }
}
