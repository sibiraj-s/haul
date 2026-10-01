import SwiftUI

/// The in-window "Add Download" panel that drops down over a dimmed window.
struct AddDownloadPanel: View {
    @Environment(DownloadStore.self) private var store
    @State private var address = ""
    @State private var connections = AppSettings.shared.connections
    @State private var startNow = true
    /// Folder picked for this download; nil uses the default from Settings.
    @State private var folder: SavedFolder?
    /// When a file with the same name is already in the destination: replace it rather than keep both.
    @State private var replace = false
    @State private var probe: ProbeState = .idle
    /// Bumped to probe the link again (after signing in).
    @State private var probeAttempt = 0
    @State private var appeared = false
    @FocusState private var addressFocused: Bool

    private enum ProbeState {
        case idle, checking, ok(Probe.Info), failed(String), needsSignIn(realm: String?, digest: Bool)
    }

    /// The link leads to a web page and Settings says to skip those.
    private var blockedWebPage: Bool {
        if case .ok(let info) = probe { return info.isWebPage && store.settings.skipWebPages }
        return false
    }

    /// Everything typed or pasted, split on spaces and new lines.
    private var words: [String] {
        address.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The valid links among `words`, without repeats.
    private var links: [URL] {
        var seen = Set<URL>()
        return words.compactMap { Self.link($0) }.filter { seen.insert($0).inserted }
    }

    private static func link(_ text: String) -> URL? {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host() != nil else { return nil }
        return url
    }

    /// The link, when exactly one was entered.
    private var parsedURL: URL? { links.count == 1 ? links.first : nil }

    /// Several links pasted at once: they're added together without checking each first.
    private var isBatch: Bool { links.count > 1 }

    /// Batch links that aren't in the list yet.
    private var newLinks: [URL] { links.filter { store.existing(url: $0) == nil } }

    private var canConfirm: Bool { isBatch ? !newLinks.isEmpty : parsedURL != nil && !blockedWebPage }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.12)
                .contentShape(Rectangle())
                .onTapGesture {}
            panel
                .padding(.top, 64)
                .scaleEffect(appeared ? 1 : 0.98)
                .offset(y: appeared ? 0 : -10)
                .opacity(appeared ? 1 : 0)
        }
        .transition(.opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.18)) { appeared = true }
            // Pre-fill copied links, as long as the clipboard holds nothing but links.
            if let s = NSPasteboard.general.string(forType: .string) {
                let copied = s.split(whereSeparator: \.isWhitespace).map(String.init)
                if !copied.isEmpty, copied.count <= 200, copied.allSatisfy({ Self.link($0) != nil }) {
                    address = copied.joined(separator: "\n")
                }
            }
            addressFocused = true
        }
        .task(id: "\(probeAttempt) \(address)") {
            guard let url = parsedURL else { probe = .idle; return }
            probe = .checking
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                probe = .ok(try await Probe.run(url))
            } catch DownloadError.signInRequired(let realm, let digest) {
                probe = .needsSignIn(realm: realm, digest: digest)
            } catch {
                if !Task.isCancelled { probe = .failed(error.localizedDescription) }
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Download").font(.system(size: 14, weight: .bold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Address").font(.system(size: 12)).foregroundStyle(Theme.text2)
                TextField(text: $address, prompt: Text("Paste a link, or several on separate lines").foregroundStyle(Theme.text3), axis: .vertical) { EmptyView() }
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($addressFocused)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(minHeight: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.field))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.ctlB, lineWidth: 0.5))
            }

            if isBatch { batchPreview } else { preview }
            duplicateNotice

            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 10) {
                GridRow {
                    Text("Save to").foregroundStyle(Theme.text2).frame(width: 96, alignment: .leading)
                    FolderMenu(folder: $folder, defaultLabel: isBatch && store.settings.autoSort
                               ? "\(store.settings.baseFolder.lastPathComponent), by kind" : store.settings.folderLabel(for: kind))
                }
                GridRow {
                    Text("Connections").foregroundStyle(Theme.text2)
                    DesignSegmented(options: [1, 4, 8, 16].map { ($0, "\($0)") }, selection: $connections)
                }
                if !isBatch {
                    GridRow {
                        Color.clear.frame(width: 96, height: 1)
                        DesignCheckbox(title: "Start immediately", isOn: $startNow)
                    }
                }
            }

            HStack(spacing: 8) {
                Spacer()
                PillButton(title: "Cancel") { close() }
                    .keyboardShortcut(.cancelAction)
                PillButton(title: isBatch ? "Add \(newLinks.count) Download\(newLinks.count == 1 ? "" : "s")" : startNow ? "Download" : "Add to Queue",
                           prominent: true) { confirm() }
                    .keyboardShortcut(.defaultAction)
                    .opacity(canConfirm ? 1 : 0.45)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(width: 440)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.win))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.ctlB, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.26), radius: 40, y: 30)
    }

    /// The name the download will be saved under, as far as we know yet.
    private var fileName: String? {
        if case .ok(let info) = probe { return info.name }
        guard let url = parsedURL, !url.lastPathComponent.isEmpty, url.lastPathComponent != "/" else { return nil }
        return url.lastPathComponent
    }

    /// Warns when the link is already in the list, or the file already exists where it'll be saved.
    @ViewBuilder private var duplicateNotice: some View {
        if isBatch {
            let skipped = links.count - newLinks.count
            if skipped > 0 {
                notice(newLinks.isEmpty ? "All of these links are already in your list."
                       : "\(skipped) of these link\(skipped == 1 ? " is" : "s are") already in your list and will be skipped.") { EmptyView() }
            }
        } else if let url = parsedURL, let existing = store.existing(url: url) {
            notice("This link is already in your list (\(existing.status.label.lowercased())).") {
                PillButton(title: "Show") {
                    close()
                    store.reveal(existing.id)
                }
            }
        } else if case .ok = probe, !blockedWebPage, let name = fileName, let file = store.existingFile(named: name, in: folder) {
            notice("“\(name)” already exists in \(file.deletingLastPathComponent().lastPathComponent).") {
                DesignSegmented(options: [(false, "Keep Both"), (true, "Replace")], selection: $replace, minWidth: 64)
            }
        }
    }

    private func notice(_ text: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.orange)
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.orange.opacity(0.1)))
    }

    private var kind: FileKind {
        if case .ok(let info) = probe { return .of(info.name) }
        return .of(parsedURL?.lastPathComponent ?? "")
    }

    @ViewBuilder private var preview: some View {
        if let url = parsedURL {
            let name: String = if case .ok(let info) = probe { info.name } else { url.lastPathComponent.isEmpty || url.lastPathComponent == "/" ? url.host() ?? "" : url.lastPathComponent }
            HStack(spacing: 10) {
                FileIcon(ext: String(fileExtension(name).uppercased().prefix(4)), kind: .of(name), width: 28, height: 34, band: 11, fontSize: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                    Group {
                        switch probe {
                        case .idle, .checking:
                            Text("\(FileKind.of(name).label) · checking size… · \(url.host() ?? "")")
                        case .ok where blockedWebPage:
                            Text("This link opens a web page, not a file.").foregroundStyle(Theme.red)
                        case .ok(let info):
                            Text([FileKind.of(info.name).label,
                                  info.size.map(formatBytes) ?? "Unknown size",
                                  url.host() ?? "",
                                  info.acceptsRanges ? nil : "single connection"].compactMap { $0 }.joined(separator: " · "))
                        case .failed(let message):
                            Text(message).foregroundStyle(Theme.red)
                        case .needsSignIn:
                            Text("This server needs a username and password.").foregroundStyle(Theme.red)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                if case .checking = probe { ProgressView().controlSize(.small) }
                if case .needsSignIn(let realm, let digest) = probe {
                    PillButton(title: "Sign In…") {
                        if SignIn.prompt(for: url, realm: realm, digest: digest) { probeAttempt += 1 }
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.group))
        } else if !address.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Enter a valid http(s) link.").font(.system(size: 12)).foregroundStyle(Theme.text3)
        }
    }

    /// The links about to be added, with how many more there are.
    private var batchPreview: some View {
        let shown = 4
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(links.count) links").font(.system(size: 12, weight: .semibold))
            ForEach(links.prefix(shown), id: \.self) { url in
                let name = url.lastPathComponent.isEmpty || url.lastPathComponent == "/" ? url.host() ?? "" : url.lastPathComponent
                HStack(spacing: 8) {
                    FileIcon(ext: String(fileExtension(name).uppercased().prefix(4)), kind: .of(name), width: 16, height: 20, band: 7, fontSize: 4.5, radius: 3)
                    Text(name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(store.existing(url: url) != nil ? "In list" : url.host() ?? "")
                        .font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1)
                }
                .opacity(store.existing(url: url) != nil ? 0.5 : 1)
            }
            if links.count > shown {
                Text("and \(links.count - shown) more").font(.system(size: 11)).foregroundStyle(Theme.text2)
            }
            if words.count > links.count {
                let ignored = words.count - links.count
                Text("\(ignored) entr\(ignored == 1 ? "y isn't a link" : "ies aren't links") and will be ignored.")
                    .font(.system(size: 11)).foregroundStyle(Theme.text3)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.group))
    }

    private func close() {
        store.showAdd = false
    }

    private func confirm() {
        guard canConfirm else { return }
        if isBatch {
            // Queued rather than started, so the simultaneous-download limit applies.
            for url in newLinks {
                store.add(url: url, probe: nil, connections: connections, startNow: false, folder: folder)
            }
            return close()
        }
        guard let url = parsedURL else { return }
        var info: Probe.Info?
        if case .ok(let i) = probe { info = i }
        let replacing = replace && fileName.flatMap { store.existingFile(named: $0, in: folder) } != nil
        store.add(url: url, probe: info, connections: connections, startNow: startNow, folder: folder, replaceExisting: replacing)
        close()
    }
}

/// "Save to" pop-up: the default folder, recent folders, and Other… (a folder picker).
private struct FolderMenu: View {
    @Binding var folder: SavedFolder?
    let defaultLabel: String
    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        Menu {
            Button {
                folder = nil
            } label: {
                Label("\(defaultLabel) (Default)", systemImage: folder == nil ? "checkmark" : "folder")
            }
            let recents = settings.recentFolders.filter { $0.url != settings.baseFolder }
            if !recents.isEmpty {
                Section("Recent") {
                    ForEach(recents, id: \.url) { recent in
                        Button {
                            folder = recent
                        } label: {
                            Label(recent.url.lastPathComponent, systemImage: folder == recent ? "checkmark" : "folder")
                        }
                        .help(recent.url.path)
                    }
                }
            }
            Divider()
            Button("Other…") {
                Task {
                    if let picked = await SavedFolder.choose(message: "Choose where to save this download.") {
                        folder = picked
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Theme.accent)
                Text(folder?.url.lastPathComponent ?? defaultLabel).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.6)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .controlChrome(RoundedRectangle(cornerRadius: 6))
            .help(folder?.url.path ?? "Default folder (change it in Settings)")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
