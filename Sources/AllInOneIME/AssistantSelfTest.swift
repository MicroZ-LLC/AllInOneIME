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

/// Holds whoever waits on it until it opens, cancelled or not.
final class SelfTestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var arrived = 0

    /// How many have come to it.
    var arrivals: Int { lock.withLock { arrived } }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            arrived += 1
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                waiting.append(continuation)
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let all = waiting
        waiting = []
        lock.unlock()
        all.forEach { $0.resume() }
    }
}

/// Stands in for the on-device model in the page's checks: a request whose sentence has `marker` in it is too long by
/// the model's count, given once `gate` opens (cancelled or not, as the framework's count goes on): the user's own
/// provider is asked instead. Any other is answered with `answer`.
final class TooLongGuidedModel: AppleGuidedBackend, @unchecked Sendable {
    let marker: String
    let gate: SelfTestGate?
    let answer: String

    init(marker: String, gate: SelfTestGate? = nil, answer: String) {
        self.marker = marker
        self.gate = gate
        self.answer = answer
    }

    var availability: AppleModelAvailability { .available }
    var contextSize: Int { 4096 }
    var supportedLanguages: Set<String> { ["en", "zh"] }

    func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
        AsyncThrowingStream { $0.finish(throwing: AppleModelError.failed("the self-test's model is held to a schema")) }
    }

    func tokenCount(of request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async -> Int? {
        guard request.prompt.contains(marker) else { return nil }
        await gate?.wait()
        return 100_000
    }

    func respond(to request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async throws -> String { answer }
}

extension SelfTest {
    /// What Settings → Assistant runs against in the self-test: a config file of its own, a stand-in on-device model,
    /// made-up apps and keys, a stand-in connection test and fake probes; the key field and the fixes' actions recorded,
    /// never done. Put back by `restore`.
    @MainActor
    final class AssistantRig {
        let url: URL
        let model = CannedGuidedModel("")
        var opened: [Provider] = []
        var performed: [AIConfig.Action] = []
        var tested = 0
        var probed = 0
        /// What the probes find (the config file as it is now, read with them).
        var facts: (URL) -> Doctor.Facts = { _ in Doctor.Facts() }
        private let saved = (AIConfigSession.url, AIConfigSession.service, AIConfigSession.environment, AIConfigSession.openKeyField,
                             AIConfigSession.testConnection, AIConfigSession.lastApplied, DoctorSession.probe, DoctorSession.perform,
                             DoctorSession.service)
        private let language = UIText.choice

        init(_ directory: URL, name: String, config: Config) {
            url = directory.appendingPathComponent(name)
            try? config.write(to: url)
            AIConfigSession.url = url
            AIConfigSession.service = AIConfigService(client: ChatClient(apple: model))
            AIConfigSession.lastApplied = nil
            AIConfigSession.environment = { typed in
                AIConfig.Environment(
                    apps: AIConfig.AppCatalog(apps: [.init(bundleID: "com.tencent.xinWeChat", names: ["WeChat", "微信"])]),
                    awsProfiles: { ["default"] }, knownModels: { $0 == .anthropic ? ["claude-haiku-5-5"] : [] },
                    hasKey: { $0 == .anthropic }, chinese: UIText.chinese, typedText: typed)
            }
            AIConfigSession.openKeyField = { [unowned self] in opened.append($0) }
            AIConfigSession.testConnection = { [unowned self] _ in
                tested += 1
                return (true, "0.8 s: Hello")
            }
            DoctorSession.perform = { [unowned self] in performed.append($0) }
            DoctorSession.probe = { [unowned self] in
                probed += 1
                return facts(url)
            }
        }

        func file() -> Config { (try? Config.load(from: url)) ?? .default }

        func restore() {
            (AIConfigSession.url, AIConfigSession.service, AIConfigSession.environment, AIConfigSession.openKeyField,
             AIConfigSession.testConnection, AIConfigSession.lastApplied, DoctorSession.probe, DoctorSession.perform,
             DoctorSession.service) = saved
            UIText.choice = language
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// The made-up setup the checks find: a language pack missing, a typing speed out of range, no key for the provider.
    static func troubledFacts(_ url: URL) -> Doctor.Facts {
        var facts = Doctor.Facts()
        facts.configData = try? Data(contentsOf: url)
        facts.config = try? Config.load(from: url)
        facts.keySaved = [.anthropic: false]
        facts.apple = .available
        facts.accessibility = .granted
        facts.microphone = .granted
        facts.packs = [.chinese: .installed, .korean: .missing]
        return facts
    }

    /// The made-up setup with nothing wrong: in use, a key for the provider, the apps it controls allowed, every pack in.
    static func fineFacts(_ url: URL) -> Doctor.Facts {
        var facts = Doctor.Facts()
        facts.configData = try? Data(contentsOf: url)
        facts.config = try? Config.load(from: url)
        facts.inputMethod.selected = true
        facts.keySaved = [.anthropic: true]
        facts.apple = .available
        facts.accessibility = .granted
        facts.automation = ["Notes": .granted, "Reminders": .granted, "Terminal": .granted]
        facts.packs = [.chinese: .installed, .korean: .installed]
        return facts
    }

    /// Settings → Assistant's first section, "Change settings in a sentence", on a config file of the self-test's own with
    /// a canned answer: the request → the preview (old → new, a refused part with its reason) → Apply writes the file →
    /// Undo puts it back; a request it can't do is one line; a key typed into the request is never sent (the key field
    /// opens); a provider change runs Test Connection, its result in the section; a provider without a key opens its key
    /// field and isn't switched to. The user's config file is never touched.
    static func testAIConfig(snapshotDirectory: URL) {
        section("Settings → Assistant: change settings in a sentence (canned answer)")
        let realBefore = try? Data(contentsOf: Config.userURL)
        var start = settings
        start.candidateLayout = .horizontal
        start.appProfiles = [:]
        start.setOrder([OutputLanguage.english, .chinese])
        let rig = AssistantRig(snapshotDirectory, name: "assistant-config.json", config: start)
        UIText.choice = .chinese
        defer {
            rig.restore()
            check((try? Data(contentsOf: Config.userURL)) == realBefore, "Assistant: the user's config file was not touched")
        }
        let model = rig.model
        let assistant = AssistantModel()
        func ask(_ request: String, _ answer: String) {
            model.answer = answer
            assistant.request = request
            assistant.sendRequest()
            _ = pump(timeout: 5) { !assistant.working }
        }

        // Nothing typed: Preview is off, nothing sent.
        assistant.request = "  "
        assistant.sendRequest()
        check(!assistant.canPreview && model.requests == 0 && assistant.preview == nil, "an empty request sends nothing")

        // The preview: a row per change, old → new, a refused part with its reason; nothing changes yet.
        ask("candidates in a column, Chinese in WeChat", """
            {"changes": [{"key": "candidateLayout", "value": "vertical"}, {"key": "appProfiles.*.inputLanguage", "app": "微信", "value": "zh"},
                         {"key": "customCommands", "value": []}], "note": "竖排候选，微信里用中文。"}
            """)
        check(model.requests == 1 && assistant.lines == ["候选排列：横排 → 竖排", "按 App · WeChat · 开始的输入语言：跟全局一样 → 中文",
                                                         "✕ customCommands：请到设置里对应的那一页改"],
              "the request goes to the on-device model; the preview shows each change and the refused part (\(assistant.lines))")
        check(assistant.preview?.note == "竖排候选，微信里用中文。" && rig.file().candidateLayout == .horizontal,
              "its note shows; nothing changed before Apply")

        // Apply: written to the file, "已改 2 项" with Undo.
        assistant.apply()
        let applied = rig.file()
        check(applied.candidateLayout == .vertical && applied.profile(for: "com.tencent.xinWeChat")?.inputLanguage == .chinese,
              "Apply writes the changes to the config file")
        check(assistant.applied == "已改 2 项" && assistant.canUndo && assistant.preview == nil,
              "the section says what changed and offers Undo (\(assistant.applied ?? "-"))")
        check(rig.tested == 0, "no Test Connection when the provider didn't change")

        // Undo: the values those keys had, back.
        assistant.undo()
        let undone = rig.file()
        check(undone.candidateLayout == .horizontal && undone.appProfiles.isEmpty, "Undo puts back exactly what changed")
        check(assistant.undone == "已撤销刚才的设置修改" && assistant.applied == nil && !assistant.canUndo,
              "and says so (\(assistant.undone ?? "-"))")

        // Undo of a key changed since: left as it is, and named.
        ask("translate into English and French", #"{"changes": [{"key": "outputLanguages", "value": ["en", "fr"]}]}"#)
        assistant.apply()
        var changed = rig.file()
        changed.candidateLayout = .vertical
        changed.setOrder([OutputLanguage.english, OutputLanguage("de")])
        try? changed.write(to: rig.url)
        assistant.undo()
        check(rig.file().outputLanguages.map(\.code) == ["en", "de"] && assistant.undone?.hasPrefix("已撤销；这些之后又改过，没有动：") == true,
              "Undo leaves a setting changed since, and names it (\(assistant.undone ?? "-"))")
        try? start.write(to: rig.url)

        // Cancel: nothing changes.
        ask("translate into English and French", #"{"changes": [{"key": "outputLanguages", "value": ["en", "fr"]}]}"#)
        assistant.dismissPreview()
        check(assistant.preview == nil && rig.file().outputLanguages == [.english, .chinese], "Cancel on the preview changes nothing")

        // A preview made before the settings changed elsewhere goes when the page shows again; one still current stays.
        ask("translate into English and French", #"{"changes": [{"key": "outputLanguages", "value": ["en", "fr"]}]}"#)
        assistant.dropStalePreview()
        let kept = assistant.preview != nil
        var elsewhere = rig.file()
        elsewhere.typeOut.toggle()
        try? elsewhere.write(to: rig.url)
        assistant.dropStalePreview()
        check(kept && assistant.preview == nil, "a preview stays while the settings are as they were, and goes once they changed elsewhere")
        try? start.write(to: rig.url)

        // Nothing it can do: one line.
        ask("install the weather plugin", #"{"changes": [{"key": "plugins", "value": []}]}"#)
        check(assistant.preview == nil && assistant.message == "✕ plugins：请到设置里对应的那一页改",
              "a refused request is one line (\(assistant.message ?? "-"))")
        ask("make it nice", "not json")
        check(assistant.message == "没能把这句话变成设置", "an answer that isn't settings is one line (\(assistant.message ?? "-"))")

        // A key typed into the request: never sent; the key field opens instead.
        let requests = model.requests
        assistant.request = "sk-ant-" + "api03-abcdefghijklmnopqrstuvwxyz0123456789"
        assistant.sendRequest()
        check(model.requests == requests && rig.opened == [.anthropic] && assistant.message == AIConfig.Text(chinese: true).droppedKey,
              "a key typed into the request isn't sent; the key field opens (\(rig.opened))")
        check(assistant.request.isEmpty, "and it doesn't stay in the field")

        // A key with other words: the words go, the key doesn't (nor stays in the field); the preview says so.
        let key = "sk-ant-" + "api03-abcdefghijklmnopqrstuvwxyz0123456789"
        ask("candidates in a column " + key, #"{"changes": [{"key": "candidateLayout", "value": "vertical"}]}"#)
        check(model.requests == requests + 1 && !(model.prompts.last ?? key).contains(key) && assistant.preview?.droppedKey == true
              && !assistant.request.contains(key) && assistant.request.hasPrefix("candidates in a column"),
              "a key mixed into a request is dropped before it's sent and from the field; the preview says so (\(assistant.request))")
        assistant.dismissPreview()

        // A provider change: applied, then Test Connection, its result in the section.
        ask("use Claude", #"{"changes": [{"key": "provider", "value": "anthropic"}]}"#)
        assistant.apply()
        _ = pump(timeout: 3) { assistant.connection?.hasPrefix("✓") == true }
        check(rig.file().provider == .anthropic && rig.tested == 1 && assistant.connection == "✓ 连接正常：0.8 s: Hello",
              "a provider change runs Test Connection, its result under the confirmation (\(assistant.connection ?? "-"))")

        // A provider without a key isn't switched to: its row says so; Apply applies the rest and opens its key field.
        ask("use Gemini, candidates in a column",
            #"{"changes": [{"key": "provider", "value": "gemini"}, {"key": "candidateLayout", "value": "vertical"}]}"#)
        check(assistant.lines == ["候选排列：横排 → 竖排", "Gemini API 需要 API key：点「应用」后在「AI」里填（不会发给 AI）"],
              "a provider without a key: the row says it's needed, no switch shown (\(assistant.lines))")
        assistant.apply()
        check(rig.file().provider == .anthropic && rig.file().candidateLayout == .vertical && rig.opened == [.anthropic, .gemini]
              && rig.tested == 1, "Apply applies the rest and opens Gemini's key field; the provider stays (\(rig.opened))")

        // In English.
        UIText.choice = .english
        try? start.write(to: rig.url)
        ask("translate into English and French, Chinese in WeChat, candidates in a column", Self.assistantChanges)
        check(assistant.lines == ["Translation languages: English, Chinese → English, French", "Candidate layout: Horizontal → Vertical",
                                  "Apps · WeChat · Starts in: Same as everywhere → Chinese"], "the preview in English (\(assistant.lines))")
        assistant.apply()
        check(assistant.applied == "Changed 3 settings", "the confirmation in English (\(assistant.applied ?? "-"))")
        assistant.reset()

        testSentInsteadIsTheRequestsOwn(snapshotDirectory: snapshotDirectory)

        testRememberQuestionsReload(snapshotDirectory: snapshotDirectory)
        testKeyStatus(snapshotDirectory: snapshotDirectory)
        testKeyFieldsKeepKeys(snapshotDirectory: snapshotDirectory)
        testSettingsWritesNothingUnasked(snapshotDirectory: snapshotDirectory)
        testFieldsFollowOutsideWrites(snapshotDirectory: snapshotDirectory)
        testAgentCommandFollowsOutsideWrites(snapshotDirectory: snapshotDirectory)
        testSettingsSavesOnlyItsChanges(snapshotDirectory: snapshotDirectory)
        testPreviousAppSettings(snapshotDirectory: snapshotDirectory)
    }

    /// The line over the preview that says the request went to the user's own provider (too long for the on-device
    /// model) is that request's alone: one cancelled, or replaced by another, while the model was still counting it says
    /// nothing when it gets to the provider, over the next one's preview or after; Cancel takes the line away with the
    /// request; a request answered on the device has none. The provider is never reached (its credentials are held,
    /// then refused).
    static func testSentInsteadIsTheRequestsOwn(snapshotDirectory: URL) {
        var start = settings
        start.provider = .bedrock
        start.candidateLayout = .horizontal  // the canned answer changes it, whatever sections before left
        let rig = AssistantRig(snapshotDirectory, name: "assistant-instead.json", config: start)
        UIText.choice = .english
        let credentials = SelfTestGate()
        defer {
            credentials.open()
            rig.restore()
        }
        func use(_ model: TooLongGuidedModel) {
            AIConfigSession.service = AIConfigService(client: ChatClient(apple: model), loadCredentials: { _ in
                await credentials.wait()
                throw AWSConfigError.profileNotFound("selftest")
            }, loadKey: { _, _ in nil })
        }
        let canned = #"{"changes": [{"key": "candidateLayout", "value": "vertical"}]}"#
        let instead = AIConfig.Text(language: "en").sentInstead(.bedrock)
        let assistant = AssistantModel()
        defer { assistant.reset() }

        // Replaced while the model counted it: the next request is answered on the device, and the first, too long, says
        // nothing over its preview.
        let replaced = SelfTestGate()
        use(TooLongGuidedModel(marker: "slowly", gate: replaced, answer: canned))
        assistant.request = "candidates in a column, slowly"
        assistant.sendRequest()
        _ = pump(timeout: 5) { replaced.arrivals > 0 }
        assistant.request = "candidates in a column"
        assistant.sendRequest()
        _ = pump(timeout: 10) { !assistant.working }
        let answered = assistant.preview != nil && assistant.notice == nil
        replaced.open()
        _ = pump(timeout: 1) { assistant.notice != nil }
        check(replaced.arrivals == 1 && answered && assistant.preview != nil && assistant.notice == nil && assistant.message == nil,
              "a request replaced while the model counted it says nothing over the next one's preview (\(assistant.notice ?? "no line"); "
                  + "\(assistant.lines), \(assistant.message ?? "no message"))")

        // Cancelled while the model counted it: nothing after.
        let cancelled = SelfTestGate()
        use(TooLongGuidedModel(marker: "slowly", gate: cancelled, answer: canned))
        assistant.request = "candidates in a column, slowly"
        assistant.sendRequest()
        _ = pump(timeout: 5) { cancelled.arrivals > 0 }
        assistant.cancelRequest()
        cancelled.open()
        _ = pump(timeout: 1) { assistant.notice != nil }
        check(cancelled.arrivals == 1 && assistant.notice == nil && !assistant.working && assistant.preview == nil && assistant.message == nil,
              "a request cancelled while the model counted it says nothing after (\(assistant.notice ?? "no line"))")

        // Cancelled on its way to the provider: the line goes with it.
        use(TooLongGuidedModel(marker: "slowly", answer: canned))
        assistant.request = "candidates in a column, slowly"
        assistant.sendRequest()
        _ = pump(timeout: 5) { assistant.notice != nil }
        let said = assistant.notice == instead && assistant.working
        assistant.cancelRequest()
        let gone = assistant.notice == nil && !assistant.working
        credentials.open()
        _ = pump(timeout: 1) { assistant.notice != nil || assistant.message != nil }
        check(said && gone && assistant.notice == nil && assistant.message == nil,
              "Cancel on the way to the provider takes the line that says so away, and nothing comes after (said: \(said), gone: \(gone))")
    }

    /// The settings the page's images are made from: made-up, never the user's (a provider without a key, a typing speed
    /// out of range, Korean without its pack).
    static var assistantSampleConfig: Config {
        var config = Config.default
        config.provider = .anthropic
        config.typeOutRate = 100
        config.setOrder([Language.korean, .chinese, .english])
        config.candidateLayout = .horizontal
        config.setOrder([OutputLanguage.english, .chinese])
        return config
    }

    /// Settings → Assistant as its images show it, in the interface language: the canned answer's preview over the
    /// made-up findings (`troubledFacts`; `fine`: `fineFacts`, the typing speed in range), all from `rig`'s stand-ins and
    /// config file.
    static func sampleAssistant(_ rig: AssistantRig, fine: Bool = false) -> AssistantModel {
        rig.facts = fine ? fineFacts : troubledFacts
        if fine {
            var config = (try? Config.load(from: rig.url)) ?? assistantSampleConfig
            config.typeOutRate = TypeOut.defaultRate
            try? config.write(to: rig.url)
        }
        let shown = AssistantModel()
        if UIText.chinese {
            rig.model.answer = assistantChanges
            shown.request = "翻译成英语和法语，微信里用中文，候选竖排"
        } else {
            // In English, nothing Chinese: translating into German before, Spanish and French after.
            var config = (try? Config.load(from: rig.url)) ?? assistantSampleConfig
            config.setOrder([OutputLanguage.english, OutputLanguage("de")])
            try? config.write(to: rig.url)
            rig.model.answer = assistantChangesInEnglish
            shown.request = "translate into Spanish and French, sync through iCloud, candidates in a column"
        }
        shown.sendRequest()
        _ = pump(timeout: 5) { !shown.working }
        shown.probe(now: true)
        _ = pump(timeout: 5) { !shown.checking }
        return shown
    }

    /// The canned answer the page's images show: three changes.
    static let assistantChanges = """
        {"changes": [{"key": "outputLanguages", "value": ["en", "fr"]}, {"key": "appProfiles.*.inputLanguage", "app": "WeChat", "value": "zh"},
                     {"key": "candidateLayout", "value": "vertical"}]}
        """

    /// The English images' canned answer: three changes, none of them about Chinese.
    static let assistantChangesInEnglish = """
        {"changes": [{"key": "outputLanguages", "value": ["es", "fr"]}, {"key": "iCloudSync.enabled", "value": true},
                     {"key": "candidateLayout", "value": "vertical"}]}
        """

    /// Settings → Assistant's second section, "Check for problems", with fake probes on a config file of the self-test's
    /// own: the quick probes alone (no connection test), problems first; a config fix shows in the first section's preview
    /// and applies and undoes like a request; the other fixes act at once (recorded here, never done), the key's opens the
    /// key field; Check runs the connection test, and with a question the model's explanation (a stand-in on-device
    /// model); problems and warnings each a row, what is fine folded under one line. The user's config is never touched.
    static func testDoctor(snapshotDirectory: URL) {
        section("Settings → Assistant: check for problems (fake probes)")
        let realBefore = try? Data(contentsOf: Config.userURL)
        var start = settings
        start.provider = .anthropic
        start.typeOutRate = 100
        start.setOrder([Language.korean, .chinese, .english])
        let rig = AssistantRig(snapshotDirectory, name: "assistant-doctor.json", config: start)
        rig.facts = troubledFacts
        UIText.choice = .chinese
        defer {
            rig.restore()
            check((try? Data(contentsOf: Config.userURL)) == realBefore, "Assistant's checks: the user's config file was not touched")
        }
        let assistant = AssistantModel()
        func probed() { _ = pump(timeout: 5) { !assistant.checking } }

        assistant.probe(now: true)
        probed()
        let rows = assistant.findings.map { $0.text(chinese: true) }
        check(rows.first?.hasPrefix("✗") == true && rows.last?.hasPrefix("✓") == true && !assistant.allFine,
              "the quick probes: problems first, then what is fine (\(rows.count) rows)")
        check(rows.contains("✗ 韩语语言包没有装 — 装好以前打不了韩语") && rows.contains { $0.hasPrefix("✗ 打字速度超出范围") }
              && rows.contains("✗ AI 服务：Claude API — 需要 API key：在设置里填（不会发给 AI）"), "the findings (\(rows))")
        check(rig.tested == 0 && assistant.connectionTests == 0, "the probes never run the connection test")
        func index(_ prefix: String) -> Int { assistant.findings.firstIndex { $0.text(chinese: true).hasPrefix(prefix) } ?? -1 }

        // The typing speed's fix: in the first section's preview, applied, then undone.
        assistant.fix(index("✗ 打字速度"))
        _ = pump(timeout: 5) { assistant.preview != nil }
        check(assistant.lines == ["打字速度：每秒 100 个字 → 每秒 16 个字"] && rig.file().typeOutRate == 100,
              "a config fix shows its change in the request's preview (\(assistant.lines))")
        assistant.apply()
        check(rig.file().typeOutRate == 16 && assistant.applied == "已改 1 项" && assistant.canUndo, "Apply fixes it in the config file")
        probed()
        check(!assistant.findings.contains { $0.text(chinese: true).hasPrefix("✗ 打字速度") }, "the probes run again: the problem is gone")
        assistant.undo()
        check(rig.file().typeOutRate == 100, "Undo puts it back")
        probed()

        // The pack's fix acts at once (recorded here): no preview.
        assistant.fix(index("✗ 韩语语言包"))
        check(rig.performed == [.downloadPack(.korean)] && assistant.preview == nil, "a pack's fix downloads it at once (\(rig.performed))")
        // The provider without a key: Settings at its key field, nothing else.
        assistant.fix(index("✗ AI 服务"))
        check(rig.opened == [.anthropic] && rig.file().provider == .anthropic, "the key's fix opens Settings at the key field (\(rig.opened))")
        _ = pump(timeout: 1) { !assistant.checking && rig.probed >= 4 }

        // Check with a question: the connection test (a key now), then the model's explanation.
        rig.facts = { url in
            var facts = troubledFacts(url)
            facts.keySaved = [.anthropic: true]
            return facts
        }
        let model = CannedGuidedModel(#"{"explanation": "打字速度超出范围，所以逐字上屏不对。", "fixes": ["F2"]}"#)
        DoctorSession.service = DoctorService(client: ChatClient(apple: model))
        assistant.question = "why is typing out odd"
        assistant.check()
        probed()
        check(rig.tested == 1 && assistant.findings.contains { $0.text(chinese: true).hasPrefix("✓ 连接正常") },
              "Check runs the connection test (\(rig.tested))")
        check(model.requests == 1 && assistant.explanation?.hasPrefix("打字速度超出范围") == true
              && assistant.recommended == assistant.findings.filter { $0.title.hasPrefix("打字速度") }.compactMap(\.fix),
              "the question is answered on device, its fix marked (\(assistant.explanation ?? "-"), \(assistant.recommended.count))")

        // A key typed into the question: never sent, nor left in the field.
        let key = "sk-ant-" + "api03-abcdefghijklmnopqrstuvwxyz0123456789"
        assistant.question = "why does " + key + " fail"
        assistant.check()
        probed()
        check(model.requests == 2 && !(model.prompts.last ?? key).contains(key) && !assistant.question.contains(key)
              && assistant.questionNote != nil, "a key typed into the question isn't sent, and leaves the field (\(assistant.question))")

        // A command to copy: Copied for a moment.
        rig.facts = { url in
            var facts = troubledFacts(url)
            facts.recentErrors = []
            var config = facts.config ?? .default
            config.provider = .bedrock
            config.awsProfile = "sso-dev"
            facts.config = config
            var status = AWSProfileStatus(profile: "sso-dev")
            status.problem = .ssoExpired(profile: "sso-dev")
            facts.awsStatus = status
            facts.awsProfile = .failure(Doctor.ProbeError(AWSCredentialError.ssoExpired(profile: "sso-dev").message(chinese: true)))
            return facts
        }
        assistant.probe(now: true)
        probed()
        let copyIndex = assistant.findings.firstIndex { if case .copyCommand = $0.fix { return true } else { return false } }
        if let copyIndex {
            assistant.fix(copyIndex)
            check(assistant.copied == copyIndex && rig.performed.last.map { if case .copyCommand = $0 { true } else { false } } == true,
                  "Copy puts the command on the clipboard (recorded here) and says Copied")
            _ = pump(timeout: 3) { assistant.copied == nil }
            check(assistant.copied == nil, "Copied goes after a moment")
        } else {
            check(false, "an expired SSO sign-in's finding offers its command to copy (\(assistant.findings.map { $0.text(chinese: false) }))")
        }

        // Problems and warnings each a row, never folded; what is fine folded under one line, at first; opened, it stays
        // so while the probes run again.
        let passed = assistant.findings.filter { $0.status == .ok }
        check(!assistant.showsFine && !passed.isEmpty && assistant.fold == "另外 \(passed.count) 项正常"
              && assistant.fine.map(\.element) == passed
              && assistant.issues.map(\.element) == assistant.findings.filter { $0.status != .ok } && !assistant.issues.isEmpty,
              "the problems are rows, what is fine folded under one line (\(assistant.fold ?? "-"))")
        assistant.showsFine = true
        assistant.probe(now: true)
        probed()
        check(assistant.showsFine, "opened, what is fine stays open while the probes run again")
        assistant.showsFine = false
        rig.facts = fineFacts
        var fine = start
        fine.typeOutRate = TypeOut.defaultRate
        try? fine.write(to: rig.url)
        assistant.probe(now: true)
        probed()
        check(assistant.allFine && assistant.issues.isEmpty && assistant.fold == "一切正常" && !assistant.showsFine,
              "everything fine: one line, folded (\(assistant.findings.map { $0.status }))")
        let updates = assistant.findings.first { $0.area == .updates }
        check(updates?.title == "更新：自动检查" && updates?.detail == "当前版本 \(AppVersion.string)",
              "the updates row is named by what it checks, not the version again (\(updates?.text(chinese: true) ?? "-"))")
        assistant.showsFine = true
        assistant.reset()
        check(!assistant.showsFine, "reset folds it again")
    }

    /// The settings window (Settings v2): six pages in the sidebar, in order, opened on General, no Assistant or Apps
    /// page; the probes run as it opens (never the connection test), and what they find wrong is a banner at the top of
    /// its page, its fix saying what it does (never just "Fix"), and a dot on the page's row; the sidebar's search finds
    /// rows at once (typing sends nothing), shows the one chosen on its page, and its last row, "Change: …", asks the AI
    /// as "Change settings in a sentence" did (the preview at the top of the page, Apply); a setting no longer shown, set
    /// otherwise than its default, shows with Restore Default; Troubleshoot's checks as VoiceOver finds them, what is fine
    /// folded until a click opens it; and the images in both languages, light and dark (`assistant*.png`: the search's
    /// Change; `settings-problem*.png`: a banner and its dot).
    static func testSettingsPages(snapshotDirectory: URL) {
        section("Settings: the pages, the search, banners, Restore Default")
        let start = assistantSampleConfig
        let rig = AssistantRig(snapshotDirectory, name: "assistant-page.json", config: start)
        rig.facts = troubledFacts
        defer { rig.restore() }
        let pages: [SettingsPage] = [.general, .ai, .privacy, .commands, .advanced, .about]
        check(SettingsPage.allCases == pages && SettingsView.firstPage == .general
              && SettingsPage(rawValue: "assistant") == nil && SettingsPage(rawValue: "apps") == nil,
              "six pages in order, General first, no Assistant or Apps page (\(SettingsPage.allCases.map(\.rawValue)))")
        check(SettingsSpot.search("doctor", trigger: "@", config: start).first == .troubleshoot
              && SettingsSpot.search("诊断", trigger: "@", config: start).first == .troubleshoot,
              "searching for doctor or 诊断 finds About → Troubleshoot")

        // VoiceOver's view of a window: SwiftUI builds the views' accessibility for an assistive app only, which says so
        // with `AXEnhancedUserInterface` on the app: set here on this process's own, by its selector (AppKit has no API
        // for it), and off again after.
        func enhanced(_ on: Bool) {
            _ = NSApp.perform(Selector(("accessibilitySetValue:forAttribute:")), with: on as NSNumber, with: "AXEnhancedUserInterface")
        }
        func ax(_ node: NSObject, _ key: String) -> Any? { node.responds(to: NSSelectorFromString(key)) ? node.value(forKey: key) : nil }
        // A table's rows (the sidebar's pages) are its `accessibilityRows`, besides its children.
        func nodes(_ node: NSObject) -> [NSObject] {
            let children = ((ax(node, "accessibilityChildren") as? [NSObject]) ?? []) + ((ax(node, "accessibilityRows") as? [NSObject]) ?? [])
            return [node] + children.flatMap(nodes)
        }
        func texts(_ window: NSWindow) -> [String] {
            nodes(window).map { (ax($0, "accessibilityValue") as? String) ?? (ax($0, "accessibilityLabel") as? String) ?? "" }
        }
        func open(_ view: some View, height: CGFloat = 700) -> NSWindow {
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.setContentSize(NSSize(width: 880, height: height))
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return window
        }
        func close(_ window: NSWindow) {
            window.close()
            _ = pump(timeout: 0.3) { false }
        }
        enhanced(true)
        defer { enhanced(false) }

        // A window opened with no page asked for: General, its probes, no connection test.
        let assistant = AssistantModel()
        let model = SettingsModel(configURL: rig.url, persists: false)
        let window = open(SettingsView(model: model, assistant: assistant))
        _ = pump(timeout: 5) { !assistant.findings.isEmpty && !assistant.checking }
        _ = pump(timeout: 0.8) { false }
        let shown = texts(window)
        // The sidebar's rows: an outline whose rows don't list their texts as children; each row's view does.
        func sidebar(_ window: NSWindow) -> [String] {
            guard let outline = nodes(window).first(where: { $0 is NSOutlineView }) as? NSOutlineView else { return [] }
            return (0..<outline.numberOfRows).flatMap { row -> [String] in
                guard let view = outline.rowView(atRow: row, makeIfNecessary: true) else { return [] }
                return nodes(view).flatMap { [ax($0, "accessibilityLabel") as? String, ax($0, "accessibilityValue") as? String] }
                    .compactMap { $0 }.filter { !$0.isEmpty }
            }
        }
        let rows = sidebar(window)
        let titles = pages.map(\.title)
        let order = titles.compactMap { title in rows.firstIndex { $0.hasPrefix(title) } }
        check(order.count == pages.count && order == order.sorted() && !rows.contains(tr("助手", "Assistant"))
              && !rows.contains(tr("按 App 设置", "Apps")),
              "the sidebar has the six pages in order, no Assistant or Apps (\(rows))")
        check(shown.contains(SettingsSpot.inputLanguages.title) && shown.contains(SettingsSpot.outputLanguages.title),
              "Settings opens on General: its input languages and Translate to")
        check(rig.probed >= 1 && !assistant.findings.isEmpty && rig.tested == 0 && assistant.connectionTests == 0,
              "its probes ran as it opened (\(rig.probed)), never the connection test")
        // The made-up problems: General's (the input method, Korean's pack) on its banner; AI's (no key) only a dot here.
        let general = assistant.issues.filter { SettingsPage.of($0.element.area) == .general }.map(\.element)
        check(!general.isEmpty && general.allSatisfy { shown.contains($0.title) }
              && rows.contains(SettingsPage.general.title + tr("：", ": ") + tr("有问题", "Has a problem"))
              && !shown.contains(tr("修复", "Fix")),
              "General's problems on its banner, a dot on the rows with one, no button just \"Fix\" (\(general.map(\.title)); "
                  + "banner \(general.allSatisfy { shown.contains($0.title) }), rows \(rows), Fix \(shown.contains(tr("修复", "Fix"))))")
        let download = general.first { if case .downloadPack = $0.fix { return true } else { return false } }
        check(download.map { shown.contains(FindingRow.title($0.fix!)) } == true, "the pack's button says Download")
        close(window)

        // AI: the provider's problem on its banner, its button Add Key…; a setting no longer shown, set otherwise than its
        // default, on its row with Restore Default, which restores it.
        model.config.maxTokens = 2000
        let ai = open(SettingsView(model: model, page: .ai, assistant: assistant))
        _ = pump(timeout: 1) { false }
        let onAI = texts(ai)
        let keyFinding = assistant.issues.first { SettingsPage.of($0.element.area) == .ai }?.element
        check(keyFinding.map { onAI.contains($0.title) } == true && onAI.contains(tr("添加密钥…", "Add Key…")),
              "AI's problem on its banner, its button Add Key… (\(keyFinding?.title ?? "-"))")
        check(onAI.contains(tr("最多输出 2000 tokens", "Up to 2000 output tokens")) && onAI.contains(tr("恢复默认", "Restore Default"))
              && !onAI.contains(tr("超时 15 秒", "Timeout 15 s")),
              "the output tokens set otherwise show with Restore Default; the timeout at its default doesn't show")
        let restore = nodes(ai).first {
            ax($0, "accessibilityRole") as? String == NSAccessibility.Role.button.rawValue
                && [ax($0, "accessibilityLabel"), ax($0, "accessibilityTitle")].contains { $0 as? String == tr("恢复默认", "Restore Default") }
        }
        _ = restore?.perform(NSSelectorFromString("accessibilityPerformPress"))
        _ = pump(timeout: 1) { model.config.maxTokens == Config.default.maxTokens }
        check(model.config.maxTokens == Config.default.maxTokens, "Restore Default puts the default back (\(model.config.maxTokens))")
        close(ai)

        // The search: typed into, it lists rows at once and sends nothing; the row chosen shows on its page; Return on
        // "Change: …" (the only row when nothing matches) asks the AI, the preview at the top of the page.
        let search = open(SettingsView(model: model, assistant: assistant))
        _ = pump(timeout: 0.6) { false }
        func textFields(_ view: NSView) -> [NSTextField] { ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(textFields) }
        let field = search.contentView.map(textFields)?.first { $0.placeholderString == tr("搜索设置…", "Search settings…") }
        func type(_ text: String) {
            guard let field, search.makeFirstResponder(field), let editor = search.firstResponder as? NSTextView else { return }
            editor.selectAll(nil)
            editor.insertText(text, replacementRange: editor.selectedRange())
            _ = pump(timeout: 0.5) { false }
        }
        func key(_ characters: String, _ code: UInt16) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: search.windowNumber, context: nil, characters: characters,
                                                   charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { continue }
                search.sendEvent(event)
            }
            _ = pump(timeout: 0.3) { false }
        }
        let request = UIText.chinese ? "翻译成英语和法语，微信里用中文，候选竖排" : "translate into Spanish and French, sync through iCloud, candidates in a column"
        rig.model.answer = UIText.chinese ? assistantChanges : assistantChangesInEnglish
        type("candidate layout")
        check(model.spot == .candidateLayout && !assistant.working && assistant.preview == nil,
              "typing finds the candidate layout and shows it, outlined (\(model.spot?.rawValue ?? "-")); nothing is sent")
        let listed = texts(search)
        check(listed.contains(SettingsSpot.candidateLayout.title) && listed.contains(tr("修改：candidate layout", "Change: candidate layout")),
              "the search lists the row, then \"Change: …\" last")
        type(request)
        check(!assistant.working && assistant.preview == nil, "typing a sentence sends nothing")
        key("\r", 0x24)
        _ = pump(timeout: 5) { assistant.preview != nil }
        check(assistant.request == request && assistant.lines.count == 3,
              "Return on \"Change: …\" asks the AI as typed: its preview (\(assistant.lines))")
        check(texts(search).contains(tr("用一句话改设置", "Change settings in a sentence")) && texts(search).contains(tr("应用", "Apply")),
              "the preview at the top of the page, with Apply")
        assistant.dismissPreview()
        close(search)

        // Troubleshoot's checks: the problems' rows, then what is fine folded under one line, a disclosure, collapsed; a
        // click on its title opens it (the ✓ rows under it), one on its chevron folds it again.
        let sheet = open(TroubleshootSheet(assistant: assistant) {}, height: 560)
        _ = pump(timeout: 2) { !assistant.checking }
        _ = pump(timeout: 0.5) { false }
        struct Shown { var texts: [String], fold: Int?, label: String?, expanded: Bool?, frame: NSRect? }
        func seen() -> Shown {
            let all = nodes(sheet)
            let fold = all.firstIndex { ax($0, "accessibilityRole") as? String == NSAccessibility.Role.disclosureTriangle.rawValue }
            let node = fold.map { all[$0] }
            return Shown(texts: all.map { (ax($0, "accessibilityValue") as? String) ?? (ax($0, "accessibilityLabel") as? String) ?? "" },
                         fold: fold, label: node.flatMap { ax($0, "accessibilityLabel") as? String },
                         expanded: node.flatMap { (ax($0, "accessibilityValue") as? NSNumber)?.boolValue },
                         frame: node.flatMap { (ax($0, "accessibilityFrame") as? NSValue)?.rectValue })
        }
        func click(_ frame: NSRect?, atEnd: Bool) {
            guard let frame else { return }
            let point = sheet.convertPoint(fromScreen: NSPoint(x: atEnd ? frame.maxX - 8 : frame.minX + 40, y: frame.midY))
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                     windowNumber: sheet.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                                     pressure: 1) else { continue }
                sheet.sendEvent(event)
            }
            _ = pump(timeout: 0.5) { false }
        }
        let issues = assistant.issues.map(\.element.title)
        let passed = assistant.fine.map(\.element.title).filter { !issues.contains($0) }
        /// The problems' rows above the line, which says how many more are fine.
        func above(_ seen: Shown) -> Bool {
            !issues.isEmpty && seen.label?.contains(assistant.fold ?? "-") == true
                && issues.allSatisfy { title in seen.texts.firstIndex(of: title).map { $0 < seen.fold ?? 0 } ?? false }
        }
        let folded = seen()
        check(folded.expanded == false && !assistant.showsFine && above(folded) && !passed.contains(where: folded.texts.contains),
              "Troubleshoot: the problems are rows above one line, a disclosure, collapsed (\(folded.label ?? "-"))")
        click(folded.frame, atEnd: false)
        let opened = seen()
        check(opened.expanded == true && assistant.showsFine && above(opened) && !passed.isEmpty && passed.allSatisfy(opened.texts.contains),
              "a click on the line opens it: the ✓ rows under it (\(String(describing: opened.expanded)))")
        click(opened.frame, atEnd: true)
        let closed = seen()
        check(closed.expanded == false && !assistant.showsFine && above(closed) && !passed.contains(where: closed.texts.contains),
              "a click on its chevron folds it again (\(String(describing: closed.expanded)))")
        close(sheet)

        // The images: the search's Change with its preview, and a page's banner with its dot, in Chinese and English,
        // light and dark.
        for (language, suffix) in [("zh", ""), ("en", "-en")] {
            UIText.choice = language
            try? start.write(to: rig.url)
            let shown = sampleAssistant(rig)
            let preview = SettingsModel(configURL: rig.url, persists: false)
            for (appearance, dark) in [(NSAppearance.Name.aqua, ""), (.darkAqua, "-dark")] {
                let name = "assistant\(suffix)\(dark).png"
                let url = snapshotDirectory.appendingPathComponent(name)
                SettingsImage.render(preview, page: .general, assistant: shown, query: shown.request, to: url, appearance: appearance) { seconds in
                    _ = pump(timeout: seconds) { false }
                }
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
                check(size > 10_000 && shown.lines.count == 3 && shown.findings.count > 3,
                      "the search's Change renders in \(language == "zh" ? "Chinese" : "English")\(dark.isEmpty ? "" : ", dark") (\(name))")
                let problem = snapshotDirectory.appendingPathComponent("settings-problem\(suffix)\(dark).png")
                SettingsImage.render(preview, page: .ai, assistant: shown, to: problem, appearance: appearance) { seconds in
                    _ = pump(timeout: seconds) { false }
                }
                check(FileManager.default.fileExists(atPath: problem.path), "AI's banner and its dot render (\(problem.lastPathComponent))")
            }
            shown.reset()
        }
    }

    /// A key row never removes a key, and says whether there is one. Settings opened at the key of the provider in use
    /// (as Settings → Assistant opens it) shows its paste field; ⏎ on it empty, the focus moved on and the window closed: every key
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
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model, page: .ai)))
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
        /// Settings → Assistant asking for `provider`'s key: the sheet once it's up (another provider), else nil.
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

    /// Settings → AI Provider says in each key's row whether it is set, from the lookup Settings → Assistant's checks use
    /// too (a stand-in here: the user's keychain is never asked): a key in the keychain is "✓ Saved · ends in a1b2"
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
        check(keyed == [.openai, .anthropic], "Settings → Assistant's checks see the same keys (\(keyed))")
    }

    /// Settings deletes the questions kept only when its switch turns "Remember recent questions" off, never when the
    /// window reads the config again with it off (as Settings → Assistant writes it, which may still be undone).
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
