import Foundation

/// The settings document's sections and fields (`SettingsDocument`), made from the settings as they are now: which fields
/// apply (on this platform, and now: a provider's own fields only while it is the one in use), their text (as the Mac's
/// window says it, in the interface language), how each one that can be changed is set (`setters`, given a value
/// already checked against the field: `SettingsService.check`), and the actions only the schema knows how to do
/// (`handlers`: an app added, a folder removed, an extension's password saved). Each change goes through the store, with
/// its rules.
struct SettingsSchema {
    typealias JSON = AIConfig.JSONValue
    typealias Field = SettingsDocument.Field
    typealias Choice = SettingsDocument.Choice
    typealias Handler = (SettingsAction) -> Result<SettingsActionOutcome, SettingsProblem>

    /// The apps added in the window without a setting of their own yet (a profile that sets nothing isn't saved): kept
    /// by the service, listed until they are removed.
    final class AddedApps {
        var apps: [String] = []
    }

    let store: SettingsStore
    let platform: SettingsPlatform
    let keySource: (Provider) -> APIKeys.Source
    let tests: [String: SettingsStore.TestStatus]
    let libraryEntries: [PluginIndex.Entry]?
    let library: PluginLibrary
    /// How each changeable field is set.
    private(set) var setters: [String: (JSON) throws -> Void] = [:]
    /// The actions done here, by field.
    var handlers: [String: Handler] = [:]
    /// The apps typed in lately, latest first (the engine's): offered when one is added.
    var recentApps: [String] = []
    var addedApps = AddedApps()
    /// The script extensions in the folders the config names.
    var extensions = ExtensionIndex.empty
    /// How the completion sources are doing (the shell's, where it runs them), the coding packs installed, and what the
    /// coding language library offers, once browsed.
    var suggestionStatuses: [CompletionSourceStatus] = []
    var codingPacks = CodingPackStore()
    var codingEntries: [CodingPackIndex.Entry]?

    init(store: SettingsStore, platform: SettingsPlatform, keySource: @escaping (Provider) -> APIKeys.Source,
         tests: [String: SettingsStore.TestStatus], libraryEntries: [PluginIndex.Entry]?, library: PluginLibrary) {
        self.store = store
        self.platform = platform
        self.keySource = keySource
        self.tests = tests
        self.libraryEntries = libraryEntries
        self.library = library
    }

    var config: Config { store.config }

    /// What the document's platform calls its keys and places (Enter, a terminal window, this PC on Windows).
    var terms: PlatformTerms { platform == .mac ? .mac : .windows }

    /// A path of this computer's as the document's platform writes it: on Windows with backslashes ("C:\Users\…",
    /// `CorePaths.windowsWritten`), on the Mac as it is.
    func shown(path: String) -> String { platform == .windows ? CorePaths.windowsWritten(path) : path }

    /// Where the jargon list is read from unless another file is named (`JargonLibrary.defaultURL`), as the document's
    /// platform writes it, whatever the system it is made on: %APPDATA%\AllInOneIME on Windows, ~/.config/allinoneime on
    /// the Mac. On Windows the placeholder typed as it is names that file (`Config.jargonURL`).
    var defaultJargonFile: String {
        platform == .windows ? #"%APPDATA%\AllInOneIME\jargon.txt"# : "~/.config/allinoneime/jargon.txt"
    }

    mutating func sections() -> [SettingsDocument.Section] {
        [
            SettingsDocument.Section(id: "general", title: tr("通用", "General"), fields: general()),
            SettingsDocument.Section(id: "input", title: tr("输入", "Input"), fields: input()),
            SettingsDocument.Section(id: "writing", title: tr("翻译与改写", "Translate & Rewrite"), fields: writing()),
            SettingsDocument.Section(id: "provider", title: tr("AI 服务", "AI Provider"), fields: provider()),
            SettingsDocument.Section(id: "request", title: tr("模型参数", "Model Settings"), fields: request()),
            SettingsDocument.Section(id: "privacy", title: tr("隐私", "Privacy"), fields: privacy()),
            SettingsDocument.Section(id: "agent", title: tr("Agent", "Agent"), fields: agent()),
            SettingsDocument.Section(id: "apps", title: tr("按 App 设置", "Apps"), fields: apps()),
            SettingsDocument.Section(id: "plugins", title: tr("插件", "Plugins"), fields: plugins()),
            SettingsDocument.Section(id: "extensions", title: tr("脚本扩展", "Script Extensions"),
                                     footer: tr("每个脚本是一个 @ 命令，名字取自文件名（convert-timestamp.sh → @converttimestamp）。参数写在命令后面，多个用逗号隔开：@flights beijing, new york。脚本可以上屏结果、显示进度、给出列表来选，或在后台运行，完成后通知你。写法见 docs/extensions.md。",
                                                "Each script is an @ command named after its file (convert-timestamp.sh → @converttimestamp). Write its arguments after it, with commas between: @flights beijing, new york. A script can insert its result, show progress, offer a list to pick from, or run in the background and notify you. See docs/extensions.md for how to write one.")
                                                .replacingOccurrences(of: "@", with: config.commandTrigger),
                                     fields: scriptExtensions()),
            SettingsDocument.Section(id: "search", title: tr("网页搜索（@search）", "Web Search (@search)")
                                        .replacingOccurrences(of: "@", with: config.commandTrigger), fields: search()),
            SettingsDocument.Section(id: "notes", title: tr("笔记（@note）", "Notes (@note)")
                                        .replacingOccurrences(of: "@", with: config.commandTrigger), fields: notes()),
            SettingsDocument.Section(id: "commands", title: tr("自定义 @ 命令", "Custom @ Commands")
                                        .replacingOccurrences(of: "@", with: config.commandTrigger),
                                     footer: tr("保存后，在任意输入框开头打 @ 加名字就能用，和 @improve 一样。",
                                                "Once saved, type @ and its name at the start of any text field, like @improve.")
                                                .replacingOccurrences(of: "@", with: config.commandTrigger),
                                     fields: commands()),
            SettingsDocument.Section(id: "advanced", title: tr("高级", "Advanced"),
                                     footer: tr("改完立即生效，不用重启。", "Changes apply right away, with no restart."),
                                     fields: advanced()),
        ].filter { !$0.fields.isEmpty }
    }

    // MARK: Building fields

    /// Whether a field only some platforms have is on this one.
    func on(_ platforms: [SettingsPlatform]?) -> Bool { platforms.map { $0.contains(platform) } ?? true }

