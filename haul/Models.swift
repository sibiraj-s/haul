import SwiftUI

enum DownloadStatus: String, Codable {
    case downloading, paused, queued, failed, completed

    var label: String {
        switch self {
        case .downloading: "Downloading"
        case .paused: "Paused"
        case .queued: "Queued"
        case .failed: "Failed"
        case .completed: "Completed"
        }
    }

    var isUnfinished: Bool { self == .downloading || self == .paused || self == .queued }
}

enum FileKind: String, Codable, CaseIterable, Identifiable {
    case video, audio, image, doc, archive, app

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .video: Color(hex: 0x7A5AF5)
        case .audio: Color(hex: 0xE5487F)
        case .image: Color(hex: 0xE8673A)
        case .doc: Color(hex: 0x3478F6)
        case .archive: Color(hex: 0x9A8468)
        case .app: Color(hex: 0x5D6878)
        }
    }

    var label: String {
        switch self {
        case .video: "Movie"
        case .audio: "Audio"
        case .image: "Image"
        case .doc: "Document"
        case .archive: "Archive"
        case .app: "Installer"
        }
    }

    /// Subfolder of Downloads used when "Sort into folders by kind" is on.
    var folder: String {
        switch self {
        case .video: "Movies"
        case .audio: "Music"
        case .image: "Pictures"
        case .doc: "Documents"
        case .archive: "Archives"
        case .app: "Apps"
        }
    }

    var sidebarTitle: String {
        switch self {
        case .video: "Movies"
        case .audio: "Music"
        case .image: "Images"
        case .doc: "Documents"
        case .archive: "Archives"
        case .app: "Apps"
        }
    }

    var symbol: String {
        switch self {
        case .video: "film"
        case .audio: "music.note"
        case .image: "photo"
        case .doc: "doc.text"
        case .archive: "archivebox"
        case .app: "shippingbox"
        }
    }

    private static let byExtension: [String: FileKind] = [
        "mp4": .video, "mov": .video, "mkv": .video, "webm": .video, "avi": .video, "m4v": .video,
        "jpg": .image, "jpeg": .image, "png": .image, "heic": .image, "gif": .image, "webp": .image, "tiff": .image,
        "pdf": .doc, "key": .doc, "epub": .doc, "docx": .doc, "pages": .doc, "txt": .doc, "csv": .doc,
        "mp3": .audio, "flac": .audio, "wav": .audio, "m4a": .audio, "aac": .audio, "ogg": .audio,
        "zip": .archive, "gz": .archive, "tgz": .archive, "bz2": .archive, "xz": .archive, "7z": .archive,
        "rar": .archive, "tar": .archive, "iso": .archive, "xip": .archive,
        "dmg": .app, "pkg": .app, "app": .app,
    ]

    static func of(_ filename: String) -> FileKind {
        byExtension[fileExtension(filename)] ?? .doc
    }
}

func fileExtension(_ name: String) -> String {
    let ext = (name as NSString).pathExtension.lowercased()
    return ext.allSatisfy { $0.isLetter || $0.isNumber } ? ext : ""
}

/// A byte range fetched over its own connection. `end` is inclusive; nil means
/// "until the server closes the stream" (size unknown up front).
nonisolated struct Segment: Codable, Hashable, Sendable {
    var start: Int64
    var end: Int64?
    var done: Int64 = 0

    var length: Int64? { end.map { $0 - start + 1 } }

    var isComplete: Bool {
        guard let length else { return false }
        return done >= length
    }

    var fraction: Double {
        guard let length else { return 0 }
        return length > 0 ? min(1, Double(done) / Double(length)) : 1
    }

    static func split(size: Int64?, connections: Int, resumable: Bool) -> [Segment] {
        guard let size else { return [Segment(start: 0, end: nil)] }
        // Don't bother splitting tiny files: keep each segment at least 256 KB.
        let count = resumable ? max(1, min(Int64(connections), size / (256 * 1024))) : 1
        let chunk = size / count
        return (0..<count).map { i in
            let start = i * chunk
            let end = i == count - 1 ? size - 1 : start + chunk - 1
            return Segment(start: start, end: end)
        }
    }
}

