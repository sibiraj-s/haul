import AppKit
import CryptoKit
import Network
import SwiftUI
import UserNotifications

@Observable
final class DownloadStore {
    static let shared = DownloadStore()

    var items: [Download] = []
    var selection: UUID?
    var filter: SidebarFilter = .all
    var query = ""
    var showAdd = false
    /// Download whose name the inspector should start editing.
    var renaming: UUID?
    /// Download shown in the Update Link panel.
    var updatingLink: UUID?
    /// Links sent from another app (a haul:// link, the Services menu), waiting for the Add panel to take them.
    var incomingLinks: [URL] = []
    /// What Safari sent with incoming links, kept until they're added. A link that's edited in
    /// the Add panel no longer matches, so it goes without.
    @ObservationIgnored var browserContexts: [URL: BrowserContext] = [:]
    /// On Personal Hotspot, a cellular connection or Low Data Mode.
    private(set) var onExpensiveNetwork = false
    /// The metered network is one with Low Data Mode turned on, rather than Personal Hotspot.
    private(set) var onLowDataMode = false
    /// Set by "Download Anyway" to ignore "Pause on Personal Hotspot" until the Mac changes
    /// network. The setting itself stays as it is.
    private(set) var allowExpensiveNetwork = false
    /// Downloads started by hand while waiting for the network; they keep going on it.
    @ObservationIgnored private var startedOnExpensive: Set<UUID> = []
    /// Paused from the network badge; they resume on their own on an unmetered network, and are
    /// saved as queued so that after a relaunch the setting decides again.
    private(set) var pausedForNetwork: Set<UUID> = []
    /// The interface and router of the current network, to tell when it changes.
    @ObservationIgnored private var networkID = ""
    /// Nothing starts until the first network update, so a relaunch on a hotspot doesn't start
    /// what was paused for it before we know.
    @ObservationIgnored private var networkKnown = false
    /// Every network the Mac is on, for spreading a download's connections over them.
    private(set) var networks = NetworkWatch.State()
    @ObservationIgnored private var networkWatch: NetworkWatch?
    /// Downloads go through a proxy; read when a download starts and each tick while it could matter,
    /// rather than on every use, as reading the system's proxy settings isn't free.
    private(set) var proxied = false
    /// Queued downloads are held back because of the network.
    var waitingForNetwork: Bool { settings.pauseOnExpensive && onExpensiveNetwork && !allowExpensiveNetwork }

    /// Set by a view that has access to `openWindow`, so non-view code can bring the main window back.
    @ObservationIgnored var openMainWindow: (() -> Void)?

    let settings = AppSettings.shared
    @ObservationIgnored private var engines: [UUID: SegmentedDownloader] = [:]
    /// Downloads whose probe is in flight, with a token for that probe so a stale one can tell it was superseded.
    @ObservationIgnored private var probing: [UUID: UUID] = [:]

    /// An archive being extracted, as the extraction window shows it. Kept apart from `items`
    /// so it stays listed if the download is removed meanwhile ("Remove When Finished").
    struct Extraction: Identifiable {
        let download: Download
        /// How far along it is, when that can be seen.
        var fraction: Double?
        var id: UUID { download.id }
    }
    private(set) var extractions: [Extraction] = []
    @ObservationIgnored private var extractionJobs: [UUID: Extractor.Job] = [:]
    @ObservationIgnored private var extractionPolling: Task<Void, Never>?
    @ObservationIgnored private let limiter = RateLimiter()
    /// Recent (bytes, time) readings per download; speed is measured across this window like curl's progress meter.
    @ObservationIgnored private var samples: [UUID: [(bytes: Int64, at: Date)]] = [:]
    /// The same readings for each network, while a download uses more than one.
    @ObservationIgnored private var networkSamples: [UUID: [(bytes: [String: Int64], at: Date)]] = [:]
    /// The networks each running engine was given, to tell when they should change.
    @ObservationIgnored private var engineRoutes: [UUID: [Route]] = [:]
    /// Whether "Multi-network downloads" was on when each running engine started, so turning it on or off
    /// applies at once rather than waiting like a network that just joined.
    @ObservationIgnored private var engineAllNetworks: [UUID: Bool] = [:]
    /// Networks a running download could add, and since when, until they've held long enough to restart it on them.
    @ObservationIgnored private var newRoutes: [UUID: (routes: [Route], since: Date)] = [:]
    /// How long a network must stay before running downloads restart to use it, so one that keeps
    /// dropping out and coming back doesn't restart them over and over.
    nonisolated static let networkSettle: TimeInterval = 10
    private static let speedWindow: TimeInterval = 4
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private let dock = DockProgress()
    /// Simultaneous-download limit the running set was last checked against.
    @ObservationIgnored private var appliedLimit: Int?
    /// Held while downloading with "Prevent sleep" on.
    @ObservationIgnored private var sleepActivity: NSObjectProtocol?
    @ObservationIgnored private var lastCleanup = Date.distantPast
    /// Waits before each automatic retry; its length is the number of retries.
    private static let retryDelays: [TimeInterval] = [10, 30, 60, 120, 300]
    static var maxRetries: Int { retryDelays.count }

