import AllInOneIMECore
import AppKit

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
        print("— @config: settings by describing them (canned answer)")
        let realBefore = try? Data(contentsOf: Config.defaultURL)
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
            check((try? Data(contentsOf: Config.defaultURL)) == realBefore, "@config: the user's config file was not touched")
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
        for ch in "sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789" {  // "-" is its own key
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

        _ = pump(timeout: 4) { controller.panelModel().detail == nil }  // the notices before go
        // The release notes' images: the preview in English too.
        settings.uiLanguage = .english
        try? start.write(to: url)
        controller.loadSettings = { var config = (try? Config.load(from: url)) ?? SelfTest.settings; config.uiLanguage = .english; return config }
        controller.applySettings()
        model.answer = """
            {"changes": [{"key": "outputLanguages", "value": ["en", "fr"]}, {"key": "appProfiles.*.inputLanguage", "app": "WeChat", "value": "zh"},
                         {"key": "candidateLayout", "value": "vertical"}]}
            """
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
