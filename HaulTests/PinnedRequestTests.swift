import Foundation
import Network
import Synchronization
import Testing
@testable import Haul

/// An HTTP server on 127.0.0.1 for connections that don't go through URLSession. Each connection's
/// request head goes to `respond`, which answers with raw bytes.
nonisolated final class LocalHTTPServer: @unchecked Sendable {
    /// What to send back: pieces sent one after another, `pause` seconds apart, then whether to close.
    struct Reply {
        var pieces: [Data]
        var pause: Double = 0
        var close = true
        /// Seconds before anything is sent.
        var wait: Double = 0
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "test.server")
    private(set) var port: UInt16 = 0
    let lock = NSLock()
    /// Every request head received, in order, and when.
    private(set) var requests: [(head: String, at: Date)] = []
    var heads: [String] { requests.map(\.head) }

    init(respond: @escaping @Sendable (String) -> Reply) async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        let queue = queue
        let ready = AsyncStream<UInt16?>.makeStream()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.continuation.yield(listener.port?.rawValue)
            case .failed: ready.continuation.yield(nil)
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: queue)
            self?.readHead(connection, Data(), respond)
        }
        listener.start(queue: queue)
        var port: UInt16?
        for await value in ready.stream { port = value; break }
        guard let port else { throw URLError(.cannotConnectToHost) }
        self.port = port
    }

    deinit { listener.cancel() }

    var base: URL { URL(string: "http://127.0.0.1:\(port)")! }

    private func readHead(_ connection: NWConnection, _ buffer: Data, _ respond: @escaping @Sendable (String) -> Reply) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.firstRange(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                lock.withLock { self.requests.append((head, Date())) }
                let reply = respond(head)
                queue.asyncAfter(deadline: .now() + reply.wait) { self.send(reply, on: connection) }
            } else if !complete && error == nil {
                readHead(connection, buffer, respond)
            } else {
                connection.cancel()
            }
        }
    }

    private func send(_ reply: Reply, on connection: NWConnection) {
        guard let first = reply.pieces.first else {
            if reply.close { connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in connection.cancel() }) }
            return
        }
        var rest = reply
        rest.pieces.removeFirst()
        connection.send(content: first, completion: .contentProcessed { [weak self] error in
            guard error == nil else { return connection.cancel() }
            self?.queue.asyncAfter(deadline: .now() + reply.pause) { self?.send(rest, on: connection) }
        })
    }

    /// A reply head followed by `body`, as one piece each.
    static func reply(_ status: String, _ headers: [String: String], _ body: Data = Data(), pause: Double = 0) -> Reply {
        let head = "HTTP/1.1 \(status)\r\n" + headers.map { "\($0.key): \($0.value)\r\n" }.joined() + "\r\n"
        return Reply(pieces: [Data(head.utf8)] + (body.isEmpty ? [] : [body]), pause: pause)
    }

    /// Serves the RangeServer test file of `size` bytes to ranged GETs, in pieces of 64 KB, with
    /// `headers` (validators) chosen for each request head.
    /// A status of "drop" closes the connection without a reply.
    /// `corrupt` requests get different bytes, as from a server with another build of the file.
    static func file(size: Int64, wait: @escaping @Sendable (String) -> Double = { _ in 0 },
                     corrupt: @escaping @Sendable (String) -> Bool = { _ in false }, pause: Double = 0,
                     headers: @escaping @Sendable (String) -> (status: String, fields: [String: String])? = { _ in nil })
        async throws -> LocalHTTPServer {
        try await LocalHTTPServer { head in
            let answer = headers(head)
            if answer?.status == "drop" { return Reply(pieces: []) }
            if let (status, fields) = answer, !status.hasPrefix("2") {
                return reply(status, fields.merging(["Content-Length": "0"]) { a, _ in a })
            }
            let range = head.split(separator: "\r\n").first { $0.lowercased().hasPrefix("range:") }
                .flatMap { $0.split(separator: "=").last }?.split(separator: "-", omittingEmptySubsequences: false)
            let start = range.flatMap { Int64($0[0]) } ?? 0
            let end = range.flatMap { $0.count > 1 ? Int64($0[1]) : nil } ?? size - 1
            var fields = ["Content-Length": "\(end - start + 1)", "Content-Range": "bytes \(start)-\(end)/\(size)"]
            fields.merge(answer?.fields ?? [:]) { _, b in b }
            var body = RangeServer.content(start...end)
            if corrupt(head) { body = Data(body.map { $0 ^ 0x5A }) }
            let pieces = stride(from: 0, to: body.count, by: 65536).map { body.subdata(in: $0..<min($0 + 65536, body.count)) }
            let head = "HTTP/1.1 206 Partial Content\r\n" + fields.map { "\($0.key): \($0.value)\r\n" }.joined() + "\r\n"
            return Reply(pieces: [Data(head.utf8)] + pieces, pause: pause, wait: wait(head))
        }
    }
}

