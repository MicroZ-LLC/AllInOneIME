import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Suggestions v1, spec 2 as decision 22 has it: Code, an input next to the input languages (`Config.codingLanguage`,
/// `Config.inputs`, a field's `Input`), which replaced coding mode and decision 13's chooser. A tap of Shift goes through
/// the inputs (中 → EN → Code), Code only once its coding language's pack is installed; an app may start in Code; the
/// long press of Shift toggles Translate as You Type at once, as in 0.6.6 (no chooser, ever), and in Code says it isn't
/// available there. In Code: that coding language's pack alone (its keywords and snippets; what is offered: spec 6.13)
/// and the field's own words (none where it tells none: 6.16), Return picking a row as in an IDE in every app (decision
/// 31), no Translate as You Type, no English words learned. The keys of decision 31 (the first row chosen from the start,
/// picked with Tab or Return, ↓↑ moving, never a digit: 6.1) and the insertion of spec 1.4 (a snippet as its trigger in
/// code editors and terminals: 6.10, 6.11), a snippet's line breaks,
/// its later lines indented as the caret's line (6.19), and its caret: at its first tab stop in reading order, `$0` or a
/// numbered one left empty with its mirrors, where the field reports ranges, else every stop's text in and the caret at
/// the end (6.21, 6.23). The rig: SuggestionsAcceptanceTests.swift.
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsCodingAcceptanceTests {
    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    static func pack(_ name: String) throws -> CodingLanguagePack {
        try JSONDecoder().decode(CodingLanguagePack.self, from: SuggestionsFixtures.data(name, in: "packs"))
    }

    /// A world with the Code input in Python, the Python pack installed (and `more` packs too); fields start in `input`.
    static func coding(input: Language = .english, more: [CodingLanguagePack] = []) throws -> SuggestionsWorld {
        let world = SuggestionsWorld(input: input)
        world.addCode("python", packs: [try pack("python")] + more)
        return world
    }

    /// A world with the Code input in `pack`'s language, `pack` its only one installed.
    static func coding(_ pack: CodingLanguagePack) -> SuggestionsWorld {
        let world = SuggestionsWorld()
        world.addCode(pack.language, packs: [pack])
        return world
    }

    /// The texts of the rows, each with its comment.
    static func texts(_ field: SuggestionsField) -> [String] { field.rows.map { $0.text + " " + $0.comment } }

    /// What the session said since output `start`: its notices, on their own or on the panel.
    static func said(_ field: SuggestionsField, since start: Int) -> [String] {
        field.host.outputs.dropFirst(start).compactMap { output in
            switch output {
            case let .notice(text): return text
            case let .panel(model?): return model.detail
            default: return nil
            }
        }
    }

    /// Whether the panel shows anything like decision 13's chooser: rows, with nothing typed for any.
    static func chooser(_ field: SuggestionsField) -> Bool { !field.rows.isEmpty }

    /// Translate as You Type on in `field`, as the shell turns it on there (on in every field once on).
    static func translateAsYouTypeOn(_ field: SuggestionsField) {
        _ = field.host.session.apply(field.host.composer.setTranslateMode(TranslateMode.Session(target: .chinese)))
    }

    /// Where the caret is once a row went in at the end of the field: the text before it, the field's text up to where the
    /// session's last `moveCaret` since output `since` put it (back from the end of what went in), else all of it.
    static func beforeCaret(_ field: SuggestionsField, since: Int) -> String {
        let back = field.host.outputs.dropFirst(since).compactMap { output -> Int? in
            if case let .moveCaret(back, _) = output { return back } else { return nil }
        }.last ?? 0
        let text = field.document as NSString
        return text.substring(to: max(0, text.length - back))
    }

    /// What the field says with a key where it reports no ranges: no selection, nowhere for a caret.
    static func withoutRanges(_ context: FieldContext) -> FieldContext {
        var context = context
        context.read.subtract([.selectedRange, .selection])
        context.selectedRange = nil
        context.selection = nil
        return context
    }

    /// Types `text` in a field that reports no ranges with any key (the app types each character), then presses Tab
    /// there: what the session put in with it, and the outputs it gave then.
    static func tabWithoutRanges(after text: String, in field: SuggestionsField, until shown: () -> Bool) -> (String, [SessionOutput]) {
        for character in text {
            field.host.send(.key(SuggestionKeys.key(character), withoutRanges(field.host.context)))
            field.host.document.append(character)
            field.noteTimers()
        }
        let rows = field.settle(until: shown)
        #expect(rows, "\(texts(field))")
        let before = field.host.outputs.count
        field.host.send(.key(SuggestionKeys.tab, withoutRanges(field.host.context)))
        let outputs = Array(field.host.outputs.dropFirst(before))
        let put = outputs.compactMap { output -> String? in
            if case let .commit(text) = output { return text } else if case let .commitAfterKey(text) = output { return text }
            return nil
        }.joined()
        return (put, outputs)
    }

    // MARK: - Shift: a tap goes through the inputs, a long press toggles Translate as You Type

    /// A long press of Shift turns Translate as You Type on at once, as in 0.6.6; another turns it off. Nothing opens in
    /// between: no chooser (decision 22).
    @Test func aLongPressOfShiftTogglesTranslateAsYouTypeDirectly() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let field = world.field()
            field.holdShift()
            #expect(world.translateAsYouType, "on at once")
            #expect(!Self.chooser(field), "no chooser: \(Self.texts(field))")
            field.holdShift()
            #expect(!world.translateAsYouType, "off again")
            #expect(!Self.chooser(field), "\(Self.texts(field))")
        }
    }

    /// A tap of Shift goes through the inputs as through the input languages: 中 → EN → Code → 中, each said as it comes
    /// (Code by its name). No chooser. In Code the letters go straight in (no pinyin) and its rows come; back in Chinese,
    /// pinyin as usual.
    @Test func aTapOfShiftGoesThroughTheInputs() async throws {
        try await inEnglish {
            let world = try Self.coding(input: .chinese)
            #expect(world.config.inputs == [.language(.chinese), .language(.english), .code], "\(world.config.inputs)")
            let field = world.field()
            #expect(field.host.composer.input == .language(.chinese))
            var seen: [Input] = []
            for _ in 0..<3 {
                let before = field.host.outputs.count
                field.tapShift()
                field.fireTimers()
                let input = field.host.composer.input
                seen.append(input)
                #expect(!Self.chooser(field), "\(input): \(Self.texts(field))")
                if input == .code {
                    #expect(Self.said(field, since: before).contains { $0.contains("Code") }, "\(Self.said(field, since: before))")
                    field.type("pr")
                    #expect(field.host.marked.isEmpty && field.document == "pr", "straight in: \(field.host.marked)")
                    #expect(field.settle { field.shown(["print"]) == ["print"] }, "Code's rows: \(Self.texts(field))")
                    field.press(SuggestionKeys.space)
                }
            }
            #expect(seen == [.language(.english), .code, .language(.chinese)], "\(seen)")
            #expect(!world.translateAsYouType, "a tap toggles nothing")
            field.type("nihao")
            #expect(field.host.marked == "nihao", "pinyin again: \(field.host.marked)")
        }
    }

    /// In Code the long press says Translate as You Type isn't available there and turns nothing on: the field stays in
    /// Code. Out of Code (a tap of Shift on to a language), it turns it on.
    @Test func inCodeTheLongPressSaysTranslateAsYouTypeIsntAvailable() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let field = world.codeField()
            #expect(field.host.composer.input == .code)
            let before = field.host.outputs.count
            field.holdShift()
            let said = Self.said(field, since: before)
            #expect(said.contains { $0.contains("Translate as You Type") }, "it says so: \(said)")
            #expect(!world.translateAsYouType, "not on in Code")
            #expect(field.host.composer.input == .code && !Self.chooser(field), "\(Self.texts(field))")
            field.tapShift()
            #expect(field.host.composer.input != .code)
            field.holdShift()
            #expect(world.translateAsYouType, "in a language: on")
        }
    }

    /// No chooser in any input, ever: after a long press in Chinese, English or Code no rows show, and the keys that
    /// picked in it are the app's (a digit typed, ↓ and Return passed on).
    @Test func noChooserEver() async throws {
        try await inEnglish {
            let world = try Self.coding(input: .chinese)
            let field = world.field()
            var inputs: [Input] = []
            for _ in 0..<3 {
                let input = field.host.composer.input
                inputs.append(input)
                field.holdShift()
                field.pause(5)  // what it said gone
                #expect(!Self.chooser(field), "\(input): \(Self.texts(field))")
                if input != .language(.chinese) {
                    let start = field.document
                    #expect(!field.press(SuggestionKeys.digit(2)) && field.document == start + "2", "\(input): \(field.document)")
                    for key in [SuggestionKeys.down, SuggestionKeys.enter] {
                        #expect(!field.press(key), "\(input): the app's")
                    }
                    field.press(SuggestionKeys.space)
                }
                world.translateAsYouType = false
                field.tapShift()
            }
            #expect(inputs == [.language(.chinese), .language(.english), .code], "\(inputs)")
        }
    }

    /// A long press of Shift isn't a tap: the input stays as it was, pinyin composing after it; Code stays Code.
    @Test func aLongPressOfShiftDoesntSwitchTheInput() async throws {
        try await inEnglish {
            let world = try Self.coding(input: .chinese)
            let field = world.field()
            #expect(field.host.composer.input == .language(.chinese))
            field.holdShift()
            #expect(field.host.composer.input == .language(.chinese), "still pinyin")
            field.type("nihao")
            #expect(field.host.marked == "nihao", "\(field.host.marked)")

            let code = world.codeField(app: "com.apple.TextEdit")
            code.holdShift()
            #expect(code.host.composer.input == .code, "still Code")
            code.type("pr")
            #expect(code.host.marked.isEmpty && code.document == "pr", "\(code.host.marked)")
        }
    }

    /// Shift held to type capitals is no long press, however long: nothing toggles, nothing is said of Translate as You
    /// Type (in Code neither). Held on its own, it toggles.
    @Test func shiftHeldWhileTypingTogglesNothing() async throws {
        try await inEnglish {
            let world = try Self.coding()
            for field in [world.field(), world.codeField(app: "com.apple.TextEdit")] {
                let input = field.host.composer.input
                let before = field.host.outputs.count
                field.host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.shift, .leftShift], timestamp: world.clock.timestamp))
                field.noteTimers()
                world.clock.advance(0.2)
                field.press(SuggestionKeys.key("H"))
                world.clock.advance(1.5)
                field.fireTimers()
                field.host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [], timestamp: world.clock.timestamp))
                field.noteTimers()
                #expect(!world.translateAsYouType && !Self.chooser(field), "\(input): \(Self.texts(field))")
                #expect(!Self.said(field, since: before).contains { $0.contains("Translate as You Type") },
                        "\(input): \(Self.said(field, since: before))")
                #expect(field.host.composer.input == input)
            }
            let field = world.field(app: "com.apple.Notes")
            field.holdShift()
            #expect(world.translateAsYouType, "held on its own, it toggles")
        }
    }

    /// Translate as You Type never runs in Code (decision 22): with it on in a field, whenever a tap of Shift has the
    /// field in Code there is no chip and the letters go straight in, nothing collected to translate; a field that starts
    /// in Code while it is on types as Code does.
    @Test func translateAsYouTypeNeverRunsInCode() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let field = world.field()
            Self.translateAsYouTypeOn(field)
            for _ in 0..<3 {
                field.tapShift()
                guard field.host.composer.input == .code else { continue }
                #expect(field.host.composer.translateModeChip() == nil, "no chip in Code")
                let start = field.document
                field.type("pr")
                #expect(field.host.marked.isEmpty && field.document == start + "pr", "straight in: \(field.host.marked)")
                field.press(SuggestionKeys.space)
            }

            let code = world.codeField(app: "com.apple.TextEdit")
            Self.translateAsYouTypeOn(code)
            #expect(code.host.composer.input == .code && code.host.composer.translateModeChip() == nil)
            code.type("print")
            #expect(code.host.marked.isEmpty && code.document == "print", "nothing to translate: \(code.host.marked)")
        }
    }

    // MARK: - Code is a field's input

    /// Code is a field's input, not a mode of every field: a field switched to it leaves the others as they are, each
    /// new field (of any app) starting in its default input, pinyin here. A tap of Shift still goes on from Code, and
    /// pinyin works as usual then.
    @Test func codeIsAFieldsInputNotAModeOfEveryField() async throws {
        try await inEnglish {
            let world = try Self.coding(input: .chinese)
            let first = world.field()
            first.tapShift()
            first.tapShift()
            #expect(first.host.composer.input == .code)
            for app in [SuggestionsApps.editor, "com.apple.TextEdit", SuggestionsApps.chrome] {
                let field = world.field(app: app)
                #expect(field.host.composer.input == .language(.chinese), "\(app): \(field.host.composer.input)")
                field.type("nihao")
                #expect(field.host.marked == "nihao", "\(app): pinyin (\(field.host.marked))")
            }
            first.tapShift()
            first.type("nihao")
            #expect(first.host.marked == "nihao", "pinyin after a tap of Shift (\(first.host.marked))")
        }
    }

    /// Code is an input only once its coding language's pack is installed, as a language is once its pack is: Java
    /// picked but not downloaded, a tap of Shift goes through the languages only. Once the pack is in, Shift reaches Code
    /// (in the field there, and in a new one).
    @Test func aTapOfShiftSkipsCodeUntilItsPackIsInstalled() async throws {
        try await inEnglish {
            let world = SuggestionsWorld()
            world.addCode("java", packs: [try Self.pack("python")])
            let field = world.field()
            var seen: [Input] = []
            for _ in 0..<4 {
                field.tapShift()
                seen.append(field.host.composer.input)
            }
            #expect(!seen.contains(.code), "no Java pack, no Code: \(seen)")
            #expect(Set(seen) == [.language(.chinese), .language(.english)], "\(seen)")

            world.packs.append(try Self.pack("java"))
            field.host.send(.configChanged)
            seen = []
            for _ in 0..<3 {
                field.tapShift()
                seen.append(field.host.composer.input)
            }
            #expect(seen.contains(.code), "its pack in: \(seen)")
            let other = world.field(app: "com.apple.TextEdit")
            other.tapShift()
            #expect(other.host.composer.input == .code, "English → Code: \(other.host.composer.input)")
        }
    }

    /// An app may start in Code (Settings → Apps, the input menu's This App): written as the app's `"inputLanguage":
    /// "code"`, read back the same. Its fields start in Code, other apps' in the default input; from Code a tap of Shift
    /// goes on to the first language. Where Code's pack isn't installed, the app starts in the default input.
    @Test func anAppMayStartInCode() async throws {
        try await inEnglish {
            let world = try Self.coding(input: .chinese)
            let mail = "com.apple.mail"
            world.config.changeProfile(for: mail) { $0.startingInput = .code }
            let json = String(decoding: try JSONEncoder().encode(world.config), as: UTF8.self)
            #expect(json.contains(#""inputLanguage":"code""#) && json.contains(#""codingLanguage":"python""#), "\(json)")
            let read = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
            #expect(read.profile(for: mail)?.startingInput == .code && read.codingLanguage == "python")
            #expect(read.inputs == [.language(.chinese), .language(.english), .code], "\(read.inputs)")

            let field = world.field(app: mail)
            #expect(field.host.composer.input == .code, "\(field.host.composer.input)")
            field.type("pr")
            #expect(field.host.marked.isEmpty && field.document == "pr", "\(field.host.marked)")
            #expect(field.settle { field.shown(["print"]) == ["print"] }, "Code's rows: \(Self.texts(field))")
            field.press(SuggestionKeys.space)
            let notes = world.field(app: "com.apple.Notes")
            #expect(notes.host.composer.input == .language(.chinese))
            notes.type("nihao")
            #expect(notes.host.marked == "nihao", "\(notes.host.marked)")
            field.tapShift()
            #expect(field.host.composer.input == .language(.chinese), "Code → 中: \(field.host.composer.input)")

            let missing = SuggestionsWorld(input: .chinese)
            missing.addCode("java", packs: [try Self.pack("python")])
            missing.config.changeProfile(for: mail) { $0.startingInput = .code }
            #expect(missing.field(app: mail).host.composer.input == .language(.chinese), "no Java pack: the default input")
        }
    }

    /// Changing Code's coding language (the input menu, Settings → Input) changes a field's rows at once: the field
    /// stays in Code, and the next token's rows are the new language's pack's (Java's `if` with its braces, not Python's).
    @Test func changingCodesLanguageChangesItsRowsAtOnce() async throws {
        try await inEnglish {
            let world = try Self.coding(more: [try Self.pack("java")])
            let field = world.codeField()
            field.type("if")
            #expect(field.settle { Self.texts(field).contains { $0.contains("if block") } }, "Python's: \(Self.texts(field))")
            field.press(SuggestionKeys.space)
            world.config.codingLanguage = "java"
            field.host.send(.configChanged)
            #expect(field.host.composer.input == .code, "still Code")
            field.type("if")
            #expect(field.settle { Self.texts(field).contains { $0.contains("if statement") } }, "Java's: \(Self.texts(field))")
            #expect(!Self.texts(field).contains { $0.contains("if block") }, "\(Self.texts(field))")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "if if () {\n    \n}", "\(field.document.debugDescription)")
        }
    }

    /// Removing the pack of Code's language removes Code: Settings → Input's installed packs (the settings document's)
    /// take the pack out and Code with it (no `codingLanguage`, Code no more among the inputs); a field in Code then is in
    /// its default input, no Code rows, and Shift goes through the languages only.
    @Test func removingThePackOfCodesLanguageRemovesCode() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("code-removed-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let plugins = folder.appendingPathComponent("plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data(#"{"inputLanguages": ["zh", "en"], "codingLanguage": "python"}"#.utf8).write(to: url)
        let packs = CodingPackStore(directory: folder.appendingPathComponent("CodingPacks", isDirectory: true))
        _ = try packs.keep(SuggestionsFixtures.data("python", in: "packs"), language: "python")
        let service = SettingsService(store: SettingsStore(configURL: url), platform: .mac, library: PluginLibrary(directory: plugins),
                                      secrets: .inMemory(), codingLibrary: CodingPackLibrary(store: packs))
        #expect(try Config.load(from: url).inputs == [.language(.chinese), .language(.english), .code])
        let removed = await service.perform(SettingsAction(field: "code.installed", name: SettingsAction.remove, item: "python"))
        #expect((try? removed.get()) != nil, "\(removed)")
        #expect(packs.installed().isEmpty)
        let after = try Config.load(from: url)
        #expect(after.codingLanguage == nil && after.inputs == [.language(.chinese), .language(.english)], "\(after.inputs)")

        try await inEnglish {
            let world = try Self.coding()
            let field = world.codeField()
            #expect(field.host.composer.input == .code)
            world.packs = []
            world.config.codingLanguage = nil
            field.host.send(.configChanged)
            #expect(field.host.composer.input == .language(.english), "its default input: \(field.host.composer.input)")
            field.type("re")
            field.idle()
            #expect(!field.shown(["return"]).contains("return"), "\(Self.texts(field))")
            var seen: [Input] = []
            for _ in 0..<3 {
                field.tapShift()
                seen.append(field.host.composer.input)
            }
            #expect(!seen.contains(.code), "\(seen)")
        }
    }

    /// In Code no word is learned as an English word (decision 22): one typed in two fields in Code, which made no rows,
    /// isn't; typed so in two fields in English mode, it is.
    @Test func inCodeNoWordIsLearnedAsEnglish() async throws {
        try await inEnglish {
            let world = try Self.coding()
            world.englishDictionary = EnglishDictionary(["hello", "world"])
            for app in [SuggestionsApps.editor, "com.apple.TextEdit"] {
                let field = world.codeField(app: app)
                #expect(field.host.composer.input == .code)
                field.type("zorblax ok ")
                #expect(field.rows.isEmpty, "\(Self.texts(field))")
            }
            #expect(!world.learned.contains { EnglishWords.key($0) == "zorblax" }, "\(world.learned)")

            let english = try Self.coding()
            english.englishDictionary = EnglishDictionary(["hello", "world"])
            for app in [SuggestionsApps.editor, "com.apple.TextEdit"] {
                let prose = english.field(app: app)
                #expect(prose.host.composer.input == .language(.english))
                prose.type("zorblax ok ")
            }
            #expect(english.learned.map(EnglishWords.key) == ["zorblax"], "in English: learned (\(english.learned))")
        }
    }

    // MARK: - The coding language's pack

    /// The pack's keywords are rows from 2 characters on; what is typed exactly is not offered.
    @Test func keywordsAreRowsFromTwoCharactersOn() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let field = world.codeField()
            field.type("r")
            field.idle()
            #expect(!Self.texts(field).contains { $0.contains("return") }, "one character: none (\(Self.texts(field)))")
            field.type("e")
            #expect(field.settle { field.shown(["return", "raise"]).contains("return") }, "\(Self.texts(field))")
            #expect(!field.shown(["return", "raise"]).contains("raise"), "\(Self.texts(field))")
            field.type("turn")
            field.idle()
            #expect(!field.shown(["return"]).contains("return"), "typed exactly: not offered (\(Self.texts(field)))")
        }
    }

    /// Code's rows come from its coding language's pack alone, whatever else is installed (decision 22): in Python, `if`
    /// is Python's (a colon), JavaScript's `function` isn't offered; in Java, `if` is Java's (parentheses and braces).
    @Test func onlyTheCodingLanguagesPackGivesRows() async throws {
        try await inEnglish {
            let world = try Self.coding(more: [try Self.pack("java"), try Self.pack("javascript")])
            let python = world.codeField()
            python.type("if")
            #expect(python.settle { Self.texts(python).contains { $0.contains("if block") } }, "\(Self.texts(python))")
            #expect(!Self.texts(python).contains { $0.contains("if statement") }, "not Java's: \(Self.texts(python))")
            var before = python.host.outputs.count
            #expect(python.press(SuggestionKeys.tab))
            #expect(python.document == "if :\n    ", "\(python.document.debugDescription)")
            #expect(Self.beforeCaret(python, since: before) == "if ", "\(Self.beforeCaret(python, since: before).debugDescription)")

            let other = world.codeField(app: "com.apple.TextEdit")
            other.type("fun")
            other.idle()
            #expect(!other.shown(["function"]).contains("function"), "JavaScript's: \(Self.texts(other))")

            world.config.codingLanguage = "java"
            let java = world.codeField(app: "com.apple.Notes")
            java.type("if")
            #expect(java.settle { Self.texts(java).contains { $0.contains("if statement") } }, "\(Self.texts(java))")
            #expect(!Self.texts(java).contains { $0.contains("if block") }, "not Python's: \(Self.texts(java))")
            before = java.host.outputs.count
            #expect(java.press(SuggestionKeys.tab))
            #expect(java.document == "if () {\n    \n}", "\(java.document.debugDescription)")
            #expect(Self.beforeCaret(java, since: before) == "if (", "\(Self.beforeCaret(java, since: before).debugDescription)")
        }
    }

    /// Out of Code (a language, Code among the inputs), the pack gives no rows and Tab is the app's; a tap of Shift into
    /// Code, they come.
    @Test func noCodingRowsOutsideCode() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let field = world.field()
            #expect(field.host.composer.input == .language(.english))
            field.type("re")
            field.idle()
            #expect(!field.shown(["return"]).contains("return"), "\(Self.texts(field))")
            #expect(!field.press(SuggestionKeys.tab))
            field.press(SuggestionKeys.space)
            field.tapShift()
            #expect(field.host.composer.input == .code)
            field.type("re")
            #expect(field.settle { field.shown(["return"]).contains("return") }, "in Code: \(Self.texts(field))")
        }
    }

    /// Return picks Code's rows as in an IDE, without ↓ first, in every app: ordinary apps, code editors, and chat apps,
    /// browsers and terminals too (spec decision 31; it replaces 6.20's "Return the app's in chat apps" and 6.23's "in
    /// terminals"), the chosen row as the app's class puts it in (a terminal: the snippet's trigger).
    @Test func returnPicksCodesRowsInEveryApp() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let editor = world.codeField()
            editor.type("pr")
            #expect(editor.settle { editor.shown(["print"]) == ["print"] }, "\(Self.texts(editor))")
            #expect(editor.press(SuggestionKeys.enter), "taken at once")
            #expect(editor.document == "print()", "\(editor.document.debugDescription)")

            let vsCode = world.codeField(app: SuggestionsApps.vsCode)
            vsCode.type("pr")
            #expect(vsCode.settle { vsCode.shown(["print"]) == ["print"] }, "\(Self.texts(vsCode))")
            #expect(vsCode.press(SuggestionKeys.enter), "a code editor: taken")
            #expect(vsCode.document.hasPrefix("print"), "\(vsCode.document.debugDescription)")

            // Decision 31: Return is ours while rows show in chat apps, browsers and terminals too; the first row chosen
            // and drawn selected from the start.
            for (app, terminal, inserted) in [(SuggestionsApps.slack, false, "print()"), (SuggestionsApps.chrome, false, "print()"),
                                              ("com.apple.Terminal", true, "print")] {
                let field = world.codeField(app: app, terminal: terminal)
                field.type("pr")
                #expect(field.settle { field.shown(["print"]).first == "print" }, "\(app): \(Self.texts(field))")
                #expect(field.host.panel?.highlighted == 0, "\(app): the first row chosen")
                #expect(field.press(SuggestionKeys.enter), "\(app): taken")
                #expect(field.document == inserted, "\(app): \(field.document.debugDescription)")
            }
        }
    }

    /// A snippet goes in as text, its line breaks kept; where the field reports ranges the caret goes to its first tab
    /// stop in reading order (spec 6.23): `${1:Name}` on its first line, before its `$0`, left empty.
    @Test func aSnippetGoesInWithItsLineBreaksAndTheCaretAtItsFirstTabStop() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let field = world.codeField()
            field.type("cl")
            #expect(field.settle { field.rows.contains { ($0.text + $0.comment).contains("class with __init__") } },
                    "\(Self.texts(field))")
            let index = try #require(field.rows.firstIndex { ($0.text + $0.comment).contains("class with __init__") })
            let before = field.host.outputs.count
            #expect(field.pick(at: index))
            #expect(field.document == "class :\n    def __init__(self):\n        \n", "\(field.document.debugDescription)")
            #expect(Self.beforeCaret(field, since: before) == "class ",
                    "the caret where `${1:Name}` was: \(Self.beforeCaret(field, since: before).debugDescription)")
        }
    }

    /// `print($0)`: "pr" and Tab make "print()", the caret between the parentheses.
    @Test func theCaretGoesToTheSnippetsDollarZero() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let field = world.codeField()
            field.type("pr")
            #expect(field.settle { field.shown(["print"]) == ["print"] }, "\(Self.texts(field))")
            let before = field.host.outputs.count
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "print()", "\(field.document)")
            #expect(field.host.outputs.dropFirst(before).contains { if case .moveCaret(back: 1, after: _) = $0 { true } else { false } },
                    "\(field.host.outputs.dropFirst(before))")
        }
    }

    /// Where the field reports no ranges, the snippet's caret stays at the end of what went in.
    @Test func withoutRangesTheCaretStaysAtTheEnd() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let field = world.codeField()
            field.type("pr")
            #expect(field.settle { field.shown(["print"]) == ["print"] }, "\(Self.texts(field))")
            var context = field.host.context
            context.read.subtract([.selectedRange, .selection])
            context.selectedRange = nil
            context.selection = nil
            let before = field.host.outputs.count
            field.host.send(.key(SuggestionKeys.tab, context))
            let outputs = Array(field.host.outputs.dropFirst(before))
            #expect(outputs.contains { if case .commit("int()") = $0 { true } else if case .commitAfterKey("int()") = $0 { true } else { false } },
                    "\(outputs)")
            #expect(!outputs.contains { if case let .moveCaret(back, _) = $0 { back > 0 } else { false } }, "\(outputs)")
        }
    }

    /// The def snippet of the spec's example (6.23): "def ${1:name}(${2}):\n    $0" goes in as "def ():\n    ", the caret
    /// after "def ": its first tab stop, `${1:name}`, left empty.
    @Test func theSpecsDefSnippet() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let field = world.codeField()
            field.type("de")
            #expect(field.settle { field.rows.contains { ($0.text + $0.comment).contains("function") } }, "\(Self.texts(field))")
            let index = try #require(field.rows.firstIndex { ($0.text + $0.comment).contains("function") })
            let before = field.host.outputs.count
            #expect(field.pick(at: index))
            #expect(field.document == "def ():\n    ", "\(field.document.debugDescription)")
            #expect(Self.beforeCaret(field, since: before) == "def ", "\(Self.beforeCaret(field, since: before).debugDescription)")
        }
    }

    /// `$0` before `$1` (6.23): the caret goes to `$0`, the first in reading order, and `${1:Exception}` keeps its text.
    @Test func whereDollarZeroComesFirstTheCaretGoesThereAndTheNumberedStopsKeepTheirText() async throws {
        try await inEnglish {
            let world = Self.coding(Self.blocksPack)
            let field = world.codeField()
            field.type("tr")
            #expect(field.settle { Self.texts(field).contains { $0.contains("try/except") } }, "\(Self.texts(field))")
            let index = try #require(field.rows.firstIndex { ($0.text + $0.comment).contains("try/except") })
            let before = field.host.outputs.count
            #expect(field.pick(at: index))
            #expect(field.document == "try:\n    \nexcept Exception:", "\(field.document.debugDescription)")
            #expect(Self.beforeCaret(field, since: before) == "try:\n    ",
                    "the caret in the try body: \(Self.beforeCaret(field, since: before).debugDescription)")
        }
    }

    /// The stop the caret goes to is left empty with its mirrors, wherever they are (6.23); the other stops keep their text.
    @Test func theFirstStopsMirrorsAreLeftEmptyToo() async throws {
        try await inEnglish {
            let world = Self.coding(Self.sortPack)
            let field = world.codeField()
            field.type("so")
            #expect(field.settle { Self.texts(field).contains { $0.contains("sort a range") } }, "\(Self.texts(field))")
            let index = try #require(field.rows.firstIndex { ($0.text + $0.comment).contains("sort a range") })
            let before = field.host.outputs.count
            #expect(field.pick(at: index))
            #expect(field.document == "sort(.begin(), .end(), less);", "\(field.document.debugDescription)")
            #expect(Self.beforeCaret(field, since: before) == "sort(", "\(Self.beforeCaret(field, since: before).debugDescription)")
        }
    }

    /// Where the field reports no ranges, every stop keeps its text, mirrors too, and the caret stays at the end of what
    /// went in (6.21, 6.23): the def snippet is "def name():\n    ".
    @Test func withoutRangesEveryStopKeepsItsTextAndTheCaretStaysAtTheEnd() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let field = world.codeField()
            let (def, defOutputs) = Self.tabWithoutRanges(after: "def", in: field) {
                field.rows.contains { ($0.text + $0.comment).contains("function") }
            }
            #expect("def" + def == "def name():\n    ", "\(def.debugDescription)")
            #expect(!defOutputs.contains { if case let .moveCaret(back, _) = $0 { back > 0 } else { false } }, "\(defOutputs)")

            let sorting = Self.coding(Self.sortPack)
            let other = sorting.codeField()
            let (sort, sortOutputs) = Self.tabWithoutRanges(after: "sort", in: other) {
                other.rows.contains { ($0.text + $0.comment).contains("sort a range") }
            }
            #expect("sort" + sort == "sort(v.begin(), v.end(), less);", "\(sort.debugDescription)")
            #expect(!sortOutputs.contains { if case let .moveCaret(back, _) = $0 { back > 0 } else { false } }, "\(sortOutputs)")
        }
    }

    /// A snippet's second and later lines get the caret's line's leading whitespace (6.19), and the caret goes to its first
    /// stop on a later line, indented as it is: `$0` in a try body, a numbered stop in a loop's (left empty).
    @Test func aSnippetsLaterLinesAreIndentedAsTheCaretsLine() async throws {
        try await inEnglish {
            let world = Self.coding(Self.blocksPack)
            let field = world.codeField()
            field.host.document = "def main():\n    "
            field.type("tr")
            #expect(field.settle { Self.texts(field).contains { $0.contains("try/except") } }, "\(Self.texts(field))")
            let index = try #require(field.rows.firstIndex { ($0.text + $0.comment).contains("try/except") })
            let before = field.host.outputs.count
            #expect(field.pick(at: index))
            #expect(field.document == "def main():\n    try:\n        \n    except Exception:", "\(field.document.debugDescription)")
            #expect(Self.beforeCaret(field, since: before) == "def main():\n    try:\n        ",
                    "the caret in the try body, indented: \(Self.beforeCaret(field, since: before).debugDescription)")

            let loop = world.codeField()
            loop.host.document = "for x in xs:\n\t"
            loop.type("wh")
            #expect(loop.settle { Self.texts(loop).contains { $0.contains("endless loop") } }, "\(Self.texts(loop))")
            let row = try #require(loop.rows.firstIndex { ($0.text + $0.comment).contains("endless loop") })
            let start = loop.host.outputs.count
            #expect(loop.pick(at: row))
            #expect(loop.document == "for x in xs:\n\twhile True:\n\t\t\n\t", "\(loop.document.debugDescription)")
            #expect(Self.beforeCaret(loop, since: start) == "for x in xs:\n\twhile True:\n\t\t",
                    "the caret where `${1:pass}` was, indented: \(Self.beforeCaret(loop, since: start).debugDescription)")
        }
    }

    /// A digit never picks a row (spec 6.1): "pr" and 1 is "pr1", typed.
    @Test func aDigitIsTypedNotAPick() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let field = world.codeField()
            field.type("pr")
            #expect(field.settle { field.shown(["print"]) == ["print"] }, "\(Self.texts(field))")
            field.press(SuggestionKeys.digit(1))
            #expect(field.document == "pr1", "\(field.document)")
        }
    }

    // MARK: - What is offered

    /// A snippet is offered while what is typed starts its trigger, the whole trigger too (Tab then puts its body in, the
    /// caret at its first stop: 6.23); a keyword typed in full isn't (spec 6.13): "def" offers the def snippet, not the
    /// keyword "def".
    @Test func theWholeTriggerStillOffersTheSnippet() async throws {
        try await inEnglish {
            let world = try Self.coding()
            let field = world.codeField()
            field.type("def")
            #expect(field.settle { field.rows.contains { ($0.text + $0.comment).contains("function") } }, "\(Self.texts(field))")
            #expect(field.rows.count == 1, "the snippet only, not the keyword: \(Self.texts(field))")
            let before = field.host.outputs.count
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "def ():\n    ", "\(field.document.debugDescription)")
            #expect(Self.beforeCaret(field, since: before) == "def ", "\(Self.beforeCaret(field, since: before).debugDescription)")
        }
    }

    /// A snippet whose body doesn't start with what was typed isn't offered (spec 6.13); one whose body does is.
    @Test func aSnippetWhoseBodyDoesntStartWithWhatWasTypedIsntOffered() async {
        await inEnglish {
            let world = Self.coding(CodingLanguagePack(language: "example", title: "Example", version: "1.0.0", keywords: [], snippets: [
                .init(trigger: "main", body: "if __name__ == \"__main__\":\n    $0", title: "main guard"),
                .init(trigger: "mainloop", body: "mainloop()$0", title: "the main loop"),
            ]))
            let field = world.codeField()
            field.type("ma")
            #expect(field.settle { Self.texts(field).contains { $0.contains("the main loop") } }, "\(Self.texts(field))")
            field.idle()
            #expect(!Self.texts(field).contains { $0.contains("main guard") }, "\(Self.texts(field))")
        }
    }

    // MARK: - The field's own words

    /// Types `text` where the field has `before` the caret and `after` it as the first key goes down (what it says with
    /// each key: its text, where the caret is); the app types each character.
    func type(_ text: String, into field: SuggestionsField, before: String, after: String) {
        var typed = ""
        for character in text {
            let left = before + typed
            let previous: FieldContext.BeforeCaret = left.last.map { FieldContext.BeforeCaret.text(String($0)) } ?? .nothing
            let context = FieldContext(read: .all, selectedRange: left.utf16.count..<left.utf16.count, beforeCaret: previous,
                                       text: FieldText(before: left, after: after))
            field.host.send(.key(SuggestionKeys.key(character), context))
            typed.append(character)
        }
    }

    /// Identifiers of 4 characters or more in the field's text, before the caret and after it, most frequent first; one
    /// shorter, or what is typed exactly, isn't offered.
    @Test func theFieldsOwnWordsAreRows() async {
        await inEnglish {
            let world = Self.coding(Self.emptyPack)
            let field = world.codeField()
            let before = "result = compute_average(items)\ncox = 1\n"
            let after = "\nprint(compute_total(a), compute_total(b), compute_total(c))\n"
            type("c", into: field, before: before, after: after)
            field.idle()
            #expect(field.shown(["compute_total", "compute_average"]).filter { $0 != "?" }.isEmpty, "one character: none")
            type("o", into: field, before: before + "c", after: after)
            let words = ["compute_total", "compute_average", "cox"]
            #expect(field.settle { field.shown(words).prefix(2) == ["compute_total", "compute_average"] },
                    "the most frequent first (after the caret too): \(Self.texts(field))")
            #expect(!field.shown(words).contains("cox"), "3 characters: not offered")
        }
    }

    /// Among words as frequent, the nearest to the caret first.
    @Test func amongWordsAsFrequentTheNearestFirst() async {
        await inEnglish {
            let world = Self.coding(Self.emptyPack)
            let field = world.codeField()
            type("ta", into: field, before: "table_far = 1\nother = 2\nstill = 3\ntable_near = 4\n", after: "")
            #expect(field.settle { field.shown(["table_near", "table_far"]) == ["table_near", "table_far"] }, "\(Self.texts(field))")
        }
    }

    /// The token is identifier characters: after "." a new one starts ("self.co" offers what "co" starts).
    @Test func aDotStartsANewToken() async {
        await inEnglish {
            let world = Self.coding(Self.emptyPack)
            let field = world.codeField()
            type("self.co", into: field, before: "count_items(x)\n", after: "")
            #expect(field.settle { field.shown(["count_items"]) == ["count_items"] }, "\(Self.texts(field))")
        }
    }

    /// A pack with nothing in it: Code's rows are the field's words alone.
    static let emptyPack = CodingLanguagePack(language: "example", title: "Example", version: "1.0.0", keywords: [], snippets: [])

    /// Blocks whose first tab stop isn't on their first line: `$0` before `${1:…}` (6.23's try/except), and a numbered
    /// stop before `$0`.
    static let blocksPack = CodingLanguagePack(language: "example", title: "Example", version: "1.0.0", keywords: [], snippets: [
        .init(trigger: "try", body: "try:\n    $0\nexcept ${1:Exception}:", title: "try/except"),
        .init(trigger: "while", body: "while True:\n\t${1:pass}\n$0", title: "endless loop"),
    ])

    /// A snippet whose first stop has a mirror (the same number again, with its text), and a second stop with text.
    static let sortPack = CodingLanguagePack(language: "example", title: "Example", version: "1.0.0", keywords: [], snippets: [
        .init(trigger: "sort", body: "sort(${1:v}.begin(), ${1:v}.end(), ${2:less});$0", title: "sort a range"),
    ])

    static let computePack = CodingLanguagePack(language: "example", title: "Example", version: "1.0.0",
                                                keywords: ["compute_total", "compute_average"],
                                                snippets: [.init(trigger: "compute_sum", body: "compute_sum($0)", title: "sum")])

    /// Terminals and code editors (VS Code, spec 6.11) are one class: a snippet isn't expanded there, it goes in as its
    /// trigger. Tab inserts the chosen row, the first from the start (spec decision 31; it replaces "Tab completes the
    /// rows' common prefix"); with the rows gone, Tab is the app's.
    @Test(arguments: [("com.apple.Terminal", true), (SuggestionsApps.vsCode, false)])
    func inTerminalsAndCodeEditorsTabInsertsTheChosenRowASnippetAsItsTrigger(_ app: String, _ terminal: Bool) async {
        await inEnglish {
            let world = Self.coding(Self.computePack)
            let field = world.codeField(app: app, terminal: terminal)
            field.type("co")
            #expect(field.settle { field.shown(["compute_total", "compute_average", "compute_sum"]).filter { $0 != "?" }.count == 3 },
                    "\(app): \(Self.texts(field))")
            // Decision 31: the first row (the snippet) chosen from the start; Tab inserts it, its trigger only.
            #expect(field.shown(["compute_total", "compute_average", "compute_sum"]).first == "compute_sum", "\(app): \(Self.texts(field))")
            #expect(field.host.panel?.highlighted == 0, "\(app): the first row chosen")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "compute_sum", "\(app): its trigger, not expanded (\(field.document))")
            #expect(field.rows.isEmpty, "\(app): the rows go (\(Self.texts(field)))")
            #expect(!field.press(SuggestionKeys.tab), "\(app): no rows, its Tab")
            #expect(field.document == "compute_sum", "\(app): \(field.document)")
        }
    }

    /// Where the field tells nothing of its text (a terminal), only the pack's keywords and snippets are rows (spec 6.16):
    /// a word in the field it doesn't tell of isn't one.
    @Test func whereTheFieldTellsNoTextOnlyPacksApply() async {
        await inEnglish {
            let world = Self.coding(Self.computePack)
            let field = world.codeField(app: "com.apple.Terminal", terminal: true)
            field.host.tellsNoText = true
            field.host.document = "compute_zebra = 1\n"
            for character in "co" {
                var context = field.host.context
                context.read.remove(.text)
                context.text = nil
                field.host.send(.key(SuggestionKeys.key(character), context))
                field.host.document.append(character)
            }
            let words = ["compute_total", "compute_average", "compute_sum", "compute_zebra"]
            #expect(field.settle { field.shown(words).filter { $0 != "?" }.count == 3 }, "\(Self.texts(field))")
            #expect(!field.shown(words).contains("compute_zebra"), "\(Self.texts(field))")
        }
    }
}
