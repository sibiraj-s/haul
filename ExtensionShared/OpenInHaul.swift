import AppKit

/// Opens links in Haul's Add panel from an extension that ships inside Haul, with a
/// haul://add link (see IncomingLinks in the app).
enum OpenInHaul {
    /// Opens the http(s) links among `links`; returns whether there were any.
    @discardableResult
    static func open(_ links: [URL]) async -> Bool {
        guard let url = addURL(for: links.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }) else {
            return false
        }
        // Haul.app/Contents/PlugIns/X.appex: open the copy of Haul this extension came in,
        // rather than whichever app LaunchServices picks for haul:// links.
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        do {
            try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            NSWorkspace.shared.open(url)
        }
        return true
    }

    /// haul://add?url=…&url=…, each link percent-encoded so its own `&` and `=` survive.
    static func addURL(for links: [URL]) -> URL? {
        guard !links.isEmpty else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#?")
        let query = links.compactMap { $0.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) }
            .map { "url=\($0)" }.joined(separator: "&")
        return URL(string: "haul://add?\(query)")
    }
}
