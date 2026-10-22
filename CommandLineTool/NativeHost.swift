import Foundation

/// `haul` as the native messaging host of the Chrome and Firefox extension (see BrowserHosts in
/// the app, which registers it): the browser starts it for each message, which it reads from
/// standard input, opens in Haul's Add panel, and answers with whether it did.
enum NativeHost {
    /// Chrome passes the extension's origin; Firefox passes the host manifest's path and the
    /// extension's ID.
    static func isBrowser(_ arguments: [String]) -> Bool {
        arguments.first?.hasPrefix("chrome-extension://") == true || (arguments.count == 2 && arguments[0].hasSuffix(".json"))
    }

    /// The message is `{ urls: [String], context: {…} }`, as the Safari extension sends.
    static func run(app: URL) async {
        guard let message = read() else { return reply(["ok": false, "error": "The message couldn't be read."]) }
        let links = (message["urls"] as? [String] ?? []).compactMap(URL.init(string:))
        let context = message["context"].flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            .map { String(decoding: $0, as: UTF8.self) }
        let opened = await OpenInHaul.open(links, context: context, in: app)
        reply(opened ? ["ok": true] : ["ok": false, "error": "There's no http(s) link to download."])
    }

    /// Each message is JSON after its length in bytes, a 32-bit integer in native byte order.
    private static func read() -> [String: Any]? {
        let input = FileHandle.standardInput
        guard let header = try? input.read(upToCount: 4), header.count == 4 else { return nil }
        let length = Int(header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        guard length <= 64 << 20, let body = try? input.read(upToCount: length), body.count == length else { return nil }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    private static func reply(_ object: [String: Any]) {
        guard let body = try? JSONSerialization.data(withJSONObject: object) else { return }
        var length = UInt32(body.count)
        FileHandle.standardOutput.write(Data(bytes: &length, count: 4) + body)
    }
}
