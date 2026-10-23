import CryptoKit
import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Code, an input next to the input languages (decision 22): a tap of Shift goes through the languages, then Code; its
/// rows come from its coding language's pack alone; picking a coding language whose pack isn't installed downloads it;
/// an app may start in Code; the long press of Shift turns Translate as You Type on or off at once (no chooser), and
/// says it can't in Code. The rig: Acceptance/SuggestionsAcceptanceTests.swift, SuggestionsCode.swift.
@Suite(.serialized, SuggestionsOneAtATime())
struct CodeInputTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    static func shipped(_ language: String) throws -> CodingLanguagePack { try SuggestionsCodingPacksTests.shipped(language) }

    /// What the session said since output `start`: its notices on their own and on the panel.
    static func said(_ field: SuggestionsField, since start: Int = 0) -> [String] {
        field.host.outputs.dropFirst(start).compactMap { output in
            switch output {
            case let .notice(text): return text
            case let .panel(model?): return model.detail
            default: return nil
            }
        }
    }

    // MARK: - Rotation

    /// A tap of Shift goes through the inputs added: the languages in their order, then Code, then the first again
    /// (中 → EN → Code → 中), each said as it comes ("Code (Python)"). Code types English's letters.
    @Test func aTapOfShiftGoesThroughTheLanguagesThenCode() async throws {
        try await inEnglish {
            let world = SuggestionsWorld(input: .chinese)
            world.addCode("python", packs: [try Self.shipped("python")])
            #expect(world.config.inputs == [.language(.chinese), .language(.english), .code])
            let field = world.field()
            #expect(field.host.composer.input == .language(.chinese))
            var seen: [Input] = [], notices: [[String]] = []
            for _ in 0..<3 {
                let before = field.host.outputs.count
                field.tapShift()
                seen.append(field.host.composer.input)
                notices.append(Self.said(field, since: before))
                if field.host.composer.coding {
                    #expect(field.host.composer.inputLanguage == .english, "Code types English's letters")
                    field.type("de")
                    #expect(field.host.marked.isEmpty && field.document == "de", "letters straight in: \(field.host.marked)")
                }
            }
            #expect(seen == [.language(.english), .code, .language(.chinese)], "\(seen)")
            #expect(notices == [["English"], ["Code (Python)"], ["Chinese"]], "\(notices)")
            field.type("nihao")
            #expect(field.host.marked == "nihao", "pinyin again: \(field.host.marked)")
        }
    }

    /// Code is an input only once its pack is installed, as a language is: without it a tap of Shift goes from the last
    /// language back to the first. With one language and Code, Shift goes between the two.
    @Test func codeIsAnInputOnceItsPackIsInstalled() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            world.addCode("java", packs: [try Self.shipped("python")])
            let field = world.field()
            #expect(field.host.composer.input == .language(.english))
            field.tapShift()
            #expect(field.host.composer.input == .language(.chinese), "no Java pack: no Code")
            field.tapShift()
            #expect(field.host.composer.input == .language(.english))

            let one = SuggestionsWorld()
            one.config.setOrder([Language.english])
            one.addCode("python", packs: [try Self.shipped("python")])
            let only = one.field()
            only.tapShift()
            #expect(only.host.composer.input == .code)
            only.tapShift()
            #expect(only.host.composer.input == .language(.english))
            // Code removed: a field in it goes back to its default input.
            only.tapShift()
            one.config.codingLanguage = nil
            only.host.send(.configChanged)
            #expect(only.host.composer.input == .language(.english) && !only.host.composer.coding)
        }
    }

    /// While Translate as You Type is on in the field, a tap of Shift goes through the languages only: it can't run in
    /// Code. A field in Code while it's on (an app that starts in Code) types as Code does, no chip, nothing collected.
    @Test func whileTranslateAsYouTypeIsOnShiftLeavesCodeOut() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            world.addCode("python", packs: [try Self.shipped("python")])
            let field = world.field()
            _ = field.host.session.apply(field.host.composer.setTranslateMode(TranslateMode.Session(target: .chinese)))
            var seen: [Input] = []
            for _ in 0..<3 {
                field.tapShift()
                seen.append(field.host.composer.input)
            }
            #expect(seen == [.language(.chinese), .language(.english), .language(.chinese)], "\(seen)")

            let code = world.codeField()
            _ = code.host.session.apply(code.host.composer.setTranslateMode(TranslateMode.Session(target: .chinese)))
            #expect(code.host.composer.coding && code.host.composer.translateModeChip() == nil)
            code.type("print")
            #expect(code.host.marked.isEmpty && code.document == "print", "no draft to translate: \(code.host.marked)")
        }
    }

    // MARK: - Rows

    /// Code's rows come from its coding language's pack alone, whatever else is installed: `if` in Python puts in
    /// Python's (a colon, the main guard among them), in Java Java's (braces); the language changed, a field's rows are
    /// the new one's.
    @Test func pythonAndJavaRowsComeFromTheirOwnPack() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            world.addCode("python", packs: [try Self.shipped("python"), try Self.shipped("java")])
            let python = world.codeField()
            python.type("if")
            #expect(python.settle { !python.rows.isEmpty }, "\(python.rows.map(\.comment))")
            #expect(python.rows.contains { $0.comment == "main guard" } && python.host.panel?.detail == "Python", "\(python.rows.map(\.comment))")
            #expect(python.press(SuggestionKeys.tab))
            #expect(python.document == "if :\n    ", "\(python.document.debugDescription)")

            world.config.codingLanguage = "java"
            let java = world.codeField()
            java.type("if")
            #expect(java.settle { !java.rows.isEmpty }, "\(java.rows.map(\.comment))")
            #expect(!java.rows.contains { $0.comment == "main guard" } && java.host.panel?.detail == "Java", "\(java.rows.map(\.comment))")
            #expect(java.press(SuggestionKeys.tab))
            #expect(java.document == "if () {\n    \n}", "\(java.document.debugDescription)")
        }
    }

    // MARK: - The menu downloads a pack

    /// Picking a coding language whose pack isn't installed (Code's menu) downloads it from the library, the newest this
    /// version may use, checked against the signed index; once it is in, Code is in that language: Shift reaches it, its
    /// rows are its pack's. One the library doesn't have: `notOffered`, nothing installed.
    @Test func pickingALanguageNotInstalledDownloadsItsPack() async throws {
        let lib = TestPackLibrary()
        defer { lib.cleanUp() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryStubProtocol.self]
        let store = CodingPackStore(directory: lib.root.appendingPathComponent("coding", isDirectory: true))
        let library = CodingPackLibrary(baseURL: URL(string: lib.base)!, publicKey: lib.key.publicKey.rawRepresentation,
                                        configuration: configuration, appVersion: "0.6.7", store: store)
        let data = try Data(contentsOf: SuggestionsCodingPacksTests.folder.appendingPathComponent("java.json"))
        let name = "java-\(UUID().uuidString.prefix(6)).json"
        LibraryStubProtocol.serve(lib.base + "assets/" + name, data)
        let java = try Self.shipped("java")
        let entries: [[String: Any]] = [
            ["language": "java", "title": "Java", "version": java.version, "url": "assets/" + name, "sha256": PluginLibrary.sha256(data),
             "size": data.count],
            ["language": "java", "title": "Java", "version": "9.0.0", "minAppVersion": "9.0.0", "url": "assets/later",
             "sha256": PluginLibrary.sha256(data), "size": data.count],
        ]
        let index = try JSONSerialization.data(withJSONObject: ["schema": 1, "packs": entries], options: [.sortedKeys])
        LibraryStubProtocol.serve(lib.base + "coding-packs.json", index)
        LibraryStubProtocol.serve(lib.base + "coding-packs.json.sig", Data(try lib.key.signature(for: index).base64EncodedString().utf8))

        let world = SuggestionsWorld()
        world.addCode("python", packs: [try Self.shipped("python")])
        let before = world.field()
        before.tapShift()
        #expect(before.host.composer.input == .code, "Python's Code")

        await #expect(throws: LanguagePackError.notOffered("rust")) { try await library.install(language: "rust") }
        #expect(store.installed().isEmpty)
        let pack = try await library.install(language: "java")
        #expect(pack == java && store.installed().map(\.language) == ["java"])
        // What Code's menu then does: Java is Code's language, the packs read again.
        world.packs = [try Self.shipped("python")] + store.installed()
        world.config.codingLanguage = "java"
        try await inEnglish {
            let field = world.field()
            field.tapShift()
            #expect(field.host.composer.input == .code && field.host.composer.messages.codeMode == "Code (Java)")
            field.type("if")
            #expect(field.settle { field.host.panel?.detail == "Java" }, "\(field.footer)")
        }
    }

    // MARK: - An app's starting input

    /// An app may start in Code (Settings → Apps): its fields do, where Code is among the inputs (its pack installed);
    /// other apps start in the default input. Written `"inputLanguage": "code"`, which a version without Code reads as
    /// none; the languages as before.
    @Test func anAppMayStartInCode() async throws {
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.codingLanguage = "python"
        config.changeProfile(for: "com.apple.mail") { $0.startingInput = .code }
        #expect(config.startingInput(in: "com.apple.mail", among: [.chinese, .english], code: true) == .code)
        #expect(config.startingInput(in: "com.apple.mail", among: [.chinese, .english], code: false) == .language(.chinese),
                "no Code here: the default")
        #expect(config.startingInput(in: "com.apple.mail", among: [.chinese, .english]) == .chinese)
        #expect(config.startingInput(in: "com.apple.TextEdit", among: [.chinese, .english], code: true) == .language(.chinese))

        let profile = try #require(config.profile(for: "com.apple.mail"))
        #expect(profile.inputLanguage == nil && !profile.isEmpty)
        let json = String(decoding: try JSONEncoder().encode(profile), as: UTF8.self)
        #expect(json == #"{"inputLanguage":"code"}"#, "\(json)")
        #expect(try JSONDecoder().decode(AppProfile.self, from: Data(json.utf8)) == profile)
        #expect(try JSONDecoder().decode(AppProfile.self, from: Data(#"{"inputLanguage":"zh"}"#.utf8)).startingInput == .language(.chinese))
        #expect(try JSONDecoder().decode(AppProfile.self, from: Data(#"{"inputLanguage":"tlh"}"#.utf8)).startingInput == nil)
        // A 0.6.6 file: its languages and apps as they were, no Code; written back, still none.
        let old = try JSONDecoder().decode(Config.self, from: Data(#"""
            {"inputLanguages": ["zh", "en"], "defaultInput": "zh", "appProfiles": {"com.apple.mail": {"inputLanguage": "en"}}}
            """#.utf8))
        #expect(old.inputs == [.language(.chinese), .language(.english)] && old.codingLanguage == nil)
        #expect(old.profile(for: "com.apple.mail")?.startingInput == .language(.english))
        let written = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        #expect(!written.contains("codingLanguage") && written.contains(#""inputLanguages":["zh","en"]"#), "\(written)")

        try await inEnglish {
            let world = SuggestionsWorld()
            world.addCode("python", packs: [try Self.shipped("python")])
            #expect(world.codeField(app: "com.apple.mail").host.composer.input == .code)
            #expect(world.field(app: "com.apple.TextEdit").host.composer.input == .language(.english))
            let missing = SuggestionsWorld()
            missing.addCode("java", packs: [try Self.shipped("python")])
            #expect(missing.codeField(app: "com.apple.mail").host.composer.input == .language(.english), "no Java pack: the default")
        }
    }

    /// Code syncs as the input languages do (each Mac downloads its pack), and an app's starting input Code with the app:
    /// a coding language's id is taken, anything else refused; Code removed on a Mac (the key gone) removes it on others.
    @Test func codeSyncsAsTheLanguagesDo() {
        let environment = ICloudSync.Environment()
        #expect(ICloudSync.category(of: "codingLanguage") == .settings)
        #expect(ICloudSync.problem("codingLanguage", .string("python"), environment: environment) == nil)
        #expect(ICloudSync.problem("codingLanguage", .string("Python 3"), environment: environment) == .unknownValue)
        #expect(ICloudSync.problem("codingLanguage", .number(1), environment: environment) == .wrongType)
        #expect(ICloudSync.problem("codingLanguage", nil, environment: environment) == nil, "Code removed")
        #expect(ICloudSync.problem("appProfiles.com.apple.mail", .object(["inputLanguage": .string("code")]), environment: environment) == nil)
        var config = Config.default
        config.codingLanguage = "go"
        #expect(ICloudSync.values(of: config, in: [.settings])["codingLanguage"] == .string("go"))
        config.codingLanguage = nil
        #expect(ICloudSync.values(of: config, in: [.settings])["codingLanguage"] == nil)
    }

    // MARK: - The long press of Shift

    /// A long press of Shift turns Translate as You Type on, another turns it off, as in 0.6.6: no chooser (no rows, no
    /// panel), the input as it was, and a digit after it typed as any; half way, the shell's hint.
    @Test func aLongPressTogglesTranslateAsYouTypeWithNoChooser() async {
        await inEnglish {
            let world = SuggestionsWorld(input: .chinese)
            let field = world.field { $0.suggestions.holdHint = { "Keep holding" } }
            let before = field.host.outputs.count
            field.host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.shift, .leftShift], timestamp: world.clock.timestamp))
            field.noteTimers()
            world.clock.advance(0.6)
            field.fireTimers()
            #expect(Self.said(field, since: before) == ["Keep holding"] && !world.translateAsYouType, "\(Self.said(field, since: before))")
            world.clock.advance(0.6)
            field.fireTimers()
            field.host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [], timestamp: world.clock.timestamp))
            #expect(world.translateAsYouType, "on")
            #expect(field.rows.isEmpty && field.host.panel == nil, "no chooser: \(field.rows.map(\.text))")
            #expect(field.host.composer.input == .language(.chinese), "the input as it was")
            field.holdShift()
            #expect(!world.translateAsYouType, "off")

            let english = SuggestionsWorld().field()
            english.holdShift()
            #expect(!english.press(SuggestionKeys.digit(2)) && english.document == "2", "a digit is typed: \(english.document)")
        }
    }

    /// In Code the long press says Translate as You Type isn't available there and changes nothing: it stays as it was,
    /// the input stays Code, and no hint comes half way.
    @Test func aLongPressInCodeSaysTranslateAsYouTypeIsUnavailable() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            world.addCode("python", packs: [try Self.shipped("python")])
            let field = world.codeField { $0.suggestions.holdHint = { "Keep holding" } }
            let before = field.host.outputs.count
            field.host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.shift, .leftShift], timestamp: world.clock.timestamp))
            field.noteTimers()
            world.clock.advance(0.6)
            field.fireTimers()
            world.clock.advance(0.6)
            field.fireTimers()
            field.host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [], timestamp: world.clock.timestamp))
            let said = Self.said(field, since: before)
            #expect(said.contains("Translate as You Type isn't available in Code") && !said.contains("Keep holding"), "\(said)")
            #expect(!world.translateAsYouType && field.host.composer.input == .code)
            world.translateAsYouType = true
            field.holdShift()
            #expect(world.translateAsYouType, "on before: still on")
        }
    }
}