    /// A field, if it is on this platform; `set` (nil: shown, not changed) is how it is set. A `choice` or `choices`
    /// field's value that isn't among its choices (a later version's, one only the file names) is shown as a choice of
    /// its own, `disabled`: kept as it is, not picked (`SettingsService.check`).
    mutating func add(_ field: Field, to fields: inout [Field], set: ((JSON) throws -> Void)? = nil) {
        guard on(field.platforms) else { return }
        var field = field
        if field.value == .null { field.value = nil }  // null is left out, as every default is
        if field.kind == .choice || field.kind == .choices {
            let values = field.kind == .choice ? [field.value ?? .null] : field.value?.array ?? []
            for value in values where field.choices?.contains(where: { $0.value == value }) != true {
                field.choices = (field.choices ?? []) + [Choice(value: value, label: value.string ?? "", disabled: true)]
            }
        }
        fields.append(field)
        if let set { setters[field.id] = set }
    }

    /// A `choices` field's new value, `list`, with what it `had` that this version doesn't know (`known` false: a later
    /// version's style, a language only the file names) put back where it was when `list` leaves it out: shown
    /// `disabled`, it is kept as it is, never dropped from here.
    static func keepingUnknown(_ list: [String], had: [String], known: (String) -> Bool) -> [String] {
        var kept = list
        for (index, item) in had.enumerated() where !known(item) && !kept.contains(item) {
            kept.insert(item, at: min(index, kept.count))
        }
        return kept
    }

    func toggle(_ id: String, _ label: String, _ help: String? = nil, _ value: Bool, platforms: [SettingsPlatform]? = nil) -> Field {
        var field = Field(id: id, kind: .toggle, label: label, help: help, value: .bool(value))
        field.platforms = platforms
        return field
    }

    /// A choice field; a choice only some platforms have is left out on the others, unless it is the value now (then it
    /// shows, `disabled`).
    func choice(_ id: String, _ label: String, _ help: String? = nil, value: JSON, choices: [(Choice, [SettingsPlatform]?)],
                platforms: [SettingsPlatform]? = nil) -> Field {
        var field = Field(id: id, kind: .choice, label: label, help: help, value: value)
        field.choices = choices.compactMap { choice, platforms in
            if on(platforms) { return choice }
            guard choice.value == value else { return nil }
            var shown = choice
            shown.disabled = true
            return shown
        }
        field.platforms = platforms
        return field
    }

    func text(_ id: String, _ label: String, _ help: String? = nil, value: String?, placeholder: String? = nil) -> Field {
        var field = Field(id: id, kind: .text, label: label, help: help, value: value.map(JSON.string) ?? .null)
        field.placeholder = placeholder
        field.optional = true
        return field
    }

    func integer(_ id: String, _ label: String, value: Int, in range: ClosedRange<Int>, step: Int) -> Field {
        var field = Field(id: id, kind: .integer, label: label, value: .number(Double(value)))
        (field.min, field.max, field.step) = (Double(range.lowerBound), Double(range.upperBound), Double(step))
        return field
    }

    /// A key, token or password: whether it is set and its last 4 characters, never itself.
    func secret(_ id: String, _ label: String, _ help: String? = nil, state: KeyState, missing: String, removable: Bool) -> Field {
        var field = Field(id: id, kind: .secret, label: label, help: help)
        field.status = state.text(missing: missing)
        field.isSet = state.isSet
        field.actions = [SettingsAction.setKey] + (removable ? [SettingsAction.removeKey] : [])
        return field
    }

    /// A Test button's last outcome, as the Mac shows it.
    func outcome(_ id: String) -> String? {
        switch tests[id] {
        case let .passed(text)?: return "✓ " + text
        case let .failed(text)?: return "✗ " + text
        case .idle?, .running?, nil: return nil
        }
    }

    static func bool(_ value: JSON) -> Bool { value.bool ?? false }
    static func int(_ value: JSON) -> Int { Int(value.number ?? 0) }
    static func strings(_ value: JSON) -> [String] { value.strings ?? [] }

    // MARK: General

