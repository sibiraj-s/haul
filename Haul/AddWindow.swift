import AppKit
import SwiftUI

/// The Add panel in a small window of its own, for links sent from another app (a browser
/// extension, Safari, the Share menu, the Services menu, the command-line tool). Adding a link
/// shouldn't bring up the whole download list: the window comes up over the app the link came
/// from, and that app gets the focus back when it closes.
///
/// A panel, so it doesn't count as a window that brings back the Dock icon (see `DockIcon`).
/// Sized by hand from what the view reports (`fit(_:)`, see `FittedWindow`).
final class AddWindow: NSObject, NSWindowDelegate {
    static let shared = AddWindow()

    private var panel: NSPanel?
    private var hosting: NSView?
    /// The app that was in front when the window came up, to hand the focus back to.
    private var previousApp: NSRunningApplication?
    /// Whether closing should hand the focus back to `previousApp`.
    private var returnFocus = true

    /// Also while a new window waits for its size, so nothing hides Haul meanwhile.
    var isOpen: Bool { panel != nil }

    /// A new window is held back until the form has reported its size, so it doesn't come up
    /// at a guessed height and then visibly resize.
    private var waitingForSize = false
    /// The app the latest link came from (see `show`).
    private var origin: NSRunningApplication?
    /// Watches for another Haul window becoming key: the user moved on from the app the link came from.
    private var otherWindowObserver: NSObjectProtocol?

    func show() {
        // The app the link came from, while it's known: opening a link activates Haul just before.
        // Nil when the user was already in Haul.
        origin = OriginApp.current
        if panel == nil || origin != nil { previousApp = origin }
        if panel == nil {
            let panel = makePanel()
            self.panel = panel
            waitingForSize = true
            // In case no size comes. Only for this window: one closed meanwhile has its own.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak panel] in
                guard let self, let panel, panel === self.panel, waitingForSize else { return }
                waitingForSize = false
                present()
            }
            return
        }
        if !waitingForSize { present() }
    }

    private func present() {
        guard let panel else { return }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        // An app that's only in the menu bar can be refused activation; still put the window in front.
        if !NSApp.isActive { panel.orderFrontRegardless() }
        if let origin { keepMainWindowBehind(origin) }
    }

    /// Activating Haul brings all its windows forward, the one with the whole list too. Puts
    /// that one back under the front window of `app`, where it was, now and once more when an
    /// activation still under way goes through.
    private func keepMainWindowBehind(_ app: NSRunningApplication) {
        let windows = NSApp.windows.filter { $0.isHaulMainWindow && $0.isVisible && !$0.isMiniaturized }
        guard !windows.isEmpty else { return }
        let putBack = {
            let onScreen =
                CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            let above =
                onScreen.first {
                    $0[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier && $0[kCGWindowLayer as String] as? Int == 0
                }?[kCGWindowNumber as String] as? Int
            for window in windows where window.isVisible {
                if let above { window.order(.below, relativeTo: above) } else { window.orderBack(nil) }
            }
        }
        putBack()
        guard !NSApp.isActive else { return }
        var observer: NSObjectProtocol?
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) {
            _ in
            MainActor.assumeIsolated {
                observer.map(NotificationCenter.default.removeObserver)
                putBack()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { observer.map(NotificationCenter.default.removeObserver) }
    }

    /// Closes the window. `returningFocus: false` when something in Haul comes up next, such as
    /// the main window showing a link that's already in the list.
    func close(returningFocus: Bool = true) {
        returnFocus = returningFocus
        panel?.close()
    }

    func windowDidBecomeKey(_ notification: Notification) { DownloadStore.shared.addWindowKey = true }
    func windowDidResignKey(_ notification: Notification) { DownloadStore.shared.addWindowKey = false }

    func windowWillClose(_ notification: Notification) {
        let store = DownloadStore.shared
        store.addWindowKey = false
        store.addFormClosed()
        otherWindowObserver.map(NotificationCenter.default.removeObserver)
        otherWindowObserver = nil
        // A new window next time, so the form starts afresh.
        panel?.delegate = nil
        panel = nil
        hosting = nil
        if returnFocus, NSApp.isActive, let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }
        previousApp = nil
        returnFocus = true
        waitingForSize = false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: AddDownloadPanel.width, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        hosting = FittedWindow.host(
            AddDownloadPanel(floating: true)
                // Natural height, whatever the window's size; the window follows it (`fit`).
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGSize.self) {
                    $0.size
                } action: { [weak self] in
                    self?.fit($0)
                }
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .environment(DownloadStore.shared)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .tint(Theme.accent)
                // Under the transparent title bar, as in Settings; otherwise the bottom is cut off.
                .ignoresSafeArea(),
            in: panel, title: "Add Download")
        // Stays up while the user goes back to the browser, e.g. to copy another link.
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        // Over a full-screen browser, rather than on another Space.
        panel.collectionBehavior.insert(.fullScreenAuxiliary)
        panel.delegate = self
        otherWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let window = note.object as? NSWindow, window !== self.panel, !(window is NSPanel) else { return }
                self.previousApp = nil
            }
        }
        panel.center()
        return panel
    }

    /// Resizes the window to the content's size, keeping its top edge in place. A new window
    /// comes up once it has its size, centered.
    private func fit(_ size: CGSize) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel, let hosting, size.height > 0,
                let frame = FittedWindow.frame(fitting: size, in: panel, hosting: hosting, always: waitingForSize)
            else { return }
            guard waitingForSize else { return panel.setFrame(frame, display: true, animate: panel.isVisible) }
            waitingForSize = false
            panel.setFrame(frame, display: false)
            panel.center()
            present()
        }
    }
}

/// The app the user was in before Haul was activated. Opening a link activates Haul before
/// the link arrives, so by then the app it came from is no longer the frontmost one.
enum OriginApp {
    /// The app that was in front when Haul was last activated, and when that was.
    private static var beforeHaul: (app: NSRunningApplication?, at: Date)?
    private static var last: NSRunningApplication?

    /// Call at launch.
    static func track() {
        if NSWorkspace.shared.frontmostApplication == .current {
            // Launched for a link and already activated: the app it came from has the front window.
            let onScreen =
                CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            let pid =
                onScreen.first {
                    $0[kCGWindowLayer as String] as? Int == 0 && $0[kCGWindowOwnerPID as String] as? pid_t != getpid()
                }?[kCGWindowOwnerPID as String] as? pid_t
            beforeHaul = (pid.flatMap(NSRunningApplication.init(processIdentifier:)), .now)
        } else {
            last = NSWorkspace.shared.frontmostApplication
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            MainActor.assumeIsolated {
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                if app == .current { beforeHaul = (last, .now) } else { last = app }
            }
        }
    }

    /// The app in front, or the one that was until Haul was activated a moment ago; nil when
    /// the user was already in Haul.
    static var current: NSRunningApplication? {
        let front = NSWorkspace.shared.frontmostApplication
        if front != .current { return front }
        guard let beforeHaul, Date.now.timeIntervalSince(beforeHaul.at) < 1 else { return nil }
        return beforeHaul.app
    }
}
