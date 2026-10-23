import Foundation
import Testing
@testable import AllInOneIMECore

/// Settings → Assistant's checks: findings from the probes' facts (problems first), the config file's own checks, the
/// fixes as a request's preview, the logs summarised, the question answered on the on-device model with the checks as tools, and the keys.
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
                == "✗ AI provider: Claude API — needs an API key: add it in Settings (never sent to the AI)")
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
        // The repairs go through `AIConfig`'s checks: the preview shows them old → new.
        let fixes = findings.compactMap(\.fix)
        let preview = try #require(Doctor.fixPreview(fixes, config: config, environment: AIConfig.Environment()))
        #expect(preview.edits == [.typeOutRate(16), .outputLanguages(["en", "fr", "de", "es", "it"].map(OutputLanguage.init))])
        #expect(preview.actions == [.resaveConfig])
        #expect(preview.rows.map { $0.text(chinese: false) }.last == "→ Remove the repeated languages from config.json (nothing else changes)")
        #expect(Doctor.configFindings(data: try JSONEncoder().encode(Config.default), error: nil, config: .default, chinese: false)
            .map(\.status) == [.ok])
    }

    @Test func fixesPreviewAsActionsAndKeyRows() {
        let preview = Doctor.fixPreview([.downloadPack(.korean), .openKeyField(.gemini)], config: .default, environment: AIConfig.Environment())
        #expect(preview?.actions == [.downloadPack(.korean)] && preview?.needsKey == .gemini && preview?.edits.isEmpty == true)
        // The key's row says it as a request's preview does (the provider is the one in use: nothing to choose).
        #expect(preview?.rows.last?.text(chinese: false) == "Gemini API needs an API key: ⏎ opens Settings to add it (never sent to the AI)")
        let zh = Doctor.fixPreview([.openKeyField(.anthropic)], config: .default, environment: AIConfig.Environment(chinese: true))
        #expect(zh?.rows.map { $0.text(chinese: true) } == ["Claude API 需要 API key：⏎ 打开设置去填（不会发给 AI）"])
        #expect(Doctor.fixPreview([], config: .default, environment: AIConfig.Environment()) == nil)
    }

    @Test func logLinesAreSummarisedWithoutTheUsersText() {
        let lines = [
            "I20261008 15:45:58.123 1234 deployer.cc:56] all fine",
            "E20261008 15:45:59.001 1234 dictionary.cc:77] Error loading /Users/alice/Library/Rime/custom.yaml",
            "2026-10-12 update check failed: \"my secret sentence\" was not sent",
        ]
        let summary = Doctor.summarizeLogLines(lines, home: "/Users/alice")
        #expect(summary == ["Rime dictionary failed to load: ~/Library/Rime/custom.yaml", "update check failed"])
        let findings = Doctor.findings(facts { $0.recentErrors = summary }, chinese: false)
        #expect(findings.contains { $0.area == .recentErrors && $0.status == .warning })
    }

    /// The report as it came: librime's two lines for the missing lunar database were "error in Rime" three times.
    @Test func lunarLogsNameTheFileAndGroupRepeatedOldErrors() {
        let lines = [
            "E20261010 09:00:00.000 1234 mapped_file.cc:78] attempt to open non-existent file '/Users/alice/Library/Application Support/AllInOneIME/Rime/lua/lunar.db'",
            "E20261010 09:00:01.000 1234 reverse_lookup_dictionary.cc:39] Error opening reversedb '/Users/alice/Library/Application Support/AllInOneIME/Rime/lua/lunar.db'",
            "E20261010 09:00:02.000 1234 mapped_file.cc:78] attempt to open non-existent file '/Users/alice/Library/Application Support/AllInOneIME/Rime/lua/lunar.db'",
        ]
        let missing = Doctor.summarizeLogLines(lines, home: "/Users/alice")
        #expect(missing == ["Rime: a file it needs is missing: lua/lunar.db (the lunar date), 3 times"])
        let shown = Doctor.findings(facts { $0.recentErrors = missing }, chinese: false).first { $0.area == .recentErrors }
        #expect(shown?.text(chinese: false)
                == "⚠ 1 recent error in the logs — Rime: a file it needs is missing: lua/lunar.db (the lunar date), 3 times")
        let zh = Doctor.findings(facts { $0.recentErrors = missing }, chinese: true).first { $0.area == .recentErrors }
        #expect(zh?.detail == "Rime：缺少所需文件 lua/lunar.db（农历日期），3 次")
        // The file is there now (this version puts it there): those runs were earlier ones, and nothing is wrong.
        let available = Doctor.summarizeLogLines(lines, home: "/Users/alice", lunarDatabaseAvailable: true)
        #expect(available == ["Earlier Rime run: lua/lunar.db was missing; this version provides it, 3 times"])
        let finding = Doctor.findings(facts { $0.recentErrors = available }, chinese: false).first { $0.area == .recentErrors }
        #expect(finding?.status == .ok && finding?.title == "An earlier Rime error is resolved")
        #expect(!(missing + available).joined().contains("alice"))
    }

    /// The same event is named once, with how many times it came up in all the lines (not only the newest few), and the
    /// newest events are the ones shown.
    @Test func repeatedLogEventsAreCountedOnce() {
        let lunar = "E20261010 09:00:00.000 1234 mapped_file.cc:78] attempt to open non-existent file '/Users/x/Rime/lua/lunar.db'"
        let lines = Array(repeating: lunar, count: 5) + [
            "2026-10-12 update check failed: The request timed out.",
            "E20261012 10:00:00.000 1234 engine.cc:81] error 1",
            "E20261012 10:00:01.000 1234 engine.cc:82] error 2",
            "2026-10-13 update check failed: The request timed out.",
            lunar,
        ]
        #expect(Doctor.summarizeLogLines(lines, home: "/Users/x") == [
            "error in Rime (engine), 2 times",
            "update check failed (timed out), 2 times",
            "Rime: a file it needs is missing: lua/lunar.db (the lunar date), 6 times",
        ])
        #expect(Doctor.summarizeLogLines(lines, home: "/Users/x", limit: 1) == [
            "Rime: a file it needs is missing: lua/lunar.db (the lunar date), 6 times",
        ])
    }

    /// After an update System Settings may show AllInOneIME allowed while this build isn't: the finding says where to turn
    /// it off and on, and Fix opens that pane.
    @Test func accessibilityDenialExplainsStaleSystemSettingsEntry() {
        let denied = Doctor.findings(facts { $0.accessibility = .denied }, chinese: false).first { $0.area == .permissions }
        #expect(denied?.status == .warning && denied?.fix == .openPrivacy(.accessibility))
        #expect(denied?.text(chinese: false) == "⚠ Accessibility isn't allowed — the selection can't be read in some apps. "
                + "If AllInOneIME is already on in System Settings → Privacy & Security → Accessibility, turn it off and on again "
                + "(macOS can keep the permission for the previous version)")
        let chinese = Doctor.findings(facts { $0.accessibility = .denied }, chinese: true).first { $0.area == .permissions }
        #expect(chinese?.detail == "有的 App 里读不到选中的文字。如果系统设置 → 隐私与安全性 → 辅助功能里 AllInOneIME 已经打开，"
                + "先关掉再打开（macOS 可能还留着上一个版本的权限）")
        let allowed = Doctor.findings(facts { $0.accessibility = .granted }, chinese: false).first { $0.area == .permissions }
        #expect(allowed?.status == .ok && allowed?.detail == nil)
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

    // MARK: - The fixes in the Assistant's preview

    /// A config fix is the preview a request gets (old → new, applied and undone through `AIConfig`); an action fix is an
    /// action row that writes no setting (nothing to undo).
    @Test func fixPreviewsAreConfigPreviews() throws {
        var config = Config.default
        config.typeOutRate = 100
        let repair = try #require(Doctor.fixPreview([.repairConfig([.init(key: .setting(.typeOutRate), value: .number(16))])],
                                                    config: config, environment: AIConfig.Environment()))
        #expect(repair.edits.count == 1 && repair.actions.isEmpty && repair.rows.first?.status == .change)
        let pack = try #require(Doctor.fixPreview([.downloadPack(.chinese)], config: .default, environment: AIConfig.Environment()))
        #expect(pack.edits.isEmpty && pack.actions == [.downloadPack(.chinese)] && pack.rows.map { $0.text(chinese: false) }
                == ["→ Download the Chinese language pack"])
        let resave = try #require(Doctor.fixPreview([.resaveConfig], config: .default, environment: AIConfig.Environment()))
        #expect(resave.edits.isEmpty && resave.actions == [.resaveConfig])
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
        // Only those lists are rewritten: every other key keeps its text as it was.
        let after = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        #expect(after.contains(#""futureKey": {"keep": [1, 2]}"#) && after.contains(#""temperature": 0.3"#))
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
        // Folder names with spaces stay inside the path; the words after it don't.
        #expect(Doctor.maskingAbsolutePaths("couldn't move /Volumes/My Disk/secret project/a.zip to /tmp") == "couldn't move …/a.zip to …/tmp")
        #expect(Doctor.maskingAbsolutePaths("move /private/var/tmp/Report Q3 2026.zip (NSURLErrorDomain -1009) failed")
                == "move …/Report Q3 2026.zip (NSURLErrorDomain -1009) failed")
        #expect(Doctor.maskingAbsolutePaths("/opt/data/b.txt: not found, try again") == "…/b.txt: not found, try again")
        #expect(Doctor.maskingAbsolutePaths("~/Library/Rime/x.yaml and https://example.com/v1 and 401/403")
                == "~/Library/Rime/x.yaml and https://example.com/v1 and 401/403")
        #expect(Doctor.scrub("/Users/x/Library/a: \"/opt/data/b.txt\"", home: "/Users/x") == "~/Library/a: \"…/b.txt\"")
    }

    @Test func logSummariesArePhrasesPerEvent() {
        let lines = [
            "E20261015 10:00:01.000 1234 dictionary.cc:56] failed to load /Users/x/Library/Rime/user.dict.yaml for Alice Smith",
            "update failed: couldn't move /private/var/tmp/Report Q3 2026.zip (NSURLErrorDomain -1009)",
            "E20261015 10:00:03.000 1234 engine.cc:81] commit error: my bank password is hunter2",
            "plugin weather failed to load: manifest.json can't be read",
            "2026-10-15 update check failed: the signature didn't verify",
            "something weird happened: error 42 in Alice's notes",
            "E20261015 10:00:05.000 1234 engine.cc:90] lookup failed for 「我想去医院」",
        ]
        #expect(Doctor.summarizeLogLines(lines, home: "/Users/x", limit: 10) == [
            "Rime dictionary failed to load: ~/Library/Rime/user.dict.yaml",
            "update failed to install (network, -1009)",
            "error in Rime (engine)",
            "plugin weather failed to load",
            "update check failed (signature)",
            "Rime lookup failed",
            "1 other log line",
        ])
        // Never a stray word of the line: a line no event matches is only counted.
        #expect(Doctor.summarizeLogLines(["commit failed: hunter2 was not sent"], home: "/Users/x") == ["1 other log line"])
        #expect(Doctor.summarizeLogLines(["update check failed: The request timed out. (NSURLErrorDomain -1001)"], home: "")
                == ["update check failed (timed out)"])
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

    @Test func typographicAndCJKQuotesAreLeftOut() {
        let lines = ["error: couldn’t read “my diary.txt”", "failed: 「我想去医院」 and 『秘密』 and «privé» and ‘mine’"]
        let out = Doctor.summarizeLogLines(lines, home: "/Users/x")
        #expect(out == ["2 other log lines"])
    }

    @Test func probesNeverShowOrSendKeysOrFullPaths() {
        let key = "sk-ant-" + "api03-Zx8Qw2Lm4Np6Rt0Vb3Yc5Hd7Jf9Kg1Ms2Pu4Wx6Ab8Cd"
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

    @Test func fileURLsAndMaskedTextAreMaskedOnce() {
        #expect(Doctor.maskingAbsolutePaths("couldn't open file:///Users/x/My%20Notes/secret.txt now") == "couldn't open file://…/secret.txt now")
        #expect(Doctor.maskingAbsolutePaths("file://localhost/opt/data/a.json") == "file://…/a.json")
        let once = Doctor.scrub("moved /opt/data/a.zip", home: "/Users/x")
        #expect(once == "moved …/a.zip" && Doctor.scrub(once, home: "/Users/x") == once)
    }

    @Test func otherLogLinesArentCountedAsErrors() {
        let only = Doctor.findings(facts { $0.recentErrors = ["2 other log lines"] }, chinese: false).first { $0.area == .recentErrors }
        #expect(only?.text(chinese: false) == "⚠ Other lines in the logs — 2 other log lines")
        let one = Doctor.findings(facts { $0.recentErrors = ["update check failed (network)", "1 other log line"] }, chinese: false)
            .first { $0.area == .recentErrors }
        #expect(one?.title == "1 recent error in the logs" && one?.detail == "update check failed (network); 1 other log line")
        let skipped = Doctor.findings(facts { $0.skippedExtensions = ["a.sh: no title"] }, chinese: false).first { $0.area == .extensions }
        #expect(skipped?.title == "1 extension command wasn't loaded")
    }
}
