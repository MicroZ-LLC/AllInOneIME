import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

// Issue #72: while config.json doesn't parse (a comma typed twice, `"learnsEnglishWords": "false"`), the input method goes
// by `Config.default` (the Mac's `LiveConfig.current`), which isn't the user's settings. A field's session learns English
// words as if learning were on, in every app, with no hidden words, and the word goes into config.json: once the file
// parses again (`EnglishWords.Writer.retry`, told as the file is read anew), or at once where the file is still JSON (a
// value of the wrong type: the writer patches the JSON). Autocomplete's switch, off in the defaults, is seen turned off
// and on again (`AutocompleteStore.saw`), which starts every app over: an app where it stopped is gone from Privacy →
// Learned. Expected: nothing is learned against the user's settings, and
// nothing is reset or counted, until the file parses again (LiveSettings.swift: the defaults never record or reset
// anything; what does goes by `currentIfValid`).
//
// The sessions here get the services as the Mac gives them (`SessionServices.mac`, `Suggestions.services`): the settings
// are the file as it parses, else the defaults (`LiveConfig.current`); whether they are the user's is
// `SuggestionsServices.settingsValid` (`LiveConfig.currentIfValid != nil`); a word learned goes to an
// `EnglishWords.Writer` that writes into the file, tried again once the file is read anew and parses
// (`LiveConfig.parsedAnew`). The file is a temporary one, never the user's.

@Suite(.serialized)
struct Issue72Tests {
    static let textEdit = "com.apple.TextEdit"

    /// How the user broke config.json in an editor, and fixed it there.
    enum Breakage: String, CaseIterable, CustomTestStringConvertible, Sendable {
        /// A comma typed twice.
        case doubledComma
        /// `"learnsEnglishWords": "false"`: the switch's value in quotes.
        case quotedSwitch
        var testDescription: String { rawValue }

        /// The file's text broken this way.
        func broken(_ data: Data) throws -> Data {
            switch self {
            case .doubledComma:
                let text = try #require(String(data: data, encoding: .utf8))
                let comma = try #require(text.firstIndex(of: ","))
                return Data((text[...comma] + "," + text[text.index(after: comma)...]).utf8)
            case .quotedSwitch:
                var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
                object["learnsEnglishWords"] = (object["learnsEnglishWords"] as? Bool ?? true) ? "true" : "false"
                return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            }
        }

        /// The file's text as it is now (what was written into it meanwhile too, as an editor shows it once it changed
        /// on the disk) with the mistake put right.
        func fixed(_ data: Data) throws -> Data {
            switch self {
            case .doubledComma:
                let text = try #require(String(data: data, encoding: .utf8))
                return Data(text.replacingOccurrences(of: ",,", with: ",").utf8)
            case .quotedSwitch:
                var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
                object["learnsEnglishWords"] = (object["learnsEnglishWords"] as? String) == "true"
                return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            }
        }
    }

    /// A setting of the user's that keeps "kubectl" typed in TextEdit from being learned.
    enum Keeps: String, CaseIterable, CustomTestStringConvertible, Sendable {
        /// Learning turned off (`learnsEnglishWords: false`).
        case learningOff
        /// "kubectl" among the hidden words (`redaction.customWords`).
        case hiddenWord
        /// TextEdit set to use no AI (`AppProfile.noAI`).
        case noAIApp
        var testDescription: String { rawValue }

        func apply(to config: inout Config) {
            switch self {
            case .learningOff: config.learnsEnglishWords = false
            case .hiddenWord: config.redaction.customWords = ["kubectl"]
            case .noAIApp: config.appProfiles[Issue72Tests.textEdit] = AppProfile(noAI: true)
            }
        }
    }

    /// A config.json of the test's own, and what writes the words learned into it.
    final class File: @unchecked Sendable {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("issue72-\(UUID().uuidString)")
        var url: URL { folder.appendingPathComponent("config.json") }
        let writer = EnglishWords.Writer()

        init(_ config: Config) throws {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try config.write(to: url)
            #expect(try Config.load(from: url) == config, "the user's settings read back")
        }

        deinit { try? FileManager.default.removeItem(at: folder) }

        /// Broken in an editor: the file no longer parses.
        func breakIt(_ breakage: Breakage) throws {
            try breakage.broken(Data(contentsOf: url)).write(to: url)
            #expect(throws: (any Error).self, "\(breakage) doesn't parse") { try Config.load(from: self.url) }
        }

        /// Fixed in the editor: it parses again.
        func fix(_ breakage: Breakage) throws {
            try breakage.fixed(Data(contentsOf: url)).write(to: url)
            #expect((try? Config.load(from: url)) != nil, "\(breakage) fixed parses")
        }

        /// The file as it parses now (nil: it doesn't).
        var parsed: Config? { try? Config.load(from: url) }

        /// The services a field's session gets on the Mac, for this file.
        func services(store: AutocompleteStore = AutocompleteStore()) -> SessionServices {
            let (url, writer) = (url, writer)
            // `LiveConfig.current`: the defaults while the file doesn't parse.
            var services = SessionServices(loadSettings: { (try? Config.load(from: url)) ?? .default })
            // `LiveConfig.currentIfValid != nil`.
            services.suggestions.settingsValid = { (try? Config.load(from: url)) != nil }
            services.levelOne = { .engine(FakeEngine()) }
            services.englishDictionary = { EnglishDictionary(["hello", "world", "it", "ok"]) }
            services.learnEnglishWord = { writer.learn($0, at: url) }
            services.removeCandidate = { writer.remove($0, at: url) }
            services.unwrittenRemovals = { writer.unwrittenRemovals(at: url) }
            services.autocomplete = store
            return services
        }
    }

