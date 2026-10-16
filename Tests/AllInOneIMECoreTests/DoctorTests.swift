import Foundation
import Testing
@testable import AllInOneIMECore

/// `@doctor`: findings from the probes' facts (problems first), the config file's own checks, the fixes as `@config`'s
/// preview, the logs summarised, the question answered on the on-device model with the checks as tools, and the keys.
struct DoctorTests {
    func facts(_ change: (inout Doctor.Facts) -> Void = { _ in }) -> Doctor.Facts {
        var facts = Doctor.Facts()
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        facts.config = config
        facts.configData = try? JSONEncoder().encode(config)
        facts.awsProfile = .success("us-west-2")
        facts.apple = .available
        facts.accessibility = .granted
        facts.microphone = .granted
        facts.packs = [.chinese: .installed]
        facts.inputMethod.version = "0.6.4"
        change(&facts)
        return facts
    }

    @Test func allFineIsAllTicks() {
        let findings = Doctor.findings(facts(), chinese: false)
        #expect(findings.allSatisfy { $0.status == .ok })
        #expect(findings.first?.text(chinese: false) == "✓ AllInOneIME 0.6.4 is installed and enabled")
        #expect(findings.contains { $0.title == "Language packs installed: Chinese" })
        #expect(Doctor.summary(findings, chinese: false) == "All \(findings.count) checks are fine")
    }

