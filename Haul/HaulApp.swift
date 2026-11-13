import SwiftUI
import UserNotifications

@main
enum Launcher {
    static func main() {
        // Unit tests run inside the app. Start an empty one for them, hidden from the Dock, so a
        // test run never loads the real download list or resumes downloads.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil {
            NSApplication.shared.setActivationPolicy(.prohibited)
            NSApplication.shared.run()
        } else {
            HaulApp.main()
        }
    }
}

/// "Haul Dev" for a Debug build, so it can be told apart from the installed app.
nonisolated enum AppInfo {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as! String
}

struct HaulApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var store = DownloadStore.shared
    @Bindable private var settings = AppSettings.shared

    var body: some Scene {
        Window(AppInfo.name, id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 860, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 720)
        .commands { HaulCommands(store: store) }

        Window("Keyboard Shortcuts", id: "shortcuts") {
            ShortcutsView()
        }
        .windowResizability(.contentSize)

        MenuBarExtra(isInserted: $settings.menuBar) {
            MenuBarPopover()
                .environment(store)
                .tint(Theme.accent)
        } label: {
            MenuBarLabel()
                .environment(store)
        }
        .menuBarExtraStyle(.window)
    }
}

extension URL {
    static let sponsor = URL(string: "https://github.com/sponsors/sibiraj-s")!
}

private struct HaulCommands: Commands {
    let store: DownloadStore

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppInfo.name)") {
                // The standard panel adds the build number in parentheses; it's the same as the version.
                NSApp.orderFrontStandardAboutPanel(options: [
                    .applicationVersion: "Version \(Updater.shared.currentVersion)",
                    .version: "",
                ])
            }
            CheckForUpdatesButton()
            CommandLineToolButton()
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { SettingsWindow.shared.show() }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .newItem) {
            Button("Add Download…") { store.requestAdd() }
                .keyboardShortcut("n")
        }
        CommandGroup(before: .sidebar) {
            ViewCommands(store: store)
        }
        CommandMenu("Downloads") {
            SelectionCommands(store: store)
            Divider()
            Button("Pause All") { store.pauseAll() }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Button("Resume All") { store.resumeAll() }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Divider()
            Button("Clear Completed…") { store.requestClearCompleted() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
        }
        CommandGroup(before: .windowList) {
            Button("Show Main Window") { store.showMainWindow() }
                .keyboardShortcut("0")
        }
        CommandGroup(after: .help) {
            ShortcutsButton()
            Divider()
            Button("Sponsor Haul…") {
                NSWorkspace.shared.open(.sponsor)
            }
        }
    }
}

/// A View to get `openWindow`, which Commands don't have.
private struct ShortcutsButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Keyboard Shortcuts") { openWindow(id: "shortcuts") }
            .keyboardShortcut("/")
    }
}

/// Commands for the selected download. A View for the same reason as `CheckForUpdatesButton`.
private struct SelectionCommands: View {
    let store: DownloadStore

    var body: some View {
        let d = store.showAdd || store.updatingLink != nil ? nil : store.selected
        let done = d?.status == .completed
        Button("Open") { d.map(store.open) }
            .keyboardShortcut("o")
            .disabled(!done)
        Button("Show in Finder") { d.map(store.revealInFinder) }
            .keyboardShortcut("r")
            .disabled(d == nil)
        Button(toggleTitle(d)) { d.map { store.toggle($0.id) } }
            .disabled(d == nil || done)
        Button("Rename…") { d.map { store.beginRename($0.id) } }
            .disabled(d == nil)
        Button("Copy Link") { d.map { copyToPasteboard($0.url.absoluteString) } }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(d == nil)
        Button("Remove…") {
            // Menu shortcuts run before the text field gets the key, so give ⌘⌫ back to it.
            if let field = NSApp.keyWindow?.firstResponder as? NSTextView {
                field.deleteToBeginningOfLine(nil)
            } else if let d {
                store.requestRemove(d.id)
            }
        }
        .keyboardShortcut(.delete)
        .disabled(d == nil)
    }

    private func toggleTitle(_ d: Download?) -> String {
        switch d?.status {
        case .downloading: "Pause"
        case .queued: "Start Now"
        case .failed: d?.issue == .signIn ? "Sign In…" : "Retry"
        default: "Resume"
        }
    }
}

/// Sidebar filters, and the panels whose visibility each window keeps in scene storage.
private struct ViewCommands: View {
    let store: DownloadStore
    @FocusedBinding(\.showSidebar) private var showSidebar
    @FocusedBinding(\.showInspector) private var showInspector

