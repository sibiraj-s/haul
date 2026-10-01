import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(DownloadStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @SceneStorage("showSidebar") private var showSidebar = true
    @SceneStorage("showInspector") private var showInspector = true
    @State private var window: NSWindow?

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SidebarPanel(window: window)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            VStack(spacing: 0) {
                HeaderBar(window: window, showSidebar: $showSidebar, showInspector: $showInspector)
                HStack(spacing: 0) {
                    DownloadList()
                    if showInspector {
                        InspectorView()
                            .frame(width: 272)
                            .overlay(alignment: .leading) { Rectangle().fill(Theme.sep).frame(width: 0.5) }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(maxHeight: .infinity)
                StatusBar()
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
        .background(Theme.win)
        .overlay {
            if store.showAdd {
                AddDownloadPanel()
            } else if let id = store.updatingLink, let d = store.items.first(where: { $0.id == id }) {
                UpdateLinkPanel(download: d)
            }
        }
        .animation(.easeOut(duration: 0.18), value: store.showAdd)
        .animation(.easeOut(duration: 0.18), value: store.updatingLink)
        .ignoresSafeArea()
        .background(WindowConfigurator { if window !== $0 { window = $0 } })
        .onAppear { store.openMainWindow = { openWindow(id: "main") } }
        .onChange(of: store.renaming) { _, id in
            if id != nil && !showInspector {
                withAnimation(.easeOut(duration: 0.2)) { showInspector = true }
            }
        }
    }
}

// MARK: - Sidebar

private struct SidebarPanel: View {
    @Environment(DownloadStore.self) private var store
    let window: NSWindow?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TrafficLights(window: window)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(WindowDragArea(window: window))

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    sectionTitle("Library", top: 6)
                    ForEach(SidebarFilter.library, id: \.self, content: row)
                    sectionTitle("Kinds", top: 14)
                    ForEach(FileKind.allCases) { row(.kind($0)) }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 10)
            }
            .scrollIndicators(.never)

            SponsorRow()
            DiskSpaceView()
        }
        .frame(width: 208)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.side))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.sep, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding([.leading, .top, .bottom], 8)
    }

    private func sectionTitle(_ title: String, top: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 8)
            .padding(.top, top)
            .padding(.bottom, 4)
    }

    private func row(_ f: SidebarFilter) -> some View {
        let n = store.count(f)
        return Button {
            store.filter = f
        } label: {
            HStack(spacing: 8) {
                Image(systemName: f.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 16)
                Text(f.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if n > 0 {
                    Text("\(n)")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text3)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(store.filter == f ? Theme.selg : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SponsorRow: View {
    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(.sponsor)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill").font(.system(size: 10)).foregroundStyle(Theme.red)
                Text("Sponsor")
                Spacer()
            }
            .font(.system(size: 12))
            .foregroundStyle(hovering ? Theme.text2 : Theme.text3)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Support Haul on GitHub Sponsors")
        .padding(.bottom, 6)
    }
}

private struct DiskSpaceView: View {
    @Environment(DownloadStore.self) private var store
    @State private var info: (name: String, free: Int64, total: Int64) = ("Macintosh HD", 0, 1)

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(info.name)
                Spacer()
                Text("\(formatBytes(info.free)) free")
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.text2)
            GeometryReader { geo in
                Capsule().fill(Theme.track)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Theme.text3)
                            .frame(width: geo.size.width * Double(info.total - info.free) / Double(max(1, info.total)))
                    }
                    .clipShape(Capsule())
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .overlay(alignment: .top) { Rectangle().fill(Theme.sep).frame(height: 0.5) }
        .task(id: store.items.filter { $0.status == .completed }.count) { refresh() }
    }

    private func refresh() {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let v = try? store.settings.downloadsFolder.resourceValues(forKeys: keys) else { return }
        info = (v.volumeName ?? "Macintosh HD", v.volumeAvailableCapacityForImportantUsage ?? 0, Int64(v.volumeTotalCapacity ?? 1))
    }
}

// MARK: - Header

