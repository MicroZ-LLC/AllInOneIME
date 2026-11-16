import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

@Suite(.serialized)
struct OneAtNumbersAndKeyHintsTests {
    private func composer(trigger: String = "@", english: Bool = true,
                          engine: PinyinEngine = FakeEngine()) -> Composer {
        let composer = Composer(engine: engine, actionKey: .enter)
        composer.commands = Command.builtins
        composer.commandTrigger = trigger
        if english { composer.setInputMode(.english) }
        return composer
    }

    private func type(_ text: String, into composer: Composer) {
        for character in text {
            _ = composer.handleKeyDown(character == " " ? spaceKey : k(String(character)))
        }
    }

    private func shortcut(_ digit: Int, modifiers: Modifiers = .option, keypad: Bool = false) -> KeyEvent {
        let rowCodes: [UInt16] = [0x1D, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19]
        let padCodes: [UInt16] = [0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C]
        let optionCharacters = ["º", "¡", "™", "£", "¢", "∞", "§", "¶", "•", "ª"]
        let character = modifiers.contains(.option)
            ? (modifiers.contains(.shift) && digit == 1 ? "⁄" : optionCharacters[digit]) : String(digit)
        return KeyEvent(keyCode: keypad ? padCodes[digit] : rowCodes[digit],
                        characters: keypad ? String(digit) : character,
                        charactersIgnoringModifiers: String(digit), modifiers: modifiers)
    }

    private func model(_ composer: Composer, config: Config = .default,
                       terms: PlatformTerms = .mac) -> PanelModel {
        PanelPresenter(config: config, language: "en", terms: terms).model(for: composer)
    }

    @Test func oneAtRowsShowPlatformPickLabelsAndRestartAtOneAfterScrolling() throws {
        let composer = composer()
        type("@", into: composer)
        try #require(composer.oneAtRows.count > Composer.oneAtRowsShown)
        for (terms, roles) in [(PlatformTerms.mac, ModifierRoles.mac), (.windows, .windows)] {
            composer.modifierRoles = roles
            let first = model(composer, terms: terms)
            #expect(first.rows.count == Composer.oneAtRowsShown)
            #expect(first.rows.map(\.label) == (1...first.rows.count).map(terms.pick))
            #expect(first.rows.first?.label == (terms == .mac ? "⌥1" : "Alt+1"))
            #expect(first.rows.map(\.choice) == first.rows.indices.map { Optional($0) })
        }
        for _ in 0..<Composer.oneAtRowsShown { _ = composer.handleKeyDown(downKey) }
        #expect(composer.oneAtFirstVisible == 1)
        for terms in [PlatformTerms.mac, .windows] {
            composer.modifierRoles = terms.roles
            let scrolled = model(composer, terms: terms)
            #expect(scrolled.rows.first?.label == terms.pick(1))
            #expect(scrolled.rows.last?.label == terms.pick(scrolled.rows.count))
            #expect(scrolled.rows.first?.choice == 0)
            #expect(scrolled.highlighted == scrolled.rows.count - 1)
        }
    }

    @Test func optionDigitPicksTheSameCommandAsClickAndReturn() throws {
        let optionOne = shortcut(1)
        #expect(optionOne.keyCode == 0x12 && optionOne.usage == 0x1E && optionOne.characters == "¡")
        for trigger in ["@", "~"] {
            let keyed = composer(trigger: trigger)
            let clicked = composer(trigger: trigger)
            let returned = composer(trigger: trigger)
            for candidate in [keyed, clicked, returned] { type(trigger, into: candidate) }
            let second = try #require(keyed.oneAtVisible.dropFirst().first?.command)
            let key = keyed.handleKeyDown(shortcut(2))
            let click = clicked.choose(index: 1)
            _ = returned.handleKeyDown(downKey)
            let enter = returned.handleKeyDown(enterKey)
            #expect(key.handled && key.effects == click && key.effects == enter.effects)
            #expect(keyed.draftCommand == second && keyed.draft == clicked.draft)
            #expect(keyed.draft == returned.draft)
        }
    }