    mutating func general() -> [Field] {
        var fields: [Field] = []
        let store = store
        // A recorded shortcut is the Mac's (its key recorder): shown as it is, not picked here.
        let terms = terms
        var keys: [(Choice, [SettingsPlatform]?)] = [
            (Choice("enter", UIText.pickerName(.enter, terms: terms)), nil),
            (Choice("optionTap", UIText.pickerName(.optionTap, terms: terms)), [.mac]),
            (Choice("optionSpace", UIText.pickerName(.optionSpace, terms: terms)), [.mac]),
            (Choice("space", UIText.pickerName(.space, terms: terms)), nil),
        ]
        let actionKey = config.actionKey.rawName ?? "shortcut"
        if case .shortcut = config.actionKey {
            keys.append((Choice("shortcut", UIText.pickerName(config.actionKey, terms: terms)), [.mac]))
        }
        add(choice("actionKey", tr("执行键", "Action key"), UIText.actionKeyNote(config.actionKey, terms: terms), value: .string(actionKey),
                   choices: keys), to: &fields) { value in
            guard let key = value.string.flatMap(ActionKey.named) else { return }
            store.config.actionKey = key
        }
        add(text("commandTrigger", tr("魔法键", "Magic key"),
                 tr("输入一个符号，例如 @ 或 ~。打在句首打开命令列表。", "Type one symbol, such as @ or ~, to open commands at the start of a sentence."),
                 value: config.commandTrigger, placeholder: "@"), to: &fields) { value in
            guard let trigger = value.string else {
                throw SettingsProblem(.badValue, field: "commandTrigger", message: SettingsService.badValue)
            }
            if let problem = Config.commandTriggerProblem(trigger) {
                throw SettingsProblem(.badValue, field: "commandTrigger", message: problem.errorDescription ?? SettingsService.badValue)
            }
            store.config.commandTrigger = trigger
        }
        add(toggle("typeOut", tr("逐字上屏", "Type results out"),
                   tr("命令的结果（翻译、润色、回答…）像人打字一样一个字一个字打进去；打拼音选词还是马上上屏。按 Esc 停下，按别的键把剩下的一次打完。",
                      "A command's result is typed in character by character, like a person typing; pinyin picks still go in at once. Esc stops it; any other key types the rest at once."),
                   config.typeOut), to: &fields) { store.config.typeOut = Self.bool($0) }
        if config.typeOut {
            var rate = Field(id: "typeOutRate", kind: .number, label: tr("打字速度", "Typing speed"), value: .number(config.typeOutRate))
            (rate.min, rate.max) = (TypeOut.slowestRate, TypeOut.fastestRate)
            rate.status = TypeOut.label(rate: config.typeOutRate)
            add(rate, to: &fields) { store.config.typeOutRate = TypeOut.rounded(rate: $0.number ?? TypeOut.defaultRate) }
            add(toggle("typeOutVaries", tr("忽快忽慢（像真人打字）", "Speed up and slow down (like a person)"), nil, config.typeOutVaries),
                to: &fields) { store.config.typeOutVaries = Self.bool($0) }
            add(toggle("typeOutMistakes", tr("偶尔打错再改", "Make occasional typos and fix them"),
                       tr("偶尔按到旁边的键、多打一个字母或空格，或者一个词打了又删掉重打，马上就改回来，打完的文字一字不差。代码、网址和数字里打错马上就改；终端里不打错。",
                          "Now and then a neighboring key, a doubled letter or space, or a word typed again, fixed on the way: typed to the end, the text is exactly the result. In code, addresses and numbers fixed at once; never in a terminal."),
                       config.typeOutMistakes), to: &fields) { store.config.typeOutMistakes = Self.bool($0) }
        }
        add(toggle("useSelection", tr("使用选中的文字", "Use the selected text"),
                   UIText.triggered(terms.keyStyle == .symbols
                       ? tr("先选中一段文字，再打 @improve、@translate、@question 等命令按 ⏎：命令处理选中的文字（打字时它一直选中、不变），选好的结果替换它；Esc 什么都不改。哪个 App 里不正常就关掉。",
                            "Select some text, then type @improve, @translate, @question … and ⏎: the command works on the selection (it stays selected and as it is while you type), and the result you pick replaces it; Esc changes nothing. Turn it off if it misbehaves in an app.")
                       : tr("先选中一段文字，再打 @improve、@translate、@question 等命令按 Enter：命令处理选中的文字（打字时它一直选中、不变），选好的结果替换它；Esc 什么都不改。哪个应用里不正常就关掉。",
                            "Select some text, then type @improve, @translate, @question … and Enter: the command works on the selection (it stays selected and as it is while you type), and the result you pick replaces it; Esc changes nothing. Turn it off if it misbehaves in an app.")),
                   config.useSelection), to: &fields) { store.config.useSelection = Self.bool($0) }
        add(toggle("rememberQuestions", tr("记住最近的问题", "Remember recent questions"), nil, config.rememberQuestions),
            to: &fields) { store.setRememberQuestions(Self.bool($0)) }
        add(suggestionsSwitch(), to: &fields) { store.config.suggestions = Self.bool($0) ? nil : false }
        add(toggle("menuBarIcon", tr("在菜单栏显示图标", "Show in Menu Bar"),
                   tr("笔记、提醒和后台的 Claude 任务，点一下就下拉出来", "Your notes, reminders and Claude tasks, a click away"),
                   config.menuBarIcon, platforms: [.mac]), to: &fields) { store.setMenuBarIcon(Self.bool($0)) }
        let shipped = UIText.shipped
        add(choice("uiLanguage", tr("界面语言", "Interface language"),
                   value: InterfaceLanguage.code(forSetting: config.uiLanguage, shipped: shipped).map(JSON.string) ?? .null,
                   choices: [(Choice(nil, tr("跟随系统", "Follow the system")), nil)]
                       + shipped.map { (Choice($0, InterfaceLanguage.name($0)), nil) }), to: &fields) { value in
            store.setUILanguage(value.string.map(InterfaceLanguage.setting(for:)))
        }
        // Sync through iCloud is the Mac's (its window turns it on, with what it takes): shown, not changed here.
        var sync = toggle("iCloudSync", tr("通过 iCloud 同步", "Sync through iCloud"), nil, config.iCloudSync.enabled, platforms: [.mac])
        sync.readOnly = true
        add(sync, to: &fields)
        add(toggle("checkForUpdates", tr("自动检查更新", "Check for updates automatically"),
                   tr("每天在后台看一次有没有新版本，有就在这里和菜单栏面板里提一句；只有你点「更新」才会安装。",
                      "Once a day, in the background; a new version is mentioned here and in the menu bar panel, and only installed when you click Update."),
                   config.checkForUpdates, platforms: [.mac]), to: &fields) { store.config.checkForUpdates = Self.bool($0) }
        return fields
    }

    // MARK: Input

    mutating func input() -> [Field] {
        var fields: [Field] = []
        let store = store
        var languages = Field(id: "inputLanguages", kind: .choices, label: tr("输入语言", "Input languages"),
                              help: config.inputLanguages.count > 1 ? nil : tr("只有一种时 Shift 不切换", "With one, Shift doesn't switch"),
                              value: .array(config.inputLanguages.map { .string($0.rawValue) }))
        languages.choices = Language.allCases.map { Choice($0.rawValue, SessionText.inputName($0, language: UIText.language)) }
        (languages.ordered, languages.minCount, languages.maxCount) = (true, 1, Config.maxInputLanguages)
        add(languages, to: &fields) { value in
            store.config.setOrder(Self.strings(value).compactMap(Language.init(rawValue:)))
        }
        // Code, after the languages and apart from them (decision 22).
        code(&fields)
        add(choice("candidateLayout", tr("候选排列", "Candidate layout"),
                   UIText.triggered(config.candidateLayout == .horizontal
                       ? tr("选词（拼音、印地语）的候选并排（默认），像系统自带的输入法：← → 选词，↑↓ 或 - = 翻页。@ 命令列表和结果还是竖排。在下一个输入框生效。",
                            "For picking words (pinyin, Hindi): side by side (the default), like the system's own input methods; ← → choose, ↑↓ or - = turn the page. The @ list and results stay vertical. From the next text field.")
                       : tr("选词（拼音、印地语）的候选一个一个往下排：↑↓ 选词，- = 翻页。@ 命令列表和结果总是竖排。在下一个输入框生效。",
                            "For picking words (pinyin, Hindi): one under the other; ↑↓ choose, - = turn the page. The @ list and results are always vertical. From the next text field.")),
                   value: .string(config.candidateLayout.rawValue),
                   choices: [(Choice("vertical", tr("竖排", "Vertical")), nil), (Choice("horizontal", tr("横排", "Horizontal")), nil)]),
            to: &fields) { value in
            store.config.candidateLayout = value.string.flatMap(CandidateArrangement.init(rawValue:)) ?? store.config.candidateLayout
        }
        if config.inputLanguages.contains(.chinese) {
            var fuzzy = Field(id: "fuzzyPinyin", kind: .choices, label: tr("模糊音", "Fuzzy pinyin"),
                              help: tr("分不清的音两种拼法都能打出来，比如 zh 和 z：打 zi 也有「之」", "Sounds you don't tell apart typed either way, e.g. zh and z: zi also offers 之"),
                              value: .array(config.fuzzyPinyin.map(JSON.string)))
            fuzzy.choices = FuzzyPinyin.pairs.map { Choice($0.id, $0.label) }
            add(fuzzy, to: &fields) { store.setFuzzyPinyin(Self.strings($0)) }
            englishWords(&fields)
        }
        if Features.voiceInput {  // off for now: no field, the setting kept as it is
            add(toggle("voiceInput", tr("按住右 ⌥ 说话，松开结束", "Hold right ⌥ to talk, release to stop"),
                       tr("在这台 Mac 上识别，不上传", "Recognized on this Mac, never uploaded"), config.voiceInput, platforms: [.mac]),
                to: &fields) { store.config.voiceInput = Self.bool($0) }
        }
        return fields
    }