private struct HeaderBar: View {
    @Environment(DownloadStore.self) private var store
    let window: NSWindow?
    @Binding var showSidebar: Bool
    @Binding var showInspector: Bool
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var store = store
        let settings = store.settings
        HStack(spacing: 10) {
            if !showSidebar {
                TrafficLights(window: window).padding(.trailing, 6)
            }
            iconButton("sidebar.left", help: "Toggle Sidebar") {
                withAnimation(.easeOut(duration: 0.2)) { showSidebar.toggle() }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(store.filter.title)
                    .font(.system(size: 14, weight: .bold))
                    .frame(height: 17)
                Text(store.subtitle)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                    .frame(height: 14)
            }
            .padding(.leading, 4)
            .fixedSize()

            WindowDragArea(window: window)

            Button {
                settings.limitOn.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: 13, weight: .medium))
                    Text(settings.limitOn ? "\(settings.limitMBps) MB/s" : "No Limit")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(settings.limitOn ? Theme.accent : Theme.text)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .capsuleControl()
            }
            .buttonStyle(.pressable)
            .help("Speed Limit")

            HStack(spacing: 0) {
                glyphButton("pause.fill", help: "Pause All") { store.pauseAll() }
                Rectangle().fill(Theme.ctlB).frame(width: 0.5, height: 14)
                glyphButton("play.fill", help: "Resume All") { store.resumeAll() }
            }
            .padding(.horizontal, 2)
            .frame(height: 28)
            .capsuleControl()

            iconButton("plus", help: "Add Download (⌘N)", weight: .medium) { store.showAdd = true }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text2)
                TextField(text: $store.query, prompt: Text("Search").foregroundStyle(Theme.text3)) { EmptyView() }
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 10)
            .frame(width: 180, height: 28)
            .capsuleControl()
            .background {
                Button("") { searchFocused = true }.keyboardShortcut("f").hidden()
            }

            iconButton("sidebar.right", help: "Toggle Inspector", color: showInspector ? Theme.accent : Theme.text) {
                withAnimation(.easeOut(duration: 0.2)) { showInspector.toggle() }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(height: 52)
    }

    private func iconButton(_ symbol: String, help: String, weight: Font.Weight = .regular, color: Color = Theme.text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: weight))
                .foregroundStyle(color)
                .frame(width: 32, height: 28)
                .capsuleControl()
        }
        .buttonStyle(.pressable)
        .help(help)
    }

    private func glyphButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 32, height: 28)
        }
        .buttonStyle(.pressable)
        .help(help)
    }
}

// MARK: - List

private struct DownloadList: View {
    @Environment(DownloadStore.self) private var store
    @FocusState private var focused: Bool
    /// Row being dragged to reorder the queue.
    @State private var dragging: UUID?

    var body: some View {
        let rows = store.visible
        let reorderable = store.filter == .queued && store.query.isEmpty
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { d in
                        DownloadRow(download: d, selected: d.id == store.selection)
                            .id(d.id)
                            .onTapGesture(count: 2) { d.status == .completed ? store.open(d) : store.toggle(d.id) }
                            .simultaneousGesture(TapGesture().onEnded {
                                dragging = nil
                                store.selection = d.id
                                focused = true
                            })
                            .contextMenu { RowMenu(download: d) }
                            .modifier(QueueReorder(id: d.id, enabled: reorderable, dragging: $dragging))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 2)
                .padding(.bottom, 8)
            }
            .overlay {
                if rows.isEmpty {
                    VStack(spacing: 4) {
                        Text("No Downloads").font(.system(size: 15, weight: .semibold))
                        Text("Nothing matches this view.").font(.system(size: 12))
                    }
                    .foregroundStyle(Theme.text3)
                }
            }
            // A drag released outside a row (or cancelled) never reaches a row's delegate.
            .onDrop(of: [.text], isTargeted: nil) { _ in dragging = nil; return false }
            .onChange(of: store.filter) { dragging = nil }
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(keys: [.upArrow, .downArrow, .space, .delete, .return]) { press in
                handle(press, rows: rows, proxy: proxy)
            }
        }
    }

    private func handle(_ press: KeyPress, rows: [Download], proxy: ScrollViewProxy) -> KeyPress.Result {
        let i = rows.firstIndex { $0.id == store.selection }
        switch press.key {
        case .downArrow, .upArrow:
            guard !rows.isEmpty else { return .ignored }
            let next = press.key == .downArrow ? min(rows.count - 1, (i ?? -1) + 1) : max(0, (i ?? 1) - 1)
            store.selection = rows[next].id
            proxy.scrollTo(rows[next].id)
            return .handled
        case .space:
            guard let id = store.selection else { return .ignored }
            store.toggle(id)
            return .handled
        case .return:
            // Return renames the selection, as in Finder.
            guard let id = store.selection else { return .ignored }
            store.beginRename(id)
            return .handled
        case .delete where press.modifiers.contains(.command):
            guard let id = store.selection else { return .ignored }
            store.requestRemove(id)
            return .handled
        default:
            return .ignored
        }
    }
}

