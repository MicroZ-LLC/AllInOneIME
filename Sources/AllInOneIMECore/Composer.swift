import Foundation

/// Two-level input state machine.
///
/// Level one is a local pinyin engine (Rime): typing, selecting and committing words works like any
/// pinyin input method, and without an @ command that is all it does (commits go straight in). A
/// sentence that starts with an @ command (`Command`, e.g. "@question …") collects into a *draft*
/// (shown inline, not yet in the document) instead of being inserted, typed in Chinese or English
/// mode or dictated (hold the right Option key). The action key (`ActionKey`: Return by default, an
/// Option tap, ⌥Space, or Space on a finished draft) starts level two: pinyin still being typed is
/// converted first, then the command runs on the rest of the sentence; `@improve` sends it to the
/// model, which streams three versions in the output language and rewrites in the configured styles.
///
///     idle ─letters / voice─▶ drafting ─action key─▶ translating ─final─▶ choosing
///      ▲               │   ▲ ◀──────────── Esc / ⌫ / typing more ────────────────────────┘ │
///      └── ⇧⏎ / Esc ───────┘ ◀──────────────── Space / digits / ⏎ commit ──────────────────┘
///
/// The input controller performs the returned `Effect`s in order. Main thread only.
public final class Composer {
    public enum Phase: Equatable, Sendable {
        case idle
        /// The engine is composing, a draft is pending and/or speech is being recorded.
        case drafting
        case translating(id: Int)
        case choosing
        case failed(String)
    }

    /// Dictation (hold the right Option key).
    public enum Voice: Equatable, Sendable {
        case off
        /// Recording; `text` is what has been recognized so far.
        case listening(id: Int, text: String)
        /// The key was released; waiting for the final transcript.
        case finishing(id: Int, text: String)

        public var id: Int? {
            switch self {
            case .off: return nil
            case let .listening(id, _), let .finishing(id, _): return id
            }
        }

        public var text: String {
            switch self {
            case .off: return ""
            case let .listening(_, text), let .finishing(_, text): return text
            }
        }
    }

    public enum Effect: Equatable, Sendable {
        /// Re-render the inline marked text from `markedText` / `markedCursor`.
        case updateMarkedText
        /// Insert text into the document, replacing the marked text.
        case commit(String)
        /// Type a result into the document character by character (`typesResults`); the marked text is gone.
        case typeOut(String)
        case startConversion(input: String, id: Int)
        /// Run a `.generate` command (`@question`, `@claude`) on `input`; results arrive via `receive`.
        case startCommand(Command, input: String, id: Int)
        /// Find files and apps named like `query` (`@open`); results arrive via `receiveSearch`.
        case search(query: String, id: Int)
        /// Open a file or app (an `@open` result was picked).
        case open(path: String)
        /// Open a `link` command's web address, with the text in it, in the default browser.
        case openLink(URL)
        /// Start a Claude Code session in a terminal window with `prompt` as its first message (`@claude`).
        case runInTerminal(prompt: String)
        /// Run `argv` in a new terminal window (a custom `terminal` command).
        case launchInTerminal(argv: [String])
        /// Start `prompt` as a Claude Code background session (`@claude` with `claudeInBackground`).
        case startBackgroundAgent(prompt: String)
        /// List the background tasks (`@tasks`); they arrive via `receiveSearch`.
        case listAgents(id: Int)
        /// Show the settings window (`@settings`).
        case openSettings
        /// Save `text` to Apple Notes (`@note`); nothing is inserted.
        case saveNote(text: String)
        /// Read the reminder in `input` (`@reminder`), by the real clock; it arrives via `receiveReminder`.
        case previewReminder(input: String, id: Int)
        /// Add a confirmed reminder to Apple Reminders; `input` is the text it was read from (back in the
        /// draft if it can't be added).
        case addReminder(ReminderDraft, input: String)
        /// Run a custom `run` command's program on `input`; what it prints arrives via `receive`.
        case startRun(Command, input: String, id: Int)
        /// Send `text` to `recipient` with a send command (`@imessage`): the user confirmed it in the panel.
        case sendMessage(Recipient, text: String, command: Command)
        /// A command was run (`commandUsage` has it): keep the usage for the order of the command list.
        case commandUsed(String)
        /// A text with commands inside it (`CommandPlan`): run the inner ones, then `outer` (nil: improve)
        /// on the result; it arrives via `receive`.
        case startPlan(outer: Command?, plan: CommandPlan, id: Int)
        /// Put `text` on the clipboard (⌘C on a result, or a note that can't be inserted: `Messages.noteNotSaved`).
        case copy(String)
        /// Read the clipboard's text for the draft (⌘V) and hand it to `pasted(_:id:)`, after the key
        /// has been answered: the system may ask the user first.
        case readClipboard(id: Int)
        case cancelConversion
        /// Show or refresh the candidate panel.
        case showPanel
        case hidePanel
        /// Briefly show a status message near the caret.
        case notice(String)
        /// The input language changed (Shift): the controller types with its keyboard layout.
        case inputLanguageChanged(Language)
        /// The right Option key went down on its own: call `voiceHoldElapsed` after `delay` seconds.
        case armVoice(delay: Double)
        /// Start recording and recognizing speech in `language`.
        case startVoice(id: Int, language: Language)
        /// Stop recording and deliver the final transcript (`voiceFinished`).
        case stopVoice(id: Int)
        /// Stop recording and discard the result.
        case cancelVoice(id: Int)
    }

    public struct Response: Equatable, Sendable {
        public var effects: [Effect]
        /// False: the application should also receive the key.
        public var handled: Bool

        public init(effects: [Effect], handled: Bool) {
            self.effects = effects
            self.handled = handled
        }

        public static let passThrough = Response(effects: [], handled: false)
        public static func consumed(_ effects: [Effect] = []) -> Response { Response(effects: effects, handled: true) }
    }

    /// A level-two candidate.
    public struct Choice: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// The sentence as typed.
            case original
            /// One of the three main versions in the output language.
            case version
            /// A rewrite in the sentence's own language; the value is the style's Chinese name ("简洁", …).
            case rewrite(String)
            /// The sentence in one of several translation languages (`@translate`); the value is its code.
            case translation(String)
            /// What a `.generate` command (`@question`) wrote, or a `.run` command's program printed.
            case answer
            /// A file or app found by `@open`; picking it opens it instead of inserting anything.
            case file(path: String)
            /// The reminder read from an `@reminder` text; picking it adds it to Reminders.
            case reminder(ReminderDraft)
            /// The message a send command (`@imessage`) will send, to confirm; picking it sends it.
            case send

