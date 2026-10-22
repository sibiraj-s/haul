import AppKit

/// "Install / Uninstall Command Line Tool…": links the `haul` tool inside the app into
/// ~/.local/bin, which needs no password (the sandbox allows that folder through an
/// entitlement), and offers to add the folder to the shell's PATH. The link points into
/// Haul.app, so updating the app updates the tool.
@Observable
final class CommandLineInstall {
    static let shared = CommandLineInstall()

    enum State: Equatable {
        case notInstalled
        /// ~/.local/bin/haul links to this copy of Haul's tool.
        case installed
        /// It links to another copy of Haul (the path), which Install points here instead.
        case otherHaul(String)
        /// Something that isn't Haul's is there, so it's left alone.
        case taken
    }

    private(set) var state = State.notInstalled

    /// The real home folder; inside the sandbox, NSHomeDirectory() is the app's container.
    nonisolated static let home = URL(filePath: String(cString: getpwuid(getuid()).pointee.pw_dir), directoryHint: .isDirectory)
    static let folder = home.appending(path: ".local/bin", directoryHint: .isDirectory)
    static let link = folder.appending(path: "haul")

    private init() {
        refresh()
        repair()
        // Look again when the user comes back, in case the link changed meanwhile.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { CommandLineInstall.shared.refresh() }
        }
    }

    func refresh() {
        let fm = FileManager.default
        // attributesOfItem doesn't follow links, so a link whose app has gone still counts.
        let exists = (try? fm.attributesOfItem(atPath: Self.link.path)) != nil
        state = Self.state(exists: exists, destination: try? fm.destinationOfSymbolicLink(atPath: Self.link.path), app: Bundle.main.bundleURL)
    }

    static func state(exists: Bool, destination: String?, app: URL) -> State {
        guard exists else { return .notInstalled }
        guard let destination else { return .taken }
        if destination == tool(in: app).path { return .installed }
        return destination.hasSuffix(".app/Contents/Helpers/haul") ? .otherHaul(destination) : .taken
    }

    nonisolated static func tool(in app: URL) -> URL { app.appending(path: "Contents/Helpers/haul") }

    /// Running from the disk image, or from where macOS runs a quarantined app it hasn't
    /// moved (App Translocation): a link there breaks once it's ejected or relaunched.
    nonisolated static func isTemporary(_ app: URL) -> Bool {
        app.path.hasPrefix("/Volumes/") || app.path.contains("/AppTranslocation/")
    }

    /// Haul was moved or renamed after installing: point the broken link at this copy.
    private func repair() {
        guard case .otherHaul(let old) = state, !FileManager.default.fileExists(atPath: old),
              !Self.isTemporary(Bundle.main.bundleURL) else { return }
        try? link()
    }

    private func link() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if case .otherHaul = state { try fm.removeItem(at: Self.link) }
        try fm.createSymbolicLink(at: Self.link, withDestinationURL: Self.tool(in: Bundle.main.bundleURL))
        refresh()
    }

    func show() {
        refresh()
        NSApp.activate()
        switch state {
        case .installed: uninstall()
        case .taken:
            alert("~/.local/bin/haul Already Exists",
                  "Something other than Haul's command is there. Move or delete it, then try again.")
        case .notInstalled, .otherHaul: install()
        }
    }

    private func install() {
        guard !Self.isTemporary(Bundle.main.bundleURL) else {
            return alert("Move Haul to Applications First",
                         "Haul is running from the disk image or a temporary location, so the command would stop working. Drag Haul to Applications, open it from there, and try again.")
        }
        do {
            try link()
        } catch {
            return alert("Couldn't Install the haul Command", error.localizedDescription)
        }
        let shell = Shell.current
        if shell?.mentionsLocalBin(in: Self.home) == true {
            return alert("The haul Command Is Installed", "A symlink to the binary was added at ~/.local/bin/haul.")
        }
        offerPath(shell)
    }

    /// ~/.local/bin isn't in the shell's startup files: show the line to add, with a button
    /// that adds it for shells Haul knows.
    private func offerPath(_ shell: Shell?) {
        let line = shell?.line ?? Shell.exportLine
        let alert = NSAlert()
        alert.messageText = "Add ~/.local/bin to Your PATH"
        alert.informativeText = "Haul put the haul command in ~/.local/bin, which your shell doesn't search yet. Add this line to \(shell.map { "~/\($0.file)" } ?? "your shell's startup file"), then open a new Terminal window."
        alert.accessoryView = Self.codeLabel(line)
        if let shell { alert.addButton(withTitle: "Add to ~/\(shell.file)") }
        alert.addButton(withTitle: "Copy Line")
        alert.addButton(withTitle: "Not Now")
        let response = alert.runModal()
        if let shell, response == .alertFirstButtonReturn {
            do {
                try Shell.append(line, to: Self.home.appending(path: shell.file))
                self.alert("Added to ~/\(shell.file)", "Open a new Terminal window, then run haul add <link>.")
            } catch {
                copyToPasteboard(line)
                self.alert("Couldn't Change ~/\(shell.file)", "\(error.localizedDescription) The line is copied, so you can add it yourself.")
            }
        } else if response == (shell == nil ? .alertFirstButtonReturn : .alertSecondButtonReturn) {
            copyToPasteboard(line)
        }
    }

    private func uninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall the haul Command?"
        alert.informativeText = "This removes ~/.local/bin/haul."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.removeItem(at: Self.link)
        } catch {
            self.alert("Couldn't Uninstall the haul Command", error.localizedDescription)
        }
        refresh()
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private static func codeLabel(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        field.isSelectable = true
        // NSAlert lays out its accessory view by frame, so size the label rather than constrain it.
        field.preferredMaxLayoutWidth = 260
        field.setFrameSize(field.fittingSize)
        return field
    }
}

