import Foundation

/// What a text field's session hears (`InputSession.handle`): from the shell (keys, the focus, a click in the panel) and
/// from its own work, which the shell hands back on the session's thread (`task`, `timer`).
public enum SessionEvent: Sendable {
    /// A key went down in the field, with what the field says around it (`FieldContext`).
    case key(KeyEvent, FieldContext)
    /// The modifier keys changed (the application sees them too).
    case modifiers(ModifierChange, FieldContext)
    /// The field took the focus.
    case focus(FieldInfo)
    /// The field lost the focus: what's pending goes in, running requests stop.
    case blur
    /// The app wants what's pending in now (a click elsewhere in it).
    case commit
    /// A row of the candidate panel clicked (its index in `PanelModel.rows`: the session picks its `choice`); its list
    /// scrolled by `steps` rows.
    case pick(Int)
    case scroll(Int)
    /// The clipboard as `SessionOutput.readClipboard` asked for it, for the draft's request `id`.
    case clipboard(ClipboardContent, id: Int)
    /// What the field says as `SessionOutput.readField` asked for it (its `id`: autocomplete's pause, or below 0 coding
    /// mode's): whether secure input is on, the selection, the text around the caret (what wasn't read,
    /// `FieldContext.read`, counts as unknown).
    case field(FieldContext, id: Int)
    /// What the session's work answers (`SessionTasks`).
    case task(TaskID, TaskUpdate)
    /// A timer the session started (`SessionOutput.startTimer`) went off.
    case timer(TimerID)
    /// Voice input, as the shell records it (`PlatformAction.startVoice`).
    case voice(VoiceUpdate)
    /// The settings changed: applied now (a shell that doesn't read them again on every key).
    case configChanged
    /// The field's session ends: nothing more comes, unless the field takes the focus again (it starts over then).
    case close
}

/// What the session answers an event with: whether it took a key (false: the application gets it too), and what the shell
/// does, in order.
public struct SessionResponse: Equatable, Sendable {
    public var handled: Bool
    public var outputs: [SessionOutput]

    public init(handled: Bool = true, outputs: [SessionOutput] = []) {
        self.handled = handled
        self.outputs = outputs
    }
}

/// What the shell does for the session, to the field and on the screen.
public enum SessionOutput: Equatable, Sendable {
    /// Text in at the caret, in place of the marked text (in a terminal, text with line breaks as a paste where the shell
    /// can paste).
    case commit(String)
    /// Text in once the key being answered is done, in the field of the key (`Composer.Effect.commitAfterKey`).
    case commitAfterKey(String)
    /// Text in place of `range` (UTF-16; nil: what is selected), never as a paste: a result over the selection a command
    /// worked on.
    case replace(String, range: Range<Int>?)
    /// The marked text: `text`, the caret `cursor` UTF-16 units into it, `converted` at level two. Empty: none of ours
    /// (leave the document alone if the shell set none).
    case marked(String, cursor: Int, converted: Bool)
    /// `text` typed out like a person typing (`Config.typeOut`); the marked text is gone.
    case typeOut(String)
    /// The caret `back` UTF-16 units into `inserted`, the text just put in (a snippet's `{cursor}`); once typed out, if it is.
    case moveCaret(back: Int, after: String?)
    /// The candidate panel as `model`; nil: nothing of the session's to show (hidden, unless the shell has something of
    /// its own there, Translate as You Type's chip).
    case panel(PanelModel?)
    /// A notice, with nothing else shown: on its own near the caret (the panel shows it otherwise).
    case notice(String)
    /// A notice for the field being typed in now, else on its own near the pointer: this field is no longer the one it
    /// was meant for (a save that came back after the field was left). `endingHere`: the progress notice to take down here.
    case noticeElsewhere(String, long: Bool, endingHere: String?)
    /// Open a file, a folder, an app or a web address.
    case open(String)
    /// Open a background agent's session (`@tasks`).
    case openAgent(String)
    /// Open the settings, at `place` (nil: as they open).
    case openSettings(SettingsPlace?)
    /// `text` on the clipboard.
    case copy(String)
    /// Read the clipboard for request `id`, once the key is answered (the system may ask first) and never during secure
    /// input; it comes back as `SessionEvent.clipboard`.
    case readClipboard(id: Int)
    /// Type with the keyboard layout of the input language now (`Composer.inputLanguage`).
    case keyboardLayout
    /// `SessionEvent.timer(id)` after `seconds`.
    case startTimer(TimerID, after: TimeInterval)
    /// Read what the field says now (secure input, the selection, the text around the caret: up to
    /// `Autocomplete.beforeLimit` characters before it and `Autocomplete.afterLimit` after it; for an `id` below 0, coding
    /// mode's words once typing paused, `ReplyContext.Limits.fieldBefore` and `fieldAfter`), never during secure input,
    /// and hand it back as `SessionEvent.field` with `id`. A shell that can't read it answers with nothing read.
    case readField(id: Int)
    /// Autocomplete's suggestion (`Autocomplete`): `text` in gray right after the caret (where the caret can't be placed,
    /// a line of the candidate panel), until the next one; nil: none. Shown again as the caret moves (typed along).
    case ghost(String?)
    /// What only some platforms can do.
    case platform(PlatformAction)
}

