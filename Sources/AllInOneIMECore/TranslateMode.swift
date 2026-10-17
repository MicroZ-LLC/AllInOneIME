import Foundation

// MARK: - Translation mode (a prototype)

/// Translation mode: typed text collects into a draft, and ⏎ translates it into one language and inserts the
/// translation at once, with no candidates to pick from (⇧⏎ inserts the draft as typed). A long press of Shift on its
/// own turns it on and off (`ShiftHold`), and so do `@mode <language> [tone]`, `@mode off` and `@exit`. It translates
/// into the first output language that isn't the language being typed, in a tone that follows the app (`tone(app:)`).
/// It is one input method's state across its text fields (`State`): switching to another app leaves it, unless that
/// app's profile translates always (`AppProfile.translateAlways`). The composer does the typing (Composer+TranslateMode.swift),
/// the controller keeps the state and asks the model (`Converter.translateMode`, a request of its own:
/// `Prompt.translateModeRequest`).
public enum TranslateMode {
    /// The tone of a translation: the app's first rewrite style (`AppProfile.rewriteStyles`), else one for the kind of
    /// app (`AppClass`), unless `@mode` named one.
    public enum Tone: String, CaseIterable, Equatable, Sendable {
        case natural, casual, formal, concise, tactful, jargon

        /// The tone of a rewrite style (`RewriteStyle.catalog`): Polish is natural.
        public init(style: RewriteStyle) {
            switch style.tag {
            case "CASUAL": self = .casual
            case "FORMAL": self = .formal
            case "CONCISE": self = .concise
            case "TACTFUL": self = .tactful
            case RewriteStyle.jargonTag: self = .jargon
            default: self = .natural
            }
        }

        /// What the request adds to the translation rules (`Prompt.translateModeRequest`).
        public var rule: String {
            let tone: String
            switch self {
            case .natural: tone = "natural and neutral, as a native speaker would normally write it"
            case .casual: tone = "casual and friendly, like chatting with a friend or a close colleague: relaxed everyday words, nothing stiff"
            case .formal: tone = "formal and polite, as for a manager, a client or an email: professional, courteous wording"
            case .concise: tone = "concise: as short as possible while keeping every point"
            case .tactful: tone = "tactful and considerate: bluntness, criticism or a refusal softened, the point kept"
            case .jargon: tone = "playful big-tech corporate jargon where it fits naturally, the point still recognizable"
            }
            return "Tone of the translation: \(tone). The tone changes only the wording: keep the meaning, the facts and the intent."
        }

        /// Its name in the interface language: 「正式」 / "formal".
        public func name(chinese: Bool) -> String {
            switch self {
            case .natural: return chinese ? "自然" : "natural"
            case .casual: return chinese ? "口语" : "casual"
            case .formal: return chinese ? "正式" : "formal"
            case .concise: return chinese ? "简洁" : "concise"
            case .tactful: return chinese ? "委婉" : "tactful"
            case .jargon: return chinese ? "黑话" : "jargon"
            }
        }

        /// The words `@mode` takes for it (any case): its English and Chinese names, and the rewrite style's.
        static let words: [Tone: [String]] = [
            .natural: ["natural", "neutral", "default", "polish", "自然", "默认", "润色"],
            .casual: ["casual", "informal", "chat", "口语", "随意", "轻松"],
            .formal: ["formal", "polite", "正式", "礼貌"],
            .concise: ["concise", "short", "简洁", "简短"],
            .tactful: ["tactful", "soft", "委婉"],
            .jargon: ["jargon", "黑话"],
        ]

        /// The tone a word names ("formal", 「正式」), if any.
        static func named(_ word: String) -> Tone? {
            let key = word.lowercased()
            return allCases.first { words[$0]?.contains(key) == true }
        }
    }

    /// What kind of app a bundle id is, for the tone it gets by default.
    public enum AppClass: Equatable, Sendable {
        /// Messaging (WeChat, Slack, Messages, Telegram, Discord, Teams): casual.
        case chat
        /// Email (Mail, Outlook, Spark): formal.
        case mail
        /// Everything else: natural.
        case other

