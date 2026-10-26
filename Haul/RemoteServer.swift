import CryptoKit
import Foundation
import Network

/// Adding downloads from other devices, or from anywhere through a tunnel the user runs: a
/// small HTTP server, on only while it's turned on in Settings. `GET /` is a page to paste
/// links into, and `POST /add` takes links from it, curl or a script; `/downloads` lists the
/// downloads and pauses, resumes or removes one (see `RemoteAPI.route`). Everything but the
/// page needs the password. Added downloads start without the Add panel, since nobody may be
/// at the Mac.
@Observable
final class RemoteServer {
    static let shared = RemoteServer()
    static let defaultPort = 7878

    enum State: Equatable {
        case off, starting, running
        case failed(String)
    }

    private(set) var state = State.off
    /// Where the page is on this Mac, and on the network when it's open to it; for showing in
    /// Settings, and set while the server runs (`refreshAddress`).
    private(set) var pageURL: URL?
    private(set) var networkURL: URL?

    @ObservationIgnored private var listener: NWListener?
    /// For "This Mac": the IPv6 loopback, so localhost works whichever address it resolves to.
    /// It doesn't decide the state; IPv6 may be turned off.
    @ObservationIgnored private var listenerIPv6: NWListener?
    @ObservationIgnored private var throttle = RemoteAPI.Throttle()

