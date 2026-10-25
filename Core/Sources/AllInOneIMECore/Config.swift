import Foundation

/// User-editable settings stored as JSON at `~/.config/allinoneime/config.json`.
/// Every key is optional in the file; missing keys fall back to `Config.default`. Keys of older
/// versions that are gone are ignored, and not written back.
public struct Config: Codable, Equatable, Sendable {
    /// Where requests go: Amazon Bedrock (the settings below), or an API-key provider with its own
    /// settings (`anthropic`, `gemini`, `openai`).
    public var provider: Provider
    /// Profile name in ~/.aws/credentials (static access keys).
    public var awsProfile: String
    /// Bedrock region. `nil` means: use the profile's region from ~/.aws/config, else us-east-1.
    public var region: String?
    /// Bedrock model or inference-profile ID used with the Converse API.
    public var modelId: String
    /// The Claude API, the Gemini API and an OpenAI-compatible API (the key is in `APIKeys`).
    public var anthropic: ProviderSettings
    public var gemini: ProviderSettings
    public var openai: ProviderSettings
    public var maxTokens: Int
    /// `nil` omits the field (some models on Bedrock reject `temperature`).
    public var temperature: Double?
    /// Network idle timeout for one conversion request.
    public var timeoutSeconds: Double
    /// Rewrite presets offered after the three main versions, in this order (names from
    /// `RewriteStyle.catalog`, e.g. "润色" polish, "简洁" concise, "正式" formal); empty = main versions only.
    /// Rewrites are in the language the sentence was typed in.
    public var rewriteStyles: [String]
    /// Language of the three main versions (1–3): a sentence in another language is translated,
    /// one already in this language is polished. Always the first of `outputLanguages`.
    public var outputLanguage: OutputLanguage
    /// The output languages the user added, in the user's order (dragged in the settings); the first
    /// is the one in use. A new user has one.
    public var outputLanguages: [OutputLanguage]
    /// The input languages added, in the user's order: pinyin (Chinese), English letters, or both
    /// (Shift switches). The first is the default. A new user has English only; with one, Shift doesn't switch.
    public var inputLanguages: [Language]
    /// The keyboard layout `language` types with: the one picked for it, else its default (nil: the system's).
    public func keyboardLayout(for language: Language) -> String? {
        keyboardLayouts[language.rawValue] ?? language.defaultKeyboardLayout
    }

    /// The language `text` is written in (`Language.of`): French only for someone who types it.
    public func language(of text: String) -> Language { Language.of(text, french: inputLanguages.contains(.french)) }

    /// Whether what is typed has a language to be translated into: an output language other than one of the input
    /// languages (text already in the language goes in as it is). A new user whose Mac has English alone has none until
    /// one is added: English typed, English out.
    public var hasLanguageToTranslateInto: Bool {
        outputLanguages.contains { output in inputLanguages.contains { !$0.matches(output) } }
    }

    /// The Code input (decision 22): the coding language whose pack its rows come from ("python",
    /// `CodingLanguagePack.offered`); nil: no Code input. It comes after the input languages, a tap of Shift away from the
    /// last, and is never one of them (`inputs`). Synced with them.
    public var codingLanguage: String? {
        didSet { if let codingLanguage, !CodingLanguagePack.isLanguage(codingLanguage) { self.codingLanguage = nil } }
    }

    /// The inputs a tap of Shift goes through, in order: the input languages, then Code.
    public var inputs: [Input] { inputLanguages.map(Input.language) + (codingLanguage == nil ? [] : [.code]) }

    /// At least one input language, at most this many.
    public static let maxInputLanguages = 5
    /// Mode a new text field starts in: pinyin (Chinese) or English letters. Always the first of `inputLanguages`.
    public var defaultInput: Language
    /// `@improve` also translates, as `@translate @improve` (one request with both).
    public var improveTranslates: Bool
    /// Hold the right Option key to dictate (on-device speech recognition): the text is inserted, or
    /// added to the @ command being written.
    public var voiceInput: Bool
    /// The user's own jargon list for the jargon (黑话) style (see `JargonLibrary`); nil = the default file.
    public var jargonFile: String?
    /// The key that runs the @ command at the start of the draft.
    public var actionKey: ActionKey
    /// One printable symbol that starts a command. Older config files use @. One that can't be
    /// (`commandTriggerProblem`) is @.
    public var commandTrigger: String = "@" {
        didSet { commandTrigger = Self.validCommandTrigger(commandTrigger) ? commandTrigger : "@" }
    }
    public static func validCommandTrigger(_ value: String) -> Bool { commandTriggerProblem(value) == nil }

    /// Why `value` can't be the command trigger; nil when it can. It opens the command list where a sentence starts, after
    /// a space and after Chinese, and goes in as itself when no command follows: one ASCII symbol, and not one typing
    /// needs there (`typingSymbols`).
    public static func commandTriggerProblem(_ value: String) -> CommandTriggerProblem? {
        guard value.unicodeScalars.count == 1, let scalar = value.unicodeScalars.first, (33...126).contains(scalar.value),
              !CharacterSet.alphanumerics.contains(scalar) else { return .notASymbol }
        return typingSymbols.contains(Character(value)) ? .typingSymbol(value) : nil
    }

    /// The ASCII symbols typing needs, which the command trigger would take from it: pinyin's (rime-ice's): ' between
    /// syllables, ` its lookup key (`speller/alphabet`, `key_binder/search`), - and = turning the candidates' pages,
    /// [ and ] picking a word's first or last character (`key_binder`), , . : held after a digit
    /// (`punctuator/digit_separators`); and every symbol its punctuation types as Chinese (`punctuator/half_shape`:
    /// ，。；：？！“”‘’、（）《》【】「」…… —— · ¥), and /. What is left types as itself in every mode (`commandTriggers`).
    /// The macOS shell's Rime tests (CommandTriggerSymbolsTests) check them against rime-ice as it is deployed.
    public static let typingSymbols: Set<Character> = [
        "'", "`", "-", "=", "[", "]", ",", ".", ":", ";", "/", "\\", "?", "!", "\"", "(", ")", "<", ">", "{", "}", "^", "_", "$",
    ]

    /// Every symbol the command trigger can be, in ASCII order: # % & * + @ | ~.
    public static var commandTriggers: [String] {
        (33...126).compactMap(UnicodeScalar.init).map(String.init).filter(validCommandTrigger)
    }

    /// Why a command trigger is refused (`commandTriggerProblem`), as Settings says it.
    public enum CommandTriggerProblem: Error, Equatable, LocalizedError {
        /// Not one ASCII symbol: a letter, a digit, a space, nothing, several characters, or another script's.
        case notASymbol
        /// A symbol typing needs (`typingSymbols`).
        case typingSymbol(String)

