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
    /// Language of the settings window; nil follows the system.
    public var uiLanguage: Language?
    /// The user's own @ commands, after the built-in ones (see `CustomCommand`).
    public var customCommands: [CustomCommand]
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
    /// `@claude` runs as a Claude Code background session, with a notification when it's done
    /// (false: an interactive session in Terminal).
    public var claudeInBackground: Bool
    /// `@question` keeps the last few questions and answers on this Mac (`QuestionHistory`) and lists them when nothing
    /// is typed after it. On by default.
    public var rememberQuestions: Bool
    /// Rounds of an `@question` conversation in the panel before it suggests going on elsewhere (`QuestionChat`):
    /// 5 by default, 2–10. Only in the file.
    public var questionRounds: Int
    /// Where an `@question` conversation can go on (`ChatHandoff`), in this order, the first the default; nil: the
    /// default choices (`ChatHandoff.defaultChoices`).
    public var questionContinueIn: [ChatHandoff.Destination]?
    /// An icon in the menu bar that drops the panel down (notes, reminders, Claude tasks) when clicked.
    public var menuBarIcon: Bool
    /// Fuzzy pinyin (模糊音): the pairs typed either way (`FuzzyPinyin.pairs` ids, e.g. "z-zh", "n-l"); none by default.
    public var fuzzyPinyin: [String]
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

    /// `jargonFile` with "~" expanded, or `JargonLibrary.defaultURL`.
    public var jargonURL: URL {
        guard let path = jargonFile?.trimmingCharacters(in: .whitespaces), !path.isEmpty else {
            return JargonLibrary.defaultURL
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    public init(
        awsProfile: String, region: String?, modelId: String,
        maxTokens: Int, temperature: Double?, timeoutSeconds: Double,
        rewriteStyles: [String] = RewriteStyle.defaultNames,
        outputLanguage: OutputLanguage = .english, outputLanguages: [OutputLanguage]? = nil,
        inputLanguages: [Language] = [.english], defaultInput: Language = .english,
        voiceInput: Bool = true, jargonFile: String? = nil,
        actionKey: ActionKey = .enter, uiLanguage: Language? = nil, customCommands: [CustomCommand] = [],
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
        self.claudeInBackground = true
        self.rememberQuestions = true
        self.questionRounds = QuestionChat.defaultRounds
        self.questionContinueIn = nil
        self.menuBarIcon = true
        self.fuzzyPinyin = []
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
        normalizeLanguages()
    }

    public static let `default` = Config(
        awsProfile: "default",
        region: nil,
        modelId: "us.anthropic.claude-haiku-4-5-20251001-v1:0",
        // Three main versions plus the rewrites; only generated tokens are billed.
        maxTokens: 1000,
        temperature: 0.3,
        timeoutSeconds: 15,
        rewriteStyles: RewriteStyle.defaultNames
    )

    /// Every key a config file may hold (`allKeys`: what `@doctor` and `@config` know as the config's own).
    enum CodingKeys: String, CodingKey, CaseIterable {
        case awsProfile, region, modelId, maxTokens, temperature, timeoutSeconds, rewriteStyles
        case outputLanguage, outputLanguages, inputLanguages, defaultInput, improveTranslates, voiceInput, jargonFile, actionKey, uiLanguage, customCommands, claudeInBackground
        case extensionFolders, findRaycastScripts, hiddenExtensionFolders, disabledExtensions, extensionPreferences
        case menuBarIcon, typeOut, typeOutRate, typeOutVaries, typeOutMistakes, typeOutSpeed, fuzzyPinyin, keyboardLayouts, candidateLayout
        case checkForUpdates, useSelection, appProfiles
        case rememberQuestions, questionRounds, questionContinueIn
        case redaction
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
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? d.maxTokens
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
        improveTranslates = try c.decodeIfPresent(Bool.self, forKey: .improveTranslates) ?? d.improveTranslates
        voiceInput = try c.decodeIfPresent(Bool.self, forKey: .voiceInput) ?? d.voiceInput
        jargonFile = try c.decodeIfPresent(String.self, forKey: .jargonFile)
        actionKey = try c.decodeIfPresent(ActionKey.self, forKey: .actionKey) ?? d.actionKey
        uiLanguage = (try? c.decodeIfPresent(Language.self, forKey: .uiLanguage)).flatMap { $0 }.flatMap { $0.isInterfaceLanguage ? $0 : nil }
        customCommands = try c.decodeIfPresent([CustomCommand].self, forKey: .customCommands) ?? d.customCommands
        extensionFolders = try c.decodeIfPresent([String].self, forKey: .extensionFolders) ?? d.extensionFolders
        findRaycastScripts = try c.decodeIfPresent(Bool.self, forKey: .findRaycastScripts) ?? d.findRaycastScripts
        hiddenExtensionFolders = try c.decodeIfPresent([String].self, forKey: .hiddenExtensionFolders) ?? d.hiddenExtensionFolders
        disabledExtensions = try c.decodeIfPresent([String].self, forKey: .disabledExtensions) ?? d.disabledExtensions
        extensionPreferences = try c.decodeIfPresent([String: [String: String]].self, forKey: .extensionPreferences)
            ?? d.extensionPreferences
        claudeInBackground = try c.decodeIfPresent(Bool.self, forKey: .claudeInBackground) ?? d.claudeInBackground
        rememberQuestions = try c.decodeIfPresent(Bool.self, forKey: .rememberQuestions) ?? d.rememberQuestions
        questionRounds = QuestionChat.rounds((try? c.decodeIfPresent(Int.self, forKey: .questionRounds)).flatMap { $0 } ?? d.questionRounds)
        // Names this version doesn't know (a service a later one added) are left out, not an error.
        questionContinueIn = (try? c.decodeIfPresent([String].self, forKey: .questionContinueIn)).flatMap { $0 }?
            .compactMap(ChatHandoff.Destination.init(rawValue:))
        menuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .menuBarIcon) ?? d.menuBarIcon
        fuzzyPinyin = FuzzyPinyin.known(try c.decodeIfPresent([String].self, forKey: .fuzzyPinyin) ?? [])
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
        extensionSources = ExtensionSource.decodeAll(c, forKey: .extensionSources)
        provider = try c.decodeIfPresent(Provider.self, forKey: .provider) ?? d.provider
        anthropic = try c.decodeIfPresent(ProviderSettings.self, forKey: .anthropic) ?? d.anthropic
        gemini = try c.decodeIfPresent(ProviderSettings.self, forKey: .gemini) ?? d.gemini
        openai = try c.decodeIfPresent(ProviderSettings.self, forKey: .openai) ?? d.openai
        normalizeLanguages()
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
        try c.encode(voiceInput, forKey: .voiceInput)
        try c.encode(jargonFile, forKey: .jargonFile)  // null: the default file
        try c.encode(actionKey, forKey: .actionKey)
        try c.encode(uiLanguage, forKey: .uiLanguage)  // null: follow the system
        try c.encode(customCommands, forKey: .customCommands)
        try c.encode(extensionFolders, forKey: .extensionFolders)
        try c.encode(findRaycastScripts, forKey: .findRaycastScripts)
        try c.encode(hiddenExtensionFolders, forKey: .hiddenExtensionFolders)
        try c.encode(disabledExtensions, forKey: .disabledExtensions)
        try c.encode(extensionPreferences, forKey: .extensionPreferences)
        try c.encode(claudeInBackground, forKey: .claudeInBackground)
        try c.encode(rememberQuestions, forKey: .rememberQuestions)
        // Only when set: a file that never had them doesn't gain them.
        if questionRounds != QuestionChat.defaultRounds { try c.encode(questionRounds, forKey: .questionRounds) }
        try c.encodeIfPresent(questionContinueIn, forKey: .questionContinueIn)
        try c.encode(menuBarIcon, forKey: .menuBarIcon)
        try c.encode(fuzzyPinyin, forKey: .fuzzyPinyin)
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
        // Only once a source is added: a file from before sources doesn't gain an empty key.
        if !extensionSources.isEmpty { try c.encode(extensionSources, forKey: .extensionSources) }
        try c.encode(provider, forKey: .provider)
        try c.encode(anthropic, forKey: .anthropic)
        try c.encode(gemini, forKey: .gemini)
        try c.encode(openai, forKey: .openai)
    }

    /// A new user's settings (no config file yet): the hosted service once it is set up, which needs
    /// nothing but a Google sign-in. A file without `provider` (from before providers) stays on Bedrock.
    public static var fresh: Config {
        fresh(preferring: Locale.preferredLanguages)
    }

    /// `fresh`, translating into the first of `languages` (the system's preferred ones) that isn't
    /// English (`OutputLanguage.preferred`); English when there is none, until one is added.
    public static func fresh(preferring languages: [String]) -> Config {
        var config = Config.default
        if HostedService.isConfigured { config.provider = .hosted }
        if let language = OutputLanguage.preferred(from: languages) { config.setOrder([language]) }
        return config
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/allinoneime/config.json")
    }

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
