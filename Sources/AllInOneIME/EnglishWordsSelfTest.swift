import AllInOneIMECore
import AppKit

extension SelfTest {
    /// English words among pinyin's candidates (`EnglishWordsEngine`) in the fake text field, on the real librime: a
    /// word rime-ice lacks ("bedrock", from the curated list) first when all its letters are typed, second while longer;
    /// letters put in as typed twice learned (into the self-test's own config file) and offered at once; nothing learned
    /// during secure input, in an app with no AI, a terminal or a remote desktop; rime-ice's own English words as they were.
    /// A word typed twice in English mode learned too, nothing shown there; not one with a capital first, not during
    /// secure input or in a terminal.
    static func testEnglishWords(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        section("English words among pinyin's candidates", needs: .composing)
        let settingsBefore = settings
        let pointerBefore = controller.services.pointerUsedWithin
        defer {
            settings = settingsBefore
            controller.services.pointerUsedWithin = pointerBefore
            controller.services.secureInputActive = { false }
            controller.commitComposition(client)
            client.bundleIDOverride = nil
            controller.activateServer(client)
            controller.applySettings()
        }
        // The fake field is no password field: secure input off, whatever holds it on this Mac now (the lock screen).
        controller.services.secureInputActive = { false }
        func candidates() -> [String] { controller.composer.engineState.candidates.map(\.text) }
        func learned() -> [String] { (try? Config.load())?.englishWords ?? [] }

        type("bedrock", controller, client)
        check(candidates().first == "Bedrock" && controller.composer.engineState.highlighted == 0,
              "'bedrock' offers Bedrock first (\(candidates().prefix(4)))")
        snapshot("english-words", in: snapshotDirectory)
        check(space(controller, client) && client.inserted.last == "Bedrock", "Space inserts Bedrock (\(client.inserted.last ?? "-"))")
        type("bedro", controller, client)
        check(candidates().dropFirst().first == "Bedrock", "'bedro' offers it second, after pinyin's first (\(candidates().prefix(3)))")
        _ = escape(controller, client)
        type("openrouter", controller, client)
        check(candidates().first == "OpenRouter" && candidates().filter { $0.lowercased() == "openrouter" }.count == 1,
              "rime-ice's own English word as before, once (\(candidates().prefix(3)))")
        _ = escape(controller, client)

        // Learned the second time letters are put in as typed (⏎), kept in the self-test's config, offered at once.
        check(Config.defaultURL != Config.userURL, "words are learned into the self-test's own config")
        type("frobnicate", controller, client)
        check(enter(controller, client) && client.inserted.last == "frobnicate", "⏎ puts 'frobnicate' in as typed")
        check(!learned().contains("frobnicate"), "…the first time it is only remembered (\(learned()))")
        type("frobnicate", controller, client)
        _ = enter(controller, client)
        check(learned().contains("frobnicate"), "…the second time it is learned (\(learned()))")
        type("frobn", controller, client)
        let place = candidates().firstIndex(of: "frobnicate")
        check(place == 1, "'frobn' offers it second (\(candidates().prefix(3)))")
        if let place {
            press(controller, client, String(place + 1), code: keyCodes[Character(String(place + 1))] ?? 0)
            check(client.inserted.last == "frobnicate", "its digit inserts it (\(client.inserted.last ?? "-"))")
        }
        _ = escape(controller, client)

        // Never during secure input, in an app with no AI, a terminal, a remote desktop; pinyin never. Each put in twice.
        func putInTwice(_ letters: String) {
            for _ in 0..<2 {
                type(letters, controller, client)
                _ = enter(controller, client)
            }
        }
        controller.services.secureInputActive = { true }
        putInTwice("quuxify")
        controller.services.secureInputActive = { false }
        let noAI = "com.example.noai"
        settings.appProfiles[noAI] = AppProfile(noAI: true)
        for app in [noAI, "com.apple.Terminal", "com.microsoft.rdc.macos", "com.termius-dmg.mac"] {
            client.bundleIDOverride = app
            controller.activateServer(client)
            controller.composer.setInputMode(.chinese)
            putInTwice("quuxify")
            check(client.inserted.last == "quuxify", "⏎ in \(app) puts it in as typed (\(client.inserted.last ?? "-"))")
        }
        client.bundleIDOverride = nil
        controller.activateServer(client)
        controller.composer.setInputMode(.chinese)
        putInTwice("nihao")
        check(!learned().contains("quuxify") && !learned().contains("nihao"),
              "nothing learned during secure input, in an app with no AI, a terminal, a remote desktop or an SSH client, or of pinyin (\(learned()))")

        // Words typed in English mode (a tap of Shift: the keys go straight to the app, nothing is shown) are learned too:
        // the second time, by the same rule; then pinyin offers them.
        controller.services.pointerUsedWithin = { _ in false }  // the user's own clicks meanwhile
        /// Whether each key went straight to the app.
        func typeInEnglish(_ text: String) -> Bool {
            text.map { character in
                switch character {
                case " ": return !space(controller, client)
                case "\r": return !enter(controller, client)
                default: return !press(controller, client, String(character), code: keyCodes[character] ?? 0)
                }
            }.allSatisfy { $0 }
        }
        tapShift(controller, client)
        check(controller.composer.inputLanguage == .english, "a tap of Shift: English mode (\(controller.composer.inputLanguage))")
        let inserted = client.inserted.count
        check(typeInEnglish("we zorblaxing it. ") && client.marked.isEmpty && client.inserted.count == inserted,
              "in English mode each key goes straight to the app: nothing marked or put in (\(client.marked), \(client.inserted.suffix(2)))")
        check(!learned().contains("zorblaxing"), "…a word typed once is only remembered (\(learned()))")
        _ = typeInEnglish("zorblaxing\rok ")
        check(learned().contains("zorblaxing"), "…typed twice it is learned (\(learned()))")
        _ = typeInEnglish("Quuxifying Quuxifying ok ")
        controller.services.secureInputActive = { true }
        _ = typeInEnglish("wibbling wibbling ok ")
        controller.services.secureInputActive = { false }
        client.bundleIDOverride = "com.apple.Terminal"
        controller.activateServer(client)
        controller.composer.setInputMode(.english)
        _ = typeInEnglish("wobbling wobbling ok ")
        client.bundleIDOverride = nil
        controller.activateServer(client)
        controller.composer.setInputMode(.english)
        check(!learned().contains { ["quuxifying", "wibbling", "wobbling"].contains($0.lowercased()) },
              "…not one with a capital first, nor during secure input or in a terminal (\(learned()))")
        tapShift(controller, client)
        check(controller.composer.inputLanguage == .chinese, "a tap of Shift: back to Chinese")
        type("zorblaxi", controller, client)
        check(candidates().contains("zorblaxing"), "'zorblaxi' then offers it among pinyin's candidates (\(candidates().prefix(4)))")
        _ = escape(controller, client)
    }

