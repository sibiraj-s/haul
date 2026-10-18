import SwiftUI
import UserNotifications

@main
enum Launcher {
    static func main() {
        // Unit tests run inside the app. Start an empty one for them, so a test run never
        // loads the real download list or resumes downloads.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil {
            TestHostApp.main()
        } else {
            HaulApp.main()
        }
    }
}

private struct TestHostApp: App {
    var body: some Scene { Settings { EmptyView() } }
}

struct HaulApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var store = DownloadStore.shared
    @Bindable private var settings = AppSettings.shared

    var body: some Scene {
        Window("Haul", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 860, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 720)
        .commands { HaulCommands(store: store) }

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
            Button("About Haul") {
                // The standard panel adds the build number in parentheses; it's the same as the version.
                NSApp.orderFrontStandardAboutPanel(options: [
                    .applicationVersion: "Version \(Updater.shared.currentVersion)",
                    .version: "",
                ])
            }
            CheckForUpdatesButton()
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { SettingsWindow.shared.show() }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .newItem) {
            Button("Add Download…") { store.requestAdd() }
                .keyboardShortcut("n")
        }
        CommandMenu("Downloads") {
            Button("Pause All") { store.pauseAll() }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Button("Resume All") { store.resumeAll() }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Divider()
            Button("Clear Completed…") { store.requestClearCompleted() }
        }
        CommandGroup(before: .windowList) {
            Button("Show Main Window") { store.showMainWindow() }
                .keyboardShortcut("0")
        }
        CommandGroup(after: .help) {
            Button("Sponsor Haul…") {
                NSWorkspace.shared.open(.sponsor)
            }
        }
    }
}

/// A View, not inline in `HaulCommands`: Commands don't reliably redraw when `canCheck`
/// changes, which could leave the item disabled after Sparkle starts.
private struct CheckForUpdatesButton: View {
    var body: some View {
        Button("Check for Updates…") { Updater.shared.checkNow() }
            .disabled(Updater.shared.isEnabled && !Updater.shared.canCheck)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.shared.applyAppearance()
        UNUserNotificationCenter.current().delegate = Notifier.shared
        let settings = AppSettings.shared
        if settings.notify || settings.notifyAdded || settings.notifyFailed || settings.dockProgress { Notifier.requestAuthorization() }
        Updater.shared.start()
    }

    /// Keep running in the menu bar after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        DownloadStore.shared.save()
    }
}