        public var errorDescription: String? { message(language: UIText.language) }

        /// What Settings says, in `language`, with the symbols that work.
        public func message(language: String) -> String {
            let t = InterfaceWords(language: language), these = Config.commandTriggers.joined(separator: " ")
            switch self {
            case .notASymbol:
                return t.tr("魔法键只能是一个符号，不能是字母、数字或空格。可以用：\(these)",
                            "The magic key must be one symbol, not a letter, digit or space. These work: \(these)")
            case let .typingSymbol(symbol):
                return t.tr("\(symbol) 打字时要用（拼音或中文标点），不能用来打开命令。可以用：\(these)",
                            "\(symbol) is needed for typing (pinyin or Chinese punctuation), so it can't open commands. These work: \(these)")
            }
        }
    }

    /// The interface language (`InterfaceLanguage.code(forSetting:shipped:)`): "zh" (Simplified Chinese) and "en", as
    /// older versions write them, or another shipped language's code ("fr"); nil follows the system. A code this version
    /// doesn't ship is kept, and followed as nil.
    public var uiLanguage: String?
    /// The user's own @ commands, after the built-in ones (see `CustomCommand`).
    public var customCommands: [CustomCommand]
    /// The entries of `customCommands` in the file this version can't read (a later one's type): kept as they are and
    /// written back after the others, never offered. Their names are taken (`unreadCustomCommandNames`).
    public var unreadCustomCommands: [AIConfig.JSONValue] = []
    /// The other entries of `customCommands` in the file this version can't read (a field with a value of the wrong kind,
    /// `"minChars": "two"`; no name): each refused alone, with its reason (spec Suggestions v1, decision 25). Kept as they
    /// are and written back after the others (before `unreadCustomCommands`), never run; Settings → Custom Commands shows
    /// each with its reason. Their names are taken (`unreadCustomCommandNames`).
    public var refusedCustomCommands: [CustomCommand.Refused] = []
    /// The custom `suggestions` commands that came from another Mac through iCloud and aren't confirmed here, each by its
    /// name and the program it came with (spec Suggestions v1, decision 26; CommandsFromOtherMacs.swift): none of them runs
    /// until the user allows it in Settings → Custom Commands, or edits it here. Sync marks them as they come; a command
    /// made on this Mac is never marked. This Mac's own, never synced. None by default.
    public var unconfirmedCommands: [CustomCommand.Unconfirmed] = []

    /// The names of the entries kept without being read, `unreadCustomCommands`' and `refusedCustomCommands`': no command
    /// of this version's may have one (`CustomCommand.problem(among:)`).
    public var unreadCustomCommandNames: [String] {
        unreadCustomCommands.compactMap(CustomCommand.Entry.name) + refusedCustomCommands.compactMap(\.name)
    }
    /// Folders of script extensions (`ScriptCommand`, docs/extensions.md), as "~/…": each script, bundle
    /// command and Raycast script in them is an @ command, after the custom ones. A new user has
    /// `ExtensionStore.defaultFolder`.
    public var extensionFolders: [String]
    /// Also the folders Spotlight finds holding Raycast scripts (`ExtensionStore.discover`), less
    /// `hiddenExtensionFolders`.
    public var findRaycastScripts: Bool
    public var hiddenExtensionFolders: [String]
    /// Extension commands turned off: a command's id (`ScriptCommand.id`) or a bundle's name.
    public var disabledExtensions: [String]
    /// The bundles' preferences that aren't passwords (those are in the keychain): bundle name → name → value.
    public var extensionPreferences: [String: [String: String]]
    /// Git repositories extension bundles are installed from (`ExtensionSource`); an enabled one's bundle folder is in
    /// `extensionFolders`. Empty by default.
    public var extensionSources: [ExtensionSource]
    /// The coding agent `@agent` hands the text to (`AgentKind`); Claude Code by default.
    public var agent: AgentKind
    /// A custom agent's command (`AgentKind.custom`), the prompt appended as its last argument: `["muse", "--"]`.
    public var agentCommand: [String]
    /// `@agent` typed in Chrome takes the page along (`PageContext`: the field, its form, the selection, the visible text),
    /// when the input method may use Accessibility. On by default.
    public var agentPageContext: Bool
    /// `@agent` with Claude Code runs as a Claude Code background session, with a notification when it's done
    /// (false: an interactive session in Terminal). Other agents always open in Terminal.
    public var claudeInBackground: Bool
    /// `@question` keeps the last few questions and answers on this Mac (`QuestionHistory`) and lists them when nothing
    /// is typed after it. On by default.
    public var rememberQuestions: Bool
    /// Rounds of an `@question` conversation in the panel before it suggests going on elsewhere (`QuestionChat`):
    /// 5 by default, 2–10. Only in the file.
    public var questionRounds: Int
    /// Where an `@question` conversation can go on (`ChatHandoff`), in this order, the first the default; nil: the
    /// default list (`ChatHandoff.defaultList`). `agent` (`.atAgent`) in it is whatever `@agent` hands to.
    public var questionContinueIn: [ChatHandoff.Destination]?
    /// An icon in the menu bar that drops the panel down (notes, reminders, Claude tasks) when clicked.
    public var menuBarIcon: Bool
    /// Fuzzy pinyin (模糊音): the pairs typed either way (`FuzzyPinyin.pairs` ids, e.g. "z-zh", "n-l"); none by default.
    public var fuzzyPinyin: [String]
    /// English words of the user's offered among pinyin's candidates (`EnglishWords`, `EnglishWordsEngine`), as they are
    /// written ("Bedrock"): added in Settings, or learned (`learnsEnglishWords`). Oldest first; none by default.
    public var englishWords: [String]
    /// Those of `englishWords` the user added in Settings, as they are written (the others were learned): beyond
    /// `EnglishWords.maxWords` the oldest learned go first (`EnglishWords.capped`). None by default.
    public var addedEnglishWords: [String]
    /// Letters put in as typed twice while typing pinyin ("bedrock" and ⏎), or a word typed twice in English mode
    /// ("bedrock " after a tap of Shift: `EnglishModeWords`), are learned as an English word (`EnglishWords.learnable`):
    /// never during secure input, in a terminal, a remote desktop or a virtual machine, in an app with no AI, or for what
    /// looks like a secret. On by default.
    public var learnsEnglishWords: Bool
    /// The keyboard layout each input language types with, by language code ("fr": "com.apple.keylayout.French"),
    /// where it isn't the language's default (`Language.defaultKeyboardLayout`).
    public var keyboardLayouts: [String: String]
    /// A command's result is typed into the document character by character, like a person typing
    /// (pinyin picks still go in at once), at `typeOutRate` characters a second (1/6: 6 s a character),
    /// in bursts of changing pace when `typeOutVaries`, with an occasional typo fixed on the way when
    /// `typeOutMistakes` (`TypeOut.plan`; typed to the end, the text is exactly the result).
    public var typeOut: Bool
    public var typeOutRate: Double
    public var typeOutVaries: Bool
    public var typeOutMistakes: Bool
    /// How the candidates of a word being typed (pinyin, Hindi) are laid out: in a row like macOS's own panel (the
    /// default, also for a file from before the setting), or in a column. The other lists (commands, results) are
    /// always a column.
    public var candidateLayout: CandidateArrangement
    /// Looks for a new version of AllInOneIME once a day, in the background (`UpdateSchedule`); one is only ever
    /// installed when the user clicks Update. On by default.
    public var checkForUpdates: Bool
    /// An @ command started with text selected in the field works on that text, which stays selected and as it is
    /// meanwhile, and the result picked replaces it (`Composer.selection`). On by default (also for a file from before
    /// the setting): off for an app where it misbehaves.
    public var useSelection: Bool
    /// Settings for single apps, by bundle id (`AppProfile`): the input language a field starts in, the rewrite
    /// styles, typing out, no AI. Empty by default.
    public var appProfiles: [String: AppProfile]
    /// Emails, numbers, keys and the user's own words hidden from the AI before a request is sent (`Redaction`). Off by default.
    public var redaction: RedactionSettings
    /// Autocomplete (「续写」, `Autocomplete`): after a pause in typing, the rest of the sentence in gray after the caret,
    /// Tab puts it in. In every app but those set otherwise (`AppProfile.autocomplete`) or where it stopped for want of
    /// use. It asks the AI provider picked (`provider`) or Apple's on-device model (`Autocomplete.route`); nothing else is
    /// kept about it (an `autocompleteCloud` key an early 0.6.7 build wrote is ignored). This Mac's own: never synced.
    /// Off by default.
    public var autocomplete: Bool = false
    /// Sync through iCloud (`ICloudSync`) and what syncs: this Mac's own, never synced. Off by default.
    public var iCloudSync: ICloudSyncSettings
    /// Where `@note` saves (`NoteSettings`): Notes by default, a folder of Markdown files, or Notion. This Mac's own (a
    /// path on it), never synced.
    public var notes: NoteSettings
    /// Suggestions (plugin completions, Code's rows): General's switch (and the input menu's); nil: on (it shows once a completion
    /// source is enabled). This Mac's own, never synced.
    public var suggestions: Bool?
    /// The completion sources enabled in Settings → Plugins, each with what was enabled (the plugin's hosts, whether it
    /// queries, its script's SHA-256): an update that changes one needs enabling again (`CompletionSourceApproval`); and
    /// the script extensions' turned on in Settings → Commands (their bundle's digest and terms; what a change does depends
    /// on where the extension comes from, `ExtensionOrigin`). Off until enabled. This Mac's own (its plugins), never synced.
    public var completionSources: [CompletionSourceApproval] = []
    /// Plugins' preferences that aren't passwords (those are in the keychain): plugin name → name → value. Never synced.
    public var pluginPreferences: [String: [String: String]] = [:]
    /// What a suggestion row inserts in every app without a choice of its own (`AppProfile.suggestionsInsert`; Settings →
    /// General, decision 28): ID only, with title, with title and link; nil: the source's own (a plugin's `insert`, a
    /// custom command's Insert). Synced as the other settings are: what goes in is the same on every Mac.
    public var suggestionsInsert: SuggestionsInsert?

