import AppKit
import SwiftUI

/// Hosts Settings in a window the app owns instead of SwiftUI's `Settings` scene.
///
/// The `Settings` scene keeps managing its title bar: it resets `titlebarAppearsTransparent`,
/// leaving a real title bar (and its blur) over the custom header.
///
/// The window is sized by hand from the size the view reports (`fit(_:)`). The SwiftUI view
/// sits inside a plain container rather than being the window's content itself: as content
/// (view or view controller) SwiftUI also resizes the window, adding the title bar height,
/// and with `sizingOptions` or `safeAreaRegions = []` that loops into an
/// "Update Constraints in Window" exception.
final class SettingsWindow {
    static let shared = SettingsWindow()

    private var window: NSWindow?
    private var hosting: NSView?

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let frame = NSRect(x: 0, y: 0, width: SettingsView.width, height: 400)
        let hosting = NSHostingView(rootView: SettingsView())
        hosting.sizingOptions = []
        hosting.sceneBridgingOptions = []
        hosting.frame = frame
        // Pinned to the top at the content's own height (see `fit`), so resizing the window
        // only reveals or hides the bottom edge and never re-lays out the SwiftUI view.
        hosting.autoresizingMask = [.width, .minYMargin]
        let container = NSView(frame: frame)
        container.addSubview(hosting)
        self.hosting = hosting

        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentView = container
        window.backgroundColor = NSColor(Theme.win)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.collectionBehavior.insert(.fullScreenNone)
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = true
        }
        window.center()
        window.setFrameAutosaveName("HaulSettings")
        return window
    }

    /// Resizes the window to the content's size, keeping its top edge in place and the whole
    /// window on screen. Deferred so it never runs inside a layout pass.
    ///
    /// The SwiftUI view is given its new size first, pinned to the top, and the window then
    /// animates around it. Resizing the SwiftUI view on every animation step makes the content
    /// lag a frame behind and visibly bounce.
    func fit(_ size: CGSize) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window, let hosting, let container = window.contentView else { return }
            let pinned = NSRect(x: 0, y: container.bounds.height - size.height, width: container.bounds.width, height: size.height)
            if hosting.frame != pinned { hosting.frame = pinned }
            var frame = window.frame
            let fitted = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
            guard abs(fitted.height - frame.height) > 0.5 || abs(fitted.width - frame.width) > 0.5 else { return }
            frame.origin.y += frame.height - fitted.height
            frame.size = fitted
            if let visible = window.screen?.visibleFrame {
                frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
            }
            window.setFrame(frame, display: true, animate: window.isVisible)
        }
    }
}
