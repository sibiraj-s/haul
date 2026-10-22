import SwiftUI

struct InspectorView: View {
    @Environment(DownloadStore.self) private var store
    /// The progress bar under the pointer, whose details replace the status lines.
    @State private var hoveredBar: Int?

    var body: some View {
        if let d = store.selected {
            ScrollView {
                VStack(spacing: 0) {
                    header(d)
                    progress(d)
                    details(d)
                    actions(d)
                }
            }
            .scrollIndicators(.never)
        } else {
            Text("No Selection")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.text3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ d: Download) -> some View {
        VStack(spacing: 8) {
            FileIcon(ext: d.ext, kind: d.kind, width: 52, height: 64, band: 20, fontSize: 11, radius: 7)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
            EditableName(download: d)
            Text("\(d.kind.label) · \(d.size.map(formatBytes) ?? "Unknown size")")
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private func statusColor(_ d: Download) -> Color {
        switch d.status {
        case .downloading: Theme.accent
        case .failed: Theme.red
        case .completed: Theme.green
        default: Theme.text2
        }
    }

    /// The file in equal parts, one bar per connection set, each filled to how much of it is
    /// downloaded. Hovering a bar swaps the status lines for that part's details, which keep
    /// updating (a tooltip wouldn't); without a size there are none to show.
    private func progress(_ d: Download) -> some View {
        let bars = d.progressBars
        let hovered = bars.first { $0.id == hoveredBar }
        let color: Color = switch d.status {
        case .completed: Theme.green
        case .failed: Theme.red
        case .downloading: Theme.accent
        default: Theme.text3
        }
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(d.status.label).fontWeight(.semibold).foregroundStyle(statusColor(d))
                Spacer()
                Text(d.progress, format: .percent.precision(.fractionLength(1))).foregroundStyle(Theme.text2)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 3), count: 8), spacing: 3) {
                ForEach(bars) { bar in
                    ZStack(alignment: .bottom) {
                        Rectangle().fill(Theme.track)
                        Rectangle()
                            .fill(color)
                            .frame(height: Self.barHeight * bar.fill)
                            .animation(.linear(duration: 0.5), value: bar.fill)
                    }
                    .frame(height: Self.barHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay {
                        if bar.id == hoveredBar {
                            RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.text2.opacity(0.6), lineWidth: 1)
                        }
                    }
                    .onHover { inside in
                        guard d.size != nil else { return }
                        if inside { hoveredBar = bar.id } else if hoveredBar == bar.id { hoveredBar = nil }
                    }
                }
            }
            // Two rows, so neither side wraps: connections beside speed, then time left, or the
            // hovered part's details.
            VStack(spacing: 3) {
                if let bar = hovered {
                    row("Part \(bar.id + 1) of \(bars.count)", partState(d, bar))
                    row("\(formatBytes(bar.done)) of \(formatBytes(bar.length))", "")
                } else {
                    row(connectionLine(d, total: d.connectionLimit), speedLine(d))
                    row("", timeLine(d) ?? "")
                }
            }
            .lineLimit(1)
            .foregroundStyle(Theme.text2)
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        // The pointer may still rest on a bar when the selection changes from the keyboard.
        .onChange(of: d.id) { hoveredBar = nil }
    }

    private static let barHeight: CGFloat = 22

    /// How far a part is, and while downloading, whether a connection is on it right now.
    private func partState(_ d: Download, _ bar: ProgressBar) -> String {
        if bar.fill >= 1 { return "Done" }
        // Rounded down, so only a finished part reads 100%.
        let percent = bar.fill.formatted(.percent.precision(.fractionLength(0)).rounded(rule: .down))
        guard d.status == .downloading else { return percent }
        return "\(percent) · \(bar.active ? "Downloading" : "Idle")"
    }

    /// One status row; an empty side still takes up its line, so hovering doesn't shift the layout.
    private func row(_ leading: String, _ trailing: String) -> some View {
        HStack {
            Text(leading.isEmpty ? " " : leading)
            Spacer()
            Text(trailing)
        }
    }