    /// The settings of an API-key provider, with its defaults filled in.
    public func settings(for provider: Provider) -> ProviderSettings {
        switch provider {
        case .bedrock: return ProviderSettings(model: modelId, temperature: temperature)
        case .anthropic: return anthropic.resolved(for: .anthropic)
        case .gemini: return gemini.resolved(for: .gemini)
        case .openai: return openai.resolved(for: .openai)
        case .hosted: return ProviderSettings().resolved(for: .hosted)
        case .apple: return ProviderSettings().resolved(for: .apple)
        }
    }

    /// The model requests go to, with the provider (it is part of the cache keys).
    public var activeModel: String {
        provider == .bedrock ? modelId : "\(provider.rawValue):\(settings(for: provider).model ?? "")"
    }

    /// The config file's key of `englishWords` (`EnglishWords.learn` writes it alone), and of `addedEnglishWords`.
    public static let englishWordsKey = CodingKeys.englishWords.rawValue
    public static let addedEnglishWordsKey = CodingKeys.addedEnglishWords.rawValue

    /// `jargonFile` with "~" expanded (on Windows its `%NAME%`s too, as Windows' settings window shows the default file:
    /// "%APPDATA%\AllInOneIME\jargon.txt"), or `JargonLibrary.defaultURL`.
    public var jargonURL: URL {
        guard let typed = jargonFile?.trimmingCharacters(in: .whitespaces), !typed.isEmpty else {
            return JargonLibrary.defaultURL
        }
        #if os(Windows)
        let path = CorePaths.windowsExpanded(typed, environment: ProcessInfo.processInfo.environment)
        #else
        let path = typed
        #endif
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    public init(
        awsProfile: String, region: String?, modelId: String,
        maxTokens: Int, temperature: Double?, timeoutSeconds: Double,
        rewriteStyles: [String] = RewriteStyle.defaultNames,
        outputLanguage: OutputLanguage = .english, outputLanguages: [OutputLanguage]? = nil,
        inputLanguages: [Language] = [.english], defaultInput: Language = .english,
        voiceInput: Bool = true, jargonFile: String? = nil,
        actionKey: ActionKey = .enter, uiLanguage: String? = nil, customCommands: [CustomCommand] = [],
        provider: Provider = .bedrock, anthropic: ProviderSettings = ProviderSettings(),
        gemini: ProviderSettings = ProviderSettings(), openai: ProviderSettings = ProviderSettings()
    ) {
        self.provider = provider
        self.anthropic = anthropic
        self.gemini = gemini
        self.openai = openai
        self.awsProfile = awsProfile
        self.region = region
        self.modelId = modelId
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.timeoutSeconds = timeoutSeconds
        self.rewriteStyles = rewriteStyles
        self.outputLanguage = outputLanguage
        self.outputLanguages = outputLanguages ?? [outputLanguage]
        self.inputLanguages = inputLanguages
        self.defaultInput = defaultInput
        self.improveTranslates = false
        self.voiceInput = voiceInput
        self.jargonFile = jargonFile
        self.actionKey = actionKey
        self.uiLanguage = uiLanguage
        self.customCommands = customCommands
        self.extensionFolders = [ExtensionStore.defaultFolder]
        self.findRaycastScripts = true
        self.hiddenExtensionFolders = []
        self.disabledExtensions = []
        self.extensionPreferences = [:]
        self.extensionSources = []
        self.agent = .claude
        self.agentCommand = []
        self.agentPageContext = true
        self.claudeInBackground = true
        self.rememberQuestions = true
        self.questionRounds = QuestionChat.defaultRounds
        self.questionContinueIn = nil
        self.menuBarIcon = true
        self.fuzzyPinyin = []
        self.englishWords = []
        self.addedEnglishWords = []
        self.learnsEnglishWords = true
        self.keyboardLayouts = [:]
        self.typeOut = false
        self.typeOutRate = TypeOut.defaultRate
        self.typeOutVaries = false
        self.typeOutMistakes = false
        self.candidateLayout = .horizontal
        self.checkForUpdates = true
        self.useSelection = true
        self.appProfiles = [:]
        self.redaction = RedactionSettings()
        self.iCloudSync = ICloudSyncSettings()
        self.notes = NoteSettings()
        normalizeLanguages()
    }

    public static let `default` = Config(
        awsProfile: "default",
        region: nil,
        modelId: "us.anthropic.claude-haiku-4-5-20251001-v1:0",
        // Three main versions plus the rewrites; only generated tokens are billed.
        maxTokens: 2000,
        temperature: 0.3,
        timeoutSeconds: 15,
        rewriteStyles: RewriteStyle.defaultNames
    )

    /// The default `maxTokens` before 0.6.7, which a config file of then holds: read as `Config.default`'s.
    static let oldDefaultMaxTokens = 1000

    /// Every key a config file may hold (`allKeys`: what the Assistant's checks and changes know as the config's own).
    enum CodingKeys: String, CodingKey, CaseIterable {
        case awsProfile, region, modelId, maxTokens, temperature, timeoutSeconds, rewriteStyles
        case outputLanguage, outputLanguages, inputLanguages, defaultInput, codingLanguage, improveTranslates, voiceInput, jargonFile, actionKey, commandTrigger, uiLanguage, customCommands, claudeInBackground, agent, agentCommand, agentPageContext
        case extensionFolders, findRaycastScripts, hiddenExtensionFolders, disabledExtensions, extensionPreferences
        case menuBarIcon, typeOut, typeOutRate, typeOutVaries, typeOutMistakes, typeOutSpeed, fuzzyPinyin, keyboardLayouts, candidateLayout
        case englishWords, addedEnglishWords, learnsEnglishWords
        case checkForUpdates, useSelection, appProfiles
        case rememberQuestions, questionRounds, questionContinueIn
        case redaction
        case autocomplete
        case iCloudSync
        case notes
        case suggestions, completionSources, pluginPreferences, unconfirmedCommands, suggestionsInsert
        case extensionSources
        case provider, anthropic, gemini, openai
    }

    /// The names of every key a config file may hold, those it only reads (`typeOutSpeed`) too.
    public static var allKeys: [String] { CodingKeys.allCases.map(\.rawValue) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.default
        awsProfile = try c.decodeIfPresent(String.self, forKey: .awsProfile) ?? d.awsProfile
        region = try c.decodeIfPresent(String.self, forKey: .region) ?? d.region
        modelId = try c.decodeIfPresent(String.self, forKey: .modelId) ?? d.modelId
        // 1000 was the default before 0.6.7, and every config written until then holds it (the default is written too):
        // it is the old default, not a limit the user chose, and reads as today's. Any other value stays as it is.
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens).flatMap { $0 == Self.oldDefaultMaxTokens ? nil : $0 }
            ?? d.maxTokens
        // An explicit `null` disables temperature; an absent key keeps the default.
        temperature = c.contains(.temperature)
            ? try c.decodeIfPresent(Double.self, forKey: .temperature)
            : d.temperature
        timeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? d.timeoutSeconds
        rewriteStyles = try c.decodeIfPresent([String].self, forKey: .rewriteStyles) ?? d.rewriteStyles
        // A file from before languages could be added had both, in the menu and on Shift: it keeps them.
        outputLanguages = try c.decodeIfPresent([OutputLanguage].self, forKey: .outputLanguages) ?? [.english, .chinese]
        // Codes this version doesn't know (a language a later one added) are left out, not an error.
        inputLanguages = try c.decodeIfPresent([String].self, forKey: .inputLanguages).map { $0.compactMap(Language.init(rawValue:)) }
            ?? [.chinese, .english]
        // Without the chosen one named, it's the first of the list.
        outputLanguage = try c.decodeIfPresent(OutputLanguage.self, forKey: .outputLanguage)
            ?? (c.contains(.outputLanguages) ? outputLanguages.first : nil) ?? d.outputLanguage
        // A file from before input languages started in Chinese; a new user starts in English (`Config.default`).
        defaultInput = (try? c.decodeIfPresent(Language.self, forKey: .defaultInput)).flatMap { $0 }
            ?? (c.contains(.inputLanguages) ? inputLanguages.first : .chinese) ?? d.defaultInput
        // One that isn't a coding language's id (of the wrong type, say) is no Code input, not an error.
        codingLanguage = (try? c.decodeIfPresent(String.self, forKey: .codingLanguage)).flatMap { $0 }
            .flatMap { CodingLanguagePack.isLanguage($0) ? $0 : nil }
        improveTranslates = try c.decodeIfPresent(Bool.self, forKey: .improveTranslates) ?? d.improveTranslates
        voiceInput = try c.decodeIfPresent(Bool.self, forKey: .voiceInput) ?? d.voiceInput
        jargonFile = try c.decodeIfPresent(String.self, forKey: .jargonFile)
        // One this version can't read (a later one's, or a recorded key gone wrong) is the default, not an error.
        actionKey = (try? c.decodeIfPresent(ActionKey.self, forKey: .actionKey)).flatMap { $0 } ?? d.actionKey
        let trigger = (try? c.decodeIfPresent(String.self, forKey: .commandTrigger)).flatMap { $0 } ?? "@"
        commandTrigger = Self.validCommandTrigger(trigger) ? trigger : "@"
        uiLanguage = (try? c.decodeIfPresent(String.self, forKey: .uiLanguage)).flatMap { $0 }.flatMap { $0.isEmpty ? nil : $0 }
        // Read one by one: an entry of a type this version doesn't know (a later one's) is kept aside, and one it can't
        // read otherwise (a value of the wrong kind) is refused alone (decision 25); neither is an error for the file.
        let entries = try c.decodeIfPresent([CustomCommand.Entry].self, forKey: .customCommands)
        customCommands = entries?.compactMap(\.command) ?? d.customCommands
        let unread = entries?.compactMap(\.unread) ?? []
        unreadCustomCommands = unread
        if !unread.isEmpty {
            Self.log.notice("kept \(unread.count) custom command(s) of a type this version doesn't know, to write back as "
                            + "they are: " + unread.compactMap(CustomCommand.Entry.name).map { "@" + $0 }.joined(separator: ", "))
        }
        refusedCustomCommands = entries?.compactMap(\.refused) ?? []
        if !refusedCustomCommands.isEmpty {
            Self.log.notice("refused \(refusedCustomCommands.count) custom command(s) it can't read, to write back as they are: "
                            + refusedCustomCommands.map { "@" + ($0.name ?? "?") + " (\($0.reason))" }.joined(separator: ", "))
        }
        extensionFolders = try c.decodeIfPresent([String].self, forKey: .extensionFolders) ?? d.extensionFolders
        findRaycastScripts = try c.decodeIfPresent(Bool.self, forKey: .findRaycastScripts) ?? d.findRaycastScripts
        hiddenExtensionFolders = try c.decodeIfPresent([String].self, forKey: .hiddenExtensionFolders) ?? d.hiddenExtensionFolders
        disabledExtensions = try c.decodeIfPresent([String].self, forKey: .disabledExtensions) ?? d.disabledExtensions
        extensionPreferences = try c.decodeIfPresent([String: [String: String]].self, forKey: .extensionPreferences)
            ?? d.extensionPreferences
        // A kind this version doesn't know (a later one's) is Claude Code, not an error.
        agent = (try? c.decodeIfPresent(AgentKind.self, forKey: .agent)).flatMap { $0 } ?? d.agent
        agentCommand = try c.decodeIfPresent([String].self, forKey: .agentCommand) ?? d.agentCommand
        agentPageContext = try c.decodeIfPresent(Bool.self, forKey: .agentPageContext) ?? d.agentPageContext
        claudeInBackground = try c.decodeIfPresent(Bool.self, forKey: .claudeInBackground) ?? d.claudeInBackground
        rememberQuestions = try c.decodeIfPresent(Bool.self, forKey: .rememberQuestions) ?? d.rememberQuestions
        questionRounds = QuestionChat.rounds((try? c.decodeIfPresent(Int.self, forKey: .questionRounds)).flatMap { $0 } ?? d.questionRounds)
        // Names this version doesn't know (a service a later one added) are left out, not an error.
        questionContinueIn = (try? c.decodeIfPresent([String].self, forKey: .questionContinueIn)).flatMap { $0 }?
            .compactMap(ChatHandoff.Destination.init(rawValue:))
        menuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .menuBarIcon) ?? d.menuBarIcon
        fuzzyPinyin = FuzzyPinyin.known(try c.decodeIfPresent([String].self, forKey: .fuzzyPinyin) ?? [])
        // A list of the wrong type reads as none, not an error (the words are offered only as `EnglishWords.word` allows).
        englishWords = (try? c.decodeIfPresent([String].self, forKey: .englishWords)).flatMap { $0 } ?? d.englishWords
        addedEnglishWords = (try? c.decodeIfPresent([String].self, forKey: .addedEnglishWords)).flatMap { $0 } ?? d.addedEnglishWords
        learnsEnglishWords = try c.decodeIfPresent(Bool.self, forKey: .learnsEnglishWords) ?? d.learnsEnglishWords
        keyboardLayouts = (try? c.decodeIfPresent([String: String].self, forKey: .keyboardLayouts)).flatMap { $0 } ?? [:]
        typeOut = try c.decodeIfPresent(Bool.self, forKey: .typeOut) ?? d.typeOut
        // A file from before the slider: "slow", "normal", "fast" or "random" (normal, varying).
        let older = try? c.decodeIfPresent(String.self, forKey: .typeOutSpeed)
        let olderRate: Double? = ["slow": 8, "normal": 16, "fast": 32, "random": 16][older ?? ""]
        typeOutRate = try c.decodeIfPresent(Double.self, forKey: .typeOutRate) ?? olderRate ?? d.typeOutRate
        typeOutVaries = try c.decodeIfPresent(Bool.self, forKey: .typeOutVaries) ?? (older == "random")
        typeOutMistakes = try c.decodeIfPresent(Bool.self, forKey: .typeOutMistakes) ?? d.typeOutMistakes
        // Not chosen (a file from before the setting) or a value a later version added: the default, in a row.
        candidateLayout = (try? c.decodeIfPresent(CandidateArrangement.self, forKey: .candidateLayout)).flatMap { $0 } ?? d.candidateLayout
        checkForUpdates = try c.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? d.checkForUpdates
        useSelection = try c.decodeIfPresent(Bool.self, forKey: .useSelection) ?? d.useSelection
        appProfiles = AppProfile.decodeAll(c, forKey: .appProfiles)
        redaction = try c.decodeIfPresent(RedactionSettings.self, forKey: .redaction) ?? d.redaction
        // A value of the wrong type reads as the default, not an error.
        autocomplete = (try? c.decodeIfPresent(Bool.self, forKey: .autocomplete)).flatMap { $0 } ?? d.autocomplete
        extensionSources = ExtensionSource.decodeAll(c, forKey: .extensionSources)
        iCloudSync = (try? c.decodeIfPresent(ICloudSyncSettings.self, forKey: .iCloudSync)).flatMap { $0 } ?? d.iCloudSync
        notes = (try? c.decodeIfPresent(NoteSettings.self, forKey: .notes)).flatMap { $0 } ?? d.notes
        // A value of the wrong type reads as none, not an error.
        suggestions = (try? c.decodeIfPresent(Bool.self, forKey: .suggestions)).flatMap { $0 }
        completionSources = (try? c.decodeIfPresent([CompletionSourceApproval].self, forKey: .completionSources)).flatMap { $0 } ?? []
        pluginPreferences = (try? c.decodeIfPresent([String: [String: String]].self, forKey: .pluginPreferences)).flatMap { $0 } ?? [:]
        // A value of the wrong type reads as none, not an error.
        unconfirmedCommands = (try? c.decodeIfPresent([CustomCommand.Unconfirmed].self, forKey: .unconfirmedCommands)).flatMap { $0 } ?? []
        // A value of the wrong type, or one this version doesn't know, reads as none.
        suggestionsInsert = (try? c.decodeIfPresent(String.self, forKey: .suggestionsInsert)).flatMap { $0 }.flatMap(SuggestionsInsert.init(rawValue:))
        provider = try c.decodeIfPresent(Provider.self, forKey: .provider) ?? d.provider
        anthropic = try c.decodeIfPresent(ProviderSettings.self, forKey: .anthropic) ?? d.anthropic
        gemini = try c.decodeIfPresent(ProviderSettings.self, forKey: .gemini) ?? d.gemini
        openai = try c.decodeIfPresent(ProviderSettings.self, forKey: .openai) ?? d.openai
        normalizeLanguages()
    }

    /// Renames the custom commands whose names a built-in command now has (a custom `@reply` from before `@reply` was
    /// built in), which the built-in would hide. Each gets the first name of `renameCandidates` (letters only, as a
    /// command's name must be) that no built-in, no name in `taken` (the plugins' and script extensions', which the
    /// caller knows) and no other custom command has, case aside: "myreply", "myownreply", "myreplyb" … "myreplyz"; none
    /// free (unlikely): it stays as it is. Order and everything else are kept. What was renamed, in config order (none:
    /// `[]`); run again, it renames nothing. The shell runs it once when it loads the config, writes it, and says so once
    /// (`Composer.ReplyMessages.renamed`).
    public mutating func freeBuiltinNames(taken extensions: [String]) -> [(old: String, new: String)] {
        let builtins = Set(Command.builtins.map(\.name))
        var taken = builtins.union(extensions.map { $0.lowercased() }).union(customCommands.map { $0.name.lowercased() })
            .union(unreadCustomCommandNames.map { $0.lowercased() })  // a later version's commands keep their names
        var renamed: [(old: String, new: String)] = []
        for index in customCommands.indices {
            let name = customCommands[index].name
            guard builtins.contains(name.lowercased()),
                  let new = Self.renameCandidates(for: name).first(where: { !taken.contains($0) }) else { continue }
            taken.insert(new)
            // One from another Mac stays unconfirmed under its new name.
            if let mark = unconfirmedCommands.firstIndex(where: { $0.marks(customCommands[index]) }) { unconfirmedCommands[mark].name = new }
            customCommands[index].name = new
            renamed.append((name, new))
        }
        return renamed
    }

    /// `renamed` (what `freeBuiltinNames` did) written into the config file at `url`, and nothing else: in its
    /// `customCommands`, the first command named `old` that isn't renamed yet takes `new` as its name, and so does its mark
    /// if it came from another Mac unconfirmed (`unconfirmedCommands`). Its other fields,
    /// the other commands (a later version's too) and every other key of the file stay as they were
    /// (`AIConfig.patchingFile`); writing the whole config would add the keys this version always writes, with their
    /// defaults. What was written: a rename whose command the file no longer has (changed meanwhile) isn't.
    @discardableResult
    public static func writeRenames(_ renamed: [(old: String, new: String)], at url: URL) throws -> [(old: String, new: String)] {
        var written: [(old: String, new: String)] = []
        try AIConfig.patchingFile(at: url) { file in
            guard case var .array(commands)? = file["customCommands"] else { return }
            var done = Set<Int>()
            for pair in renamed {
                let found = commands.indices.first { index in
                    guard !done.contains(index), case let .object(fields) = commands[index] else { return false }
                    return fields["name"] == .string(pair.old)
                }
                guard let index = found, case var .object(fields) = commands[index] else { continue }
                let argv = fields["argv"]
                fields["name"] = .string(pair.new)
                commands[index] = .object(fields)
                done.insert(index)
                written.append(pair)
                // Its mark, if it came from another Mac unconfirmed: the same command's.
                guard case var .array(marks)? = file["unconfirmedCommands"], let mark = marks.firstIndex(where: { mark in
                    guard case let .object(fields) = mark else { return false }
                    return fields["name"] == .string(pair.old) && fields["argv"] == argv
                }), case var .object(markFields) = marks[mark] else { continue }
                markFields["name"] = .string(pair.new)
                marks[mark] = .object(markFields)
                file["unconfirmedCommands"] = .array(marks)
            }
            file["customCommands"] = .array(commands)
        }
        return written
    }

    /// The names `freeBuiltinNames` tries for a custom command named `name`, in order: "my" before it, then "myown", then
    /// "my" before it and a letter after ("b" … "z"); only those a command can have (`CustomCommand.isValid`: letters,
    /// at most 24).
    static func renameCandidates(for name: String) -> [String] {
        let name = name.lowercased()
        let letters = "bcdefghijklmnopqrstuvwxyz".map { "my" + name + String($0) }
        return (["my" + name, "myown" + name] + letters).filter { candidate in
            candidate.count <= 24 && candidate.allSatisfy { $0.isASCII && $0.isLetter }
        }
    }

    /// The chosen output language and the default input lead their lists (whoever sets
    /// `outputLanguage` or `defaultInput` moves it to the front); one to five input languages; no
    /// language twice. To reorder, set the list and then its first as the chosen one (`setOrder`).
    public mutating func normalizeLanguages() {
        var seenOutput = Set<OutputLanguage>()
        outputLanguages = [outputLanguage] + outputLanguages.filter { $0 != outputLanguage }
        outputLanguages = outputLanguages.filter { seenOutput.insert($0).inserted }
        var seenInput = Set<Language>()
        inputLanguages = inputLanguages.filter { seenInput.insert($0).inserted }
        if inputLanguages.isEmpty { inputLanguages = [.english] }
        inputLanguages = Array(inputLanguages.prefix(Self.maxInputLanguages))
        if inputLanguages.contains(defaultInput) {
            inputLanguages = [defaultInput] + inputLanguages.filter { $0 != defaultInput }
        } else {
            defaultInput = inputLanguages[0]
        }
    }

    /// The output languages in this order: the first becomes the one in use.
    public mutating func setOrder(_ languages: [OutputLanguage]) {
        guard let first = languages.first else { return }
        outputLanguages = languages
        outputLanguage = first
        normalizeLanguages()
    }

    /// The input languages in this order: the first becomes the default.
    public mutating func setOrder(_ languages: [Language]) {
        guard let first = languages.first else { return }
        inputLanguages = languages
        defaultInput = first
        normalizeLanguages()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(awsProfile, forKey: .awsProfile)
        try c.encode(region, forKey: .region)  // written as null so the key is discoverable
        try c.encode(modelId, forKey: .modelId)
        try c.encode(maxTokens, forKey: .maxTokens)
        try c.encode(temperature, forKey: .temperature)
        try c.encode(timeoutSeconds, forKey: .timeoutSeconds)
        try c.encode(rewriteStyles, forKey: .rewriteStyles)
        try c.encode(outputLanguage, forKey: .outputLanguage)
        try c.encode(outputLanguages, forKey: .outputLanguages)
        try c.encode(inputLanguages, forKey: .inputLanguages)
        try c.encode(improveTranslates, forKey: .improveTranslates)
        try c.encode(defaultInput, forKey: .defaultInput)
        try c.encodeIfPresent(codingLanguage, forKey: .codingLanguage)
        try c.encode(voiceInput, forKey: .voiceInput)
        try c.encode(jargonFile, forKey: .jargonFile)  // null: the default file
        try c.encode(actionKey, forKey: .actionKey)
        if commandTrigger != "@" { try c.encode(commandTrigger, forKey: .commandTrigger) }
        try c.encode(uiLanguage, forKey: .uiLanguage)  // null: follow the system
        var commands = c.nestedUnkeyedContainer(forKey: .customCommands)
        for command in customCommands { try commands.encode(command) }
        for entry in refusedCustomCommands { try commands.encode(entry.json) }
        for entry in unreadCustomCommands { try commands.encode(entry) }
        try c.encode(extensionFolders, forKey: .extensionFolders)
        try c.encode(findRaycastScripts, forKey: .findRaycastScripts)
        try c.encode(hiddenExtensionFolders, forKey: .hiddenExtensionFolders)
        try c.encode(disabledExtensions, forKey: .disabledExtensions)
        try c.encode(extensionPreferences, forKey: .extensionPreferences)
        try c.encode(agent, forKey: .agent)
        try c.encode(agentCommand, forKey: .agentCommand)
        try c.encode(agentPageContext, forKey: .agentPageContext)
        try c.encode(claudeInBackground, forKey: .claudeInBackground)
        try c.encode(rememberQuestions, forKey: .rememberQuestions)
        // Only when set: a file that never had them doesn't gain them.
        if questionRounds != QuestionChat.defaultRounds { try c.encode(questionRounds, forKey: .questionRounds) }
        try c.encodeIfPresent(questionContinueIn, forKey: .questionContinueIn)
        try c.encode(menuBarIcon, forKey: .menuBarIcon)
        try c.encode(fuzzyPinyin, forKey: .fuzzyPinyin)
        // Only once there are words, and learning only when it's off: a file from before them doesn't gain the keys.
        if !englishWords.isEmpty { try c.encode(englishWords, forKey: .englishWords) }
        if !addedEnglishWords.isEmpty { try c.encode(addedEnglishWords, forKey: .addedEnglishWords) }
        if !learnsEnglishWords { try c.encode(learnsEnglishWords, forKey: .learnsEnglishWords) }
        try c.encode(keyboardLayouts, forKey: .keyboardLayouts)
        try c.encode(typeOut, forKey: .typeOut)
        try c.encode(typeOutRate, forKey: .typeOutRate)
        try c.encode(typeOutVaries, forKey: .typeOutVaries)
        try c.encode(typeOutMistakes, forKey: .typeOutMistakes)
        try c.encode(candidateLayout, forKey: .candidateLayout)
        try c.encode(checkForUpdates, forKey: .checkForUpdates)
        try c.encode(useSelection, forKey: .useSelection)
        // Only when some app sets something: a file from before per-app settings doesn't gain an empty key.
        let profiles = appProfiles.filter { !$0.value.isEmpty }
        if !profiles.isEmpty { try c.encode(profiles, forKey: .appProfiles) }
        try c.encode(redaction, forKey: .redaction)
        // Only once turned on: a file from before autocomplete doesn't gain the key.
        if autocomplete { try c.encode(autocomplete, forKey: .autocomplete) }
        // Only once a source is added: a file from before sources doesn't gain an empty key.
        if !extensionSources.isEmpty { try c.encode(extensionSources, forKey: .extensionSources) }
        // Only once it was turned on: a file from before sync doesn't gain the key.
        if iCloudSync != ICloudSyncSettings() { try c.encode(iCloudSync, forKey: .iCloudSync) }
        // Only once it differs from Notes: a file from before the setting doesn't gain the key.
        if notes != NoteSettings() { try c.encode(notes, forKey: .notes) }
        // Only once set: a file from before suggestions doesn't gain the keys.
        try c.encodeIfPresent(suggestions, forKey: .suggestions)
        if !completionSources.isEmpty { try c.encode(completionSources, forKey: .completionSources) }
        if !pluginPreferences.isEmpty { try c.encode(pluginPreferences, forKey: .pluginPreferences) }
        if !unconfirmedCommands.isEmpty { try c.encode(unconfirmedCommands, forKey: .unconfirmedCommands) }
        try c.encodeIfPresent(suggestionsInsert?.rawValue, forKey: .suggestionsInsert)
        try c.encode(provider, forKey: .provider)
        try c.encode(anthropic, forKey: .anthropic)
        try c.encode(gemini, forKey: .gemini)
        try c.encode(openai, forKey: .openai)
    }

    /// A new user's settings (no config file yet): the hosted service once it is set up, which needs
    /// nothing but a Google sign-in. A file without `provider` (from before providers) stays on Bedrock. The
    /// translation language is the first of the user's languages that isn't English (`Platform.userLanguages`).
    public static var fresh: Config {
        fresh(preferring: Platform.current.userLanguages.preferred)
    }

    /// `fresh`, translating into the first of `languages` (the system's preferred ones) that isn't
    /// English (`OutputLanguage.preferred`); English when there is none, until one is added.
    public static func fresh(preferring languages: [String]) -> Config {
        var config = Config.default
        if HostedService.isConfigured { config.provider = .hosted }
        if let language = OutputLanguage.preferred(from: languages) { config.setOrder([language]) }
        return config
    }

    /// The config file everything reads and writes: the user's (`userURL`), or the self-test's own while it runs.
    public static var defaultURL: URL { selfTestURL ?? userURL }

    /// The user's config file, `~/.config/allinoneime/config.json`.
    public static var userURL: URL {
        CorePaths.configDir.appendingPathComponent("config.json")
    }

    /// Set only by the app's self-test, before anything reads the config: a file of its own in its own folder, so
    /// that nothing it runs depends on the user's settings or changes them. Never set in the input method.
    nonisolated(unsafe) public static var selfTestURL: URL?

    /// Loads the config file. A missing file yields `Config.default`; a malformed file throws.
    public static func load(from url: URL = defaultURL) throws -> Config {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return .fresh
        }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            throw ConfigError.malformed(path: url.path, detail: String(describing: error))
        }
    }

    public func write(to url: URL = defaultURL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// The config file at `url` changed by `change`, written as Settings saves (`SettingsStore.save`, `AIConfig.writing`):
    /// only the keys `change` changed, in place, every other key of the file as it was, its text too: a key this version
    /// doesn't know, an app's field it doesn't know, the custom commands it refused or keeps for a later version.
    /// Writing the whole config (`write`) would drop those, and add the keys this version always writes. What a change
    /// outside Settings uses (the input menu's). Nothing is written when nothing changed; a file that can't be read
    /// throws and is left as it is; with none yet, the config (a new user's, `load`) is written whole. The config as
    /// changed.
    @discardableResult
    public static func change(at url: URL = defaultURL, _ change: (inout Config) throws -> Void) throws -> Config {
        let old = try load(from: url)
        var new = old
        try change(&new)
        try AIConfig.writing(new, from: old, keys: AIConfig.changedKeys(old, new), at: url)
        return new
    }
}