/// The user's login shell, as far as putting ~/.local/bin on its PATH goes. Paths are relative
/// to the home folder; Haul.entitlements lets the sandbox read them and write `file`.
nonisolated struct Shell: Equatable {
    /// Where Add puts the line.
    let file: String
    let line: String
    /// Where the shell might already set its PATH.
    let startupFiles: [String]

    static let exportLine = #"export PATH="$HOME/.local/bin:$PATH""#

    static func named(_ name: String) -> Shell? {
        switch name {
        case "zsh": Shell(file: ".zshrc", line: exportLine, startupFiles: [".zshenv", ".zprofile", ".zshrc", ".zlogin"])
        case "bash": Shell(file: ".bash_profile", line: exportLine, startupFiles: [".bash_profile", ".bashrc", ".profile"])
        case "fish": Shell(file: ".config/fish/config.fish", line: "fish_add_path ~/.local/bin",
                           startupFiles: [".config/fish/config.fish", ".config/fish/fish_variables"])
        default: nil
        }
    }

    static var current: Shell? {
        getpwuid(getuid())?.pointee.pw_shell.flatMap { named(URL(filePath: String(cString: $0)).lastPathComponent) }
    }

    /// Whether a startup file already mentions ~/.local/bin, however it's spelled.
    func mentionsLocalBin(in home: URL) -> Bool {
        startupFiles.contains { file in
            (try? String(contentsOf: home.appending(path: file), encoding: .utf8))?.contains(".local/bin") == true
        }
    }

    /// Adds `line` to the end of `file`, creating it if needed. Appending writes through a
    /// symlinked file (dotfiles kept in a repo) rather than replacing it.
    static func append(_ line: String, to file: URL) throws {
        let fm = FileManager.default
        let block = "# Added by Haul for the haul command\n\(line)\n"
        guard fm.fileExists(atPath: file.path) else { return try Data(block.utf8).write(to: file) }
        let handle = try FileHandle(forUpdating: file)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        // Start on a new line, with a blank one before, unless the file is empty.
        var prefix = ""
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            prefix = handle.readData(ofLength: 1) == Data("\n".utf8) ? "\n" : "\n\n"
            try handle.seekToEnd()
        }
        try handle.write(contentsOf: Data((prefix + block).utf8))
    }
}