    /// The user's settings: pinyin and English, the interface in English.
    static var userSettings: Config {
        var config = Config.default
        config.uiLanguage = "en"
        config.setOrder([Language.chinese, .english])
        return config
    }

    /// A field of TextEdit's taking the focus.
    func focusTextEdit(_ services: SessionServices) -> FakeHost {
        let host = FakeHost(services: services)
        host.app = Self.textEdit
        host.focus()
        return host
    }

    /// `text` typed in English mode (a tap of Shift into it, unless it's in it), a key a character.
    func typeInEnglish(_ text: String, _ host: FakeHost) {
        if host.composer.inputLanguage != .english {
            host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.shift, .leftShift], timestamp: 100))
            host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [], timestamp: 100.1))
        }
        #expect(host.composer.inputLanguage == .english)
        for character in text {
            host.press(character == " " ? FakeHost.space : KeyEvent(keyCode: 0, characters: String(character)))
        }
    }

    /// "kubectl " typed twice in TextEdit while config.json doesn't parse, then the mistake fixed in the editor and a field
    /// focused (the file read anew: the writer told to try again, `LiveConfig.parsedAnew`): the user's settings, as the
    /// file has them all along, say it isn't learned, so it isn't in `englishWords`.
    @Test(arguments: Breakage.allCases, Keeps.allCases)
    func aWordTypedWhileTheFileDoesntParseIsntWrittenAgainstTheUsersSettings(_ breakage: Breakage, _ keeps: Keeps) async throws {
        try await withInterfaceLanguage("en") {
            var config = Self.userSettings
            keeps.apply(to: &config)
            let file = try File(config)
            let services = file.services()
            let host = focusTextEdit(services)

            try file.breakIt(breakage)
            host.focus()
            typeInEnglish("kubectl kubectl ok", host)
            file.writer.flush()
            #expect(file.parsed == nil, "still broken")

            try file.fix(breakage)
            host.focus()
            file.writer.retry()
            file.writer.flush()
            let words = try #require(file.parsed).englishWords
            #expect(!words.contains("kubectl"),
                    "config.json says \(keeps) (\(breakage) broke it for a while), and kubectl typed in TextEdit meanwhile was written into englishWords: \(words)")
        }
    }

    /// The same with nothing in the user's settings against it: a word learned while the file doesn't parse isn't lost
    /// (EnglishWordsTests' aWordWhoseWriteFailedIsKeptUntilTheFileTakesIt), written once the file parses and allows it.
    @Test(arguments: Breakage.allCases)
    func aWordTypedWhileTheFileDoesntParseIsWrittenOnceTheFileAllowsIt(_ breakage: Breakage) async throws {
        try await withInterfaceLanguage("en") {
            let config = Self.userSettings
            let file = try File(config)
            let host = focusTextEdit(file.services())

            try file.breakIt(breakage)
            host.focus()
            typeInEnglish("kubectl kubectl ok", host)
            file.writer.flush()
            #expect(file.parsed == nil, "still broken")

            try file.fix(breakage)
            host.focus()
            file.writer.retry()
            file.writer.flush()
            let words = try #require(file.parsed).englishWords
            #expect(words == ["kubectl"], "\(words)")
        }
    }

    /// Autocomplete on in config.json and stopped in TextEdit for want of use (Privacy → Learned lists it); the file
    /// broken for a while, a field focused meanwhile, then fixed and a field focused: the switch was on in the file all
    /// along, so TextEdit stays stopped, and no switch is counted.
    @Test(arguments: Breakage.allCases)
    func autocompleteIsntResetByAFileThatDoesntParse(_ breakage: Breakage) async throws {
        try await withInterfaceLanguage("en") {
            var config = Self.userSettings
            config.autocomplete = true
            config.learnsEnglishWords = false
            // A cloud provider of the user's own: nothing loads the on-device model as a field takes the focus.
            config.provider = .anthropic
            let file = try File(config)
            let store = AutocompleteStore()
            store.learn { learning in
                for _ in 0..<Autocomplete.Learning.window { _ = learning.record(false, in: Self.textEdit) }
            }
            let host = focusTextEdit(file.services(store: store))
            #expect(store.stopped(in: Self.textEdit) && store.metrics.turnedOn == 0, "stopped in TextEdit, the switch seen on")

            try file.breakIt(breakage)
            host.focus()
            try file.fix(breakage)
            host.focus()
            #expect(store.stopped(in: Self.textEdit),
                    "autocomplete was on in config.json all along (\(breakage) broke it for a while), and TextEdit started over: \(store.learning.apps)")
            #expect(store.metrics.turnedOn == 0 && store.metrics.turnedOffWithinADay == 0,
                    "a switch counted that the user never turned: on \(store.metrics.turnedOn), off within a day \(store.metrics.turnedOffWithinADay)")
        }
    }
}
