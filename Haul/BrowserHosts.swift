import Foundation

/// Registers the `haul` tool inside the app as the native messaging host of the Chrome and
/// Firefox extension (BrowserExtension/ in the repository), so the extension can hand it links
/// without the browser asking first. Each browser looks for a manifest named after the host in
/// its own folder; Haul writes one for every installed browser each time it launches, so they
/// follow the app when it's moved or updated. The sandbox allows these folders through
/// Haul.entitlements.
nonisolated enum BrowserHosts {
    /// The host's name; background.js sends to it.
    static let name = "dev.sibiraj.haul"
    /// The extension's origin in Chromium browsers. Its ID comes from the `key` in its manifest,
    /// which the Chrome Web Store's copy and copies loaded unpacked share; the "Chrome Extension
    /// ID" build phase works it out into ChromeExtensionID.txt.
    static let chromeExtension: String? = Bundle.main.url(forResource: "ChromeExtensionID", withExtension: "txt")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .flatMap { $0.count == 32 ? "chrome-extension://\($0)/" : nil }
    static let firefoxExtension = "haul@sibiraj.dev"

    /// Where the extension is installed from: Chromium browsers all take the Chrome Web Store's.
    static let chromeWebStore = URL(string: "https://chromewebstore.google.com/detail/dhpcpomodjoajhnpnbnobdngljjilfge")!
    static let firefoxAddons = URL(string: "https://addons.mozilla.org/firefox/addon/haul-downloader/")!

    struct Browser: Equatable {
        let name: String
        /// The app's bundle identifier, to find whether it's installed.
        let bundleIdentifier: String
        /// The browser's own folder, relative to ~/Library/Application Support.
        let folder: String
        let isFirefox: Bool

        var hostsFolder: String { folder + "/NativeMessagingHosts" }
        var store: URL { isFirefox ? firefoxAddons : chromeWebStore }
    }

    static let browsers = [
        Browser(name: "Google Chrome", bundleIdentifier: "com.google.Chrome", folder: "Google/Chrome", isFirefox: false),
        Browser(name: "Chromium", bundleIdentifier: "org.chromium.Chromium", folder: "Chromium", isFirefox: false),
        Browser(name: "Brave", bundleIdentifier: "com.brave.Browser", folder: "BraveSoftware/Brave-Browser", isFirefox: false),
        Browser(name: "Microsoft Edge", bundleIdentifier: "com.microsoft.edgemac", folder: "Microsoft Edge", isFirefox: false),
        Browser(name: "Vivaldi", bundleIdentifier: "com.vivaldi.Vivaldi", folder: "Vivaldi", isFirefox: false),
        Browser(name: "Arc", bundleIdentifier: "company.thebrowser.Browser", folder: "Arc/User Data", isFirefox: false),
        Browser(name: "Firefox", bundleIdentifier: "org.mozilla.firefox", folder: "Mozilla", isFirefox: true),
    ]

    /// Nil for a Chromium browser when the build has no extension ID.
    static func manifest(for browser: Browser, tool: URL) -> Data? {
        var manifest: [String: Any] = ["name": name, "description": "Haul", "path": tool.path, "type": "stdio"]
        if browser.isFirefox {
            manifest["allowed_extensions"] = [firefoxExtension]
        } else {
            guard let chromeExtension else { return nil }
            manifest["allowed_origins"] = [chromeExtension]
        }
        return try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Writes the manifests for the browsers that are installed (whose folder exists), pointing
    /// at this copy of Haul. Skipped when Haul runs from somewhere it won't stay.
    static func install(app: URL = Bundle.main.bundleURL) {
        guard !CommandLineInstall.isTemporary(app) else { return }
        let support = CommandLineInstall.home.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let tool = CommandLineInstall.tool(in: app)
        for browser in browsers {
            guard let data = manifest(for: browser, tool: tool) else { continue }
            let folder = support.appending(path: browser.hostsFolder, directoryHint: .isDirectory)
            // Not creating intermediate folders: a browser that isn't installed has none.
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            let file = folder.appending(path: name + ".json")
            guard (try? Data(contentsOf: file)) != data else { continue }
            try? data.write(to: file, options: .atomic)
        }
    }
}