    /// Starts, stops or restarts the server to match the settings.
    func update() {
        listener?.cancel()
        listener = nil
        listenerIPv6?.cancel()
        listenerIPv6 = nil
        let settings = AppSettings.shared
        pageURL = nil
        networkURL = nil
        guard settings.remoteOn else { return state = .off }
        guard (1...65535).contains(settings.remotePort), let port = NWEndpoint.Port(rawValue: UInt16(settings.remotePort)) else {
            return state = .failed("Choose a port from 1 to 65535.")
        }
        // "Network" listens on every interface, loopback included; "This Mac" only on loopback.
        let listener: NWListener
        do {
            listener = settings.remoteScope == .thisMac
                ? try NWListener(using: Self.parameters(.ipv4(.loopback), port))
                : try NWListener(using: Self.parameters(nil, port), on: port)
        } catch {
            return state = .failed(error.localizedDescription)
        }
        if settings.remoteScope == .thisMac, let ipv6 = try? NWListener(using: Self.parameters(.ipv6(.loopback), port)) {
            ipv6.stateUpdateHandler = { [weak ipv6] new in
                if case .failed(let error) = new {
                    NSLog("Haul: the remote downloads server isn't on the IPv6 loopback: \(error)")
                    ipv6?.cancel()
                }
            }
            ipv6.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.serve(connection) }
            }
            listenerIPv6 = ipv6
            ipv6.start(queue: .main)
        }
        state = .starting
        listener.stateUpdateHandler = { [weak self, weak listener] new in
            MainActor.assumeIsolated {
                guard let self, let listener, self.listener === listener else { return }
                switch new {
                case .ready:
                    self.state = .running
                    self.refreshAddress()
                case .waiting(let error):
                    // E.g. no network yet at login; the listener becomes ready by itself once there is.
                    NSLog("Haul: the remote downloads server is waiting: \(error)")
                    self.state = .failed(Self.describe(error))
                    self.refreshAddress()
                case .failed(let error):
                    NSLog("Haul: the remote downloads server couldn't start: \(error)")
                    self.state = .failed(Self.describe(error))
                    self.refreshAddress()
                    listener.cancel()
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.serve(connection) }
        }
        self.listener = listener
        listener.start(queue: .main)
    }

    /// TCP, bound to `host` when given.
    private static func parameters(_ host: NWEndpoint.Host?, _ port: NWEndpoint.Port) -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        if let host { parameters.requiredLocalEndpoint = .hostPort(host: host, port: port) }
        return parameters
    }

    private static func describe(_ error: NWError) -> String {
        if case .posix(.EADDRINUSE) = error { return "Another app is using this port." }
        return error.localizedDescription
    }

    // MARK: - Connections

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        // A client that never finishes its request doesn't keep the connection open.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { connection.cancel() }
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 << 10) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return connection.cancel() }
                var buffer = buffer
                if let data { buffer.append(data) }
                switch HTTPRequest.parse(buffer) {
                case .incomplete where !isComplete && error == nil: self.receive(connection, buffer: buffer)
                case .incomplete, .invalid: self.send(.json(400, error: "The request couldn't be read."), on: connection)
                case .tooLarge: self.send(.json(413, error: "The request is too large."), on: connection)
                case .complete(let request): self.respond(to: request, on: connection)
                }
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        switch RemoteAPI.route(request.method, request.path) {
        case .page: send(.page(), on: connection)
        case .notFound: send(.json(404, error: "Not found."), on: connection)
        case .methodNotAllowed: send(.json(405, error: "Method not allowed."), on: connection)
        case let action:
            authorize(request, on: connection) { self.perform(action, request, on: connection) }
        }
    }

    private func perform(_ route: RemoteAPI.Route, _ request: HTTPRequest, on connection: NWConnection) {
        let store = DownloadStore.shared
        let ok = HTTPResponse.json(200, ["ok": true])
        switch route {
        case .auth: send(ok, on: connection)
        case .add: add(request, on: connection)
        case .list: send(.json(200, ["ok": true, "downloads": store.items.map(RemoteAPI.summary)]), on: connection)
        case .pause(let id), .resume(let id), .remove(let id):
            guard let d = store.items.first(where: { $0.id == id }) else {
                return send(.json(404, error: "There's no such download."), on: connection)
            }
            switch route {
            case .pause where [.downloading, .queued].contains(d.status):
                store.pause(id)
            case .resume where d.issue == .signIn:
                return send(.json(409, error: "This download needs a sign-in on the Mac."), on: connection)
            case .resume where [.paused, .failed].contains(d.status):
                store.toggle(id)
            case .remove:
                // Only from the list; a finished file stays where it was saved.
                store.remove(id)
            default:
                return send(.json(409, error: "The download is \(d.status.label.lowercased())."), on: connection)
            }
            send(ok, on: connection)
        case .page, .notFound, .methodNotAllowed: break
        }
    }

    /// Runs `then` when the request has the password, and answers it otherwise.
    private func authorize(_ request: HTTPRequest, on connection: NWConnection, then: () -> Void) {
        // Another site in the user's browser can't add or guess, nor run up the lockout.
        if RemoteAPI.isCrossSite(request) {
            return send(.json(403, error: "Requests from other sites aren't allowed."), on: connection)
        }
        if throttle.isLocked(at: .now) {
            return send(.json(429, error: "Too many wrong passwords. Try again later."), on: connection)
        }
        guard RemoteAPI.authorized(request, password: AppSettings.shared.remotePassword) else {
            // Without a password at all it isn't a guess. That's also all a web page can send
            // without the browser asking first, which the server never allows.
            guard request.headers["authorization"] != nil else {
                return send(.json(401, error: "The password is missing.", headers: [("WWW-Authenticate", "Bearer")]), on: connection)
            }
            throttle.fail(at: .now)
            // Slows down guessing; the lockout stops it.
            return DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.send(.json(401, error: "Wrong password.", headers: [("WWW-Authenticate", "Bearer")]), on: connection)
            }
        }
        then()
    }

    private func add(_ request: HTTPRequest, on connection: NWConnection) {
        let links: [URL]
        switch RemoteAPI.links(in: request) {
        case .success(let found): links = found
        case .failure(let error): return send(.json(400, error: error.message), on: connection)
        }
        let store = DownloadStore.shared
        let new = links.filter { store.existing(url: $0) == nil }
        // Queued, like a batch from the Add panel, so the simultaneous-download limit applies.
        for url in new {
            store.add(url: url, probe: nil, connections: AppSettings.shared.connections, start: .queued, reveal: false)
        }
        send(.json(200, ["ok": true, "added": new.count, "skipped": links.count - new.count]), on: connection)
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.data, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - Addresses

    /// Looks up the addresses again, e.g. after the Mac joined another network.
    func refreshAddress() {
        let settings = AppSettings.shared
        guard state == .running else {
            pageURL = nil
            networkURL = nil
            return
        }
        pageURL = URL(string: "http://localhost:\(settings.remotePort)/")
        networkURL = settings.remoteScope == .network
            ? Self.networkAddresses().first.flatMap { URL(string: "http://\($0):\(settings.remotePort)/") } : nil
    }

    /// This Mac's IPv4 addresses on its network interfaces (Wi-Fi, Ethernet), not loopback.
    nonisolated static func networkAddresses() -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var addresses: [String] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, String(cString: entry.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses.append(String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
            }
        }
        return addresses
    }
}