        static let chatApps: Set<String> = [
            "com.tencent.xinwechat", "com.tinyspeck.slackmacgap", "com.apple.mobilesms", "com.apple.ichat",
            "ru.keepcoder.telegram", "org.telegram.desktop", "com.tdesktop.telegram", "com.hnc.discord",
            "com.microsoft.teams", "com.microsoft.teams2",
        ]
        static let mailApps: Set<String> = [
            "com.apple.mail", "com.microsoft.outlook", "com.readdle.smartemail-mac", "com.readdle.sparkdesktop",
            "com.readdle.spark",
        ]

        /// The class of `app` (a bundle id, any case).
        public init(app: String?) {
            let id = app?.lowercased() ?? ""
            self = Self.chatApps.contains(id) ? .chat : Self.mailApps.contains(id) ? .mail : .other
        }

        public var tone: Tone {
            switch self {
            case .chat: return .casual
            case .mail: return .formal
            case .other: return .natural
            }
        }
    }

    /// The tone in `app`: `explicit` (`@mode en formal`), else the first of the app's own rewrite styles, else its
    /// class's (`AppClass`).
    public static func tone(app: String?, config: Config, explicit: Tone? = nil) -> Tone {
        if let explicit { return explicit }
        if let first = config.profile(for: app)?.rewriteStyles.map(RewriteStyle.resolve)?.first { return Tone(style: first) }
        return AppClass(app: app).tone
    }

    /// The language text typed in `source` is translated into: the first of `outputs` that isn't it (nil: none).
    public static func target(source: Language, outputs: [OutputLanguage]) -> OutputLanguage? {
        outputs.first { !source.matches($0) }
    }

    /// One language as the mode's indicator writes it: 「英」, 「日」, 「繁」 …, else its Chinese name without 语 / 文.
    public static func short(_ language: OutputLanguage) -> String {
        let table = ["en": "英", "zh": "中", "zh-Hant": "繁", "ja": "日", "ko": "韩", "fr": "法", "de": "德", "es": "西",
                     "pt": "葡", "it": "意", "ru": "俄", "vi": "越", "th": "泰", "id": "印尼", "ar": "阿", "hi": "印"]
        if let short = table[language.code] { return short }
        var name = language.name(chinese: true)
        if name.count > 2, name.hasSuffix("语") || name.hasSuffix("文") { name.removeLast() }
        return name
    }

    /// 「中→英」: the language typed (`from`; nil or the target itself: left out) and the one translated into.
    public static func indicator(from source: Language?, to target: OutputLanguage) -> String {
        let from = source.flatMap { $0.matches(target) ? nil : short(OutputLanguage($0)) } ?? ""
        return from + "→" + short(target)
    }

    /// One time the mode is on: what it translates into, and the tone `@mode` named (nil: the app's).
    public struct Session: Equatable, Sendable {
        public var target: OutputLanguage
        public var tone: Tone?

        public init(target: OutputLanguage, tone: Tone? = nil) {
            self.target = target
            self.tone = tone
        }
    }

    /// The mode turned on (into a language, nil: the default one; in a tone, nil: the app's) or off.
    public enum Change: Equatable, Sendable {
        case enter(target: OutputLanguage?, tone: Tone?)
        case leave
    }

    /// What `@mode`'s text asks for, or the word it can't read.
    public enum Parsed: Equatable, Sendable {
        case change(Change)
        case unknown(String)
    }

