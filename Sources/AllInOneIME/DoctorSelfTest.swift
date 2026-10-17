import AllInOneIMECore
import AppKit

extension SelfTest {
    /// `@doctor` with fake probes (a missing language pack, a typing speed out of range, no key for the provider) and a
    /// stand-in connection test, on a config file of the self-test's own: the findings, problems first, numbered where a
    /// fix can be picked; a fix through `@config`'s preview, applied and undone; an action fix recorded, not run; a
    /// question answered by a stand-in on-device model. The user's config is never touched.
    static func testDoctor(_ controller: AllInOneIMEInputController, _ client: FakeTextClient, snapshotDirectory: URL) {
        section("@doctor: checks and fixes (fake probes)", needs: .composing)
        let realBefore = try? Data(contentsOf: Config.userURL)
        let url = snapshotDirectory.appendingPathComponent("doctor-config.json")
        var performed: [AIConfig.Action] = []
        var opened: [Provider] = []
        let saved = (AIConfigSession.url, AIConfigSession.environment, AIConfigSession.openKeyField, AIConfigSession.testConnection,
                     AIConfigSession.lastApplied, DoctorSession.probe, DoctorSession.perform, DoctorSession.service)
        let (settingsBefore, loadBefore) = (settings, controller.loadSettings)
        // Requests here go to a stand-in: nothing to refuse while the screen is locked.
        let secureBefore = controller.secureInputActive
        controller.secureInputActive = { false }
        defer {
            controller.commitComposition(client)
            controller.secureInputActive = secureBefore
            (AIConfigSession.url, AIConfigSession.environment, AIConfigSession.openKeyField, AIConfigSession.testConnection,
             AIConfigSession.lastApplied, DoctorSession.probe, DoctorSession.perform, DoctorSession.service) = saved
            (settings, controller.loadSettings) = (settingsBefore, loadBefore)
            controller.applySettings()
            controller.composer.setInputMode(settings.defaultInput)
            try? FileManager.default.removeItem(at: url)
            check((try? Data(contentsOf: Config.userURL)) == realBefore, "@doctor: the user's config file was not touched")
        }
        var start = settings
        start.provider = .anthropic
        start.typeOutRate = 100
        start.setOrder([Language.korean, .chinese, .english])
        try? start.write(to: url)
        AIConfigSession.url = url
        AIConfigSession.lastApplied = nil
        AIConfigSession.environment = { _ in AIConfig.Environment(hasKey: { _ in false }, chinese: UIText.chinese) }
        AIConfigSession.openKeyField = { opened.append($0) }
        AIConfigSession.testConnection = { _ in (false, "No API key for the Claude API") }
        DoctorSession.perform = { performed.append($0) }
        DoctorSession.probe = {
            var facts = Doctor.Facts()
            facts.inputMethod.version = AppVersion.string
            facts.configData = try? Data(contentsOf: url)
            facts.config = try? Config.load(from: url)
            facts.keySaved = [.anthropic: false]
            facts.apple = .available
            facts.accessibility = .granted
            facts.microphone = .granted
            facts.packs = [.chinese: .installed, .korean: .missing]
            return facts
        }
        controller.loadSettings = { (try? Config.load(from: url)) ?? SelfTest.settings }
        controller.applySettings()
        func file() -> Config { (try? Config.load(from: url)) ?? .default }
        func doctor(_ question: String = "") {
            controller.composer.setInputMode(.english)  // the text as letters (not while composing: before the "@")
            press(controller, client, "@", code: 0x13, flags: .shift)
            type("doc", controller, client)
            press(controller, client, "\t", code: VirtualKey.tab)
            type(question, controller, client)
            _ = enter(controller, client)
            _ = pump(timeout: 5) { controller.composer.phase == .choosing && controller.composer.configState.report?.isFinal == true }
        }
        /// A fix's preview is worked out in the panel's task (`previewFixes`): shown once the run loop has run it.
        func previewShown() { _ = pump(timeout: 5) { controller.composer.configState.fixPreview != nil } }
        client.inserted.removeAll()
        _ = pump(timeout: 4) { controller.panelModel().detail == nil }  // the notices before go

        doctor()
        let panel = controller.panelModel()
        let rows = panel.rows
        check(rows.first?.text.hasPrefix("✗") == true && rows.last?.text.hasPrefix("✓") == true, "problems first, then what is fine")
        // No key saved: Test Connection isn't run, the provider's row says what's missing (no second ✗ row).
        check(rows.contains { $0.text == "✗ 韩语语言包没有装 — 装好以前打不了韩语" } && rows.contains { $0.text.hasPrefix("✗ 打字速度超出范围") }
              && !rows.contains { $0.text.hasPrefix("✗ 连接失败") } && rows.contains { $0.text.hasPrefix("✓ AllInOneIME") },
              "the findings (\(rows.map(\.text)))")
        check(rows.filter { !$0.label.isEmpty }.map(\.label) == ["1", "2", "3"], "the fixable ones are numbered (\(rows.map(\.label)))")
        check({ if case let .hint(text) = panel.status { return text.hasPrefix("3 个问题") } else { return false } }()
              && panel.footer.hasPrefix("数字 修这一项"), "the summary and keys (\(panel.status) | \(panel.footer))")
        snapshot("doctor", in: snapshotDirectory)

        // The typing speed's fix, through @config's preview: applied, then ⌘Z.
        let speed = rows.first { $0.text.hasPrefix("✗ 打字速度") }?.label ?? "?"
        type(speed, controller, client)
        previewShown()
        check(controller.panelModel().rows.map(\.text) == ["打字速度：每秒 100 个字 → 每秒 16 个字"],
              "a fix shows as @config's preview (\(controller.panelModel().rows.map(\.text)))")
        snapshot("doctor-fix", in: snapshotDirectory)
        _ = enter(controller, client)
        check(file().typeOutRate == 16 && client.inserted.isEmpty, "⏎ applies it to the config file")
        press(controller, client, "z", code: 0x06, flags: .command)
        check(file().typeOutRate == 100, "⌘Z puts it back")

        // ⏎ on the findings: the safe fixes (the speed); a pack download only when picked, recorded here.
        doctor()
        _ = enter(controller, client)
        previewShown()
        check(controller.panelModel().rows.map(\.text) == ["打字速度：每秒 100 个字 → 每秒 16 个字"], "⏎ previews the safe fixes")
        _ = escape(controller, client)
        let pack = controller.panelModel().rows.first { $0.text.hasPrefix("✗ 韩语语言包") }?.label ?? "?"
        type(pack, controller, client)
        previewShown()
        _ = enter(controller, client)
        _ = pump(timeout: 5) { !performed.isEmpty }
        check(performed == [.downloadPack(.korean)] && controller.composer.choices.first?.text == "已完成：下载韩语语言包",
              "a pack's fix downloads it once confirmed (\(performed))")
        _ = escape(controller, client)
        check(controller.composer.phase == .idle && client.inserted.isEmpty, "nothing is inserted")

        // The provider without a key: said as @config says it; its fix opens Settings at the key field, nothing else.
        doctor()
        let keyFinding = controller.panelModel().rows.first { $0.text.hasPrefix("✗ AI 服务") }
        check(keyFinding?.text == "✗ AI 服务：Claude API — 需要 API key：在设置里填（不会发给 AI）",
              "the provider's finding says its key is needed (\(keyFinding?.text ?? "-"))")
        type(keyFinding?.label ?? "?", controller, client)
        previewShown()
        check(controller.panelModel().rows.map(\.text) == ["Claude API 需要 API key：⏎ 打开设置去填（不会发给 AI）"],
              "its fix is @config's key row (\(controller.panelModel().rows.map(\.text)))")
        let provider = file().provider
        _ = enter(controller, client)
        _ = pump(timeout: 2) { !opened.isEmpty }
        check(opened == [.anthropic] && file().provider == provider && client.inserted.isEmpty,
              "⏎ opens Settings at the key field, nothing else (\(opened))")
        opened.removeAll()
        _ = pump(timeout: 4) { controller.panelModel().detail == nil }

        // A question: the model's explanation over the findings, its fixes first for ⏎.
        let model = CannedGuidedModel(#"{"explanation": "没有 Claude API 的 key，所以翻译发不出去。", "fixes": ["F1"]}"#)
        DoctorSession.service = DoctorService(client: ChatClient(apple: model))
        doctor("why no translate")
        let asked = controller.panelModel()
        check({ if case let .hint(text) = asked.status { return text.hasPrefix("没有 Claude API 的 key") } else { return false } }()
              && model.requests == 1 && asked.rows.first?.comment == "AI 建议", "the question is answered on device (\(asked.status))")
        snapshot("doctor-question", in: snapshotDirectory)
        _ = escape(controller, client)

        // In English, for the release notes.
        settings.uiLanguage = .english
        controller.loadSettings = { var config = (try? Config.load(from: url)) ?? SelfTest.settings; config.uiLanguage = .english; return config }
        controller.applySettings()
        DoctorSession.service = DoctorService(client: ChatClient(apple: CannedGuidedModel("{}")))
        _ = pump(timeout: 4) { controller.panelModel().detail == nil }
        doctor()
        check(controller.panelModel().rows.contains { $0.text == "✗ The Korean language pack isn't installed — Korean can't be typed until it is" },
              "the findings in English")
        snapshot("doctor-en", in: snapshotDirectory)
        _ = escape(controller, client)
        check(opened.isEmpty && client.inserted.isEmpty, "nothing opened or inserted unasked")
    }
}