            public var isRewrite: Bool {
                if case .rewrite = self { return true }
                return false
            }
        }
        public var label: String
        public var kind: Kind
        public var text: String
        public var isComplete: Bool
    }

    public private(set) var phase: Phase = .idle
    /// What the composer itself says (notices near the caret, a failure without a result), in the
    /// interface language. Chinese unless the controller sets another.
    public var messages = Messages.chinese

    public struct Messages: Equatable, Sendable {
        public var notReady: String
        public var holdToTalk: String
        public var didNotHear: String
        public var chineseMode: String
        public var englishMode: String
        public var noResult: String
        public var typeAfterCommand: String
        public var nothingFound: String
        public var copied: String
        public var openedTerminal: String
        /// @claude while secure input is on: Claude Code isn't started.
        public var secureInputTerminal: String
        /// A custom terminal command was started in its own window.
        public var ranInTerminal: String
        /// `@claude` started in the background.
        public var startedInBackground: String
        /// A custom terminal command while secure input is on: nothing is started.
        public var secureInputCommand: String
        /// ⌘V in a draft with more on the clipboard than `Composer.maxPasteLength`.
        public var pasteTooLong: String
        /// ⌘V in a draft with no text on the clipboard (or reading it isn't allowed).
        public var nothingToPaste: String
        /// `@reminder` with only a time ("@reminder 明天下午3点"): nothing to be reminded of.
        public var reminderWithoutTitle: String
        /// ⌘V in an `@note` draft with more on the clipboard than `Composer.maxNoteLength`.
        public var noteTooLong: String
        /// A `link` command's text is longer than `LinkTemplate.maxInputLength`.
        public var linkTooLong: String
        /// `@py` / `@js` code that printed nothing and ended without a value.
        public var noOutput: String
        /// A note with line breaks was left unsaved (the text field lost focus, ⇧⏎): it isn't inserted, its text
        /// is on the clipboard instead.
        public var noteNotSaved: String
        /// ⏎ on a send command (`@imessage`) before a recipient was picked.
        public var pickRecipient = "先选收件人：↑↓ 选择，⏎ / Tab 确定（也可以直接输入手机号或邮箱）"
        /// `@py` (or another command that runs code) in pasted or dictated text: left as text.
        public var codeNotRun = "粘贴或语音来的文字里的 @py、@js 等没有运行，当作文字"
        /// The notices of a switch to French or Korean (Shift).
        public var frenchMode = "法"
        public var koreanMode = "韩"
        public var hindiMode = "印"

        /// The notice of a switch of input language.
        public func mode(_ language: Language) -> String {
            switch language {
            case .chinese: return chineseMode
            case .english: return englishMode
            case .french: return frenchMode
            case .korean: return koreanMode
            case .hindi: return hindiMode
            }
        }

        public static let chinese = Messages(
            notReady: "词库准备中，稍候可用", holdToTalk: "按住右 ⌥ 说话", didNotHear: "没听清，再说一次",
            chineseMode: "中", englishMode: "英", noResult: "没有得到结果",
            typeAfterCommand: "在命令后面写上内容", nothingFound: "没有找到", copied: "已复制",
            openedTerminal: "已在终端打开 Claude Code",
            secureInputTerminal: "系统安全输入已开启（密码框或锁屏），没有打开 Claude Code",
            ranInTerminal: "已在终端运行",
            startedInBackground: "已在后台开始，做完会通知你；@tasks 查看",
            secureInputCommand: "系统安全输入已开启（密码框或锁屏），没有运行命令",
            pasteTooLong: "剪贴板里的文字太长：最多 \(Composer.maxPasteLength) 字",
            nothingToPaste: "剪贴板里没有能用的文字",
            reminderWithoutTitle: "写上要提醒的事，比如「明天下午3点给张三打电话」",
            noteTooLong: "剪贴板里的文字太长：最多 \(Composer.maxNoteLength) 字",
            linkTooLong: "文字太长，放不进链接：最多 \(LinkTemplate.maxInputLength) 字",
            noOutput: "代码没有输出：最后写一个表达式，或者把结果打印出来",
            noteNotSaved: "笔记还没存，原文已复制到剪贴板")
        public static let english = Messages(
            notReady: "Loading the dictionaries, one moment", holdToTalk: "Hold right ⌥ to talk",
            didNotHear: "Didn't catch that, try again", chineseMode: "Chinese", englishMode: "English",
            noResult: "No result",
            typeAfterCommand: "Type something after the command", nothingFound: "Nothing found", copied: "Copied",
            openedTerminal: "Opened Claude Code in Terminal",
            secureInputTerminal: "Secure input is on (a password field or the lock screen): Claude Code was not opened",
            ranInTerminal: "Running in Terminal",
            startedInBackground: "Started in the background; you'll be notified when it's done (@tasks)",
            secureInputCommand: "Secure input is on (a password field or the lock screen): the command was not run",
            pasteTooLong: "The clipboard text is too long: \(Composer.maxPasteLength) characters at most",
            nothingToPaste: "No text on the clipboard to use",
            reminderWithoutTitle: "Write what to be reminded of, e.g. “call Bob tomorrow at 3pm”",
            noteTooLong: "The clipboard text is too long: \(Composer.maxNoteLength) characters at most",
            linkTooLong: "Too long for a link: \(LinkTemplate.maxInputLength) characters at most",
            noOutput: "The code printed nothing: end it with an expression, or print the result",
            noteNotSaved: "The note wasn't saved; its text is on the clipboard",
            pickRecipient: "Pick a recipient first: ↑↓ choose, ⏎ / Tab confirm (or type a phone number or email)",
            codeNotRun: "@py, @js and the like in pasted or dictated text weren't run: kept as text",
            frenchMode: "French", koreanMode: "Korean", hindiMode: "Hindi")
    }
    /// The command of the request in level two (nil otherwise).
    public private(set) var activeCommand: Command?
    /// The commands "@" offers: the built-in ones and the user's (`Command.catalog`).
    public var commands: [Command] = Command.builtins
    /// How much each command is used: the list shows the most used first (set by the controller,
    /// shared by its text fields).
    public var commandUsage = CommandUsage()
    /// `@claude` starts a background session instead of a Terminal window.
    public var claudeInBackground = false
    /// A result picked in level two is typed out character by character (`Config.typeOut`), not inserted at once.
    public var typesResults = false
    /// The reminder read from an `@reminder` text (`receiveReminder`), shown to confirm.
    public private(set) var pendingReminder: ReminderDraft?
    /// Files and apps found for `@open`.
    public private(set) var searchResults: [SearchResult] = []
    /// Results for the `@open` text as it is typed (`liveQuery`), and the highlighted one.
    public private(set) var liveResults: [SearchResult] = []
    private var liveResultsQuery: String?
    public private(set) var liveHighlight = 0
    /// ↑↓ moved the highlight among these results (back to the first counts too): it opens (`opensLiveResult`).
    /// Reset with the highlight when the results or the text change.
    private var liveHighlightMoved = false
    /// A send command's recipient (`@imessage`), once picked; until then the text after the command
    /// finds one (`recipientQuery`).
    public private(set) var messageRecipient: Recipient?
    /// Recipients found for `recipientQuery` (`receiveRecipients`), what the panel says about them (no
    /// access to Contacts …), and the highlighted one.
    public private(set) var recipientResults: [Recipient] = []
    public private(set) var recipientNote: String?
    private var recipientResultsQuery: String?
    public private(set) var recipientHighlight = 0
    /// A command that types Latin letters (`@open`, code) switched the engine to them; Chinese comes back after.
    private var restoreChineseAfterOpen = false
    /// Letters were switched on for a command inside the text, whose argument starts at this offset:
    /// Chinese comes back at the first space after it.
    private var nestedLatinFrom: Int?
    /// Highlighted row of the command palette.
    private var paletteHighlight = 0 {
        didSet { if paletteHighlight == 0 { paletteTop = 0 } }
    }
    /// The first command the list shows; it scrolls to keep the highlight in view.
    private var paletteTop = 0
    /// How many commands the list shows at once (the rest scroll into view).
    public static let paletteRows = 5
    /// The ⌘V whose clipboard text the draft is waiting for (`pasted`), and the last one's id.
    private var pendingPaste: Int?
    private var pasteCounter = 0
    /// Whether ⌘V in a draft takes the clipboard into it. False in apps that paste on ⌘V themselves
    /// whatever the input method does (terminals): the text would be pasted twice. There ⌃V takes the
    /// clipboard instead.
    public var pastesIntoDraft = true
    /// Whether secure input is on anywhere (set by the input controller). Nothing is sent to a model
    /// then: a terminal command doesn't start Claude Code, and its text stays in the draft. (The other
    /// commands are refused by the controller, which sends their requests; `@note` and `@reminder`
    /// stay on this Mac and go ahead.)
    public var secureInputActive: () -> Bool = { false }
    /// Confirmed text waiting for level two: an @ command and the sentence after it.
    public private(set) var draft = "" {
        // A pick among the `@open` results as you type was made for the text as it was: once that changes, the
        // highlight starts at the first again (`opensLiveResult`).
        didSet {
            if draft != oldValue { resetLiveHighlight() }
            if draft.isEmpty { draftHasOutsideText = false }
        }
    }
    /// Text the user didn't type is in the draft (pasted, dictated, a draft given back): a command in it that
    /// runs code (`Command.runsCode`) stays text. Something copied from a web page may hide "@py …".
    private var draftHasOutsideText = false
    /// Last known state of the level-one engine.
    public private(set) var engineState = EngineSnapshot.empty
    public private(set) var result = ConversionResult.empty
    public private(set) var voice = Voice.off
    /// The input languages on (`Config.inputLanguages`): with one, a tap of Shift doesn't switch.
    public var inputLanguages: [Language] = [.chinese, .english]
    /// Holding the right Option key records speech.
    public var voiceEnabled: Bool
    /// The key that runs the @ command at the start of the draft.
    public var actionKey: ActionKey
    /// The action key was pressed during dictation: the sentence goes once the transcript is final.
    public private(set) var actsAfterVoice = false
    /// Level one. Nil while the dictionaries are being prepared; keys then go to the application.
    /// Level one: librime (or `LatinEngine` without the Chinese pack), as the controller sets it; in Hindi,
    /// `HindiEngine` in its place.
    public var engine: PinyinEngine? {
        get { hindiActive && primaryEngine != nil ? hindiEngine ?? primaryEngine : primaryEngine }
        set {
            primaryEngine = newValue
            engineState = engine?.snapshot() ?? .empty
        }
    }
    /// The engine the controller set (`engine`), also while Hindi's is in its place: what to check for which
    /// engine level one has (`LatinEngine` without the Chinese pack).
    public private(set) var primaryEngine: PinyinEngine?
    /// Hindi's engine, on the Hindi pack's tables (`hindiTables`, set by the controller once the pack is installed).
    private var hindiEngine: HindiEngine?
    public var hindiTables: HindiTables? {
        didSet {
            guard hindiTables != oldValue else { return }
            hindiEngine = hindiTables.map(HindiEngine.init(tables:))
            // The pack deleted while Hindi was typed: on in another of the user's languages (not Chinese they
            // may not have).
            if hindiEngine == nil, hindiActive { enter(fallbackLanguage(for: .hindi)) }
            engineState = engine?.snapshot() ?? .empty
        }
    }
    /// Hindi is the input language (its engine in place of librime).
    private var hindiActive = false

    private var highlightOverride: Int?
    private var requestCounter = 0
    private var voiceCounter = 0
    /// The right Option key is down on its own and dictation hasn't started yet.
    private var voiceArmed = false
    /// Whether the voice key's events tell left and right Option apart (device bits).
    private var voiceKeySided = false
    /// When Shift went down with no other key since (nil once any key is pressed).
    private var shiftPressedAt: TimeInterval?
    /// Whether a mouse button, a drag or the scroll wheel was used in the last `seconds`: a Shift-click
    /// or ⌥-click is no tap of the key (the mouse never reaches the input method). Set by the app.
    public var pointerUsedWithin: (_ seconds: TimeInterval) -> Bool = { _ in false }
    /// Which Option key went down on its own, and when (nil once anything else happens).
    private var optionPressed: (keyCode: UInt16, at: TimeInterval)?
    private var warnedNotReady = false
    /// The last thing added to the draft was a transcript (Space then runs the command right away).
    private var draftEndsWithVoice = false

    /// The accent of a dead key (⌥E: "´"), shown at the cursor until the next key composes it (`KeyEvent.composed`).
    public private(set) var pendingAccent: String?
    /// Korean being typed: the syllable shown at the cursor until it's done (`HangulComposer`).
    public private(set) var hangul = HangulComposer(tables: .none)
    /// The Korean pack's tables (set by the controller once the pack is installed).
    public var hangulTables: HangulTables? {
        didSet {
            guard hangulTables != oldValue else { return }
            hangul = HangulComposer(tables: hangulTables ?? .none)
            if hangulTables == nil, inputLanguage == .korean { enter(fallbackLanguage(for: .korean)) }  // the pack deleted
        }
    }
    /// The language typed while the engine is in its ASCII mode: English, French or Korean (Chinese is pinyin).
    public private(set) var asciiLanguage: Language = .english

    /// The input language in effect.
    public var inputLanguage: Language { engineState.isAsciiMode ? asciiLanguage : nativeLanguage }

    /// What to type in once `language`'s pack is gone: the first other input language (the default, normally).
    private func fallbackLanguage(for language: Language) -> Language {
        inputLanguages.first { $0 != language } ?? .english
    }

    /// The language of the engine in place when it isn't in its ASCII mode.
    private var nativeLanguage: Language { hindiActive ? .hindi : .chinese }

    public init(engine: PinyinEngine? = nil, voiceEnabled: Bool = true, actionKey: ActionKey = .enter) {
        primaryEngine = engine
        self.voiceEnabled = voiceEnabled
        self.actionKey = actionKey
        engineState = engine?.snapshot() ?? .empty
    }

    // MARK: - State for rendering

    public var isComposing: Bool { phase != .idle }

    public var isLevelTwo: Bool {
        switch phase {
        case .translating, .choosing, .failed: return true
        case .idle, .drafting: return false
        }
    }

    /// A draft still free of Chinese text, e.g. "@improve this is …" typed in English mode: a shortcut
    /// (⌘A, ⌘⏎ …) inserts it as typed and then reaches the application; ⌘V instead takes the
    /// clipboard's text into the draft (`pasted`).
    public var isLatinDraft: Bool { !draft.isEmpty && !draft.containsHan }

    /// Whether Space on the draft starts level two now. Only with the `space` action key (in English
    /// mode the first Space after a word is a space; right after dictation one Space is enough);
    /// otherwise Space in a draft is a space.
    public var spaceActs: Bool {
        actionKey == .space && (!engineState.isAsciiMode || draft.hasSuffix(" ") || draftEndsWithVoice)
    }

    /// Inline text: the draft followed by the engine's composition and any speech being recognized.
    public var markedText: String {
        if isLevelTwo { return shownDraft }
        // What is being typed or said goes in at the cursor; what follows it (`tail`, shown the same) after.
        let shown = shownDraft, after = tail.count
        return String(shown.dropLast(after)) + (engineState.isComposing ? engineState.preedit : "") + (pendingAccent ?? "") + hangul.preedit
            + appendix(voice.text) + String(shown.suffix(after))
    }

    /// Caret position in `markedText`, in Characters.
    public var markedCursor: Int {
        let before = shownDraft.count - tail.count + (pendingAccent?.count ?? 0) + hangul.preedit.count
        if voice != .off { return before + appendix(voice.text).count }
        guard !isLevelTwo, engineState.isComposing else { return before }
        return before + min(max(engineState.cursor, 0), engineState.preedit.count)
    }

    // MARK: The cursor in a command's text

    /// What follows the cursor in the draft, when ← moved it back into the text after the command; typing,
    /// pinyin, ⌫, a paste and speech then go in there. Replaced wholesale (a command picked, cleared), the
    /// draft no longer ends with it and the cursor is back at the end (`tail`).
    private var cursorTail = ""

    /// `cursorTail` while it still holds: the draft ends with it, and the cursor stays after the command.
    private var tail: String {
        guard !cursorTail.isEmpty, !isLevelTwo, draft.hasSuffix(cursorTail),
              draft.count - cursorTail.count >= textStart else { return "" }
        return cursorTail
    }

    /// Where the text after the command starts (the cursor never goes into "@question ").
    private var textStart: Int {
        guard let command = draftCommand else { return 0 }
        let header = "@\(command.name) "
        return draft.hasPrefix(header) ? header.count : 0
    }

    /// The draft before the cursor.
    private var beforeCursor: Substring { draft.dropLast(tail.count) }

    /// `text` into the draft at the cursor.
    private func insertIntoDraft(_ text: String) {
        let after = tail
        draft = String(draft.dropLast(after.count)) + text + after
        cursorTail = after
    }

    /// ⌫ in the text: the character before the cursor (none before the command's text).
    private func deleteBeforeCursor() {
        let after = tail
        guard draft.count - after.count > (after.isEmpty ? 0 : textStart) else { return }
        draft = String(draft.dropLast(after.count).dropLast()) + after
        cursorTail = after
    }

    /// ← → (⌘ or Home/End: to the start or end of the text, ⌥: a word at a time).
    private func moveCursor(_ event: KeyEvent) -> [Effect] {
        let after = tail, start = textStart
        let position = draft.count - after.count
        let chars = Array(draft)
        let toEdge = event.modifiers.contains(.command) || event.keyCode == VirtualKey.home || event.keyCode == VirtualKey.end
        let wordwise = event.modifiers.contains(.option)
        let left = event.keyCode == VirtualKey.left || event.keyCode == VirtualKey.home
        var target = position
        if toEdge {
            target = left ? start : chars.count
        } else if left {
            target = max(start, position - 1)
            if wordwise {
                while target > start, chars[target - 1] == " " { target -= 1 }
                while target > start, chars[target - 1] != " " { target -= 1 }
            }
        } else {
            target = min(chars.count, position + 1)
            if wordwise {
                while target < chars.count, chars[target] == " " { target += 1 }
                while target < chars.count, chars[target] != " " { target += 1 }
            }
        }
        cursorTail = String(chars[target...])
        return [.updateMarkedText]
    }

    /// The draft as the app shows it while it is typed: commands without their "@" (`improve › 你好` for
    /// "@improve 你好", `imp` while "@imp" picks a command) and any other "@" in the draft full-width
    /// ("＠bob"). Apps like Slack turn an "@…" being typed into a mention and take the text
    /// out of the composition. A lone "@" (maybe a mention) stays; what runs and what is inserted are
    /// the draft as typed.
    public var shownDraft: String {
        guard draft.contains("@") else { return draft }
        let chars = Array(draft)
        let names = Set(commands.map(\.name))
        let paletteAt = palette.map { draft.distance(from: draft.startIndex, to: $0.at) }
        let pickingCommand = palette.map { !$0.query.isEmpty && !paletteMatches.isEmpty } ?? false
        let inCommand = draftCommand != nil
        // In a note, a reminder, a search, code or a terminal command, an "@name" after the command is just text:
        // none runs there (`@py x = "@stock AAPL"`).
        let asTyped = takesTextAsTyped
        var out = ""
        var i = 0
        while i < chars.count {
            guard chars[i] == "@" else {
                // A note keeps its lines (`pasted`); the draft is shown on one line.
                if chars[i].isNewline { out += Self.lineBreak } else { out.append(chars[i]) }
                i += 1
                continue
            }
            var j = i + 1
            while j < chars.count, chars[j].isASCII, chars[j].isLetter { j += 1 }
            let name = String(chars[(i + 1)..<j]).lowercased()
            let afterWord = i > 0 && chars[i - 1].isASCII && (chars[i - 1].isLetter || chars[i - 1].isNumber)
            if !afterWord, i == 0 || !asTyped, names.contains(name), j < chars.count, chars[j] == " " || "「“\"".contains(chars[j]) {
                out += String(chars[(i + 1)..<j]) + " › "  // a chosen command
                i = chars[j] == " " ? j + 1 : j
            } else if i == paletteAt, pickingCommand {
                out += String(chars[(i + 1)..<j])  // its name being typed
                i = j
            } else if chars.count == 1 || !inCommand && i == 0 {
                out.append("@")
                i += 1
            } else {
                out.append("＠")
                i += 1
            }
        }
        // A send command's recipient, picked: "imessage › 张三 › 你好".
        if let recipient = messageRecipient, let command = draftCommand, out.hasPrefix(command.name + " › ") {
            out.insert(contentsOf: recipient.displayName + " › ", at: out.index(out.startIndex, offsetBy: command.name.count + 3))
        }
        return out
    }

    /// Level-two rows: "0" the sentence as typed, "1"–"3" the versions in the output language, then
    /// the rewrites in the configured styles, numbered on from 4. A rewrite is shown once it has fully
    /// arrived, and only if it changes the wording (not just punctuation) and repeats no other row.
    /// For `@question` / `@claude`: "0" the text sent and "1" the answer; for `@open`: the files found;
    /// for `@reminder`: "1" the reminder to add.
    public var choices: [Choice] {
        guard isLevelTwo else { return [] }
        switch activeCommand?.kind {
        case .search?, .agents?:
            return searchResults.prefix(9).enumerated().map {
                Choice(label: String($0.offset + 1), kind: .file(path: $0.element.path), text: $0.element.name,
                       isComplete: true)
            }
        case .reminder?:
            return pendingReminder.map { [Choice(label: "1", kind: .reminder($0), text: $0.title, isComplete: true)] } ?? []
        case .generate?, .run?, .link?:
            var out = [Choice(label: "0", kind: .original, text: sentText, isComplete: true)]
            if let line = result.versions.first {
                out.append(Choice(label: "1", kind: .answer, text: line.text, isComplete: line.isComplete))
            }
            return out
        case .message?:
            guard let line = result.versions.first, !line.text.isEmpty else { return [] }
            return [Choice(label: "⏎", kind: .send, text: line.text, isComplete: line.isComplete)]
        case .convert?, .terminal?, .settings?, .note?, nil:
            break
        }
        let original = sentText
        var out = [Choice(label: "0", kind: .original, text: original, isComplete: true)]
        var shownWordings: Set<String> = [original.wordingKey]
        var label = 1
        for line in result.versions {
            // A version that only re-punctuates the original or another version adds nothing.
            if line.isComplete, !shownWordings.insert(line.text.wordingKey).inserted { continue }
            out.append(Choice(label: String(label), kind: .version, text: line.text, isComplete: line.isComplete))
            label += 1
        }
        for translation in result.translations where label <= 9 {
            out.append(Choice(label: String(label), kind: .translation(translation.language.code), text: translation.line.text,
                              isComplete: translation.line.isComplete))
            label += 1
        }
        var next = max(4, label)
        for rewrite in result.rewrites where rewrite.line.isComplete && next <= 9 {
            let key = rewrite.line.text.wordingKey
            guard !key.isEmpty, shownWordings.insert(key).inserted else { continue }
            out.append(Choice(label: String(next), kind: .rewrite(rewrite.style), text: rewrite.line.text, isComplete: true))
            next += 1
        }
        return out
    }

    /// Index into `choices`. Defaults to the first main version, even before it has streamed in,
    /// so an early Space or Return never commits something else by accident.
    public var highlighted: Int {
        let all = choices
        if let highlightOverride { return all.isEmpty ? 0 : min(highlightOverride, all.count - 1) }
        if activeCommand?.kind == .search || activeCommand?.kind == .agents || activeCommand?.kind == .reminder
            || activeCommand?.kind == .message { return 0 }
        if case .translating = phase { return 1 }
        // The first version, answer or translation (`@translate` into several languages has no versions).
        if let i = all.firstIndex(where: {
            if case .translation = $0.kind { return true }
            return $0.kind == .version || $0.kind == .answer
        }) { return i }
        if let i = all.firstIndex(where: { $0.kind.isRewrite }) { return i }
        return 0
    }

    /// What level two works on: the text after the draft's command ("@question 量子计算" → "量子计算").
    public var sentText: String {
        Command.parse(draft, in: commands).map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) } ?? draft
    }

    /// The command at the start of the draft, once its name is complete ("@question …").
    public var draftCommand: Command? { Command.parse(draft, in: commands)?.command }

    /// While a command name is typed after "@" at the start of the draft: the letters so far.
    public var paletteQuery: String? { palette?.query }

    /// The "@letters" being typed: at the start of the draft, or (`nested`) inside a command's text
    /// (`@reply 告诉他 @st`, not inside a word), where the commands that can run inside a text are offered.
    /// Not inside a note, a reminder, a search, code or a terminal command: they take their text as typed (`takesTextAsTyped`).
    private var palette: (query: String, nested: Bool, at: String.Index)? {
        guard !isLevelTwo, voice == .off, !engineState.isComposing, tail.isEmpty, let at = draft.lastIndex(of: "@") else { return nil }
        let query = draft[draft.index(after: at)...]
        guard query.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        if at == draft.startIndex { return (String(query), false, at) }
        let before = draft[draft.index(before: at)]
        guard draftCommand != nil, !takesTextAsTyped, !(before.isASCII && (before.isLetter || before.isNumber)) else { return nil }
        return (String(query), true, at)
    }

    /// The draft is a note, a reminder, a search, code (`@py`, `@js`) or a terminal command (`@claude`, a custom
    /// one): no command inside its text runs first (`startAction`; Terminal and Claude Code get the text as typed),
    /// so an "@" in it is just text (no list to pick a command from, none shown as picked).
    private var takesTextAsTyped: Bool {
        guard let command = draftCommand else { return false }
        return command.kind == .note || command.kind == .reminder || command.kind == .search || command.kind == .terminal
            || command.isCode
    }

    /// The commands the list can offer: all of them at the start, inside a text the ones that run there,
    /// and inside `@translate` `@improve` (or the other way round): written together, one request does both.
    private var paletteCommands: [Command] {
        guard palette?.nested == true else { return commands }
        return commands.filter { CommandPlan.canBeInner($0) || pairsWithDraft($0) }
    }

    private func pairsWithDraft(_ command: Command) -> Bool {
        guard let draftCommand, draftCommand.kind == .convert, command.kind == .convert, command != draftCommand else { return false }
        return !draft.components(separatedBy: " ").contains("@" + command.name)
    }

    /// Commands offered for `paletteQuery`, and the highlighted one.
    /// All of them, the most used first, or what matches the letters (`Command.palette`); the list shows
    /// `paletteRows` at a time from `paletteFirstVisible`.
    public var paletteMatches: [Command] {
        paletteQuery.map { Command.palette($0, in: paletteCommands, usage: commandUsage, limit: .max) } ?? []
    }
    public var paletteHighlighted: Int { min(paletteHighlight, max(paletteMatches.count - 1, 0)) }

    /// The first row shown: where the list was scrolled to, moved just enough to show the highlight.
    public var paletteFirstVisible: Int {
        let count = paletteMatches.count, highlight = paletteHighlighted, rows = Self.paletteRows
        var top = min(paletteTop, max(count - rows, 0))
        if highlight < top { top = highlight } else if highlight >= top + rows { top = highlight - rows + 1 }
        return max(top, 0)
    }

    /// The commands shown now (digits 1–5 pick them).
    public var paletteVisible: ArraySlice<Command> {
        let all = paletteMatches, first = paletteFirstVisible
        return all[first..<min(first + Self.paletteRows, all.count)]
    }

    /// Moves the highlight by `steps` (arrows, the scroll wheel), around the ends, scrolling with it.
    private func movePaletteHighlight(by steps: Int) {
        let count = paletteMatches.count
        guard count > 0 else { return }
        paletteHighlight = ((paletteHighlighted + steps) % count + count) % count
        paletteTop = paletteFirstVisible
    }

    /// The scroll wheel over the list: the highlight moves (the list scrolls with it).
    public func scrollPalette(by steps: Int) -> [Effect] {
        guard paletteQuery != nil, steps != 0, !paletteMatches.isEmpty else { return [] }
        let count = paletteMatches.count
        // Not around the ends: the wheel stops at the first and the last.
        let target = min(max(paletteHighlighted + steps, 0), count - 1)
        movePaletteHighlight(by: target - paletteHighlighted)
        return [.showPanel]
    }

    /// The `@open` text while it is typed, for results as you type (`receiveLive`).
    public var liveQuery: String? {
        guard !isLevelTwo, voice == .off, !engineState.isComposing, draftCommand == .open else { return nil }
        let query = sentText
        return query.isEmpty ? nil : query
    }

    /// The results as you type that belong to the current `liveQuery`.
    public var currentLiveResults: [SearchResult] {
        liveQuery != nil && liveResultsQuery == liveQuery ? liveResults : []
    }

    /// Whether the action key opens the highlighted result as you type. Not the first when every row is a
    /// content match: nothing is named like the text, so the first may have little to do with it, and the
    /// key lists them to choose from instead, as before the results arrive. One picked with ↑↓ opens, the
    /// first too (↓ then ↑, or round from the last): what the user moved to, not where the highlight started.
    public var opensLiveResult: Bool {
        let live = currentLiveResults
        return live.indices.contains(liveHighlight) && (liveHighlightMoved || !live.allSatisfy(\.matchedContent))
    }

    /// The text after a send command (`@imessage zs`) while no recipient is picked: what finds one
    /// (`receiveRecipients`). Empty right after the command: the recent recipients.
    public var recipientQuery: String? {
        guard !isLevelTwo, voice == .off, !engineState.isComposing, pickingRecipient else { return nil }
        return sentText
    }

    /// A send command without its recipient yet.
    private var pickingRecipient: Bool { messageRecipient == nil && draftCommand?.kind == .message }

    /// The recipients found that belong to the current `recipientQuery`.
    public var currentRecipients: [Recipient] {
        recipientQuery != nil && recipientResultsQuery == recipientQuery ? recipientResults : []
    }

    /// Recipients for `query` (`recipientQuery`) and a note for the panel (nil: none): ↑↓ pick, Tab, ⏎,
    /// a digit or a click chooses one.
    public func receiveRecipients(_ results: [Recipient], note: String? = nil, for query: String) -> [Effect] {
        guard query == recipientQuery else { return [] }
        recipientResults = results
        recipientNote = note
        recipientResultsQuery = query
        recipientHighlight = 0
        return [.showPanel]
    }

    /// Picks a found recipient: the text typed to find them goes, and the message follows (in the input
    /// mode from before the command).
    private func pickRecipient(at index: Int) -> [Effect] {
        let found = currentRecipients
        guard found.indices.contains(index), let command = draftCommand else { return [] }
        messageRecipient = found[index]
        draft = "@\(command.name) "
        clearRecipientResults()
        setLevelOnePhase()
        return [.updateMarkedText, .showPanel]
    }

    private func clearRecipientResults() {
        recipientResults = []
        recipientNote = nil
        recipientResultsQuery = nil
        recipientHighlight = 0
    }

    /// Keys while a recipient is picked: ↑↓ move, Tab picks, so do digits after a name (a number
    /// being typed takes them). Nil: the key acts as usual.
    private func handleRecipientKey(_ event: KeyEvent) -> Response? {
        guard let query = recipientQuery, event.modifiers.subtracting(.capsLock).isEmpty else { return nil }
        let found = currentRecipients
        guard !found.isEmpty else { return nil }
        switch event.keyCode {
        case VirtualKey.up, VirtualKey.down:
            recipientHighlight = (recipientHighlight + (event.keyCode == VirtualKey.up ? -1 : 1) + found.count) % found.count
            return .consumed([.showPanel])
        case VirtualKey.tab:
            return .consumed(pickRecipient(at: recipientHighlight))
        default:
            break
        }
        if let text = event.printableText, text.count == 1, let n = text.first?.wholeNumberValue, n >= 1, found.indices.contains(n - 1),
           !query.isEmpty, !query.contains(where: { $0.isNumber }) {
            return .consumed(pickRecipient(at: n - 1))
        }
        return nil
    }

    /// Files and apps for `query` (`liveQuery`): ↑↓ pick, Tab completes the path, the action key opens
    /// (`opensLiveResult`).
    public func receiveLive(_ results: [SearchResult], for query: String) -> [Effect] {
        guard query == liveQuery else { return [] }
        liveResults = results
        liveResultsQuery = query
        resetLiveHighlight()
        return [.showPanel]
    }

    /// The highlight back on the first result as you type, where it starts rather than moved to.
    private func resetLiveHighlight() {
        liveHighlight = 0
        liveHighlightMoved = false
    }

    /// What ⌘C copies: the highlighted result (a file's path), if one is shown.
    public var copyableText: String? {
        if isLevelTwo {
            let all = choices
            guard all.indices.contains(highlighted), all[highlighted].isComplete, !all[highlighted].text.isEmpty else { return nil }
            if case let .file(path) = all[highlighted].kind {
                return searchResults.first { $0.path == path }?.detail ?? path  // a task: its reply
            }
            return all[highlighted].text
        }
        let live = currentLiveResults
        return live.indices.contains(liveHighlight) ? live[liveHighlight].path : nil
    }

    /// Whether the candidate panel has something to show.
    public var wantsPanel: Bool {
        if isLevelTwo || voice != .off { return true }
        if engineState.isComposing { return !engineState.candidates.isEmpty }
        return !draft.isEmpty
    }

    // MARK: - Keys

    public func handleKeyDown(_ event: KeyEvent) -> Response {
        if let response = handleHangulKey(event) { return response }
        // Any other key finishes the syllable being typed first, then does what it does.
        let finished = finishHangul()
        let response = handleOtherKeyDown(event)
        return finished.isEmpty ? response : Response(effects: finished + response.effects, handled: response.handled)
    }

    /// Whether letter keys type Hangul now: in Korean, outside a command's name, code and `@open`'s letters (also
    /// code inside the text, until its argument is typed: `nestedLatinFrom`).
    private var typesHangul: Bool {
        inputLanguage == .korean && !isLevelTwo && voice == .off && engine != nil && palette == nil
            && draftCommand?.typesLatin != true && nestedLatinFrom == nil && !(draft.hasPrefix("@") && draftCommand == nil)
    }

    /// A letter key in Korean: its jamo joins the syllable being typed, and a finished one goes in. ⌫ takes
    /// back a key of the syllable. Nil for every other key.
    private func handleHangulKey(_ event: KeyEvent) -> Response? {
        guard typesHangul else { return nil }
        let modifiers = event.modifiers.subtracting(.capsLock)
        let back = event.keyCode == VirtualKey.delete && modifiers.isEmpty && !hangul.isEmpty
        let jamo = modifiers.isSubset(of: .shift) ? hangul.tables.jamo(keyCode: event.keyCode, shift: modifiers.contains(.shift)) : nil
        guard back || jamo != nil else { return nil }
        shiftPressedAt = nil
        optionPressed = nil
        voiceArmed = false
        var effects: [Effect] = []
        if back {
            _ = hangul.backspace()
        } else if let jamo {
            let done = hangul.feed(jamo)
            if !done.isEmpty { effects += typeFinished(done) }
        }
        setLevelOnePhase()  // a syllable being typed is a composition (`isComposing`)
        return .consumed(effects + [.updateMarkedText] + (draft.isEmpty ? [] : [.showPanel]))
    }

    /// Finishes the syllable being typed (another key, a switch of language, the field lost).
    private func finishHangul() -> [Effect] {
        guard !hangul.isEmpty else { return [] }
        let text = hangul.flush()
        let effects = typeFinished(text)
        setLevelOnePhase()
        return effects + [.updateMarkedText]
    }

    /// Finished Hangul: into the command's text, or into the document.
    private func typeFinished(_ text: String) -> [Effect] {
        guard !draft.isEmpty else { return [.commit(text)] }
        appendTyped(text)
        setLevelOnePhase()
        return []
    }

    private func handleOtherKeyDown(_ event: KeyEvent) -> Response {
        shiftPressedAt = nil
        optionPressed = nil  // ⌥ with a key is a shortcut, not a tap
        voiceArmed = false  // a key with right ⌥ down is an ⌥ shortcut, not dictation
        // A held key goes no further than its first press did: holding ⏎ runs a command, it doesn't then
        // also insert the result, or send the message it shows to confirm.
        if event.isRepeat, isLevelTwo || !draft.isEmpty,
           [VirtualKey.returnKey, VirtualKey.keypadEnter, VirtualKey.space, VirtualKey.tab].contains(event.keyCode)
            || isLevelTwo && event.printableText?.first?.isNumber == true {
            return .consumed()
        }
        if isActionKey(event), let effects = actionKeyPressed() {
            draftEndsWithVoice = false
            return .consumed(effects)
        }
        let afterVoice = draftEndsWithVoice
        draftEndsWithVoice = false
        var prefix: [Effect] = []
        switch voice {
        case let .listening(id, _):
            // Any key while recording (an Option chord, or typing) cancels the recording.
            prefix = cancelVoice(id)
            if event.keyCode == VirtualKey.escape { return .consumed(prefix) }
        case let .finishing(id, text):
            // The final transcript hasn't arrived yet: keep what was recognized so far.
            if event.keyCode == VirtualKey.escape { return .consumed(cancelVoice(id)) }
            actsAfterVoice = false  // another key after the action key: not sending after all
            prefix = [.cancelVoice(id: id)] + voiceFinished(text, id: id)
        case .off:
            break
        }
        let response = dispatchKey(event, afterVoice: afterVoice || !prefix.isEmpty && draftEndsWithVoice)
        return Response(effects: prefix + response.effects, handled: response.handled)
    }

    private func dispatchKey(_ event: KeyEvent, afterVoice: Bool) -> Response {
        draftEndsWithVoice = false
        var accentTyped: [Effect] = []
        if pendingAccent != nil || event.isDeadKey {
            switch handleDeadKey(event) {
            case let .done(response): return response
            case let .then(effects): accentTyped = effects
            }
        }
        let response = dispatchOtherKey(event, afterVoice: afterVoice)
        return Response(effects: accentTyped + response.effects, handled: response.handled)
    }

    private enum DeadKeyOutcome {
        case done(Response)
        /// The accent went in as is; the key does what it does.
        case then([Effect])
    }

    /// A dead key waits, with its accent marked, for the key it goes on (`KeyEvent.composed`): in English
    /// mode, and in a command's text in either mode. Not while pinyin is being typed (the key is then as before).
    private func handleDeadKey(_ event: KeyEvent) -> DeadKeyOutcome {
        if let accent = pendingAccent {
            pendingAccent = nil
            if let text = event.composed {
                guard !draft.isEmpty else { return .done(.consumed([.commit(text)])) }
                appendTyped(text)
                setLevelOnePhase()
                return .done(.consumed([.updateMarkedText, .showPanel]))
            }
            // ⌫ and Esc take the accent back; another key types it, then does what it does (as macOS does).
            if event.keyCode == VirtualKey.delete || event.keyCode == VirtualKey.escape { return .done(.consumed([.updateMarkedText])) }
            guard !draft.isEmpty else { return .then([.commit(accent)]) }
            insertIntoDraft(accent)
            return .then([.updateMarkedText])
        }
        guard event.isDeadKey, !isLevelTwo, voice == .off, let engine, !engine.snapshot().isComposing,
              !draft.isEmpty || engine.snapshot().isAsciiMode, !event.characters.isEmpty
        else { return .then([]) }
        pendingAccent = event.characters
        return .done(.consumed([.updateMarkedText]))
    }

    private func dispatchOtherKey(_ event: KeyEvent, afterVoice: Bool) -> Response {
        let modifiers = event.modifiers.subtracting(.capsLock)
        if modifiers == .command, event.charactersIgnoringModifiers.lowercased() == "c", let text = copyableText {
            return .consumed([.copy(text), .notice(messages.copied)])  // the result stays up
        }
        if modifiers == .command, event.charactersIgnoringModifiers.lowercased() == "v", let response = pasteIntoDraft() {
            return response
        }
        // ⌃V does the same in every app: none pastes on it by itself (terminals and Notes do on ⌘V,
        // whatever the input method does), so the text is pasted once, into the draft.
        if modifiers == .control, event.charactersIgnoringModifiers.lowercased() == "v",
           let response = pasteIntoDraft(evenWhereTheAppPastes: true) {
            return response
        }
        // ⌘← ⌘→ in a command's text: to its start or end, as in any text field.
        if modifiers == .command, event.keyCode == VirtualKey.left || event.keyCode == VirtualKey.right,
           !draft.isEmpty, !isLevelTwo, !engineState.isComposing, voice == .off, palette == nil {
            return .consumed(moveCursor(event))
        }
        if modifiers.contains(.command) {
            // A shortcut with an English draft pending acts on the text as typed (⌘A, ⌘⏎ …). A note with line
            // breaks can't go in as typed: it stays, and the shortcut is the app's (a terminal's ⌘V then pastes
            // the clipboard as it was, not the note put there by `commitAll`).
            return isLatinDraft && !isLevelTwo && !draftIsNoteWithLines ? Response(effects: commitAll(), handled: false) : .passThrough
        }
        if event.keyCode == VirtualKey.space, modifiers == [.shift] {
            // ⇧Space is Space in every state (Shift is often still down after a capital: "I am").
            // librime never sees Shift+space, which a schema may bind (e.g. to full-width).
            var space = event
            space.modifiers.remove(.shift)
            return isLevelTwo ? handleLevelTwo(space) : handleLevelOne(space, afterVoice: afterVoice)
        }
        return isLevelTwo ? handleLevelTwo(event) : handleLevelOne(event, afterVoice: afterVoice)
    }

    /// Shift pressed and released on its own (within half a second, so holding Shift for a
    /// Shift-click selection doesn't count) switches the engine between Chinese and Latin input.
    /// Words already picked are kept and remaining letters are committed as typed (librime's
    /// `commit_code`). The right Option key held on its own records speech until it is released.
    /// With the `optionTap` action key, either Option key pressed and released on its own sends
    /// the sentence (a hold of the right one still dictates).
    /// The application always receives modifier changes as well. `timestamp` is in seconds.
    public func handleFlagsChanged(keyCode: UInt16, modifiers: KeyModifiers, timestamp: TimeInterval) -> [Effect] {
        if let held = optionTapHeld(keyCode: keyCode, modifiers: modifiers, timestamp: timestamp),
           !pointerUsedWithin(held), actionKey == .optionTap, let effects = actionKeyPressed() {
            voiceArmed = false  // a tap of right ⌥, not a hold
            shiftPressedAt = nil
            return effects
        }
        if let effects = handleVoiceKey(keyCode: keyCode, modifiers: modifiers) { return effects }
        let isShift = keyCode == VirtualKey.leftShift || keyCode == VirtualKey.rightShift
        let others = modifiers.subtracting([.shift, .capsLock, .leftOption, .rightOption])
        if isShift, modifiers.contains(.shift), others.isEmpty {
            shiftPressedAt = timestamp
            return []
        }
        let held = shiftPressedAt.map { timestamp - $0 }
        let toggle = isShift && !modifiers.contains(.shift)
            && held.map { $0 <= Self.shiftTapWindow && !pointerUsedWithin(max($0, 0)) } == true
        shiftPressedAt = nil
        // With one input language Shift stays put, except to leave the letters a command switched to
        // (Chinese inside `@python print("…")`).
        let switches = inputLanguages.count > 1 || restoreChineseAfterOpen || nestedLatinFrom != nil
        return toggle && voice == .off && switches ? switchInputLanguage() : []
    }

    static let shiftTapWindow: TimeInterval = 0.5
    /// Longest press of an Option key that still counts as a tap (`optionTap`). A hold of the right
    /// Option key turns into dictation sooner, after `voiceArmDelay`.
    static let optionTapWindow: TimeInterval = 0.5
    /// How long the right Option key must be held on its own before dictation starts (so ⌥
    /// shortcuts, ⌥-arrows and taps never touch the microphone).
    public static let voiceArmDelay: TimeInterval = 0.2

    /// Tracks the Option keys. True for the release of one that went down on its own and came back
    /// up within `optionTapWindow`, with no key or other modifier (including the other Option) between:
    /// how long it was held. Nil otherwise.
    private func optionTapHeld(keyCode: UInt16, modifiers: KeyModifiers, timestamp: TimeInterval) -> TimeInterval? {
        let side: KeyModifiers
        switch keyCode {
        case VirtualKey.leftOption: side = .leftOption
        case VirtualKey.rightOption: side = .rightOption
        default:
            optionPressed = nil  // another modifier changed
            return nil
        }
        let sided = !modifiers.isDisjoint(with: [.leftOption, .rightOption])
        let down = sided ? modifiers.contains(side) : modifiers.contains(.option)
        if down {
            let alone = modifiers.subtracting([.option, side, .capsLock]).isEmpty && optionPressed == nil
            optionPressed = alone ? (keyCode, timestamp) : nil
            return nil
        }
        defer { optionPressed = nil }
        guard let pressed = optionPressed, pressed.keyCode == keyCode else { return nil }
        let held = timestamp - pressed.at
        return held <= Self.optionTapWindow ? max(held, 0) : nil
    }

    /// The voice key: arms on press, dictation runs while it is held, stops on release. Nil for
    /// modifier changes that are for the Shift logic.
    private func handleVoiceKey(keyCode: UInt16, modifiers: KeyModifiers) -> [Effect]? {
        let sided = !modifiers.isDisjoint(with: [.leftOption, .rightOption])
        if case let .listening(id, text) = voice {
            // Released, also when the release itself went unseen (another modifier changed meanwhile).
            let released = voiceKeySided ? !modifiers.contains(.rightOption) : !modifiers.contains(.option)
            if released { return releaseVoice(id: id, text: text) }
            return keyCode == VirtualKey.rightOption ? [] : nil
        }
        guard keyCode == VirtualKey.rightOption else {
            voiceArmed = false  // another modifier joined in: not a hold on its own
            return nil
        }
        shiftPressedAt = nil
        let down = sided ? modifiers.contains(.rightOption) : modifiers.contains(.option)
        if down {
            let others = modifiers.subtracting([.option, .rightOption, .capsLock])
            guard others.isEmpty, voice == .off, voiceEnabled, engine != nil else {
                voiceArmed = false
                return []
            }
            voiceArmed = true
            voiceKeySided = sided
            return [.armVoice(delay: Self.voiceArmDelay)]
        }
        guard voiceArmed else { return [] }
        voiceArmed = false
        return [.notice(messages.holdToTalk)]  // released before dictation started: a tap
    }

    /// `voiceArmDelay` after `.armVoice`: starts dictation if the key is still held on its own
    /// (`stillHeld` false, e.g. its release went unseen or a mouse button is down, disarms).
    public func voiceHoldElapsed(stillHeld: Bool = true) -> [Effect] {
        guard voiceArmed, voice == .off else { return [] }
        voiceArmed = false
        return stillHeld ? startVoice() : []
    }

    /// A candidate clicked in the panel.
    public func choose(index: Int) -> [Effect] {
        if isLevelTwo { return commitChoice(at: index) }
        if recipientQuery != nil { return pickRecipient(at: index) }
        // A command in the list (`index` among the rows shown).
        if paletteQuery != nil {
            let matches = paletteMatches
            return matches.indices.contains(paletteFirstVisible + index) ? complete(matches, at: paletteFirstVisible + index) : []
        }
        guard let engine, engineState.isComposing, engine.selectCandidate(onPage: index) else { return [] }
        return afterEngineChange(engine, effects: [])
    }

    /// Switches level one to Chinese (pinyin) or English input, e.g. to the configured default.
    /// Ignored while something is being composed.
    public func setInputMode(_ language: Language) {
        guard engine != nil, !isComposing, hangul.isEmpty else { return }
        enter(language)
    }

    /// Puts level one in `language`: Hindi's engine or librime's, in or out of its ASCII mode.
    private func enter(_ language: Language) {
        hindiActive = language == .hindi && hindiEngine != nil
        guard let engine else { return }
        let ascii = language != .chinese && language != .hindi
        if ascii { asciiLanguage = language }
        if engine.snapshot().isAsciiMode != ascii { engine.setAsciiMode(ascii) }
        engineState = engine.snapshot()
    }

    // MARK: - Conversion feedback

    public func receive(_ newResult: ConversionResult, isFinal: Bool, id: Int) -> [Effect] {
        guard phase == .translating(id: id) else { return [] }
        result = newResult
        if isFinal, activeCommand?.kind == .link {
            // The commands inside a link's text have run: open it with their outputs.
            let text = result.versions.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Counted when it started (with the commands inside).
            switch link(activeCommand!, text, counted: true) {
            case let .opened(effects): return effects
            case let .refused(message):
                phase = .failed(message)
                return [.showPanel]
            }
        }
        if isFinal {
            // Versions that only repeat the original are hidden, but the answer still counts.
            let answered = !result.versions.isEmpty || choices.contains { $0.kind != .original && !$0.text.isEmpty }
            phase = answered ? .choosing : .failed(activeCommand?.isCode == true ? messages.noOutput : messages.noResult)
        }
        return [.showPanel]
    }

    /// Files and apps found for `@open` (`.search`): shown to pick from, or "nothing found".
    public func receiveSearch(_ results: [SearchResult], id: Int) -> [Effect] {
        guard phase == .translating(id: id) else { return [] }
        searchResults = results
        phase = results.isEmpty ? .failed(messages.nothingFound) : .choosing
        return [.showPanel]
    }

    public func fail(_ message: String, id: Int) -> [Effect] {
        guard phase == .translating(id: id) else { return [] }
        phase = .failed(message)
        return [.showPanel]
    }

    /// The reminder read from the `@reminder` text (`.previewReminder`): one row to confirm (Space, ⏎ or 1
    /// adds it, Esc or another digit goes back to the wording), or a hint when the text holds only a time
    /// (⏎, Space and Esc then go back to it).
    public func receiveReminder(_ reminder: ReminderDraft, id: Int) -> [Effect] {
        guard phase == .translating(id: id) else { return [] }
        if reminder.title.isEmpty {
            phase = .failed(messages.reminderWithoutTitle)
        } else {
            pendingReminder = reminder
            phase = .choosing
        }
        return [.showPanel]
    }

    /// A note or reminder that couldn't be saved (no permission, no account, a script error): its text comes
    /// back as the draft it was ("@note …", "@reminder …"), to fix and send again, if nothing is being typed
    /// here. Nil otherwise: the controller then puts the text on the clipboard instead.
    public func restoreDraft(_ command: Command, text: String) -> [Effect]? {
        guard phase == .idle, draft.isEmpty, voice == .off, !(engine?.snapshot().isComposing ?? false) else { return nil }
        draft = "@\(command.name) " + text
        draftHasOutsideText = true
        setLevelOnePhase()
        return [.updateMarkedText, .showPanel]
    }

    // MARK: - Voice feedback

    /// Speech recognized so far (shown inline while recording).
    public func voiceText(_ text: String, id: Int) -> [Effect] {
        switch voice {
        case .listening(id, _): voice = .listening(id: id, text: text)
        case .finishing(id, _): voice = .finishing(id: id, text: text)
        default: return []
        }
        return [.updateMarkedText, .showPanel]
    }

    /// The final transcript: it continues the draft (an @ command is pending) or is inserted. If the
    /// action key was pressed during dictation, the command then runs.
    public func voiceFinished(_ text: String, id: Int) -> [Effect] {
        guard voice.id == id else { return [] }
        voice = .off
        let translate = actsAfterVoice
        actsAfterVoice = false
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else {
            setLevelOnePhase()
            return [.updateMarkedText, wantsPanel ? .showPanel : .hidePanel, .notice(messages.didNotHear)]
        }
        guard !draft.isEmpty else {
            setLevelOnePhase()
            return [.commit(spoken), wantsPanel ? .showPanel : .hidePanel]
        }
        insertIntoDraft(appendix(spoken))
        draftEndsWithVoice = tail.isEmpty
        draftHasOutsideText = true
        setLevelOnePhase()
        if translate { return startAction().effects }
        return [.updateMarkedText, .showPanel]
    }

    /// Recording or recognition failed (no microphone permission, model missing, …).
    public func voiceFailed(_ message: String, id: Int) -> [Effect] {
        guard voice.id == id else { return [] }
        voice = .off
        actsAfterVoice = false
        setLevelOnePhase()
        return [.updateMarkedText, wantsPanel ? .showPanel : .hidePanel, .notice(message)]
    }

    // MARK: - Ending the composition from outside

    /// The application ends the composition (focus change, click elsewhere, input source switch):
    /// everything pending is committed as converted text, including speech recognized so far (but not a
    /// note with line breaks: `finishAsTyped`).
    public func commitAll() -> [Effect] {
        typePendingAccent()
        var effects: [Effect] = []
        var spoken = ""
        if let id = voice.id {
            spoken = voice.text
            effects = cancelVoice(id, refresh: false)
        }
        var text = draft
        if !isLevelTwo, let engine, engine.snapshot().isComposing {
            text += engine.commitComposition() ?? ""
        }
        text += spoken.isEmpty ? "" : separator(before: spoken, after: text) + spoken
        return effects + finishAsTyped(text)
    }

    /// Commits everything exactly as typed (draft plus raw letters), without converting (but not a note with
    /// line breaks: `finishAsTyped`). Speech being recognized is dropped (this runs when a password field takes over).
    public func commitAsTyped() -> [Effect] {
        typePendingAccent()
        var effects: [Effect] = []
        if let id = voice.id { effects = cancelVoice(id, refresh: false) }
        var text = draft
        if !isLevelTwo, let engine, engine.snapshot().isComposing {
            text += engine.rawInput
        }
        return effects + finishAsTyped(text)
    }

    /// A dead key's accent with nothing after it goes in as is (the field lost, everything committed), as macOS does.
    private func typePendingAccent() {
        if !hangul.isEmpty { insertIntoDraft(hangul.flush()) }
        guard let accent = pendingAccent else { return }
        pendingAccent = nil
        insertIntoDraft(accent)
    }

    /// The draft is a note with line breaks (pasted, or back from a save that failed). Inserted as typed, each
    /// break would be a Return: in a terminal every line would run as a command.
    private var draftIsNoteWithLines: Bool {
        draftCommand?.kind == .note && draft.contains(where: \.isNewline)
    }

    /// Ends the composition inserting `text`, the draft as typed (and what is still being typed after it). A note
    /// with line breaks isn't inserted (`draftIsNoteWithLines`): its text goes to the clipboard and a notice
    /// says it wasn't saved. A one-line note goes in like any other draft.
    private func finishAsTyped(_ text: String) -> [Effect] {
        guard draftIsNoteWithLines, let content = Command.parse(text, in: commands)?.content else {
            return finish(committing: text)
        }
        let note = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return finish(committing: "") + (note.isEmpty ? [] : [.copy(note), .notice(messages.noteNotSaved)])
    }

    /// Re-reads the engine (e.g. after it became available).
    public func refreshEngineState() {
        engineState = engine?.snapshot() ?? .empty
    }

    // MARK: - Level one

    private func handleLevelOne(_ event: KeyEvent, afterVoice: Bool = false) -> Response {
        guard let engine else {
            guard event.printableText != nil, !warnedNotReady else { return .passThrough }
            warnedNotReady = true
            return Response(effects: [.notice(messages.notReady)], handled: false)
        }
        let composing = engine.snapshot().isComposing
        let modifiers = event.modifiers.subtracting(.capsLock)
        if !composing, let response = handlePaletteKey(event) { return response }
        // Return runs a command draft ("@question …"), like the action key; text keeps Return = as typed.
        if event.keyCode == VirtualKey.returnKey || event.keyCode == VirtualKey.keypadEnter, modifiers.isEmpty,
           draftCommand != nil, let effects = actionKeyPressed() {
            return .consumed(effects)
        }
        if !composing {
            if !draft.isEmpty, let response = handleDraftKey(event, afterVoice: afterVoice) { return response }
            if draft.isEmpty {
                // "@" first: the command palette ("@question …").
                if event.printableText == "@" {
                    draft = "@"
                    paletteHighlight = 0
                    setLevelOnePhase()
                    return .consumed([.updateMarkedText, .showPanel])
                }
                // Shortcuts and Caps Lock typing go straight to the application when nothing is pending.
                if !modifiers.isDisjoint(with: [.control, .option]) { return .passThrough }
                if event.modifiers.contains(.capsLock) { return .passThrough }
            }
        }

        let pending = composing || !draft.isEmpty
        // rime-ice rejects every key carrying the Caps Lock mask (`good_old_caps_lock`), which would
        // freeze a composition in progress: keep editing it as if Caps Lock were off.
        var rimeEvent = event
        if composing { rimeEvent.modifiers.remove(.capsLock) }
        // ⇧Return is "as typed" (the action key may be Return): librime gets a plain Return.
        if event.keyCode == VirtualKey.returnKey || event.keyCode == VirtualKey.keypadEnter { rimeEvent.modifiers.remove(.shift) }
        guard let key = RimeKey.map(rimeEvent) else {
            // Characters librime has no key for (é, ß, other scripts) belong to the sentence too.
            if !composing, !draft.isEmpty, let text = event.printableText {
                appendTyped(text, afterVoice: afterVoice)
                return .consumed([.updateMarkedText, .showPanel])
            }
            return pending ? .consumed() : .passThrough
        }
        let handled = engine.processKey(key.keycode, mask: key.mask)
        var effects: [Effect] = []
        if let committed = engine.takeCommit(), !committed.isEmpty {
            effects += accept(committed)
        }
        engineState = engine.snapshot()
        var consumed = handled
        if !handled, !engineState.isComposing, !draft.isEmpty, let text = event.printableText {
            // Digits, Latin-mode letters etc. continue the draft.
            appendTyped(text, afterVoice: afterVoice)
            consumed = true
        }
        setLevelOnePhase()
        if !consumed && (engineState.isComposing || !draft.isEmpty) {
            consumed = true  // keep the application from typing into the marked text
        }
        let committedDirectly = effects.contains { if case .commit = $0 { return true } else { return false } }
        if !consumed && !committedDirectly { return .passThrough }
        effects += [.updateMarkedText, wantsPanel ? .showPanel : .hidePanel]
        return Response(effects: effects, handled: consumed)
    }

    // MARK: - Paste

    /// The most text ⌘V puts into a draft, in Characters (a long paragraph; the answer grows with it).
    public static let maxPasteLength = 2000

    /// ⌘V or ⌃V with a draft pending ("@improve ", a command name being typed):
    /// the clipboard's text will join the draft instead of the document (`pasted`), so the action key
    /// then runs on it. Pinyin still being typed is converted first, and "@imp" picks its command. Nil
    /// without a draft, and after "@" alone (a mention): the key then does what it does in the app.
    /// ⌘V is left to apps that paste on it themselves (`pastesIntoDraft`); ⌃V works everywhere.
    private func pasteIntoDraft(evenWhereTheAppPastes: Bool = false) -> Response? {
        guard pastesIntoDraft || evenWhereTheAppPastes, !isLevelTwo, voice == .off, !draft.isEmpty else { return nil }
        if let query = paletteQuery, query.isEmpty || paletteMatches.isEmpty { return nil }
        var effects: [Effect] = []
        if paletteQuery != nil { _ = complete(paletteMatches) }  // the draft is now "@name "
        if let engine, engine.snapshot().isComposing { effects += convertComposition(engine) }
        setLevelOnePhase()
        return .consumed(effects + [.updateMarkedText, .showPanel, requestClipboard()])
    }

    /// Asks for the clipboard's text (`pasted`); only the latest request counts.
    private func requestClipboard() -> Effect {
        pasteCounter += 1
        pendingPaste = pasteCounter
        return .readClipboard(id: pasteCounter)
    }

    /// The clipboard's text for ⌘V `id` (nil: no text, or it may not be read): it continues the draft,
    /// as pasting continues a text. Dropped when the draft has been sent or cleared meanwhile.
    public func pasted(_ clipboard: String?, id: Int) -> [Effect] {
        guard pendingPaste == id else { return [] }
        pendingPaste = nil
        guard !isLevelTwo, voice == .off, !draft.isEmpty else { return [] }
        // A note keeps its lines and may be longer; every other command takes one line (its answer has one per row).
        let note = draftCommand?.kind == .note
        let limit = note ? Self.maxNoteLength : Self.maxPasteLength
        let tooLong = note ? messages.noteTooLong : messages.pasteTooLong
        // Far too much is refused before it is looked at (this runs on the main thread).
        if let clipboard, clipboard.utf16.count > limit * 8 { return [.notice(tooLong)] }
        let text = clipboard.map(note ? Self.noteText : Self.oneLine) ?? ""
        guard !text.isEmpty else { return [.notice(messages.nothingToPaste)] }
        guard text.count <= limit else { return [.notice(tooLong)] }
        insertIntoDraft(text)
        draftHasOutsideText = true
        setLevelOnePhase()
        return [.updateMarkedText, .showPanel]
    }

    /// The most text a note takes from the clipboard, in Characters (it keeps its lines).
    public static let maxNoteLength = 20_000

    /// How a line break of a note shows in the one-line draft.
    static let lineBreak = " ↵ "

    /// Clipboard text for a note: as it is, its lines too, without the blank space at its ends and without
    /// control characters other than tabs and line breaks (they would only garble the draft and the note).
    static func noteText(_ text: String) -> String {
        let kept = String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            scalar.properties.generalCategory != .control || scalar == "\t" || scalar == "\n" || scalar == "\r" || scalar == "\u{85}"
        }))
        return kept.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Clipboard text as one line for the draft (the improve answer has one line per version): line
    /// breaks become spaces, or nothing between Chinese; control characters become spaces; the ends
    /// are trimmed.
    static func oneLine(_ text: String) -> String {
        var out = ""
        for line in text.components(separatedBy: .newlines) {
            let part = CandidateParser.stripControls(line).trimmingCharacters(in: .whitespaces)
            guard let first = part.first else { continue }
            if let last = out.last, !(isCJK(last) && isCJK(first)) { out += " " }
            out += part
        }
        return out
    }

    /// Chinese, Japanese and Korean characters and full-width punctuation: no space between lines of them.
    static func isCJK(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return String(c).containsHan || (0x3000...0x30FF).contains(v) || (0xFF00...0xFFEF).contains(v)
            || (0xAC00...0xD7AF).contains(v)
    }

    // MARK: - Command palette

    /// Keys while a command name is typed after "@": letters narrow the list, Tab, Space, Return or a
    /// digit pick a command, ↑↓ move, ⌫ edits, Esc removes it. Any other key, or a letter no command
    /// starts with, inserts the "@…" as typed and then acts as usual, so "@name" mentions still reach
    /// the app. Nil outside the palette.
    private func handlePaletteKey(_ event: KeyEvent) -> Response? {
        guard let (query, nested, at) = palette else { return nil }
        let matches = paletteMatches
        let plain = event.modifiers.subtracting([.capsLock, .shift]).isEmpty
        // Inside a text, leaving the list just goes on with the draft (nil: the key acts as usual).
        func leave() -> Response? { nested ? nil : commitPalette(then: event) }
        switch event.keyCode {
        case VirtualKey.tab where plain:
            return matches.isEmpty ? leave() : .consumed(complete(matches))
        case VirtualKey.space where plain:
            // "@ " is just an at sign and a space.
            return query.isEmpty || matches.isEmpty ? leave() : .consumed(complete(matches))
        case VirtualKey.returnKey, VirtualKey.keypadEnter:
            // Picks, like Tab; "@" alone goes in as typed (inside a text, Return runs the command as usual).
            if query.isEmpty || matches.isEmpty { return nested ? nil : .consumed(finish(committing: draft)) }
            return .consumed(complete(matches))
        case VirtualKey.escape:
            // Removes the "@…" (inside a text, only that).
            draft = nested ? String(draft[..<at]) : ""
            setLevelOnePhase()
            return .consumed([.updateMarkedText, draft.isEmpty ? .hidePanel : .showPanel])
        case VirtualKey.delete where plain:
            draft.removeLast()
            paletteHighlight = 0
            setLevelOnePhase()
            return .consumed([.updateMarkedText, draft.isEmpty ? .hidePanel : .showPanel])
        case VirtualKey.up, VirtualKey.down:
            guard !matches.isEmpty else { return .consumed() }
            movePaletteHighlight(by: event.keyCode == VirtualKey.up ? -1 : 1)
            return .consumed([.showPanel])
        default:
            break
        }
        if plain, let text = event.printableText, text.count == 1, let c = text.first, c.isASCII {
            if c.isLetter, !Command.palette(query + text, in: paletteCommands, usage: commandUsage).isEmpty {
                draft += text
                paletteHighlight = 0
                return .consumed([.updateMarkedText, .showPanel])
            }
            // Digits pick from the rows shown.
            if let n = c.wholeNumberValue, n >= 1, matches.indices.contains(paletteFirstVisible + n - 1) {
                return .consumed(complete(matches, at: paletteFirstVisible + n - 1))
            }
        }
        return leave()
    }

    /// Picks a palette command: the draft becomes "@name " (inside a text, the "@…" typed does), and the
    /// rest of the sentence follows.
    private func complete(_ matches: [Command], at index: Int? = nil) -> [Effect] {
        let command = matches[index ?? paletteHighlighted]
        // Nothing to write after it: picked, it's done (only at the start of a draft).
        if command.kind == .settings, palette?.nested != true {
            return finish(committing: "") + [.openSettings, used(command)]
        }
        let nested = palette?.nested == true
        draft = (palette.map { String(draft[..<$0.at]) } ?? "") + "@\(command.name) "
        paletteHighlight = 0
        // File names, paths and code are typed as letters; the input mode comes back when the command is
        // done (inside a text: once its argument is typed and a space follows).
        if command.typesLatin || command.kind == .message && !nested, let engine, !engine.snapshot().isAsciiMode {
            typeLetters(engine)
            nestedLatinFrom = nested ? draft.count : nil
        } else if nested, command.typesLatin, inputLanguage == .korean {
            nestedLatinFrom = draft.count  // letters, not Hangul, until its argument is typed (`typesHangul`)
        }
        setLevelOnePhase()
        return [.updateMarkedText, .showPanel]
    }

    /// Tab on an `@open` result: its path replaces what was typed (a folder's ends in "/", which lists it).
    private func completeLivePath() -> [Effect] {
        let live = currentLiveResults
        guard live.indices.contains(liveHighlight) else { return [] }
        let result = live[liveHighlight]
        draft = "@open " + (result.path as NSString).abbreviatingWithTildeInPath + (result.isFolder ? "/" : "")
        liveResults = []
        liveResultsQuery = nil
        resetLiveHighlight()
        return [.updateMarkedText, .showPanel]
    }

    /// Leaves the palette: what was typed ("@", "@na") goes in as typed, then `event` acts as usual. A
    /// letter in Chinese mode is a name being typed (「@lisi」 for @李四): only the "@" goes in, and the letters
    /// typed after it are pinyin.
    private func commitPalette(then event: KeyEvent) -> Response {
        let query = paletteQuery ?? ""
        let pinyin = !query.isEmpty && event.printableText?.allSatisfy(\.isLetter) == true
            && engine.map { !$0.snapshot().isAsciiMode } == true
        let typed = finish(committing: pinyin ? "@" : draft)
        var effects = typed
        if pinyin {
            for letter in query {
                effects += handleLevelOne(KeyEvent(keyCode: 0, characters: String(letter))).effects
            }
        }
        let next = handleLevelOne(event)
        return Response(effects: effects + next.effects, handled: next.handled)
    }

    private func appendTyped(_ text: String, afterVoice: Bool = false) {
        insertIntoDraft(afterVoice ? appendix(text) : text)  // "hello world" + "and" → "hello world and"
        // The argument of a command inside the text is done: back to Chinese for the rest of the sentence.
        if let from = nestedLatinFrom, text == " ", draft.count > from + 1 {
            nestedLatinFrom = nil
            restoreInputModeAfterOpen()
        }
    }

    /// Keys with a meaning for the draft itself, when the engine has nothing left to convert.
    private func handleDraftKey(_ event: KeyEvent, afterVoice: Bool) -> Response? {
        let plain = event.modifiers.subtracting(.capsLock).isEmpty
        if let response = handleRecipientKey(event) { return response }
        let live = currentLiveResults
        if !live.isEmpty, plain {
            switch event.keyCode {
            case VirtualKey.up, VirtualKey.down:
                liveHighlight = (liveHighlight + (event.keyCode == VirtualKey.up ? -1 : 1) + live.count) % live.count
                liveHighlightMoved = true
                return .consumed([.showPanel])
            case VirtualKey.tab:
                return .consumed(completeLivePath())
            default:
                break
            }
        }
        switch event.keyCode {
        case VirtualKey.space where plain && actionKey == .space:
            // In English (Latin) mode Space separates words; a second Space in a row runs the command.
            // Right after dictation the sentence is finished, so one Space does. (With the other
            // action keys, Space in a draft is just a space: it goes on below.)
            if engineState.isAsciiMode, !beforeCursor.hasSuffix(" "), !afterVoice {
                insertIntoDraft(" ")
                return .consumed([.updateMarkedText, .showPanel])
            }
            return startAction()
        case VirtualKey.returnKey, VirtualKey.keypadEnter:
            // ⇧⏎ (⏎ alone runs the command): as typed, except a note with line breaks (`finishAsTyped`).
            return .consumed(finishAsTyped(draft))
        case VirtualKey.delete:
            // Right after a picked recipient: back to picking one.
            if messageRecipient != nil, let command = draftCommand, draft == "@\(command.name) " {
                messageRecipient = nil
                if let engine, !engine.snapshot().isAsciiMode { typeLetters(engine) }  // names, pinyin, numbers: typed as letters
                return .consumed([.updateMarkedText, .showPanel])
            }
            deleteBeforeCursor()
            setLevelOnePhase()
            return .consumed([.updateMarkedText, draft.isEmpty ? .hidePanel : .showPanel])
        case VirtualKey.escape:
            draft = ""
            setLevelOnePhase()
            return .consumed([.updateMarkedText, .hidePanel])
        case VirtualKey.left, VirtualKey.right, VirtualKey.home, VirtualKey.end:
            // The cursor moves in the text after the command, as in any text field.
            return .consumed(moveCursor(event))
        case VirtualKey.forwardDelete:
            let after = tail
            guard !after.isEmpty else { return .consumed() }
            draft = String(draft.dropLast(after.count)) + after.dropFirst()
            cursorTail = String(after.dropFirst())
            setLevelOnePhase()
            return .consumed([.updateMarkedText, .showPanel])
        case VirtualKey.tab, VirtualKey.up, VirtualKey.down, VirtualKey.pageUp, VirtualKey.pageDown:
            return .consumed()
        default:
            return nil
        }
    }

    /// Collects the engine's commit and new state after it processed something.
    private func afterEngineChange(_ engine: PinyinEngine, effects: [Effect]) -> [Effect] {
        var effects = effects
        if let committed = engine.takeCommit(), !committed.isEmpty {
            effects += accept(committed)
        }
        engineState = engine.snapshot()
        setLevelOnePhase()
        effects += [.updateMarkedText, wantsPanel ? .showPanel : .hidePanel]
        return effects
    }

    /// Engine output continues a draft (an @ command); otherwise it is inserted, as in any input method.
    private func accept(_ text: String) -> [Effect] {
        if !draft.isEmpty {
            insertIntoDraft(text)
            return []
        }
        return [.commit(text)]
    }

    private func setLevelOnePhase() {
        phase = draft.isEmpty && !engineState.isComposing && hangul.isEmpty && voice == .off ? .idle : .drafting
        if messageRecipient != nil, draftCommand?.kind != .message { messageRecipient = nil }
        if !pickingRecipient, recipientResultsQuery != nil { clearRecipientResults() }
        restoreInputModeAfterOpen()
    }

    /// A command typed in letters (`@open`, code, a recipient) from Chinese or Hindi: the engine in its ASCII mode, as
    /// English (not the Latin language last typed: Korean would be Hangul), until the command is done
    /// (`restoreInputModeAfterOpen`).
    private func typeLetters(_ engine: PinyinEngine) {
        engine.setAsciiMode(true)
        asciiLanguage = .english
        restoreChineseAfterOpen = true
        engineState = engine.snapshot()
    }

    /// Back to Chinese once the draft is no longer a command typed in letters (`@open`, code).
    private func restoreInputModeAfterOpen() {
        if draft.isEmpty { nestedLatinFrom = nil }
        guard restoreChineseAfterOpen, draft.isEmpty || draftCommand?.typesLatin != true && nestedLatinFrom == nil && !pickingRecipient,
              let engine else { return }
        restoreChineseAfterOpen = false
        engine.setAsciiMode(false)
        engineState = engine.snapshot()
    }

    /// A tap of Shift: the next input language, in the order they were added (`inputLanguages`). Out of the
    /// letters a command switched to (`@open` typed in Chinese), back to Chinese.
    private func switchInputLanguage() -> [Effect] {
        guard engine != nil, !isLevelTwo else { return [] }
        let current = inputLanguage
        // Out of the letters for code inside Korean text (`@translate 안녕 @py …`): back to Hangul.
        if nestedLatinFrom != nil, !restoreChineseAfterOpen, current == .korean {
            nestedLatinFrom = nil
            return [.updateMarkedText, .notice(messages.mode(current))]
        }
        let next: Language
        if restoreChineseAfterOpen || nestedLatinFrom != nil || inputLanguages.count < 2 {
            next = current == nativeLanguage ? asciiLanguage : nativeLanguage
        } else {
            let index = inputLanguages.firstIndex(of: current).map { $0 + 1 } ?? 0
            next = inputLanguages[index % inputLanguages.count]
        }
        guard next != current else { return [] }
        var effects = finishHangul()
        if current == .chinese {
            // Pinyin being typed goes in as librime's Shift does it (`toggleLatin`).
            effects += toggleLatin()
        } else if let engine, engine.snapshot().isComposing, let word = engine.commitComposition() {
            effects += accept(word)  // a Hindi word being typed: its first spelling
        }
        if restoreChineseAfterOpen || nestedLatinFrom != nil {
            restoreChineseAfterOpen = false  // left by hand
        }
        enter(next)
        return effects + [.updateMarkedText, .inputLanguageChanged(next), .notice(messages.mode(next))]
    }

    private func toggleLatin() -> [Effect] {
        guard let engine, !isLevelTwo else { return [] }
        let before = engine.snapshot()
        let latin = before.isAsciiMode
        // librime's own Shift handling (rime-ice: `Shift_L: commit_code`) keeps the words already
        // picked and commits the remaining letters as typed. rime-ice ignores Shift_R, so Shift_L
        // stands for either key.
        _ = engine.processKey(RimeKey.shiftL, mask: 0)
        _ = engine.processKey(RimeKey.shiftL, mask: RimeKey.releaseMask)
        var effects: [Effect] = []
        if let committed = engine.takeCommit(), !committed.isEmpty {
            effects += accept(committed)
        }
        if engine.snapshot().isAsciiMode == latin {
            // The schema has no Shift binding: switch directly, keeping the typed letters.
            if !latin, engine.snapshot().isComposing {
                let rest = engine.rawInput
                engine.clearComposition()
                if !rest.isEmpty { effects += accept(rest) }
            }
            engine.setAsciiMode(!latin)
        }
        return afterEngineChange(engine, effects: effects)
    }

    // MARK: - Voice

    private func startVoice() -> [Effect] {
        // A Hangul syllable being typed goes in first: the transcript follows it.
        var effects = finishHangul()
        if isLevelTwo { effects += backToDraft() }
        // "@q" + hold right ⌥: the command is picked, and the dictation is what follows it.
        if paletteQuery != nil, !paletteMatches.isEmpty { effects += complete(paletteMatches) }
        // Pinyin still being typed is converted first; the transcript follows it.
        if let engine, engine.snapshot().isComposing, let text = engine.commitComposition(), !text.isEmpty {
            effects += accept(text)
            engineState = engine.snapshot()
        }
        voiceCounter += 1
        voice = .listening(id: voiceCounter, text: "")
        optionPressed = nil  // the hold became dictation: its release is not a tap
        actsAfterVoice = false
        setLevelOnePhase()
        let language = inputLanguage
        // Start last: if it fails at once, its notice must not be hidden by these updates.
        return effects + [.updateMarkedText, .showPanel, .startVoice(id: voiceCounter, language: language)]
    }

    private func releaseVoice(id: Int, text: String) -> [Effect] {
        voice = .finishing(id: id, text: text)
        return [.stopVoice(id: id), .showPanel]
    }

    private func cancelVoice(_ id: Int, refresh: Bool = true) -> [Effect] {
        voice = .off
        actsAfterVoice = false
        guard refresh else { return [.cancelVoice(id: id)] }
        setLevelOnePhase()
        return [.cancelVoice(id: id), .updateMarkedText, wantsPanel ? .showPanel : .hidePanel]
    }

    /// `text` as it continues the draft: English words get a separating space.
    private func appendix(_ text: String) -> String {
        text.isEmpty ? "" : separator(before: text, after: String(beforeCursor)) + text
    }

    private func separator(before text: String, after existing: String) -> String {
        guard let last = existing.last, let first = text.first else { return "" }
        let wordy: (Character) -> Bool = { $0.isLetter && !String($0).containsHan || $0.isNumber }
        return (wordy(last) || ".,!?;:".contains(last)) && wordy(first) ? " " : ""
    }

    // MARK: - Level two

    private func handleLevelTwo(_ event: KeyEvent) -> Response {
        switch event.keyCode {
        case VirtualKey.space:
            // A message is sent by ⏎ (or the action key), never by a Space typed on the way.
            if activeCommand?.kind == .message, actionKey != .space, phase == .choosing { return .consumed() }
            return .consumed(acceptInLevelTwo())
        case VirtualKey.returnKey, VirtualKey.keypadEnter:
            // Like Space: the highlighted row (row 0 is the sentence as typed). After a failure
            // nothing is highlighted, and Return keeps the sentence as typed (as the Return action
            // key it retries instead, before reaching here). A reminder with nothing to be reminded of
            // goes back to its text instead: typed into the app, it would only be the time.
            if case .failed = phase {
                // A message is never inserted: ⏎ tries again.
                if activeCommand?.kind == .message { return .consumed(startAction().effects) }
                return .consumed(activeCommand?.kind == .reminder ? backToDraft() : finish(committing: sentText))
            }
            return .consumed(commitChoice(at: highlighted))
        case VirtualKey.escape, VirtualKey.delete:
            return .consumed(backToDraft())
        case VirtualKey.up, VirtualKey.pageUp:
            return .consumed(moveHighlight(by: -1))
        case VirtualKey.down, VirtualKey.pageDown:
            return .consumed(moveHighlight(by: 1))
        case VirtualKey.tab:
            return .consumed(moveHighlight(by: event.modifiers.contains(.shift) ? -1 : 1))
        case VirtualKey.left, VirtualKey.right, VirtualKey.home, VirtualKey.end, VirtualKey.forwardDelete:
            return .consumed()
        default:
            break
        }
        guard let text = event.printableText else { return .consumed() }
        if text.count == 1, let c = text.first, c.isASCII, c.isNumber {
            if let index = choices.firstIndex(where: { $0.label == text }) { return .consumed(commitChoice(at: index)) }
            // A reminder has one row: another digit belongs to its text ("…下午" + 3), typed below.
            guard activeCommand?.kind == .reminder else { return .consumed() }
        }
        // Typing more: back to the draft and continue the sentence with this key.
        let back = backToDraft()
        let next = handleLevelOne(event)
        return .consumed(back + next.effects)
    }

    private func startAction() -> Response {
        // A Hangul syllable still being typed belongs to the text (the action key was an Option tap).
        if !hangul.isEmpty { insertIntoDraft(hangul.flush()) }
        let parsed = Command.parse(draft, in: commands)
        // Only an @ command is ever sent: without one the input method just types.
        guard parsed != nil else { return .consumed() }
        let input = sentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let command = parsed?.command, command.kind == .message { return startMessage(command, input: input) }
        if parsed?.command.kind == .settings, !isLevelTwo {
            return .consumed(finish(committing: "") + [.openSettings, used(parsed!.command)])
        }
        // The task list needs nothing after the command.
        if parsed?.command.kind == .agents, !isLevelTwo {
            requestCounter += 1
            phase = .translating(id: requestCounter)
            result = .empty
            searchResults = []
            highlightOverride = nil
            activeCommand = parsed?.command
            return .consumed([.listAgents(id: requestCounter), .updateMarkedText, .showPanel, used(parsed!.command)])
        }
        // Nothing after the command: a hint (the clipboard's text comes in with ⌃V or ⌘V).
        guard !input.isEmpty else { return .consumed([.notice(messages.typeAfterCommand)]) }
        if let command = parsed?.command, command.kind == .terminal {
            guard !secureInputActive() else {
                return .consumed([.updateMarkedText, .notice(command.custom == nil ? messages.secureInputTerminal : messages.secureInputCommand)])
            }
            // The session runs in its own window: nothing to wait for or insert here.
            let usage = used(command)
            if let custom = command.custom {
                return .consumed(finish(committing: "") + [.launchInTerminal(argv: custom.arguments(for: input)),
                                                           .notice(messages.ranInTerminal), usage])
            }
            if command == .claude, claudeInBackground {
                return .consumed(finish(committing: "") + [.startBackgroundAgent(prompt: input),
                                                           .notice(messages.startedInBackground), usage])
            }
            return .consumed(finish(committing: "") + [.runInTerminal(prompt: input), .notice(messages.openedTerminal), usage])
        }
        if let command = parsed?.command, command.kind == .note {
            // Saved on this Mac (Apple Notes) and nothing goes to a model, so secure input doesn't hold it
            // back. The controller says when it is saved, or why not.
            let usage = used(command)
            return .consumed(finish(committing: "") + [.saveNote(text: input), usage])
        }
        // Commands inside the text (`@stock AAPL`) run first; not inside a search's text, nor a reminder's
        // (it stays on this Mac), and never inside code or a custom program's text: it runs exactly as typed,
        // so no command's output (a web page, a program's) is executed. With text the user didn't type in the
        // draft, commands that run code stay text (`draftHasOutsideText`).
        let local = parsed?.command.kind == .search || parsed?.command.kind == .reminder
        let inner = local || parsed?.command.runsCode == true ? nil : innerPlan(input)
        let (plan, codeLeft) = (inner?.plan, inner?.codeLeft == true)
        if let command = parsed?.command, command.kind == .link, plan?.isEmpty != false {
            // A password field's text must not end up in an address (and the browser's history).
            guard !secureInputActive() else { return .consumed([.updateMarkedText, .notice(messages.secureInputCommand)]) }
            switch link(command, input) {
            case let .opened(effects): return .consumed(effects)
            case let .refused(message): return .consumed([.updateMarkedText, .notice(message)])  // the draft stays
            }
        }
        requestCounter += 1
        phase = .translating(id: requestCounter)
        result = .empty
        searchResults = []
        pendingReminder = nil
        highlightOverride = nil
        activeCommand = parsed?.command
        let start: Effect
        switch parsed?.command {
        case _ where plan?.isEmpty == false:
            start = .startPlan(outer: parsed?.command, plan: plan!, id: requestCounter)
        case let command? where command.kind == .generate: start = .startCommand(command, input: input, id: requestCounter)
        case let command? where command.kind == .run: start = .startRun(command, input: input, id: requestCounter)
        case .open?: start = .search(query: input, id: requestCounter)
        // Read by the controller on this Mac (nothing is sent anywhere, so secure input doesn't hold it back).
        case .reminder?: start = .previewReminder(input: input, id: requestCounter)
        default: start = .startConversion(input: input, id: requestCounter)
        }
        let usage = ((parsed.map { [$0.command] } ?? []) + (plan?.inner.map(\.command) ?? [])).map(used)
        return .consumed([start, .updateMarkedText, .showPanel] + usage + (codeLeft ? [.notice(messages.codeNotRun)] : []))
    }

    /// Opens a `link` command's address with `text` in it: the composition ends with nothing inserted,
    /// as when `@open` opens something. A failure is a message (the text is too long for an address).
    private func link(_ command: Command, _ text: String, counted: Bool = false) -> LinkOutcome {
        guard text.count <= LinkTemplate.maxInputLength else { return .refused(messages.linkTooLong) }
        guard let template = command.linkTemplate, let url = LinkTemplate.url(template, input: text) else {
            return .refused(messages.noResult)  // not reached: the catalog only has valid templates
        }
        return .opened(finish(committing: "") + [.openLink(url)] + (counted ? [] : [used(command)]))
    }

    private enum LinkOutcome {
        case opened([Effect])
        case refused(String)
    }

    /// A send command: picks the highlighted recipient while there is none; then runs the commands
    /// inside the message (`@stock AAPL`) and shows the message to confirm (`Choice.Kind.send`).
    private func startMessage(_ command: Command, input: String) -> Response {
        guard messageRecipient != nil else {
            if !isLevelTwo, !currentRecipients.isEmpty { return .consumed(pickRecipient(at: recipientHighlight)) }
            return .consumed([.updateMarkedText, .showPanel, .notice(messages.pickRecipient)])
        }
        guard !input.isEmpty else { return .consumed([.notice(messages.typeAfterCommand)]) }
        guard !secureInputActive() else { return .consumed([.updateMarkedText, .notice(messages.secureInputCommand)]) }
        requestCounter += 1
        result = .empty
        searchResults = []
        highlightOverride = nil
        activeCommand = command
        let (plan, codeLeft) = innerPlan(input)
        let usage = plan.inner.map(\.command).map(used)
        let notice: [Effect] = codeLeft ? [.notice(messages.codeNotRun)] : []
        guard !plan.isEmpty else {
            phase = .choosing
            result = ConversionResult(versions: [CandidateLine(input)])
            return .consumed([.updateMarkedText, .showPanel] + notice)
        }
        phase = .translating(id: requestCounter)
        return .consumed([.startPlan(outer: command, plan: plan, id: requestCounter), .updateMarkedText, .showPanel] + usage + notice)
    }

    /// The commands inside `input` that run first. With text the user didn't type in the draft (pasted,
    /// dictated, given back), commands that run code stay text (`draftHasOutsideText`); `codeLeft`: some
    /// did, which a notice says.
    private func innerPlan(_ input: String) -> (plan: CommandPlan, codeLeft: Bool) {
        guard draftHasOutsideText else { return (CommandPlan.make(input, commands: commands), false) }
        let plan = CommandPlan.make(input, commands: commands.filter { !$0.runsCode })
        return (plan, CommandPlan.make(input, commands: commands).inner.contains { $0.command.runsCode })
    }

    /// The app took the text being typed into the document on its own (`MarkedTextWatch`): start over
    /// with nothing pending, without inserting anything or sending a request.
    public func appTookMarkedText() -> [Effect] {
        let wasRequesting = isLevelTwo
        let recording = voice.id
        draft = ""
        pendingAccent = nil
        _ = hangul.flush()
        messageRecipient = nil
        engine?.clearComposition()
        engineState = engine?.snapshot() ?? .empty
        voice = .off
        actsAfterVoice = false
        pendingPaste = nil
        highlightOverride = nil
        paletteHighlight = 0
        setLevelOnePhase()
        return (wasRequesting ? [.cancelConversion] : []) + (recording.map { [.cancelVoice(id: $0)] } ?? []) + [.hidePanel]
    }

    /// Counts a run of `command` for the order of the command list.
    private func used(_ command: Command) -> Effect {
        commandUsage.record(command.name)
        return .commandUsed(command.name)
    }

    // MARK: - Action key

    /// ⌥Space, when that is the action key (an Option tap arrives as modifier changes instead).
    /// The action key as a key press: Return, or ⌥Space (an Option tap arrives as modifier changes).
    /// While right ⌥ is held for dictation, Return arrives as ⌥Return.
    private func isActionKey(_ event: KeyEvent) -> Bool {
        let modifiers = event.modifiers.subtracting(.capsLock)
        switch actionKey {
        case .enter:
            let listening: Bool
            if case .listening = voice { listening = true } else { listening = false }
            return (event.keyCode == VirtualKey.returnKey || event.keyCode == VirtualKey.keypadEnter)
                && (modifiers.isEmpty || listening && modifiers == .option)
        case .optionSpace:
            return event.keyCode == VirtualKey.space && modifiers == .option
        case let .shortcut(key):
            return key.matches(event)
        case .optionTap, .space:
            return false
        }
    }

    /// The action key: pinyin still being typed is converted as Space would pick it, then the draft's
    /// @ command runs. In level two it accepts like Space; during dictation the command runs once the
    /// transcript is final. Nil without an @ command: the key is then the app's, as in any input method.
    private func actionKeyPressed() -> [Effect]? {
        guard let engine else { return nil }
        if isLevelTwo { return acceptInLevelTwo() }
        if paletteQuery != nil { return paletteMatches.isEmpty ? nil : complete(paletteMatches) }
        guard draftCommand != nil else { return nil }
        if voice != .off { return actAfterVoice() }
        // @open with results as you type: open the highlighted one right away (only content matches: listed
        // to choose from, below).
        if opensLiveResult {
            let path = currentLiveResults[liveHighlight].path  // before `finish` clears them
            return finish(committing: "") + [.open(path: path)]
        }
        let composing = engine.snapshot().isComposing
        let effects = composing ? convertComposition(engine) : []
        setLevelOnePhase()
        return effects + startAction().effects
    }

    /// The action key during dictation: recording stops (as if the key was released) and the
    /// command runs as soon as the final transcript is in.
    private func actAfterVoice() -> [Effect] {
        actsAfterVoice = true
        if case let .listening(id, text) = voice { return releaseVoice(id: id, text: text) }
        return [.showPanel]
    }

    private static let maxPicks = 16

    /// Picks the highlighted candidate as Space would until no pinyin is left (a long input can take
    /// several picks); the words go to the draft.
    private func convertComposition(_ engine: PinyinEngine) -> [Effect] {
        var effects: [Effect] = []
        for _ in 0..<Self.maxPicks {
            let before = engine.snapshot()
            guard before.isComposing else { break }
            _ = engine.processKey(RimeKey.space, mask: 0)
            let committed = engine.takeCommit() ?? ""
            if !committed.isEmpty { effects += accept(committed) }
            if committed.isEmpty, engine.snapshot() == before { break }  // Space picks nothing here
        }
        // Whatever Space didn't convert goes in the way the engine commits a composition.
        if engine.snapshot().isComposing, let rest = engine.commitComposition(), !rest.isEmpty {
            effects += accept(rest)
        }
        engineState = engine.snapshot()
        return effects
    }

    /// Space (or the action key) in level two: inserts the highlighted line once it is complete;
    /// after a failure, asks again (a reminder with nothing to be reminded of would fail again: back to
    /// its text, like Esc).
    private func acceptInLevelTwo() -> [Effect] {
        if case .failed = phase { return activeCommand?.kind == .reminder ? backToDraft() : startAction().effects }
        return commitChoice(at: highlighted)
    }

    private func backToDraft() -> [Effect] {
        var effects: [Effect] = []
        if case .translating = phase { effects.append(.cancelConversion) }
        result = .empty
        searchResults = []
        pendingReminder = nil
        activeCommand = nil
        highlightOverride = nil
        setLevelOnePhase()
        return effects + [.updateMarkedText, wantsPanel ? .showPanel : .hidePanel]
    }

    private func commitChoice(at index: Int) -> [Effect] {
        let all = choices
        guard all.indices.contains(index), all[index].isComplete, !all[index].text.isEmpty else { return [] }
        if case let .file(path) = all[index].kind { return finish(committing: "") + [.open(path: path)] }
        if case let .reminder(reminder) = all[index].kind {
            let input = sentText  // before the draft is cleared: it comes back if the reminder can't be added
            return finish(committing: "") + [.addReminder(reminder, input: input)]
        }
        if case .send = all[index].kind, let recipient = messageRecipient, let command = activeCommand {
            // Sent, not inserted: the draft goes.
            return finish(committing: "") + [.sendMessage(recipient, text: all[index].text, command: command), used(command)]
        }
        if typesResults { return finish(committing: "") + [.typeOut(all[index].text)] }
        return finish(committing: all[index].text)
    }

    private func moveHighlight(by delta: Int) -> [Effect] {
        let count = choices.count
        guard count > 0 else { return [] }
        let current = min(highlighted, count - 1)
        highlightOverride = (current + delta + count) % count
        return [.showPanel]
    }

    /// Ends the composition, inserting `text`, and clears the engine.
    private func finish(committing text: String) -> [Effect] {
        var effects: [Effect] = []
        if case .translating = phase { effects.append(.cancelConversion) }
        if let id = voice.id { effects += cancelVoice(id, refresh: false) }
        engine?.clearComposition()
        engineState = engine?.snapshot() ?? .empty
        draft = ""
        pendingAccent = nil
        _ = hangul.flush()
        messageRecipient = nil
        clearRecipientResults()
        draftEndsWithVoice = false
        actsAfterVoice = false
        result = .empty
        searchResults = []
        pendingReminder = nil
        activeCommand = nil
        paletteHighlight = 0
        pendingPaste = nil  // a paste still on its way is dropped
        liveResults = []
        liveResultsQuery = nil
        resetLiveHighlight()
        highlightOverride = nil
        phase = .idle
        restoreInputModeAfterOpen()
        effects.append(.hidePanel)
        effects.append(text.isEmpty ? .updateMarkedText : .commit(text))
        return effects
    }
}