    /// Settings → Input → Chinese → English Words: words added and removed are saved at once (a config file of its own),
    /// the switch too; the page drawn in Chinese and English with sample words (nothing saved).
    static func testEnglishWordsSettings(snapshotDirectory: URL) {
        section("Settings → Input → English words")
        let dir = snapshotDirectory.appendingPathComponent("english-words-config")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try? Config.default.write(to: url)
        func saved() -> Config? { try? Config.load(from: url) }
        let model = SettingsModel(configURL: url)
        check(model.addEnglishWords("Bedrock, frobnicate").words == ["Bedrock", "frobnicate"]
                && saved()?.englishWords == ["Bedrock", "frobnicate"] && saved()?.addedEnglishWords == ["Bedrock", "frobnicate"],
              "Add saves the words at once, as added (\(saved()?.englishWords ?? []), \(saved()?.addedEnglishWords ?? []))")
        check(model.addEnglishWords("BEDROCK") == EnglishWords.Added() && model.addEnglishWords("北京") == EnglishWords.Added(),
              "a word there already, or not English, isn't added")
        let key = "sk-ant-api03-abcdefghijklmnopqrstuvwx"
        check(model.addEnglishWords(key) == EnglishWords.Added(refused: [key]) && saved()?.englishWords == ["Bedrock", "frobnicate"],
              "a key is refused, and not saved")
        model.removeEnglishWord("FROBNICATE")
        check(saved()?.englishWords == ["Bedrock"] && saved()?.addedEnglishWords == ["Bedrock"],
              "✕ removes it (\(saved()?.englishWords ?? []), \(saved()?.addedEnglishWords ?? []))")
        _ = try? EnglishWords.learn("quuxify", at: url)
        check(model.addEnglishWords("Quuxify").words == ["Quuxify"] && saved()?.englishWords == ["Bedrock", "Quuxify"]
                && saved()?.addedEnglishWords == ["Bedrock", "Quuxify"],
              "Add makes a word learned the user's, as written (\(saved()?.englishWords ?? []), \(saved()?.addedEnglishWords ?? []))")
        model.config.learnsEnglishWords = false
        model.save()
        check(saved()?.learnsEnglishWords == false, "learning turned off is saved")
        check(SettingsPage.input.matches("英文词") && SettingsPage.input.matches("english words"), "the search finds the English words")

        let chosen = UIText.choice
        defer { UIText.choice = chosen }
        for (name, language) in [("settings-english-words", "zh"), ("settings-english-words-en", "en")] {
            UIText.choice = language
            let preview = SettingsModel(configURL: Config.defaultURL, persists: false)
            preview.config.setOrder([Language.chinese, .english])
            preview.config.englishWords = ["Bedrock", "frobnicate", "LangGraph", "Kiro", "OpenRouter Chat"]
            let image = snapshotDirectory.appendingPathComponent("\(name).png")
            SettingsImage.render(preview, page: .input, inputTab: .chinese, to: image) { seconds in _ = pump(timeout: seconds) { false } }
            check(FileManager.default.fileExists(atPath: image.path), "Settings → Input → English words drawn (\(language))")
        }
    }
}
