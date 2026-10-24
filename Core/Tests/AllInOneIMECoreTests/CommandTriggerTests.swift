import Foundation
import Testing
@testable import AllInOneIMECore

/// The symbols the command trigger can't be: what isn't one symbol, and the symbols typing needs where a trigger opens
/// the command list (a sentence's start, after a space, after Chinese). Refused in the config, in Settings (with what
/// works instead), and typing goes on as before.
@Suite(.serialized, MemorySecrets())
struct CommandTriggerTests {
    /// Not one ASCII symbol: letters, digits, whitespace, nothing, two symbols, another script's (the full-width ＠).
    static let notSymbols = ["a", "Z", "q", "0", "7", " ", "\t", "\n", "\u{3000}", "", "~~", "@@", "＠", "～", "é", "中", "~\u{301}"]
    /// pinyin's (rime-ice's) keys, its punctuation held after a digit, and every symbol it types as Chinese punctuation.
    static let typing = ["'", ";", "=", "-", ",", ".", "/", "[", "]", "\\", "`", ":", "?", "!", "\"", "(", ")", "<", ">",
                         "{", "}", "^", "_", "$"]

    @Test(arguments: notSymbols)
    func whatIsNotOneSymbolIsRefused(_ value: String) throws {
        #expect(Config.commandTriggerProblem(value) == .notASymbol)
        #expect(!Config.validCommandTrigger(value))
        try expectFallsBackToAtSign(value)
    }

    @Test(arguments: typing)
    func aSymbolTypingNeedsIsRefused(_ symbol: String) throws {
        #expect(Config.commandTriggerProblem(symbol) == .typingSymbol(symbol))
        #expect(!Config.validCommandTrigger(symbol))
        try expectFallsBackToAtSign(symbol)
    }

    /// Every ASCII symbol is one or the other: what is left types as itself.
    @Test func whatIsLeftIsTheSymbolsThatTypeAsThemselves() {
        #expect(Config.commandTriggers == ["#", "%", "&", "*", "+", "@", "|", "~"])
        let symbols = (33...126).compactMap(UnicodeScalar.init).map(String.init).filter { !$0.first!.isLetter && !$0.first!.isNumber }
        #expect(Set(symbols) == Set(Config.commandTriggers + Self.typing))
        for trigger in Config.commandTriggers { #expect(Config.commandTriggerProblem(trigger) == nil, "\(trigger)") }
    }

    /// Read from a file or set in the code, a refused value is @.
    func expectFallsBackToAtSign(_ value: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let data = try JSONEncoder().encode(["commandTrigger": value])
        #expect(try JSONDecoder().decode(Config.self, from: data).commandTrigger == "@", sourceLocation: sourceLocation)
        var config = Config.default
        config.commandTrigger = "~"
        config.commandTrigger = value
        #expect(config.commandTrigger == "@", sourceLocation: sourceLocation)
    }

    // MARK: Settings says why

    func service(_ text: String = "{}") throws -> (SettingsService, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("command-trigger-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data(text.utf8).write(to: url)
        let library = PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true))
        return (SettingsService(store: SettingsStore(configURL: url), platform: .windows, library: library), url)
    }

    /// A refused value changes nothing, and the problem says which symbol and what works instead; a good one is saved.
    @Test func settingsRefusesWithWhatWorksInstead() throws {
        let (service, url) = try service(#"{"commandTrigger": "~"}"#)
        for value in ["-", ",", "a", " "] {
            guard case let .failure(problem) = service.set("commandTrigger", to: .string(value)) else {
                Issue.record("\(value) taken")
                continue
            }
            #expect(problem.code == .badValue && problem.field == "commandTrigger")
            #expect(problem.message == Config.commandTriggerProblem(value)?.errorDescription)
            #expect(problem.message.contains("# % & * + @ | ~"), "\(problem.message)")
            if value == "-" || value == "," { #expect(problem.message.hasPrefix(value), "\(problem.message)") }
            #expect(try Config.load(from: url).commandTrigger == "~")
        }
        #expect((try? service.set("commandTrigger", to: .string("#")).get()) != nil)
        #expect(try Config.load(from: url).commandTrigger == "#")
    }

    /// In Simplified Chinese and English from the code, and translated in every other language the catalog has.
    @Test func theMessagesAreInEveryLanguage() throws {
        #expect(Config.CommandTriggerProblem.typingSymbol(",").message(language: "zh-Hans")
            == ", 打字时要用（拼音或中文标点），不能用来打开命令。可以用：# % & * + @ | ~")
        #expect(Config.CommandTriggerProblem.notASymbol.message(language: "en")
            == "The magic key must be one symbol, not a letter, digit or space. These work: # % & * + @ | ~")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Localizable.xcstrings"))
        let tables = try StringCatalog.tables(from: data)
        let keys = ["The magic key must be one symbol, not a letter, digit or space. These work: %@",
                    "%@ is needed for typing (pinyin or Chinese punctuation), so it can't open commands. These work: %@"]
        for language in StringCatalogCheck.languages {
            for key in keys {
                let translated = try #require(tables[language]?[key], "\(language): \(key)")
                #expect(translated != key && StringCatalogCheck.arguments(translated) == StringCatalogCheck.arguments(key),
                        "\(language): \(translated)")
            }
        }
    }

    // MARK: Typing goes on

    /// With a trigger that types as itself, pinyin's own keys and the punctuation after a space or Chinese reach the engine
    /// as before: only the trigger opens the list.
    @Test func otherSymbolsStillTypeWithAnAllowedTrigger() {
        for trigger in Config.commandTriggers {
            let composer = Composer(engine: FakeEngine(), actionKey: .enter)
            composer.commands = Command.builtins
            composer.commandTrigger = trigger
            composer.characterBeforeCaret = { "好" }
            for symbol in Self.typing {
                _ = composer.handleKeyDown(k(symbol))
                #expect(composer.draft.isEmpty && composer.paletteMatches.isEmpty, "\(trigger): \(symbol) opened the list")
            }
            #expect(composer.handleKeyDown(k(trigger)).handled && composer.draft == trigger && !composer.paletteMatches.isEmpty)
        }
    }
}