/// What a remote request may do, apart from the server: checking the password, reading the
/// links, and limiting wrong guesses.
nonisolated enum RemoteAPI {
    static let maxLinks = 100

    enum Route: Equatable {
        case page, auth, add, list
        case pause(UUID), resume(UUID), remove(UUID)
        case notFound, methodNotAllowed
    }

    /// What a request asks for. Everything but the page needs the password.
    static func route(_ method: String, _ path: String) -> Route {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        func only(_ allowed: String, _ route: Route) -> Route { method == allowed ? route : .methodNotAllowed }
        switch parts.count {
        case 0: return only("GET", .page)
        case 1:
            switch parts[0] {
            case "index.html": return only("GET", .page)
            case "auth": return only("POST", .auth)
            case "add": return only("POST", .add)
            case "downloads": return only("GET", .list)
            default: return .notFound
            }
        case 2, 3:
            guard parts[0] == "downloads", let id = UUID(uuidString: parts[1]) else { return .notFound }
            if parts.count == 2 { return only("DELETE", .remove(id)) }
            switch parts[2] {
            case "pause": return only("POST", .pause(id))
            case "resume": return only("POST", .resume(id))
            default: return .notFound
            }
        default: return .notFound
        }
    }

    /// A download as `GET /downloads` lists it.
    @MainActor static func summary(_ d: Download) -> [String: Any] {
        var summary: [String: Any] = [
            "id": d.id.uuidString, "name": d.name, "url": d.url.absoluteString, "host": d.host,
            "status": d.status.rawValue, "received": d.status == .completed ? d.size ?? d.received : d.received,
            "progress": d.progress, "speed": d.status == .downloading ? Int(d.speed) : 0,
            "added": d.added.timeIntervalSince1970,
        ]
        if let size = d.size { summary["size"] = size }
        if let error = d.error, d.status == .failed { summary["error"] = error }
        return summary
    }

    struct Failure: Error, Equatable { let message: String }

    /// Whether a browser says the request comes from a page on another site. The page's own
    /// requests are same-origin, also through a tunnel; curl and scripts don't send the header.
    static func isCrossSite(_ request: HTTPRequest) -> Bool {
        guard let site = request.headers["sec-fetch-site"]?.lowercased() else { return false }
        return site != "same-origin" && site != "none"
    }

    /// A random password for when remote downloads are first turned on.
    static func newPassword() -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return String((0..<16).map { _ in alphabet.randomElement()! })
    }

    /// The password as Basic auth (any user name, so `curl -u :password` works) or as a bearer token.
    static func authorized(_ request: HTTPRequest, password: String) -> Bool {
        guard !password.isEmpty, let header = request.headers["authorization"] else { return false }
        let parts = header.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        let given: String
        switch parts[0].lowercased() {
        case "bearer": given = parts[1]
        case "basic":
            guard let data = Data(base64Encoded: parts[1]), let credentials = String(data: data, encoding: .utf8),
                  let colon = credentials.firstIndex(of: ":") else { return false }
            given = String(credentials[credentials.index(after: colon)...])
        default: return false
        }
        // Compared as hashes, so the time taken says nothing about how much of the guess was right.
        return SHA256.hash(data: Data(given.utf8)) == SHA256.hash(data: Data(password.utf8))
    }

    /// The links in the body: JSON `{"urls": […]}` (or just the array), or any text with links in it.
    static func links(in request: HTTPRequest) -> Result<[URL], Failure> {
        let found: [URL]
        if request.headers["content-type"]?.lowercased().contains("json") == true {
            let json = try? JSONSerialization.jsonObject(with: request.body)
            guard let strings = (json as? [String: Any])?["urls"] as? [String] ?? json as? [String] else {
                return .failure(Failure(message: #"Send JSON like {"urls": ["https://…"]}."#))
            }
            var seen = Set<URL>()
            found = strings.compactMap(AddDownloadPanel.link).filter { seen.insert($0).inserted }
        } else {
            found = AddDownloadPanel.links(in: String(decoding: request.body, as: UTF8.self))
        }
        if found.isEmpty { return .failure(Failure(message: "There's no http(s) link to download.")) }
        if found.count > maxLinks { return .failure(Failure(message: "Send at most \(maxLinks) links at a time.")) }
        return .success(found)
    }

    /// Locks adding for a while after too many wrong passwords. It counts every client together,
    /// since through a tunnel they all seem to come from the same address. A right password
    /// doesn't clear the count: the page asks every few seconds, which would undo it.
    struct Throttle {
        static let limit = 10
        static let window: TimeInterval = 10 * 60
        static let lockout: TimeInterval = 15 * 60

        private var failures: [Date] = []
        private var lockedUntil: Date?

        func isLocked(at now: Date) -> Bool { lockedUntil.map { now < $0 } ?? false }

        mutating func fail(at now: Date) {
            failures = failures.filter { now.timeIntervalSince($0) < Self.window } + [now]
            if failures.count >= Self.limit {
                lockedUntil = now.addingTimeInterval(Self.lockout)
                failures = []
            }
        }
    }
}

/// An HTTP/1.1 request, as much of one as the remote server reads.
nonisolated struct HTTPRequest: Equatable {
    var method: String
    /// Without the query.
    var path: String
    /// Lowercased names.
    var headers: [String: String]
    var body: Data

    static let maxSize = 256 << 10

    enum Parsed: Equatable {
        case incomplete, invalid, tooLarge
        case complete(HTTPRequest)
    }

    static func parse(_ data: Data) -> Parsed {
        guard let end = data.firstRange(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxSize ? .tooLarge : .incomplete
        }
        let lines = String(decoding: data[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
        }
        if headers["transfer-encoding"] != nil { return .invalid }
        let length = headers["content-length"].map { Int($0) } ?? 0
        guard let length, length >= 0 else { return .invalid }
        guard length <= maxSize, end.upperBound + length <= maxSize else { return .tooLarge }
        let bodyEnd = end.upperBound + length
        guard data.count >= bodyEnd else { return .incomplete }
        let target = String(requestLine[1])
        return .complete(HTTPRequest(method: String(requestLine[0]), path: String(target.prefix { $0 != "?" }),
                                     headers: headers, body: Data(data[end.upperBound..<bodyEnd])))
    }
}

nonisolated struct HTTPResponse {
    var status: Int
    var headers: [(String, String)]
    var body: Data

    static func json(_ status: Int, _ object: [String: Any], headers: [(String, String)] = []) -> HTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return HTTPResponse(status: status, headers: [("Content-Type", "application/json")] + headers, body: body + Data("\n".utf8))
    }

    static func json(_ status: Int, error: String, headers: [(String, String)] = []) -> HTTPResponse {
        json(status, ["ok": false, "error": error], headers: headers)
    }

    /// The page in RemotePage.html. It only talks to the server it came from, so nothing else
    /// may run in it, frame it or be sent from it.
    static func page() -> HTTPResponse {
        guard let body = pageBody else { return json(500, error: "The page is missing from Haul.") }
        return HTTPResponse(status: 200, headers: [
            ("Content-Type", "text/html; charset=utf-8"),
            ("Content-Security-Policy", "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; connect-src 'self'; form-action 'none'; frame-ancestors 'none'; base-uri 'none'"),
            ("Referrer-Policy", "no-referrer"),
            ("X-Content-Type-Options", "nosniff"),
            ("Cache-Control", "no-store"),
        ], body: body)
    }

    private static let pageBody: Data? = {
        let body = Bundle.main.url(forResource: "RemotePage", withExtension: "html").flatMap { try? Data(contentsOf: $0) }
        if body == nil { NSLog("Haul: RemotePage.html is missing from the app") }
        return body
    }()

    private static let reasons = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
                                  405: "Method Not Allowed", 409: "Conflict", 413: "Content Too Large", 429: "Too Many Requests",
                                  500: "Internal Server Error"]

    var data: Data {
        let reason = Self.reasons[status] ?? ""
        let head = (["HTTP/1.1 \(status) \(reason)"] + (headers + [("Content-Length", "\(body.count)"), ("Connection", "close")]).map { "\($0): \($1)" })
            .joined(separator: "\r\n") + "\r\n\r\n"
        return Data(head.utf8) + body
    }
}
