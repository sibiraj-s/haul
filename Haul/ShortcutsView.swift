import SwiftUI

/// Help → Keyboard Shortcuts. Keep in step with `HaulCommands` and the list's key handling.
struct ShortcutsView: View {
    private static let sections: [(title: String, rows: [(keys: String, action: String)])] = [
        ("General", [
            ("⌘N", "Add Download"),
            ("⌘F", "Search"),
            ("⌘,", "Settings"),
            ("⌘0", "Show Main Window"),
        ]),
        ("Selected Download", [
            ("↑ ↓", "Select Previous or Next"),
            ("Space", "Pause, Resume or Start"),
            ("Return", "Rename"),
            ("⌘O", "Open"),
            ("⌘R", "Show in Finder"),
            ("⇧⌘C", "Copy Link"),
            ("⌘⌫", "Remove"),
        ]),
        ("All Downloads", [
            ("⌥⌘P", "Pause All"),
            ("⌥⌘R", "Resume All"),
            ("⇧⌘⌫", "Clear Completed"),
        ]),
        ("View", [
            ("⌘1 – ⌘5", "All, Active, Queued, Completed, Failed"),
            ("⌃⌘S", "Show or Hide Sidebar"),
            ("⌥⌘I", "Show or Hide Inspector"),
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Self.sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.text3)
                        VStack(spacing: 0) {
                            ForEach(section.rows, id: \.action) { row in
                                HStack {
                                    Text(row.action)
                                    Spacer()
                                    Text(row.keys)
                                        .foregroundStyle(Theme.text2)
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                if row.action != section.rows.last?.action {
                                    Rectangle().fill(Theme.sep).frame(height: 0.5).padding(.leading, 12)
                                }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.group))
                    }
                }
            }
            .padding(20)
        }
        .font(.system(size: 13))
        .foregroundStyle(Theme.text)
        .frame(width: 400)
        .frame(minHeight: 300, idealHeight: 600)
        .background(Theme.win)
    }
}

#Preview {
    ShortcutsView()
}