    @Test func optionDigitPicksTheVisibleRowAfterScrolling() throws {
        let keyed = composer()
        let clicked = composer()
        for candidate in [keyed, clicked] {
            type("@", into: candidate)
            for _ in 0..<Composer.oneAtRowsShown { _ = candidate.handleKeyDown(downKey) }
        }
        let top = try #require(keyed.oneAtVisible.first?.command)
        let picked = keyed.handleKeyDown(shortcut(1))
        let click = clicked.choose(index: 0)
        #expect(picked.handled && picked.effects == click)
        #expect(keyed.draftCommand == top && keyed.draft == clicked.draft)
    }

    @Test func optionKeypadDigitPicksByItsUsageAndKeypadZeroChangesNothing() throws {
        let keyed = composer()
        let clicked = composer()
        for candidate in [keyed, clicked] { type("@", into: candidate) }
        let padTwo = shortcut(2, keypad: true)
        #expect(padTwo.keyCode == 0x54 && padTwo.usage == 0x5A && padTwo.placeDigit == 2)
        let key = keyed.handleKeyDown(padTwo)
        let click = clicked.choose(index: 1)
        #expect(key.handled && key.effects == click && keyed.draft == clicked.draft)

        let zero = composer()
        type("@", into: zero)
        let before = model(zero)
        let padZero = shortcut(0, keypad: true)
        #expect(padZero.usage == 0x62 && padZero.placeDigit == 0)
        let response = zero.handleKeyDown(padZero)
        #expect(response.handled && response.effects.isEmpty && model(zero) == before)
    }

    @Test func optionDigitInsertsASumsValueAsItsClickDoes() throws {
        let keyed = composer()
        let clicked = composer()
        for candidate in [keyed, clicked] { type("@1+2", into: candidate) }
        #expect(model(keyed).rows.first?.text == "= 3")
        let key = keyed.handleKeyDown(shortcut(1))
        let click = clicked.choose(index: 0)
        #expect(key.handled && commits(key) == ["3"])
        #expect(key.effects == click && keyed.phase == clicked.phase)
    }

    @Test func missingOptionDigitsAreTakenWithoutChangingTheList() {
        for (text, digit) in [("@", 9), ("@", 0)] {
            let composer = composer()
            type(text, into: composer)
            let before = model(composer)
            let draft = composer.draft
            let response = composer.handleKeyDown(shortcut(digit))
            #expect(response.handled && response.effects.isEmpty, "\(text), ⌥\(digit)")
            #expect(composer.draft == draft && model(composer) == before)
        }
        let three = composer()
        three.commands = Array(Command.builtins.prefix(3))
        type("@", into: three)
        #expect(model(three).rows.count == 3)
        let before = model(three)
        let response = three.handleKeyDown(shortcut(5))
        #expect(response.handled && response.effects.isEmpty)
        #expect(three.draft == "@" && model(three) == before)
    }

    @Test func plainDigitsRemainTextForEitherCommandTrigger() {
        for trigger in ["@", "~"] {
            let composer = composer(trigger: trigger)
            type(trigger, into: composer)
            #expect(composer.handleKeyDown(k("1")).handled)
            #expect(composer.draft == trigger + "1" && composer.draftCommand == nil)
            type("+2", into: composer)
            #expect(composer.draft == trigger + "1+2")
            #expect(model(composer).rows.first?.text == "= 3")
        }
    }

    @Test func shiftedDigitTypesAnArithmeticOperatorInsteadOfPickingARow() {
        let composer = composer()
        type("@2", into: composer)
        let star = KeyEvent(keyCode: 0x1C, characters: "*", charactersIgnoringModifiers: "*", modifiers: .shift)
        #expect(composer.handleKeyDown(star).handled)
        type("3", into: composer)
        #expect(composer.draft == "@2*3")
        #expect(model(composer).rows.first?.text == "= 6")
    }

    @Test func ordinaryPinyinAndRewriteListsKeepPlainDigitLabelsAndPicks() {
        let pinyin = composer(english: false)
        type("nihao", into: pinyin)
        #expect(model(pinyin).rows.map(\.label) == ["1", "2"])
        #expect(commits(pinyin.handleKeyDown(k("2"))) == ["拟好"])

        let rewrite = composer()
        type("@improve", into: rewrite)
        _ = rewrite.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        type("hello", into: rewrite)
        _ = rewrite.handleKeyDown(enterKey)
        _ = rewrite.receive(ConversionResult(versions: [CandidateLine("Better."), CandidateLine("Best.")]),
                            isFinal: true, id: 1)
        #expect(model(rewrite).rows.map(\.label) == ["0", "1", "2"])
        #expect(commits(rewrite.handleKeyDown(k("2"))) == ["Best."])
    }

