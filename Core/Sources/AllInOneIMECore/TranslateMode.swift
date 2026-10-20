import Foundation

// MARK: - Translate as You Type (a prototype)

/// Translate as You Type (「边打边译」): typed text collects into a draft, and ⏎ translates it into one language and
/// inserts the translation at once, with no candidates to pick from (⇧⏎ inserts the draft as typed). A long press of
/// Shift on its own turns it on and off (`ShiftHold`); there is no command for it. It translates into the language picked
/// last on its chip (`Chip`), at first the first output language (`target(last:outputs:)`), in a tone that follows the
/// app (`tone(app:config:)`).
/// It is one input method's state across its text fields (`State`): switching to another app leaves it (`appActivated`,
/// a text field or not), unless that app's profile translates always (`AppProfile.translateAlways`), where its field
/// keeps it on or turns it on. The composer does the typing (Composer+TranslateMode.swift),
/// the controller keeps the state and asks the model (`Converter.translateMode`, a request of its own:
/// `Prompt.translateModeRequest`).
public enum TranslateMode {
    /// The tone in `app` (`AppTone`, AppTone.swift): the first of the app's own rewrite styles, else its class's
    /// (`AppClass`). `@reply` writes in it too.
    public static func tone(app: String?, config: Config) -> AppTone {
        if let first = config.profile(for: app)?.rewriteStyles.map(RewriteStyle.resolve)?.first { return AppTone(style: first) }
        return AppClass(app: app).tone
    }

    /// The language it translates into: the one picked last (`last`, on the chip) while it is one of `outputs`, else
    /// the first of them (nil: none). The language being typed has no say: text typed in the target goes in as typed.
    public static func target(last: OutputLanguage?, outputs: [OutputLanguage]) -> OutputLanguage? {
        last.flatMap { last in outputs.first { $0 == last } } ?? outputs.first
    }

    /// One language as the chip writes it in the Chinese interface: 「英」, 「日」, 「繁」 …, else its Chinese name
    /// without 语 / 文.
    public static func short(_ language: OutputLanguage) -> String {
        let table = ["en": "英", "zh": "中", "zh-Hant": "繁", "ja": "日", "ko": "韩", "fr": "法", "de": "德", "es": "西",
                     "pt": "葡", "it": "意", "ru": "俄", "vi": "越", "th": "泰", "id": "印尼", "ar": "阿", "hi": "印"]
        if let short = table[language.code] { return short }
        var name = language.name(chinese: true)
        if name.count > 2, name.hasSuffix("语") || name.hasSuffix("文") { name.removeLast() }
        return name
    }

    /// One language as the chip writes it in the English interface: its code in capitals, "EN", "ZH", "ZH-HANT".
    public static func tag(_ language: OutputLanguage) -> String {
        language.code.uppercased()
    }

    /// One time the mode is on: what it translates into.
    public struct Session: Equatable, Sendable {
        public var target: OutputLanguage

        public init(target: OutputLanguage) {
            self.target = target
        }
    }

    /// The mode across the input method's text fields: on or off, and the app typed in last.
    public struct State: Equatable, Sendable {
        public private(set) var session: Session?
        /// The app of the text field that became active last (`activated`); nil once another app became active
        /// (`appActivated`).
        public private(set) var app: String?
        private var sawApp = false

        public init() {}

        public var isOn: Bool { session != nil }

        /// Turns it on: into `last` (the language picked last) if it's still an output language, else the first one.
        /// Nil, and nothing changes, when there's nothing to translate into.
        @discardableResult
        public mutating func enter(last: OutputLanguage?, config: Config) -> Session? {
            guard let target = TranslateMode.target(last: last, outputs: config.outputLanguages) else { return nil }
            let session = Session(target: target)
            self.session = session
            return session
        }

        public mutating func leave() { session = nil }

        /// Another language picked on the chip while it's on: it translates into that one from now on. Nil, and
        /// nothing changes, while it's off.
        @discardableResult
        public mutating func retarget(_ target: OutputLanguage) -> Session? {
            guard session != nil else { return nil }
            let session = Session(target: target)
            self.session = session
            return session
        }

        /// The settings were read again (`outputs`, the output languages now): a target no longer among them (removed in
        /// the settings) gives way at once to the first of them; with none left it leaves. True: the session changed.
        @discardableResult
        public mutating func follow(outputs: [OutputLanguage]) -> Bool {
            guard let session, !outputs.contains(session.target) else { return false }
            self.session = outputs.first.map(Session.init(target:))
            return true
        }

        public enum Transition: Equatable, Sendable {
            case unchanged
            case entered(Session)
            case left(Session)
        }

        /// A text field of `app` became active. Another field of the same app changes nothing. Another app leaves
        /// the mode, unless its profile translates always (`AppProfile.translateAlways`): there it stays on, or comes
        /// on (as `enter`, into `last` or the first output language).
        public mutating func activated(app: String?, last: OutputLanguage?, config: Config) -> Transition {
            let same = sawApp && app?.lowercased() == self.app?.lowercased()
            (self.app, sawApp) = (app, true)
            guard !same else { return .unchanged }
            if config.profile(for: app)?.translateAlways == true {
                guard session == nil, let session = enter(last: last, config: config) else { return .unchanged }
                return .entered(session)
            }
            guard let session else { return .unchanged }
            leave()
            return .left(session)
        }

