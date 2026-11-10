import AppKit
import Testing

@testable import Haul

/// A Debug build runs next to the installed app, so the two must be easy to tell apart.
struct AppIdentityTests {
    @Test func debugBuildHasItsOwnName() throws {
        let id = try #require(Bundle.main.bundleIdentifier)
        #if DEBUG
            #expect(id.hasSuffix(".debug"))
            #expect(AppInfo.name == "Haul Dev")
        #else
            #expect(AppInfo.name == "Haul")
        #endif
    }

    @Test(arguments: [0.0, 0.5])
    func menuBarIconMarksDebugBuilds(progress: Double) throws {
        let image = MenuBarLabel.ringImage(progress: progress)
        #expect(image.isTemplate)
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let scale = CGFloat(rep.pixelsWide) / image.size.width
        // The dot's centre, at the lower right; NSBitmapImageRep counts rows from the top.
        let alpha = rep.colorAt(x: rep.pixelsWide - Int(3 * scale), y: rep.pixelsHigh - Int(3 * scale))?.alphaComponent ?? 0
        #if DEBUG
            #expect(alpha > 0.9)
        #else
            #expect(alpha < 0.1)
        #endif
    }

    /// The Share menu and Safari's extension list show the extensions under the app's name.
    @Test func extensionsShowTheAppName() throws {
        for name in ["SafariExtension", "ShareExtension"] {
            let plugin = try #require(Bundle(url: Bundle.main.bundleURL.appending(path: "Contents/PlugIns/\(name).appex")))
            #expect(plugin.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == AppInfo.name)
        }
    }
}