    @Test func pinyinPlainDigitPicksAWordWhileOptionDigitPicksAOneAtRow() throws {
        let plain = composer(english: false)
        let keyed = composer(english: false)
        let clicked = composer(english: false)
        for candidate in [plain, keyed, clicked] {
            type("@nihao", into: candidate)
            try #require(candidate.engineState.isComposing)
            #expect(model(candidate).candidates == "1 你好   2 拟好")
        }
        _ = plain.handleKeyDown(k("2"))
        #expect(plain.draft == "@拟好" && !plain.engineState.isComposing)
        let key = keyed.handleKeyDown(shortcut(1))
        let click = clicked.choose(index: 0)
        #expect(key.handled && key.effects == click)
        #expect(keyed.draft == clicked.draft && keyed.draft != plain.draft)
    }

    @Test func extraModifiersNeverPickAOneAtRowAndCapsLockDoesNotBlockIt() {
        let unwanted: [Modifiers] = [[.option, .shift], [.option, .command], [.option, .control], [.command]]
        for modifiers in unwanted {
            let composer = composer()
            let ordinary = self.composer()
            type("@", into: composer)
            type("@", into: ordinary)
            let digit = shortcut(1, modifiers: modifiers)
            var unrelatedKey = digit
            unrelatedKey.keyCode = 0x00
            let response = composer.handleKeyDown(digit)
            let ordinaryResponse = ordinary.handleKeyDown(unrelatedKey)
            #expect(response == ordinaryResponse, "\(modifiers)")
            #expect(composer.draft == ordinary.draft && composer.draftCommand == nil, "\(modifiers)")
            if modifiers == .command {
                #expect(!response.handled && commits(response) == ["@"])
            }

            let withText = self.composer()
            type("@ab", into: withText)
            _ = withText.handleKeyDown(shortcut(1, modifiers: modifiers))
            #expect(withText.draftCommand == nil, "\(modifiers)")
        }
        let composer = composer()
        type("@", into: composer)
        let first = composer.oneAtVisible.first?.command
        #expect(composer.handleKeyDown(shortcut(1, modifiers: [.option, .capsLock])).handled)
        #expect(composer.draftCommand == first)

        let sided = self.composer()
        type("@", into: sided)
        let sidedFirst = sided.oneAtVisible.first?.command
        #expect(sided.handleKeyDown(shortcut(1, modifiers: [.option, .rightOption])).handled)
        #expect(sided.draftCommand == sidedFirst)
    }

    @Test func optionDigitWithoutNumberedChoicesActsAsAnOrdinaryKey() {
        let plain = composer()
        let ordinary = composer()
        var unrelatedKey = shortcut(1)
        unrelatedKey.keyCode = 0x00
        let plainResponse = plain.handleKeyDown(shortcut(1))
        let ordinaryResponse = ordinary.handleKeyDown(unrelatedKey)
        #expect(plainResponse == ordinaryResponse && plain.draft == ordinary.draft)
        #expect(plain.oneAtVisible.isEmpty)

        let digitEngine = OptionCommittingPinyinEngine()
        let letterEngine = OptionCommittingPinyinEngine()
        let digit = composer(english: false, engine: digitEngine)
        let letter = composer(english: false, engine: letterEngine)
        for candidate in [digit, letter] { type("nihao", into: candidate) }
        let optionA = KeyEvent(keyCode: 0x00, characters: "å", charactersIgnoringModifiers: "a", modifiers: .option)
        let response = digit.handleKeyDown(shortcut(1))
        let letterResponse = letter.handleKeyDown(optionA)
        #expect(response == letterResponse)
        #expect(!response.handled && commits(response) == ["你好"])
        #expect(digitEngine.selectedCandidates.isEmpty && letterEngine.selectedCandidates.isEmpty)
        #expect(digit.draftCommand == nil && letter.draftCommand == nil)
    }