        /// Another application became active (`app`, its bundle id), a text field in it or not: it leaves. Nothing
        /// changes when a field of that app became active first (`activated` has had its say), nor for an app that
        /// translates always (its field, once active, keeps it on or turns it on: `activated`). Coming back to the app
        /// left, through one that translates always too, is switching to another app again: its field doesn't count
        /// as the same app's (`activated`).
        public mutating func appActivated(_ app: String?, config: Config) -> Transition {
            guard !sawApp || app?.lowercased() != self.app?.lowercased() else { return .unchanged }
            (self.app, sawApp) = (nil, false)
            guard config.profile(for: app)?.translateAlways != true, let session else { return .unchanged }
            leave()
            return .left(session)
        }
    }

    /// The chip near the caret while it's on (「中 → 英」, "ZH → EN" in the English interface; in the input method's own
    /// panel: the app's marked text can't be clicked). A click on its source part switches the input language, as a tap
    /// of Shift does; one on its target part lists the output languages (`choices`), the target checked, and the one
    /// clicked is the target from then on.
    public struct Chip: Equatable, Sendable {
        /// The language being typed.
        public var source: Language
        /// The language it translates into.
        public var target: OutputLanguage
        /// The output languages listed under it to pick from (the target part clicked); nil: no list.
        public var choices: [OutputLanguage]?

        public init(source: Language, target: OutputLanguage, choices: [OutputLanguage]? = nil) {
            (self.source, self.target, self.choices) = (source, target, choices)
        }

        /// 「中」, the source part.
        public var sourceText: String { TranslateMode.short(OutputLanguage(source)) }
        /// 「英」, the target part.
        public var targetText: String { TranslateMode.short(target) }
        /// 「中 → 英」.
        public var text: String { sourceText + " → " + targetText }
        /// "ZH", the source part in the English interface.
        public var sourceTag: String { TranslateMode.tag(OutputLanguage(source)) }
        /// "EN", the target part in the English interface.
        public var targetTag: String { TranslateMode.tag(target) }

        /// Whether `language` is checked in the list: the target.
        public func checks(_ language: OutputLanguage) -> Bool { language == target }

        /// The language of the list's row `index` (a click on it), nil: no such row or no list.
        public func choice(at index: Int) -> OutputLanguage? {
            guard let choices, choices.indices.contains(index) else { return nil }
            return choices[index]
        }
    }

    /// Tells a long press of Shift on its own from a tap (which switches the input language, `Composer`), from Shift
    /// with a letter (a capital) and from Shift with another modifier (a shortcut). Pure timing on `now` (the clock
    /// the modifier changes and the timers go by; tests set their own): Shift going down alone, from no Shift, arms it
    /// (`flagsChanged` says so), and the controller asks `poll` after `hintAfter` and after `toggleAfter`: the hint
    /// ("keep holding") is due once it has been held `hintAfter`, the toggle once `toggleAfter`, each once per press.
    /// Any key, another modifier (fn too), the release, or the pointer used or moved meanwhile (a Shift-click, aimed)
    /// ends the press. With Sticky Keys on there is none: a Shift it latches looks held.
    public struct ShiftHold {
        public static let hintAfter: TimeInterval = 0.5
        public static let toggleAfter: TimeInterval = 1.0
        /// How far (in points) the pointer may move while Shift is held: further, it's a Shift-click being aimed.
        public static let pointerSlack: CGFloat = 5

        public enum Due: Equatable, Sendable {
            case hint
            case toggle
        }

        let now: () -> TimeInterval
        /// Where the pointer is (the controller's: the mouse, in screen points; tests set their own).
        let pointer: () -> CGPoint
        /// Whether Sticky Keys is on (the controller reads the system's setting; tests set their own).
        let stickyKeys: () -> Bool
        /// When Shift went down on its own (nil: it isn't held so).
        public private(set) var pressedAt: TimeInterval?
        /// Where the pointer was then.
        private var pressedPointer = CGPoint.zero
        /// Whether Shift was down after the last modifier change: the other Shift pressed or let go meanwhile starts
        /// no press.
        private var shiftDown = false
        private var hinted = false
        private var toggled = false

        public init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                    pointer: @escaping () -> CGPoint = ShiftHold.noPointer, stickyKeys: @escaping () -> Bool = { false }) {
            (self.now, self.pointer, self.stickyKeys) = (now, pointer, stickyKeys)
        }

        /// No pointer: always at the origin. (A function of the core's own: a public default argument written
        /// `{ .zero }` would need CGPoint's module, CoreGraphics on Apple platforms, imported here.)
        @usableFromInline static func noPointer() -> CGPoint { .zero }

        /// How long Shift has been held on its own so far (nil: it isn't).
        public var held: TimeInterval? { pressedAt.map { max(now() - $0, 0) } }