    /// The English words among pinyin's candidates (`EnglishWords`), as the Mac's window has them (Input → Chinese →
    /// English Words): the switch that learns them, and the user's, the newest first. A word typed in is added as its Add
    /// adds it (the user's: one that isn't a word, or that hiding sensitive information hides, refused), one taken out is
    /// removed, learned or added (`EnglishWords.edit`).
    mutating func englishWords(_ fields: inout [Field]) {
        let store = store
        add(toggle("learnsEnglishWords", tr("学习打出的英文词", "Learn the English words you type"),
                   terms.keyStyle == .symbols
                       ? tr("打拼音时把同样的字母原样上屏两次（比如打 bedrock 按 ⏎，再来一次），或者在英文模式下把同一个词打两次，这个词以后就出现在拼音的候选里（英文模式下照常打字，什么都不显示）。密码框、终端、远程桌面和虚拟机、关了 AI 的 App 里不学，像密钥、号码的不学，英文模式下大写字母开头的词也不学。",
                            "Put the same letters in as typed twice while typing pinyin (bedrock and ⏎, then again), or type the same word twice in English mode, and it comes up among pinyin's candidates from then on (English mode itself shows nothing). Never in password fields, terminals, remote desktops and virtual machines, or apps with AI off, nor anything that looks like a key or a number, nor a word typed in English mode with a capital first.")
                       : tr("打拼音时把同样的字母原样上屏两次（比如打 bedrock 按 Enter，再来一次），这个词以后就出现在候选里。密码框、终端、远程桌面和虚拟机、关了 AI 的应用里不学，像密钥、号码的也不学。",
                            "Put the same letters in as typed twice while typing pinyin (bedrock and Enter, then again) and the word comes up among the candidates from then on. Never in password fields, terminals, remote desktops and virtual machines, or apps with AI off, nor anything that looks like a key or a number."),
                   config.learnsEnglishWords), to: &fields) { store.config.learnsEnglishWords = Self.bool($0) }
        let shown = Array(config.englishWords.reversed())
        var words = Field(id: "englishWords", kind: .words, label: tr("你的英文词", "Your English words"),
                          help: tr("\(shown.count) 个，新的在前", "\(shown.count), the newest first"), value: .array(shown.map(JSON.string)))
        words.placeholder = tr("比如 Bedrock", "Bedrock, say")
        words.text = shown.joined(separator: ", ")
        let platform = platform
        add(words, to: &fields) { value in
            var config = store.config
            switch EnglishWords.edit(&config, to: value.string.map(RedactionSettings.words(from:)) ?? Self.strings(value)) {
            case .sensitive?:
                throw SettingsProblem(.badValue, field: "englishWords", message: platform == .mac
                    ? tr("没有添加像密钥、卡号、电话号码或 IP 地址的内容：你的英文词会通过 iCloud 同步，也会出现在候选里。",
                         "Left out what looks like a key, a card or phone number, or an IP address: your English words sync through iCloud and come up among the candidates.")
                    : tr("没有添加像密钥、卡号、电话号码或 IP 地址的内容：你的英文词会出现在候选里。",
                         "Left out what looks like a key, a card or phone number, or an IP address: your English words come up among the candidates."))
            case .notAWord?:
                throw SettingsProblem(.badValue, field: "englishWords",
                                      message: tr("没有添加：已经有了，或者不是英文词（英文字母开头，可以带数字和 - . + & ' _ /）。",
                                                  "Not added: it's there already, or isn't an English word (a Latin letter first, then letters, digits or - . + & ' _ /)."))
            case nil:
                store.config = config
            }
        }
    }

    // MARK: Translate & Rewrite

    mutating func writing() -> [Field] {
        var fields: [Field] = []
        let store = store
        // A language the file names that the catalog doesn't (added by hand): kept, under its own name.
        let codes = config.outputLanguages.map(\.code)
        let inCatalog = { (code: String) in OutputLanguage.catalog.contains { $0.code == code } }
        var languages = Field(id: "outputLanguages", kind: .choices, label: tr("翻译语言", "Languages"),
                              help: tr("每种一行，拖动排序", "A line in each; drag to reorder"),
                              value: .array(codes.map(JSON.string)))
        languages.choices = OutputLanguage.catalog.map { Choice($0.code, UIText.name($0)) }
            + config.outputLanguages.filter { !inCatalog($0.code) }.map { Choice(value: .string($0.code), label: UIText.name($0), disabled: true) }
        (languages.ordered, languages.minCount) = (true, 1)
        add(languages, to: &fields) { value in
            let kept = Self.keepingUnknown(Self.strings(value), had: codes, known: inCatalog)
            store.config.setOrder(kept.map { code in OutputLanguage.catalog.first { $0.code == code } ?? OutputLanguage(code) })
        }
        // The styles on, in their order: a name this version doesn't know (a later version's style) too, as it is.
        var seen = Set<String>()
        let on = config.rewriteStyles.map { RewriteStyle.named($0)?.name ?? $0 }.filter { seen.insert($0).inserted }
        var styles = Field(id: "rewriteStyles", kind: .choices, label: tr("风格", "Styles"),
                           help: config.rewriteStyles.isEmpty ? tr("没有风格时只出 1–3 行", "With none, lines 1–3 only")
                               : tr("用你写的语言改写，拖动排序", "In the language you wrote; drag to reorder"),
                           value: .array(on.map(JSON.string)))
        styles.choices = RewriteStyle.catalog.map { Choice($0.name, UIText.name($0), note: UIText.summary($0)) }
        styles.ordered = true
        add(styles, to: &fields) { value in
            store.setStyleOrder(Self.keepingUnknown(Self.strings(value), had: on, known: { RewriteStyle.named($0) != nil }))
        }
        add(toggle("improveTranslates", UIText.triggered(tr("@improve 同时翻译", "@improve also translates")), nil, config.improveTranslates),
            to: &fields) { store.config.improveTranslates = Self.bool($0) }
        var jargon = text("jargonFile", tr("黑话库", "Jargon list"), tr("你团队自己的说法", "Your team's own terms"),
                          value: config.jargonFile, placeholder: defaultJargonFile)
        jargon.picker = .file
        add(jargon, to: &fields) { value in
            let path = value.string?.trimmingCharacters(in: .whitespaces) ?? ""
            store.config.jargonFile = path.isEmpty ? nil : path
        }
        return fields
    }

    // MARK: AI provider

