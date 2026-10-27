import AllInOneIMEMac
import Foundation
import Testing

/// Apps built on Chromium or Electron (`ChromiumApps`), where the input method keeps a key the suggestion rows take from
/// the page: told by Electron's or a Chromium framework in their bundle, or a Chromium browser's bundle id (a web app of
/// one too); each app found once, one not found again after a while.
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
            // Chromium or CEF anywhere in the name of a framework or a library there.
            ("Chromium renamed", ["Sparkle.framework", "MyChromiumShell.framework"], true),
            ("CEF renamed", ["CEF.framework"], true),
            ("CEF helper", ["AppCEFHelper.framework"], true),
            ("libcef", ["libcef.dylib"], true),
            ("Native", ["Sparkle.framework"], false),
            ("Look-alike", ["Operations Framework.framework", "Electronics.framework", "Arcade Framework.framework"], false),
            // CEF in capitals only: "ceF" and "Cef" in other words aren't.
            ("Case look-alike", ["PlaceFramework.framework", "Cefalu.framework"], false),
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

    /// Each app found is told once and kept: a browser without its bundle looked for, another by its bundle as `locate`
    /// finds it; one not found, or no app, isn't one.
    @Test func eachAppIsToldOnce() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let chat = try Self.bundle("Chat", ["Electron Framework.framework"], in: folder)
        let notes = try Self.bundle("Notes", [], in: folder)
        final class Looked: @unchecked Sendable { var ids: [String] = [] }
        let looked = Looked()
        let known = ChromiumApps.Known(now: { 100 }) { id in
            looked.ids.append(id)
            return ["com.example.chat": chat, "com.example.notes": notes][id]
        }
        // A browser's other channel and a web app of one: told by their id too, no bundle looked for.
        let ids: [String?] = ["com.example.chat", "com.example.notes", "com.example.chat", "com.google.Chrome", "com.microsoft.edgemac.Beta",
                              "com.google.Chrome.app.abcdefgh", "com.example.gone", "com.example.gone", nil, ""]
        #expect(ids.map(known.isChromium) == [true, false, true, true, true, true, false, false, false, false])
        #expect(looked.ids == ["com.example.chat", "com.example.notes", "com.example.gone"], "\(looked.ids)")
    }

    /// An app not found is no for now, nothing kept: looked for again once 30 seconds have gone, not before (a key in the
    /// meantime costs no look-up); found then (installed since), it is told by its bundle and kept for good.
    @Test func anAppNotFoundIsLookedForAgainAfterAWhile() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let chat = try Self.bundle("Chat", ["Electron Framework.framework"], in: folder)
        final class World: @unchecked Sendable {
            var now: TimeInterval = 1000
            var installed: URL?
            var looked = 0
        }
        let world = World()
        let known = ChromiumApps.Known(now: { world.now }) { id in
            world.looked += 1
            return id == "com.example.chat" ? world.installed : nil
        }
        #expect(!known.isChromium("com.example.chat") && world.looked == 1, "not found: no")
        world.installed = chat
        world.now += 10
        #expect(!known.isChromium("com.example.chat") && world.looked == 1, "within 30 seconds: no, not looked for")
        world.now += ChromiumApps.Known.retry - 10
        #expect(known.isChromium("com.example.chat") && world.looked == 2, "30 seconds on: looked for again, found")
        world.installed = nil
        world.now += 1000
        #expect(known.isChromium("com.example.chat") && world.looked == 2, "found once: kept, not looked for again")
        // Each app not found waits on its own.
        #expect(!known.isChromium("com.example.other") && world.looked == 3)
        world.now += 1
        #expect(!known.isChromium("com.example.other") && world.looked == 3)
    }

    /// What a key the rows took is marked with during it in a Chromium page (`ChromiumApps.keyMark`), `text` the field's,
    /// read back as Chromium's view does (nil past its end, half of a surrogate pair as U+FFFD): the selection itself; the
    /// whole character before the caret, an emoji's surrogate pair, a letter with its accent, an emoji with its skin tone or
    /// a family's joiners, a flag; a space at the field's start; nothing where the field tells no caret or reads nothing
    /// back.
    @Test func whatAKeyIsMarkedWith() {
        func reader(_ text: String) -> (NSRange) -> String? {
            { range in
                let units = Array(text.utf16)
                guard range.location >= 0, NSMaxRange(range) <= units.count else { return nil }
                return String(decoding: units[range.location..<NSMaxRange(range)], as: UTF16.self)
            }
        }
        func mark(_ text: String, caret: Int, selected: Int = 0) -> ChromiumApps.KeyMark? {
            ChromiumApps.keyMark(caret: NSRange(location: caret, length: selected), read: reader(text))
        }
        #expect(mark("Hello world", caret: 6, selected: 5) == .selection(NSRange(location: 6, length: 5), "world"))
        #expect(mark("ab 👍", caret: 0, selected: 5) == .selection(NSRange(location: 0, length: 5), "ab 👍"), "from the start")
        #expect(mark("#17", caret: 3) == .character(NSRange(location: 2, length: 1), "7"))
        #expect(mark("ok 👍", caret: 5) == .character(NSRange(location: 3, length: 2), "👍"), "a surrogate pair")
        #expect(mark("👍", caret: 2) == .character(NSRange(location: 0, length: 2), "👍"), "the field's only character")
        #expect(mark("cafe\u{301}", caret: 5) == .character(NSRange(location: 3, length: 2), "e\u{301}"), "a letter and its accent")
        #expect(mark("hi 👍🏽", caret: 7) == .character(NSRange(location: 3, length: 4), "👍🏽"), "a skin tone")
        let family = "👨‍👩‍👧‍👦"
        #expect(mark("a" + family, caret: 12) == .character(NSRange(location: 1, length: 11), family), "joined by ZWJ")
        #expect(mark("flags 🇯🇵", caret: 10) == .character(NSRange(location: 6, length: 4), "🇯🇵"))
        #expect(mark("", caret: 0) == .space && mark("tail", caret: 0) == .space, "the field's start")
        // A character longer than the window read back: nothing.
        let long = "a" + String(repeating: "\u{301}", count: 40)
        #expect(mark(long, caret: 41) == nil)
        #expect(ChromiumApps.keyMark(caret: NSRange(location: NSNotFound, length: 0), read: reader("abc")) == nil, "no caret")
        #expect(ChromiumApps.keyMark(caret: NSRange(location: 3, length: 0), read: { _ in nil }) == nil, "nothing read back")
        #expect(ChromiumApps.keyMark(caret: NSRange(location: 1, length: 2), read: { _ in "a" }) == nil, "the selection cut short")
        // Half of a surrogate pair before the caret reads back as U+FFFD.
        #expect(ChromiumApps.keyMark(caret: NSRange(location: 1, length: 0), read: { _ in "\u{FFFD}" }) == nil)
    }
}
