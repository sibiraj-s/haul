import Foundation
import Testing
@testable import Haul

struct CommandLineInstallTests {
    private let app = URL(filePath: "/Applications/Haul.app")

    @Test func diskImageAndTranslocationAreTemporary() {
        #expect(CommandLineInstall.isTemporary(URL(filePath: "/Volumes/Haul/Haul.app")))
        #expect(CommandLineInstall.isTemporary(URL(filePath: "/private/var/folders/x/AppTranslocation/ABC/d/Haul.app")))
        #expect(!CommandLineInstall.isTemporary(app))
        #expect(!CommandLineInstall.isTemporary(URL(filePath: "/Users/me/Applications/Haul.app")))
    }

    @Test func onlyHaulsOwnLinksAreReplaced() {
        #expect(CommandLineInstall.state(exists: false, destination: nil, app: app) == .notInstalled)
        #expect(CommandLineInstall.state(exists: true, destination: "/Applications/Haul.app/Contents/Helpers/haul", app: app) == .installed)
        #expect(CommandLineInstall.state(exists: true, destination: "/Users/me/Old/Haul.app/Contents/Helpers/haul", app: app)
            == .otherHaul("/Users/me/Old/Haul.app/Contents/Helpers/haul"))
        #expect(CommandLineInstall.state(exists: true, destination: "/opt/tools/haul", app: app) == .taken)
        #expect(CommandLineInstall.state(exists: true, destination: nil, app: app) == .taken)
    }

    @Test func linkIsInTheRealHomeFolder() {
        #expect(!CommandLineInstall.home.path.contains("/Library/Containers/"))
        #expect(CommandLineInstall.link.path == CommandLineInstall.home.path + "/.local/bin/haul")
    }

    @Test func shells() {
        #expect(Shell.named("zsh")?.file == ".zshrc")
        #expect(Shell.named("zsh")?.line == #"export PATH="$HOME/.local/bin:$PATH""#)
        #expect(Shell.named("bash")?.file == ".bash_profile")
        #expect(Shell.named("fish")?.line == "fish_add_path ~/.local/bin")
        #expect(Shell.named("tcsh") == nil)
    }

    @Test func findsLocalBinInAnyStartupFile() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "haul-home-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let zsh = try #require(Shell.named("zsh"))
        #expect(!zsh.mentionsLocalBin(in: home))
        try "export EDITOR=vim\n".write(to: home.appending(path: ".zshrc"), atomically: true, encoding: .utf8)
        #expect(!zsh.mentionsLocalBin(in: home))
        try "path+=(~/.local/bin)\n".write(to: home.appending(path: ".zprofile"), atomically: true, encoding: .utf8)
        #expect(zsh.mentionsLocalBin(in: home))
    }

    @Test func appendsOnItsOwnLines() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "haul-rc-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let block = "# Added by Haul for the haul command\nLINE\n"

        let new = dir.appending(path: "new")
        try Shell.append("LINE", to: new)
        #expect(try String(contentsOf: new, encoding: .utf8) == block)

        let noNewline = dir.appending(path: "no-newline")
        try "alias x=y".write(to: noNewline, atomically: true, encoding: .utf8)
        try Shell.append("LINE", to: noNewline)
        #expect(try String(contentsOf: noNewline, encoding: .utf8) == "alias x=y\n\n" + block)

        let newline = dir.appending(path: "newline")
        try "alias x=y\n".write(to: newline, atomically: true, encoding: .utf8)
        try Shell.append("LINE", to: newline)
        #expect(try String(contentsOf: newline, encoding: .utf8) == "alias x=y\n\n" + block)

        // A symlinked startup file (dotfiles in a repo) stays a link; the line goes into its target.
        let target = dir.appending(path: "dotfiles-zshrc")
        try "export A=1\n".write(to: target, atomically: true, encoding: .utf8)
        let symlink = dir.appending(path: "zshrc-link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        try Shell.append("LINE", to: symlink)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: symlink.path) == target.path)
        #expect(try String(contentsOf: target, encoding: .utf8) == "export A=1\n\n" + block)
    }
}
