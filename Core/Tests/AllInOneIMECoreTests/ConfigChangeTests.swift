import Foundation
import Testing
@testable import AllInOneIMECore

/// A quick change of the config file outside Settings (the input menu's: a rewrite style, the output language, a switch,
/// This App's settings), made as Settings saves (`Config.change`, final review, low 7): only the keys it changed are
/// written, in place. A key this version doesn't know, a custom command it refused (decision 25), a later version's
/// command, an app's field it doesn't know and every other key keep their text. Each test has a config file of its own in
/// a temporary folder.
struct ConfigChangeTests {
    /// A config file a later version wrote, and one by hand: a key and an app's field this version doesn't know, a custom
    /// command of the wrong kind (refused) and one of a later type (kept aside), spacing of its own.
    static let file = """
        {
          "uiLanguage": "en",
          "rewriteStyles" : ["简洁"],
          "aLaterVersionsKey" : {"kept": [1, 2.50, "as is"]},
          "customCommands" : [
            {"name": "polite", "type": "prompt", "prompt": "Make it polite"},
            {"name": "wrong", "type": "suggestions", "prefix": "W-", "argv": ["/bin/echo"], "minChars": "two"},
            {"name": "later", "type": "aLaterType", "what": 1}
          ],
          "appProfiles" : {"com.apple.mail": {"noAI": true, "aLaterField": "kept"}}
        }

        """

    func url(_ text: String = Self.file) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("config-change-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data(text.utf8).write(to: url)
        return url
    }

    func text(_ url: URL) throws -> String { String(decoding: try Data(contentsOf: url), as: UTF8.self) }

    /// The menu's rewrite style toggled: that key written, everything else as the file has it, the key this version
    /// doesn't know and the refused command among it.
    @Test func aMenuChangeKeepsWhatThisVersionDoesntKnow() throws {
        let url = try url()
        let changed = try Config.change(at: url) { $0.rewriteStyles = SessionText.toggled("正式", in: $0.rewriteStyles) }
        #expect(changed.rewriteStyles == ["简洁", "正式"])
        let written = try text(url)
        // Written in place, as Settings writes a list.
        let expected = Self.file.replacingOccurrences(of: #""rewriteStyles" : ["简洁"]"#,
                                                      with: "\"rewriteStyles\" : [\n    \"简洁\",\n    \"正式\"\n  ]")
        #expect(written == expected, "\(written)")
        #expect(written.contains(#"{"kept": [1, 2.50, "as is"]}"#), "\(written)")
        #expect(written.contains(#"{"name": "wrong", "type": "suggestions", "prefix": "W-", "argv": ["/bin/echo"], "minChars": "two"}"#))
        #expect(written.contains(#"{"name": "later", "type": "aLaterType", "what": 1}"#))
        let config = try Config.load(from: url)
        #expect(config.rewriteStyles == ["简洁", "正式"])
        #expect(config.refusedCustomCommands.map(\.name) == ["wrong"] && config.unreadCustomCommands.count == 1)
        #expect(config.customCommands.map(\.name) == ["polite"])
    }

    /// This App's settings from the menu: the app's field this version doesn't know stays, and so does the rest.
    @Test func anAppsChangeKeepsItsUnknownField() throws {
        let url = try url()
        try Config.change(at: url) { $0.changeProfile(for: "com.apple.mail", dropsEmpty: true) { $0.typeOut = true } }
        let written = try text(url)
        #expect(written.contains(#""aLaterField""#) && written.contains(#""aLaterVersionsKey""#), "\(written)")
        #expect(try Config.load(from: url).profile(for: "com.apple.mail") == AppProfile(typeOut: true, noAI: true))
    }

    /// A change that changes nothing writes nothing; a file that can't be read is never written over (the change throws);
    /// with no file yet, the config is written whole, as a new user's.
    @Test func nothingChangedOrNothingToReadOrNoFile() throws {
        let url = try url()
        let before = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        try Config.change(at: url) { $0.rewriteStyles = ["简洁"] }
        #expect(try text(url) == Self.file)
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date == before)

        let broken = try self.url("{ not json")
        #expect(throws: ConfigError.self) { try Config.change(at: broken) { $0.typeOut = true } }
        #expect(try text(broken) == "{ not json")

        let none = try self.url().deletingLastPathComponent().appendingPathComponent("none.json")
        try Config.change(at: none) { $0.typeOut = true }
        #expect(try Config.load(from: none).typeOut)
    }
}
