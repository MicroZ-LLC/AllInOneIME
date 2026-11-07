import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// One @ (0.7.0), "Your own commands, plugins and script extensions" (owner, 2026-11-05). Started as today: `@name text`
/// works as it does for every kind (prompt, run, terminal, link, snippet), for plugins and script extensions; a
/// `suggestions` source is used by its prefix, unchanged, and is not in the @ list. Found without the name too: the
/// letters or words after the magic key also match, by a word's start and in any language, a command's summary (its
/// description in the list), a script extension's title and keywords (`ScriptCommand.searchTerms`) and a plugin's title;
/// by name first, then by those words. Offered as actions once used: a prompt command and a plugin that takes text the
/// user has used (`CommandUsage` > 0) are writing actions for a sentence and for a selection with the magic key alone,
/// after the rule rows, ordered by use in the app with Improve and Translate, at most 3 of the user's own (the rest by
/// name or summary); never one never used. Never guessed: `run`, `terminal`, `link`, snippets and script extensions are
/// offered only when the text matches their name, summary, title or keywords, never for an arbitrary sentence or
/// selection.
///
/// As `OneAtAcceptanceTests` does: through a field's session (`FakeHost`), typed as the user types it (Chinese as pinyin,
/// English with the input on English), the AI on the device (its stand-in `OneAtAcceptanceTests.Model` keeps each
/// request). What ⏎ on a row did is set against what the command typed by name does (`@formal text`, `@sig` …). A row is
/// told by the command name it shows (`kind`); its wording is otherwise free. A command is used as the user uses it: by
/// name, then ⏎, in a field of the app. The user's programs, terminal, browser, plugins and scripts are stand-ins that keep
/// what they were given. "A plugin's title" is read as what a plugin's list row shows next to its name, its manifest's
/// `summary` (a plugin has no other title).
@Suite(.serialized)
struct OneAtCustomCommandsAcceptanceTests {
    typealias Suite = OneAtCustomCommandsAcceptanceTests
    typealias Model = OneAtAcceptanceTests.Model

    // MARK: - Apps and texts

    static let editor = "com.example.editor"
    /// A chat app (`AppClass.chat`).
    static let slackApp = "com.tinyspeck.slackmacgap"

    /// The pinyin the stand-in engine composes, and its candidates (the first is what Space picks).
    static let pinyin: [String: [String]] = [
        "zhejiadiandecaihenhaochi": ["这家店的菜很好吃"],  // a statement in the user's language: Improve first
        "hongshaorouzenmezuo": ["红烧肉怎么做"],  // a question: Ask AI first
        "qianming": ["签名"],  // a word of sig's summary, 邮件签名
        "nihao": ["你好"],
    ]

    /// Selections in the user's language and in another.
    static let chineseSelection = "这个方案我觉得还可以"
    static let englishSelection = "Thank you for the gift"

    // MARK: - The user's own commands (README, "Your own commands")

    /// Prompt commands: AI instructions of the user's.
    static let formal = CustomCommand(name: "formal", type: .prompt, summary: "正式一点",
                                      prompt: "Rewrite the text in a formal tone.")
    static let polite = CustomCommand(name: "polite", type: .prompt, summary: "More polite", prompt: "Rewrite the text politely.")
    static let shorter = CustomCommand(name: "shorter", type: .prompt, summary: "Shorter", prompt: "Make the text shorter.")
    static let bullets = CustomCommand(name: "bullets", type: .prompt, summary: "As bullet points",
                                       prompt: "Rewrite the text as bullet points.")
    static let email = CustomCommand(name: "email", type: .prompt, summary: "Write an email", prompt: "Write the text as an email.")
    /// A prompt command never used.
    static let pirate = CustomCommand(name: "pirate", type: .prompt, summary: "Talk like a pirate",
                                      prompt: "Say it as a pirate would.")
    static let shout = CustomCommand(name: "shout", type: .run, summary: "Upper case", argv: ["/usr/bin/tr", "a-z", "A-Z"])
    static let sh = CustomCommand(name: "sh", type: .terminal, summary: "Shell", argv: ["zsh", "-c", "{input}"])
    static let google = CustomCommand(name: "google", type: .link, summary: "Search Google",
                                      url: "https://www.google.com/search?q={input}")
    /// A snippet, its summary in Chinese; `sigInEnglish` is the same one described in English.
    static let sig = CustomCommand(name: "sig", type: .snippet, summary: "邮件签名", text: "Best,\nWei\n{cursor}")
    static let sigInEnglish = CustomCommand(name: "sig", type: .snippet, summary: "Email signature", text: "Best,\nWei\n{cursor}")
    /// A snippet with the text typed after its name in it.
    static let greet = CustomCommand(name: "greet", type: .snippet, summary: "Greeting", text: "Hi {input}, thanks!")
    /// A suggestion source, used by its prefix "#".
    static let issues = CustomCommand(name: "issues", type: .suggestions, summary: "Our issues", argv: ["/Users/me/bin/gh-issues"],
                                      prefix: "#")

