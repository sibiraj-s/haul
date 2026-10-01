import AppKit

/// Checks GitHub Releases for a newer version of Haul and offers to download it.
@Observable
final class Updater {
    static let shared = Updater()
    static let repository = "sibiraj-s/haul"

    /// Automatic checks happen at most this often.
    static let interval: TimeInterval = 86_400

    private(set) var isChecking = false

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var timer: Timer?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let htmlURL: URL
        let body: String?
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body, assets
        }

        var version: String { Updater.normalized(tagName) }
        /// The DMG attached by the release workflow, else the release page.
        var downloadURL: URL { assets.first { $0.name.hasSuffix(".dmg") }?.browserDownloadURL ?? htmlURL }
    }

    enum CheckError: LocalizedError {
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .http(let code): "GitHub answered with HTTP \(code)."
            }
        }
    }

    /// Checks now if automatic checks are on and the last one was over a day ago, then
    /// keeps doing so while the app runs. Stays quiet unless there's an update.
    func startAutomaticChecks() {
        #if DEBUG
        return  // Development builds aren't versioned, so every release would look newer.
        #else
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { Updater.shared.checkIfDue() }
        }
        #endif
    }

    private func checkIfDue() {
        guard AppSettings.shared.checkForUpdates, !isChecking else { return }
        let last = defaults.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= Self.interval else { return }
        Task { await check(userInitiated: false) }
    }

    /// "Check for Updates…": always reports the result, and offers versions the user skipped.
    func checkNow() {
        guard !isChecking else { return }
        Task { await check(userInitiated: true) }
    }

    private func check(userInitiated: Bool) async {
        isChecking = true
        defer { isChecking = false }
        do {
            let release = try await latestRelease()
            defaults.set(Date(), forKey: "lastUpdateCheck")
            guard let release, Self.isNewer(release.version, than: currentVersion) else {
                if userInitiated { showUpToDate() }
                return
            }
            if !userInitiated && defaults.string(forKey: "skippedVersion") == release.version { return }
            offer(release)
        } catch {
            if userInitiated { showError(error) }
        }
    }

    /// The newest published release (drafts and pre-releases excluded); nil if there are none yet.
    private func latestRelease() async throws -> Release? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard status == 200 else { throw CheckError.http(status) }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    // MARK: - Alerts

    /// Standalone alerts rather than sheets: sheets on Haul's title-bar-less windows make
    /// AppKit restore the title bar.
    private func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "Haul \(release.version) is available"
        alert.informativeText = "You have \(currentVersion). Download the new version and drag it to Applications to replace this one."
        if let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            alert.accessoryView = Self.notesView(notes)
        }
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(release.downloadURL)
        case .alertThirdButtonReturn: defaults.set(release.version, forKey: "skippedVersion")
        default: break
        }
    }

    private func showUpToDate() {
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        alert.informativeText = "Haul \(currentVersion) is the latest version."
        NSApp.activate()
        alert.runModal()
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't check for updates"
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }

    /// Scrollable release notes.
    private static func notesView(_ markdown: String) -> NSView {
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 320, height: 140)
        scroll.borderType = .lineBorder
        if let view = scroll.documentView as? NSTextView {
            view.isEditable = false
            view.drawsBackground = false
            view.textContainerInset = NSSize(width: 4, height: 6)
            view.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            view.textColor = .labelColor
            view.string = plainNotes(markdown)
        }
        return scroll
    }

    /// Release notes as plain text: Markdown headings and emphasis markers removed, bullets
    /// kept, and the commit hash Changesets puts before each entry dropped.
    nonisolated static func plainNotes(_ markdown: String) -> String {
        markdown
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacing(/^#+\s*/, with: "")
                    .replacing(#/^([-*]) [0-9a-f]{7,40}: /#, with: { "\($0.1) " })
                    .replacing(/\*\*|__|`/, with: "")
            }
            .joined(separator: "\n")
            .replacing(/\n{3,}/, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Versions

    /// "v1.2.0" → "1.2.0".
    nonisolated static func normalized(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Compares dotted versions numerically, so 1.10.0 is newer than 1.9.0 and 1.2 equals 1.2.0.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            normalized(v).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