/// The candidate panel's layout for a word being typed (`Config.candidateLayout`).
public enum CandidateArrangement: String, Codable, CaseIterable, Sendable {
    /// One under the other, numbered on the left (↑↓ move, -/= turn the page): what 0.6.2 and earlier showed.
    case vertical
    /// Side by side, as macOS's own panel (← → move, ↑↓ or -/= turn the page): the default.
    case horizontal
}

public enum ConfigError: Error, LocalizedError, Equatable {
    case malformed(path: String, detail: String)

    public var errorDescription: String? {
        switch self {
        case let .malformed(path, detail):
            return "配置文件格式错误（\(path)）：\(detail)"
        }
    }
}

extension Optional where Wrapped == String {
    /// `Config.uiLanguage`'s values for Simplified Chinese and English ("zh", "en"), by the names they had while it was a
    /// `Language`: `config.uiLanguage = .chinese`.
    public static var chinese: String? { "zh" }
    public static var english: String? { "en" }
}

extension Config {
    static let log = CoreLog(subsystem: "com.aipinyin.inputmethod.AIPinyin", category: "config")
}

extension CustomCommand {
    /// An entry of `Config.customCommands` as the file has it: a command this version reads; the JSON of one whose
    /// `type` is a string this version doesn't know and whose `name` is a string (a later version's: kept,
    /// `Config.unreadCustomCommands`); or the JSON of any other it can't read, refused with its reason
    /// (`Config.refusedCustomCommands`, decision 25). No entry is an error for the whole list.
    struct Entry: Decodable {
        var command: CustomCommand?
        var unread: AIConfig.JSONValue?
        var refused: Refused?

