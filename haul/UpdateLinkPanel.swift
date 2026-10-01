import SwiftUI

/// Swaps a download's link (e.g. after a signed link expired), keeping progress when the
/// new link serves the same file.
struct UpdateLinkPanel: View {
    @Environment(DownloadStore.self) private var store
    let download: Download
    @State private var address = ""
    @State private var probe: ProbeState = .idle
    @State private var appeared = false
    @FocusState private var addressFocused: Bool

    private enum ProbeState {
        case idle, checking, ok(Probe.Info), failed(String)
    }

    private var parsedURL: URL? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host() != nil else { return nil }
        return url
    }

    private var check: DownloadStore.LinkCheck? {
        guard case .ok(let info) = probe else { return nil }
        return store.checkNewLink(download.id, info)
    }

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
            // Prefill with a link from the clipboard if it isn't the current one.
            if let s = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let url = URL(string: s), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
               url != download.url {
                address = url.absoluteString
            }
            addressFocused = true
        }
        .task(id: address) {
            guard let url = parsedURL else { probe = .idle; return }
            probe = .checking
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                probe = .ok(try await Probe.run(url))
            } catch {
                if !Task.isCancelled { probe = .failed(error.localizedDescription) }
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Update Link").font(.system(size: 14, weight: .bold))
                Text(download.received > 0
                     ? "Paste a new link to the same file. \(formatBytes(download.received)) already downloaded will be kept if it matches."
                     : "Paste a new link for this download.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                FileIcon(ext: download.ext, kind: download.kind, width: 28, height: 34, band: 11, fontSize: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(download.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                    Text("\(download.size.map(formatBytes) ?? "Unknown size") · was \(download.host)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.group))

            VStack(alignment: .leading, spacing: 6) {
                Text("New address").font(.system(size: 12)).foregroundStyle(Theme.text2)
                TextField(text: $address, prompt: Text("Paste a link").foregroundStyle(Theme.text3)) { EmptyView() }
                    .textFieldStyle(.plain)
                    .focused($addressFocused)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.field))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.ctlB, lineWidth: 0.5))
                verdict
            }

            HStack(spacing: 8) {
                Spacer()
                PillButton(title: "Cancel") { close() }
                    .keyboardShortcut(.cancelAction)
                switch check {
                case .resumable:
                    PillButton(title: download.received > 0 ? "Update & Resume" : "Update & Start", prominent: true) { apply(restart: false) }
                        .keyboardShortcut(.defaultAction)
                case .restartOnly:
                    PillButton(title: "Restart with New Link", prominent: true) { apply(restart: true) }
                        .keyboardShortcut(.defaultAction)
                case nil:
                    PillButton(title: "Update & Resume", prominent: true) {}
                        .opacity(0.45)
                        .allowsHitTesting(false)
                }
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

    /// One line under the field saying what the new link will do.
    @ViewBuilder private var verdict: some View {
        Group {
            if parsedURL == nil {
                if !address.trimmingCharacters(in: .whitespaces).isEmpty {
                    Label("Enter a valid http(s) link.", systemImage: "exclamationmark.circle").foregroundStyle(Theme.text3)
                }
            } else {
                switch probe {
                case .idle, .checking:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Checking \(parsedURL?.host() ?? "")…")
                    }
                    .foregroundStyle(Theme.text2)
                case .failed(let message):
                    Label(message, systemImage: "xmark.circle.fill").foregroundStyle(Theme.red)
                case .ok(let info):
                    switch check {
                    case .resumable(let warning?):
                        Label(warning, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.orange)
                    case .resumable(nil):
                        Label(download.received > 0
                              ? "Same file (\(info.size.map(formatBytes) ?? "?")) — will resume where it stopped."
                              : "Link works (\(info.size.map(formatBytes) ?? "unknown size")).",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.green)
                    case .restartOnly(let reason):
                        Label(reason, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.orange)
                    case nil:
                        EmptyView()
                    }
                }
            }
        }
        .font(.system(size: 12))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func close() {
        store.updatingLink = nil
    }

    private func apply(restart: Bool) {
        guard let url = parsedURL, case .ok(let info) = probe else { return }
        store.applyNewLink(download.id, url: url, info: info, restart: restart)
        close()
    }
}
