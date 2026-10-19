import Foundation

/// Unpacks a finished archive next to it, as Archive Utility does: a lone top-level item is
/// placed beside the archive, several go into a folder named after it. The archive is kept.
/// Uses the system's ditto (zip) and bsdtar (tar, 7z), which refuse entries that point outside
/// the folder they extract into.
nonisolated enum Extractor {
    private enum Tool { case ditto, bsdtar }

    /// Endings of the archives Haul can extract, longest first so "a.tar.gz" isn't taken for ".gz".
    private static let endings: [(ending: String, tool: Tool)] = [
        (".tar.gz", .bsdtar), (".tar.bz2", .bsdtar), (".tar.xz", .bsdtar),
        (".zip", .ditto), (".tar", .bsdtar), (".tgz", .bsdtar), (".tbz", .bsdtar), (".tbz2", .bsdtar),
        (".txz", .bsdtar), (".7z", .bsdtar),
    ]

    private static func match(_ name: String) -> (ending: String, tool: Tool)? {
        let lower = name.lowercased()
        return endings.first { lower.hasSuffix($0.ending) && lower.count > $0.ending.count }
    }

    static func canExtract(_ name: String) -> Bool { match(name) != nil }

    /// The archive's name without its archive ending: "app.tar.gz" → "app".
    static func baseName(_ name: String) -> String {
        guard let ending = match(name)?.ending else { return (name as NSString).deletingPathExtension }
        return String(name.dropLast(ending.count))
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    /// Extracts `archive` into its own folder; returns the item that now holds its contents.
    static func extract(_ archive: URL) throws -> URL {
        guard let tool = match(archive.lastPathComponent)?.tool else {
            throw Failure(errorDescription: "“\(archive.lastPathComponent)” isn't an archive Haul can extract.")
        }
        let fm = FileManager.default
        let folder = archive.deletingLastPathComponent()
        // A hidden folder on the same volume, so the results can be moved into place.
        let work = folder.appending(path: ".\(baseName(archive.lastPathComponent)).haul-extract-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: work) }

        switch tool {
        case .ditto: try run("/usr/bin/ditto", ["-x", "-k", archive.path, work.path])
        case .bsdtar: try run("/usr/bin/bsdtar", ["-x", "-f", archive.path, "-C", work.path])
        }

        // Resource forks of zips made in Finder; ditto has already applied them.
        try? fm.removeItem(at: work.appending(path: "__MACOSX"))
        let contents = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != ".DS_Store" }
        if contents.isEmpty { throw Failure(errorDescription: "The archive is empty.") }

        let (source, name) = contents.count == 1
            ? (contents[0], contents[0].lastPathComponent)
            : (work, baseName(archive.lastPathComponent))
        let target = uniqueURL(in: folder, name: name)
        try fm.moveItem(at: source, to: target)
        return target
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let output = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return }
        // The tools' last line names the problem, e.g. "bsdtar: Damaged archive".
        let message = String(decoding: output, as: UTF8.self).split(separator: "\n").last.map(String.init)
        throw Failure(errorDescription: message ?? "\((tool as NSString).lastPathComponent) failed (\(process.terminationStatus)).")
    }

    /// `name` in `folder`, or "name 2", "name 3"… when taken. A folder name keeps any dots.
    private static func uniqueURL(in folder: URL, name: String) -> URL {
        var url = folder.appending(path: name)
        var isFolder: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
        let ext = isFolder.boolValue ? "" : (name as NSString).pathExtension
        let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appending(path: ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }
}
