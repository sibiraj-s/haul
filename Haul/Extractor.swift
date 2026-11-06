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

    /// Lets the caller follow and stop an extraction running on another thread.
    nonisolated final class Job: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var stopped = false
        private var finishing = false
        private var fed: Int64 = 0
        private var total: Int64?
        private var work: URL?

        /// Stops the tool; `extract` then throws `CancellationError` and leaves nothing behind.
        /// Too late once the results are being moved into place.
        func stop() {
            lock.withLock {
                guard !finishing else { return }
                stopped = true
                process?.terminate()
            }
        }

        var isStopped: Bool { lock.withLock { stopped } }

        /// For quitting: stops the tool and removes its half-made results right away, as the
        /// extraction's own cleanup won't get to run.
        func abandon() {
            stop()
            let (process, work) = lock.withLock { (process, finishing ? nil : work) }
            // Not waitUntilExit: that runs the main run loop, letting other work start mid-quit.
            for _ in 0..<50 where process?.isRunning == true { usleep(20_000) }
            if let work { try? FileManager.default.removeItem(at: work) }
        }

        /// How much of the archive the tool has been given, or nil when it reads the file itself (7z).
        var fraction: Double? {
            lock.withLock {
                guard let total, total > 0 else { return nil }
                return min(1, Double(fed) / Double(total))
            }
        }

        fileprivate func extracting(into work: URL) { lock.withLock { self.work = work } }

        fileprivate func start(_ process: Process) throws {
            try lock.withLock {
                if stopped { throw CancellationError() }
                try process.run()
                self.process = process
            }
        }

        fileprivate func fed(_ bytes: Int, of total: Int64) {
            lock.withLock {
                fed += Int64(bytes)
                self.total = total
            }
        }

        /// Called before the results are moved into place; throws if stopped by then.
        fileprivate func finish() throws {
            try lock.withLock {
                if stopped { throw CancellationError() }
                finishing = true
            }
        }
    }

    /// Extracts `archive` into its own folder; returns the item that now holds its contents.
    /// With a `job`, the extraction can be followed and stopped.
    static func extract(_ archive: URL, job: Job? = nil) throws -> URL {
        guard let matched = match(archive.lastPathComponent) else {
            throw Failure(errorDescription: "“\(archive.lastPathComponent)” isn't an archive Haul can extract.")
        }
        let fm = FileManager.default
        let folder = archive.deletingLastPathComponent()
        // A hidden folder on the same volume, so the results can be moved into place.
        let work = folder.appending(path: ".\(baseName(archive.lastPathComponent)).haul-extract-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: work) }
        job?.extracting(into: work)

        // The archive is fed to the tool ("-" reads it from standard input), so Haul can tell how
        // far along it is; the sandbox won't let it look at what the tool reads. 7z can't be read
        // that way, as its index is at the end.
        switch matched.tool {
        case .ditto: try run("/usr/bin/ditto", ["-x", "-k", "-", work.path], feeding: archive, job: job)
        case .bsdtar where matched.ending == ".7z":
            try run("/usr/bin/bsdtar", ["-x", "-f", archive.path, "-C", work.path], feeding: nil, job: job)
        case .bsdtar: try run("/usr/bin/bsdtar", ["-x", "-f", "-", "-C", work.path], feeding: archive, job: job)
        }

        // Resource forks of zips made in Finder; ditto has already applied them.
        try? fm.removeItem(at: work.appending(path: "__MACOSX"))
        let contents = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != ".DS_Store" }
        if contents.isEmpty { throw Failure(errorDescription: "The archive is empty.") }

        let (source, name) =
            contents.count == 1
            ? (contents[0], contents[0].lastPathComponent)
            : (work, baseName(archive.lastPathComponent))
        try job?.finish()
        let target = uniqueURL(in: folder, name: name)
        try fm.moveItem(at: source, to: target)
        return target
    }

    /// Runs `tool`, writing the file `feeding` (if any) to its standard input.
    private static func run(_ tool: String, _ arguments: [String], feeding input: URL?, job: Job?) throws {
        let source = try input.map { try FileHandle(forReadingFrom: $0) }
        defer { try? source?.close() }
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        let pipe = source.map { _ in Pipe() }
        if let pipe {
            process.standardInput = pipe
            // If the tool quits early, writing fails with EPIPE instead of SIGPIPE ending Haul.
            _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        }
        if let job { try job.start(process) } else { try process.run() }

        // Read errors alongside feeding, so a chatty tool can't fill its pipe and stall both sides.
        let reading = DispatchGroup()
        nonisolated(unsafe) var output = Data()
        DispatchQueue.global().async(group: reading) { output = errors.fileHandleForReading.readDataToEndOfFile() }
        var readError: Error?
        if let source, let pipe {
            do {
                let total = Int64((try? source.seekToEnd()) ?? 0)
                try source.seek(toOffset: 0)
                while job?.isStopped != true, let chunk = try source.read(upToCount: 1 << 20), !chunk.isEmpty {
                    guard (try? pipe.fileHandleForWriting.write(contentsOf: chunk)) != nil else { break }  // the tool quit
                    job?.fed(chunk.count, of: total)
                }
            } catch {
                // The archive couldn't be read (e.g. its volume went away); end the tool before cleaning up.
                readError = error
                process.terminate()
            }
            try? pipe.fileHandleForWriting.close()
        }
        reading.wait()
        process.waitUntilExit()

        if job?.isStopped == true { throw CancellationError() }
        if let readError { throw readError }
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
