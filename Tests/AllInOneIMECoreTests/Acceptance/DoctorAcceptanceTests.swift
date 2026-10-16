import Foundation
import Testing
@testable import AllInOneIMECore

// Acceptance tests for `@doctor` (spec-doctor.md, with @config's CHANGE 1 and the coordinator's decisions), written from
// the spec by an independent reviewer; the implementer may not edit them. Each test names what it enforces: "area<N>"
// the spec's check N, "order" problems first, "fix" the fixes, "logs" the log summaries, "ask" `@doctor <question>`,
// "noai" apps with no AI.
//
// The probes are injected (`Doctor.Facts`); the model is `AICAppleStub` or the HTTP stub (AIConfigAcceptanceTests.swift);
// config files are temporary. The input controller is stood in for by `DocRig`, which does with the composer's effects
// what DoctorController and AIConfigController do (`startDoctor`, `previewFixes`, `applyConfig`, `undoConfig`).

// MARK: - Fixtures

enum Doc {
    /// A setup with nothing wrong: every probe says fine.
    static var healthy: Doctor.Facts {
        var facts = Doctor.Facts()
        var config = AIC.base
        config.provider = .anthropic
        facts.config = config
        facts.configData = try! JSONEncoder().encode(config)
        facts.keySaved = [.anthropic: true]
        facts.apple = .available
        facts.connection = .ok("claude-haiku-5-5 answered in 0.8 s")
        facts.accessibility = .granted
        facts.microphone = .granted
        facts.automation = ["Notes": .granted, "Terminal": .granted]
        facts.secureInput = nil
        facts.packs = [.chinese: .installed]
        facts.updates.available = nil
        facts.recentErrors = []
        return facts
    }

    /// A setup with a problem in every area.
    static var broken: Doctor.Facts {
        var facts = healthy
        facts.inputMethod.enabled = false
        facts.keySaved = [:]
        facts.connection = .failed("401 Unauthorized")
        facts.apple = .appleIntelligenceNotEnabled
        facts.accessibility = .denied
        facts.microphone = .denied
        facts.automation = ["Notes": .denied]
        facts.secureInput = "1Password"
        facts.packs = [.chinese: .missing]
        var config = facts.config!
        config.typeOutRate = 100
        config.outputLanguages = ["en", "fr", "de", "es", "it", "pt"].map(OutputLanguage.init)
        facts.config = config
        facts.configData = Data(#"{"provider":"anthropic","typeOutRate":100,"outputLanguages":["en","fr","de","es","it","pt","fr"],"futureSetting":1}"#.utf8)
        facts.skippedExtensions = ["weather.sh: no @raycast.title"]
        facts.pluginErrors = ["broken-plugin: manifest.json can't be read"]
        facts.updates.available = "9.9.9"
        facts.updates.lastError = "the download was interrupted"
        facts.recentErrors = ["update check failed: timed out"]
        return facts
    }

    static func findings(_ facts: Doctor.Facts, _ area: Doctor.Area, chinese: Bool = false) -> [Doctor.Finding] {
        Doctor.findings(facts, chinese: chinese).filter { $0.area == area }
    }

    static func statuses(_ facts: Doctor.Facts, _ areas: Set<Doctor.Area>) -> [Doctor.Status] {
        Doctor.findings(facts, chinese: false).filter { areas.contains($0.area) }.map(\.status)
    }

    /// The panel's report of `findings`, as DoctorController makes it.
    static func report(_ findings: [Doctor.Finding], chinese: Bool = false, recommended: [Int] = [], explanation: String? = nil)
        -> Composer.ConfigState.Report {
        Composer.ConfigState.Report(lines: findings.map { $0.text(chinese: chinese) }, fixes: findings.map(\.fix),
                                    recommended: recommended, explanation: explanation,
                                    summary: Doctor.summary(findings, chinese: chinese), isFinal: true)
    }

    static func doctorService(_ apple: AICAppleStub, secrets: AICSecrets = AICSecrets(), keys: Bool = true) -> DoctorService {
        DoctorService(client: ChatClient(bedrock: BedrockClient(session: AICHTTPStub.session()), apple: apple),
                      loadCredentials: { _ in
                          secrets.asked()
                          throw AICNoCredentials()
                      },
                      loadKey: { _, _ in
                          secrets.asked()
                          return keys ? "sk-test-not-a-real-key" : nil
                      })
    }

    static func isEdit(_ effect: Composer.Effect) -> Bool {
        if case .applyConfig = effect { return true } else { return false }
    }

    static func fixesPreviewed(_ effects: [Composer.Effect]) -> [[Doctor.Fix]] {
        effects.compactMap { if case let .previewFixes(fixes) = $0 { return fixes } else { return nil } }
    }
}

private let docAt = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
private let docTab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
private let docCommandZ = KeyEvent(keyCode: 0x06, characters: "z", charactersIgnoringModifiers: "z", modifiers: .command)

// MARK: - The input controller, stood in for

final class DocRig {
    let composer = Composer(engine: FakeEngine(), actionKey: .enter)
    let url: URL
    var facts: Doctor.Facts
    var env = AIC.env()
    let apple: AICAppleStub
    let service: DoctorService
    var lastApplied: AIConfig.Applied?
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    /// What the fixes did besides the settings, and the key fields opened.
    var actions: [AIConfig.Action] = []
    var openedKeyField: [Provider] = []
    var notices: [String] = []
    var effects: [Composer.Effect] = []
    /// The questions the model was asked.
    var asked: [String] = []