        /// A modifier changed: `keyCode` the key, `modifiers` those down now (fn as `.function`). True when Shift went
        /// down on its own (no Shift before, nothing else held but Caps Lock) and Sticky Keys is off: poll after
        /// `hintAfter` and `toggleAfter`. Anything else ends a press.
        public mutating func flagsChanged(keyCode: UInt16, modifiers: KeyModifiers) -> Bool {
            flagsChanged(key: MacKeyCodes.key(keyCode), modifiers: modifiers)
        }

        /// `flagsChanged(keyCode:modifiers:)` with the key that changed as a `Key`.
        public mutating func flagsChanged(key: Key, modifiers: Modifiers) -> Bool {
            let isShift = key.modifierKind == .shift
            let wasDown = shiftDown
            shiftDown = modifiers.contains(.shift)
            if isShift, shiftDown, !wasDown, modifiers.subtracting([.shift, .capsLock]).subtracting(.sides).isEmpty, !stickyKeys() {
                (pressedAt, pressedPointer, hinted, toggled) = (now(), pointer(), false, false)
                return true
            }
            cancel()  // released, the other Shift too, or another modifier: no long press of Shift alone
            return false
        }

        /// A key went down: Shift is for a capital or a shortcut.
        public mutating func keyDown() { cancel() }

        public mutating func cancel() { pressedAt = nil }

        /// Modifier changes may have gone unseen (another field, another app, secure input): no press, and Shift down
        /// or not as it really is (`shiftDown`), so a release missed doesn't make the next press look like the other
        /// Shift's.
        public mutating func resync(shiftDown: Bool) {
            cancel()
            self.shiftDown = shiftDown
        }

        /// What is due now (a timer went off): the hint, then the toggle, each once. `pointerUsed`: a mouse button, a
        /// drag or the wheel since Shift went down: a Shift-click, never a long press; so is the pointer moved further
        /// than `pointerSlack` since then.
        public mutating func poll(pointerUsed: Bool = false) -> Due? {
            guard let held else { return nil }
            let at = pointer()
            if pointerUsed || hypot(at.x - pressedPointer.x, at.y - pressedPointer.y) > Self.pointerSlack {
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

        public func failed(_ reason: String) -> String {
            let line = reason.split(whereSeparator: \.isNewline).first.map(String.init) ?? reason
            return failedFormat.replacingOccurrences(of: "{reason}", with: line.count > 100 ? String(line.prefix(100)) + "…" : line)
        }

        /// What the mode says in the interface language `language` (`InterfaceLanguage`), with the keys as `terms` name
        /// them.
        public static func make(language: String, terms: PlatformTerms = Platform.current.terms) -> Messages {
            let t = InterfaceWords(language: language)
            return Messages(
                translating: t.tr("翻译中…", "Translating…", key: "translateMode.translating"),
                secureInput: t.tr("系统安全输入已开启（密码框或锁屏），没有发给 AI", "secure input is on (a password field or the lock screen), nothing was sent"),
                failedFormat: t.tr("没翻译成：{reason}（\(terms.enter) 重试）", "Not translated: {reason} (\(terms.enter) to retry)"))
        }

        public static let chinese = make(language: "zh-Hans")
        public static let english = make(language: "en")
    }

    /// The lines the mode asks for: one, the text in `target` (`Prompt.system`'s format for translations).
    static func plan(for input: String, target: OutputLanguage, config: Config) -> WritingPlan {
        WritingPlan(versions: nil, translations: [target], styles: [], input: OutputLanguage(config.language(of: input)))
    }
}

// MARK: - The request

extension Prompt {
    /// Bump when the wording of Translate as You Type's request changes (part of its cache key). The other requests are
    /// untouched by it: this one is built on its own (`translateModeRequest`).
    public static let translateModeVersion = 1

    /// The instructions of Translate as You Type: `system(plan)` for one translation line, then the tone.
    static func translateModeSystem(_ plan: WritingPlan, tone: AppTone) -> String {
        system(plan) + "\n- " + tone.rule
    }

    /// Translate as You Type's request: `input` into `target`, one line, in `tone`. No few-shot turns: the examples are
    /// neutral in tone and only in English and Chinese.
    public static func translateModeRequest(for input: String, target: OutputLanguage, tone: AppTone,
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
    /// Translate as You Type on `input`: into `target`, in the app's tone (`TranslateMode.tone`), with `app`'s
    /// settings (nothing sent where it has no AI). Hidden values (`Redaction`) as for `@translate`. The translation
    /// arrives as the result's one translation line (or, if the model ignored the format, its first version).
    public func translateMode(_ input: String, target: OutputLanguage,
                              app: String? = nil) -> AsyncThrowingStream<ConversionUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.runTranslateMode(input, target: target, app: app, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runTranslateMode(_ input: String, target: OutputLanguage, app: String?,
                                  continuation: AsyncThrowingStream<ConversionUpdate, Error>.Continuation) async throws {
        let started = ContinuousClock.now
        func elapsed() -> TimeInterval {
            let d = ContinuousClock.now - started
            return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }
        let config = try Self.settings(try loadConfig(), app: app)
        let tone = TranslateMode.tone(app: app, config: config)
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
