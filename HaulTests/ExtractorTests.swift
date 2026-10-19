import Foundation
import Testing
@testable import Haul

struct ExtractorTests {
    @Test func knowsWhichArchivesItCanExtract() {
        for name in ["a.zip", "A.ZIP", "a.tar", "a.tar.gz", "a.tgz", "a.tar.bz2", "a.tbz2", "a.tar.xz", "a.txz", "a.7z"] {
            #expect(Extractor.canExtract(name), "\(name)")
        }
        for name in ["a.dmg", "a.iso", "a.rar", "a.gz", "a.xip", "zip", ".zip", "a.zip.part"] {
            #expect(!Extractor.canExtract(name), "\(name)")
        }
    }

    @Test func baseNameDropsTheWholeEnding() {
        #expect(Extractor.baseName("app-1.2.tar.gz") == "app-1.2")
        #expect(Extractor.baseName("Photos.zip") == "Photos")
        #expect(Extractor.baseName("x.7z") == "x")
    }

    @Test func loneFolderIsPlacedBesideTheArchive() throws {
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.write("one", to: dir.appending(path: "src/Tool/readme.txt"))
        try Self.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", dir.appending(path: "src/Tool").path, dir.appending(path: "Tool-1.0.zip").path])

        let result = try Extractor.extract(dir.appending(path: "Tool-1.0.zip"))
        #expect(result == dir.appending(path: "Tool"))
        #expect(try String(contentsOf: result.appending(path: "readme.txt"), encoding: .utf8) == "one")
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "Tool-1.0.zip").path))
        // Nothing left behind but the archive, its source and the result.
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == ["Tool", "Tool-1.0.zip", "src"])
    }

    @Test func severalItemsGoIntoAFolderNamedAfterTheArchive() throws {
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.write("a", to: dir.appending(path: "src/a.txt"))
        try Self.write("b", to: dir.appending(path: "src/b.txt"))
        try Self.run("/usr/bin/bsdtar", ["-c", "-z", "-f", dir.appending(path: "pair.tar.gz").path, "-C", dir.appending(path: "src").path, "a.txt", "b.txt"])

        let result = try Extractor.extract(dir.appending(path: "pair.tar.gz"))
        #expect(result == dir.appending(path: "pair"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: result.path).sorted() == ["a.txt", "b.txt"])

        // Extracting again keeps the first copy.
        #expect(try Extractor.extract(dir.appending(path: "pair.tar.gz")) == dir.appending(path: "pair 2"))
    }

    @Test func damagedArchiveFailsAndCleansUp() throws {
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.write("not a zip", to: dir.appending(path: "broken.zip"))
        #expect(throws: Extractor.Failure.self) { try Extractor.extract(dir.appending(path: "broken.zip")) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["broken.zip"])
    }

    private static func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "haul-extract-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = try Process.run(URL(filePath: tool), arguments: arguments)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
