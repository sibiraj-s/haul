import AppKit
import SafariServices

/// Receives links from the extension's background script and opens them in Haul's Add panel,
/// along with what Safari would send with them (page, User-Agent, cookies).
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let message = (context.inputItems.first as? NSExtensionItem)?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        let links = (message?["urls"] as? [String] ?? []).compactMap(URL.init(string:))
        let browser = (message?["context"]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            .map { String(decoding: $0, as: UTF8.self) }
        Task {
            await OpenInHaul.open(links, context: browser)
            context.completeRequest(returningItems: nil)
        }
    }
}