    init(_ facts: Doctor.Facts = Doc.broken, apple: AICAppleStub = AICAppleStub()) throws {
        self.facts = facts
        url = try AIC.tempConfig(facts.config ?? AIC.base)
        self.apple = apple
        service = Doc.doctorService(apple)
        composer.setInputMode(.english)
    }

    var c: Composer { composer }
    var config: Config { (try? Config.load(from: url)) ?? .default }

    @discardableResult
    func key(_ event: KeyEvent) async -> [Composer.Effect] {
        let out = composer.handleKeyDown(event).effects
        effects += out
        await perform(out)
        return out
    }

    func type(_ text: String) async {
        for ch in text {
            await key(ch == " " ? spaceKey : KeyEvent(keyCode: 0, characters: String(ch), modifiers: ch.isUppercase ? .shift : []))
        }
    }

    /// "@doctor", a question if any, ⏎.
    @discardableResult
    func run(_ question: String = "") async -> [Composer.Effect] {
        await key(docAt)
        await type("doctor")
        await key(docTab)
        await type(question)
        return await key(enterKey)
    }

    func perform(_ effects: [Composer.Effect]) async {
        for effect in effects {
            switch effect {
            case let .startCommand(command, input, id) where command.kind == .doctor:
                await start(input, id: id)
            case let .previewFixes(fixes):
                guard let preview = Doctor.fixPreview(fixes, config: config, environment: env) else {
                    notices.append("Nothing to fix")
                    continue
                }
                self.effects += composer.showFixPreview(preview, lines: preview.rows.map { $0.text(chinese: env.chinese) })
            case let .applyConfig(preview):
                apply(preview)
            case .undoConfig:
                if let applied = lastApplied, (try? AIConfig.undo(applied, at: url, now: now)) == true {
                    notices.append("undone")
                } else {
                    notices.append("nothing to undo")
                }
                lastApplied = nil
            default:
                break
            }
        }
    }

    /// As `startDoctor` (the connection test's outcome is among the facts).
    func start(_ question: String, id: Int) async {
        let findings = Doctor.findings(facts, chinese: env.chinese)
        var report = Doc.report(findings, chinese: env.chinese)
        if !question.isEmpty {
            asked.append(question)
            do {
                let answer = try await service.ask(question, findings: findings, config: facts.config ?? .default)
                report.explanation = answer.explanation
                report.recommended = answer.fixes
            } catch {
                report.explanation = "Couldn't ask the AI: \(error)"
            }
        }
        effects += composer.receiveDoctor(report, id: id)
    }

    /// As `applyConfig`.
    func apply(_ preview: AIConfig.Preview) {
        if !preview.edits.isEmpty {
            lastApplied = try? AIConfig.applying(preview.edits, at: url, now: now)
        }
        actions += preview.actions
        if let provider = preview.needsKey {
            effects += composer.endConfig()
            openedKeyField.append(provider)
            return
        }
        effects += composer.configApplied(preview.edits.isEmpty ? "Done" : AIConfig.Text(chinese: false).applied(preview.edits.count))
    }

    var rows: [String] { composer.choices.map(\.text) }
}

// MARK: - The tests

struct DoctorAcceptanceTests {
    // MARK: The nine checks, from injected facts

    /// 1. The input method is installed, enabled, selectable and current.
    @Test func area1_inputMethod() {
        var facts = Doc.healthy
        #expect(Doc.statuses(facts, [.inputMethod]) == [.ok])
        #expect(Doc.findings(facts, .inputMethod)[0].text(chinese: false).contains(facts.inputMethod.version))
        facts.inputMethod.registered = false
        #expect(Doc.statuses(facts, [.inputMethod]) == [.problem])
        #expect(Doc.findings(facts, .inputMethod)[0].fix == .enableInputMethod)
        facts = Doc.healthy
        facts.inputMethod.enabled = false
        #expect(Doc.statuses(facts, [.inputMethod]) == [.problem])
        #expect(Doc.findings(facts, .inputMethod)[0].fix == .enableInputMethod)
        facts = Doc.healthy
        facts.inputMethod.listed = false
        #expect(Doc.statuses(facts, [.inputMethod]).first.map { $0 != .ok } == true)
        facts = Doc.healthy
        facts.inputMethod.selectable = false
        #expect(Doc.statuses(facts, [.inputMethod]).first.map { $0 != .ok } == true)
    }

