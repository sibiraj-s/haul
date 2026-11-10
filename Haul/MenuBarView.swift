import SwiftUI

/// Menu bar icon: a ring that fills with overall progress, plus live speed while downloading.
struct MenuBarLabel: View {
    @Environment(DownloadStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let active = !store.downloading.isEmpty
        HStack(spacing: 5) {
            Image(nsImage: Self.ringImage(progress: active ? store.overallProgress : 0))
            if active {
                Text("\(formatBytes(store.totalSpeed))/s").monospacedDigit()
            }
        }
        .onAppear { store.openMainWindow = { openWindow(id: "main") } }
    }

    static func ringImage(progress: Double) -> NSImage {
        // Debug builds add a dot at the lower right, so they can be told apart from the installed
        // app in the menu bar.
        #if DEBUG
            let dot: CGFloat = 6
        #else
            let dot: CGFloat = 0
        #endif
        let image = NSImage(size: NSSize(width: 17 + dot / 3, height: 17), flipped: false) { rect in
            let center = NSPoint(x: 8.5, y: rect.midY)
            let radius: CGFloat = 6.8
            // No ring while idle: only progress is drawn around the arrow.
            if progress > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * min(1, progress), clockwise: true)
                arc.lineWidth = 1.5
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: center.x, y: center.y + 3.4))
            arrow.line(to: NSPoint(x: center.x, y: center.y - 2.6))
            arrow.move(to: NSPoint(x: center.x - 2.3, y: center.y - 0.3))
            arrow.line(to: NSPoint(x: center.x, y: center.y - 2.6))
            arrow.line(to: NSPoint(x: center.x + 2.3, y: center.y - 0.3))
            arrow.lineWidth = 1.4
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            NSColor.black.setStroke()
            arrow.stroke()
            if dot > 0 {
                // Cut out of the ring with a gap around it, so it stays visible.
                let spot = NSRect(x: rect.maxX - dot, y: 0, width: dot, height: dot)
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: spot.insetBy(dx: -1.5, dy: -1.5)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.black.setFill()
                NSBezierPath(ovalIn: spot).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct MenuBarPopover: View {
    @Environment(DownloadStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let unfinished = store.items.filter { $0.status.isUnfinished }
        let recent = store.items.filter { $0.status == .completed }.prefix(3)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(AppInfo.name).fontWeight(.bold)
                Spacer()
                Text(store.subtitle).font(.system(size: 11)).foregroundStyle(Theme.text2).monospacedDigit()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .help("Quit \(AppInfo.name)")
                .accessibilityLabel("Quit \(AppInfo.name)")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                if unfinished.isEmpty {
                    Text("No active downloads.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 14)
                } else {
                    ForEach(unfinished.prefix(4)) { ActiveItem(download: $0) }
                }
            }
            .padding(.horizontal, 6)

            if !recent.isEmpty {
                Text("Recently finished")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text3)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                VStack(spacing: 0) {
                    ForEach(recent) { d in
                        HoverRow {
                            store.reveal(d.id)
                            dismiss()
                        } content: {
                            HStack(spacing: 10) {
                                FileIcon(ext: "", kind: d.kind, width: 20, height: 25, band: 8, radius: 3)
                                Text(d.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(formatBytes(d.size ?? d.received)).font(.system(size: 11)).foregroundStyle(Theme.text2)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }

            HStack(spacing: 6) {
                let running = !store.downloading.isEmpty
                PillButton(title: running ? "Pause All" : "Resume All", height: 26, fontSize: 12, expand: true) {
                    running ? store.pauseAll() : store.resumeAll()
                }
                PillButton(title: "Add Link…", height: 26, fontSize: 12, expand: true) {
                    dismiss()
                    store.requestAdd()
                }
                PillButton(title: "Open \(AppInfo.name)", prominent: true, height: 26, fontSize: 12, expand: true) {
                    dismiss()
                    store.showMainWindow()
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .overlay(alignment: .top) { Rectangle().fill(Theme.sep).frame(height: 0.5) }
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.text)
        .frame(width: 320)
    }
}

private struct ActiveItem: View {
    @Environment(DownloadStore.self) private var store
    let download: Download
    @State private var hovering = false

    var body: some View {
        let d = download
        HStack(spacing: 10) {
            FileIcon(ext: "", kind: d.kind, width: 20, height: 25, band: 8, radius: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(d.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                ThinProgressBar(value: d.progress, fill: d.status == .downloading ? Theme.accent : Theme.text3, height: 3)
                Text(statusLine(d)).font(.system(size: 10.5)).foregroundStyle(Theme.text2).monospacedDigit().lineLimit(1)
            }
            Button {
                store.toggle(d.id)
            } label: {
                Image(systemName: d.status == .downloading ? "pause.fill" : "play.fill")
                    .font(.system(size: 7.5, weight: .heavy))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(Theme.text3, lineWidth: 1.2))
                    .contentShape(Circle())
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Theme.hover : .clear))
        .onHover { hovering = $0 }
    }
}

private struct HoverRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content
                .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Theme.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Right-click (or Control-click) on the menu bar icon shows app-level actions, which are otherwise
/// out of reach when the window is closed and the Dock icon is hidden.
/// `MenuBarExtra` has no context menu of its own, so catch the click on its status bar window.
enum MenuBarContextMenu {
    static func install() {
        NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
            guard event.type == .rightMouseDown || event.modifierFlags.contains(.control),
                let window = event.window, window.className == "NSStatusBarWindow",
                let view = window.contentView
            else { return event }
            // Close the popover if it's open, so it doesn't stay up under the menu.
            for w in NSApp.windows where w.isVisible && w.className.contains("MenuBarExtra") { w.close() }
            // No key equivalents: they don't reach Haul while it has no window and no Dock icon.
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(withTitle: "Settings…", action: #selector(Actions.settings), keyEquivalent: "").target = Actions.shared
            let update = menu.addItem(withTitle: "Check for Updates…", action: #selector(Actions.checkForUpdates), keyEquivalent: "")
            update.target = Actions.shared
            update.isEnabled = Updater.shared.canCheckNow
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            let button = view as? NSButton
            button?.highlight(true)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.isFlipped ? view.bounds.maxY + 4 : -4), in: view)
            button?.highlight(false)
            return nil  // Don't also open the popover.
        }
    }

    private final class Actions: NSObject {
        static let shared = Actions()

        @objc func settings() { SettingsWindow.shared.show() }

        @objc func checkForUpdates() { Updater.shared.checkNow() }
    }
}