    mutating func provider() -> [Field] {
        var fields: [Field] = []
        let store = store
        let offered = Provider.offered(apple: platform == .mac ? AppleModel.system.availability : .unsupportedSystem)
        // The Cloud's sign-in and Apple's model are the Mac's.
        let choices = Provider.allCases.filter { offered.contains($0) || $0 == config.provider }.map { provider in
            (Choice(provider.rawValue, UIText.name(provider)), provider == .hosted || provider == .apple ? [SettingsPlatform.mac] : nil)
        }
        add(choice("provider", tr("服务", "Provider"), value: .string(config.provider.rawValue), choices: choices), to: &fields) { value in
            store.config.provider = value.string.flatMap(Provider.init(rawValue:)) ?? store.config.provider
        }
        let provider = config.provider
        switch provider {
        case .anthropic, .gemini, .openai:
            let stored = store.providerSettings(provider)
            let defaults = ProviderSettings.defaults(for: provider)
            var model = text("\(provider.rawValue).model", tr("模型", "Model"), value: stored.model, placeholder: defaults.model)
            model.choices = SuggestedModel.suggested(for: provider).map { Choice($0.id, $0.title, note: $0.note) }
            add(model, to: &fields) { store.setProviderField(provider, \.model, to: $0.string ?? "") }
            let source = keySource(provider)
            add(secret("\(provider.rawValue).key", "API key", state: KeyState(source, ending: APIKeys.keyEnding(account: provider.rawValue)),
                       missing: tr("还没有 API key", "No API key yet"), removable: source == .keychain), to: &fields)
            add(text("\(provider.rawValue).baseURL", tr("Base URL", "Base URL"), value: stored.baseURL, placeholder: defaults.baseURL),
                to: &fields) { store.setProviderField(provider, \.baseURL, to: $0.string ?? "") }
            add(choice("\(provider.rawValue).effort", tr("思考", "Thinking"),
                       value: .string(stored.effort ?? config.settings(for: provider).effort ?? ""),
                       choices: [(Choice("low", tr("少（low，最快）", "Little (low, fastest)")), nil), (Choice("medium", "medium"), nil),
                                 (Choice("high", "high"), nil), (Choice("", tr("不设置（模型不支持时选）", "Not set (for models without it)")), nil)]),
                to: &fields) { store.setProviderField(provider, \.effort, to: $0.string ?? "", empty: "") }
        case .bedrock:
            var model = Field(id: "bedrock.modelId", kind: .text, label: tr("模型", "Model"), value: .string(config.modelId))
            model.choices = SuggestedModel.all.map { Choice($0.id, $0.title, note: $0.note) }
            add(model, to: &fields) { value in
                let id = value.string?.trimmingCharacters(in: .whitespaces) ?? ""
                guard !id.isEmpty else {
                    throw SettingsProblem(.badValue, field: "bedrock.modelId", message: SettingsService.badValue)
                }
                store.config.modelId = id
            }
            var profiles = AWSSharedConfig.profileNames()
            if !profiles.contains(config.awsProfile) { profiles.insert(config.awsProfile, at: 0) }
            add(choice("bedrock.awsProfile", "AWS Profile", value: .string(config.awsProfile),
                       choices: profiles.map { (Choice($0, $0), nil) }), to: &fields) { value in
                store.config.awsProfile = value.string ?? store.config.awsProfile
            }
            let region = AWSSharedConfig.region(profile: config.awsProfile) ?? "us-east-1"
            add(text("bedrock.region", tr("区域", "Region"), value: config.region,
                     placeholder: tr("留空用 profile 的区域（\(region)）", "Empty: the profile's region (\(region))")), to: &fields) { value in
                let region = value.string?.trimmingCharacters(in: .whitespaces) ?? ""
                store.config.region = region.isEmpty ? nil : region
            }
        case .hosted, .apple:
            break  // the Mac's: the sign-in, the system's model
        }
        var test = Field(id: "provider.test", kind: .button, label: tr("测试连接", "Test Connection"))
        test.actions = [SettingsAction.test]
        test.status = outcome("provider.test")
        add(test, to: &fields)
        return fields
    }

    // MARK: Model settings

    mutating func request() -> [Field] {
        var fields: [Field] = []
        let store = store
        add(integer("maxTokens", tr("最多输出 \(config.maxTokens) tokens", "Up to \(config.maxTokens) output tokens"),
                    value: config.maxTokens, in: 200...4000, step: 100), to: &fields) { store.config.maxTokens = Self.int($0) }
        if config.provider == .bedrock || config.provider == .apple {
            var temperature = Field(id: "temperature", kind: .number,
                                    label: tr("发送 temperature（不接受的模型会自动不发）",
                                              "Send temperature (left out for models that refuse it)"),
                                    value: config.temperature.map(JSON.number) ?? .null)
            (temperature.min, temperature.max, temperature.step, temperature.optional) = (0, 1, 0.1, true)
            add(temperature, to: &fields) { value in
                store.config.temperature = value.number.map { ($0 * 10).rounded() / 10 }
            }
        }
        add(integer("timeoutSeconds", tr("超时 \(Int(config.timeoutSeconds)) 秒", "Timeout \(Int(config.timeoutSeconds)) s"),
                    value: Int(config.timeoutSeconds), in: 5...60, step: 5), to: &fields) { store.config.timeoutSeconds = Double(Self.int($0)) }
        return fields
    }

    // MARK: Privacy

    mutating func privacy() -> [Field] {
        var fields: [Field] = []
        let store = store
        let redaction = config.redaction
        add(toggle("redaction.enabled", tr("发送前隐藏敏感信息", "Hide sensitive information before sending"),
                   tr("邮箱、电话、卡号、密钥这些先换成 [EMAIL_1] 这样的占位符再发给 AI，结果里再换回真实内容。",
                      "Emails, numbers and keys are replaced with placeholders such as [EMAIL_1] before the AI sees the text, and put back in the results."),
                   redaction.enabled), to: &fields) { store.config.redaction.enabled = Self.bool($0) }
        guard redaction.enabled else { return fields }
        let kinds: [(String, String, WritableKeyPath<RedactionSettings, Bool>)] = [
            ("emails", tr("邮箱地址", "Email addresses"), \.emails),
            ("phones", tr("电话号码", "Phone numbers"), \.phones),
            ("cards", tr("银行卡号", "Payment card numbers"), \.cards),
            ("keys", tr("API 密钥和令牌", "API keys and tokens"), \.keys),
            ("ips", tr("IP 地址", "IP addresses"), \.ips),
        ]
        for (id, label, path) in kinds {
            add(toggle("redaction." + id, label, nil, redaction[keyPath: path]), to: &fields) { store.config.redaction[keyPath: path] = Self.bool($0) }
        }
        var words = Field(id: "redaction.customWords", kind: .words, label: tr("也隐藏这些词", "Also hide these words"),
                          help: tr("不分大小写", "In any case"), value: .array(redaction.customWords.map(JSON.string)))
        words.placeholder = tr("项目代号、名字…，用逗号分开", "A codename, a name…, separated by commas")
        words.text = redaction.customWords.joined(separator: ", ")
        add(words, to: &fields) { value in
            let list = (value.string.map(RedactionSettings.words(from:)) ?? Self.strings(value))
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            store.config.redaction.customWords = list.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        }
        return fields
    }

    // MARK: Agent