/// The loopback interface, for pinning test connections to it.
nonisolated func loopback() async -> NWInterface {
    let monitor = NWPathMonitor(requiredInterfaceType: .loopback)
    let found = AsyncStream<NWInterface>.makeStream()
    monitor.pathUpdateHandler = { path in
        if let lo = path.availableInterfaces.first(where: { $0.type == .loopback }) { found.continuation.yield(lo) }
    }
    monitor.start(queue: DispatchQueue(label: "test.loopback"))
    defer { monitor.cancel() }
    for await interface in found.stream { return interface }
    fatalError("no loopback interface")
}

struct PinnedRequestTests {
    struct Outcome {
        var response: HTTPURLResponse?
        var body = Data()
        var error: Error?
        var completions = 0
    }

    /// Runs one request pinned to loopback; `accept` decides on the reply, and `cancelAfter` cancels
    /// once that many bytes have arrived.
    private func run(_ request: URLRequest, accept: Bool = true, cancelAfter: Int? = nil, idleLimit: TimeInterval = 60,
                     cookies: @escaping @Sendable (URL) -> [String: String] = { _ in [:] }) async -> Outcome {
        let interface = await loopback()
        let queue = DispatchQueue(label: "test.pinned")
        let state = Mutex(Outcome())
        return await withCheckedContinuation { continuation in
            queue.async {
                var pinned: PinnedRequest?
                pinned = PinnedRequest(request, over: interface, queue: queue, cookies: cookies, idleLimit: idleLimit, onResponse: { _, response in
                    state.withLock { $0.response = response }
                    return accept
                }, onData: { _, data in
                    let count = state.withLock { $0.body.append(data); return $0.body.count }
                    if let cancelAfter, count >= cancelAfter { pinned?.cancel() }
                }, onComplete: { _, error in
                    let first = state.withLock { $0.error = error; $0.completions += 1; return $0.completions == 1 }
                    // A second completion would show up in the count; give it a moment to arrive.
                    if first { queue.asyncAfter(deadline: .now() + 0.2) { continuation.resume(returning: state.withLock { $0 }); pinned = nil } }
                })
                pinned?.start()
            }
        }
    }

    private func code(_ error: Error?) -> URLError.Code? { (error as? URLError)?.code }

