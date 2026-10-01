import AppKit
import ServiceManagement
import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {
    case light, dark, auto
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case blue, purple, pink, graphite
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: Color(hex: 0x0A7AFF)
        case .purple: Color(hex: 0xA24FD6)
        case .pink: Color(hex: 0xE8437A)
        case .graphite: Color(hex: 0x7D7D84)
        }
    }
}

/// When finished downloads leave the list on their own.
enum ListCleanup: String, CaseIterable, Identifiable {
    case manually, whenFinished, day, week, month
    var id: String { rawValue }

    var label: String {
        switch self {
        case .manually: "Manually"
        case .whenFinished: "When Finished"
        case .day: "After One Day"
        case .week: "After One Week"
        case .month: "After One Month"
        }
    }

    /// How long a finished download stays listed; nil means until removed by hand.
    var age: TimeInterval? {
        switch self {
        case .manually: nil
        case .whenFinished: 0
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        }
    }
}

/// User preferences, persisted to UserDefaults.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults = UserDefaults.standard

    var appearance: Appearance { didSet { save(appearance.rawValue, "appearance"); applyAppearance() } }
    var accent: AccentChoice { didSet { save(accent.rawValue, "accent") } }
    var menuBar: Bool { didSet { save(menuBar, "menuBar") } }
    var dockProgress: Bool { didSet { save(dockProgress, "dockProgress") } }
    /// Notify when a download finishes.
    var notify: Bool { didSet { save(notify, "notify"); if notify { Notifier.requestAuthorization() } } }
    var notifyAdded: Bool { didSet { save(notifyAdded, "notifyAdded"); if notifyAdded { Notifier.requestAuthorization() } } }
    var notifyFailed: Bool { didSet { save(notifyFailed, "notifyFailed"); if notifyFailed { Notifier.requestAuthorization() } } }
    /// Skip notifications while Haul is the frontmost app.
    var notifyOnlyInBackground: Bool { didSet { save(notifyOnlyInBackground, "notifyOnlyInBackground") } }
    var autoSort: Bool { didSet { save(autoSort, "autoSort") } }
    var computeChecksum: Bool { didSet { save(computeChecksum, "computeChecksum") } }
    var maxConcurrent: Int { didSet { save(maxConcurrent, "maxConcurrent") } }
    var connections: Int { didSet { save(connections, "connections") } }
    var limitOn: Bool { didSet { save(limitOn, "limitOn") } }
    var limitMBps: Int { didSet { save(limitMBps, "limitMBps") } }
    var scheduleOnly: Bool { didSet { save(scheduleOnly, "scheduleOnly") } }
    /// Hours (0–23) the schedule runs from and until; it wraps past midnight when `from > to`.
    var scheduleFrom: Int { didSet { save(scheduleFrom, "scheduleFrom") } }
    var scheduleTo: Int { didSet { save(scheduleTo, "scheduleTo") } }
    var pauseOnExpensive: Bool { didSet { save(pauseOnExpensive, "pauseOnExpensive") } }
    /// Keep the Mac from idle-sleeping while something is downloading.
    var preventSleep: Bool { didSet { save(preventSleep, "preventSleep") } }
    var removeFinished: ListCleanup { didSet { save(removeFinished.rawValue, "removeFinished") } }
    /// Drop finished downloads whose file is no longer where it was saved.
    var removeDeleted: Bool { didSet { save(removeDeleted, "removeDeleted") } }
    /// Ask before removing downloads from the list.
    var confirmRemove: Bool { didSet { save(confirmRemove, "confirmRemove") } }
    var autoRetry: Bool { didSet { save(autoRetry, "autoRetry") } }
    var skipWebPages: Bool { didSet { save(skipWebPages, "skipWebPages") } }
    /// Date saved files with the server's Last-Modified instead of when they finished.
    var useServerDate: Bool { didSet { save(useServerDate, "useServerDate") } }
    /// Record the link a file came from (Finder's "Where from").
    var recordSource: Bool { didSet { save(recordSource, "recordSource") } }
    /// Look for a newer release on GitHub once a day.
    var checkForUpdates: Bool { didSet { save(checkForUpdates, "checkForUpdates") } }
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Default save folder chosen by the user; nil means ~/Downloads.
    private(set) var defaultFolder: SavedFolder?
    /// Folders picked recently in the Add panel, newest first.
    private(set) var recentFolders: [SavedFolder] = []

    private init() {
        let d = UserDefaults.standard
        appearance = Appearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .auto
        accent = AccentChoice(rawValue: d.string(forKey: "accent") ?? "") ?? .blue
        menuBar = d.object(forKey: "menuBar") as? Bool ?? true
        dockProgress = d.object(forKey: "dockProgress") as? Bool ?? true
        notify = d.object(forKey: "notify") as? Bool ?? true
        notifyAdded = d.object(forKey: "notifyAdded") as? Bool ?? false
        notifyFailed = d.object(forKey: "notifyFailed") as? Bool ?? true
        notifyOnlyInBackground = d.object(forKey: "notifyOnlyInBackground") as? Bool ?? false
        autoSort = d.object(forKey: "autoSort") as? Bool ?? true
        computeChecksum = d.object(forKey: "computeChecksum") as? Bool ?? true
        maxConcurrent = d.object(forKey: "maxConcurrent") as? Int ?? 3
        connections = d.object(forKey: "connections") as? Int ?? 8
        limitOn = d.object(forKey: "limitOn") as? Bool ?? false
        limitMBps = d.object(forKey: "limitMBps") as? Int ?? 8
        scheduleOnly = d.object(forKey: "scheduleOnly") as? Bool ?? false
        scheduleFrom = d.object(forKey: "scheduleFrom") as? Int ?? 1
        scheduleTo = d.object(forKey: "scheduleTo") as? Int ?? 7
        pauseOnExpensive = d.object(forKey: "pauseOnExpensive") as? Bool ?? true
        preventSleep = d.object(forKey: "preventSleep") as? Bool ?? true
        removeFinished = ListCleanup(rawValue: d.string(forKey: "removeFinished") ?? "") ?? .manually
        removeDeleted = d.object(forKey: "removeDeleted") as? Bool ?? true
        confirmRemove = d.object(forKey: "confirmRemove") as? Bool ?? true
        autoRetry = d.object(forKey: "autoRetry") as? Bool ?? true
        skipWebPages = d.object(forKey: "skipWebPages") as? Bool ?? true
        useServerDate = d.object(forKey: "useServerDate") as? Bool ?? false
        recordSource = d.object(forKey: "recordSource") as? Bool ?? true
        checkForUpdates = d.object(forKey: "checkForUpdates") as? Bool ?? true
        defaultFolder = d.data(forKey: "defaultFolder").flatMap { SavedFolder(bookmark: $0) }
        recentFolders = (d.array(forKey: "recentFolders") as? [Data] ?? []).compactMap { SavedFolder(bookmark: $0) }
    }

    /// Whether `hour` falls in the schedule. Equal start and end means all day.
    func inSchedule(hour: Int) -> Bool { Self.inSchedule(hour: hour, from: scheduleFrom, to: scheduleTo) }

    static func inSchedule(hour: Int, from: Int, to: Int) -> Bool {
        if from == to { return true }
        return from < to ? (from..<to).contains(hour) : hour >= from || hour < to
    }

    /// "01:00" or "1 AM", following the user's clock format.
    static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    func setDefaultFolder(_ folder: SavedFolder?) {
        defaultFolder = folder
        defaults.set(folder?.bookmark, forKey: "defaultFolder")
    }

    func rememberRecent(_ folder: SavedFolder) {
        recentFolders.removeAll { $0.url == folder.url }
        recentFolders.insert(folder, at: 0)
        recentFolders = Array(recentFolders.prefix(5))
        defaults.set(recentFolders.map(\.bookmark), forKey: "recentFolders")
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Haul: couldn't change login item: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func applyAppearance() {
        NSApp?.appearance = switch appearance {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .auto: nil
        }
    }

    var downloadsFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].resolvingSymlinksInPath()
    }

    /// Where downloads go by default: the chosen folder, or ~/Downloads.
    var baseFolder: URL { defaultFolder?.url ?? downloadsFolder }

    /// Default destination for a kind, including the per-kind subfolder when sorting is on.
    func folder(for kind: FileKind) -> URL {
        autoSort ? baseFolder.appending(path: kind.folder, directoryHint: .isDirectory) : baseFolder
    }

    func folderLabel(for kind: FileKind) -> String {
        autoSort ? "\(baseFolder.lastPathComponent)/\(kind.folder)" : baseFolder.lastPathComponent
    }
}