    mutating func agent() -> [Field] {
        var fields: [Field] = []
        let store = store
        add(choice("agent", UIText.triggered(tr("@agent 交给", "@agent hands it to")),
                   terms.terminal == .terminalApp
                       ? tr("在终端打开它，你打的字是第一句话。", "It opens in Terminal with what you typed as its first message.")
                       : tr("在终端窗口里打开它，你打的字是第一句话。", "It opens in a terminal window with what you typed as its first message."),
                   value: .string(config.agent.rawValue),
                   choices: AgentKind.allCases.map { kind in
                       (Choice(kind.rawValue, kind == .custom ? tr("自定义", "Custom") : kind.displayName(custom: config.agentCommand)), nil)
                   }), to: &fields) { value in
            store.config.agent = value.string.flatMap(AgentKind.init(rawValue:)) ?? store.config.agent
        }
        if config.agent == .custom {
            var command = Field(id: "agentCommand", kind: .words, label: tr("命令", "Command"),
                                help: tr("你打的字加在最后，作为最后一个参数。", "What you typed is added as its last argument."),
                                value: .array(config.agentCommand.map(JSON.string)))
            command.placeholder = tr("例如 ", "e.g. ") + "muse --"
            command.ordered = true  // a command's arguments, in order
            let rules = CustomCommand.LineRules(platform)  // the line as the system writes it
            command.text = CustomCommand.commandLine(config.agentCommand, rules: rules)
            add(command, to: &fields) { value in
                guard let line = value.string else {
                    store.config.agentCommand = Self.strings(value)
                    return
                }
                guard let argv = CustomCommand.arguments(fromCommandLine: line, rules: rules) else {
                    throw SettingsProblem(.badValue, field: "agentCommand", message: UIText.describe(.unbalancedQuote))
                }
                store.config.agentCommand = argv
            }
        }
        if config.agent == .claude {
            add(toggle("claudeInBackground", tr("在后台运行，做完通知我", "Runs in the background and notifies me"), nil,
                       config.claudeInBackground), to: &fields) { store.config.claudeInBackground = Self.bool($0) }
        }
        add(toggle("agentPageContext", UIText.triggered(tr("@agent 和 @reply 带上 Chrome 里的网页", "@agent and @reply take the Chrome page along")), nil,
                   config.agentPageContext, platforms: [.mac]), to: &fields) { store.config.agentPageContext = Self.bool($0) }
        return fields
    }

    // MARK: Plugins

    mutating func plugins() -> [Field] {
        var fields: [Field] = []
        let installed = PluginStore.load(from: library.directory).plugins
        var list = Field(id: "plugins.installed", kind: .items, label: tr("插件", "Plugins"))
        var items: [SettingsDocument.Item] = []
        for plugin in installed {
            // Its completion sources and preferences (Suggestions), when it has any.
            let own = pluginFields(plugin)
            items.append(SettingsDocument.Item(id: plugin.name, title: config.commandTrigger + plugin.name,
                                               detail: [plugin.manifest.version, plugin.manifest.summary?.text(chinese: UIText.chinese)]
                                                   .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                                               actions: [SettingsAction.remove], fields: own.isEmpty ? nil : own))
        }
        list.items = items
        if installed.isEmpty {
            list.help = UIText.triggered(tr("还没有插件。插件是别人写好的 @ 命令，比如 @stock 查股价；装好后和其他命令一样用。",
                           "No plugins yet. Plugins are ready-made @ commands, like @stock for stock quotes; once installed they work like any command."))
        }
        add(list, to: &fields)
        var browse = Field(id: "plugins.library", kind: .items, label: tr("插件库", "Plugin Library"))
        browse.help = tr("插件库里的插件都经过审核和签名；打开时才会联网（\(library.host)）。",
                         "Library plugins are reviewed and signed; the library is fetched only when you open it (\(library.host)).")
        browse.actions = [SettingsAction.browse]
        if let entries = libraryEntries {
            browse.items = entries.map { entry in
                let status = library.status(of: entry)
                let actions: [String]
                let state: String
                switch status {
                case .notInstalled: (actions, state) = ([SettingsAction.install], tr("安装", "Install"))
                case let .update(from): (actions, state) = ([SettingsAction.install], tr("更新（当前 \(from)）", "Update (from \(from))"))
                case .installed: (actions, state) = ([], tr("已安装", "Installed"))
                case .local: (actions, state) = ([], tr("已有同名本地插件", "Local plugin installed"))
                }
                return SettingsDocument.Item(id: entry.name, title: config.commandTrigger + entry.name + " " + entry.version,
                                             detail: [entry.summary?.text(chinese: UIText.chinese), state].compactMap { $0 }
                                                 .filter { !$0.isEmpty }.joined(separator: " · "),
                                             actions: actions)
            }
        }
        add(browse, to: &fields)
        return fields
    }

    // MARK: Web search

    mutating func search() -> [Field] {
        var fields: [Field] = []
        guard Command.webSearchOffered else { return fields }
        let source = WebSearch.keySource()
        let state = KeyState(source, ending: APIKeys.keyEnding(account: WebSearch.backend.keyAccount))
        var key = secret("search.key", "API key",
                         UIText.triggered(tr("@search 用 Brave Search 搜网页，用你自己的 API key：Brave 每月送一些免费额度（目前约 1000 次搜索），注册时要绑信用卡。"
                                + "要搜的内容会发给 Brave。key 存在钥匙串里；也可以在 shell 里设置 BRAVE_API_KEY。",
                            "@search searches the web with Brave Search, using your own API key: Brave gives some free credit each month "
                                + "(about 1,000 searches for now); signing up needs a credit card. What you search for is sent to Brave. "
                                + "The key is kept in the keychain; you can also set BRAVE_API_KEY in your shell.")),
                         state: state, missing: tr("还没有 API key", "No API key yet"), removable: source == .keychain)
        if state.isSet { key.actions?.append(SettingsAction.test) }
        key.status = [key.status, outcome("search.key")].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        add(key, to: &fields)
        return fields
    }

    // MARK: Notes