    @Test func anotherPrimaryShortcutAfterTriggerPassesThroughTheTypedTrigger() {
        for trigger in ["@", "~"] {
            let composer = composer(trigger: trigger)
            type(trigger, into: composer)
            let response = composer.handleKeyDown(
                KeyEvent(keyCode: 0x09, characters: "v", charactersIgnoringModifiers: "v", modifiers: .command))
            #expect(!response.handled)
            #expect(commits(response) == [trigger])
            #expect(composer.draft.isEmpty)
        }
    }

    @Test func windowsAltDigitPicksAndControlDigitDoesNot() {
        let composer = composer()
        composer.modifierRoles = .windows
        type("@", into: composer)
        #expect(model(composer, terms: .windows).rows.first?.label == "Alt+1")
        let first = composer.oneAtVisible.first?.command
        #expect(composer.handleKeyDown(shortcut(1)).handled)
        #expect(composer.draftCommand == first)

        let control = self.composer()
        control.modifierRoles = .windows
        type("@", into: control)
        let response = control.handleKeyDown(shortcut(1, modifiers: .control))
        #expect(!response.handled && commits(response) == ["@"])
        #expect(control.draftCommand == nil)
    }

    @Test func optionDigitPicksAOneAtRowWithSelectedText() throws {
        let keyed = composer()
        let clicked = composer()
        for candidate in [keyed, clicked] {
            candidate.readSelection = { Composer.Selection(text: "Please rewrite this", range: 0..<19) }
            type("@", into: candidate)
            #expect(!model(candidate).header.isEmpty)
        }
        let selected = try #require(keyed.oneAtVisible.first?.command)
        let key = keyed.handleKeyDown(shortcut(1))
        let click = clicked.choose(index: 0)
        #expect(key.handled && key.effects == click)
        #expect(keyed.draftCommand == selected && keyed.draft == clicked.draft)
    }

    @Test func markedOneAtTextTakesTheMacShortcutBeforeItsHostApp() throws {
        let config = Config.default
        let host = FakeHost(services: SessionServices(loadSettings: { config }))
        host.app = "com.example.editor"
        host.focus()
        host.type("@")
        try #require(!host.preedit.isEmpty && host.panel != nil)  // in the panel's input line, not marked (#128)
        let first = try #require(host.composer.oneAtVisible.first?.command)
        let appReceivedKey = !host.press(shortcut(1))
        #expect(!appReceivedKey)
        #expect(host.composer.draftCommand == first)
        #expect(host.document.isEmpty)
    }