/// What a session asks of the platform that not every one can do; one that can't answers as if it failed.
public enum PlatformAction: Equatable, Sendable {
    /// Record and recognize speech in `language` for dictation `id` (`SessionEvent.voice`); stop it and deliver the final
    /// transcript; stop it and drop the result.
    case startVoice(id: Int, language: Language)
    case stopVoice(id: Int)
    case cancelVoice(id: Int)
}

/// Dictation `id`, as the platform hears it.
public enum VoiceUpdate: Equatable, Sendable {
    case text(String, id: Int)
    case finished(String, id: Int)
    case failed(String, id: Int)
}

/// A timer of the session's (`SessionOutput.startTimer`): a newer one of a kind makes the older one's firing do nothing.
public enum TimerID: Hashable, Sendable {
    /// The notice up now expires.
    case notice(Int)
    /// The voice key has been held long enough to dictate.
    case voiceHold(Int)
    /// Autocomplete's pause is over (`Autocomplete.Route.pause`): its suggestion may be asked for.
    case autocomplete(Int)
    /// Suggestions' (`InputSession+Suggestions.swift`): Shift held long enough for the chooser, a pause before a query
    /// is asked again, a list's refresh (or its back-off or pause) due.
    case suggestions(SuggestionsTimer)
}

/// A timer of suggestions' (`TimerID.suggestions`), counted: an older one of a kind does nothing.
public enum SuggestionsTimer: Hashable, Sendable {
    /// The long press of Shift half way (its hint), then long enough for the chooser.
    case chooserHint(Int)
    case chooser(Int)
    case query(Int)
    case refresh(Int)
    /// A pause in typing in coding mode: the field's words read again (`SessionOutput.readField`).
    case words(Int)
}

/// The modifier keys changed: `key` the one that did (`.modifier(kind, side)`), `modifiers` those down now with their
/// sides, `timestamp` when (seconds), `late` how long ago that was when the shell got it (the pointer is asked later:
/// it looks back that much further).
public struct ModifierChange: Equatable, Sendable {
    public var key: Key
    public var modifiers: Modifiers
    public var timestamp: TimeInterval
    public var late: TimeInterval

    public init(key: Key, modifiers: Modifiers, timestamp: TimeInterval, late: TimeInterval = 0) {
        self.key = key
        self.modifiers = modifiers
        self.timestamp = timestamp
        self.late = late
    }
}

/// The text field a session is in, as the shell tells it when the field takes the focus.
public struct FieldInfo: Equatable, Sendable {
    /// The app (its bundle id on the Mac): its own settings (`AppProfile`).
    public var app: String?
    /// A terminal: it runs every line it is given, pastes on ⌘V itself, tells nothing of its text.
    public var terminal: Bool
    /// A password field (Windows' `IS_PASSWORD` scope): nothing is composed or sent. (The Mac tells secure input per key,
    /// `FieldContext.secure`, and anywhere, `SessionServices.secureInputActive`.)
    public var secure: Bool

    public init(app: String? = nil, terminal: Bool = false, secure: Bool = false) {
        self.app = app
        self.terminal = terminal
        self.secure = secure
    }
}

/// What the field says when a key goes down, read by the shell before it hands the key on: the core never asks the field
/// in the middle of a key. A shell where reading is cheap reads it all; one where it isn't reads what the key may need
/// (`InputSession.fieldWants`). What wasn't read (`read`) counts as unknown.
public struct FieldContext: Equatable, Sendable {
    public struct Parts: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let secure = Parts(rawValue: 1 << 0)
        public static let markedText = Parts(rawValue: 1 << 1)
        public static let selectedRange = Parts(rawValue: 1 << 2)
        public static let selection = Parts(rawValue: 1 << 3)
        public static let beforeCaret = Parts(rawValue: 1 << 4)
        public static let text = Parts(rawValue: 1 << 5)
        public static let all: Parts = [.secure, .markedText, .selectedRange, .selection, .beforeCaret, .text]
    }

    /// What is right before the caret, as the field tells it.
    public enum BeforeCaret: Equatable, Sendable {
        /// It doesn't say: no caret, nothing read back (a terminal).
        case unknown
        /// Nothing: a selection, or the caret at the start.
        case nothing
        /// The character there.
        case text(String)
    }

    /// What the shell read.
    public var read: Parts
    /// The field of the key, when the shell tells it apart from the one that took the focus.
    public var field: FieldInfo?
    /// Secure input is on for this field's app (a password field or prompt): nothing is composed, keys go straight in.
    public var secure: Bool
    /// The app took the marked text on its own (it reports none where it had it: Slack's mention).
    public var markedTextTaken: Bool
    /// Where the selection is (UTF-16), as the field reports it; nil: it tells none.
    public var selectedRange: Range<Int>?
    /// The selected text, and where (`Composer.Selection`); nil: none.
    public var selection: Composer.Selection?
    public var beforeCaret: BeforeCaret
    /// The text around the caret, without the draft (`@reply`'s context).
    public var text: FieldText?

    public init(read: Parts = [], field: FieldInfo? = nil, secure: Bool = false, markedTextTaken: Bool = false,
                selectedRange: Range<Int>? = nil, selection: Composer.Selection? = nil, beforeCaret: BeforeCaret = .unknown,
                text: FieldText? = nil) {
        self.read = read
        self.field = field
        self.secure = secure
        self.markedTextTaken = markedTextTaken
        self.selectedRange = selectedRange
        self.selection = selection
        self.beforeCaret = beforeCaret
        self.text = text
    }
}