    /// The text after `@mode`: a language and a tone in either order, by code or name, in English or Chinese
    /// ("en formal", 「英文 正式」, "ja", "casual"), either or both left out for the defaults; "off" (「关」) leaves the mode.
    public static func parse(_ text: String) -> Parsed {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "，" || $0 == "、" }).map(String.init)
        if words.count == 1, ["off", "exit", "stop", "关", "关闭", "退出"].contains(words[0].lowercased()) { return .change(.leave) }
        var target: OutputLanguage?
        var tone: Tone?
        for word in words {
            if let named = Tone.named(word) {
                tone = named
            } else if let language = language(named: word) {
                target = language
            } else {
                return .unknown(word)
            }
        }
        return .change(.enter(target: target, tone: tone))
    }

    /// The output language a word names: its code ("ja", "zh-Hant"), its name in English or Chinese ("Japanese",
    /// 「日语」, 「日」), and a few common other spellings (jp, cn, 英语, 汉语, 繁体).
    static func language(named word: String) -> OutputLanguage? {
        let key = word.lowercased()
        let aliases = ["jp": "ja", "cn": "zh", "kr": "ko", "英语": "en", "汉语": "zh", "简体": "zh", "简体中文": "zh",
                       "繁体": "zh-Hant", "繁體": "zh-Hant", "zhhant": "zh-Hant", "traditional": "zh-Hant"]
        if let code = aliases[key] { return OutputLanguage(code) }
        return OutputLanguage.catalog.first { language in
            let chinese = language.name(chinese: true)
            return language.code.lowercased() == key || language.name(chinese: false).lowercased() == key
                || chinese == word || short(language) == word
                || (chinese.hasSuffix("语") || chinese.hasSuffix("文")) && String(chinese.dropLast()) == word
        }
    }

    /// The mode across the input method's text fields: on or off, and the app typed in last.
    public struct State: Equatable, Sendable {
        public private(set) var session: Session?
        /// The app of the text field that became active last (`activated`).
        public private(set) var app: String?
        private var sawApp = false

        public init() {}

        public var isOn: Bool { session != nil }

        /// Turns it on: into `target`, else the first output language that isn't `source` (the language being
        /// typed); in `tone`, else the app's. Nil, and nothing changes, when there's nothing to translate into.
        @discardableResult
        public mutating func enter(target: OutputLanguage? = nil, tone: Tone? = nil, source: Language, config: Config) -> Session? {
            guard let target = target ?? TranslateMode.target(source: source, outputs: config.outputLanguages) else { return nil }
            let session = Session(target: target, tone: tone)
            self.session = session
            return session
        }

        public mutating func leave() { session = nil }

        public enum Transition: Equatable, Sendable {
            case unchanged
            case entered(Session)
            case left(Session)
        }

        /// A text field of `app` became active. Another field of the same app changes nothing. Another app leaves
        /// the mode, unless its profile translates always (`AppProfile.translateAlways`): there it stays on, or comes
        /// on (as `enter`, with the defaults).
        public mutating func activated(app: String?, source: Language, config: Config) -> Transition {
            let same = sawApp && app?.lowercased() == self.app?.lowercased()
            (self.app, sawApp) = (app, true)
            guard !same else { return .unchanged }
            if config.profile(for: app)?.translateAlways == true {
                guard session == nil, let session = enter(source: source, config: config) else { return .unchanged }
                return .entered(session)
            }
            guard let session else { return .unchanged }
            leave()
            return .left(session)
        }
    }

    /// Tells a long press of Shift on its own from a tap (which switches the input language, `Composer`), from Shift
    /// with a letter (a capital) and from Shift with another modifier (a shortcut). Pure timing on `now` (the clock
    /// the modifier changes and the timers go by; tests set their own): Shift down alone arms it (`flagsChanged` says
    /// so), and the controller asks `poll` after `hintAfter` and after `toggleAfter`: the hint ("keep holding") is due
    /// once it has been held `hintAfter`, the toggle once `toggleAfter`, each once per press. Any key, another modifier,
    /// the release, or the pointer used meanwhile (a Shift-click) ends the press.
    public struct ShiftHold {
        public static let hintAfter: TimeInterval = 0.4
        public static let toggleAfter: TimeInterval = 0.8

        public enum Due: Equatable, Sendable {
            case hint
            case toggle
        }

        let now: () -> TimeInterval
        /// When Shift went down on its own (nil: it isn't held so).
        public private(set) var pressedAt: TimeInterval?
        private var hinted = false
        private var toggled = false

        public init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
            self.now = now
        }

        /// How long Shift has been held on its own so far (nil: it isn't).
        public var held: TimeInterval? { pressedAt.map { max(now() - $0, 0) } }

        /// A modifier changed: `keyCode` the key, `modifiers` those down now. True when Shift went down on its own
        /// (nothing else held but Caps Lock): poll after `hintAfter` and `toggleAfter`. Anything else ends a press.
        public mutating func flagsChanged(keyCode: UInt16, modifiers: KeyModifiers) -> Bool {
            let isShift = keyCode == VirtualKey.leftShift || keyCode == VirtualKey.rightShift
            if isShift, modifiers.contains(.shift), modifiers.subtracting([.shift, .capsLock]).isEmpty, pressedAt == nil {
                (pressedAt, hinted, toggled) = (now(), false, false)
                return true
            }
            cancel()  // released, the other Shift too, or another modifier: no long press of Shift alone
            return false
        }

        /// A key went down: Shift is for a capital or a shortcut.
        public mutating func keyDown() { cancel() }

        public mutating func cancel() { pressedAt = nil }

        /// What is due now (a timer went off): the hint, then the toggle, each once. `pointerUsed`: a mouse button, a
        /// drag or the wheel since Shift went down: a Shift-click, never a long press.
        public mutating func poll(pointerUsed: Bool = false) -> Due? {
            guard let held else { return nil }
            if pointerUsed {
                cancel()
                return nil
            }
            // A millisecond's leeway: a timer set for exactly that long may read a hair less on the clock.
            if held + 0.001 >= Self.toggleAfter, !toggled {
                (toggled, hinted) = (true, true)
                return .toggle
            }
            if held + 0.001 >= Self.hintAfter, !hinted {
                hinted = true
                return .hint
            }
            return nil
        }
    }

    /// What the composer says in the mode, in the interface language (the controller sets them).
    public struct Messages: Equatable, Sendable {
        /// After the draft while its translation comes.
        public var translating: String
        /// Why ⏎ sent nothing during secure input (`failed` says it, the draft kept).
        public var secureInput: String
        /// A request that failed: the draft stays, ⏎ tries again; "{reason}" is what went wrong.
        public var failedFormat: String
        /// `@mode` with a word that's neither a language nor a tone: "{word}".
        public var unknownFormat: String

        public func failed(_ reason: String) -> String {
            let line = reason.split(whereSeparator: \.isNewline).first.map(String.init) ?? reason
            return failedFormat.replacingOccurrences(of: "{reason}", with: line.count > 100 ? String(line.prefix(100)) + "…" : line)
        }

        public func unknown(_ word: String) -> String { unknownFormat.replacingOccurrences(of: "{word}", with: word) }

        public static func make(chinese: Bool) -> Messages {
            func tr(_ zh: String, _ en: String) -> String { chinese ? zh : en }
            return Messages(
                translating: tr("翻译中…", "Translating…"),
                secureInput: tr("系统安全输入已开启（密码框或锁屏），没有发给 AI", "secure input is on (a password field or the lock screen), nothing was sent"),
                failedFormat: tr("没翻译成：{reason}（⏎ 重试）", "Not translated: {reason} (⏎ to retry)"),
                unknownFormat: tr("@mode 不认识「{word}」：试试 @mode en formal、@mode 日语 口语、@mode off",
                                  "@mode doesn't know “{word}”: try @mode en formal, @mode ja casual, @mode off"))
        }

        public static let chinese = make(chinese: true)
        public static let english = make(chinese: false)
    }

    /// The lines the mode asks for: one, the text in `target` (`Prompt.system`'s format for translations).
    static func plan(for input: String, target: OutputLanguage, config: Config) -> WritingPlan {
        WritingPlan(versions: nil, translations: [target], styles: [], input: OutputLanguage(config.language(of: input)))
    }
}