/// A folder the user picked, kept as a security-scoped bookmark so the sandboxed app can
/// write there again after relaunching. Access is started once and held for the app's lifetime.
struct SavedFolder: Equatable {
    let url: URL
    let bookmark: Data

    private static var accessing: Set<URL> = []

    /// Bookmarks a folder the user just chose in an open panel.
    init?(choosing url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return nil }
        self.url = url
        bookmark = data
        Self.startAccess(url)
    }

    /// Restores a saved bookmark; nil if the folder no longer exists.
    init?(bookmark data: Data) {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        Self.startAccess(url)
        // A stale bookmark still resolves (e.g. the folder moved); refresh it while we have access.
        bookmark = stale ? (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)) ?? data : data
        self.url = url
    }

    private static func startAccess(_ url: URL) {
        guard !accessing.contains(url), url.startAccessingSecurityScopedResource() else { return }
        accessing.insert(url)
    }

    static func == (a: SavedFolder, b: SavedFolder) -> Bool { a.url == b.url }

    /// Shows a folder picker in its own window. (Not a sheet: attaching one to Haul's
    /// title-bar-less windows makes AppKit restore the title bar over the content.)
    @MainActor static func choose(message: String) async -> SavedFolder? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = message
        NSApp.activate()
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        guard response == .OK, let url = panel.url else { return nil }
        return SavedFolder(choosing: url)
    }
}
