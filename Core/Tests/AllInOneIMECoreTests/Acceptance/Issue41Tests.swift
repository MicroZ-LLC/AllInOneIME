import Foundation
import Testing
@testable import AllInOneIMECore

// Issue #41: Traditional candidates stop following the system language after a launch with a broken config. With
// `chineseCharacters` unset, Chinese is typed in the characters of the Mac's preferred languages (`Config.typedChinese`),
// read each time: the 繁/简 chip, the prompts and Translate as You Type follow a change at once, and the candidates follow
// once Rime's patch is written again for them (`RimeFuzzy.follow`, at every text field focused and when the system's
// languages change), which `ChineseCharacters.Written.changed` says when to do. Rime's start writes the patch, and records
// it as written, only when config.json parses (`LanguagePacks.start` through `LiveConfig.currentIfValid`). Launched while
// the file is mid-edit, nothing is recorded, and `changed` answers nil for as long as nothing is: the file fixed and the
// Mac switched from Simplified to Traditional, the chip says 繁 but the candidates stay Simplified until the settings or
// a sync write the patch, or the input method restarts. Expected: the candidates follow the system's languages.
//
// The input method's own code (an executable target) can't be imported here: its launch is `rimeStarts` below, as
// `LanguagePacks.start` and `RimeFuzzy.write` have it, and a text field focused is `Written.changed` asked with the
// config as it parses now, as `RimeFuzzy.follow` asks it (and writes the patch, deploying again, when it says so).

private enum Issue41 {
    struct Languages: UserLanguages { var preferred: [String] }

    /// `body` on a Mac whose preferred languages (System Settings → Language & Region) are `languages`.
    static func onMac<T>(preferring languages: [String], _ body: () throws -> T) rethrows -> T {
        var platform = Platform.current
        platform.userLanguages = Languages(preferred: languages)
        return try Platform.$override.withValue(platform) { try body() }
    }

    /// config.json with Chinese typed and no characters picked, and the same left mid-edit (a comma, no closing brace).
    static let fixed = #"{"inputLanguages": ["zh", "en"], "outputLanguages": ["en"]}"#
    static let midEdit = #"{"inputLanguages": ["zh", "en"], "outputLanguages": ["en"],"#

    /// A config folder of the test's own, with config.json holding `text`.
    static func configFile(_ text: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("issue41-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data(text.utf8).write(to: url)
        return url
    }

    /// Rime starting as the input method's launch starts it: the patch written for the config's characters, and recorded
    /// as written, only when the file parses; while it doesn't, the patch stays as it is and nothing is recorded.
    static func rimeStarts(configAt url: URL, written: ChineseCharacters.Written) {
        if let config = try? Config.load(from: url) { written.wrote(config.typedChinese) }
    }

    /// A text field focused (or the system's languages changed) with the file as it parses now: the characters the patch
    /// is to be written again for, nil when it stays.
    static func focus(configAt url: URL, written: ChineseCharacters.Written) -> ChineseCharacters? {
        guard let config = try? Config.load(from: url) else { return nil }
        return written.changed(config)
    }
}

struct Issue41Tests {
    /// Launched while config.json was mid-edit on a Simplified Mac, the file fixed, a few text fields focused, then the
    /// Mac's preferred language switched to Traditional: the chip and the prompts say Traditional, and the candidates are
    /// to follow (the patch written for them, once), and follow back to Simplified too.
    @Test(arguments: [("zh-Hant-TW", ChineseCharacters.taiwan), ("zh-HK", .hongkong), ("zh-Hant", .taiwan)])
    func theCandidatesFollowTheSystemsLanguagesAfterALaunchWithABrokenConfig(_ language: String,
                                                                          _ characters: ChineseCharacters) throws {
        let url = try Issue41.configFile(Issue41.midEdit)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let written = ChineseCharacters.Written()
        #expect(throws: (any Error).self) { try Config.load(from: url) }
        Issue41.onMac(preferring: ["zh-Hans-CN", "en-US"]) { Issue41.rimeStarts(configAt: url, written: written) }

        // Fixed in the editor, and typed with for a while on the Simplified Mac: the patch is Simplified's, whatever is
        // written for it now.
        try Data(Issue41.fixed.utf8).write(to: url)
        for _ in 0..<3 {
            let now = Issue41.onMac(preferring: ["zh-Hans-CN", "en-US"]) { Issue41.focus(configAt: url, written: written) }
            #expect(now == nil || now == .simplified, "a Simplified Mac's patch is Simplified's: \(String(describing: now))")
        }

        // System Settings → Language & Region: Traditional first. The rest of the app follows at once…
        let config = try Config.load(from: url)
        #expect(config.chineseCharacters == nil)
        #expect(Issue41.onMac(preferring: [language, "en-US"]) { config.typedChinese } == characters)
        #expect(Issue41.onMac(preferring: [language, "en-US"]) { config.typedLanguage(.chinese) } == characters.language)
        // …and so do the candidates: the patch written again for these characters, once.
        let switched = Issue41.onMac(preferring: [language, "en-US"]) { Issue41.focus(configAt: url, written: written) }
        #expect(switched == characters,
                "the Mac now prefers \(language): the chip says \(characters.rawValue), but the candidates are not to follow (\(String(describing: switched)))")
        let again = Issue41.onMac(preferring: [language, "en-US"]) { Issue41.focus(configAt: url, written: written) }
        #expect(again == nil, "asked once: \(String(describing: again))")
        // Back to Simplified: followed back.
        let back = Issue41.onMac(preferring: ["zh-Hans-CN", "en-US"]) { Issue41.focus(configAt: url, written: written) }
        #expect(back == .simplified, "the Mac prefers Simplified again: \(String(describing: back))")
    }

    /// Nothing recorded as written (Rime started while config.json didn't parse): the patch on disk is whatever an earlier
    /// launch left, so the characters typed now are to be written, Traditional ones on a Traditional Mac.
    @Test func nothingWrittenYetIsAChange() {
        let absent = Issue41.onMac(preferring: ["zh-Hant-TW"]) { () -> ChineseCharacters? in
            var config = Config.default
            config.inputLanguages = [.chinese, .english]
            config.chineseCharacters = nil
            return ChineseCharacters.Written().changed(config)
        }
        #expect(absent == .taiwan, "nothing written since Rime started, on a Mac preferring zh-Hant-TW: \(String(describing: absent))")
    }
}
