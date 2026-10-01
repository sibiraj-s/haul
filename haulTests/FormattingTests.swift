import Testing
@testable import Haul

private let KB = 1024.0, MB = KB * 1024, GB = MB * 1024

struct FormattingTests {
    nonisolated static let byteCases: [(Double, String)] = [
        (0, "0 KB"),
        (1536, "2 KB"),
        (5 * MB, "5.0 MB"),
        (1.5 * GB, "1.50 GB"),
        (12 * GB, "12.0 GB"),
    ]

    nonisolated static let durationCases: [(Double?, String)] = [
        (nil, "—"),
        (30, "30 sec"),
        (59.2, "1 min"),
        (90, "2 min"),
        (3700, "1 hr 2 min"),
    ]

    @Test(arguments: byteCases)
    func bytes(_ value: Double, _ expected: String) {
        #expect(formatBytes(value) == expected)
    }

    @Test func negativeBytesClampToZero() {
        #expect(formatBytes(-500.0) == "0 KB")
    }

    @Test(arguments: durationCases)
    func duration(_ seconds: Double?, _ expected: String) {
        #expect(formatDuration(seconds) == expected)
    }

    @Test func infiniteDurationIsUnknown() {
        #expect(formatDuration(.infinity) == "—")
    }
}

struct FileKindTests {
    nonisolated static let cases: [(String, FileKind)] = [
        ("movie.MKV", .video),
        ("song.flac", .audio),
        ("photo.heic", .image),
        ("backup.tar.gz", .archive),
        ("Installer.dmg", .app),
        ("notes.pdf", .doc),
        ("README", .doc),
    ]

    @Test(arguments: cases)
    func kindFromName(_ name: String, _ kind: FileKind) {
        #expect(FileKind.of(name) == kind)
    }

    @Test func extensionsWithOddCharactersAreIgnored() {
        #expect(fileExtension("report.final version") == "")
        #expect(fileExtension("archive.7Z") == "7z")
    }
}