    @Test func problemsComeFirstWithTheirFixes() {
        let findings = Doctor.findings(facts {
            $0.inputMethod.enabled = false
            var config = $0.config!
            config.provider = .anthropic
            $0.config = config
            $0.keySaved = [.anthropic: false]
            $0.connection = .failed("No API key for the Claude API")
            $0.packs = [.chinese: .missing]
            $0.secureInput = "loginwindow"
            $0.updates.available = "0.6.5"
        }, chinese: false)
        #expect(findings.prefix(4).allSatisfy { $0.status == .problem })
        #expect(findings.map(\.fix).contains(.enableInputMethod) && findings.map(\.fix).contains(.openKeyField(.anthropic))
                && findings.map(\.fix).contains(.downloadPack(.chinese)) && findings.map(\.fix).contains(.checkForUpdates))
        let statuses = findings.map(\.status)
        #expect(statuses == statuses.sorted())
        #expect(Doctor.summary(findings, chinese: false).hasPrefix("4 problems, 2 warnings"))
        // The key's row never holds a key; only whether one is saved.
        #expect(findings.first { $0.area == .provider }?.text(chinese: false)
                == "✗ AI provider: Claude API — no API key: enter it in Settings (never sent to the AI)")
    }

    @Test func theConnectionShowsWhileItRuns() {
        let running = Doctor.findings(facts { $0.connection = .running }, chinese: true)
        #expect(running.contains { $0.area == .connection && $0.status == .warning && $0.title == "正在测试连接…" })
        let ok = Doctor.findings(facts { $0.connection = .ok("0.8 s: Hi") }, chinese: false)
        #expect(ok.contains { $0.text(chinese: false) == "✓ The connection works — 0.8 s: Hi" })
    }

    @Test func permissionsAreReportedWithoutAsking() {
        let findings = Doctor.findings(facts {
            $0.accessibility = .denied
            $0.microphone = .denied
            $0.automation = ["Notes": .denied, "Terminal": .granted]
        }, chinese: false)
        #expect(findings.map(\.fix).contains(.openPrivacy(.accessibility)) && findings.map(\.fix).contains(.openPrivacy(.microphone))
                && findings.map(\.fix).contains(.openPrivacy(.automation)))
        #expect(findings.contains { $0.title == "Allowed to control: Terminal" })
        // Voice off: the microphone isn't a problem.
        let quiet = Doctor.findings(facts {
            $0.microphone = .denied
            $0.config?.voiceInput = false
        }, chinese: false)
        #expect(!quiet.contains { $0.title.contains("microphone") })
    }

    @Test func theConfigFileIsChecked() throws {
        #expect(Doctor.configFindings(data: nil, error: "bad JSON", config: nil, chinese: false).first?.status == .problem)
        #expect(Doctor.configFindings(data: nil, error: "bad JSON", config: nil, chinese: false).first?.fix == nil)  // never replaced
        var config = Config.default
        config.typeOutRate = 100
        config.outputLanguages = ["en", "fr", "de", "es", "it", "ja"].map(OutputLanguage.init)
        let raw = #"{"outputLanguages": ["en", "en"], "inputLanguages": ["zh"], "fontSize": 12}"#
        let findings = Doctor.configFindings(data: Data(raw.utf8), error: nil, config: config, chinese: false)
        #expect(findings.map(\.title) == ["config.json has keys this version doesn't know", "The typing speed is out of range",
                                          "More than 5 translation languages", "A language is listed twice in config.json"])
        #expect(findings[0].detail == "fontSize (ignored)")
        #expect(findings[3].fix == .resaveConfig)
        // The repairs go through @config's checks: the preview shows them old → new.
        let fixes = findings.compactMap(\.fix)
        let preview = try #require(Doctor.fixPreview(fixes, config: config, environment: AIConfig.Environment()))
        #expect(preview.edits == [.typeOutRate(16), .outputLanguages(["en", "fr", "de", "es", "it"].map(OutputLanguage.init))])
        #expect(preview.actions == [.resaveConfig])
        #expect(preview.rows.map { $0.text(chinese: false) }.last == "→ Remove the repeated languages from config.json (nothing else changes)")
        #expect(Doctor.configFindings(data: try JSONEncoder().encode(Config.default), error: nil, config: .default, chinese: false)
            .map(\.status) == [.ok])
    }

    @Test func fixesAreSafeOrPicked() {
        #expect(Doctor.Fix.repairConfig([]).isSafe && Doctor.Fix.resaveConfig.isSafe && Doctor.Fix.enableInputMethod.isSafe)
        #expect(!Doctor.Fix.downloadPack(.korean).isSafe && !Doctor.Fix.openPrivacy(.microphone).isSafe && !Doctor.Fix.openKeyField(.gemini).isSafe)
        let preview = Doctor.fixPreview([.downloadPack(.korean), .openKeyField(.gemini)], config: .default, environment: AIConfig.Environment())
        #expect(preview?.actions == [.downloadPack(.korean)] && preview?.needsKey == .gemini && preview?.edits.isEmpty == true)
        #expect(Doctor.fixPreview([], config: .default, environment: AIConfig.Environment()) == nil)
    }

    @Test func logLinesAreSummarisedWithoutTheUsersText() {
        let lines = [
            "I20261008 15:45:58.123 1234 deployer.cc:56] all fine",
            "E20261008 15:45:59.001 1234 dictionary.cc:77] Error loading /Users/alice/Library/Rime/custom.yaml",
            "2026-10-12 update check failed: \"my secret sentence\" was not sent",
        ]
        let summary = Doctor.summarizeLogLines(lines, home: "/Users/alice")
        #expect(summary == ["Error loading ~/Library/Rime/custom.yaml", "update check failed: not"])
        let findings = Doctor.findings(facts { $0.recentErrors = summary }, chinese: false)
        #expect(findings.contains { $0.area == .recentErrors && $0.status == .warning })
    }

    @Test func theReportForTheModelNamesFixesByID() {
        let findings = Doctor.findings(facts { $0.packs = [.chinese: .missing] }, chinese: false)
        let report = Doctor.report(findings)
        #expect(report.hasPrefix("- languagePacks: ✗ The Chinese language pack isn't installed") && report.contains("[fix F1]"))
        #expect(!report.contains(NSHomeDirectory()))
        let parsed = DoctorService.parse(#"{"explanation": "The pack is missing.", "fixes": ["F1", "F9", "F1", "X"]}"#, findings: findings)
        #expect(parsed.explanation == "The pack is missing." && parsed.fixes == [0])
        #expect(DoctorService.parse("Just text.", findings: findings) == DoctorService.Answer(explanation: "Just text.", fixes: [], onDevice: false))
    }

    final class Stub: AppleGuidedBackend, @unchecked Sendable {
        let availability: AppleModelAvailability = .available
        let contextSize = 8192
        let supportedLanguages: Set<String> = ["en"]
        var tools: [String] = []
        var instructions = ""
        func respond(to request: AppleModelRequest) -> AsyncThrowingStream<AppleModelSnapshot, Error> {
            AsyncThrowingStream { $0.finish() }
        }
        func respond(to request: AppleModelRequest, schema: GuidedSchema, tools: [GuidedTool]) async throws -> String {
            self.tools = tools.map(\.name)
            instructions = request.instructions
            let packs = await tools.first { $0.name == "check_languagePacks" }?.call([:]) ?? ""
            return packs.contains("[fix F1]") ? #"{"explanation": "Chinese can't be typed: its pack is missing.", "fixes": ["F1"]}"# : "{}"
        }
    }

    @Test func aQuestionGoesToTheOnDeviceModelWithTheChecksAsTools() async throws {
        let stub = Stub()
        let findings = Doctor.findings(facts { $0.packs = [.chinese: .missing] }, chinese: false)
        var config = Config.default
        config.provider = .gemini  // not set up: never asked
        let answer = try await DoctorService(client: ChatClient(apple: stub)).ask("why can't I type Chinese", findings: findings, config: config)
        #expect(answer.onDevice && answer.fixes == [0] && answer.explanation.hasPrefix("Chinese can't be typed"))
        #expect(stub.tools.contains("check_languagePacks") && stub.tools.contains("check_inputMethod"))
        // The findings aren't in its instructions: it asks for them.
        #expect(!stub.instructions.contains("[fix F1]") && stub.instructions.contains("languagePacks"))
        #expect(DoctorService.system(findings, tools: false).contains("[fix F1]"))
    }

    // MARK: - The panel

    func drafted(_ text: String = "") -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.setInputMode(.english)
        _ = c.handleKeyDown(KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift))
        for ch in "doc" { _ = c.handleKeyDown(k(String(ch))) }
        _ = c.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        for ch in text { _ = c.handleKeyDown(ch == " " ? spaceKey : k(String(ch))) }
        return c
    }

    func reported() -> (Composer, Composer.ConfigState.Report) {
        let c = drafted()
        #expect(c.draft == "@doctor ")
        let started = c.handleKeyDown(enterKey).effects
        #expect(started.first == .startCommand(.doctor, input: "", id: 1))
        let report = Composer.ConfigState.Report(lines: ["✗ Chinese pack missing", "⚠ typing speed", "✓ fine"],
                                                 fixes: [.downloadPack(.chinese), .repairConfig([]), nil])
        _ = c.receiveDoctor(report, id: 1)
        return (c, report)
    }

    @Test func findingsWithAFixAreNumbered() {
        let (c, _) = reported()
        #expect(c.phase == .choosing && c.choices.map(\.label) == ["1", "2", ""])
        // A digit previews that fix; ⏎ the safe ones; nothing is inserted.
        #expect(c.handleKeyDown(k("1")).effects == [.previewFixes([.downloadPack(.chinese)])])
        #expect(c.handleKeyDown(enterKey).effects == [.previewFixes([.repairConfig([])])])
        // A click on a numbered row too; one without a fix does nothing.
        #expect(c.choose(index: 0) == [.previewFixes([.downloadPack(.chinese)])] && c.choose(index: 2).isEmpty)
    }

    @Test func theFixPreviewAppliesLikeConfigs() throws {
        let (c, _) = reported()
        let preview = try #require(Doctor.fixPreview([.downloadPack(.chinese)], config: .default, environment: AIConfig.Environment()))
        _ = c.showFixPreview(preview, lines: ["→ Download the Chinese language pack"])
        #expect(c.choices.map(\.text) == ["→ Download the Chinese language pack"])
        // Esc goes back to the findings, ⏎ applies.
        _ = c.handleKeyDown(escKey)
        #expect(c.choices.map(\.label) == ["1", "2", ""] && c.phase == .choosing)
        // A fix that writes settings: ⏎ applies it, ⌘Z undoes it.
        var config = Config.default
        config.typeOutRate = 100
        let repair = try #require(Doctor.fixPreview([.repairConfig([.init(key: .setting(.typeOutRate), value: .number(16))])],
                                                    config: config, environment: AIConfig.Environment()))
        _ = c.showFixPreview(repair, lines: ["Typing speed: 100 a second → 16 a second"])
        #expect(c.handleKeyDown(enterKey).effects == [.applyConfig(repair), .showPanel])
        _ = c.configApplied("Changed 1 setting")
        let undo = c.handleKeyDown(k("z", mods: .command)).effects
        #expect(undo.last == .undoConfig && commits(undo).isEmpty)
    }

    @Test func checksAloneSendNothingEvenWithoutAI() {
        let c = drafted()
        c.aiRefusal = { "AI is off in this app" }
        let effects = c.handleKeyDown(enterKey).effects
        #expect(effects.first == .startCommand(.doctor, input: "", id: 1) && !effects.contains { if case .notice = $0 { return true } else { return false } })
    }

    // MARK: - What must never show or go out

    @Test func repeatsAreRemovedKeepingUnknownKeys() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("doctor-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let text = #"{"futureKey": {"keep": [1, 2]}, "inputLanguages": ["zh", "en", "zh"], "outputLanguages": ["en", "fr", "en"], "temperature": 0.3}"#
        try Data(text.utf8).write(to: url)
        try Doctor.removeRepeatedLanguages(at: url)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(object["inputLanguages"] as? [String] == ["zh", "en"] && object["outputLanguages"] as? [String] == ["en", "fr"])
        #expect((object["futureKey"] as? [String: Any])?["keep"] as? [Int] == [1, 2] && object["temperature"] as? Double == 0.3)
        #expect(String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("\"temperature\" : 0.3"))
        // Offered whenever a list repeats a language (not a list of strings: not repeats).
        var config = Config.default
        config.setOrder([OutputLanguage.english])
        let odd = Doctor.configFindings(data: Data(#"{"outputLanguages": ["en", "en", {"x": 1}]}"#.utf8), error: nil, config: config,
                                        chinese: false)
        #expect(odd.first { $0.title.hasPrefix("A language is listed twice") } == nil)
        let twice = Doctor.configFindings(data: Data(#"{"outputLanguages": ["en", "en"]}"#.utf8), error: nil, config: config, chinese: false)
        #expect(twice.first { $0.title.hasPrefix("A language is listed twice") }?.fix == .resaveConfig)
    }

    @Test func everyConfigKeyIsKnown() {
        // Built from `Config.CodingKeys`: a key added there (questionRounds, questionContinueIn …) is never "unknown".
        #expect(Set(Config.allKeys).isSubset(of: Doctor.knownConfigKeys))
        for key in Config.allKeys { #expect(AIConfig.Key.parse(key) != nil, "\(key)") }
        #expect(Config.allKeys.contains("questionRounds") && Config.allKeys.contains("questionContinueIn"))
        let raw = #"{"questionRounds": 5, "questionContinueIn": "claude", "fontSize": 3}"#
        let findings = Doctor.configFindings(data: Data(raw.utf8), error: nil, config: .default, chinese: false)
        #expect(findings.first { $0.title.hasPrefix("config.json has keys") }?.detail == "fontSize (ignored)")
    }

    @Test func absolutePathsAreMasked() {
        // Folder names with spaces stay inside the path: masked rather than shown (here up to the last path in the line).
        #expect(Doctor.maskingAbsolutePaths("couldn't move /Volumes/My Disk/secret project/a.zip") == "couldn't move …/a.zip")
        #expect(!Doctor.maskingAbsolutePaths("couldn't move /Volumes/My Disk/secret project/a.zip to /tmp").contains("secret"))
        #expect(Doctor.maskingAbsolutePaths("~/Library/Rime/x.yaml and https://example.com/v1 and 401/403")
                == "~/Library/Rime/x.yaml and https://example.com/v1 and 401/403")
        #expect(Doctor.scrub("/Users/x/Library/a: \"/opt/data/b.txt\"", home: "/Users/x") == "~/Library/a: \"…/b.txt\"")
    }

    @Test func logSummariesKeepAFixedVocabulary() {
        let lines = [
            "E20261015 10:00:01.000 1234 dictionary.cc:56] failed to load /Users/x/Library/Rime/user.dict.yaml for Alice Smith",
            "update failed: couldn't move /private/var/tmp/Report Q3 2026.zip (NSURLErrorDomain -1009)",
            "E20261015 10:00:03.000 1234 engine.cc:81] commit error: my bank password is hunter2",
        ]
        #expect(Doctor.summarizeLogLines(lines, home: "/Users/x") == [
            "failed to load ~/Library/Rime/user.dict.yaml for",
            "update failed: couldn't move …/Report NSURLErrorDomain -1009",
            "error:",
        ])
    }

    @Test func checkForUpdatesIsPickedNotSafe() {
        #expect(!Doctor.Fix.checkForUpdates.isSafe)
        let report = Composer.ConfigState.Report(lines: ["a"], fixes: [.checkForUpdates])
        #expect(report.defaultFixes.isEmpty)
    }

    @Test func testConnectionOnlyWithSomethingToTest() {
        var claude = facts { $0.config?.provider = .anthropic }
        #expect(!Doctor.canTestConnection(claude))
        claude.keySaved[.anthropic] = true
        #expect(Doctor.canTestConnection(claude))
        #expect(Doctor.canTestConnection(facts()))  // Bedrock with credentials found
        #expect(!Doctor.canTestConnection(facts { $0.awsProfile = .failure(Doctor.ProbeError("no profile")) }))
        #expect(!Doctor.canTestConnection(facts { $0.config?.provider = .apple; $0.apple = .modelNotReady }))
        #expect(!Doctor.canTestConnection(facts { $0.config = nil }))
    }

    @Test func aFixThatOnlyRunsActionsOffersNoUndo() throws {
        let (c, _) = reported()
        let preview = try #require(Doctor.fixPreview([.downloadPack(.chinese)], config: .default, environment: AIConfig.Environment()))
        _ = c.showFixPreview(preview, lines: ["→ Download the Chinese language pack"])
        _ = c.handleKeyDown(enterKey)
        _ = c.configApplied("Done")
        #expect(!c.configState.writesSettings)
        // ⌘Z isn't @config's here: it never undoes an older change.
        let z = c.handleKeyDown(k("z", mods: .command))
        #expect(!z.effects.contains(.undoConfig))
    }

    @Test func typographicAndCJKQuotesAreLeftOut() {
        let lines = ["error: couldn’t read “my diary.txt”", "failed: 「我想去医院」 and 『秘密』 and «privé» and ‘mine’"]
        let out = Doctor.summarizeLogLines(lines, home: "/Users/x")
        #expect(out == ["error: couldn’t read", "failed:"])
    }

    @Test func probesNeverShowOrSendKeysOrFullPaths() {
        let key = "sk-ant-api03-Zx8Qw2Lm4Np6Rt0Vb3Yc5Hd7Jf9Kg1Ms2Pu4Wx6Ab8Cd"
        let home = NSHomeDirectory()
        let findings = Doctor.findings(facts {
            $0.connection = .failed("401: invalid key \(key)")
            $0.pluginErrors = ["\(home)/Library/plugins/x: bad"]
            $0.updates.lastError = "couldn't move \(home)/Downloads/a.zip"
        }, chinese: false)
        let shown = findings.map { $0.text(chinese: false) }.joined(separator: "\n")
        #expect(!shown.contains(key) && !shown.contains(home) && shown.contains("~/Downloads/a.zip") && shown.contains("[KEY]"))
        #expect(!Doctor.report(findings).contains(key) && !Doctor.report(findings).contains(home))
        // Even findings made elsewhere, as the report is sent.
        let raw = [Doctor.Finding(area: .extensions, status: .warning, title: "x", detail: "\(home)/a \(key)")]
        #expect(Doctor.report(raw) == "- extensions: ⚠ x — ~/a [KEY]")
    }

    @Test func enterAppliesOnlySafeFixesWhateverTheModelSuggests() {
        let report = Composer.ConfigState.Report(lines: ["a", "b", "c", "d"],
                                                 fixes: [.downloadPack(.korean), .repairConfig([]), nil, .checkForUpdates],
                                                 recommended: [0, 3])
        #expect(report.defaultFixes == [.repairConfig([])])  // Check for Updates opens Settings: picked by its number
    }

    @Test func inAnAppWithNoAIOnlyTheQuestionIsRefused() {
        let c = drafted("why")
        c.aiRefusal = { "AI is off in this app" }
        let effects = c.handleKeyDown(enterKey).effects
        #expect(effects.first == .startCommand(.doctor, input: "", id: 1) && effects.contains(.notice("AI is off in this app")))
    }

    @Test func shiftReturnDoesNothingOnTheFindings() {
        let (c, _) = reported()
        #expect(c.handleKeyDown(KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r", modifiers: .shift)).effects.isEmpty)
        #expect(c.phase == .choosing)
    }
}
