import AppKit

/// Opens links in Haul's Add panel from an extension or the command-line tool that ships
/// inside Haul, with a haul://add link (see IncomingLinks in the app).
enum OpenInHaul {
    /// Opens the http(s) links among `links` in the copy of Haul at `app`, rather than
    /// whichever app LaunchServices picks for haul:// links; returns whether there were any.
    /// Without `app`, the caller is an extension in Haul.app/Contents/PlugIns/X.appex.
    @discardableResult
    static func open(_ links: [URL], in app: URL? = nil) async -> Bool {
        guard let url = addURL(for: links.filter(isDownloadLink)) else { return false }
        let app = app ?? Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        do {
            try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            NSWorkspace.shared.open(url)
        }
        return true
    }

    static func isDownloadLink(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
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
