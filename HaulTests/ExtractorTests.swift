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
        try Self.run(
            "/usr/bin/ditto", ["-c", "-k", "--keepParent", dir.appending(path: "src/Tool").path, dir.appending(path: "Tool-1.0.zip").path])

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
        try Self.run(
            "/usr/bin/bsdtar",
            ["-c", "-z", "-f", dir.appending(path: "pair.tar.gz").path, "-C", dir.appending(path: "src").path, "a.txt", "b.txt"])

        let result = try Extractor.extract(dir.appending(path: "pair.tar.gz"))
        #expect(result == dir.appending(path: "pair"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: result.path).sorted() == ["a.txt", "b.txt"])

        // Extracting again keeps the first copy.
        #expect(try Extractor.extract(dir.appending(path: "pair.tar.gz")) == dir.appending(path: "pair 2"))
    }

    @Test func stoppedExtractionLeavesOnlyTheArchive() throws {
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.write("a", to: dir.appending(path: "src/a.txt"))
        let archive = dir.appending(path: "a.zip")
        try Self.run("/usr/bin/ditto", ["-c", "-k", dir.appending(path: "src").path, archive.path])
        try FileManager.default.removeItem(at: dir.appending(path: "src"))

        let job = Extractor.Job()
        job.stop()
        #expect(throws: CancellationError.self) { try Extractor.extract(archive, job: job) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["a.zip"])
    }

    @Test func progressCountsWhatTheToolWasGiven() throws {
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.write("a", to: dir.appending(path: "src/a.txt"))
        try Self.run("/usr/bin/ditto", ["-c", "-k", dir.appending(path: "src").path, dir.appending(path: "a.zip").path])
        try Self.run(
            "/usr/bin/bsdtar",
            ["--format", "7zip", "-c", "-f", dir.appending(path: "a.7z").path, "-C", dir.appending(path: "src").path, "a.txt"])

        let zip = Extractor.Job()
        #expect(zip.fraction == nil)
        _ = try Extractor.extract(dir.appending(path: "a.zip"), job: zip)
        #expect(zip.fraction == 1)

        // 7z is read from the file by bsdtar itself, so there's no progress to show.
        let sevenZip = Extractor.Job()
        let result = try Extractor.extract(dir.appending(path: "a.7z"), job: sevenZip)
        #expect(try String(contentsOf: result, encoding: .utf8) == "a")
        #expect(sevenZip.fraction == nil)
    }

    @Test func zipKeepsPermissionsAndSymlinks() throws {
        let dir = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fm = FileManager.default
        let tool = dir.appending(path: "src/Tool")
        try Self.write("#!/bin/sh", to: tool.appending(path: "run"))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.appending(path: "run").path)
        try fm.createSymbolicLink(atPath: tool.appending(path: "link").path, withDestinationPath: "run")
        try Self.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", tool.path, dir.appending(path: "Tool.zip").path])

        let result = try Extractor.extract(dir.appending(path: "Tool.zip"))
        let mode = try fm.attributesOfItem(atPath: result.appending(path: "run").path)[.posixPermissions] as? Int
        #expect(mode == 0o755)
        #expect(try fm.destinationOfSymbolicLink(atPath: result.appending(path: "link").path) == "run")
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
