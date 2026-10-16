import AllInOneIMECore
import AppKit
import SwiftUI

/// Stands in for the on-device model in the self-test: available, held to the schema, answers with the JSON it's given
/// (no live AI), and counts the requests.
final class CannedGuidedModel: AppleGuidedBackend, @unchecked Sendable {
    var answer: String
    private(set) var requests = 0
    private(set) var prompts: [String] = []

    init(_ answer: String) { self.answer = answer }

    var availability: AppleModelAvailability { .available }
    var contextSize: Int { 8192 }
    var supportedLanguages: Set<String> { ["en", "zh"] }

    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        AsyncThrowingStream { $0.finish(throwing: AppleModelError.failed("the self-test's model is held to a schema")) }
    }

    func respond(to request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async throws -> String {
        requests += 1
        prompts.append(request.prompt)
        return answer
    }
}

extension SelfTest {
    /// `@config` with a canned answer from a stand-in on-device model, on a config file of the self-test's own: the hint
    /// under "@config ", the preview (old → new, a refused part with its reason), ⏎ applies to the file and nothing is
    /// inserted, ⌘Z puts it back, "@config undo" with nothing to undo says so, a key typed into the text is never sent
    /// (the key field opens), a provider change runs Test Connection. The user's config file is never touched.
    static func testAIConfig(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        section("@config: settings by describing them (canned answer)", needs: .composing)
        let realBefore = try? Data(contentsOf: Config.userURL)
        let url = snapshotDirectory.appendingPathComponent("aiconfig-config.json")
        let model = CannedGuidedModel("")
        var opened: [Provider] = []
        var tested = 0
        let saved = (AIConfigSession.url, AIConfigSession.service, AIConfigSession.environment, AIConfigSession.openKeyField,
                     AIConfigSession.testConnection, AIConfigSession.lastApplied)
        let (settingsBefore, loadBefore, insertedBefore) = (settings, controller.loadSettings, client.inserted)
        // Requests here go to a stand-in: nothing to refuse while the screen is locked.
        let secureBefore = controller.secureInputActive
        controller.secureInputActive = { false }
        defer {
            controller.commitComposition(client)
            controller.secureInputActive = secureBefore
            (AIConfigSession.url, AIConfigSession.service, AIConfigSession.environment, AIConfigSession.openKeyField,
             AIConfigSession.testConnection, AIConfigSession.lastApplied) = saved
            (settings, controller.loadSettings, client.inserted) = (settingsBefore, loadBefore, insertedBefore)
            controller.applySettings()
            controller.composer.setInputMode(settings.defaultInput)
            try? FileManager.default.removeItem(at: url)
            check((try? Data(contentsOf: Config.userURL)) == realBefore, "@config: the user's config file was not touched")
        }
        var start = settings
        start.candidateLayout = .horizontal
        start.appProfiles = [:]
        start.setOrder([OutputLanguage.english, .chinese])
        try? start.write(to: url)
        AIConfigSession.url = url
        AIConfigSession.service = AIConfigService(client: ChatClient(apple: model))
        AIConfigSession.lastApplied = nil
        AIConfigSession.environment = { typed in
            AIConfig.Environment(
                apps: AIConfig.AppCatalog(apps: [.init(bundleID: "com.tencent.xinWeChat", names: ["WeChat", "微信"])]),
                awsProfiles: { ["default"] }, knownModels: { $0 == .anthropic ? ["claude-haiku-5-5"] : [] },
                hasKey: { $0 == .anthropic }, chinese: UIText.chinese, typedText: typed)
        }
        AIConfigSession.openKeyField = { opened.append($0) }
        AIConfigSession.testConnection = { _ in
            tested += 1
            return (true, "0.8 s: Hello")
        }
        // The controller follows the file @config writes (as the input method follows the real one).
        controller.loadSettings = { (try? Config.load(from: url)) ?? SelfTest.settings }
        controller.applySettings()
        func file() -> Config { (try? Config.load(from: url)) ?? .default }
        func command(_ text: String) {
            controller.composer.setInputMode(.english)  // the text as letters (not while composing: before the "@")
            press(controller, client, "@", code: 0x13, flags: .shift)
            type("conf", controller, client)
            press(controller, client, "\t", code: VirtualKey.tab)
            type(text, controller, client)
        }
        func waitForPreview() -> Bool {
            pump(timeout: 5) { if case .translating = controller.composer.phase { return false } else { return true } }
        }
        client.inserted.removeAll()

        // "@config " with nothing after it: a hint with examples; ⏎ does nothing.
        command("")
        let hint = controller.panelModel()
        check(client.marked == "config › " && { if case let .hint(text) = hint.status { return text.contains("微信里用中文") } else { return false } }(),
              "@config with nothing after it hints what to write (\(hint.status))")
        _ = enter(controller, client)
        check(model.requests == 0 && controller.composer.phase == .drafting, "⏎ with nothing typed sends nothing")
        controller.commitComposition(client)
        client.inserted.removeAll()

        // The preview: a row per change, old → new, a refused part with its reason; nothing goes in yet.
        model.answer = """
            {"changes": [{"key": "candidateLayout", "value": "vertical"}, {"key": "appProfiles.*.inputLanguage", "app": "微信", "value": "zh"},
                         {"key": "customCommands", "value": []}], "note": "竖排候选，微信里用中文。"}
            """
        command("candidates in a column")
        _ = enter(controller, client)
        check(waitForPreview() && controller.composer.phase == .choosing && model.requests == 1, "the request goes to the on-device model")
        let rows = controller.panelModel().rows.map(\.text)
        check(rows == ["候选排列：横排 → 竖排", "按 App · WeChat · 开始的输入语言：跟全局一样 → 中文", "✕ customCommands：不能在这里改，请打开设置"],
              "the preview shows each change and the refused part (\(rows))")
        let footer = controller.panelModel().footer
        check(footer.hasPrefix("⏎ / 1 全部应用") && controller.panelModel().detail == "本机", "⏎ applies all; on device (\(footer))")
        snapshot("config-preview", in: snapshotDirectory)
        check(file().candidateLayout == .horizontal && client.inserted.isEmpty, "nothing changed or inserted before ⏎")

        // ⏎: written to the file, the confirmation with ⌘Z; nothing inserted.
        _ = enter(controller, client)
        let applied = file()
        check(applied.candidateLayout == .vertical && applied.profile(for: "com.tencent.xinWeChat")?.inputLanguage == .chinese,
              "⏎ applies the changes to the config file")
        check(controller.composer.choices.map(\.text) == ["已修改 2 项设置"] && client.inserted.isEmpty,
              "the confirmation shows, nothing is inserted (\(controller.composer.choices.map(\.text)))")
        check(controller.panelModel().footer.hasPrefix("⌘Z 撤销"), "⌘Z undoes it (\(controller.panelModel().footer))")
        snapshot("config-applied", in: snapshotDirectory)
        check(controller.composer.horizontalCandidates == false, "the input method follows the change at once")

        // ⌘Z: the values those keys had, back.
        press(controller, client, "z", code: 0x06, flags: .command)
        let undone = file()
        check(undone.candidateLayout == .horizontal && undone.appProfiles.isEmpty && controller.composer.phase == .idle,
              "⌘Z puts back exactly what changed")
        check(controller.panelModel().detail == "已撤销刚才的设置修改", "and says so (\(controller.panelModel().detail ?? "-"))")
        command("undo")
        _ = enter(controller, client)
        check(controller.panelModel().detail == "10 分钟内没有可以撤销的设置修改" && model.requests == 1,
              "@config undo with nothing to undo says so, sends nothing (\(controller.panelModel().detail ?? "-"))")
        client.inserted.removeAll()

        // Refine: typing more asks again with the answer before; Esc goes back to it.
        model.answer = #"{"changes": [{"key": "outputLanguages", "value": ["en", "fr"]}]}"#
        command("translate into English and French")
        _ = enter(controller, client)
        _ = waitForPreview()
        model.answer = #"{"changes": [{"key": "outputLanguages", "value": ["en", "fr", "de"]}]}"#
        type("also german", controller, client)
        let refining = controller.panelModel().footer
        check(refining == "⇧⏎ 修改 · ⏎ 全部应用 · Esc 清除", "the refine line's footer says ⇧⏎ refines, ⏎ applies (\(refining))")
        _ = shiftEnter(controller, client)  // ⇧⏎ sends the line (⏎ would apply the proposal shown)
        _ = waitForPreview()
        let refined = controller.panelModel().rows.map(\.text)
        check(refined == ["翻译语言：英文、中文 → 英文、法语、德语"] && model.requests == 3 && model.prompts.last == "<refine>also german</refine>",
              "typing more refines the proposal (\(refined), \(model.requests) requests, \(model.prompts.last ?? "-"))")
        _ = escape(controller, client)
        check(controller.panelModel().rows.map(\.text) == ["翻译语言：英文、中文 → 英文、法语"], "Esc goes back to the proposal before")
        _ = escape(controller, client)
        _ = escape(controller, client)
        check(file().outputLanguages == [.english, .chinese] && client.inserted.isEmpty, "Esc cancels: nothing changed or inserted")
        controller.commitComposition(client)
        client.inserted.removeAll()

        // Nothing it can do: one line.
        model.answer = #"{"changes": [{"key": "plugins", "value": []}]}"#
        command("install the weather plugin")
        _ = enter(controller, client)
        _ = waitForPreview()
        check(controller.composer.phase == .failed("✕ plugins：不能在这里改，请打开设置"), "a refused request is one line (\(controller.composer.phase))")
        _ = enter(controller, client)
        check(controller.composer.phase == .drafting && client.inserted.isEmpty, "⏎ then goes back to the text, inserting nothing")
        controller.commitComposition(client)
        client.inserted.removeAll()

        // A key typed into the text: never sent; the key field opens instead.
        command("")
        for ch in "sk-ant-" + "api03-abcdefghijklmnopqrstuvwxyz0123456789" {  // "-" is its own key
            press(controller, client, String(ch), code: ch == "-" ? 0x1B : keyCodes[ch] ?? 0)
        }
        _ = enter(controller, client)
        check(model.requests == 4 && opened == [.anthropic] && controller.composer.phase == .idle && client.inserted.isEmpty,
              "a key typed into @config isn't sent, nor inserted; the key field opens (\(opened), \(model.requests) requests, '\(client.marked)')")
        _ = pump(timeout: 0.2) { false }

        // A provider change: applied, then Test Connection runs.
        model.answer = #"{"changes": [{"key": "provider", "value": "anthropic"}]}"#
        command("use Claude")
        _ = enter(controller, client)
        _ = waitForPreview()
        _ = enter(controller, client)
        _ = pump(timeout: 3) { controller.composer.configState.status?.hasPrefix("✓") == true }
        check(file().provider == .anthropic && tested == 1 && controller.composer.choices.last?.text == "✓ 连接正常：0.8 s: Hello",
              "a provider change runs Test Connection (\(controller.composer.choices.map(\.text)))")
        _ = escape(controller, client)

        // A provider without a key isn't switched to (nothing would work): its row says so; ⏎ applies the rest and opens
        // Settings at its key field, where it is chosen once the key is saved. No Test Connection.
        model.answer = #"{"changes": [{"key": "provider", "value": "gemini"}, {"key": "candidateLayout", "value": "vertical"}]}"#
        command("use Gemini, candidates in a column")
        _ = enter(controller, client)
        _ = waitForPreview()
        let keyless = controller.panelModel().rows.map(\.text)
        check(keyless == ["候选排列：横排 → 竖排", "Gemini API 需要 API key：⏎ 打开设置去填（不会发给 AI），可以在那里换过去"],
              "a provider without a key: the row says it's needed, no switch shown (\(keyless))")
        _ = enter(controller, client)
        _ = pump(timeout: 2) { opened.count == 2 }
        check(file().provider == .anthropic && file().candidateLayout == .vertical && opened == [.anthropic, .gemini] && tested == 1
              && client.inserted.isEmpty, "⏎ applies the rest and opens Gemini's key field; the provider stays (\(file().provider), \(opened))")
        _ = escape(controller, client)

        _ = pump(timeout: 13) { controller.panelModel().detail == nil }  // the notices before go (the key's is up 12 s)
        // The release notes' images: three changes, in Chinese (config-changes.png), then in English.
        let changes = """
            {"changes": [{"key": "outputLanguages", "value": ["en", "fr"]}, {"key": "appProfiles.*.inputLanguage", "app": "WeChat", "value": "zh"},
                         {"key": "candidateLayout", "value": "vertical"}]}
            """
        try? start.write(to: url)
        controller.applySettings()
        model.answer = changes
        command("translate into English and French, Chinese in WeChat, candidates in a column")
        _ = enter(controller, client)
        _ = waitForPreview()
        snapshot("config-changes", in: snapshotDirectory)
        _ = escape(controller, client)
        controller.commitComposition(client)
        settings.uiLanguage = .english
        try? start.write(to: url)
        controller.loadSettings = { var config = (try? Config.load(from: url)) ?? SelfTest.settings; config.uiLanguage = .english; return config }
        controller.applySettings()
        model.answer = changes
        command("translate into English and French, Chinese in WeChat, candidates in a column")
        _ = enter(controller, client)
        _ = waitForPreview()
        let english = controller.panelModel().rows.map(\.text)
        check(english == ["Translation languages: English, Chinese → English, French", "Candidate layout: Horizontal → Vertical",
                          "Apps · WeChat · Starts in: Same as everywhere → Chinese"], "the preview in English (\(english))")
        snapshot("config-preview-en", in: snapshotDirectory)
        _ = escape(controller, client)
        controller.commitComposition(client)
        check(client.inserted.allSatisfy { $0.hasPrefix("@config") }, "nothing but the draft as typed ever went in")
        testRememberQuestionsReload(snapshotDirectory: snapshotDirectory)
        testKeyStatus(snapshotDirectory: snapshotDirectory)
        testKeyFieldsKeepKeys(snapshotDirectory: snapshotDirectory)
    }