    mutating func notes() -> [Field] {
        var fields: [Field] = []
        let store = store
        let notes = config.notes
        add(choice("notes.destination", tr("存到", "Save to"), value: .string(notes.destination.rawValue),
                   choices: [(Choice("notes", tr("备忘录", "Notes")), [.mac]), (Choice("notion", "Notion"), nil),
                             (Choice("folder", tr("文件夹（Obsidian 等）", "Folder (Obsidian or any)")), nil)]), to: &fields) { value in
            guard let destination = value.string.flatMap(NoteSettings.Destination.init(rawValue:)) else { return }
            if destination == .folder, store.config.notes.folderURL == nil {
                // No folder yet: one is set first (`notes.folder`), as the Mac's window asks for one first.
                throw SettingsProblem(.badValue, field: "notes.destination",
                                      message: tr("还没选文件夹：笔记先存到备忘录", "No folder chosen: notes go to Notes until you choose one"))
            }
            store.setNotesDestination(destination) { nil }
        }
        if notes.destination == .folder || platform != .mac {
            var folder = text("notes.folder", tr("文件夹（Obsidian 等）", "Folder (Obsidian or any)"), value: notes.folder)
            folder.picker = .folder
            add(folder, to: &fields) { value in
                let path = value.string?.trimmingCharacters(in: .whitespaces) ?? ""
                guard !path.isEmpty else { throw SettingsProblem(.badValue, field: "notes.folder", message: SettingsService.badValue) }
                store.setNotesFolder(path)
            }
        }
        if notes.destination == .notion {
            let source = APIKeys.source(account: NotionAPI.keyAccount, variables: [])
            add(secret("notes.notionToken", tr("令牌", "Token"),
                       tr("新建集成 → 内部 → 复制令牌", "New integration → Internal → copy the token"),
                       state: KeyState(source, ending: APIKeys.keyEnding(account: NotionAPI.keyAccount)),
                       missing: tr("还没有设置", "Not set yet"), removable: source == .keychain), to: &fields)
            var link = Field(id: "notes.notion", kind: .button, label: tr("页面或数据库链接", "Page or database link"),
                             help: tr("在 Notion 里打开那个页面 → ··· → 连接 → 加上你的集成", "In Notion, open the page → ··· → Connections → add your integration"))
            link.placeholder = "https://www.notion.so/…"
            link.actions = [SettingsAction.test]
            link.textActions = [SettingsAction.test]
            link.status = outcome("notes.notion") ?? notes.notion?.label(language: UIText.language)
            add(link, to: &fields)
        }
        return fields
    }

    // MARK: Custom commands

    mutating func commands() -> [Field] {
        var fields: [Field] = []
        var list = Field(id: "commands.custom", kind: .items, label: UIText.triggered(tr("自定义 @ 命令", "Custom @ Commands")))
        list.actions = [SettingsAction.save]
        list.schema = Self.commandSchema(terms)
        list.items = config.customCommands.map { command in
            let value = (try? JSONEncoder().encode(command)).flatMap { try? JSONSerialization.jsonObject(with: $0) }.flatMap(JSON.init)
            // A suggestion source: how it is doing, or why it isn't used.
            let key = CompletionSourceKey(command: command.name)
            let state = command.suggestionsState(config, status: suggestionStatuses.first { $0.plugin == key.plugin && $0.source == key.source })
            let detail = [UIText.customKind(command), command.summary].compactMap { $0 }.joined(separator: " · ")
                + (state.map { "\n" + $0.text } ?? "")
                + (Command.builtins.contains { $0.name == command.name.lowercased() }
                   ? "\n" + tr("和内置命令重名，不会生效，请改名", "Same name as a built-in command: rename it to use it") : "")
            return SettingsDocument.Item(id: command.name, title: config.commandTrigger + command.name, detail: detail, value: value,
                                         actions: [SettingsAction.save, SettingsAction.delete])
        }
        // Those config.json has that can't be read (decision 25): why, and Delete only (no editor reads them).
        list.items? += config.refusedCustomCommands.enumerated().map { index, refused in
            SettingsDocument.Item(id: CustomCommand.Refused.itemPrefix + String(index), title: config.commandTrigger + (refused.name ?? "?"),
                                  detail: UIText.describe(refused), actions: [SettingsAction.delete])
        }
        add(list, to: &fields)
        return fields
    }

    /// A custom command's definition (`CustomCommand`, as `config.json` has it), as the Mac's command editor shows it:
    /// what `save` takes as its `value`. What runs where, and the keys, as `terms` names them (on Windows a terminal
    /// window, this PC, cmd, Enter).
    static func commandSchema(_ terms: PlatformTerms) -> [Field] {
        let mac = terms.terminal == .terminalApp
        let types = ["prompt", "run", "terminal", "link", "snippet", "suggestions"].map(JSON.string)
        func only(_ values: String...) -> [String: [JSON]] { ["type": values.map(JSON.string)] }
        var name = Field(id: "name", kind: .text, label: tr("名字", "Name"))
        name.placeholder = tr("只用英文字母，比如 py", "Letters only, e.g. py")
        var type = Field(id: "type", kind: .choice, label: tr("做什么", "What it does"), value: .string("prompt"))
        type.choices = zip(types, [tr("AI 指令", "AI instruction"), tr("运行程序", "Run a program"),
                                   mac ? tr("在终端运行", "Run in Terminal") : tr("在终端窗口运行", "Run in a terminal"),
                                   tr("打开网页", "Open a web page"), tr("插入文字", "Insert text"), tr("建议", "Suggestions")])
            .map { Choice(value: $0, label: $1) }
        var summary = Field(id: "summary", kind: .text, label: tr("说明", "Description"))
        (summary.placeholder, summary.optional) = (tr("命令列表里显示，可以不填", "Shown in the command list (optional)"), true)
        var prompt = Field(id: "prompt", kind: .text, label: tr("AI 指令", "AI instruction"),
                           help: terms.keyStyle == .symbols
                               ? tr("告诉 AI 怎么处理命令后面写的内容，比如「把用户的话写成一条礼貌简短的回复」。回答出现在候选里，⏎ 上屏。",
                                    "Tell the AI what to do with the text after the command, e.g. \"Write a short, polite reply to the user's message.\" The answer appears in the candidates; ⏎ inserts it.")
                               : tr("告诉 AI 怎么处理命令后面写的内容，比如「把用户的话写成一条礼貌简短的回复」。回答出现在候选里，按 Enter 上屏。",
                                    "Tell the AI what to do with the text after the command, e.g. \"Write a short, polite reply to the user's message.\" The answer appears in the candidates; Enter inserts it."))
        (prompt.multiline, prompt.when) = (true, only("prompt"))
        var text = Field(id: "text", kind: .text, label: tr("插入文字", "Insert text"),
                         help: tr("命令后面写的内容换掉 {input}；{名字?} 是要填的空，用逗号分开依次填；{{ 写出 {",
                                  "The text after the command replaces {input}; {label?} is a blank, filled in order, separated by commas; write {{ for {"))
        (text.multiline, text.when) = (true, only("snippet"))
        var url = Field(id: "url", kind: .text, label: tr("网址", "Address"),
                        help: tr("{input} 换成命令后面写的内容（自动编码），放在 ? 后面。按执行键在浏览器打开，不上屏。只能用 https://。",
                                 "{input} becomes the text after the command (encoded), after the ?. The action key opens it in the browser; nothing is inserted. https:// only."))
        (url.placeholder, url.when) = ("https://www.google.com/search?q={input}", only("link"))
        var argv = Field(id: "argv", kind: .words, label: tr("命令", "Command"),
                         help: mac
                             ? tr("{input} 换成命令后面写的内容，始终是一个参数，不经过 shell（要 shell 就写 zsh -c {input}）。参数里有空格时用引号。",
                                  "{input} becomes the text after the command, always as one argument, never through a shell (for one, write zsh -c {input}). Quote arguments with spaces.")
                             : tr("{input} 换成命令后面写的内容，始终是一个参数，不经过 shell（要 shell 就写 cmd /c {input}）。参数里有空格时用引号。",
                                  "{input} becomes the text after the command, always as one argument, never through a shell (for one, write cmd /c {input}). Quote arguments with spaces."))
        (argv.placeholder, argv.ordered, argv.when) = ("python3 -c {input}", true, only("run", "terminal", "suggestions"))
        var stdin = Field(id: "stdin", kind: .text, label: tr("标准输入", "Standard input"),
                          help: tr("把内容作为标准输入（命令里不用写 {input}）", "Send the text to standard input (no {input} needed)"))
        (stdin.placeholder, stdin.optional, stdin.when) = (CustomCommand.placeholder, true, only("run"))
        var timeout = Field(id: "timeoutSeconds", kind: .number, label: tr("最多运行（秒）", "Stop after (seconds)"))
        (timeout.min, timeout.max, timeout.step, timeout.optional) = (1, 120, 1, true)
        (timeout.placeholder, timeout.when) = (String(Int(CustomCommand.defaultTimeout)), only("run", "suggestions"))
        var ascii = Field(id: "ascii", kind: .toggle, label: tr("用英文字母输入（写代码、路径时）", "Type English letters (for code and paths)"))
        (ascii.optional, ascii.when) = (true, only("prompt", "run", "terminal", "link"))
        var programs = Field(id: "programs", kind: .info, label: "",
                             value: .string(terms.device == .mac
                                 ? tr("「运行程序」和「在终端运行」会在你的 Mac 上执行命令：只加你自己写的、信得过的。它们只在你按执行键时运行，密码框里不运行。",
                                      "Programs run on your Mac: add only commands you wrote and trust. They run only when you press the action key, never in password fields.")
                                 : tr("「运行程序」和「在终端窗口运行」会在这台电脑上执行命令：只加你自己写的、信得过的。它们只在你按执行键时运行，密码框里不运行。",
                                      "Programs run on this PC: add only commands you wrote and trust. They run only when you press the action key, never in password fields.")))
        programs.when = only("run", "terminal")
        return [name, type, summary, prompt, text, url] + suggestionsSchema(terms, only: only("suggestions"), first: true)
            + [argv, stdin, timeout, ascii, programs] + suggestionsSchema(terms, only: only("suggestions"), first: false)
    }

