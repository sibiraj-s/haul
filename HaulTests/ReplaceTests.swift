import Foundation
import Testing
@testable import Haul

/// Replacing an existing file with a finished download. A stand-in Trash folder keeps the
/// real Trash out of it.
struct ReplaceTests {
    private let folder: URL
    private let trash: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "ReplaceTests-\(UUID().uuidString)")
        trash = folder.appending(path: "Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    private func file(_ name: String, _ contents: String) throws -> URL {
        let url = folder.appending(path: name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func contents(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    private func moveToTrash(_ url: URL) throws -> URL? {
        let trashed = trash.appending(path: url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: trashed)
        return trashed
    }

    @Test func newFileTakesTheOldOnesPlace() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = try file("a.zip", "old")
        let new = try file("a 2.zip", "new")

        let result = DownloadStore.swapIn(new, for: old, trash: moveToTrash)

        #expect(result == old)
        #expect(contents(old) == "new")
        #expect(!FileManager.default.fileExists(atPath: new.path))
        #expect(contents(trash.appending(path: "a.zip")) == "old")
    }

    @Test func bothFilesKeptWhenTrashingFails() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = try file("a.zip", "old")
        let new = try file("a 2.zip", "new")

        let result = DownloadStore.swapIn(new, for: old, trash: { _ in throw CocoaError(.fileWriteNoPermission) })

        #expect(result == new)
        #expect(contents(old) == "old")
        #expect(contents(new) == "new")
    }

    @Test func originalPutBackWhenNewFileCantMove() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = try file("a.zip", "old")
        let missing = folder.appending(path: "a 2.zip")  // nothing there, so the move in fails

        let result = DownloadStore.swapIn(missing, for: old, trash: moveToTrash)

        #expect(result == missing)
        #expect(contents(old) == "old")
    }
}