    @Test func readsABodyOfKnownLength() async throws {
        let server = try await LocalHTTPServer { _ in
            LocalHTTPServer.reply("206 Partial Content", ["Content-Length": "10", "Content-Range": "bytes 10-19/100"], Data("0123456789".utf8))
        }
        var request = URLRequest(url: server.base.appending(path: "file.bin"))
        request.setValue("bytes=10-19", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let outcome = await run(request)
        #expect(outcome.response?.statusCode == 206)
        #expect(outcome.response?.value(forHTTPHeaderField: "content-range") == "bytes 10-19/100")
        #expect(outcome.body == Data("0123456789".utf8))
        #expect(outcome.error == nil)
        #expect(outcome.completions == 1)

        let head = try #require(server.lock.withLock { server.heads.first })
        #expect(head.hasPrefix("GET /file.bin HTTP/1.1\r\n"))
        #expect(head.contains("Host: 127.0.0.1:\(server.port)\r\n"))
        #expect(head.contains("Range: bytes=10-19\r\n"))
        #expect(head.contains("Accept-Encoding: identity\r\n"))
        #expect(head.contains("Connection: close\r\n"))
    }

    @Test func readsChunkedBodiesSplitAnywhere() async throws {
        let server = try await LocalHTTPServer { _ in
            LocalHTTPServer.Reply(pieces: ["HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n", "\r\n4\r\nWi", "ki\r", "\n5;x=y\r\npedia\r\n0\r\n",
                                           "Trailer: z\r\n\r\n"].map { Data($0.utf8) }, pause: 0.02, close: false)
        }
        let outcome = await run(URLRequest(url: server.base))
        #expect(String(decoding: outcome.body, as: UTF8.self) == "Wikipedia")
        #expect(outcome.error == nil)
    }

    @Test func headSplitAcrossReadsAndInterimRepliesAreSkipped() async throws {
        let server = try await LocalHTTPServer { _ in
            LocalHTTPServer.Reply(pieces: ["HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nContent-", "Length: 3\r\n\r", "\nabc"].map { Data($0.utf8) },
                                  pause: 0.02, close: false)
        }
        let outcome = await run(URLRequest(url: server.base))
        #expect(outcome.response?.statusCode == 200)
        #expect(outcome.body == Data("abc".utf8))
        #expect(outcome.error == nil)
    }

    @Test func closingShortOfTheLengthIsAnError() async throws {
        let server = try await LocalHTTPServer { _ in
            LocalHTTPServer.reply("200 OK", ["Content-Length": "100"], Data(repeating: 1, count: 50))
        }
        let outcome = await run(URLRequest(url: server.base))
        #expect(outcome.body.count == 50)
        #expect(code(outcome.error) == .networkConnectionLost)
    }

    @Test func closingEndsABodyOfUnknownLength() async throws {
        let server = try await LocalHTTPServer { _ in LocalHTTPServer.reply("200 OK", [:], Data(repeating: 2, count: 70_000)) }
        let outcome = await run(URLRequest(url: server.base))
        #expect(outcome.body.count == 70_000)
        #expect(outcome.error == nil)
    }

    @Test func closingBeforeTheLastChunkIsAnError() async throws {
        let server = try await LocalHTTPServer { _ in
            LocalHTTPServer.Reply(pieces: [Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n".utf8)])
        }
        let outcome = await run(URLRequest(url: server.base))
        #expect(outcome.body == Data("Wiki".utf8))
        #expect(code(outcome.error) == .networkConnectionLost)
    }

    @Test func aConnectionThatGoesQuietTimesOut() async throws {
        let server = try await LocalHTTPServer { _ in
            var reply = LocalHTTPServer.reply("200 OK", ["Content-Length": "100"], Data(repeating: 1, count: 10))
            reply.close = false
            return reply
        }
        let outcome = await run(URLRequest(url: server.base), idleLimit: 0.5)
        #expect(outcome.body.count == 10)
        #expect(code(outcome.error) == .timedOut)
    }

    @Test func refusedReplyIsCancelledWithoutItsBody() async throws {
        let server = try await LocalHTTPServer { _ in LocalHTTPServer.reply("200 OK", ["Content-Length": "3"], Data("abc".utf8)) }
        let outcome = await run(URLRequest(url: server.base), accept: false)
        #expect(outcome.response?.statusCode == 200)
        #expect(outcome.body.isEmpty)
        #expect(code(outcome.error) == .cancelled)
        #expect(outcome.completions == 1)
    }

    @Test func cancellingCompletesOnce() async throws {
        let body = Data(repeating: 3, count: 1_000_000)
        let server = try await LocalHTTPServer { _ in
            var reply = LocalHTTPServer.reply("200 OK", ["Content-Length": "\(body.count)"])
            reply.pieces += stride(from: 0, to: body.count, by: 65536).map { body.subdata(in: $0..<min($0 + 65536, body.count)) }
            reply.pause = 0.01
            return reply
        }
        let outcome = await run(URLRequest(url: server.base), cancelAfter: 100_000)
        #expect(outcome.body.count < body.count)
        #expect(code(outcome.error) == .cancelled)
        #expect(outcome.completions == 1)
    }

    @Test func unreachableServerFailsBeforeAReply() async throws {
        // A port nothing listens on: the server above takes one, then closes it.
        let port = try await LocalHTTPServer { _ in LocalHTTPServer.Reply(pieces: []) }.port
        let outcome = await run(URLRequest(url: URL(string: "http://127.0.0.1:\(port)/")!))
        #expect(outcome.response == nil)
        #expect(outcome.error != nil)
        #expect(outcome.completions == 1)
    }

    @Test func redirectsAreFollowedWithEachHostsOwnCookies() async throws {
        let server = try await LocalHTTPServer { head in
            if head.hasPrefix("GET /old ") {
                return LocalHTTPServer.reply("302 Found", ["Location": "/moved", "Content-Length": "0"])
            }
            if head.hasPrefix("GET /moved ") {
                // localhost is the same server, but another host as far as cookies go.
                let port = head.split(separator: "\r\n").first { $0.hasPrefix("Host: ") }?.split(separator: ":").last ?? ""
                return LocalHTTPServer.reply("307 Temporary Redirect", ["Location": "http://localhost:\(port)/file", "Content-Length": "0"])
            }
            return LocalHTTPServer.reply("200 OK", ["Content-Length": "4"], Data("done".utf8))
        }
        var request = URLRequest(url: server.base.appending(path: "old"))
        request.setValue("session=1", forHTTPHeaderField: "Cookie")
        let outcome = await run(request) { url in url.host() == "localhost" ? ["Cookie": "cdn=2"] : [:] }
        #expect(outcome.response?.statusCode == 200)
        #expect(outcome.response?.url?.host() == "localhost")
        #expect(outcome.body == Data("done".utf8))
        let heads = server.lock.withLock { server.heads }
        #expect(heads.count == 3)
        #expect(heads.prefix(2).allSatisfy { $0.contains("Cookie: session=1") })
        #expect(!(heads.last ?? "").contains("session=1"))
        #expect((heads.last ?? "").contains("Cookie: cdn=2"))
    }

    @Test func endlessRedirectsStopAtTheLimit() async throws {
        let server = try await LocalHTTPServer { _ in LocalHTTPServer.reply("302 Found", ["Location": "/again", "Content-Length": "0"]) }
        let outcome = await run(URLRequest(url: server.base))
        #expect(outcome.response?.statusCode == 302)
        #expect(server.lock.withLock { server.heads.count } == PinnedRequest.maxRedirects + 1)
    }

    @Test func headFieldsAreJoinedAndCaseInsensitive() throws {
        let head = Data("HTTP/1.1 206 Partial Content\r\nETag: \"a\"\r\nVary: Accept\r\nvary: Range\r\nX: a: b".utf8)
        let (status, fields) = try #require(PinnedRequest.parseHead(head))
        #expect(status == 206)
        #expect(fields["ETag"] == "\"a\"")
        #expect(fields["Vary"] == "Accept, Range")
        #expect(fields["X"] == "a: b")
        #expect(PinnedRequest.parseHead(Data("SSH-2.0-OpenSSH\r\n".utf8)) == nil)
    }

    @Test func localAddressMustBelongToTheInterface() {
        let local = NWEndpoint.hostPort(host: .ipv4(.loopback), port: 1234)
        #expect(PinnedRequest.isLocal(local, on: "lo0"))
        #expect(!PinnedRequest.isLocal(NWEndpoint.hostPort(host: .ipv4(IPv4Address("10.2.0.2")!), port: 1234), on: "lo0"))
        #expect(!PinnedRequest.isLocal(nil, on: "lo0"))
    }
}