    var body: some View {
        Button(showSidebar == false ? "Show Sidebar" : "Hide Sidebar") {
            withAnimation(.easeOut(duration: 0.2)) { showSidebar?.toggle() }
        }
        .keyboardShortcut("s", modifiers: [.command, .control])
        .disabled(showSidebar == nil)
        Button(showInspector == false ? "Show Inspector" : "Hide Inspector") {
            withAnimation(.easeOut(duration: 0.2)) { showInspector?.toggle() }
        }
        .keyboardShortcut("i", modifiers: [.command, .option])
        .disabled(showInspector == nil)
        Divider()
        ForEach(Array(SidebarFilter.library.enumerated()), id: \.offset) { n, f in
            Button(f.title) { store.filter = f }
                .keyboardShortcut(KeyEquivalent(Character("\(n + 1)")))
        }
        Divider()
    }
}

extension FocusedValues {
    @Entry var showSidebar: Binding<Bool>?
    @Entry var showInspector: Binding<Bool>?
}

/// A View, not inline in `HaulCommands`: Commands don't reliably redraw when `canCheck`
/// changes, which could leave the item disabled after Sparkle starts.
private struct CheckForUpdatesButton: View {
    var body: some View {
        Button("Check for Updates…") { Updater.shared.checkNow() }
            .disabled(!Updater.shared.canCheckNow)
    }
}

/// A View for the same reason as `CheckForUpdatesButton`: the title follows whether the tool is installed.
private struct CommandLineToolButton: View {
    var body: some View {
        Button(CommandLineInstall.shared.state == .installed ? "Uninstall Command Line Tool…" : "Install Command Line Tool…") {
            CommandLineInstall.shared.show()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var confirmingQuit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.shared.applyAppearance()
        UNUserNotificationCenter.current().delegate = Notifier.shared
        let settings = AppSettings.shared
        if settings.notify || settings.notifyAdded || settings.notifyFailed || settings.dockProgress { Notifier.requestAuthorization() }
        Updater.shared.start()
        NSApp.servicesProvider = ServiceProvider.shared
        // Only the installed app: the browsers' manifests name one copy of Haul, and a Debug build
        // would point them at itself, sending downloads from the browser extension to it.
        #if !DEBUG
            Task.detached(priority: .utility) { BrowserHosts.install() }
        #endif
        RemoteServer.shared.update()
        DockIcon.observeWindows()
        MenuBarContextMenu.install()
    }

    /// haul://add links from other apps and browser extensions.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let links = IncomingLinks.links(in: url)
            if !links.isEmpty { DownloadStore.shared.requestAdd(links, browser: IncomingLinks.browserContext(in: url)) }
        }
    }

    /// Keep running in the menu bar after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Asks before a quit that would interrupt downloads or extractions.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // An update's relaunch was already agreed to in Sparkle's window.
        if Updater.shared.isRelaunching { return .terminateNow }
        // Logging out, restarting and shutting down say why in the quit event. Asking then would
        // hold them up, and cancel them if nobody answers.
        let event = NSAppleEventManager.shared().currentAppleEvent
        if event?.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil { return .terminateNow }
        // Quit can be chosen again from the Dock or the menu bar while the alert is up.
        guard !confirmingQuit else { return .terminateCancel }
        confirmingQuit = true
        defer { confirmingQuit = false }
        return DownloadStore.shared.confirmQuit() ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        DownloadStore.shared.abandonExtractions()
        DownloadStore.shared.save()
    }
}

/// Shows the Dock icon while a window is open, and hides it once the last one closes
/// when the user chose to keep Haul only in the menu bar.
enum DockIcon {
    static func observeWindows() {
        let center = NotificationCenter.default
        // The closing window is still on screen during `willClose`, so look once it's gone.
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.async { update() }
        }
        center.addObserver(forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { _ in update() }
        // Haul may start with no window, e.g. when it was closed at quit.
        DispatchQueue.main.async { update() }
    }

    /// Call before bringing up a window: an accessory app can be refused activation, and its
    /// menu bar only appears when it's activated after becoming a regular app.
    static func show() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }

    static func update() {
        guard let app = NSApp, !app.isHidden else { return }  // ⌘H hides windows without closing them.
        let settings = AppSettings.shared
        // Only Haul's own windows count: not the status item, the menu bar popover, open panels or alerts.
        let windowOpen = app.windows.contains { !($0 is NSPanel) && $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized) }
        let policy: NSApplication.ActivationPolicy =
            settings.menuBar && settings.hideDockWhenClosed && !windowOpen ? .accessory : .regular
        guard app.activationPolicy() != policy else { return }
        app.setActivationPolicy(policy)
        // Otherwise Haul stays frontmost with its menus showing and no window to type into.
        if policy == .accessory && app.isActive { app.hide(nil) }
    }
}