    @Test func keyHintsDefaultOnAndOldConfigDecodesOn() throws {
        #expect(Config.default.keyHints)
        let old = try JSONDecoder().decode(Config.self, from: Data(#"{"candidateLayout":"vertical"}"#.utf8))
        #expect(old.keyHints)
    }

    @Test func keyHintsOffRoundTripsUnderItsJsonKey() throws {
        var config = Config.default
        config.keyHints = false
        let data = try JSONEncoder().encode(config)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["keyHints"] as? Bool == false)
        #expect(try JSONDecoder().decode(Config.self, from: data).keyHints == false)
    }

    @Test func keyHintsOffRemovesOnlyExplanatoryKeysFromEveryPanelShape() throws {
        var on = Config.default
        on.keyHints = true
        var off = on
        off.keyHints = false
        let examples: [Composer] = {
            let at = composer()
            type("@", into: at)
            let sum = composer()
            type("@1+2", into: sum)
            let pinyin = composer(english: false)
            type("nihao", into: pinyin)
            let composingAt = composer(english: false)
            type("@nihao", into: composingAt)
            let command = composer()
            type("@open", into: command)
            return [at, sum, pinyin, composingAt, command]
        }()
        for composer in examples {
            let shown = model(composer, config: on)
            let hidden = model(composer, config: off)
            #expect(!shown.footer.isEmpty)
            #expect(hidden.footer.isEmpty && hidden.hints.isEmpty)
            #expect(hidden.footerHints.hints.isEmpty)
            #expect(hidden.footerHints.note == shown.footerHints.note)
            #expect(hidden.note == shown.note && hidden.detail == shown.detail)
            #expect(hidden.candidatesHint == nil)
            #expect(hidden.rows == shown.rows && hidden.highlighted == shown.highlighted)
            #expect(hidden.status == shown.status && hidden.header == shown.header)
            #expect(hidden.input == shown.input && hidden.chip == shown.chip)
            #expect(hidden.candidates == shown.candidates)
        }
        let composing = try #require(examples.first { $0.engineState.isComposing && $0.draft.hasPrefix("@") })
        #expect(model(composing, config: on).candidatesHint != nil)
    }

    @Test func keyHintsOnKeepsTheExistingFooterAndHighlightedAction() {
        var config = Config.default
        config.keyHints = true
        let composer = composer()
        type("@", into: composer)
        let shown = model(composer, config: config)
        #expect(shown == model(composer, config: .default))
        #expect(!shown.footer.isEmpty && !shown.footerHints.hints.isEmpty)
        #expect(shown.rows.first?.action == model(composer).rows.first?.action)
    }

    @Test func keyHintsOffKeepsWritingNoteLoadingStatusAndNoticeDetail() {
        let composer = composer()
        type("@improve", into: composer)
        _ = composer.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        type("hello", into: composer)
        _ = composer.handleKeyDown(enterKey)
        var on = Config.default
        on.keyHints = true
        var off = on
        off.keyHints = false
        let writing = PanelPresenter(config: on, language: "en", notice: "Saved").model(for: composer)
        let quiet = PanelPresenter(config: off, language: "en", notice: "Saved").model(for: composer)
        #expect(writing.note != nil && writing.footerHints.note != nil)
        #expect(quiet.footer.isEmpty && quiet.hints.isEmpty && quiet.footerHints.hints.isEmpty)
        #expect(quiet.note == writing.note && quiet.footerHints.note == writing.footerHints.note)
        #expect(quiet.status == writing.status && quiet.detail == "Saved")
        #expect(quiet.rows == writing.rows && quiet.highlighted == writing.highlighted)
    }

    @Test func keyHintsSettingSitsBesideCandidateLayoutAndWritesConfig() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("key-hints-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("config.json")
        try Data(#"{"uiLanguage":"en"}"#.utf8).write(to: url)
        let service = SettingsService(store: SettingsStore(configURL: url), platform: .mac,
                                      library: PluginLibrary(directory: folder.appendingPathComponent("plugins")))
        let document = await withInterfaceLanguage("en") { service.document() }
        let input = try #require(document.sections.first { $0.id == "input" })
        let ids = input.fields.map(\.id)
        let layout = try #require(ids.firstIndex(of: "candidateLayout"))
        let hints = try #require(ids.firstIndex(of: "keyHints"))
        #expect(abs(layout - hints) == 1)
        let field = try #require(document.field("keyHints"))
        #expect(field.kind == .toggle && field.value == .bool(true))
        #expect(field.label == "Show key hints")
        #expect(field.help?.contains("smaller box") == true)
        let saved = await withInterfaceLanguage("en") { service.set("keyHints", to: .bool(false)) }
        #expect((try? saved.get()) != nil)
        #expect(try Config.load(from: url).keyHints == false)
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(json["keyHints"] as? Bool == false)
    }

    @Test func keyHintsSettingHasChineseTextAndAppearsOnWindows() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("key-hints-locales-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("config.json")
        try Data(#"{"uiLanguage":"zh-Hans"}"#.utf8).write(to: url)
        for platform in [SettingsPlatform.mac, .windows] {
            let service = SettingsService(store: SettingsStore(configURL: url), platform: platform,
                                          library: PluginLibrary(directory: folder.appendingPathComponent("plugins")))
            let document = await withInterfaceLanguage("zh-Hans") { service.document() }
            let field = try #require(document.field("keyHints"))
            #expect(field.label == "显示按键提示")
            #expect(field.help?.contains("候选框更小") == true)
        }
    }

    @Test func keyHintsIsSyncedWithInputSettings() {
        #expect(ICloudSync.settingsKeys.contains("keyHints"))
        #expect(ICloudSync.settingsKeys.contains("candidateLayout"))
    }
}