    /// 2. The AI provider: which one, its key or profile (existence only), Test Connection, Apple Intelligence.
    @Test func area2_provider() {
        var facts = Doc.healthy
        #expect(Doc.statuses(facts, [.provider, .connection, .appleIntelligence]).allSatisfy { $0 == .ok })
        #expect(Doc.findings(facts, .provider)[0].text(chinese: false).contains("Claude"))
        // No key saved: a problem, fixed by the key field.
        facts.keySaved = [:]
        let noKey = Doc.findings(facts, .provider)
        #expect(noKey.map(\.status) == [.problem] && noKey[0].fix == .openKeyField(.anthropic))
        // Bedrock: the profile resolves (its region shown, no credentials), or not.
        facts = Doc.healthy
        var bedrock = facts.config!
        bedrock.provider = .bedrock
        facts.config = bedrock
        facts.awsProfile = .success("us-west-2")
        #expect(Doc.statuses(facts, [.provider]) == [.ok])
        #expect(Doc.findings(facts, .provider)[0].text(chinese: false).contains("us-west-2"))
        facts.awsProfile = .failure(Doctor.ProbeError("The profile “default” isn't in ~/.aws/config"))
        #expect(Doc.statuses(facts, [.provider]) == [.problem])
        // Test Connection: running, failed.
        facts = Doc.healthy
        facts.connection = .running
        #expect(Doc.statuses(facts, [.connection]) == [.warning])
        facts.connection = .failed("401 Unauthorized")
        #expect(Doc.statuses(facts, [.connection]) == [.problem])
        #expect(Doc.findings(facts, .connection)[0].text(chinese: false).contains("401"))
        // Apple Intelligence's availability and reason.
        facts = Doc.healthy
        facts.apple = .appleIntelligenceNotEnabled
        let off = Doc.findings(facts, .appleIntelligence)
        #expect(off.map(\.status) == [.warning] && off[0].fix == .openAppleIntelligenceSettings)
        #expect(off[0].text(chinese: false).contains("System Settings"))
        var onApple = facts.config!
        onApple.provider = .apple
        facts.config = onApple
        facts.apple = .deviceNotEligible
        #expect(Doc.statuses(facts, [.provider]) == [.problem])
    }

    /// 3. Permissions: Accessibility, the microphone if voice is used, Automation for the apps used.
    @Test func area3_permissions() {
        var facts = Doc.healthy
        #expect(Doc.statuses(facts, [.permissions]).allSatisfy { $0 == .ok })
        facts.accessibility = .denied
        let ax = Doc.findings(facts, .permissions).filter { $0.status != .ok }
        #expect(ax.count == 1 && ax[0].fix == .openPrivacy(.accessibility))
        facts = Doc.healthy
        facts.microphone = .denied
        #expect(Doc.findings(facts, .permissions).contains { $0.status == .problem && $0.fix == .openPrivacy(.microphone) })
        var noVoice = facts.config!
        noVoice.voiceInput = false
        facts.config = noVoice
        #expect(!Doc.findings(facts, .permissions).contains { $0.fix == .openPrivacy(.microphone) })  // voice not used
        facts = Doc.healthy
        facts.automation = ["Notes": .denied, "Terminal": .granted]
        let auto = Doc.findings(facts, .permissions).filter { $0.status != .ok }
        #expect(auto.count == 1 && auto[0].fix == .openPrivacy(.automation) && auto[0].text(chinese: false).contains("Notes"))
    }

    /// 4. Secure input is on right now, and which app holds it.
    @Test func area4_secureInput() {
        var facts = Doc.healthy
        #expect(Doc.statuses(facts, [.secureInput]) == [.ok])
        facts.secureInput = "1Password"
        let on = Doc.findings(facts, .secureInput)
        #expect(on.count == 1 && on[0].status != .ok && on[0].text(chinese: false).contains("1Password"))
        #expect(on[0].text(chinese: true).contains("1Password"))
    }

    /// 5. Language packs: configured languages whose pack is missing or damaged.
    @Test func area5_languagePacks() {
        var facts = Doc.healthy
        #expect(Doc.statuses(facts, [.languagePacks]) == [.ok])
        for state in [Doctor.Facts.Pack.missing, .damaged] {
            facts.packs = [.chinese: state]
            let found = Doc.findings(facts, .languagePacks)
            #expect(found.map(\.status) == [.problem], "\(state)")
            #expect(found.first?.fix == .downloadPack(.chinese))
            #expect(found.first?.text(chinese: false).contains("Chinese") == true)
        }
        facts.packs = [.chinese: .downloading]
        #expect(Doc.statuses(facts, [.languagePacks]) == [.warning])
    }

