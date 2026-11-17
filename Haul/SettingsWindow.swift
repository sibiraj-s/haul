import AppKit
import SwiftUI

/// Hosts Settings in a window the app owns instead of SwiftUI's `Settings` scene.
///
/// The `Settings` scene keeps managing its title bar: it resets `titlebarAppearsTransparent`,
/// leaving a real title bar (and its blur) over the custom header.
///
/// The window is sized by hand from the size the view reports (`fit(_:)`, see `FittedWindow`).
final class SettingsWindow {
    static let shared = SettingsWindow()

    private var window: NSWindow?
    private var hosting: NSView?

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        DockIcon.show()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsView.width, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        hosting = FittedWindow.host(SettingsView(), in: window, title: "Settings")
        window.isMovableByWindowBackground = false
        window.center()
        window.setFrameAutosaveName("HaulSettings")
        return window
    }

    /// Resizes the window to the content's size, keeping its top edge in place and the whole
    /// window on screen. Deferred so it never runs inside a layout pass.
    func fit(_ size: CGSize) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window, let hosting, let frame = FittedWindow.frame(fitting: size, in: window, hosting: hosting) else {
                return
            }
            window.setFrame(frame, display: true, animate: window.isVisible)
        }
    }
}
