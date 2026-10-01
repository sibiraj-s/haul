import SwiftUI

/// Document glyph with a coloured band carrying the file extension.
struct FileIcon: View {
    let ext: String
    let kind: FileKind
    var width: CGFloat = 24
    var height: CGFloat = 30
    var band: CGFloat = 10
    var fontSize: CGFloat = 6.5
    var radius: CGFloat = 4

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack(alignment: .bottom) {
            shape.fill(Theme.page)
            Rectangle()
                .fill(kind.color)
                .frame(height: band)
                .overlay {
                    if !ext.isEmpty {
                        Text(ext)
                            .font(.system(size: fontSize, weight: .heavy))
                            .tracking(0.02 * fontSize)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.ctlB, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
    }
}

/// Thin capsule progress bar.
struct ThinProgressBar: View {
    let value: Double
    var track: Color = Theme.track
    var fill: Color = Theme.accent
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(track)
                .overlay(alignment: .leading) {
                    Capsule().fill(fill)
                        .frame(width: geo.size.width * min(1, max(0, value)))
                        .animation(.linear(duration: 0.5), value: value)
                }
                .clipShape(Capsule())
        }
        .frame(height: height)
    }
}

struct DownloadRow: View {
    @Environment(DownloadStore.self) private var store
    let download: Download
    let selected: Bool

    var body: some View {
        let d = download
        let fg: Color = selected ? .white : Theme.text
        let fg2: Color = selected ? .white.opacity(0.78) : d.status == .failed ? Theme.red : Theme.text2
        HStack(spacing: 10) {
            FileIcon(ext: d.ext, kind: d.kind)
            VStack(alignment: .leading, spacing: 3) {
                Text(d.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if d.status == .downloading || d.status == .paused {
                    ThinProgressBar(
                        value: d.progress,
                        track: selected ? .white.opacity(0.3) : Theme.track,
                        fill: selected ? .white : d.status == .paused ? Theme.text3 : Theme.accent
                    )
                }
                Text(statusLine(d, queuePosition: store.queuePosition(d.id)))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(fg2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let action = action(for: d) {
                Button {
                    store.toggle(d.id)
                } label: {
                    Image(systemName: action.symbol)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(fg)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(fg2, lineWidth: 1.2))
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable)
                .help(action.title)
            } else {
                Text(formatAdded(d.finished ?? d.added).replacingOccurrences(of: "Today, ", with: ""))
                    .font(.system(size: 11))
                    .foregroundStyle(fg2)
            }
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minHeight: 46)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.accent : .clear))
        .contentShape(Rectangle())
    }

    private func action(for d: Download) -> (symbol: String, title: String)? {
        switch d.status {
        case .downloading: ("pause.fill", "Pause")
        case .failed: d.issue == .signIn ? ("key.fill", "Sign In") : ("arrow.clockwise", "Retry")
        case .completed: nil
        case .paused, .queued: ("play.fill", "Resume")
        }
    }
}

func statusLine(_ d: Download, queuePosition: Int? = nil) -> String {
    let done = formatBytes(d.received)
    let total = d.size.map(formatBytes) ?? "unknown size"
    switch d.status {
    case .downloading:
        if d.speed <= 0 { return d.segments.isEmpty ? "Connecting…" : "\(done) of \(total) — connecting…" }
        return "\(done) of \(total) — \(formatBytes(d.speed))/s, \(formatDuration(d.remainingTime)) left"
    case .paused: return "Paused — \(done) of \(total)"
    case .queued:
        let waiting = queuePosition.map { "Waiting — #\($0) in queue" } ?? "Waiting"
        return d.size.map { "\(waiting) · \(formatBytes($0))" } ?? waiting
    case .failed:
        let error = d.error ?? "Unknown error"
        if d.retryAt != nil && AppSettings.shared.autoRetry {
            return "Retrying soon (\(d.retries) of \(DownloadStore.maxRetries)) — \(error)"
        }
        return "Failed at \(Int(d.progress * 100))% — \(error)"
    case .completed: return "\(formatBytes(d.size ?? d.received)) — \(d.host)"
    }
}
