import SwiftUI

/// Menu bar icon: a ring that fills with overall progress, plus live speed while downloading.
struct MenuBarLabel: View {
    @Environment(DownloadStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let active = !store.downloading.isEmpty
        HStack(spacing: 5) {
            Image(nsImage: ringImage(progress: active ? store.overallProgress : 0))
            if active {
                Text("\(formatBytes(store.totalSpeed))/s").monospacedDigit()
            }
        }
        .onAppear { store.openMainWindow = { openWindow(id: "main") } }
    }

    private func ringImage(progress: Double) -> NSImage {
        let image = NSImage(size: NSSize(width: 17, height: 17), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY), radius: CGFloat = 6.8
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = 1.5
            NSColor.black.withAlphaComponent(0.25).setStroke()
            track.stroke()
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
                Text("Haul").fontWeight(.bold)
                Spacer()
                Text(store.subtitle).font(.system(size: 11)).foregroundStyle(Theme.text2).monospacedDigit()
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
                PillButton(title: "Open Haul", prominent: true, height: 26, fontSize: 12, expand: true) {
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
