import AppKit

/// Asks for a username and password when a server answers with a sign-in challenge, and
/// saves them where URLSession looks for credentials, so the retried request sends them.
enum SignIn {
    /// Shows the prompt; returns false if cancelled.
    static func prompt(for url: URL, realm: String?, digest: Bool) -> Bool {
        let space = Probe.protectionSpace(for: url, realm: realm, digest: digest)
        let saved = URLCredentialStorage.shared.defaultCredential(for: space)
        // A saved login is sent automatically, so being asked again means it was rejected.
        let failed = saved != nil

        let user = NSTextField(string: saved?.user ?? "")
        user.placeholderString = "Username"
        let password = NSSecureTextField(string: "")
        password.placeholderString = "Password"
        let remember = NSButton(checkboxWithTitle: "Remember in Keychain", target: nil, action: nil)
        remember.state = saved?.persistence == .permanent || saved == nil ? .on : .off
        for field in [user, password] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 260).isActive = true
        }
        let stack = NSStackView(views: [user, password, remember])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setFrameSize(stack.fittingSize)

        let alert = NSAlert()
        alert.messageText = failed ? "Sign-in failed for \(space.host)" : "Sign in to \(space.host)"
        alert.informativeText = [
            failed ? "The username or password was rejected. Try again." : "This server needs a username and password to download the file.",
            realm.map { "The server says: “\($0)”." },
            url.scheme?.lowercased() == "http" && !digest ? "The connection isn't secure, so your password is sent unencrypted." : nil,
        ].compactMap { $0 }.joined(separator: " ")
        alert.accessoryView = stack
        alert.addButton(withTitle: "Sign In")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = user.stringValue.isEmpty ? user : password
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn, !user.stringValue.isEmpty else { return false }

        if let saved { URLCredentialStorage.shared.remove(saved, for: space) }
        let credential = URLCredential(user: user.stringValue, password: password.stringValue,
                                       persistence: remember.state == .on ? .permanent : .forSession)
        URLCredentialStorage.shared.setDefaultCredential(credential, for: space)
        return true
    }
}
