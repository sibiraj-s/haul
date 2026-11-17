import AppKit
import SwiftUI

/// A SwiftUI view in a window the app owns, under a transparent title bar, with the window
/// sized by hand to the height the view reports (Settings, the Add window).
///
/// The SwiftUI view sits inside a plain container rather than being the window's content
/// itself: as content (view or view controller) SwiftUI also resizes the window, adding the
/// title bar height, and with `sizingOptions` or `safeAreaRegions = []` that loops into an
/// "Update Constraints in Window" exception.
enum FittedWindow {
    /// Puts `rootView` in `window` and styles the window; returns the hosting view for `frame(fitting:in:hosting:)`.
    static func host(_ rootView: some View, in window: NSWindow, title: String) -> NSView {
        let frame = NSRect(origin: .zero, size: window.contentRect(forFrameRect: window.frame).size)
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []
        hosting.sceneBridgingOptions = []
        hosting.frame = frame
        // Pinned to the top at the content's own height (see `frame(fitting:in:hosting:)`), so
        // resizing the window only reveals or hides the bottom edge and never re-lays out the SwiftUI view.
        hosting.autoresizingMask = [.width, .minYMargin]
        let container = NSView(frame: frame)
        container.addSubview(hosting)

        window.contentView = container
        window.backgroundColor = NSColor(Theme.win)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.title = title
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenNone)
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = true
        }
        return hosting
    }

    /// Gives the SwiftUI view its new `size`, pinned to the top, and returns the window frame
    /// that fits it with the top edge in place and the whole window on screen; nil when the
    /// window already fits, unless `always`. The window can then animate around the view:
    /// resizing the SwiftUI view on every animation step makes the content lag a frame behind
    /// and visibly bounce.
    static func frame(fitting size: CGSize, in window: NSWindow, hosting: NSView, always: Bool = false) -> NSRect? {
        guard let container = window.contentView else { return nil }
        let pinned = NSRect(x: 0, y: container.bounds.height - size.height, width: container.bounds.width, height: size.height)
        if hosting.frame != pinned { hosting.frame = pinned }
        var frame = window.frame
        let fitted = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        guard always || abs(fitted.height - frame.height) > 0.5 || abs(fitted.width - frame.width) > 0.5 else { return nil }
        frame.origin.y += frame.height - fitted.height
        frame.size = fitted
        if let visible = window.screen?.visibleFrame {
            frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        }
        return frame
    }
}