    /// A key row never removes a key, and says whether there is one. Settings opened at the key of the provider in use
    /// (as `@config` opens it) shows its paste field; ⏎ on it empty, the focus moved on and the window closed: every key
    /// is still there. An empty or blank save does nothing; only Remove…, confirmed (`removeKey`), removes one, and only
    /// that one. Another provider's key opens the key sheet instead (nothing of it on this page): Esc changes nothing,
    /// Save keeps the key without switching, Save and Use switches and runs Test Connection. In an in-memory keychain:
    /// the user's is never touched.
    static func testKeyFieldsKeepKeys(snapshotDirectory: URL) {
        let url = snapshotDirectory.appendingPathComponent("keyfields-config.json")
        let saved = (APIKeys.keychain, AIConfigSession.keySource, SettingsModel.looksUpKeys)
        let store = APIKeys.Keychain.inMemory()
        APIKeys.keychain = store
        defer {
            (APIKeys.keychain, AIConfigSession.keySource, SettingsModel.looksUpKeys) = saved
            try? FileManager.default.removeItem(at: url)
            _ = secureInputGoes()  // a key field's, if it had the focus
        }
        try? APIKeys.save("sk-selftest-gemini-0001", for: .gemini)
        try? APIKeys.save("sk-selftest-openai-0002", for: .openai)
        AIConfigSession.keySource = { APIKeys.hasKeychainKey(account: $0.rawValue) ? .keychain : .none }
        SettingsModel.looksUpKeys = true
        var config = Config.default
        config.provider = .gemini
        try? config.write(to: url)
        func provider() -> Provider { ((try? Config.load(from: url)) ?? .default).provider }
        let model = SettingsModel(configURL: url)
        var tested = 0
        model.testRunner = { tested += 1 }
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model, page: .provider)))
        window.setContentSize(NSSize(width: 880, height: 700))
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        _ = pump(timeout: 2) { model.keySources[.gemini] == .keychain }
        check(model.keyStatus(.gemini) == tr("✓ 已保存 · 结尾 0001", "✓ Saved · ends in 0001"),
              "the row says the key is saved, with its last 4 characters (\(model.keyStatus(.gemini)))")
        func keys() -> [String?] { [store.read("gemini"), store.read("openai"), store.read("anthropic")] }
        let all: [String?] = ["sk-selftest-gemini-0001", "sk-selftest-openai-0002", nil]
        /// A key pressed in `target`: its first responder gets it, or, as a key equivalent (Esc, ⌘⏎), the button that has it
        /// (the window needn't be the key window: the self-test may not be the active app).
        func key(_ characters: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = [], in target: NSWindow, equivalent: Bool = false) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                                                   timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: target.windowNumber,
                                                   context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                                   isARepeat: false, keyCode: code) else { continue }
                if !equivalent { target.sendEvent(event) } else if type == .keyDown { _ = target.performKeyEquivalent(with: event) }
            }
            _ = pump(timeout: 0.15) { false }
        }
        func type(_ text: String, in target: NSWindow) {
            for character in text { key(String(character), character == "-" ? 0x1B : keyCodes[character] ?? 0, in: target) }
        }
        /// `@config` asking Settings for `provider`'s key: the sheet once it's up (another provider), else nil.
        func ask(_ provider: Provider) -> NSWindow? {
            NotificationCenter.default.post(name: .allInOneIMEFocusAPIKey, object: nil, userInfo: ["provider": provider.rawValue])
            if provider == .gemini {  // the one in use: its own row
                _ = pump(timeout: 1) { window.firstResponder is NSText }
                return nil
            }
            _ = pump(timeout: 3) { window.attachedSheet != nil }
            _ = pump(timeout: 0.5) { false }  // its field focused
            return window.attachedSheet
        }

        // The provider in use: its own row, the paste field focused; ⏎ on it empty, then Tab away.
        _ = ask(.gemini)
        let focused = window.firstResponder is NSText  // a field editor: the paste field has the focus
        key("\r", 0x24, in: window)
        key("\t", 0x30, in: window)
        check(focused && window.attachedSheet == nil && keys() == all,
              "the key of the provider in use: its own row's paste field (focused: \(focused)); ⏎ on it empty removes nothing")

        // Another provider: the sheet. ⏎ on it empty saves nothing; Esc closes it and changes nothing.
        let sheet = ask(.openai)
        check(sheet != nil && provider() == .gemini, "another provider's key opens the key sheet, the provider stays")
        if let sheet {
            key("\r", 0x24, in: sheet)
            key("\u{1b}", 0x35, in: sheet, equivalent: true)
            _ = pump(timeout: 2) { window.attachedSheet == nil }
        }
        check(sheet != nil && window.attachedSheet == nil && keys() == all && provider() == .gemini, "Esc closes the sheet and changes nothing")

        // Save (⏎): the key kept, no switch.
        let saving = ask(.anthropic)
        if let saving {
            type("sk-selftest-claude-0003", in: saving)
            key("\r", 0x24, in: saving)
            _ = pump(timeout: 2) { window.attachedSheet == nil }
        }
        check(saving != nil && window.attachedSheet == nil && store.read("anthropic") == "sk-selftest-claude-0003" && provider() == .gemini
              && tested == 0, "Save keeps the key and doesn't switch (\(provider().rawValue))")

        // Save and Use (⌘⏎): kept, switched to, Test Connection run.
        let using = ask(.openai)
        if let using {
            type("sk-selftest-openai-0004", in: using)
            key("\r", 0x24, .command, in: using, equivalent: true)
            _ = pump(timeout: 2) { window.attachedSheet == nil }
        }
        check(using != nil && window.attachedSheet == nil && store.read("openai") == "sk-selftest-openai-0004" && provider() == .openai
              && tested == 1, "Save and Use keeps the key, switches to it and runs Test Connection (\(provider().rawValue), \(tested))")
        if let open = window.attachedSheet { window.endSheet(open) }  // whatever failed above: not left up

        window.close()
        _ = pump(timeout: 0.3) { false }
        let now: [String?] = ["sk-selftest-gemini-0001", "sk-selftest-openai-0004", "sk-selftest-claude-0003"]
        check(keys() == now, "closing the window removes no key")
        model.saveKey("", for: .gemini)
        model.saveKey("  \n", for: .gemini)
        check(keys() == now, "an empty or blank key saved leaves the key there")
        model.removeKey(.gemini)
        check(keys() == [nil, "sk-selftest-openai-0004", "sk-selftest-claude-0003"], "Remove…, confirmed, removes that key only")
    }

    /// Settings → AI Provider says in each key's row whether it is set, from the lookup `@config`'s checks and `@doctor`'s
    /// use too (a stand-in here: the user's keychain is never asked): a key in the keychain is "✓ Saved · ends in a1b2"
    /// (its last 4 kept with it, not read), one in the shell names its variable, none is "No API key yet".
    static func testKeyStatus(snapshotDirectory: URL) {
        let url = snapshotDirectory.appendingPathComponent("keys-config.json")
        let saved = (AIConfigSession.keySource, SettingsModel.looksUpKeys, APIKeys.keychain)
        defer {
            (AIConfigSession.keySource, SettingsModel.looksUpKeys, APIKeys.keychain) = saved
            try? FileManager.default.removeItem(at: url)
        }
        // The keychain in memory: OpenAI's key saved (its last 4 kept), Claude's in the shell, Gemini's nowhere.
        APIKeys.keychain = .inMemory()
        try? APIKeys.save("sk-selftest-openai-a1b2", for: .openai)
        AIConfigSession.keySource = { $0 == .openai ? .keychain : $0 == .anthropic ? .environment("ANTHROPIC_API_KEY") : .none }
        SettingsModel.looksUpKeys = true
        try? Config.default.write(to: url)
        let model = SettingsModel(configURL: url)
        model.refreshKeys()
        _ = pump(timeout: 3) { !model.keySources.isEmpty }
        let shown = [Provider.openai, .anthropic, .gemini].map(model.keyStatus)
        check(shown == [tr("✓ 已保存 · 结尾 a1b2", "✓ Saved · ends in a1b2"), tr("✓ 来自 $ANTHROPIC_API_KEY", "✓ From $ANTHROPIC_API_KEY"),
                        tr("还没有 API key", "No API key yet")], "Settings says in each key's row whether it is set (\(shown))")
        let keyed = AIConfigSession.providersWithKey(AIConfigSession.keySource)
        check(keyed == [.openai, .anthropic], "@config's and @doctor's checks see the same keys (\(keyed))")
    }

    /// Settings deletes the questions kept only when its switch turns "Remember recent questions" off, never when the
    /// window reads the config again with it off (as `@config` writes it, which may still be undone).
    static func testRememberQuestionsReload(snapshotDirectory: URL) {
        let url = snapshotDirectory.appendingPathComponent("remember-config.json")
        defer {
            try? FileManager.default.removeItem(at: url)
            QuestionHistoryStore.clear()
        }
        var config = settings
        config.rememberQuestions = true
        try? config.write(to: url)
        let model = SettingsModel(configURL: url)
        QuestionHistoryStore.clear()
        QuestionHistoryStore.record(QuestionHistory.Entry(question: "一加一等于几", answer: "二", date: Date()))
        config.rememberQuestions = false
        try? config.write(to: url)
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        model.reloadIfChanged()
        check(!model.config.rememberQuestions && QuestionHistoryStore.history.entries.count == 1,
              "Settings reading the config again with the switch off keeps the questions (\(QuestionHistoryStore.history.entries.count))")
        model.setRememberQuestions(true)
        model.setRememberQuestions(false)
        check(QuestionHistoryStore.history.entries.isEmpty, "turning the switch off in Settings deletes them")
    }
}