    /// 6. Config: it parses; unknown keys; values out of range; a language twice; more than 5 output languages.
    @Test func area6_config() throws {
        var facts = Doc.healthy
        #expect(Doc.statuses(facts, [.config]) == [.ok])
        // Doesn't parse: a problem, never fixed by replacing the file.
        facts.config = nil
        facts.configError = "The data isn't valid JSON (line 3)"
        let unreadable = Doc.findings(facts, .config)
        #expect(unreadable.map(\.status) == [.problem] && unreadable[0].fix == nil)
        // Unknown keys.
        facts = Doc.healthy
        facts.configData = Data(#"{"provider":"anthropic","futureSetting":true}"#.utf8)
        let unknown = Doc.findings(facts, .config)
        #expect(unknown.map(\.status) == [.warning] && unknown[0].text(chinese: false).contains("futureSetting"))
        // Out of range: repaired through @config.
        facts = Doc.healthy
        facts.config!.typeOutRate = 100
        let range = Doc.findings(facts, .config)
        #expect(range.map(\.status) == [.problem])
        guard case .repairConfig? = range.first?.fix else { Issue.record("no repair: \(range)"); return }
        // A language twice.
        facts = Doc.healthy
        facts.configData = Data(#"{"provider":"anthropic","outputLanguages":["en","fr","en"]}"#.utf8)
        #expect(Doc.statuses(facts, [.config]) == [.warning])
        #expect(Doc.findings(facts, .config).first?.fix != nil)
        // More than 5 output languages: keep the first 5.
        facts = Doc.healthy
        facts.config!.outputLanguages = ["en", "fr", "de", "es", "it", "pt"].map(OutputLanguage.init)
        let many = Doc.findings(facts, .config)
        #expect(many.map(\.status) == [.problem])
        let fix = try #require(many.first?.fix)
        let preview = try #require(Doctor.fixPreview([fix], config: facts.config!, environment: AIC.env()))
        var repaired = facts.config!
        AIConfig.apply(preview.edits, to: &repaired)
        #expect(repaired.outputLanguages == ["en", "fr", "de", "es", "it"].map(OutputLanguage.init))
    }

    /// 7. Extensions and plugins: skipped commands with their reasons, plugin errors.
    @Test func area7_extensions() {
        var facts = Doc.healthy
        #expect(Doc.statuses(facts, [.extensions]) == [.ok])
        facts.skippedExtensions = ["weather.sh: no @raycast.title"]
        let skipped = Doc.findings(facts, .extensions)
        #expect(skipped.map(\.status) == [.warning] && skipped[0].text(chinese: false).contains("no @raycast.title"))
        facts = Doc.healthy
        facts.pluginErrors = ["broken-plugin: manifest.json can't be read"]
        let plugins = Doc.findings(facts, .extensions)
        #expect(plugins.map(\.status) == [.warning] && plugins[0].text(chinese: false).contains("manifest.json"))
    }

    /// 8. Updates: the version, whether a newer one exists, the last update error.
    @Test func area8_updates() {
        var facts = Doc.healthy
        let current = Doc.findings(facts, .updates)
        #expect(current.map(\.status) == [.ok] && current[0].text(chinese: false).contains(facts.updates.version))
        facts.updates.available = "9.9.9"
        let newer = Doc.findings(facts, .updates)
        #expect(newer.map(\.status) == [.warning] && newer[0].fix == .checkForUpdates && newer[0].text(chinese: false).contains("9.9.9"))
        facts = Doc.healthy
        facts.updates.lastError = "the download was interrupted"
        #expect(Doc.findings(facts, .updates).contains { $0.status == .warning && $0.text(chinese: false).contains("interrupted") })
    }

    /// 9. Recent errors from the app's own logs.
    @Test func area9_recentErrors() {
        var facts = Doc.healthy
        #expect(Doc.statuses(facts, [.recentErrors]) == [.ok])
        facts.recentErrors = ["update check failed: timed out"]
        let errors = Doc.findings(facts, .recentErrors)
        #expect(errors.map(\.status) == [.warning] && errors[0].text(chinese: false).contains("timed out"))
    }

    /// Every one of the nine checks gives a row, marked ✓ / ⚠ / ✗, in both languages.
    @Test func area_everyCheckHasMarkedRowsInBothLanguages() {
        let areas: [(String, Set<Doctor.Area>)] = [
            ("input method", [.inputMethod]), ("provider", [.provider, .connection, .appleIntelligence]),
            ("permissions", [.permissions]), ("secure input", [.secureInput]), ("language packs", [.languagePacks]),
            ("config", [.config]), ("extensions", [.extensions]), ("updates", [.updates]), ("recent errors", [.recentErrors]),
        ]
        for facts in [Doc.healthy, Doc.broken] {
            for chinese in [false, true] {
                let findings = Doctor.findings(facts, chinese: chinese)
                for (name, set) in areas {
                    let rows = findings.filter { set.contains($0.area) }
                    #expect(!rows.isEmpty, "\(name) has no row")
                    for row in rows {
                        let text = row.text(chinese: chinese)
                        #expect(text.hasPrefix(row.status.mark + " "), "\(text)")
                        #expect(["✓", "⚠", "✗"].contains(row.status.mark))
                    }
                }
                if chinese {
                    #expect(findings.allSatisfy { $0.text(chinese: true).unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF } })
                }
            }
        }
        #expect(Doc.findings(Doc.broken, .inputMethod)[0].status == .problem)
    }

    // MARK: Order

    /// Problems first, then warnings, then what is fine; the panel lists them in that order.
    @Test func order_problemsFirst() async throws {
        // Fine, a warning, a problem late in the areas' order.
        var facts = Doc.healthy
        facts.secureInput = "1Password"
        facts.recentErrors = ["update check failed: timed out"]
        facts.packs = [.chinese: .missing]
        facts.updates.available = "9.9.9"
        for mixed in [facts, Doc.broken] {
            let ranks = Doctor.findings(mixed, chinese: false).map(\.status.rawValue)
            #expect(ranks == ranks.sorted())
        }
        let findings = Doctor.findings(facts, chinese: false)
        #expect(findings.first?.area == .languagePacks && findings.first?.status == .problem)
        #expect(Set(findings.map(\.status)) == [.problem, .warning, .ok])
        let rig = try DocRig(facts)
        await rig.run()
        #expect(rig.c.phase == .choosing)
        #expect(rig.rows == findings.map { $0.text(chinese: false) })
        #expect(rig.rows.first?.hasPrefix("✗") == true)
    }

    // MARK: Fixes

    /// ⏎ fixes the safe ones only: settings repaired, the input method enabled again, Check for Updates. Panes,
    /// windows and downloads are picked one by one.
    @Test func fix_enterAppliesOnlySafeFixes() async throws {
        let rig = try DocRig(Doc.broken)
        await rig.run()
        let effects = await rig.key(enterKey)
        let previewed = try #require(Doc.fixesPreviewed(effects).first)
        #expect(!previewed.isEmpty)
        #expect(previewed.allSatisfy { $0.isSafe }, "\(previewed)")
        #expect(!previewed.contains { if case .openPrivacy = $0 { return true } else { return false } })
        #expect(!previewed.contains { if case .downloadPack = $0 { return true } else { return false } })
        #expect(!previewed.contains { if case .openKeyField = $0 { return true } else { return false } })
        // Every safe fix among the findings is in it.
        let safe = Doctor.findings(Doc.broken, chinese: false).compactMap(\.fix).filter(\.isSafe)
        #expect(Set(safe.map { "\($0)" }) == Set(previewed.map { "\($0)" }))
        // And ⏎ on that preview applies them.
        await rig.key(enterKey)
        #expect(rig.config.typeOutRate == TypeOut.defaultRate)
        #expect(rig.actions.contains(.enableInputMethod))
        #expect(rig.openedKeyField.isEmpty)
        #expect(!rig.actions.contains { if case .openPrivacy = $0 { return true } else { return false } })
        #expect(!rig.actions.contains { if case .downloadPack = $0 { return true } else { return false } })
    }

    /// The same after `@doctor <question>`: whatever fixes the model names, ⏎ applies only safe ones.
    @Test func fix_enterAfterAQuestionStillOnlySafe() async throws {
        let findings = Doctor.findings(Doc.broken, chinese: false)
        let unsafe = try #require(findings.firstIndex { $0.fix != nil && $0.fix?.isSafe == false })
        let answer = #"{"explanation": "The key is missing.", "fixes": ["F\#(unsafe + 1)"]}"#
        let rig = try DocRig(Doc.broken, apple: AICAppleStub([answer]))
        await rig.run("why doesnt translate work")
        #expect(rig.apple.calls.count == 1)
        let effects = await rig.key(enterKey)
        for fixes in Doc.fixesPreviewed(effects) {
            #expect(fixes.allSatisfy { $0.isSafe }, "⏎ applies \(fixes)")
        }
    }

    /// A finding's number picks its fix, unsafe ones too, into the same preview.
    @Test func fix_digitPicksOneFix() async throws {
        let rig = try DocRig(Doc.broken)
        await rig.run()
        let numbered = rig.c.choices.filter { !$0.label.isEmpty }
        let findings = Doctor.findings(Doc.broken, chinese: false)
        #expect(numbered.count == min(9, findings.filter { $0.fix != nil }.count))
        let first = try #require(numbered.first)
        let effects = await rig.key(KeyEvent(keyCode: 0x12, characters: first.label))
        let picked = try #require(Doc.fixesPreviewed(effects).first)
        let fix = try #require(findings.first { $0.text(chinese: false) == first.text }?.fix)
        #expect(picked == [fix])
        #expect(rig.c.configPreview != nil)
    }

    /// A settings fix goes through @config's preview (old → new), its apply and its undo (⌘Z); Esc on the preview goes
    /// back to the findings; nothing is inserted.
    @Test func fix_throughConfigPreviewAndUndo() async throws {
        var facts = Doc.healthy
        facts.config!.typeOutRate = 100
        let rig = try DocRig(facts)
        let before = try AIC.bytes(rig.url)
        await rig.run()
        let findings = Doctor.findings(facts, chinese: false)
        #expect(findings.first?.area == .config)
        await rig.key(enterKey)  // the safe fixes: the speed
        #expect(rig.rows.count == 1 && rig.rows[0].contains("→"), "\(rig.rows)")
        #expect(rig.rows[0].contains("100") && rig.rows[0].contains("16"))
        await rig.key(escKey)  // back to the findings
        #expect(rig.rows == findings.map { $0.text(chinese: false) })
        await rig.key(enterKey)
        let applied = await rig.key(enterKey)
        #expect(applied.contains { Doc.isEdit($0) })
        #expect(rig.config.typeOutRate == TypeOut.defaultRate)
        let undo = await rig.key(docCommandZ)
        #expect(undo.contains(.undoConfig))
        #expect(try AIC.bytes(rig.url) == before)
        #expect(aicInsertsNothing(rig.effects))
    }

    /// No fix touches a key or deletes the user's data: the fixes' previews change no provider setting or credential,
    /// remove nothing, and their actions are the safe local ones.
    @Test func fix_noFixTouchesKeysOrDeletesData() throws {
        var facts = Doc.broken
        facts.config!.redaction.customWords = ["Bluebird"]
        facts.config!.appProfiles = ["com.apple.mail": AppProfile(rewriteStyles: ["正式"])]
        facts.config!.customCommands = [CustomCommand(name: "tweetit", type: .prompt, prompt: "Tweet it")]
        let config = facts.config!
        let fixes = Doctor.findings(facts, chinese: false).compactMap(\.fix)
            + [.enableInputMethod, .openPrivacy(.accessibility), .openPrivacy(.microphone), .openPrivacy(.automation),
               .downloadPack(.korean), .resaveConfig, .openKeyField(.anthropic), .openKeyField(.bedrock),
               .openAppleIntelligenceSettings, .checkForUpdates]
        for fix in fixes {
            guard let preview = Doctor.fixPreview([fix], config: config, environment: AIC.env()) else { continue }
            for edit in preview.edits {
                switch edit {
                case .provider, .awsProfile, .region, .model, .baseURL: Issue.record("\(fix) changes the provider: \(edit)")
                case .customWords: Issue.record("\(fix) replaces the hidden words")
                default: break
                }
            }
            var after = config
            AIConfig.apply(preview.edits, to: &after)
            #expect(after.redaction.customWords == config.redaction.customWords, "\(fix)")
            #expect(after.appProfiles == config.appProfiles, "\(fix)")
            #expect(after.customCommands == config.customCommands, "\(fix)")
            #expect(after.provider == config.provider && after.anthropic == config.anthropic && after.awsProfile == config.awsProfile)
            for row in preview.rows {
                if case .needsKey = row.status { #expect(row.edit == nil && row.action == nil) }  // opens the field, no more
            }
            let allowed: [AIConfig.Action] = [.resaveConfig, .enableInputMethod, .openPrivacy(.accessibility), .openPrivacy(.microphone),
                                              .openPrivacy(.automation), .downloadPack(.korean), .downloadPack(.chinese),
                                              .openAppleIntelligenceSettings, .checkForUpdates]
            for action in preview.actions { #expect(allowed.contains(action), "\(action)") }
        }
        // A repair can't sneak in a forbidden key either: it goes through @config's checks.
        let sneaky = Doctor.Fix.repairConfig([.init(key: .forbidden("anthropic.apiKey", secret: true), value: .string(AIC.claudeKey)),
                                              .init(key: .setting(.provider), value: .string("gemini"))])
        let preview = Doctor.fixPreview([sneaky], config: config, environment: AIC.env(offered: [.anthropic]))
        #expect(preview?.edits.isEmpty ?? true)
    }

    /// The checks themselves never send anything: `@doctor` alone asks no model.
    @Test func fix_checksNeverSend() async throws {
        let rig = try DocRig(Doc.broken, apple: AICAppleStub(["{}"]))
        let effects = await rig.run()
        #expect(effects.contains(.startCommand(.doctor, input: "", id: 1)) || effects.contains { if case .startCommand(.doctor, "", _) = $0 { return true } else { return false } })
        #expect(rig.apple.calls.isEmpty && rig.asked.isEmpty)
        #expect(rig.c.phase == .choosing)
    }

    // MARK: Logs

    /// Log lines are summarised without the user's text: no timestamps or sources, the home folder as ~, quoted text
    /// left out, short, the newest few.
    @Test func logs_summariesCarryNoUserText() {
        let home = "/Users/someone"
        let lines = [
            "I20261015 10:00:00.000 1234 engine.cc:10] loaded",
            "E20261015 10:00:01.000 1234 dictionary.cc:56] failed to load \(home)/Library/Rime/user.dict.yaml",
            "E20261015 10:00:02.000 1234 engine.cc:80] lookup failed for \"wo xiang qu yiyuan kan bing\"",
            "update failed: couldn't move \(home)/Downloads/AllInOneIME.zip",
            "E20261015 10:00:03.000 1234 engine.cc:81] commit error: 'my bank password is hunter2'",
            "E20261015 10:00:04.000 1234 engine.cc:82] error " + String(repeating: "x", count: 300),
        ]
        let summary = Doctor.summarizeLogLines(lines, home: home, limit: 10)
        #expect(summary.count == 5)  // the error lines only
        for line in summary {
            #expect(!line.contains(home), "\(line)")
            #expect(!line.contains("wo xiang qu") && !line.contains("hunter2"), "\(line)")
            #expect(!line.contains("20261015") && !line.contains(".cc:"), "\(line)")
            #expect(line.count <= 121)
        }
        #expect(summary.contains { $0.contains("~/Library/Rime") })
        #expect(Doctor.summarizeLogLines(lines, home: home).count == 3)
        #expect(Doctor.summarizeLogLines(lines, home: home).last?.hasPrefix("error") == true)
    }

    /// Edge: text quoted the way macOS and the app quote it (“…”, 「…」) is the user's too.
    @Test func logs_typographicQuotesLeftOut() {
        let lines = [
            "@config failed: couldn’t read “my secret diary.txt”",
            "E20261015 10:00:02.000 1234 engine.cc:80] lookup failed for 「我想去医院看病」",
        ]
        for line in Doctor.summarizeLogLines(lines, home: "/Users/someone") {
            #expect(!line.contains("secret diary") && !line.contains("我想去医院"), "\(line)")
        }
    }

    // MARK: @doctor <question>

    /// On the device first: the model gets the question and the check results (through its tools) and nothing else of
    /// the config; no key or credentials are asked for; nothing goes over the network.
    @Test func ask_onDeviceFirstWithFindingsAndQuestion() async throws {
        let host = AIC.host()
        var facts = Doc.broken
        facts.config = AIC.onClaude(facts.config!, host: host)
        facts.config!.redaction.customWords = ["Bluebird"]
        facts.config!.customCommands = [CustomCommand(name: "sentinelcmd", type: .prompt, prompt: "SENTINEL-PROMPT")]
        let findings = Doctor.findings(facts, chinese: false)
        let apple = AICAppleStub([#"{"explanation": "Your Claude key isn't saved.", "fixes": ["F2"]}"#])
        let secrets = AICSecrets()
        let question = "why doesnt translate work"
        let answer = try await Doc.doctorService(apple, secrets: secrets).ask(question, findings: findings, config: facts.config!)
        #expect(answer.onDevice)
        #expect(answer.explanation == "Your Claude key isn't saved.")
        let call = try #require(apple.calls.first)
        #expect(call.guided)
        #expect(call.request.prompt.contains(question))
        // The check results reach it (through the tools).
        let report = Doctor.report(findings)
        for line in report.split(separator: "\n") { #expect(call.text.contains(String(line)), "\(line) missing") }
        #expect(!call.text.contains("Bluebird") && !call.text.contains("SENTINEL") && !call.text.contains("sentinelcmd"))
        #expect(secrets.count == 0)
        #expect(AICHTTPStub.bodies(host).isEmpty)
        // Only fixes the findings have.
        #expect(answer.fixes.allSatisfy { findings[$0].fix != nil })
    }

    /// No paths beyond ~-relative are sent, whatever the probes reported.
    @Test func ask_noPathsBeyondHome() async throws {
        let home = NSHomeDirectory()
        var facts = Doc.broken
        facts.skippedExtensions = ["\(home)/Extensions/weather.sh: no @raycast.title"]
        facts.pluginErrors = ["\(home)/Library/Application Support/AllInOneIME/plugins/broken: manifest.json can't be read"]
        facts.updates.lastError = "couldn't move \(home)/Downloads/AllInOneIME.zip"
        facts.configError = nil
        let findings = Doctor.findings(facts, chinese: false)
        // On the device.
        let apple = AICAppleStub([#"{"explanation": "x"}"#])
        _ = try await Doc.doctorService(apple).ask("why", findings: findings, config: facts.config!)
        #expect(!(apple.calls.first?.text ?? "").contains(home), "a full path went to the model")
        // On the configured provider.
        let host = AIC.host()
        AICHTTPStub.enqueue(host, #"{"explanation": "x"}"#)
        _ = try await Doc.doctorService(AICAppleStub(availability: .deviceNotEligible))
            .ask("why", findings: findings, config: AIC.onClaude(facts.config!, host: host))
        #expect(AICHTTPStub.sentTexts(host).allSatisfy { !$0.contains(home) }, "a full path went to the provider")
    }

    /// No keys are sent, whatever the probes reported (a connection error that echoes a key, say), even with the
    /// user's redaction off.
    @Test func ask_noKeys() async throws {
        var facts = Doc.broken
        facts.connection = .failed("401: invalid x-api-key \(AIC.claudeKey)")
        facts.pluginErrors = ["slack: token \(AIC.geminiKey) rejected"]
        facts.config!.redaction.enabled = false
        let findings = Doctor.findings(facts, chinese: false)
        let apple = AICAppleStub([#"{"explanation": "x"}"#])
        _ = try await Doc.doctorService(apple).ask("why", findings: findings, config: facts.config!)
        let text = apple.calls.first?.text ?? ""
        #expect(!text.contains(AIC.claudeKey) && !text.contains(AIC.geminiKey), "a key went to the model")
    }

    /// Apple Intelligence unavailable: the configured provider gets the findings and the question, and the answer says
    /// it came from there; with neither, it fails.
    @Test func ask_configuredProviderWhenOnDeviceUnavailable() async throws {
        let host = AIC.host()
        AICHTTPStub.enqueue(host, #"{"explanation": "No key.", "fixes": ["F1"]}"#)
        let facts = Doc.broken
        let findings = Doctor.findings(facts, chinese: false)
        let apple = AICAppleStub(availability: .appleIntelligenceNotEnabled)
        let answer = try await Doc.doctorService(apple).ask("why doesnt translate work", findings: findings,
                                                            config: AIC.onClaude(facts.config!, host: host))
        #expect(!answer.onDevice)
        #expect(apple.calls.isEmpty)
        let sent = try #require(AICHTTPStub.sentTexts(host).first)
        #expect(sent.contains("why doesnt translate work"))
        #expect(sent.contains(Doctor.report(findings)))
        // Neither.
        var onApple = facts.config!
        onApple.provider = .apple
        await #expect(throws: (any Error).self) {
            _ = try await Doc.doctorService(apple).ask("why", findings: findings, config: onApple)
        }
    }

    /// The answer's fixes are only findings that have one.
    @Test func ask_parseKeepsOnlyRealFixes() {
        let findings = Doctor.findings(Doc.broken, chinese: false)
        let withFix = findings.indices.filter { findings[$0].fix != nil }
        let without = findings.indices.first { findings[$0].fix == nil }!
        let text = #"```json"# + "\n" + #"{"explanation": "e", "fixes": ["F\#(withFix[0] + 1)", "F\#(without + 1)", "F999", "nonsense"]}"# + "\n```"
        let answer = DoctorService.parse(text, findings: findings)
        #expect(answer.explanation == "e" && answer.fixes == [withFix[0]])
    }

    // MARK: Apps with no AI

    /// Coordinator: @doctor's checks still run in an app with no AI.
    @Test func noai_checksStillRun() async throws {
        let rig = try DocRig(Doc.broken)
        rig.c.aiRefusal = { "AI is off in this app" }
        let effects = await rig.run()
        #expect(effects.contains { if case .startCommand(.doctor, "", _) = $0 { return true } else { return false } })
        #expect(rig.c.phase == .choosing && !rig.rows.isEmpty)
    }

    /// Coordinator: `@doctor <question>` is refused there: the question isn't sent.
    @Test func noai_questionNotSent() async throws {
        let rig = try DocRig(Doc.broken, apple: AICAppleStub([#"{"explanation": "x"}"#]))
        rig.c.aiRefusal = { "AI is off in this app" }
        await rig.run("why doesnt translate work")
        #expect(rig.asked.isEmpty && rig.apple.calls.isEmpty)
        #expect(rig.effects.contains(.notice("AI is off in this app")) || rig.c.configState.report?.explanation != nil)
        #expect(aicInsertsNothing(rig.effects))
    }

    /// Coordinator: … while the checks still run (only the question is refused).
    @Test func noai_questionRefusedButChecksStillRun() async throws {
        let rig = try DocRig(Doc.broken, apple: AICAppleStub([#"{"explanation": "x"}"#]))
        rig.c.aiRefusal = { "AI is off in this app" }
        await rig.run("why doesnt translate work")
        #expect(rig.asked.isEmpty)
        #expect(rig.c.configState.report != nil, "the checks didn't run")
        #expect(rig.rows == Doctor.findings(Doc.broken, chinese: false).map { $0.text(chinese: false) })
    }
}
