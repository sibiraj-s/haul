import Foundation
import Testing
@testable import Haul

struct VersionComparisonTests {
    nonisolated static let newer: [(String, String)] = [
        ("1.0.1", "1.0.0"),
        ("1.1.0", "1.0.9"),
        ("2.0.0", "1.99.99"),
        ("1.10.0", "1.9.0"),
        ("v1.2.0", "1.1.0"),
        ("1.2.1", "1.2"),
        ("0.1.0", "0.0.0"),
    ]

    nonisolated static let notNewer: [(String, String)] = [
        ("1.0.0", "1.0.0"),
        ("1.2", "1.2.0"),
        ("v1.0.0", "1.0.0"),
        ("1.0.0", "1.0.1"),
        ("1.9.0", "1.10.0"),
    ]

    @Test(arguments: newer)
    func newerVersions(candidate: String, current: String) {
        #expect(Updater.isNewer(candidate, than: current))
    }

    @Test(arguments: notNewer)
    func sameOrOlderVersions(candidate: String, current: String) {
        #expect(!Updater.isNewer(candidate, than: current))
    }

    @Test func tagPrefixIsDropped() {
        #expect(Updater.normalized("v1.2.3") == "1.2.3")
        #expect(Updater.normalized("1.2.3") == "1.2.3")
    }
}

struct ReleaseNotesTests {
    @Test func changesetsNotesBecomePlainText() {
        let notes = """
        ## 1.2.0

        ### Minor Changes

        - 4f2a9c1: Add **check for updates**
        - Fix the `Dock` badge



        ### Patch Changes
        """
        #expect(Updater.plainNotes(notes) == """
        1.2.0

        Minor Changes

        - Add check for updates
        - Fix the Dock badge

        Patch Changes
        """)
    }
}

struct ReleaseDecodingTests {
    private func release(assets: String) throws -> Updater.Release {
        let json = """
        {
          "tag_name": "v1.2.0",
          "html_url": "https://github.com/sibiraj-s/haul/releases/tag/v1.2.0",
          "body": "### Minor Changes",
          "assets": [\(assets)]
        }
        """
        return try JSONDecoder().decode(Updater.Release.self, from: Data(json.utf8))
    }

    @Test func downloadsTheAttachedDMG() throws {
        let r = try release(assets: """
            {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"},
            {"name": "Haul-1.2.0.dmg", "browser_download_url": "https://example.com/Haul-1.2.0.dmg"}
            """)
        #expect(r.version == "1.2.0")
        #expect(r.downloadURL.absoluteString == "https://example.com/Haul-1.2.0.dmg")
    }

    @Test func fallsBackToTheReleasePage() throws {
        let r = try release(assets: "")
        #expect(r.downloadURL.absoluteString == "https://github.com/sibiraj-s/haul/releases/tag/v1.2.0")
    }
}
