import AppKit

/// "Haul" in the Share menu: sends the shared links to Haul's Add panel and closes straight
/// away, since the panel is where they're checked and confirmed.
final class ShareViewController: NSViewController {
    override func loadView() {
        view = NSView(frame: .zero)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        Task {
            var links: [URL] = []
            for provider in providers {
                if let url = await Self.url(from: provider) { links.append(url) }
            }
            if await OpenInHaul.open(links) {
                extensionContext?.completeRequest(returningItems: nil)
            } else {
                extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
            }
        }
    }

    private static func url(from provider: NSItemProvider) async -> URL? {
        guard provider.canLoadObject(ofClass: NSURL.self) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSURL.self) { item, _ in continuation.resume(returning: item as? URL) }
        }
    }
}
