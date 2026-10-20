import Foundation
import Testing
@testable import Haul

struct CommandLineInstallTests {
    private let app = URL(filePath: "/Applications/Haul.app")

    @Test func linksTheToolInsideTheApp() {
        #expect(CommandLineInstall.installCommand(for: app)
            == "sudo mkdir -p /usr/local/bin && sudo ln -sf '/Applications/Haul.app/Contents/Helpers/haul' /usr/local/bin/haul")
        #expect(CommandLineInstall.uninstallCommand == "sudo rm /usr/local/bin/haul")
    }

    @Test func quotesSpacesAndQuotesInThePath() {
        #expect(CommandLineInstall.quoted("/Users/me/My Apps/Haul.app") == "'/Users/me/My Apps/Haul.app'")
        #expect(CommandLineInstall.quoted("/Users/me/Sam's/Haul.app") == #"'/Users/me/Sam'\''s/Haul.app'"#)
    }

    @Test func diskImageAndTranslocationAreTemporary() {
        #expect(CommandLineInstall.isTemporary(URL(filePath: "/Volumes/Haul/Haul.app")))
        #expect(CommandLineInstall.isTemporary(URL(filePath: "/private/var/folders/x/AppTranslocation/ABC/d/Haul.app")))
        #expect(!CommandLineInstall.isTemporary(app))
        #expect(!CommandLineInstall.isTemporary(URL(filePath: "/Users/me/Applications/Haul.app")))
    }

    @Test func installedOnlyWhenLinkedToThisCopy() {
        #expect(CommandLineInstall.state(exists: false, destination: nil, app: app) == .notInstalled)
        #expect(CommandLineInstall.state(exists: true, destination: "/Applications/Haul.app/Contents/Helpers/haul", app: app) == .installed)
        #expect(CommandLineInstall.state(exists: true, destination: "/Users/me/Old/Haul.app/Contents/Helpers/haul", app: app)
            == .other("/Users/me/Old/Haul.app/Contents/Helpers/haul"))
        #expect(CommandLineInstall.state(exists: true, destination: nil, app: app) == .other(nil))
    }
}