    static let commands = [formal, polite, shorter, bullets, email, pirate, shout, sh, google, sig, greet, issues]

    // MARK: - Plugins and a script extension

    static func plugin(_ name: String, _ type: PluginManifest.PluginType, title: LocalizedText, script: String? = nil,
                       prompt: String? = nil, url: String? = nil) -> InstalledPlugin {
        InstalledPlugin(manifest: PluginManifest(name: name, version: "1.0.0", minAppVersion: "0.5.0", type: type, summary: title,
                                                 script: script, prompt: prompt, url: url),
                        directory: URL(fileURLWithPath: "/tmp/stand-in-plugins/\(name)"), isLocal: true)
    }

    /// A prompt plugin (an AI instruction), titled "Cute faces".
    static let kaomoji = plugin("kaomoji", .prompt, title: LocalizedText(en: "Cute faces", zh: "颜文字"),
                                prompt: "Add a fitting kaomoji to the text.")
    /// A script plugin that takes text.
    static let wordcount = plugin("wordcount", .script, title: LocalizedText(en: "Count words", zh: "数字数"), script: "main.js")
    /// A link plugin.
    static let tweet = plugin("tweet", .link, title: LocalizedText(en: "Post to X", zh: "发到 X"),
                              url: "https://x.com/intent/post?text={input}")

    static let plugins = [kaomoji, wordcount, tweet]

    /// A script extension: found by "Convert Timestamp" and by "epoch" or "unix".
    static let tsconv = ScriptCommand(file: URL(fileURLWithPath: "/tmp/stand-in-scripts/tsconv.sh"), name: "tsconv",
                                      title: "Convert Timestamp", keywords: ["epoch", "unix"])

    // MARK: - Stand-ins

    /// The settings, what is kept between fields, and what reached outside them, for the fields made from it (`field`):
    /// Chinese the main input language, then English; English, then Chinese, the output languages; the AI on the device;
    /// the user's commands, plugins and script extensions.
    final class World: @unchecked Sendable {
        var config: Config
        let plugins: [InstalledPlugin]
        let extensions: ExtensionIndex
        /// The command usage as kept (`SessionServices.loadCommandUsage`, `saveCommandUsage`).
        let usage = Locked(initialState: CommandUsage())
        /// What the user's programs, terminal, plugins and scripts were given: "shout hello", "terminal zsh -c ls",
        /// "wordcount hello", "tsconv 1700000000".
        let ran = Locked<[String]>(initialState: [])
        private let models = Locked<[Model]>(initialState: [])

        init(commands: [CustomCommand] = Suite.commands, plugins: [InstalledPlugin] = Suite.plugins,
             scripts: [ScriptCommand] = [Suite.tsconv]) {
            config = .default
            config.uiLanguage = "en"
            config.setOrder([Language.chinese, .english])
            config.setOrder([OutputLanguage.english, .chinese])
            config.provider = .apple
            config.claudeInBackground = false
            config.customCommands = commands
            self.plugins = plugins
            extensions = ExtensionIndex(commands: scripts)
        }

        var trigger: String { config.commandTrigger }
        /// What every field's model was sent.
        var requests: [AppleModelRequest] { models.withLock { $0.flatMap(\.requests) } }
        var runs: [String] { ran.withLock { $0 } }

        /// Whether `name` counts as used (`CommandUsage` > 0).
        func used(_ name: String) -> Bool { usage.withLock { $0 }.score(name) > 0 }

        /// A new field of `app` that has the focus, the input on English or Chinese, `selected` its text, all selected.
        func field(app: String = Suite.editor, english: Bool = false, selected: String? = nil) -> Field {
            let field = Field(self, app: app, english: english, selected: selected)
            models.withLock { $0.append(field.model) }
            return field
        }

        /// What reached the AI when `keys` were typed in a new field, then ⏎ (nil: nothing).
        func sent(app: String = Suite.editor, english: Bool = false, selected: String? = nil,
                  _ keys: (Field) -> Void) -> AppleModelRequest? {
            let field = self.field(app: app, english: english, selected: selected)
            keys(field)
            return field.returnSends()
        }

        /// A command used as the user uses it, `times` times: `typed` (its name, then its text) in a new field of `app`,
        /// the input on English, then ⏎, until what it does is done.
        func use(_ typed: String, app: String = Suite.editor, times: Int = 1) {
            for _ in 0..<times {
                let field = self.field(app: app, english: true)
                let before = runs.count
                field.type(typed)
                field.press(FakeHost.enter)
                field.host.settle(timeout: 5) {
                    !field.model.requests.isEmpty || self.runs.count > before || !field.host.opened.isEmpty
                        || !field.host.document.isEmpty
                }
            }
        }
    }

