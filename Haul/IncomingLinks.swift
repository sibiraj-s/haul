import AppKit

/// Links handed to Haul by other apps: `haul://add?url=…` links (one `url` item per link,
/// percent-encoded) and the "Download with Haul" service. Both open the Add panel filled in
/// rather than downloading straight away, so a web page that opens a haul:// link can't
/// start a download by itself.
enum IncomingLinks {
    nonisolated static let scheme = "haul"

    /// The download links in a `haul://add` URL; empty when it isn't one.
    nonisolated static func links(in url: URL) -> [URL] {
        guard url.scheme?.lowercased() == scheme, url.host()?.lowercased() == "add",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [] }
        return items.filter { $0.name == "url" }.compactMap { $0.value.flatMap(AddDownloadPanel.link) }
    }

    /// The download links on a pasteboard: copied URLs, and links in selected text.
    static func links(on pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        let text = pasteboard.string(forType: .string) ?? ""
        var seen = Set<URL>()
        return (urls.compactMap { AddDownloadPanel.link($0.absoluteString) } + AddDownloadPanel.links(in: text))
            .filter { seen.insert($0).inserted }
    }
}

/// Answers the "Download with Haul" item in the Services menu (declared in Info.plist).
final class ServiceProvider: NSObject {
    static let shared = ServiceProvider()

    @objc func downloadLinks(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let links = IncomingLinks.links(on: pasteboard)
        guard !links.isEmpty else {
            error.pointee = "The selection doesn't contain an http(s) link."
            return
        }
        DownloadStore.shared.requestAdd(links)
    }
}
