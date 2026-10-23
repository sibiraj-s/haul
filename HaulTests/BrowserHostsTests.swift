import CryptoKit
import Foundation
import Testing
@testable import Haul

struct BrowserHostsTests {
    private let tool = URL(filePath: "/Applications/Haul.app/Contents/Helpers/haul")

    private func manifest(_ browser: BrowserHosts.Browser) throws -> [String: Any] {
        let data = try #require(BrowserHosts.manifest(for: browser, tool: tool))
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    @Test func chromiumBrowsersAllowTheExtensionsOrigin() throws {
        let chrome = try manifest(#require(BrowserHosts.browsers.first { $0.folder == "Google/Chrome" }))
        #expect(chrome["name"] as? String == "dev.sibiraj.haul")
        #expect(chrome["path"] as? String == "/Applications/Haul.app/Contents/Helpers/haul")
        #expect(chrome["type"] as? String == "stdio")
        let origin = try #require(BrowserHosts.chromeExtension)
        #expect(chrome["allowed_origins"] as? [String] == [origin])
        #expect(chrome["allowed_extensions"] == nil)
    }

    @Test func firefoxAllowsTheExtensionsID() throws {
        let firefox = try manifest(#require(BrowserHosts.browsers.first { $0.isFirefox }))
        #expect(firefox["allowed_extensions"] as? [String] == ["haul@sibiraj.dev"])
        #expect(firefox["allowed_origins"] == nil)
    }

    @Test func hostsFolders() {
        #expect(BrowserHosts.browsers.map(\.hostsFolder).contains("Mozilla/NativeMessagingHosts"))
        #expect(BrowserHosts.browsers.map(\.hostsFolder).contains("Google/Chrome/NativeMessagingHosts"))
    }

    /// The host name and extension IDs have to match the extension's own files.
    @Test func matchesTheExtension() throws {
        let folder = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "BrowserExtension")
        let script = try String(contentsOf: folder.appending(path: "background.js"), encoding: .utf8)
        #expect(script.contains("const host = '\(BrowserHosts.name)'"))
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appending(path: "manifest.json")))
        let manifest = try #require(object as? [String: Any])
        let gecko = (manifest["browser_specific_settings"] as? [String: Any])?["gecko"] as? [String: Any]
        #expect(gecko?["id"] as? String == BrowserHosts.firefoxExtension)
        // A Chromium extension's ID is the first 32 hex digits of the SHA-256 of its key, spelled with a–p.
        let key = try #require((manifest["key"] as? String).flatMap { Data(base64Encoded: $0) })
        let id = SHA256.hash(data: key).prefix(16).flatMap { [$0 >> 4, $0 & 0xF] }.map { String(UnicodeScalar($0 + 97)) }.joined()
        #expect(BrowserHosts.chromeExtension == "chrome-extension://\(id)/")
        #expect(BrowserHosts.chromeWebStore.lastPathComponent == id)
    }
}