        init(from decoder: Decoder) throws {
            do {
                command = try CustomCommand(from: decoder)
            } catch {
                guard let json = try? AIConfig.JSONValue(from: decoder) else { throw error }
                if Self.name(json) != nil { unread = json } else { refused = Refused(json) }
            }
        }

        /// The name of an entry of a later version's (a JSON object whose `type` this version doesn't know and whose
        /// `name` is a string), or nil when it isn't one.
        static func name(_ json: AIConfig.JSONValue) -> String? {
            guard case let .object(fields) = json, case let .string(type)? = fields["type"], CommandType(rawValue: type) == nil,
                  case let .string(name)? = fields["name"] else { return nil }
            return name
        }
    }
}

extension CustomCommand {
    /// An entry of `Config.customCommands` that isn't a command this version can read, nor a later version's: a field
    /// with a value of the wrong kind (`"minChars": "two"`), no `name` or `type`, not an object. Refused alone (spec
    /// Suggestions v1, decision 25): it never runs, Settings → Custom Commands says why (`UIText.describe`), and its JSON
    /// is written back as the file had it.
    public struct Refused: Hashable, Sendable {
        /// The entry as the file has it.
        public var json: AIConfig.JSONValue
        public var reason: Reason

        /// What is wrong with it: the first field, in `fields`' order, that is.
        public enum Reason: Hashable, Sendable, CustomStringConvertible {
            /// The field (`argv[1]` for one of its arguments) has a value of another kind than `ValueKind`.
            case wrongKind(field: String, ValueKind)
            /// `name` or `type` isn't there, or is null.
            case missing(field: String)
            /// Not a JSON object, or nothing found wrong in its fields.
            case unreadable