/// Drag-to-reorder for rows in the Queued view. Rows move live while dragging over them.
private struct QueueReorder: ViewModifier {
    @Environment(DownloadStore.self) private var store
    let id: UUID
    let enabled: Bool
    @Binding var dragging: UUID?

    func body(content: Content) -> some View {
        if enabled {
            content
                .opacity(dragging == id ? 0.4 : 1)
                .onDrag {
                    dragging = id
                    return NSItemProvider(object: id.uuidString as NSString)
                }
                .onDrop(of: [.text], delegate: Delegate(target: id, store: store, dragging: $dragging))
        } else {
            content
        }
    }

    struct Delegate: DropDelegate {
        let target: UUID
        let store: DownloadStore
        @Binding var dragging: UUID?

        func dropEntered(info: DropInfo) {
            guard let dragging, dragging != target else { return }
            withAnimation(.easeOut(duration: 0.15)) { store.moveInQueue(dragging, to: target) }
        }

        func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

        func performDrop(info: DropInfo) -> Bool {
            dragging = nil
            return true
        }
    }
}

private struct RowMenu: View {
    @Environment(DownloadStore.self) private var store
    let download: Download

    var body: some View {
        switch download.status {
        case .completed:
            Button("Open") { store.open(download) }
            Button("Show in Finder") { store.revealInFinder(download) }
        case .downloading:
            Button("Pause") { store.toggle(download.id) }
        case .paused:
            Button("Resume") { store.toggle(download.id) }
        case .queued:
            Button("Start Now") { store.toggle(download.id) }
            if store.queue.count > 1 {
                Button("Start Next") { store.startNext(download.id) }
                    .disabled(store.queuePosition(download.id) == 1)
                Button("Move to End of Queue") { store.moveToEnd(download.id) }
                    .disabled(store.queuePosition(download.id) == store.queue.count)
            }
        case .failed:
            Button(download.issue == .signIn ? "Sign In…" : "Retry") { store.toggle(download.id) }
        }
        if download.status == .failed || download.status == .paused {
            Button("Restart from Beginning") { store.restart(download.id) }
        }
        Divider()
        Button("Rename…") { store.beginRename(download.id) }
        if download.status != .completed {
            Button("Update Link…") { store.beginUpdateLink(download.id) }
        }
        Button("Copy Link") { copyToPasteboard(download.url.absoluteString) }
        Divider()
        Button("Remove…", role: .destructive) { store.requestRemove(download.id) }
        if store.items.contains(where: { $0.status == .completed }) {
            Button("Clear Completed…") { store.requestClearCompleted() }
        }
    }
}

private struct StatusBar: View {
    @Environment(DownloadStore.self) private var store

    var body: some View {
        let s = store.settings
        let count = store.visible.count
        HStack(spacing: 14) {
            Text("\(count) item\(count == 1 ? "" : "s")")
            Spacer()
            Text(s.limitOn ? "Limited to \(s.limitMBps) MB/s · ↓ \(formatBytes(store.totalSpeed))/s" : "↓ \(formatBytes(store.totalSpeed))/s")
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .foregroundStyle(Theme.text2)
        .padding(.horizontal, 14)
        .frame(height: 26)
        .overlay(alignment: .top) { Rectangle().fill(Theme.sep).frame(height: 0.5) }
    }
}

func copyToPasteboard(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}

#Preview {
    ContentView()
        .environment(DownloadStore.shared)
        .frame(width: 1180, height: 720)
}