struct Download: Codable, Identifiable {
    var id = UUID()
    var url: URL
    var name: String
    var size: Int64?
    var status: DownloadStatus
    var connections: Int
    var resumable = false
    var segments: [Segment] = []
    var added = Date()
    var finished: Date?
    var error: String?
    var fileURL: URL?
    var sha256: String?
    /// Set when the user renamed it, so the server's suggested name no longer overrides it.
    /// Optional so lists saved before this field existed still decode.
    var renamed: Bool?
    /// Validators for the exact file version being downloaded (sent as If-Range on resume).
    var etag: String?
    var lastModified: String?
    /// Why the last attempt failed, when the fix is something other than Retry.
    var issue: DownloadIssue?
    /// Folder picked for this download in the Add panel (security-scoped bookmark);
    /// nil means the default folder from Settings.
    var folderBookmark: Data?
    var folderName: String?
    /// Position in the queue; lower starts first. Fractional so an item can be moved
    /// between two others without renumbering.
    var queueOrder: Double?
    /// Replace a file with the same name at the destination instead of saving alongside it.
    var replaceExisting: Bool?
    /// The sign-in the server asked for (with `issue == .signIn`).
    var authRealm: String?
    var authDigest: Bool?

    /// Live engine state; not persisted.
    var speed: Double = 0
    var liveConnections = 0
    var serverLimit: Int?
    /// When the current run started; used to pick which downloads go back to the queue
    /// when the simultaneous-download limit is lowered.
    var startedAt: Date?
    /// Automatic retries used since the download last made progress, and when the next is due.
    var retries = 0
    var retryAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, url, name, size, status, connections, resumable, segments, added, finished, error, fileURL, sha256, renamed, etag, lastModified, issue, folderBookmark, folderName, queueOrder, replaceExisting, authRealm, authDigest
    }

    var kind: FileKind { .of(name) }
    var host: String { url.host() ?? url.absoluteString }
    var ext: String { String(fileExtension(name).uppercased().prefix(4)) }
    var received: Int64 { segments.reduce(0) { $0 + $1.done } }

    var progress: Double {
        if status == .completed { return 1 }
        guard let size, size > 0 else { return 0 }
        return min(1, Double(received) / Double(size))
    }

    var remainingTime: TimeInterval? {
        guard let size, speed > 0 else { return nil }
        return Double(size - received) / speed
    }
}

enum DownloadIssue: String, Codable {
    /// Server rejected the link (401/403/404/410); a fresh link is needed.
    case linkExpired
    /// The file changed on the server; the partial data has to be discarded.
    case fileChanged
    /// The server wants a username and password.
    case signIn
}

enum SidebarFilter: Hashable {
    case all, active, queued, completed, failed
    case kind(FileKind)

    var title: String {
        switch self {
        case .all: "All Downloads"
        case .active: "Active"
        case .queued: "Queued"
        case .completed: "Completed"
        case .failed: "Failed"
        case .kind(let k): k.sidebarTitle
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray"
        case .active: "arrow.down.circle"
        case .queued: "clock"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .kind(let k): k.symbol
        }
    }

    static let library: [SidebarFilter] = [.all, .active, .queued, .completed, .failed]

    func matches(_ d: Download) -> Bool {
        switch self {
        case .all: true
        case .active: d.status == .downloading || d.status == .paused
        case .queued: d.status == .queued
        case .completed: d.status == .completed
        case .failed: d.status == .failed
        case .kind(let k): d.kind == k
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Formatting (binary units: 1 KB = 1024 bytes)

private let KB = 1024.0, MB = KB * 1024, GB = MB * 1024

func formatBytes<T: BinaryInteger>(_ bytes: T) -> String { formatBytes(Double(bytes)) }

func formatBytes(_ b: Double) -> String {
    if b >= GB { return String(format: b >= 10 * GB ? "%.1f GB" : "%.2f GB", b / GB) }
    if b >= MB { return String(format: "%.1f MB", b / MB) }
    return "\(max(0, Int((b / KB).rounded()))) KB"
}

func formatDuration(_ seconds: TimeInterval?) -> String {
    guard let seconds, seconds.isFinite else { return "—" }
    let s = Int(seconds.rounded(.up))
    if s < 60 { return "\(s) sec" }
    let m = Int((Double(s) / 60).rounded())
    if m < 60 { return "\(m) min" }
    return "\(m / 60) hr \(m % 60) min"
}

func formatAdded(_ date: Date) -> String {
    let cal = Calendar.current
    let time = date.formatted(date: .omitted, time: .shortened)
    if cal.isDateInToday(date) { return "Today, \(time)" }
    if cal.isDateInYesterday(date) { return "Yesterday, \(time)" }
    return date.formatted(.dateTime.month(.abbreviated).day())
}
