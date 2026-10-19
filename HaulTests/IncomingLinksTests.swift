import AppKit
import Testing
@testable import Haul

struct IncomingLinksTests {
    @Test func readsEveryURLItem() {
        let url = URL(string: "haul://add?url=https%3A%2F%2Fa.com%2Fx.zip%3Fsig%3D1%26e%3D2&url=http://b.com/y.iso")!
        #expect(IncomingLinks.links(in: url) == [URL(string: "https://a.com/x.zip?sig=1&e=2")!, URL(string: "http://b.com/y.iso")!])
    }

    @Test func ignoresOtherSchemesActionsAndLinks() {
        #expect(IncomingLinks.links(in: URL(string: "https://add?url=https://a.com/x")!).isEmpty)
        #expect(IncomingLinks.links(in: URL(string: "haul://open?url=https://a.com/x")!).isEmpty)
        #expect(IncomingLinks.links(in: URL(string: "haul://add")!).isEmpty)
        // Only http(s) downloads: no local files or other schemes.
        #expect(IncomingLinks.links(in: URL(string: "haul://add?url=file:///etc/hosts&url=ftp://a.com/x")!).isEmpty)
    }

    @Test func schemeAndActionIgnoreCase() {
        #expect(IncomingLinks.links(in: URL(string: "HAUL://Add?url=https://a.com/x")!) == [URL(string: "https://a.com/x")!])
    }

    @Test func readsLinksFromSelectedText() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("haul-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("Get https://a.com/x.zip, or https://b.com/y.zip and https://a.com/x.zip", forType: .string)
        #expect(IncomingLinks.links(on: pasteboard) == [URL(string: "https://a.com/x.zip")!, URL(string: "https://b.com/y.zip")!])
    }
}
