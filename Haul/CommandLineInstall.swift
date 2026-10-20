import AppKit

/// "Install / Uninstall Command Line Tool…". The sandbox keeps Haul out of /usr/local/bin, so
/// these show the Terminal command that links the `haul` tool inside the app there, or
/// removes the link, ready to copy.
@Observable
final class CommandLineInstall {
    static let shared = CommandLineInstall()
    static let link = "/usr/local/bin/haul"

    enum State: Equatable {
        case notInstalled
        /// /usr/local/bin/haul links to this copy of Haul's tool.
        case installed
        /// Something else is there: a link to another copy of Haul (its path), or a file (nil).
        case other(String?)
    }

    private(set) var state = State.notInstalled

    private init() {
        refresh()
        // The command runs in Terminal, so look again when the user comes back.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { CommandLineInstall.shared.refresh() }
        }
    }

    func refresh() {
        let fm = FileManager.default
        // attributesOfItem doesn't follow links, so a link whose app has gone still counts.
        let exists = (try? fm.attributesOfItem(atPath: Self.link)) != nil
        state = Self.state(exists: exists, destination: try? fm.destinationOfSymbolicLink(atPath: Self.link), app: Bundle.main.bundleURL)
    }

    static func state(exists: Bool, destination: String?, app: URL) -> State {
        guard exists else { return .notInstalled }
        guard let destination else { return .other(nil) }
        return destination == tool(in: app).path ? .installed : .other(destination)
    }

    static func tool(in app: URL) -> URL { app.appending(path: "Contents/Helpers/haul") }

    /// The command that puts `haul` on the PATH, pointing at the copy of Haul at `app`.
    static func installCommand(for app: URL) -> String {
        "sudo mkdir -p /usr/local/bin && sudo ln -sf \(quoted(tool(in: app).path)) \(link)"
    }

    static let uninstallCommand = "sudo rm \(link)"

    /// Single-quoted for the shell, so spaces and quotes in the path stay part of it.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Running from the disk image, or from where macOS runs a quarantined app it hasn't
    /// moved (App Translocation): a link there breaks once it's ejected or relaunched.
    static func isTemporary(_ app: URL) -> Bool {
        app.path.hasPrefix("/Volumes/") || app.path.contains("/AppTranslocation/")
    }

    func show() {
        refresh()
        let app = Bundle.main.bundleURL
        NSApp.activate()
        if state == .installed {
            Self.offer(Self.uninstallCommand, title: "Uninstall the haul Command",
                       message: "Haul can't remove it by itself. Paste this command into Terminal and enter your password.")
            return
        }
        guard !Self.isTemporary(app) else {
            let alert = NSAlert()
            alert.messageText = "Move Haul to Applications first"
            alert.informativeText = "Haul is running from the disk image or a temporary location, so the command-line tool would stop working. Drag Haul to Applications, open it from there, and try again."
            alert.runModal()
            return
        }
        let replacing: String? = switch state {
        case .other(let path?): "It replaces \(Self.link), which links to \(path)."
        case .other(nil): "It replaces the file at \(Self.link)."
        default: nil
        }
        Self.offer(Self.installCommand(for: app), title: "Install the haul Command",
                   message: ["Haul can't add it by itself. Paste this command into Terminal and enter your password. Then run haul add <link> to open links in Haul's Add panel.",
                             replacing].compactMap { $0 }.joined(separator: "\n\n"))
    }

    /// An alert showing `command`, with a button that copies it.
    private static func offer(_ command: String, title: String, message: String) {
        let field = NSTextField(wrappingLabelWithString: command)
        field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        field.isSelectable = true
        // NSAlert lays out its accessory view by frame, so size the label rather than constrain it.
        field.preferredMaxLayoutWidth = 260
        field.setFrameSize(field.fittingSize)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.accessoryView = field
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { copyToPasteboard(command) }
    }
}