    private func connectionLine(_ d: Download, total: Int) -> String {
        guard d.status == .downloading, d.liveConnections > 0 || d.serverLimit != nil else {
            return "\(total) connection\(total == 1 ? "" : "s")"
        }
        let line = "\(d.liveConnections) of \(total) connections"
        return d.serverLimit != nil ? line + " · server limit" : line
    }

    private func speedLine(_ d: Download) -> String {
        if d.status == .downloading && d.speed > 0 { return "\(formatBytes(d.speed))/s" }
        return d.status == .completed ? "Done" : "—"
    }

    private func timeLine(_ d: Download) -> String? {
        d.status == .downloading && d.speed > 0 ? "\(formatDuration(d.remainingTime)) left" : nil
    }

    private func details(_ d: Download) -> some View {
        let checksum: (String, Color) = d.status != .completed
            ? ("After download", Theme.text2)
            : d.sha256.map { ("SHA-256 \($0.prefix(12))…", Theme.green) }
            ?? (store.settings.computeChecksum ? "Computing…" : "Not computed", Theme.text2)
        return DesignGroup {
            DetailRow("Size") {
                Text(d.status == .completed ? formatBytes(d.size ?? d.received) : "\(formatBytes(d.received)) of \(d.size.map(formatBytes) ?? "?")")
                    .monospacedDigit()
            }
            DetailRow("Source") { Text(d.host) }
            DetailRow("Link") {
                HStack(spacing: 6) {
                    Link(destination: d.url) {
                        Text(d.url.absoluteString).lineLimit(1).truncationMode(.tail)
                    }
                    .foregroundStyle(Theme.accent)
                    .help(d.url.absoluteString)
                    if d.status != .completed {
                        Button {
                            store.beginUpdateLink(d.id)
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.text2)
                        }
                        .buttonStyle(.pressable)
                        .help("Update Link…")
                    }
                }
            }
            DetailRow("Saved to") { Text(store.destinationLabel(for: d)).lineLimit(1).truncationMode(.middle) }
            DetailRow("Added") { Text(formatAdded(d.added)) }
            DetailRow("Checksum") {
                Text(checksum.0).foregroundStyle(checksum.1)
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .help(d.sha256 ?? "")
            }
            if d.extract == true && Extractor.canExtract(d.name) {
                DetailRow("Extract") { extraction(d) }
            }
            if let whenDone = d.whenDone, whenDone != .nothing, d.status != .completed {
                DetailRow("When done") { Text(whenDone.label) }
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
    }

    /// Where the archive was extracted to (click to show it in Finder), or how extracting is going.
    @ViewBuilder private func extraction(_ d: Download) -> some View {
        if let url = d.extractedURL {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .help("Show in Finder")
        } else if let error = d.extractError {
            Text(error).foregroundStyle(Theme.red).lineLimit(2).help(error)
        } else {
            Text(d.extracting ? "Extracting…" : d.status == .completed ? "Not extracted" : "After download")
                .foregroundStyle(Theme.text2)
        }
    }

    private func actions(_ d: Download) -> some View {
        VStack(spacing: 6) {
            PillButton(title: primaryLabel(d), prominent: true, expand: true) {
                switch (d.status, d.issue) {
                case (.completed, _): store.revealInFinder(d)
                case (.failed, .linkExpired): store.beginUpdateLink(d.id)
                case (.failed, .fileChanged): store.restart(d.id)
                default: store.toggle(d.id)
                }
            }
            HStack(spacing: 6) {
                CopyLinkButton(url: d.url)
                PillButton(title: "Remove", height: 26, fontSize: 12, foreground: Theme.red, expand: true) {
                    store.requestRemove(d.id)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    private func primaryLabel(_ d: Download) -> String {
        switch d.status {
        case .downloading: "Pause"
        case .paused: "Resume"
        case .queued: "Start Now"
        case .failed:
            switch d.issue {
            case .linkExpired: "Update Link…"
            case .fileChanged: "Restart Download"
            case .signIn: "Sign In…"
            case nil: "Retry"
            }
        case .completed: "Show in Finder"
        }
    }
}

private struct DetailRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).foregroundStyle(Theme.text2).frame(width: 62, alignment: .leading)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct CopyLinkButton: View {
    let url: URL
    @State private var copied = false

    var body: some View {
        PillButton(title: copied ? "Copied" : "Copy Link", height: 26, fontSize: 12, expand: true) {
            copyToPasteboard(url.absoluteString)
            copied = true
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}

/// The inspector's file name: click it (or choose Rename…) to edit in place.
/// Return saves, Escape cancels; the extension is left unselected, like Finder.
private struct EditableName: View {
    @Environment(DownloadStore.self) private var store
    let download: Download
    @State private var editing = false
    @State private var editingID: UUID?
    @State private var draft = ""
    @State private var error: String?

    var body: some View {
        Group {
            if editing {
                VStack(spacing: 4) {
                    RenameField(text: $draft, onCommit: commit, onCancel: cancel)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.field))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(error == nil ? Theme.accent : Theme.red, lineWidth: 1))
                    if let error {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.red)
                            .multilineTextAlignment(.center)
                    }
                }
            } else {
                Text(download.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .onTapGesture { begin() }
                    .help("Click to rename")
            }
        }
        .onChange(of: store.renaming, initial: true) { _, id in
            if id == download.id { begin() }
        }
        .onChange(of: download.id) { _, _ in
            // Selection moved while editing: save to the download that was being edited, like Finder.
            if editing, let id = editingID { store.rename(id, to: draft) }
            editing = false
            error = nil
        }
    }

    private func begin() {
        store.renaming = nil
        draft = download.name
        editingID = download.id
        error = nil
        editing = true
    }

    private func commit() {
        guard editing, let id = editingID, id == download.id else { return }
        if let message = store.rename(id, to: draft) {
            error = message
        } else {
            editing = false
            error = nil
        }
    }

    private func cancel() {
        editing = false
        error = nil
    }
}

/// Wrapping, centred AppKit text field that selects only the name's stem when it gains focus.
///
/// SwiftUI's TextField can't do this reliably: AppKit selects all text when a field becomes
/// first responder, overriding any selection set beforehand. Here the stem is selected
/// right after that happens, which is how Finder behaves.
private struct RenameField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void
    var onCancel: () -> Void

    final class Field: NSTextField {
        private var focusedOnce = false

        /// SwiftUI adds the view to the window only after makeNSView returns, so focus is taken here.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !focusedOnce else { return }
            focusedOnce = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window === window else { return }
                window.makeFirstResponder(self)
            }
        }

        override func becomeFirstResponder() -> Bool {
            guard super.becomeFirstResponder() else { return false }
            let name = stringValue as NSString
            let ext = name.pathExtension
            // "a.mkv.zip" → "a.mkv"; ".hidden" and "noext" → whole name.
            let stemLength = ext.isEmpty ? name.length : name.length - (ext as NSString).length - 1
            currentEditor()?.selectedRange = NSRange(location: 0, length: max(0, stemLength))
            return true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.stringValue = text
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 13, weight: .semibold)
        field.alignment = .center
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 4
        return field
    }

    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: Field, context: Context) -> CGSize? {
        let width = proposal.width ?? 220
        field.preferredMaxLayoutWidth = width
        let height = field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height ?? 17
        return CGSize(width: width, height: ceil(height))
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RenameField
        private var finished = false

        init(_ parent: RenameField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            // Names can't contain newlines (pasted text might).
            let clean = field.stringValue.replacingOccurrences(of: "\n", with: " ")
            if clean != field.stringValue { field.stringValue = clean }
            parent.text = clean
            field.invalidateIntrinsicContentSize()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.cancelOperation(_:)):
                finished = true
                parent.onCancel()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                // Stay in the field; commit either closes the editor or shows an error.
                parent.onCommit()
                return true
            default:
                return false
            }
        }

        /// Clicking or tabbing away saves, as in Finder.
        func controlTextDidEndEditing(_ note: Notification) {
            guard !finished else { return }
            parent.onCommit()
        }
    }
}
