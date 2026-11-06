import AppKit
import SwiftUI

/// A small window listing the archives being extracted, like Archive Utility's: it comes up
/// when an extraction starts and goes away when the last one ends.
final class ExtractionPanel {
    static let shared = ExtractionPanel()

    private var panel: NSPanel?

    /// Shows the window without taking focus, as extractions often start in the background.
    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func close() {
        panel?.close()
    }

    private func makePanel() -> NSPanel {
        let hosting = NSHostingController(rootView: ExtractionList().environment(DownloadStore.shared))
        hosting.sizingOptions = .preferredContentSize
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: ExtractionList.width, height: 80),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.contentViewController = hosting
        panel.title = "Extracting"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior.insert(.fullScreenNone)
        panel.center()
        panel.setFrameAutosaveName("HaulExtraction")
        return panel
    }
}

private struct ExtractionList: View {
    static let width: CGFloat = 440
    @Environment(DownloadStore.self) private var store

    var body: some View {
        // Sized to its rows; a long batch scrolls instead of growing past the screen.
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.extractions) { extraction in
                    if extraction.id != store.extractions.first?.id { Divider() }
                    ExtractionRow(extraction: extraction)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Self.width)
        .frame(maxHeight: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ExtractionRow: View {
    @Environment(DownloadStore.self) private var store
    let extraction: DownloadStore.Extraction

    var body: some View {
        let d = extraction.download
        HStack(spacing: 12) {
            FileIcon(ext: d.ext, kind: d.kind, width: 32, height: 40, band: 13, fontSize: 8)
            VStack(alignment: .leading, spacing: 5) {
                Text("Extracting “\(d.name)”")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let fraction = extraction.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                Text(detail)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Button {
                store.stopExtraction(d.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Stop")
            .accessibilityLabel("Stop extracting \(d.name)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var detail: String {
        let size = extraction.download.size ?? extraction.download.received
        guard let fraction = extraction.fraction, size > 0 else { return formatBytes(size) }
        return "\(formatBytes(Int64(Double(size) * fraction))) of \(formatBytes(size))"
    }
}
