import AllInOneIMEMac
import Foundation
import Testing

/// Apps built on Chromium or Electron (`ChromiumApps`), where the input method keeps a key the suggestion rows take from
/// the page: told by Electron's or a Chromium framework in their bundle, or a Chromium browser's bundle id (a web app of
/// one too); each app once.
struct ChromiumAppsTests {
    /// A bundle in a temporary folder with `frameworks` in its Contents/Frameworks.
    static func bundle(_ name: String, _ frameworks: [String], in folder: URL) throws -> URL {
        let app = folder.appendingPathComponent(name + ".app", isDirectory: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        for framework in frameworks {
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/Frameworks/" + framework),
                                                    withIntermediateDirectories: true)
        }
        return app
    }

    static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("chromium-apps-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func toldByTheFrameworksInTheBundle() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cases: [(String, [String], Bool)] = [
            ("Slack-like", ["Electron Framework.framework", "Squirrel.framework", "Mantle.framework"], true),
            ("Chrome-like", ["Google Chrome Framework.framework"], true),
            ("Chromium-like", ["Chromium Framework.framework"], true),
            ("Edge Beta-like", ["Microsoft Edge Beta Framework.framework"], true),
            ("Brave-like", ["Brave Browser Framework.framework"], true),
            ("Vivaldi-like", ["Vivaldi Framework.framework"], true),
            ("Opera-like", ["Opera Framework.framework"], true),
            ("CEF player", ["Chromium Embedded Framework.framework"], true),
            ("Native", ["Sparkle.framework"], false),
            ("Look-alike", ["Operations Framework.framework", "Electronics.framework", "Arcade Framework.framework"], false),
            ("Plain", [], false),
        ]
        for (name, frameworks, chromium) in cases {
            #expect(ChromiumApps.hasChromium(bundle: try Self.bundle(name, frameworks, in: folder)) == chromium, "\(name)")
        }
        #expect(!ChromiumApps.hasChromium(bundle: folder.appendingPathComponent("Missing.app")))
    }

    @Test func browsersByTheirBundleIDAndTheirWebApps() {
        for id in ["com.google.Chrome", "com.google.Chrome.canary", "org.chromium.Chromium", "com.microsoft.edgemac",
                   "com.brave.Browser", "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
                   "com.google.Chrome.app.abcdefghijklmnop", "com.microsoft.edgemac.app.abcdef"] {
            #expect(ChromiumApps.isBrowser(id), "\(id)")
        }
        for id in ["com.apple.Safari", "org.mozilla.firefox", "com.google.Chromecast", "com.google.Chrome.helper", "com.apple.MobileSMS"] {
            #expect(!ChromiumApps.isBrowser(id), "\(id)")
        }
    }

    /// Each app is told once and kept: a browser without its bundle looked for, another by its bundle as `locate` finds it;
    /// one not found, or no app, isn't one.
    @Test func eachAppIsToldOnce() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let chat = try Self.bundle("Chat", ["Electron Framework.framework"], in: folder)
        let notes = try Self.bundle("Notes", [], in: folder)
        final class Looked: @unchecked Sendable { var ids: [String] = [] }
        let looked = Looked()
        let known = ChromiumApps.Known { id in
            looked.ids.append(id)
            return ["com.example.chat": chat, "com.example.notes": notes][id]
        }
        let ids: [String?] = ["com.example.chat", "com.example.notes", "com.example.chat", "com.google.Chrome", "com.example.gone",
                              "com.example.gone", nil, ""]
        #expect(ids.map(known.isChromium) == [true, false, true, true, false, false, false, false])
        #expect(looked.ids == ["com.example.chat", "com.example.notes", "com.example.gone"], "\(looked.ids)")
    }
}
