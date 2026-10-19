#if os(Windows)
import AllInOneIMECore
@testable import AllInOneIMEEngineKit
import AllInOneIMEWire
import Foundation
import Testing

/// Level one through the engine (M5): a field's Composer types pinyin with the real librime and rime-ice's data, the
/// composition goes to the app and the candidates to the panel, in the settings' input languages, Shift switching them.
@Suite(.serialized)
struct PinyinTests {
    /// English first as for a new user, Chinese beside it (what `EngineSettings.fresh` has), Return as the action key.
    static let twoLanguages = #"{"inputLanguages": ["en", "zh"], "defaultInput": "en"}"#

    func client(_ json: String = twoLanguages) throws -> (EngineClient, URL) {
        let folder = try temporaryFolder("pinyin")
        let rime = try RimeFixture.rime.get()
        return (EngineClient(settings: try settingsFile(json, in: folder), rime: rime), folder)
    }

    @Test func aNewUserTypesEnglishAndShiftSwitchesToChinese() throws {
        let (client, folder) = try client()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(client.composer.engine is LockedRimeEngine)
        #expect(client.composer.inputLanguage == .english)
        // English: letters go straight in.
        #expect(client.type("hi") == [])
        client.tapShift()
        #expect(client.composer.inputLanguage == .chinese)
        #expect(client.panel.notices.count == 1)  // "中"
        client.tapShift()
        #expect(client.composer.inputLanguage == .english)
    }

    @Test func nihaoAndSpaceCommitsNihao() throws {
        let (client, folder) = try client(#"{"inputLanguages": ["zh", "en"], "defaultInput": "zh"}"#)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(client.composer.inputLanguage == .chinese)
        let outputs = client.type("nihao")
        // The pinyin is the app's composition; the candidates are the panel's.
        guard case let .composition(text, _, _, _) = outputs.first(where: { $0.op == "composition" }) else {
            Issue.record("no composition: \(outputs)")
            return
        }
        #expect(text.replacingOccurrences(of: " ", with: "") == "nihao")
        let model = try #require(client.panel.model)
        #expect(model.rows.first?.text == "你好")
        #expect(model.rows.first?.label == "1")
        #expect(model.highlighted == 0)
        #expect(!model.footer.isEmpty)
        client.space()
        #expect(client.committed == "你好")
        #expect(client.composition.isEmpty)
        #expect(client.panel.model == nil)
    }

    @Test func nihaoAndOneCommitsNihao() throws {
        let (client, folder) = try client(#"{"inputLanguages": ["zh", "en"], "defaultInput": "zh"}"#)
        defer { try? FileManager.default.removeItem(at: folder) }
        client.type("nihao")
        client.type("1")
        #expect(client.committed == "你好")
    }

    @Test func aClickOnARowPicksIt() throws {
        let (client, folder) = try client(#"{"inputLanguages": ["zh", "en"], "defaultInput": "zh"}"#)
        defer { try? FileManager.default.removeItem(at: folder) }
        client.type("shi")
        let model = try #require(client.panel.model)
        #expect(model.rows.count > 2)
        let second = model.rows[1].text
        // The window's click: the owner's session picks row 1, through the wire's push (`apply`).
        client.panel.owner?.choose(1)
        #expect(client.wait { client.committed == second })
        #expect(client.panel.model == nil)
    }

    @Test func theCandidatesFollowTheLayoutSetting() throws {
        let (client, folder) = try client(#"{"inputLanguages": ["zh"], "candidateLayout": "horizontal"}"#)
        defer { try? FileManager.default.removeItem(at: folder) }
        client.type("ni")
        #expect(client.panel.model?.horizontal == true)
    }

    @Test func aCommandWithPinyinInIt() throws {
        let (client, folder) = try client(#"{"inputLanguages": ["zh", "en"], "defaultInput": "zh"}"#)
        defer { try? FileManager.default.removeItem(at: folder) }
        // "@" then a command's name: the command list, numbered.
        client.type("@impro")
        let palette = try #require(client.panel.model)
        #expect(palette.rows.first?.text == "@improve")
        #expect(palette.rows.first?.label == "1")
    }

    @Test func withoutLibrimeTheEngineTypesLatinLetters() throws {
        let folder = try temporaryFolder("latin")
        defer { try? FileManager.default.removeItem(at: folder) }
        let client = EngineClient(settings: try settingsFile(Self.twoLanguages, in: folder), rime: nil)
        #expect(client.composer.engine is LatinEngine)
        client.tapShift()
        // Chinese isn't an input language without librime: Shift has nothing to switch to.
        #expect(client.composer.inputLanguage == .english)
        #expect(client.type("hello") == [])
    }

    @Test func whileLibrimeDeploysTheFieldTypesLatinLettersAndCommands() throws {
        let folder = try temporaryFolder("deploying")
        defer { try? FileManager.default.removeItem(at: folder) }
        // A librime not started yet (as while it deploys): no session to give.
        let location = EngineRime.Location(sharedData: folder, library: folder.appendingPathComponent("rime.dll"))
        let deploying = EngineRime(location: location, userData: folder, log: { _ in })
        let client = EngineClient(settings: try settingsFile(Self.twoLanguages, in: folder), rime: deploying)
        #expect(client.composer.engine is LatinEngine)
        // English goes in, and a command drafts, from the first key.
        #expect(client.type("hi ") == [])
        client.type("@improve hello")
        #expect(client.composer.draftCommand == .improve)
        #expect(!client.composition.isEmpty)
    }

    @Test func languagesWithoutTheirPackAreNoInputMode() throws {
        let (client, folder) = try client(#"{"inputLanguages": ["zh", "ko", "en", "hi"], "defaultInput": "zh"}"#)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(client.composer.inputLanguages == [.chinese, .english])
    }

    @Test func theSettingsFileIsReadAgainWhenItChanges() throws {
        let folder = try temporaryFolder("reload")
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = try settingsFile(#"{"actionKey": "enter"}"#, in: folder)
        #expect(settings.current.actionKey == .enter)
        Thread.sleep(forTimeInterval: 0.05)
        try Data(#"{"actionKey": "space", "inputLanguages": ["zh"]}"#.utf8).write(to: settings.url)
        // A new modification date (some file systems keep it to the second).
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: settings.url.path)
        #expect(settings.current.actionKey == .space)
        #expect(settings.current.inputLanguages == [.chinese])
    }

    @Test func aNewUserOnWindowsHasEnglishThenChinese() throws {
        let folder = try temporaryFolder("fresh")
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = EngineSettings(url: folder.appendingPathComponent("config.json"))  // no file
        let config = settings.current
        #expect(config.inputLanguages == [.english, .chinese])
        #expect(config.defaultInput == .english)
        // The provider is the Mac's for a new install: AllInOneIME Cloud.
        #expect(config.provider == Config.fresh.provider)
        #expect(settings.problem == nil)
    }

    @Test func theUsersLanguagesAreWindowsOwn() {
        // Windows' list, not Foundation's (which says "en-001" on Windows whatever the user has).
        let languages = EngineSettings.preferredLanguages
        #expect(!languages.isEmpty)
        #expect(languages.allSatisfy { $0.contains("-") || $0.count == 2 })
    }

    @Test func aBrokenSettingsFileReadsAsTheDefaultsAndSaysWhy() throws {
        let folder = try temporaryFolder("broken")
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = try settingsFile("{ not json", in: folder)
        #expect(settings.current.inputLanguages == [.english, .chinese])
        #expect(settings.problem != nil)
    }
}
#endif
