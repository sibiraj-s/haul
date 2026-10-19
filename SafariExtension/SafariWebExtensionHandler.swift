import AppKit
import SafariServices

/// Receives links from the extension's background script and opens them in Haul with a
/// haul://add link, which shows the Add panel with them filled in.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let message = (context.inputItems.first as? NSExtensionItem)?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        let links = (message?["urls"] as? [String] ?? []).compactMap(URL.init(string:)).filter {
            ["http", "https"].contains($0.scheme?.lowercased() ?? "")
        }
        guard let url = Self.addURL(for: links) else {
            context.completeRequest(returningItems: nil)
            return
        }
        // Haul.app/Contents/PlugIns/SafariExtension.appex: open the copy of Haul this extension
        // came in, rather than whichever app LaunchServices picks for haul:// links.
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil { NSWorkspace.shared.open(url) }
            context.completeRequest(returningItems: nil)
        }
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