    private init() {
        // Before anything can start, so no download goes around a proxy at launch.
        refreshProxied()
        load()
        // Anything that was running when we quit goes back in the queue and resumes on its own.
        for i in items.indices where items[i].status == .downloading { items[i].status = .queued }
        // Lists saved before queue ordering existed: oldest first, as the queue used to run.
        if items.contains(where: { $0.queueOrder == nil }) {
            var next = queueEnd
            for i in items.indices.reversed() where items[i].queueOrder == nil {
                items[i].queueOrder = next
                next += 1
            }
        }
        selection = items.first?.id

        // Common modes, so progress keeps updating while a menu is open or a window is being resized.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        pathMonitor.pathUpdateHandler = { [weak self] path in
            // The interface traffic goes over, skipping VPN tunnels; others may still be joined to a hotspot.
            let primary = path.availableInterfaces.first { $0.type != .other && $0.type != .loopback }
            // A failed read keeps the last lease, so the network doesn't seem to change.
            let lease = primary.flatMap(NetworkLease.read)
            let hotspot = path.isExpensive || lease?.metered == true
            let expensive = hotspot || path.isConstrained
            let lowData = path.isConstrained && !hotspot
            let id = "\(primary?.name ?? "") \(lease?.router ?? "")"
            // In order, so an older update can't land after a newer one.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.networkChanged(id: id, expensive: expensive, lowData: lowData) }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "Haul.network"))
        let watch = NetworkWatch { [weak self] state in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.networks = state } }
        }
        watch.start()
        networkWatch = watch
    }

    /// Offer "Multi-network downloads" once, when there's more than one usable network to use.
    var offersAllNetworks: Bool {
        !settings.useAllNetworks && !settings.allNetworksOfferAnswered && usableNetworks.count > 1
    }

    /// Each network's speed summed over the downloads running on more than one; empty when none is.
    var allNetworksSpeeds: [String: Double] {
        downloading.reduce(into: [:]) { sum, d in
            guard d.networkSpeeds.count > 1 else { return }
            sum.merge(d.networkSpeeds, uniquingKeysWith: +)
        }
    }

    /// The networks one download can use together. Metered ones count only where downloads
    /// may use metered networks: "Pause on Personal Hotspot" is off, or Download Anyway was chosen.
    var usableNetworks: [NetworkLink] {
        NetworkLink.usable(
            networks.links, vpn: networks.vpn, proxy: proxied,
            allowMetered: !settings.pauseOnExpensive || allowExpensiveNetwork)
    }

    private func networkChanged(id: String, expensive: Bool, lowData: Bool) {
        networkKnown = true
        onExpensiveNetwork = expensive
        onLowDataMode = lowData
        // A new network, or one no longer metered, starts fresh: the setting applies again,
        // whatever was allowed before.
        if id != networkID || !expensive {
            networkID = id
            allowExpensiveNetwork = false
            startedOnExpensive = []
        }
        if !expensive { resumePausedForNetwork() }
    }

    /// Back to the queue for what the badge's Pause All stopped.
    private func resumePausedForNetwork() {
        for i in items.indices where pausedForNetwork.contains(items[i].id) && items[i].status == .paused {
            items[i].status = .queued
        }
        pausedForNetwork = []
    }

    // MARK: - Derived state

    var visible: [Download] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = items.filter { filter.matches($0) && (q.isEmpty || $0.name.lowercased().contains(q) || $0.host.contains(q)) }
        // The Queued view lists items in the order they'll start.
        return filter == .queued ? matching.sorted { $0.queueOrder ?? 0 < $1.queueOrder ?? 0 } : matching
    }

    /// Queued downloads in the order they'll start.
    var queue: [Download] {
        items.filter { $0.status == .queued }.sorted { $0.queueOrder ?? 0 < $1.queueOrder ?? 0 }
    }

    /// 1-based place in the queue, for queued downloads.
    func queuePosition(_ id: UUID) -> Int? {
        queue.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    /// Another download already using this link, if any.
    func existing(url: URL) -> Download? {
        items.first { $0.url == url }
    }

    /// The file a new download named `name` would collide with, if one is already there.
    func existingFile(named name: String, in folder: SavedFolder?) -> URL? {
        let url = (folder?.url ?? settings.folder(for: .of(name))).appending(path: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func count(_ f: SidebarFilter) -> Int { items.filter(f.matches).count }

    var downloading: [Download] { items.filter { $0.status == .downloading } }
    var totalSpeed: Double { downloading.reduce(0) { $0 + $1.speed } }

    /// Byte-weighted progress across everything currently downloading.
    var overallProgress: Double {
        let known = downloading.filter { ($0.size ?? 0) > 0 }
        let total = known.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
        guard total > 0 else { return 0 }
        return Double(known.reduce(Int64(0)) { $0 + $1.received }) / Double(total)
    }

    var subtitle: String {
        let n = downloading.count
        if n > 0 { return "\(n) downloading · \(formatBytes(totalSpeed))/s" }
        let queued = items.filter { $0.status == .queued }.count
        if queued > 0 && waitingForNetwork { return "\(queued) queued · waiting for an unmetered network" }
        if queued > 0 && settings.scheduleOnly && !inScheduleWindow {
            return "\(queued) queued · starts at \(AppSettings.hourLabel(settings.scheduleFrom))"
        }
        return "\(queued) queued · idle"
    }

    var selected: Download? { items.first { $0.id == selection } }

    private func index(_ id: UUID) -> Int? { items.firstIndex { $0.id == id } }

    private var inScheduleWindow: Bool { settings.inSchedule(hour: Calendar.current.component(.hour, from: .now)) }

    // MARK: - Actions

    /// How a new download begins: `.now` goes to the front of the queue (it still waits for a
    /// free slot), `.queued` to the back, and `.paused` waits until it's started by hand.
    enum Start { case now, queued, paused }

    /// `folder` is a folder picked for this download; nil saves to the default folder. `extract`
    /// unpacks the file when it's done, if it turns out to be an archive Haul can extract, and
    /// `whenDone` then opens or shows the file (or what was extracted). `reveal` selects it in
    /// the list, clearing any search or filter; not for downloads added from another device.
    func add(
        url: URL, probe: Probe.Info?, connections: Int, start: Start, folder: SavedFolder? = nil, replaceExisting: Bool = false,
        extract: Bool = false, whenDone: WhenDone = .nothing, reveal: Bool = true
    ) {
        var d = Download(
            url: url, name: probe?.name ?? url.lastPathComponent, size: nil,
            status: start == .paused ? .paused : .queued, connections: connections)
        if let probe { d.apply(probe) }
        d.queueOrder = start == .now ? queueStart : queueEnd
        if replaceExisting { d.replaceExisting = true }
        if extract { d.extract = true }
        if whenDone != .nothing { d.whenDone = whenDone }
        d.browser = browserContexts.removeValue(forKey: url)
        if let folder {
            d.folderBookmark = folder.bookmark
            d.folderName = folder.url.lastPathComponent
            settings.rememberRecent(folder)
        }
        items.insert(d, at: 0)
        if reveal {
            selection = d.id
            filter = .all
            query = ""
        }
        dirty = true
        if settings.notifyAdded { Notifier.added(d) }
        if start == .now { schedule() }
    }

    /// The row/inspector primary action: pause, resume, start now or retry.
    func toggle(_ id: UUID) {
        guard let d = items.first(where: { $0.id == id }) else { return }
        switch d.status {
        case .downloading: pause(id)
        case .failed where d.issue == .signIn:
            signIn(id)
        case .paused, .queued, .failed:
            if let i = index(id) {
                items[i].retries = 0
                items[i].retryAt = nil
            }
            beginByHand(id)
        case .completed: break
        }
    }

    /// Starts `id` because the user asked to, so it keeps going while waiting for the network.
    private func beginByHand(_ id: UUID) {
        if waitingForNetwork { startedOnExpensive.insert(id) }
        pausedForNetwork.remove(id)
        begin(id)
    }

    func pause(_ id: UUID) {
        guard let i = index(id) else { return }
        stopEngine(at: i)
        items[i].status = .paused
        pausedForNetwork.remove(id)
    }

    /// Lets downloads run on Personal Hotspot or Low Data Mode until the network changes, and
    /// resumes the ones the badge's Pause All stopped.
    func downloadAnyway() {
        allowExpensiveNetwork = true
        resumeForNetwork()
    }

    /// Resumes what the badge's Pause All stopped, for when nothing holds downloads back.
    func resumeForNetwork() {
        resumePausedForNetwork()
        schedule()
    }

    /// Downloads paused from the badge, still paused.
    var hasPausedForNetwork: Bool { items.contains { $0.status == .paused && pausedForNetwork.contains($0.id) } }

    /// The badge's Pause All: like Pause All, but what it stops resumes on an unmetered network,
    /// and Download Anyway is undone.
    func pauseForNetwork() {
        let stopping = items.filter { $0.status == .downloading || $0.status == .queued }.map(\.id)
        pauseAll()
        pausedForNetwork.formUnion(stopping)
        allowExpensiveNetwork = false
        startedOnExpensive = []
    }

    func pauseAll() {
        for d in items where d.status == .downloading || d.status == .queued { pause(d.id) }
        // Pending automatic retries would start things up again.
        for i in items.indices where items[i].retryAt != nil { items[i].retryAt = nil }
    }

    /// Resumed items go through the queue so the simultaneous-download limit still applies.
    func resumeAll() {
        for i in items.indices where items[i].status == .paused || items[i].status == .failed {
            items[i].status = .queued
            items[i].error = nil
            items[i].retries = 0
            items[i].retryAt = nil
        }
        pausedForNetwork = []
        schedule()
    }

    /// `trashFile` also moves a finished download's file to the Trash.
    func remove(_ id: UUID, trashFile: Bool = false) {
        guard let i = index(id) else { return }
        pausedForNetwork.remove(id)
        if trashFile, items[i].status == .completed, let file = items[i].fileURL {
            _ = destinationFolder(for: items[i])  // makes sure a picked folder's sandbox access is active
            do {
                try FileManager.default.trashItem(at: file, resultingItemURL: nil)
            } catch  where FileManager.default.fileExists(atPath: file.path) {
                // Keep the entry so the file can still be found from the list.
                let alert = NSAlert()
                alert.messageText = "Couldn't move “\(items[i].name)” to the Trash"
                alert.informativeText = "\(error.localizedDescription) It's still in the list."
                NSApp.activate()
                alert.runModal()
                return
            } catch {}  // Already gone, so there's nothing left to trash.
            extractionJobs[id]?.stop()  // nothing to unpack once the archive is in the Trash
        }
        stopEngine(at: i)
        if items[i].status != .completed { try? FileManager.default.removeItem(at: partURL(id)) }
        items.remove(at: i)
        if selection == id { selection = items.indices.contains(i) ? items[i].id : items.last?.id }
        dirty = true
    }

    // MARK: - Queue order

    private var queueStart: Double { (items.compactMap(\.queueOrder).min() ?? 1) - 1 }
    private var queueEnd: Double { (items.compactMap(\.queueOrder).max() ?? -1) + 1 }

    /// Makes a queued download the next one to start.
    func startNext(_ id: UUID) {
        guard let i = index(id) else { return }
        items[i].queueOrder = queueStart
        dirty = true
    }

    /// Sends a queued download to the back of the queue.
    func moveToEnd(_ id: UUID) {
        guard let i = index(id) else { return }
        items[i].queueOrder = queueEnd
        dirty = true
    }

    /// Moves `id` to `target`'s place in the queue (dragging a row onto another).
    func moveInQueue(_ id: UUID, to target: UUID) {
        guard id != target else { return }
        var order = items.filter { $0.queueOrder != nil }.sorted { $0.queueOrder! < $1.queueOrder! }.map(\.id)
        guard let from = order.firstIndex(of: id), let to = order.firstIndex(of: target) else { return }
        order.remove(at: from)
        order.insert(id, at: to)
        for (n, itemID) in order.enumerated() {
            if let i = index(itemID) { items[i].queueOrder = Double(n) }
        }
        dirty = true
    }

    /// Renames a download. Unfinished downloads just take the new name when they're saved;
    /// finished ones are renamed on disk. Returns an error message to show, or nil on success.
    @discardableResult
    func rename(_ id: UUID, to proposed: String) -> String? {
        guard let i = index(id) else { return nil }
        let name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Name can't be empty." }
        if name.contains("/") || name.contains(":") { return "Names can't contain “/” or “:”." }
        if name == "." || name == ".." { return "That name is reserved." }
        if name == items[i].name { return nil }

        if items[i].status == .completed, let old = items[i].fileURL, FileManager.default.fileExists(atPath: old.path) {
            _ = destinationFolder(for: items[i])  // makes sure a picked folder's sandbox access is active
            let new = old.deletingLastPathComponent().appending(path: name)
            // Allow case-only renames (same file on a case-insensitive volume).
            if FileManager.default.fileExists(atPath: new.path) && name.lowercased() != items[i].name.lowercased() {
                return "“\(name)” already exists in \(new.deletingLastPathComponent().lastPathComponent)."
            }
            do {
                try FileManager.default.moveItem(at: old, to: new)
            } catch {
                return "Couldn't rename: \(error.localizedDescription)"
            }
            items[i].fileURL = new
        }
        items[i].name = name
        items[i].renamed = true
        // "Replace" was chosen for the old name; don't let it apply to a different file.
        items[i].replaceExisting = nil
        dirty = true
        return nil
    }

    /// Selects a download and asks the inspector to start editing its name.
    func beginRename(_ id: UUID) {
        selection = id
        renaming = id
    }

    // MARK: - Updating the link

    func beginUpdateLink(_ id: UUID) {
        selection = id
        updatingLink = id
        showMainWindow()
    }

    enum LinkCheck {
        /// Same size and resumable: progress is kept.
        case resumable(warning: String?)
        /// Can be used, but only by starting over.
        case restartOnly(reason: String)
    }

    /// Decides whether `info` (the probe of a new link) can continue download `id`.
    func checkNewLink(_ id: UUID, _ info: Probe.Info) -> LinkCheck {
        guard let d = items.first(where: { $0.id == id }) else { return .restartOnly(reason: "Download not found.") }
        if d.received == 0 { return .resumable(warning: nil) }
        guard info.acceptsRanges else {
            return .restartOnly(reason: "This server can't resume, so the download would start over.")
        }
        if let old = d.size, let new = info.size, old != new {
            return .restartOnly(reason: "Size differs (\(formatBytes(new)) vs \(formatBytes(old))), so this looks like a different file.")
        }
        if d.size != nil && info.size == nil {
            return .restartOnly(reason: "The server didn't report a size, so it can't be confirmed as the same file.")
        }
        // A fresh signed link is often served by a different mirror with its own ETag, so this is only a warning.
        if let old = d.etag, let new = info.etag, old != new {
            return .resumable(warning: "Size matches, but the server's file tag differs. If the finished file is corrupt, restart it.")
        }
        return .resumable(warning: nil)
    }

    /// Points download `id` at a new link. With `restart`, discards progress and starts over;
    /// otherwise keeps the partial file and resumes. The caller has already probed the link.
    func applyNewLink(_ id: UUID, url: URL, info: Probe.Info, restart: Bool) {
        guard let i = index(id) else { return }
        stopEngine(at: i)
        items[i].url = url
        items[i].etag = info.etag
        items[i].lastModified = info.lastModified
        items[i].error = nil
        items[i].issue = nil
        if restart || items[i].received == 0 {
            try? FileManager.default.removeItem(at: partURL(id))
            items[i].apply(info)
        } else {
            items[i].resumable = true
        }
        items[i].status = .paused
        dirty = true
        beginByHand(id)
    }

    /// Discards the partial file and downloads again from the start.
    func restart(_ id: UUID) {
        guard let i = index(id) else { return }
        stopEngine(at: i)
        try? FileManager.default.removeItem(at: partURL(id))
        items[i].segments = []
        items[i].error = nil
        items[i].issue = nil
        items[i].status = .paused
        dirty = true
        beginByHand(id)
    }

    /// Asks for the username and password the server wants, then tries again.
    func signIn(_ id: UUID) {
        guard let d = items.first(where: { $0.id == id }),
            SignIn.prompt(for: d.url, realm: d.authRealm, digest: d.authDigest ?? false),
            let i = index(id)
        else { return }
        items[i].retries = 0
        items[i].retryAt = nil
        beginByHand(id)
    }

    /// Asks first (unless turned off in Settings), then removes.
    func requestRemove(_ id: UUID) {
        guard let d = items.first(where: { $0.id == id }) else { return }
        if d.status == .completed { _ = destinationFolder(for: d) }  // makes sure a picked folder's sandbox access is active
        let hasFile = d.status == .completed && d.fileURL.map { FileManager.default.fileExists(atPath: $0.path) } == true
        let detail =
            hasFile
            ? "Removes it from the list. The file is in \(destinationLabel(for: d))."
            : d.status == .completed
                ? "Removes it from the list."
                : "What's been downloaded so far will be deleted."
        // Without the dialog (confirmation off) the file is always kept.
        let asked = settings.confirmRemove
        let (confirmed, trash) = confirm(
            "Remove “\(d.name)”?", detail, button: "Remove",
            checkbox: hasFile ? "Also move the file to the Trash" : nil,
            checked: settings.trashOnRemove)
        guard confirmed else { return }
        if hasFile && asked { settings.trashOnRemove = trash }
        remove(id, trashFile: trash)
    }

    func requestClearCompleted() {
        let n = count(.completed)
        guard n > 0 else { return }
        if confirm(
            "Clear \(n) completed download\(n == 1 ? "" : "s")?", "They're removed from the list. The files stay where they are.",
            button: "Clear")
        {
            clearCompleted()
        }
    }

    /// A standalone alert rather than a sheet: sheets on Haul's title-bar-less windows make
    /// AppKit restore the title bar.
    private func confirm(_ title: String, _ detail: String, button: String) -> Bool {
        confirm(title, detail, button: button, checkbox: nil).confirmed
    }

    /// `checkbox` adds an option that starts in the `checked` state; the result's `checked` is whether it ended up on.
    private func confirm(_ title: String, _ detail: String, button: String, checkbox: String?, checked: Bool = false) -> (
        confirmed: Bool, checked: Bool
    ) {
        guard settings.confirmRemove else { return (true, false) }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: button).hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        let option = checkbox.map { NSButton(checkboxWithTitle: $0, target: nil, action: nil) }
        if let option {
            option.state = checked ? .on : .off
            option.sizeToFit()
            let container = OverhangView(frame: option.frame)
            container.addSubview(option)
            alert.accessoryView = container
            // NSAlert insets the accessory view; line the checkbox up with "Don't ask again".
            alert.layout()
            if let suppression = alert.suppressionButton {
                let dx = suppression.convert(suppression.bounds, to: nil).minX - option.convert(option.bounds, to: nil).minX
                option.frame.origin.x += dx
            }
        }
        NSApp.activate()
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        if confirmed && alert.suppressionButton?.state == .on { settings.confirmRemove = false }
        return (confirmed, confirmed && option?.state == .on)
    }

    func clearCompleted() {
        items.removeAll { $0.status == .completed }
        dirty = true
    }

    /// Opens a finished download. Archives that would go to Archive Utility are unpacked by Haul
    /// instead: launched from the sandbox, Archive Utility can't write beside the archive and
    /// unpacks into ~/Downloads. Like Archive Utility, the result is shown, not opened.
    func open(_ download: Download) {
        // The live item: a view's copy may predate an extraction that has since finished.
        let d = index(download.id).map { items[$0] } ?? download
        guard let url = d.fileURL else { return }
        _ = destinationFolder(for: d)  // makes sure a picked folder's sandbox access is active
        let fm = FileManager.default
        guard Extractor.canExtract(url.lastPathComponent), fm.fileExists(atPath: url.path),
            NSWorkspace.shared.urlForApplication(toOpen: url).flatMap({ Bundle(url: $0)?.bundleIdentifier })
                == "com.apple.archiveutility"
        else {
            NSWorkspace.shared.open(url)
            return
        }
        if let extracted = d.extractedURL, fm.fileExists(atPath: extracted.path) {
            Self.perform(.reveal, on: extracted)
        } else if d.extractError != nil {
            // Haul couldn't unpack it before, e.g. password-protected; Archive Utility still can.
            NSWorkspace.shared.open(url)
        } else if !d.extracting {
            extract(d.id, url, then: .reveal, openOnFailure: true)
        }
    }

    func revealInFinder(_ d: Download) {
        if let url = d.fileURL, FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(destinationFolder(for: d))
        }
    }

    /// Where a download is (or will be) saved: its own picked folder, else the default for its kind.
    func destinationFolder(for d: Download) -> URL {
        if let data = d.folderBookmark, let folder = SavedFolder(bookmark: data) { return folder.url }
        return settings.folder(for: d.kind)
    }

    /// Short label for the destination, e.g. "Downloads/Movies" or "Films".
    func destinationLabel(for d: Download) -> String {
        if let parent = d.fileURL?.deletingLastPathComponent() {
            let components = parent.pathComponents.suffix(2)
            // Show the kind subfolder with its parent ("Downloads/Movies"), otherwise just the folder.
            return components.count == 2 && FileKind.allCases.contains { $0.folder == components.last }
                ? components.joined(separator: "/") : parent.lastPathComponent
        }
        return d.folderName ?? settings.folderLabel(for: d.kind)
    }

    func reveal(_ id: UUID) {
        filter = .all
        query = ""
        selection = id
        showMainWindow()
    }

    func showMainWindow() {
        DockIcon.show()
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }

    func requestAdd() {
        showAdd = true
        showMainWindow()
    }

    /// Opens the Add panel with `links` filled in, for the user to confirm.
    func requestAdd(_ links: [URL], browser: BrowserContext? = nil) {
        if let browser { for link in links { browserContexts[link] = browser } }
        incomingLinks += links
        updatingLink = nil
        requestAdd()
    }

    // MARK: - Engine lifecycle

    private func begin(_ id: UUID) {
        guard let i = index(id), engines[id] == nil, probing[id] == nil else { return }
        items[i].status = .downloading
        items[i].startedAt = .now
        items[i].error = nil
        items[i].issue = nil
        items[i].speed = 0
        samples[id] = nil

        let d = items[i]
        // Fresh downloads, and ones whose server can't resume, need (re)probing first.
        guard d.segments.isEmpty || (!d.resumable && d.received > 0) else { return launchEngine(id) }
        let token = UUID()
        probing[id] = token
        Task {
            // A pause and resume while probing starts a new probe; only the latest one may act.
            defer { if probing[id] == token { probing[id] = nil } }
            do {
                let info = try await Probe.run(d.url, browser: d.browser)
                guard probing[id] == token, let j = index(id), items[j].status == .downloading else { return }
                if info.isWebPage && settings.skipWebPages { return fail(j, DownloadError.webPage) }
                items[j].apply(info)
                try? FileManager.default.removeItem(at: partURL(id))
                launchEngine(id)
            } catch {
                guard probing[id] == token, let j = index(id), items[j].status == .downloading else { return }
                fail(j, error)
            }
        }
    }

    private func launchEngine(_ id: UUID) {
        guard let i = index(id) else { return }
        let d = items[i]
        if let shortfall = diskShortfall(for: d) { return fail(i, DownloadError.diskFull(shortfall)) }
        // A proxy turned on since the last tick must not be gone around.
        if settings.useAllNetworks { refreshProxied() }
        let routes = routes(for: d)
        let engine = SegmentedDownloader(
            url: d.url, partURL: partURL(id), segments: d.segments, connections: d.connectionLimit,
            etag: d.etag, lastModified: d.lastModified, routes: routes,
            browser: d.browser, limiter: limiter
        ) { result in
            Task { @MainActor in DownloadStore.shared.engineFinished(id, result) }
        }
        engines[id] = engine
        engineRoutes[id] = routes
        engineAllNetworks[id] = settings.useAllNetworks
        engine.start()
    }

    /// Only Multi-network downloads and its offer depend on it.
    private func refreshProxied() {
        let proxied = ProxySettings.current.goesThroughProxy
        if proxied != self.proxied { self.proxied = proxied }
    }

    private func routes(for d: Download) -> [Route] {
        Self.routes(
            usableNetworks, primary: networks.primary, enabled: settings.useAllNetworks,
            connections: d.connectionLimit, resumable: d.resumable, signIn: d.authRealm != nil)
    }

    /// The networks a download's connections go over: with "Multi-network downloads" on, every usable
    /// network, the default one through URLSession and the others pinned; otherwise just the default.
    /// Only resumable downloads split across networks, and not ones that need a sign-in, which
    /// only URLSession can answer.
    nonisolated static func routes(
        _ links: [NetworkLink], primary: String?, enabled: Bool,
        connections: Int, resumable: Bool, signIn: Bool
    ) -> [Route] {
        let links = links.filter { $0.interface != nil }
        guard enabled, links.count > 1, connections > 1, resumable, !signIn else { return [.standard] }
        return links.map { $0.name == primary ? Route(interface: nil, name: $0.name) : Route(interface: $0.interface, name: $0.name) }
    }

    /// Restarts running downloads whose networks have changed: a VPN came on, a network left or
    /// joined, or the setting changed. Progress carries over; only the connections start again.
    private func applyNetworkChanges(_ now: Date) {
        for i in items.indices where items[i].status == .downloading {
            let id = items[i].id
            guard let old = engineRoutes[id], engines[id] != nil else { continue }
            let wanted = routes(for: items[i])
            let waiting = newRoutes[id].flatMap { $0.routes == wanted ? $0.since : nil }
            switch Self.networkChange(
                from: old, to: wanted, waitingSince: waiting, now: now,
                byUser: engineAllNetworks[id] != settings.useAllNetworks)
            {
            case .none:
                newRoutes[id] = nil
                // The setting may have changed without changing this download's networks.
                engineAllNetworks[id] = settings.useAllNetworks
            case .waiting(let since):
                newRoutes[id] = (wanted, since)
            case .restart:
                stopEngine(at: i)
                launchEngine(id)
            }
        }
    }

    enum NetworkChange: Equatable {
        case none
        /// The new networks have been wanted since then; not long enough yet.
        case waiting(since: Date)
        case restart
    }

    /// What to do about a running download whose networks would now be `wanted` rather than `old`.
    /// A network to stop using is dropped at once, so nothing more goes around a VPN that just came on,
    /// and so is the setting being changed; a network to start using must first stay for `networkSettle`,
    /// so one that keeps dropping out and coming back doesn't restart downloads over and over.
    nonisolated static func networkChange(
        from old: [Route], to wanted: [Route], waitingSince: Date?, now: Date,
        byUser: Bool
    ) -> NetworkChange {
        guard wanted != old else { return .none }
        if byUser || old.contains(where: { $0.interface != nil && !wanted.contains($0) }) { return .restart }
        guard let since = waitingSince else { return .waiting(since: now) }
        return now.timeIntervalSince(since) >= networkSettle ? .restart : .waiting(since: since)
    }

    /// Whether what's saved can be continued after `error`. Not when the partial file is missing bytes,
    /// or the server can't send the rest of it: retrying those same parts would fail the same way.
    nonisolated static func canContinue(after error: Error) -> Bool {
        switch error as? DownloadError {
        case .incomplete, .noRangeSupport: false
        default: true
        }
    }

    private func fail(_ i: Int, _ error: Error) {
        items[i].status = .failed
        items[i].error = error.localizedDescription
        items[i].speed = 0
        switch error as? DownloadError {
        case .linkExpired: items[i].issue = .linkExpired
        case .fileChanged: items[i].issue = .fileChanged
        case .signInRequired(let realm, let digest):
            items[i].issue = .signIn
            items[i].authRealm = realm
            items[i].authDigest = digest
        default: items[i].issue = nil
        }
        // Retry then probes again and starts from the beginning.
        if !Self.canContinue(after: error) { items[i].segments = [] }
        if settings.autoRetry && DownloadError.isTransient(error) && items[i].retries < Self.maxRetries {
            items[i].retryAt = .now + Self.retryDelays[items[i].retries]
            items[i].retries += 1
        } else {
            items[i].retryAt = nil
            if settings.notifyFailed { Notifier.failed(items[i]) }
        }
        dirty = true
    }

    private func stopEngine(at i: Int) {
        let id = items[i].id
        if let engine = engines.removeValue(forKey: id) {
            engine.cancel()
            items[i].segments = engine.snapshot()
        }
        probing[id] = nil
        engineRoutes[id] = nil
        engineAllNetworks[id] = nil
        newRoutes[id] = nil
        networkSamples[id] = nil
        items[i].speed = 0
        items[i].liveConnections = 0
        items[i].writingAt = []
        items[i].networkSpeeds = [:]
        dirty = true
    }

    private func engineFinished(_ id: UUID, _ result: Result<Void, Error>) {
        guard let engine = engines.removeValue(forKey: id), let i = index(id) else { return }
        engineRoutes[id] = nil
        engineAllNetworks[id] = nil
        newRoutes[id] = nil
        networkSamples[id] = nil
        items[i].segments = engine.snapshot()
        items[i].speed = 0
        items[i].liveConnections = 0
        items[i].writingAt = []
        items[i].networkSpeeds = [:]
        dirty = true
        switch result {
        case .failure(let error):
            fail(i, error)
        case .success:
            complete(at: i)
        }
    }

    private func complete(at i: Int) {
        let d = items[i]
        do {
            let folder = destinationFolder(for: d)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appending(path: d.name)
            let exists = FileManager.default.fileExists(atPath: target.path)
            // Save alongside an existing file first, so if replacing goes wrong both are still there.
            var dest = exists ? uniqueURL(in: folder, name: d.name) : target
            try FileManager.default.moveItem(at: partURL(d.id), to: dest)
            if exists && d.replaceExisting == true { dest = Self.swapIn(dest, for: target) }
            if settings.useServerDate, let date = d.lastModified.flatMap(Self.httpDate.date(from:)) {
                try? FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: dest.path)
            }
            if settings.recordSource { recordSource(of: dest, url: d.url) }
            items[i].fileURL = dest
            items[i].browser = nil
            items[i].name = dest.lastPathComponent
        } catch {
            items[i].status = .failed
            items[i].error = "Couldn't save file: \(error.localizedDescription)"
            if settings.notifyFailed { Notifier.failed(items[i]) }
            return
        }
        items[i].status = .completed
        items[i].finished = .now
        if items[i].size == nil { items[i].size = items[i].received }

        if settings.computeChecksum, let url = items[i].fileURL {
            let id = d.id
            Task.detached(priority: .utility) {
                let digest = sha256(of: url)
                await MainActor.run {
                    if let j = DownloadStore.shared.items.firstIndex(where: { $0.id == id }) {
                        DownloadStore.shared.items[j].sha256 = digest
                        DownloadStore.shared.dirty = true
                    }
                }
            }
        }
        // With extracting, "When done" waits for it, so it never lands on a half-unpacked folder.
        if d.extract == true, let url = items[i].fileURL, Extractor.canExtract(url.lastPathComponent) {
            extract(d.id, url, then: d.whenDone ?? .nothing)
        } else if let url = items[i].fileURL {
            Self.perform(d.whenDone ?? .nothing, on: url)
        }
        if settings.notify { Notifier.finished(items[i], folder: destinationLabel(for: items[i])) }
        NSApp.requestUserAttention(.informationalRequest)
        if settings.removeFinished == .whenFinished { remove(d.id) }
    }

    /// Unpacks a finished archive next to it, in the background, then carries out `whenDone`.
    /// `openOnFailure` hands the archive to its default app if Haul can't unpack it.
    private func extract(_ id: UUID, _ archive: URL, then whenDone: WhenDone, openOnFailure: Bool = false) {
        guard let i = index(id), extractionJobs[id] == nil else { return }
        _ = destinationFolder(for: items[i])  // makes sure a picked folder's sandbox access is active
        items[i].extracting = true
        let job = Extractor.Job()
        extractionJobs[id] = job
        extractions.append(Extraction(download: items[i]))
        ExtractionPanel.shared.show()
        followExtractions()
        Task.detached(priority: .utility) {
            let result = Result { try Extractor.extract(archive, job: job) }
            await MainActor.run {
                DownloadStore.shared.extractionFinished(id, result, archive: archive, then: whenDone, openOnFailure: openOnFailure)
            }
        }
    }

    /// Ends extractions when Haul quits, so no tool keeps running or leaves a hidden folder behind.
    func abandonExtractions() {
        for job in extractionJobs.values { job.abandon() }
    }

    /// Stops an extraction from the extraction window; what was unpacked so far is discarded.
    func stopExtraction(_ id: UUID) {
        extractionJobs[id]?.stop()
    }

    /// Updates the extraction window's progress while anything is being extracted.
    private func followExtractions() {
        guard extractionPolling == nil else { return }
        extractionPolling = Task {
            while !extractions.isEmpty {
                for k in extractions.indices {
                    let fraction = extractionJobs[extractions[k].id]?.fraction
                    if fraction != extractions[k].fraction { extractions[k].fraction = fraction }
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            extractionPolling = nil
        }
    }

    private func extractionFinished(
        _ id: UUID, _ result: Result<URL, Error>, archive: URL, then whenDone: WhenDone, openOnFailure: Bool
    ) {
        extractionJobs[id] = nil
        extractions.removeAll { $0.id == id }
        if extractions.isEmpty { ExtractionPanel.shared.close() }
        if case .failure(let error) = result, error is CancellationError {
            // Stopped by hand: nothing to show, open or report.
            if let i = index(id) { items[i].extracting = false }
            dirty = true
            return
        }
        // Done even if the download has left the list meanwhile ("Remove When Finished").
        switch result {
        case .success(let url): Self.perform(whenDone, on: url)
        // Opening the archive would only unpack it again; showing it still finds the download.
        case .failure where openOnFailure: NSWorkspace.shared.open(archive)
        case .failure: if whenDone == .reveal { Self.perform(.reveal, on: archive) }
        }
        guard let i = index(id) else { return }
        items[i].extracting = false
        switch result {
        case .success(let url):
            items[i].extractedURL = url
            items[i].extractError = nil
        case .failure(let error):
            items[i].extractedURL = nil
            items[i].extractError = error.localizedDescription
            // With `openOnFailure` the archive has opened in its app instead; that's not a failure to report.
            if settings.notifyFailed && !openOnFailure { Notifier.extractFailed(items[i]) }
        }
        dirty = true
    }

    /// Carries out a "When done" choice on a finished file, or what was extracted from it.
    private static func perform(_ whenDone: WhenDone, on url: URL) {
        switch whenDone {
        case .nothing: break
        case .open: NSWorkspace.shared.open(url)
        case .reveal: NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// Parses an HTTP date such as "Wed, 21 Oct 2015 07:28:00 GMT".
    private static let httpDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    /// Saves the link as the file's "Where from" and in its quarantine record, which macOS
    /// shows when an app from it is first opened. (The sandbox quarantines every file Haul
    /// writes regardless; this only adds where it came from.)
    private func recordSource(of file: URL, url: URL) {
        if let data = try? PropertyListSerialization.data(fromPropertyList: [url.absoluteString], format: .binary, options: 0) {
            _ = data.withUnsafeBytes { setxattr(file.path, "com.apple.metadata:kMDItemWhereFroms", $0.baseAddress, data.count, 0, 0) }
        }
        var values = URLResourceValues()
        values.quarantineProperties = [
            kLSQuarantineAgentNameKey as String: "Haul",
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
            kLSQuarantineDataURLKey as String: url,
        ]
        var file = file
        try? file.setResourceValues(values)
    }

    private func uniqueURL(in folder: URL, name: String) -> URL {
        var url = folder.appending(path: name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appending(path: ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    /// Sends `old` to the Trash (rather than deleting it, in case replacing was a mistake) and moves
    /// `new` into its place. Returns where the new file ended up; if any step fails, both files are kept.
    static func swapIn(
        _ new: URL, for old: URL,
        trash: (URL) throws -> URL? = { url in
            var trashed: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
            return trashed as URL?
        }
    ) -> URL {
        let trashed: URL?
        do { trashed = try trash(old) } catch { return new }
        if (try? FileManager.default.moveItem(at: new, to: old)) != nil { return old }
        if let trashed { try? FileManager.default.moveItem(at: trashed, to: old) }
        return new
    }

    private func partURL(_ id: UUID) -> URL { Self.partialsFolder.appending(path: "\(id.uuidString).part") }

    // MARK: - Tick: progress sampling, queue, dock

    private func tick() {
        limiter.setRate(settings.limitOn ? Double(settings.limitMBps) * 1024 * 1024 : 0)
        let now = Date()
        for i in items.indices where items[i].status == .downloading {
            let id = items[i].id
            guard let engine = engines[id] else { continue }
            items[i].segments = engine.snapshot()
            let state = engine.connectionState()
            (items[i].liveConnections, items[i].serverLimit, items[i].writingAt) = (state.live, state.serverLimit, state.writingAt)
            items[i].networkSpeeds = networkSpeeds(id, state.byRoute, now)
            let bytes = items[i].received
            var window = samples[id, default: []]
            window.append((bytes, now))
            window.removeAll { now.timeIntervalSince($0.at) > Self.speedWindow }
            samples[id] = window
            if let oldest = window.first, now.timeIntervalSince(oldest.at) >= 0.4 {
                items[i].speed = Double(bytes - oldest.bytes) / now.timeIntervalSince(oldest.at)
            }
            // Getting data again earns back the full set of automatic retries.
            if items[i].speed > 0 && items[i].retries > 0 { items[i].retries = 0 }
            dirty = true
        }
        if settings.useAllNetworks || !settings.allNetworksOfferAnswered { refreshProxied() }
        applyNetworkChanges(now)
        checkDiskSpace(now)
        retryDue(now)
        schedule()
        updateSleepPrevention()
        cleanUpList(now)
        // The badge shows overall progress; when no size is known yet, how many are downloading.
        let sized = downloading.contains { ($0.size ?? 0) > 0 }
        dock.update(
            progress: settings.dockProgress && !downloading.isEmpty ? overallProgress : nil,
            badge: sized ? "\(Int(overallProgress * 100))%" : "\(downloading.count)")
        if dirty { save() }
    }

    /// Each network's speed over the same window as the download's, once it uses more than one.
    private func networkSpeeds(_ id: UUID, _ bytes: [String: Int64], _ now: Date) -> [String: Double] {
        guard bytes.count > 1 else { return [:] }
        var window = networkSamples[id, default: []]
        window.append((bytes, now))
        window.removeAll { now.timeIntervalSince($0.at) > Self.speedWindow }
        networkSamples[id] = window
        guard let oldest = window.first, now.timeIntervalSince(oldest.at) >= 0.4 else { return [:] }
        let seconds = now.timeIntervalSince(oldest.at)
        // The default route's bytes are filed under the network it goes over.
        let primary = networks.primary ?? ""
        return Dictionary(
            bytes.map { ($0.key.isEmpty ? primary : $0.key, Double($0.value - (oldest.bytes[$0.key] ?? 0)) / seconds) },
            uniquingKeysWith: +)
    }

    private func schedule() {
        guard networkKnown else { return }
        if waitingForNetwork {
            // Back to the queue so they pick up again once we're on an unmetered network.
            for i in items.indices where items[i].status == .downloading && !startedOnExpensive.contains(items[i].id) {
                stopEngine(at: i)
                items[i].status = .queued
            }
            // Ones started by hand keep going, automatic retries included.
            var active = items.filter { $0.status == .downloading }.count
            for d in queue where startedOnExpensive.contains(d.id) && active < settings.maxConcurrent {
                begin(d.id)
                active += 1
            }
            return
        }
        // A lowered limit sends the most recently started downloads back to the front of the
        // queue. Only on a change, so "Start Now" can still run something beyond the limit.
        if let last = appliedLimit, settings.maxConcurrent < last {
            let running = items.filter { $0.status == .downloading }
                .sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
            // Newest first; each goes in front of the previous, so they resume oldest-first.
            for d in running.prefix(max(0, running.count - settings.maxConcurrent)) {
                guard let i = index(d.id) else { continue }
                stopEngine(at: i)
                items[i].status = .queued
                items[i].queueOrder = queueStart
            }
        }
        appliedLimit = settings.maxConcurrent

        if settings.scheduleOnly && !inScheduleWindow { return }
        var active = items.filter { $0.status == .downloading }.count
        for d in queue where active < settings.maxConcurrent {
            begin(d.id)
            active += 1
        }
    }

    // MARK: - Disk space

    /// Room always left free, so a download never fills the disk.
    private static let diskReserve: Int64 = 1024 * 1024 * 1024
    @ObservationIgnored private var lastDiskCheck = Date.distantPast

    private static func freeSpace(at url: URL) -> Int64? {
        // The folder may not exist yet (a kind subfolder): use its nearest existing parent.
        var url = url
        while !FileManager.default.fileExists(atPath: url.path), url.pathComponents.count > 1 { url.deleteLastPathComponent() }
        return try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }

    private static func volume(of url: URL) -> NSObject? {
        var url = url
        while !FileManager.default.fileExists(atPath: url.path), url.pathComponents.count > 1 { url.deleteLastPathComponent() }
        return (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
    }

    /// Why `d` can't start for lack of space, or nil if it fits. The partial file grows in
    /// Haul's own folder; a destination on another disk also needs room for the whole file.
    private func diskShortfall(for d: Download) -> String? {
        guard let size = d.size else { return nil }
        let partials = Self.partialsFolder
        let destination = destinationFolder(for: d)
        var needs: [(URL, Int64)] = [(partials, size - d.received)]
        if let a = Self.volume(of: partials), let b = Self.volume(of: destination), a != b { needs.append((destination, size)) }
        for (folder, bytes) in needs {
            guard let free = Self.freeSpace(at: folder), free - bytes < Self.diskReserve else { continue }
            return "Not enough disk space: needs \(formatBytes(bytes)), \(formatBytes(max(0, free))) free"
        }
        return nil
    }

    /// Stops everything when the disk is nearly full (sizes the server didn't report, or
    /// other apps filling the disk).
    private func checkDiskSpace(_ now: Date) {
        guard now.timeIntervalSince(lastDiskCheck) >= 5, !downloading.isEmpty else { return }
        lastDiskCheck = now
        guard let free = Self.freeSpace(at: Self.partialsFolder), free < Self.diskReserve else { return }
        for i in items.indices where items[i].status == .downloading {
            stopEngine(at: i)
            fail(i, DownloadError.diskFull("Stopped: the disk is almost full (\(formatBytes(max(0, free))) free)"))
        }
    }

    /// Failed downloads whose automatic retry is due go back in the queue (so the
    /// simultaneous-download limit still applies).
    private func retryDue(_ now: Date) {
        for i in items.indices where items[i].status == .failed {
            guard let at = items[i].retryAt else { continue }
            // Retrying was turned off while this one waited: it has failed for good, so say so now.
            if !settings.autoRetry {
                items[i].retryAt = nil
                if settings.notifyFailed { Notifier.failed(items[i]) }
                dirty = true
                continue
            }
            guard at <= now else { continue }
            items[i].retryAt = nil
            items[i].status = .queued
            items[i].error = nil
            items[i].issue = nil
            dirty = true
        }
    }

    /// Removes finished downloads that are past the keep time, or whose file was deleted.
    private func cleanUpList(_ now: Date) {
        guard now.timeIntervalSince(lastCleanup) >= 5 else { return }
        lastCleanup = now
        var gone: [UUID] = []
        // A missing file only counts when its folder can be read: an unplugged drive or a
        // folder we've lost access to shouldn't empty the list.
        var readable: [URL: Bool] = [:]
        for d in items where d.status == .completed {
            if let age = settings.finishedKeepTime, now.timeIntervalSince(d.finished ?? d.added) >= age {
                gone.append(d.id)
            } else if settings.removeDeleted, let file = d.fileURL {
                let parent = file.deletingLastPathComponent()
                if readable[parent] == nil {
                    _ = destinationFolder(for: d)  // makes sure a picked folder's sandbox access is active
                    readable[parent] = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) != nil
                }
                if readable[parent] == true && !FileManager.default.fileExists(atPath: file.path) { gone.append(d.id) }
            }
        }
        for id in gone { remove(id) }
    }

    /// Holds a "no idle sleep" assertion while anything is downloading and the setting is on.
    private func updateSleepPrevention() {
        let wanted = settings.preventSleep && !downloading.isEmpty
        if wanted, sleepActivity == nil {
            sleepActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .userInitiated], reason: "Downloading files")
        } else if !wanted, let activity = sleepActivity {
            ProcessInfo.processInfo.endActivity(activity)
            sleepActivity = nil
        }
    }

    // MARK: - Persistence

    private static let supportFolder: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Haul")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static let partialsFolder: URL = {
        let url = supportFolder.appending(path: "Partials")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static var listURL: URL { supportFolder.appending(path: "downloads.json") }

    private func load() {
        guard let data = try? Data(contentsOf: Self.listURL) else { return }
        items = (try? JSONDecoder().decode([Download].self, from: data)) ?? []
    }

    func save() {
        dirty = false
        // Persist the latest engine progress so a crash or quit resumes from here.
        var snapshot = items
        for i in snapshot.indices { if let e = engines[snapshot[i].id] { snapshot[i].segments = e.snapshot() } }
        for i in snapshot.indices where snapshot[i].status == .paused && pausedForNetwork.contains(snapshot[i].id) {
            snapshot[i].status = .queued
        }
        do {
            try JSONEncoder().encode(snapshot).write(to: Self.listURL, options: .atomic)
        } catch {
            NSLog("Haul: couldn't save downloads: \(error)")
        }
    }
}

extension Download {
    fileprivate mutating func apply(_ info: Probe.Info) {
        if renamed != true { name = info.name }
        etag = info.etag
        lastModified = info.lastModified
        size = info.size
        resumable = info.acceptsRanges
        segments = Segment.split(size: info.size, connections: connections, resumable: info.acceptsRanges)
        // The file is downloaded from the start, so anything extracted came from the old one.
        extractedURL = nil
        extractError = nil
    }
}

nonisolated func sha256(of url: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try? handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

// MARK: - Notifications

nonisolated final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// Also asks for badges: without them macOS hides the Dock icon's percentage.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    @MainActor static func added(_ d: Download) {
        post(d, title: "Download Added", body: d.host)
    }

    @MainActor static func finished(_ d: Download, folder: String) {
        post(d, title: "Download Finished", body: "\(formatBytes(d.size ?? d.received)) · \(folder)")
    }

    @MainActor static func failed(_ d: Download) {
        post(d, title: "Download Failed", body: d.error ?? "Unknown error")
    }

    @MainActor static func extractFailed(_ d: Download) {
        post(d, title: "Couldn't Extract", body: d.extractError ?? "Unknown error")
    }

    /// One notification per download: a newer one (e.g. finished) replaces the earlier (added).
    @MainActor private static func post(_ d: Download, title: String, body: String) {
        if AppSettings.shared.notifyOnlyInBackground && NSApp.isActive { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = d.name
        content.body = body
        content.userInfo = ["id": d.id.uuidString]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: d.id.uuidString, content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions
    {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = (response.notification.request.content.userInfo["id"] as? String).flatMap(UUID.init) else { return }
        await MainActor.run { DownloadStore.shared.reveal(id) }
    }
}

// MARK: - Dock tile

final class DockProgress {
    private var shown = false
    private let host = NSHostingView(rootView: DockTileView(progress: 0))

    init() { host.frame = NSRect(x: 0, y: 0, width: 128, height: 128) }

    /// Pass nil to restore the plain icon.
    func update(progress: Double?, badge: String) {
        let tile = NSApp.dockTile
        if let progress {
            if !shown {
                tile.contentView = host
                shown = true
            }
            host.rootView = DockTileView(progress: progress)
            if tile.badgeLabel != badge { tile.badgeLabel = badge }
            tile.display()
        } else if shown {
            tile.contentView = nil
            tile.badgeLabel = nil
            tile.display()
            shown = false
        }
    }
}

struct DockTileView: View {
    let progress: Double

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
            Capsule()
                .fill(.white.opacity(0.92))
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule().fill(Color(hex: 0x1D1D1F))
                            .frame(width: max(6, geo.size.width * progress))
                    }
                    .padding(3)
                }
                .overlay(Capsule().stroke(.black.opacity(0.2), lineWidth: 0.5))
                .frame(height: 16)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .frame(width: 128, height: 128)
    }
}

/// Lets a subview that sticks out past this view's bounds still take clicks.
private final class OverhangView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        for sub in subviews.reversed() {
            if let hit = sub.hitTest(local) { return hit }
        }
        return super.hitTest(point)
    }
}