    final class Field {
        let host: FakeHost
        let model: Model
        let world: World
        let selected: String?

        init(_ world: World, app: String, english: Bool, selected: String?) {
            let (model, engine, fixed, extensions) = (Model(), FakeEngine(), world.config, world.extensions)
            engine.dictionary.merge(Suite.pinyin) { $1 }
            var services = SessionServices(converter: Converter(loadConfig: { fixed }, loadJargon: { _ in [] }, appleModel: model),
                                           loadSettings: { fixed })
            services.levelOne = { .engine(engine) }
            services.programInstalled = { _ in true }
            services.loadCommandUsage = { world.usage.withLock { $0 } }
            services.saveCommandUsage = { usage in world.usage.withLock { $0 = usage } }
            services.plugins = { _ in world.plugins }
            services.loadExtensions = { _, _ in extensions }
            services.runProgram = { command, input in
                world.ran.withLock { $0.append("\(command.name) \(input)") }
                return OneAtAcceptanceTests.printing(input.uppercased())
            }
            services.launchInTerminal = { argv in world.ran.withLock { $0.append((["terminal"] + argv).joined(separator: " ")) } }
            services.runPlugin = { plugin, input, _ in
                world.ran.withLock { $0.append("\(plugin.name) \(input)") }
                return OneAtAcceptanceTests.printing(input.uppercased())
            }
            services.startScript = { script, arguments, _, event in
                world.ran.withLock { $0.append(([script.name] + arguments).joined(separator: " ")) }
                event(.update(CommandRunner.ScriptUpdate(output: .text("2023-11-14"), text: "2023-11-14", isFinal: true)))
                return 1
            }
            host = FakeHost(services: services)
            (self.model, self.world, self.selected) = (model, world, selected)
            host.app = app
            if let selected {
                host.document = selected
                host.selection = 0..<(selected as NSString).length
            }
            host.focus()
            if english { host.composer.setInputMode(.english) }
        }

        /// The rows for the text: the panel's, without the pinyin candidates shown with them while composing.
        var rows: [PanelModel.Row] {
            let candidates = Set(host.composer.engineState.isComposing ? host.composer.engineState.candidates.map(\.text) : [])
            return (host.panel?.rows ?? []).filter { !candidates.contains($0.text) }
        }
        /// What each row is (`Suite.kind`).
        var kinds: [String] { rows.map(Suite.kind) }
        var texts: [String] { rows.map { $0.comment.isEmpty ? $0.text : "\($0.text) | \($0.comment)" } }

        func type(_ text: String) { host.type(text) }
        func press(_ key: KeyEvent) { host.press(key) }

        /// Pinyin, then Space: its first candidate.
        func write(pinyin letters: String) {
            host.type(letters)
            host.press(FakeHost.space)
        }

        /// The magic key, a command's full name and Tab: "@name ", as the command list picks it.
        func pick(_ name: String) {
            host.type(world.trigger + name)
            host.press(FakeHost.tab)
        }

        /// A row of `kind` is there, neither the first (the rule row) nor the last (Ask AI).
        func isBetweenTheFirstAndLastRows(_ kind: String) -> Bool {
            let kinds = self.kinds
            return kinds.firstIndex(of: kind).map { $0 > 0 && $0 < kinds.count - 1 } == true
        }

        /// ↓ from the first row to the first one of `kind`: whether it is highlighted (false: there's none).
        @discardableResult
        func highlight(_ kind: String) -> Bool {
            guard let index = host.panel?.rows.firstIndex(where: { Suite.kind(of: $0) == kind }) else { return false }
            for _ in 0..<20 where host.panel?.highlighted != index { host.press(FakeHost.down) }
            return host.panel?.highlighted == index
        }

        /// ⏎, and what reached the AI for it (nil: nothing within five seconds).
        func returnSends() -> AppleModelRequest? {
            host.press(FakeHost.enter)
            host.settle(timeout: 5) { !model.requests.isEmpty }
            return model.requests.first
        }
    }

    /// The names a row can show: the built-in commands', `@edit`'s, the user's own, the plugins' and the script
    /// extension's.
    static let names = Command.builtins.map(\.name) + [Command.edit.name] + commands.map(\.name) + plugins.map(\.name)
        + [tsconv.name]

    /// What a row is: the command whose name it shows: the name itself (a command list's row), or the name after a magic
    /// key, in its text or else its comment ("@formal"); else its text.
    static func kind(of row: PanelModel.Row) -> String {
        for part in [row.text, row.comment] {
            let bare = part.trimmingCharacters(in: .whitespaces)
            if names.contains(bare) { return bare }
            let characters = Array(part)
            for (index, character) in characters.enumerated() where character == "@" || character == "~" {
                let name = String(characters[(index + 1)...].prefix { $0.isASCII && ($0.isLetter || $0.isNumber) })
                if names.contains(name) { return name }
            }
        }
        return row.text
    }