extension Command {
    /// `@mode <language> [tone]`: translation mode on (`TranslateMode`); `@mode off` leaves it. Offered by the
    /// controller, not a built-in (the composer on its own has none of these).
    public static let translationMode = Command(name: "mode", kind: .terminal)
    /// `@exit`: translation mode off; offered while it's on.
    public static let exitMode = Command(name: "exit", kind: .terminal)
}

// MARK: - The request

extension Prompt {
    /// Bump when the wording of translation mode's request changes (part of its cache key). The other requests are
    /// untouched by it: this one is built on its own (`translateModeRequest`).
    public static let translateModeVersion = 1

    /// The instructions of translation mode: `system(plan)` for one translation line, then the tone.
    static func translateModeSystem(_ plan: WritingPlan, tone: TranslateMode.Tone) -> String {
        system(plan) + "\n- " + tone.rule
    }

    /// Translation mode's request: `input` into `target`, one line, in `tone`. No few-shot turns: the examples are
    /// neutral in tone and only in English and Chinese.
    public static func translateModeRequest(for input: String, target: OutputLanguage, tone: TranslateMode.Tone,
                                            config: Config) -> ConverseRequest {
        let plan = TranslateMode.plan(for: input, target: target, config: config)
        return ConverseRequest(
            system: [.init(translateModeSystem(plan, tone: tone))],
            messages: [.init(role: "user", text: input)],
            inferenceConfig: .init(maxTokens: maxTokens(for: input, lines: plan.lineCount, config: config),
                                   temperature: config.temperature))
    }
}