            /// For the log: field names only.
            public var description: String {
                switch self {
                case let .wrongKind(field, kind): return "\(field): not \(kind)"
                case let .missing(field): return "\(field): missing"
                case .unreadable: return "not a command"
                }
            }
        }

        /// The kinds of value a command's fields take.
        public enum ValueKind: Hashable, Sendable {
            case text, number, wholeNumber, trueOrFalse
            /// Of texts (`argv`).
            case list

            func fits(_ value: AIConfig.JSONValue) -> Bool {
                switch (self, value) {
                case (.text, .string), (.number, .number), (.trueOrFalse, .bool), (.list, .array): return true
                case let (.wholeNumber, .number(number)): return Int(exactly: number) != nil
                default: return false
                }
            }
        }

        /// The kind of value each field of a command takes in config.json, `name` and `type` (required) first, then in
        /// `CustomCommand`'s order: every field but `insert`, which takes any JSON (a source's rules read it).
        static let fields: [(name: String, kind: ValueKind)] = [
            ("name", .text), ("type", .text), ("summary", .text), ("prompt", .text), ("argv", .list), ("stdin", .text),
            ("ascii", .trueOrFalse), ("timeoutSeconds", .number), ("icon", .text), ("color", .text), ("url", .text),
            ("text", .text), ("prefix", .text), ("minChars", .wholeNumber), ("compare", .text), ("refresh", .text),
            ("query", .trueOrFalse), ("queryMinChars", .wholeNumber),
        ]

        init(_ json: AIConfig.JSONValue) {
            self.json = json
            reason = Self.reason(json)
        }

        /// The start of its item's id in the settings document's list of custom commands, before its place among the
        /// refused (`Config.refusedCustomCommands`): no command's name has a ":".
        public static let itemPrefix = "refused:"

        /// Its name, when it has one that is a text.
        public var name: String? {
            guard case let .object(fields) = json, case let .string(name)? = fields["name"] else { return nil }
            return name
        }

        /// What is wrong with `json`, an entry that isn't a command this version reads nor a later version's: a `type`
        /// it doesn't know comes with a `name` that isn't a string, so the name is what's wrong.
        static func reason(_ json: AIConfig.JSONValue) -> Reason {
            guard case let .object(values) = json else { return .unreadable }
            for (field, kind) in fields {
                guard let value = values[field], value != .null else {
                    if field == "name" || field == "type" { return .missing(field: field) }
                    continue
                }
                guard kind.fits(value) else { return .wrongKind(field: field, kind) }
                if case let .array(items) = value, let index = items.firstIndex(where: { !ValueKind.text.fits($0) }) {
                    return .wrongKind(field: "\(field)[\(index)]", .text)
                }
            }
            return .unreadable
        }
    }
}
