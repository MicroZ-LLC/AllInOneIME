import Foundation
import Testing
@testable import AllInOneIMECore

/// `@reportissue`: GitHub's new-issue page with the title and the diagnostics, nothing personal in them.
struct IssueReportTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")

    var diagnostics: IssueReport.Diagnostics {
        IssueReport.Diagnostics(appVersion: "0.6.3", macOS: "26.1", architecture: "arm64", interfaceLanguage: "system (en)",
                                inputLanguages: ["en", "zh"], languagePacks: ["zh-pinyin 1.0.0"], provider: "bedrock",
                                model: "us.anthropic.claude-haiku-4-5-20251001-v1:0", actionKey: "enter",
                                customCommands: 2, plugins: 1, extensions: 5)
    }

    /// The query's values as GitHub reads them.
    func query(_ url: URL) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    // MARK: - The address

    @Test func theNewIssuePageWithTitleAndBody() {
        let url = IssueReport(title: "Pinyin 候选 & more", diagnostics: diagnostics).url
        #expect(url.absoluteString.hasPrefix("https://github.com/MicroZ-LLC/AllInOneIME/issues/new?title="))
        let values = query(url)
        #expect(values["title"] == "Pinyin 候选 & more")  // "&" can't end the value
        // No labels: GitHub answers 404 when the user may not label issues.
        #expect(Set(values.keys) == ["title", "body"])
        let body = values["body"] ?? ""
        #expect(body.contains("### What happened") && body.contains("### What you expected") && body.contains("### Diagnostics"))
        #expect(body.contains("- AllInOneIME: 0.6.3") && body.contains("- macOS: 26.1 (arm64)"))
        #expect(body.contains("- Input languages: en, zh") && body.contains("- Language packs: zh-pinyin 1.0.0"))
        #expect(body.contains("- AI provider: bedrock (us.anthropic.claude-haiku-4-5-20251001-v1:0)") && body.contains("- Action key: enter"))
        #expect(body.contains("- Custom commands: 2, plugins: 1, extensions: 5"))
        #expect(!url.absoluteString.contains(" ") && !url.absoluteString.contains("+"))  // spaces as %20, a plus encoded
    }

    @Test func theTitleIsOneLine() {
        #expect(IssueReport(title: "  two\nlines\twith\u{7}bell  ", diagnostics: diagnostics).title == "two lines withbell")
        #expect(IssueReport(title: String(repeating: "长", count: 500), diagnostics: diagnostics).title.count == IssueReport.maxTitleLength)
        #expect(IssueReport(title: "", diagnostics: diagnostics).title.isEmpty)
    }

    @Test func longDiagnosticsAreCutFirstThenTheTitle() {
        var long = diagnostics
        long.languagePacks = (1...400).map { "pack-\($0) 1.0.0" }
        let report = IssueReport(title: "Crash on start", diagnostics: long)
        let url = report.url
        #expect(url.absoluteString.count <= IssueReport.maxURLLength)
        let body = query(url)["body"] ?? ""
        // The lines after the one too long went with it; "…" says so; the title and the template are whole.
        #expect(query(url)["title"] == "Crash on start" && body.contains("- macOS: 26.1") && body.hasSuffix("- …"))
        #expect(!body.contains("pack-400") && body.contains("### What you expected"))
        // Everything fits as it is: nothing cut.
        #expect(!(query(IssueReport(title: "x", diagnostics: diagnostics).url)["body"] ?? "").contains("…"))
        // A title that can't fit, even without diagnostics, is cut too (never past the limit).
        var report2 = IssueReport(title: "", diagnostics: long)
        report2.title = String(repeating: "长", count: 2000)
        #expect(report2.url.absoluteString.count <= IssueReport.maxURLLength && !(query(report2.url)["title"] ?? "").isEmpty)
    }

    // MARK: - Privacy

    @Test func onlyKindsAndCountsFromTheSettings() {
        var config = Config.default
        config.awsProfile = "jane-doe-work"
        config.region = "eu-central-1"
        config.customCommands = [CustomCommand(name: "secretproject", type: .run, argv: ["/Users/jane/bin/deploy", "{input}"])]
        config.extensionFolders = ["~/Projects/Secret/extensions"]
        config.jargonFile = "~/Documents/acme-jargon.txt"
        config.openai = ProviderSettings(model: "gpt-5.4-mini", baseURL: "https://jane:hunter2@llm.internal.acme.com/v1")
        config.provider = .openai
        config.setOrder([Language.chinese, .english])
        let d = IssueReport.Diagnostics(config: config, macOS: "26.1", architecture: "arm64", interfaceLanguage: "zh",
                                        languagePacks: ["zh-pinyin 1.0.0"], plugins: 3, extensions: 7)
        #expect(d.provider == "openai" && d.model == "gpt-5.4-mini" && d.customCommands == 1 && d.plugins == 3 && d.extensions == 7)
        #expect(d.inputLanguages == ["zh", "en"] && d.actionKey == "enter")
        let report = IssueReport(title: "Hello", diagnostics: d)
        let everything = report.lines.joined(separator: "\n") + (query(report.url)["body"] ?? "") + report.url.absoluteString
        for secret in ["jane", "hunter2", "acme", "secretproject", "deploy", "/Users", "~/", "eu-central-1", "Secret", "llm.internal"] {
            #expect(!everything.contains(secret), "\(secret) must not be in the report")
        }
    }

    @Test func onlyPublicModelsAreNamed() {
        // Public models' ids, as they are.
        for model in ["us.anthropic.claude-haiku-4-5-20251001-v1:0", "anthropic.claude-3-haiku-20240307-v1:0", "claude-haiku-5-5",
                      "gpt-5.4-mini", "gpt-4o", "o3-mini", "anthropic/claude-sonnet-5.5", "meta-llama/llama-3.1-8b-instruct:free",
                      "llama3.2:latest", "qwen2.5:7b", "gemini-3.8-flash", "deepseek-chat", "glm-4.6", "kimi-k2", "mistral.mistral-large-2407-v1:0",
                      "us.meta.llama3-1-70b-instruct-v1:0"] {
            #expect(IssueReport.publicModel(model) == model, "\(model)")
        }
        // Anything else: a fine-tuned model (its organization's name), an ARN (an account, a profile's id), a private
        // organization or deployment, a path, an address, a key.
        for value in ["ft:gpt-4o-mini-2024-07-18:acmecorp:support-bot:9AbCdEf1", "ft:gpt-4o:acme::abc123",
                      "arn:aws:bedrock:us-west-2:123456789012:inference-profile/us.anthropic.claude-haiku-4-5-20251001-v1:0",
                      "arn:aws:bedrock:us-west-2:123456789012:application-inference-profile/a1b2c3d4e5f6",
                      "acmecorp/support-model", "acme-support-bot", "acme-bot:latest", "my-gpt", "gpt-4o:acmecorp:x",
                      "yiacme", "claude-haiku-5-5:a-very-long-private-tag", "/Users/jane/models/llama.gguf", "~/models/x",
                      "https://host/v1", "jane@example.com", "sk-proj-abc123", "AK\u{49}AIOSFODNN7EXAMPLE",
                      "gpt-a1b2c3d4e5f6a7b8c9d0e1f2a3b4", "llama-123456789012", String(repeating: "x", count: 200), ""] {
            #expect(IssueReport.publicModel(value) == nil, "\(value)")
        }
        // In a report: the provider's kind always, the model by its id or as "custom".
        func model(_ provider: Provider, _ id: String) -> (String, String?) {
            var config = Config.default
            config.provider = provider
            config.modelId = id
            config.openai = ProviderSettings(model: id)
            let d = IssueReport.Diagnostics(config: config, macOS: "26", architecture: "arm64", interfaceLanguage: "en",
                                            languagePacks: [], plugins: 0, extensions: 0)
            return (d.provider, d.model)
        }
        #expect(model(.openai, "ft:gpt-4o-mini-2024-07-18:acmecorp:support-bot:9AbCdEf1") == ("openai", "custom"))
        #expect(model(.bedrock, "arn:aws:bedrock:us-west-2:123456789012:application-inference-profile/a1b2c3d4e5f6") == ("bedrock", "custom"))
        #expect(model(.openai, "gpt-5.4-mini") == ("openai", "gpt-5.4-mini"))
        let report = IssueReport(title: "", diagnostics: IssueReport.Diagnostics(
            config: { var c = Config.default; c.provider = .openai; c.openai = ProviderSettings(model: "ft:gpt-4o:acmecorp:bot:1"); return c }(),
            macOS: "26", architecture: "arm64", interfaceLanguage: "en", languagePacks: [], plugins: 0, extensions: 0))
        #expect(report.lines.contains("AI provider: openai (custom)") && !report.url.absoluteString.contains("acmecorp"))
        // A recorded action key keeps its name.
        var config = Config.default
        config.actionKey = .shortcut(KeyShortcut(keyCode: VirtualKey.returnKey, modifiers: .control, name: "⌃⏎"))
        let d = IssueReport.Diagnostics(config: config, macOS: "26", architecture: "arm64", interfaceLanguage: "en",
                                        languagePacks: [], plugins: 0, extensions: 0)
        #expect(d.actionKey == "⌃⏎")
    }

    // MARK: - The command

    func composer(_ key: ActionKey = .enter) -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: key)
        c.setInputMode(.english)
        c.issueDiagnostics = { diagnostics }
        return c
    }

    func type(_ s: String, _ c: Composer) {
        for ch in s { _ = c.handleKeyDown(ch == "@" ? at : ch == " " ? spaceKey : k(String(ch))) }
    }

    @Test func showsWhatGoesInThenOpensThePage() throws {
        #expect(Command.builtins.contains(.reportIssue) && Command.reportIssue.name == "reportissue" && Command.reportIssue.kind == .report)
        let c = composer()
        type("@reporti", c)
        _ = c.handleKeyDown(tab)
        #expect(c.draft == "@reportissue ")
        type("Crash @py on start", c)
        #expect(c.paletteQuery == nil)  // an "@" in the title is text
        // ⏎: the issue to confirm, nothing opened yet.
        let shown = c.handleKeyDown(enterKey)
        #expect(!shown.effects.contains { if case .openLink = $0 { return true } else { return false } })
        let issue = try #require(c.pendingIssue)
        #expect(c.phase == .choosing && issue.title == "Crash @py on start" && issue.lines == IssueReport(title: "", diagnostics: diagnostics).lines)
        #expect(c.choices == [Composer.Choice(label: "⏎", kind: .issue(issue.url), text: "Crash @py on start", isComplete: true)])
        // Space and digits don't open it.
        #expect(c.handleKeyDown(spaceKey).effects.isEmpty && c.handleKeyDown(k("1")).effects.isEmpty && c.phase == .choosing)
        // ⏎ opens it; nothing is inserted.
        let opened = c.handleKeyDown(enterKey).effects
        #expect(opened.contains(.openLink(issue.url)) && opened.contains(.commandUsed("reportissue")) && commits(opened).isEmpty)
        #expect(c.phase == .idle && c.draft.isEmpty && c.pendingIssue == nil)
    }

    @Test func escGoesBackAndNoTitleIsFine() {
        let c = composer()
        type("@reporti", c)
        _ = c.handleKeyDown(tab)
        _ = c.handleKeyDown(enterKey)  // no title: written on GitHub
        #expect(c.phase == .choosing && c.pendingIssue?.title == "" && query(c.pendingIssue!.url)["title"] == "")
        _ = c.handleKeyDown(escKey)
        #expect(c.phase == .drafting && c.draft == "@reportissue " && c.pendingIssue == nil)
        // ⏎ on the preview without a title opens the page all the same.
        _ = c.handleKeyDown(enterKey)
        let url = c.pendingIssue?.url
        let opened = c.handleKeyDown(enterKey).effects
        #expect(url != nil && opened.contains(.openLink(url!)) && c.phase == .idle && commits(opened).isEmpty)
    }

    /// Whether `effects` open the page.
    func opens(_ effects: [Composer.Effect]) -> Bool {
        effects.contains { if case .openLink = $0 { return true } else { return false } }
    }

    /// The action key, pressed: ⏎, a tap of left ⌥, or Space.
    func act(_ c: Composer) -> [Composer.Effect] {
        switch c.actionKey {
        case .optionTap:
            _ = c.handleFlagsChanged(keyCode: VirtualKey.leftOption, modifiers: [.option, .leftOption], timestamp: 10)
            return c.handleFlagsChanged(keyCode: VirtualKey.leftOption, modifiers: [], timestamp: 10.1)
        case .space: return c.handleKeyDown(spaceKey).effects
        default: return c.handleKeyDown(enterKey).effects
        }
    }

    @Test(arguments: [ActionKey.enter, .optionTap, .space])
    func withoutATitleEveryActionKeyOpensIt(_ key: ActionKey) {
        let c = composer(key)
        type("@reporti", c)
        _ = c.handleKeyDown(tab)
        #expect(c.draft == "@reportissue ")
        let shown = act(c)
        #expect(!opens(shown) && c.phase == .choosing && c.pendingIssue?.title == "", "\(key)")
        let opened = act(c)
        #expect(opens(opened) && opened.contains(.commandUsed("reportissue")) && c.phase == .idle && commits(opened).isEmpty, "\(key)")
    }

    @Test func withoutATitleAClickOpensIt() {
        let c = composer()
        type("@reporti", c)
        _ = c.handleKeyDown(tab)
        _ = c.handleKeyDown(enterKey)
        let url = c.pendingIssue?.url
        #expect(url != nil && c.choose(index: 0).contains(.openLink(url!)) && c.phase == .idle)
        // With a title too.
        type("@reporti", c)
        _ = c.handleKeyDown(tab)
        type("Typo", c)
        _ = c.handleKeyDown(enterKey)
        #expect(opens(c.choose(index: 0)))
    }

    @Test func notDuringSecureInput() {
        let c = composer()
        c.secureInputActive = { true }
        type("@reporti", c)
        _ = c.handleKeyDown(tab)
        type("secret", c)
        let refused = c.handleKeyDown(enterKey)
        #expect(refused.effects.contains(.notice(c.messages.secureInputCommand)) && !c.isLevelTwo && c.pendingIssue == nil)
    }
}
