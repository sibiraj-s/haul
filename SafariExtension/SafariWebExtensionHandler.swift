import AppKit
import SafariServices

/// Receives links from the extension's background script and opens them in Haul's Add panel.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let message = (context.inputItems.first as? NSExtensionItem)?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        let links = (message?["urls"] as? [String] ?? []).compactMap(URL.init(string:))
        Task {
            await OpenInHaul.open(links)
            context.completeRequest(returningItems: nil)
        }
    }
}
