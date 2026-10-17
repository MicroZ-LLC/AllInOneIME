import AllInOneIMECore
import AppKit

extension SelfTest {
    /// Per-app settings (`AppProfile`) through the fake text field pretending to be two apps: a chat app that starts in
    /// English and has no AI (an AI command is refused with a notice, @js still runs), and a mail app that starts
    /// in pinyin, types results out and rewrites formally only (live Bedrock); back in the chat app, English again.
    /// Then the input menu's "This App" item, and Settings → Apps rendered in Chinese and English.
    static func testAppProfiles(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        section("per-app settings (two apps through the fake client)", needs: .composing)
        let (chat, mail) = ("com.example.chat", "com.example.mail")
        let (settingsBefore, converterBefore, recordBefore) = (settings, controller.converter, controller.recordApp)
        var recorded: [String] = []
        controller.recordApp = { recorded.append($0) }  // never the user's list of recent apps
        defer {
            (settings, controller.converter, controller.recordApp) = (settingsBefore, converterBefore, recordBefore)
            controller.commitComposition(client)
            client.bundleIDOverride = nil
            controller.activateServer(client)
            controller.composer.setInputMode(settings.defaultInput)
        }
        settings.setOrder([Language.chinese, .english])  // pinyin by default
        settings.typeOut = false
        settings.appProfiles = [chat: AppProfile(inputLanguage: .english, noAI: true),
                                mail: AppProfile(inputLanguage: .chinese, rewriteStyles: ["正式"], typeOut: true)]
        let profiles = settings.appProfiles
        // The live requests with the same profiles (the self-test's config otherwise, translating into English).
        controller.converter = Converter(loadConfig: {
            var config = try Config.load()
            config.setOrder([OutputLanguage.english, .chinese])
            config.appProfiles = profiles
            return config
        })
        controller.commitComposition(client)
        client.inserted.removeAll()

        // The chat app: a new field starts in English; an AI command is refused, its draft kept; the others run.
        client.bundleIDOverride = chat
        controller.activateServer(client)
        check(controller.composer.inputLanguage == .english && !controller.composer.typesResults,
              "the chat app's field starts in English (\(controller.composer.inputLanguage.rawValue)), results not typed out")
        check(recorded.last == chat, "the app is kept for Add App… (\(recorded))")
        improve(controller, client)
        type("hello there", controller, client)
        act(controller, client)
        check(!controller.composer.isLevelTwo && client.marked == "improve › hello there" && client.inserted.isEmpty,
              "@improve in the chat app sends nothing, the draft stays (\(client.marked), \(controller.composer.phase))")
        check(controller.composer.aiRefusal() == AppProfileText.refusal, "…with the notice: \(controller.composer.aiRefusal() ?? "none")")
        _ = escape(controller, client)
        _ = escape(controller, client)
        press(controller, client, "@", code: 0x13, flags: .shift)
        type("js", controller, client)
        press(controller, client, "\t", code: VirtualKey.tab)
        type("6", controller, client)
        press(controller, client, "*", code: 0x1C, flags: .shift)
        type("7", controller, client)
        act(controller, client)
        if finishConversion(controller, "@js 6*7 in the chat app") {
            check(controller.composer.choices.contains { $0.text == "42" }, "@js still runs there")
        }
        _ = escape(controller, client)
        _ = escape(controller, client)
        controller.commitComposition(client)

        // The mail app: pinyin, typed out, its own rewrite style only (live Bedrock).
        needing([.composing, .bedrock])
        client.bundleIDOverride = mail
        controller.activateServer(client)
        check(controller.composer.inputLanguage == .chinese && controller.composer.typesResults && controller.composer.aiRefusal() == nil,
              "the mail app's field starts in pinyin, types results out, may use AI")
        improve(controller, client)
        type("wojintianyoudianbushufu", controller, client)
        act(controller, client)
        if finishConversion(controller, "@improve in the mail app") {
            let rewrites = controller.composer.choices.filter(\.kind.isRewrite)
            check(rewrites.count == 1 && rewrites.first?.kind == .rewrite("正式"),
                  "only the mail app's style, 正式 (\(rewrites.map { "\($0.kind)" }))")
        }
        _ = escape(controller, client)
        _ = escape(controller, client)
        controller.commitComposition(client)

        // The chat app again (a Shift there before sticks no more than the default would): English.
        needing(.composing)
        controller.composer.setInputMode(.chinese)
        client.bundleIDOverride = chat
        controller.activateServer(client)
        check(controller.composer.inputLanguage == .english, "back in the chat app: English again")
        // An app without a profile: the default input.
        client.bundleIDOverride = "com.example.other"
        controller.activateServer(client)
        check(controller.composer.inputLanguage == .chinese && !controller.composer.typesResults && controller.composer.aiRefusal() == nil,
              "an app without its own settings: pinyin, not typed out, AI allowed")

        // The input menu has the app's item (by its bundle id: the app isn't installed), with its toggles.
        client.bundleIDOverride = chat
        controller.activateServer(client)
        let item = controller.menu()?.items.first { $0.title.hasPrefix(tr("这个 App：", "This App: ")) }
        let titles = item?.submenu?.items.map(\.title) ?? []
        check(item?.title.hasSuffix(chat) == true && titles.contains(tr("不用 AI", "No AI")) && titles.contains(tr("逐字上屏", "Type Results Out")),
              "the input menu's \(item?.title ?? "This App item") (\(titles.filter { !$0.isEmpty }.joined(separator: ", ")))")

        // Settings → Apps, in both languages, with sample apps (nothing saved).
        needing([])
        let chosen = UIText.choice
        defer { UIText.choice = chosen }
        for (name, language) in [("settings-apps", "zh"), ("settings-apps-en", "en")] {
            UIText.choice = language
            let preview = SettingsModel(configURL: Config.defaultURL, persists: false)
            preview.config.setOrder([Language.chinese, .english])
            preview.config.appProfiles = AppProfileSamples.profiles
            let url = snapshotDirectory.appendingPathComponent("\(name).png")
            SettingsImage.render(preview, page: .apps, to: url) { seconds in _ = pump(timeout: seconds) { false } }
            check(FileManager.default.fileExists(atPath: url.path), "Settings → Apps rendered (\(language))")
        }
        check(SettingsPage.apps.matches("slack") && SettingsPage.apps.matches("不用 AI") && SettingsPage.apps.matches("按 App"),
              "the search finds Settings → Apps")
    }
}