    /// A `suggestions` command's own fields (decision 24), as the Mac's editor has them: its prefix before the program
    /// (`first`); after it Look up as you type and from which character, how often the list runs again, what a row
    /// inserts (the editor's presets), and what the program is given.
    static func suggestionsSchema(_ terms: PlatformTerms, only: [String: [JSON]], first: Bool) -> [Field] {
        guard !first else {
            var prefix = Field(id: "prefix", kind: .text, label: tr("前缀", "Prefix"),
                               help: tr("打了它，光标下面就列出程序给的、对得上的行，Tab 插入：1 到 16 个英文字母、数字或 . _ - #，比如 JIRA-",
                                        "Type it and the program's rows that match show under the caret; Tab inserts. 1 to 16 letters, digits or . _ - #, like JIRA-"))
            (prefix.placeholder, prefix.when) = ("JIRA-", only)
            return [prefix]
        }
        var query = Field(id: "query", kind: .toggle, label: tr("边打边查（把前缀后面打的字交给程序）", "Look up as you type (what you type after the prefix goes to the program)"),
                          help: tr("前缀后面打的字作为一个参数给程序：写在命令里 {input} 的位置，没写就放在最后。",
                                   "What you type after the prefix goes to the program as one argument: where {input} is in the command, else last."))
        (query.optional, query.when) = (true, only)
        var from = Field(id: "queryMinChars", kind: .number, label: tr("从第几个字开始查", "Look up from character"))
        (from.min, from.max, from.step, from.optional, from.placeholder, from.when) = (1, 32, 1, true, "3", only)
        var refresh = Field(id: "refresh", kind: .choice, label: tr("刷新", "Refresh"), value: .string("1h"))
        refresh.choices = ["5m", "15m", "30m", "1h", "6h", "12h", "1d", "7d"].map { choice in
            Choice(value: .string(choice), label: CompletionDeclaration.duration(choice).map {
                tr("每 \(CompletionSource.interval($0))", "Every \(CompletionSource.interval($0))")
            } ?? choice)
        }
        (refresh.optional, refresh.when) = (true, only)
        var insert = Field(id: "insert", kind: .choice, label: tr("插入", "Insert"),
                           help: tr("其他写法（自己的模板）和插件的 insert 一样，写在配置文件里。", "Other templates of your own are written as a plugin's insert, in the config file."))
        insert.choices = [
            Choice(value: CustomCommand.InsertPreset.match.insert ?? .object(["default": .string("{arg}")]), label: tr("只插入匹配的部分", "Just the match")),
            Choice(value: CustomCommand.InsertPreset.title.insert ?? .null, label: tr("连同标题", "With its title")),
            Choice(value: CustomCommand.InsertPreset.titleAndLink.insert ?? .null, label: tr("连同标题和链接（聊天 App 里）", "With title and link (in chat apps)")),
        ]
        (insert.optional, insert.when) = (true, only)
        var program = Field(id: "suggestionsProgram", kind: .info, label: "",
                            value: .string(terms.device == .mac
                                ? tr("这个程序会在你的 Mac 上运行：打前缀时按刷新间隔拿列表，边打边查时把前缀后面的字作为一个参数给它，别的什么都不给；密码框里不运行。只加你自己写的、信得过的程序。",
                                     "The program runs on your Mac: for its list when you type the prefix (then at the refresh interval), and with Look up as you type with what follows the prefix as one argument, nothing else; never in password fields. Add only programs you wrote and trust.")
                                : tr("这个程序会在这台电脑上运行：打前缀时按刷新间隔拿列表，边打边查时把前缀后面的字作为一个参数给它，别的什么都不给；密码框里不运行。只加你自己写的、信得过的程序。",
                                     "The program runs on this PC: for its list when you type the prefix (then at the refresh interval), and with Look up as you type with what follows the prefix as one argument, nothing else; never in password fields. Add only programs you wrote and trust.")))
        program.help = tr("不带参数运行时打印全部条目：每行「匹配⇥标题⇥网址」（标题、网址可以不写），或者插件那样的 JSON。",
                          "Run with no input, it prints every item: a line each, \"match⇥title⇥url\" (title and url optional), or the plugins' JSON.")
        program.when = only
        return [query, from, refresh, insert, program]
    }

    // MARK: Advanced

    mutating func advanced() -> [Field] {
        var fields: [Field] = []
        add(Field(id: "configFile", kind: .info, label: tr("配置文件", "Config file"), value: .string(shown(path: store.configURL.path))),
            to: &fields)
        return fields
    }
}

extension ActionKey {
    /// The action key a settings document names ("enter", "space", …); a recorded shortcut is none of these.
    static func named(_ name: String) -> ActionKey? {
        [ActionKey.enter, .optionTap, .optionSpace, .space].first { $0.rawName == name }
    }
}