    // MARK: - The magic key alone includes the user's commands

    /// Picking a custom command from the unfiltered list, then giving it text, does exactly what its
    /// name and text do for run, terminal and prompt commands.
    @Test func loneMagicKeyPicksCustomCommandsAndTheirTextRunsAsByName() async {
        await inEnglish {
            for trigger in ["@", "~"] {
                for english in [false, true] {
                    for name in ["shout", "sh", "formal"] {
                        let world = World()
                        world.config.commandTrigger = trigger
                        world.usage.withLock { usage in
                            for _ in 0..<5 { usage.record(name, in: Suite.editor) }
                        }
                        let picked = world.field(english: english)
                        picked.type(trigger)
                        #expect(picked.kinds.first == name, "\(trigger), \(name), English \(english): \(picked.texts)")
                        picked.press(FakeHost.enter)
                        let chosen = picked.host.composer.draftCommand?.name == name
                        #expect(chosen && world.runs.isEmpty && world.requests.isEmpty,
                                "\(trigger), \(name): \(picked.host.composer.draft)")
                        guard chosen else { continue }
                        if english { picked.type("hello") } else { picked.write(pinyin: "nihao") }
                        picked.press(FakeHost.enter)
                        let input = english ? "hello" : "你好"
                        if name == "formal" {
                            #expect(picked.host.settle(timeout: 5) { !picked.model.requests.isEmpty })
                        } else {
                            #expect(picked.host.settle(timeout: 5) { world.runs.count == 1 }, "\(world.runs)")
                        }
                        let byName = world.field(english: english)
                        byName.type(trigger + name + " ")
                        if english { byName.type("hello") } else { byName.write(pinyin: "nihao") }
                        byName.press(FakeHost.enter)
                        if name == "formal" {
                            #expect(byName.host.settle(timeout: 5) { !byName.model.requests.isEmpty })
                            #expect(picked.model.requests.first == byName.model.requests.first,
                                    "\(trigger), \(name): \(world.requests.map(\.prompt))")
                        } else {
                            #expect(byName.host.settle(timeout: 5) { world.runs.count == 2 }, "\(world.runs)")
                            if world.runs.count == 2 {
                                #expect(world.runs[0] == world.runs[1] && world.runs[0].contains(input),
                                        "\(trigger), \(name): \(world.runs)")
                            }
                        }
                    }
                }
            }
        }
    }

    /// A no-input snippet runs on the first Return. Plugins and script extensions are in the same
    /// unfiltered command list and can be picked with Down and Return.
    @Test func loneMagicKeyListsNoInputCommandsPluginsAndScriptExtensions() async {
        await inEnglish {
            for trigger in ["@", "~"] {
                for english in [false, true] {
                    let world = World()
                    world.config.commandTrigger = trigger
                    world.usage.withLock { usage in
                        for _ in 0..<6 { usage.record("sig", in: Suite.editor) }
                        for _ in 0..<5 { usage.record("kaomoji", in: Suite.editor) }
                        for _ in 0..<4 { usage.record("tsconv", in: Suite.editor) }
                    }
                    let snippet = world.field(english: english)
                    snippet.type(trigger)
                    #expect(snippet.kinds.prefix(3).elementsEqual(["sig", "kaomoji", "tsconv"]),
                            "\(trigger), English \(english): \(snippet.texts)")
                    snippet.press(FakeHost.enter)
                    #expect(snippet.host.document == "Best,\nWei\n" && world.runs.isEmpty && world.requests.isEmpty,
                            "\(snippet.host.document.debugDescription)")

                    let plugin = world.field(english: english)
                    plugin.type(trigger)
                    plugin.press(FakeHost.down)
                    plugin.press(FakeHost.enter)
                    #expect(plugin.host.composer.draftCommand?.name == "kaomoji" && world.requests.isEmpty,
                            "\(plugin.host.composer.draft)")

                    let script = world.field(english: english)
                    script.type(trigger)
                    script.press(FakeHost.down)
                    script.press(FakeHost.down)
                    script.press(FakeHost.enter)
                    #expect(script.host.composer.draftCommand?.name == "tsconv" && world.runs.isEmpty,
                            "\(script.host.composer.draft)")
                }
            }
        }
    }

    /// The request asks the AI to do `instruction` (the command's prompt) with `text`.
    static func asks(_ request: AppleModelRequest?, _ instruction: String?, about text: String) -> Bool {
        guard let request, let instruction else { return false }
        return (request.instructions + request.prompt).contains(instruction) && request.prompt.contains(text)
    }

    func inEnglish(_ body: () throws -> Void) async rethrows { try await withInterfaceLanguage("en", body) }

    // MARK: - Started as today

    /// `@name text`, ⏎, for each kind: a prompt command's instruction and the text reach the AI; a `run` command's program
    /// gets the text; a `terminal` command's runs in a terminal with it; a `link` command opens its address with the text
    /// in it; a snippet goes in (with the text where it says `{input}`).
    @Test func eachKindIsStillStartedByItsNameThenItsText() async {
        await inEnglish {
            let world = World()
            let formal = world.field(english: true)
            formal.type("@formal thank you for the gift")
            let sent = formal.returnSends()
            #expect(formal.host.composer.activeCommand?.name == "formal", "\(String(describing: formal.host.composer.activeCommand))")
            #expect(Suite.asks(sent, Suite.formal.prompt, about: "thank you for the gift"), "\(String(describing: sent))")
            let shout = world.field(english: true)
            shout.type("@shout hello")
            shout.press(FakeHost.enter)
            #expect(shout.host.settle(timeout: 5) { world.runs == ["shout hello"] }, "\(world.runs)")
            let sh = world.field(english: true)
            sh.type("@sh ls -la")
            sh.press(FakeHost.enter)
            #expect(sh.host.settle(timeout: 5) { world.runs.last == "terminal zsh -c ls -la" }, "\(world.runs)")
            let google = world.field(english: true)
            google.type("@google swift testing")
            google.press(FakeHost.enter)
            let address = LinkTemplate.url(Suite.google.url ?? "", input: "swift testing")?.absoluteString
            #expect(address != nil && google.host.settle(timeout: 5) { google.host.opened == [address ?? ""] },
                    "\(google.host.opened)")
            let sig = world.field(english: true)
            sig.type("@sig")
            sig.press(FakeHost.enter)
            #expect(sig.host.document == "Best,\nWei\n", "\(sig.host.document.debugDescription)")
            let greet = world.field(english: true)
            greet.type("@greet Ann")
            greet.press(FakeHost.enter)
            #expect(greet.host.document == "Hi Ann, thanks!", "\(greet.host.document.debugDescription)")
            #expect(world.requests.count == 1, "only the prompt command reached the AI: \(world.requests.map(\.prompt))")
        }
    }

    /// `@name text`, ⏎, for a prompt plugin (its instruction and the text reach the AI), a script plugin (its script gets
    /// the text), a link plugin (its address opens with the text) and a script extension (it runs with the text).
    @Test func pluginsAndScriptExtensionsAreStillStartedByTheirNameThenTheirText() async {
        await inEnglish {
            let world = World()
            let kaomoji = world.field(english: true)
            kaomoji.type("@kaomoji so happy today")
            let sent = kaomoji.returnSends()
            #expect(Suite.asks(sent, Suite.kaomoji.manifest.prompt, about: "so happy today"), "\(String(describing: sent))")
            let wordcount = world.field(english: true)
            wordcount.type("@wordcount hello world")
            wordcount.press(FakeHost.enter)
            #expect(wordcount.host.settle(timeout: 5) { world.runs == ["wordcount hello world"] }, "\(world.runs)")
            let tweet = world.field(english: true)
            tweet.type("@tweet hello")
            tweet.press(FakeHost.enter)
            let address = LinkTemplate.url(Suite.tweet.manifest.url ?? "", input: "hello")?.absoluteString
            #expect(address != nil && tweet.host.settle(timeout: 5) { tweet.host.opened == [address ?? ""] }, "\(tweet.host.opened)")
            let script = world.field(english: true)
            script.type("@tsconv 1700000000")
            script.press(FakeHost.enter)
            #expect(script.host.settle(timeout: 5) { world.runs.last == "tsconv 1700000000" }, "\(world.runs)")
        }
    }

    // MARK: - Found without the name

    /// `@签名`, typed as pinyin: sig, whose summary is "邮件签名", is listed; ⏎ on it does what `@sig` ⏎ does (its text
    /// goes in, in place of what was typed).
    @Test func aCommandIsFoundByAWordOfItsSummaryInChinese() async {
        await inEnglish {
            let world = World()
            let field = world.field()
            field.type("@")
            field.write(pinyin: "qianming")
            #expect(field.kinds.contains("sig"), "\(field.texts)")
            #expect(field.highlight("sig"), "\(field.texts)")
            field.press(FakeHost.enter)
            let named = world.field(english: true)
            named.type("@sig")
            named.press(FakeHost.enter)
            #expect(!named.host.document.isEmpty && field.host.document == named.host.document,
                    "\(field.host.document.debugDescription) / \(named.host.document.debugDescription)")
        }
    }

    /// `@email`: sig, whose summary is "Email signature", is listed (no command is named so); ⏎ on it does what `@sig` ⏎
    /// does.
    @Test func aCommandIsFoundByAWordOfItsSummaryInEnglish() async {
        await inEnglish {
            let world = World(commands: [Suite.shout, Suite.sigInEnglish])
            let field = world.field(english: true)
            field.type("@email")
            #expect(field.kinds.contains("sig"), "\(field.texts)")
            #expect(field.highlight("sig"), "\(field.texts)")
            field.press(FakeHost.enter)
            let named = world.field(english: true)
            named.type("@sig")
            named.press(FakeHost.enter)
            #expect(!named.host.document.isEmpty && field.host.document == named.host.document,
                    "\(field.host.document.debugDescription) / \(named.host.document.debugDescription)")
        }
    }

    /// `@ema`: email (its name starts so) is listed before sig (a word of its summary, "Email signature", does), though
    /// sig comes first in the config and is the one used.
    @Test func nameMatchesComeBeforeSummaryMatches() async {
        await inEnglish {
            let world = World(commands: [Suite.sigInEnglish, Suite.email])
            world.use("@sig", times: 3)
            #expect(world.used("sig"))
            let field = world.field(english: true)
            field.type("@ema")
            let (email, sig) = (field.kinds.firstIndex(of: "email"), field.kinds.firstIndex(of: "sig"))
            #expect(email.flatMap { email in sig.map { email < $0 } } == true, "\(field.texts)")
        }
    }

    /// "Convert Timestamp", keywords "epoch" and "unix": `@timest`, `@epoch`, `@unix` list tsconv; ⏎ on it picks it, as
    /// the command list does (it needs its text: nothing is run yet).
    @Test func aScriptExtensionIsFoundByItsTitleAndKeywords() async {
        await inEnglish {
            let world = World()
            for typed in ["@timest", "@epoch", "@unix"] {
                let field = world.field(english: true)
                field.type(typed)
                #expect(field.kinds.contains("tsconv"), "\(typed): \(field.texts)")
                #expect(field.highlight("tsconv"), "\(typed): \(field.texts)")
                field.press(FakeHost.enter)
                #expect(field.host.composer.draftCommand?.name == "tsconv", "\(typed): \(field.host.composer.draft)")
            }
            #expect(world.runs.isEmpty, "\(world.runs)")
        }
    }

    /// The prompt plugin titled "Cute faces": `@cute`, `@faces` list kaomoji; ⏎ on it picks it, as the command list does.
    @Test func aPluginIsFoundByItsTitle() async {
        await inEnglish {
            let world = World()
            for typed in ["@cute", "@faces"] {
                let field = world.field(english: true)
                field.type(typed)
                #expect(field.kinds.contains("kaomoji"), "\(typed): \(field.texts)")
                #expect(field.highlight("kaomoji"), "\(typed): \(field.texts)")
                field.press(FakeHost.enter)
                #expect(field.host.composer.draftCommand?.name == "kaomoji", "\(typed): \(field.host.composer.draft)")
            }
            #expect(world.requests.isEmpty, "\(world.requests.map(\.prompt))")
        }
    }

    // MARK: - Offered as actions once used

    /// `@formal` used twice in the editor: for a sentence there, a row after the rule row (Improve, for a statement in the
    /// user's language) and before Ask AI, the last; ⏎ on it sends what `@formal` with the sentence sends. `@pirate`,
    /// never used, isn't there.
    @Test func aUsedPromptCommandIsAWritingActionForASentence() async {
        await inEnglish {
            let world = World()
            world.use("@formal thank you", times: 2)
            #expect(world.used("formal") && !world.used("pirate"))
            let field = world.field()
            field.type("@")
            field.write(pinyin: "zhejiadiandecaihenhaochi")
            let kinds = field.kinds
            #expect(kinds.first == "improve" && kinds.last == "question", "\(field.texts)")
            #expect(field.isBetweenTheFirstAndLastRows("formal"), "\(field.texts)")
            #expect(!kinds.contains("pirate"), "\(field.texts)")
            #expect(field.highlight("formal"), "\(field.texts)")
            let sent = field.returnSends()
            let formal = world.sent { $0.pick("formal"); $0.write(pinyin: "zhejiadiandecaihenhaochi") }
            #expect(formal != nil && sent == formal, "\(String(describing: sent?.prompt)) / \(String(describing: formal?.prompt))")
        }
    }

    /// `@formal` used twice in the editor: with a selection and the magic key alone there, a row after the rule row
    /// (Improve, for a selection in the user's language) and before Ask AI about it, the last; ⏎ on it sends what
    /// `@formal` on the selection sends, nothing replaced yet. `@pirate`, never used, isn't there.
    @Test func aUsedPromptCommandIsAWritingActionForASelection() async {
        await inEnglish {
            let world = World()
            world.use("@formal thank you", times: 2)
            let text = Suite.chineseSelection
            let field = world.field(selected: text)
            field.type("@")
            let kinds = field.kinds
            #expect(kinds.first == "improve" && kinds.last == "question", "\(field.texts)")
            #expect(field.isBetweenTheFirstAndLastRows("formal"), "\(field.texts)")
            #expect(!kinds.contains("pirate"), "\(field.texts)")
            #expect(field.highlight("formal"), "\(field.texts)")
            let sent = field.returnSends()
            let formal = world.sent(selected: text) { $0.pick("formal") }
            #expect(formal != nil && sent == formal, "\(String(describing: sent?.prompt)) / \(String(describing: formal?.prompt))")
            #expect(field.host.document == text, "nothing replaced yet")
        }
    }

    /// In the editor Translate was used 3 times and `@formal` twice; in Slack `@polite` 3 times and Improve twice. For a
    /// question (Ask AI first, the rule row) the writing actions come by use in its app: Translate then formal in the
    /// editor, polite then Improve in Slack; for a selection in the editor, Translate before formal.
    @Test func theUsersOwnAreOrderedByUseInThisAppWithImproveAndTranslate() async {
        await inEnglish {
            let world = World()
            world.use("@translate thank you", times: 3)
            world.use("@formal thank you", times: 2)
            world.use("@polite thank you", app: Suite.slackApp, times: 3)
            world.use("@improve thank you", app: Suite.slackApp, times: 2)
            let writing: Set<String> = ["improve", "translate", "formal", "polite"]
            func order(in app: String) -> [String] {
                let field = world.field(app: app)
                field.type("@")
                field.write(pinyin: "hongshaorouzenmezuo")
                #expect(field.kinds.first == "question", "\(app): \(field.texts)")
                return field.kinds.dropFirst().filter(writing.contains)
            }
            let editor = order(in: Suite.editor), slack = order(in: Suite.slackApp)
            #expect(Array(editor.prefix(2)) == ["translate", "formal"], "the editor: \(editor)")
            #expect(Array(slack.prefix(2)) == ["polite", "improve"], "Slack: \(slack)")
            let selected = world.field(selected: Suite.chineseSelection)
            selected.type("@")
            #expect(selected.kinds.filter { $0 == "translate" || $0 == "formal" } == ["translate", "formal"], "\(selected.texts)")
        }
    }

    /// Four prompt commands used in the editor (formal 4 times, polite 3, shorter 2, bullets once): for a sentence and for
    /// a selection, the 3 used most are there, by use; bullets isn't, and is found by its name (`@bul`) or a word of its
    /// summary (`@points`). Neither is pirate, never used.
    @Test func atMostThreeOfTheUsersOwnAreAmongTheWritingActions() async {
        await inEnglish {
            let world = World()
            world.use("@formal thank you", times: 4)
            world.use("@polite thank you", times: 3)
            world.use("@shorter thank you", times: 2)
            world.use("@bullets thank you", times: 1)
            #expect(["formal", "polite", "shorter", "bullets"].allSatisfy(world.used))
            let own: Set<String> = Set(Suite.commands.filter { $0.type == .prompt }.map(\.name))
            let sentence = world.field()
            sentence.type("@")
            sentence.write(pinyin: "zhejiadiandecaihenhaochi")
            #expect(sentence.kinds.filter(own.contains) == ["formal", "polite", "shorter"], "\(sentence.texts)")
            let selected = world.field(selected: Suite.chineseSelection)
            selected.type("@")
            #expect(selected.kinds.filter(own.contains) == ["formal", "polite", "shorter"], "\(selected.texts)")
            let named = world.field(english: true)
            named.type("@bul")
            #expect(named.kinds.first == "bullets", "\(named.texts)")
            let described = world.field(english: true)
            described.type("@points")
            #expect(described.kinds.contains("bullets"), "\(described.texts)")
        }
    }

    /// The prompt plugin used twice in the editor: for a sentence and for a selection there, a row after the rule row and
    /// before Ask AI; ⏎ on it sends what `@kaomoji` with the sentence sends. The script plugin, never used, isn't there.
    @Test func aUsedPluginThatTakesTextIsAWritingActionToo() async {
        await inEnglish {
            let world = World()
            world.use("@kaomoji thank you", times: 2)
            #expect(world.used("kaomoji") && !world.used("wordcount"))
            let field = world.field()
            field.type("@")
            field.write(pinyin: "zhejiadiandecaihenhaochi")
            #expect(field.isBetweenTheFirstAndLastRows("kaomoji") && !field.kinds.contains("wordcount"), "\(field.texts)")
            #expect(field.highlight("kaomoji"), "\(field.texts)")
            let sent = field.returnSends()
            let kaomoji = world.sent { $0.pick("kaomoji"); $0.write(pinyin: "zhejiadiandecaihenhaochi") }
            #expect(kaomoji != nil && sent == kaomoji, "\(String(describing: sent?.prompt)) / \(String(describing: kaomoji?.prompt))")
            let selected = world.field(selected: Suite.chineseSelection)
            selected.type("@")
            #expect(selected.isBetweenTheFirstAndLastRows("kaomoji") && !selected.kinds.contains("wordcount"), "\(selected.texts)")
        }
    }

    // MARK: - Never guessed

    /// A `run`, `terminal`, `link` command, the snippets and the script extension, each used twice: never a row for a
    /// sentence (a statement, a question, English) or a selection (in the editor, in Slack), however used; only text
    /// matching one lists it (`@upper`, shout's summary; `@epoch`, tsconv's keyword).
    @Test func programsLinksSnippetsAndScriptExtensionsAreNeverGuessed() async {
        await inEnglish {
            let world = World()
            world.use("@shout hello", times: 2)
            world.use("@sh ls", times: 2)
            world.use("@google swift", times: 2)
            world.use("@sig", times: 2)
            world.use("@greet Ann", times: 2)
            world.use("@tsconv 1700000000", times: 2)
            let never = ["shout", "sh", "google", "sig", "greet", "tsconv"]
            for name in never { #expect(world.used(name), "\(name) was used") }
            let typed: [(String, (Field) -> Void, World.FieldKind)] = [
                ("a statement", { $0.type("@"); $0.write(pinyin: "zhejiadiandecaihenhaochi") }, .chinese),
                ("a question", { $0.type("@"); $0.write(pinyin: "hongshaorouzenmezuo") }, .chinese),
                ("English", { $0.type("@thank you for the gift") }, .english),
                ("a selection", { $0.type("@") }, .selected(Suite.chineseSelection, Suite.editor)),
                ("a selection in English", { $0.type("@") }, .selected(Suite.englishSelection, Suite.editor)),
                ("a selection in Slack", { $0.type("@") }, .selected(Suite.chineseSelection, Suite.slackApp)),
            ]
            for (what, keys, kind) in typed {
                let field = world.field(kind)
                keys(field)
                #expect(!field.rows.isEmpty && Set(never).isDisjoint(with: field.kinds), "\(what): \(field.texts)")
            }
            let upper = world.field(english: true)
            upper.type("@upper")
            #expect(upper.kinds.contains("shout"), "\(upper.texts)")
            let epoch = world.field(english: true)
            epoch.type("@epoch")
            #expect(epoch.kinds.contains("tsconv"), "\(epoch.texts)")
        }
    }

    // MARK: - A suggestions source

    /// The source "issues" (summary "Our issues", prefix "#") is no @ command: `@iss`, `@issues`, `@our` don't list it.
    @Test func aSuggestionsSourceIsNotInTheAtList() async {
        await inEnglish {
            let world = World()
            for typed in ["@iss", "@issues", "@our"] {
                let field = world.field(english: true)
                field.type(typed)
                #expect(!field.kinds.contains("issues") && !field.texts.contains { $0.contains("Our issues") },
                        "\(typed): \(field.texts)")
                #expect(!field.host.composer.paletteMatches.contains { $0.name == "issues" }, "\(typed)")
            }
        }
    }

    /// The user's program for "issues": its list, two issues.
    final class IssuesProgram: CommandCompletionRuntime, @unchecked Sendable {
        private let lists = Locked(initialState: 0)
        var listed: Int { lists.withLock { $0 } }

        func list(_ command: CustomCommand) async throws -> Data {
            lists.withLock { $0 += 1 }
            return Data("#12\tFix login\n#17\tDark mode\n".utf8)
        }

        func query(_ text: String, _ command: CustomCommand) async throws -> Data { Data() }
    }

    /// The same settings in a Suggestions field (`SuggestionsWorld`): "#1" shows the source's rows, as before.
    @Test(SuggestionsOneAtATime()) func aSuggestionsSourceIsStillUsedByItsPrefix() async {
        await inEnglish {
            let program = IssuesProgram()
            let world = SuggestionsWorld()
            world.config.customCommands = Suite.commands
            world.switches = world.config.suggestionsSettings()
            let field = world.field { $0.suggestions.commandRuntime = program }
            #expect(field.settle { program.listed > 0 }, "its list, at the focus")
            field.type("#1")
            #expect(field.settle { field.rows.map(\.text) == ["#12", "#17"] }, "\(field.rows.map(\.text))")
        }
    }
}

extension OneAtCustomCommandsAcceptanceTests.World {
    /// The field a text is typed in: the input on Chinese or English, or a selection in an app.
    enum FieldKind {
        case chinese, english
        case selected(String, String)
    }

    func field(_ kind: FieldKind) -> OneAtCustomCommandsAcceptanceTests.Field {
        switch kind {
        case .chinese: return field()
        case .english: return field(english: true)
        case let .selected(text, app): return field(app: app, selected: text)
        }
    }
}