extension Converter {
    /// Translation mode on `input`: into `target`, in `tone` (nil: the app's, `TranslateMode.tone`), with `app`'s
    /// settings (nothing sent where it has no AI). Hidden values (`Redaction`) as for `@translate`. The translation
    /// arrives as the result's one translation line (or, if the model ignored the format, its first version).
    public func translateMode(_ input: String, target: OutputLanguage, tone: TranslateMode.Tone? = nil,
                              app: String? = nil) -> AsyncThrowingStream<ConversionUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runTranslateMode(input, target: target, tone: tone, app: app, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runTranslateMode(_ input: String, target: OutputLanguage, tone explicit: TranslateMode.Tone?, app: String?,
                                  continuation: AsyncThrowingStream<ConversionUpdate, Error>.Continuation) async throws {
        let started = ContinuousClock.now
        func elapsed() -> TimeInterval {
            let d = ContinuousClock.now - started
            return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }
        let config = try Self.settings(try loadConfig(), app: app)
        let tone = TranslateMode.tone(app: app, config: config, explicit: explicit)
        var redaction = Redaction(config.redaction)
        let sent = redaction?.hide(input) ?? input
        let hidden = redaction?.count ?? 0
        let key = "mode|\(config.activeModel)|\(Prompt.translateModeVersion)|\(target.code)|\(tone.rawValue)|\(input)"
        if let hit = cache.withLock({ $0.get(key) }) {
            continuation.yield(ConversionUpdate(result: hit, rawText: "", isFinal: true, elapsed: elapsed(),
                                                firstTokenLatency: nil, fromCache: true, hidden: hidden))
            return
        }
        let request = Prompt.translateModeRequest(for: input, target: target, tone: tone, config: config)
        let stream = client.stream(redaction?.protect(request, sent: sent) ?? request, config: config,
                                   loadCredentials: loadCredentials, loadKey: loadKey)
        var text = ""
        var firstToken: TimeInterval?
        var stopReason: String?
        for try await event in stream {
            if case let .messageStop(reason) = event { stopReason = reason }
            if case let .textDelta(delta) = event {
                text += delta
            } else if case let .textReplaced(whole) = event {
                text = whole
            } else {
                continue
            }
            if firstToken == nil { firstToken = elapsed() }
            if text.utf8.count > Self.maxOutputBytes {
                stopReason = "max_tokens"
                break
            }
        }
        try Task.checkCancellation()
        let parsed = Self.finalResult(text, stopReason: stopReason, output: nil, translations: [target])
        let final = redaction?.restore(parsed) ?? parsed
        if !final.isEmpty, stopReason != "max_tokens" { cache.withLock { $0.set(key, final) } }
        continuation.yield(ConversionUpdate(result: final, rawText: text, isFinal: true, elapsed: elapsed(),
                                            firstTokenLatency: firstToken, fromCache: false, hidden: hidden))
    }
}
