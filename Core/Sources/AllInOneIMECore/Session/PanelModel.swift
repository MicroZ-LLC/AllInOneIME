import Foundation

/// The candidate panel as data, the same on every platform: what `PanelPresenter` makes of the composer, and what each
/// shell draws (the Mac: `CandidateView`). From top to bottom: Translate as You Type's chip, where a conversation can go
/// on (`handoff`), the input line, the header's lines, the rows, the status, and the footer with the detail on its
/// right. Its text is in the language and with the key names it was made with; what is structure (a caret, a list of
/// choices, lines) is data, for each shell to draw its own way.
public struct PanelModel: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        /// How a row is drawn.
        public enum Kind: Equatable, Sendable {
            /// Level-one pinyin candidate (and a list's row).
            case candidate
            /// The sentence as typed (level two, row 0); dimmed.
            case original
            /// A version or rewrite from the model (level two).
            case translation
        }

        /// Its number ("1"), or "" (a row nothing picks by number), or a mark ("✓", "›"), or the key that picks it (a
        /// message to send, an issue to open: ⏎, "Enter").
        public var label: String
        public var text: String
        /// Smaller, after the text: the language, the style, where a file is …
        public var comment: String
        public var kind: Kind
        /// False while it's still coming in (a caret after it).
        public var isComplete: Bool
        /// A symbol in a colored rounded square before the text, like the icons of iOS Settings.
        public var icon: IconToken?
        /// A click picks it and the pointer over it highlights it; not a line a script printed or a list's information,
        /// which nothing picks.
        public var pickable: Bool
        /// What a click on it picks: the index `Composer.choose(index:)` takes, which the session finds here for the row
        /// a shell says was clicked (`SessionEvent.pick`). The row's own index, but in a conversation, whose rows are its
        /// questions and answers, an answer's round, and nil for a question.
        public var choice: Int?

        public init(label: String, text: String, comment: String = "", kind: Kind, isComplete: Bool = true,
                    icon: IconToken? = nil, pickable: Bool = true, choice: Int? = nil) {
            self.label = label
            self.text = text
            self.comment = comment
            self.kind = kind
            self.isComplete = isComplete
            self.icon = icon
            self.pickable = pickable
            self.choice = choice
        }
    }

    /// The line under the rows.
    public enum Status: Equatable, Sendable {
        case none
        /// Waiting for something (dimmed).
        case loading(String)
        case hint(String)
        /// A hint with a list under it, an item a line (what an issue report fills in besides its title).
        case list(String, items: [String])
        /// Drawn in red, after "⚠︎". A message from elsewhere (a script's error, a server's) may have line breaks.
        case error(String)
    }

    /// The line of input on top, with its caret: a command written on the selected text (it isn't marked in the field),
    /// a refine instruction or an `@question` conversation's next question being typed.
    public struct Input: Equatable, Sendable {
        /// What it is, before the text: "refine › ", "question 2/5 › " (empty: the text says it, "improve › …").
        public var prompt: String
        public var text: String
        /// Where the caret is in `text`, in characters (`Character`, 0 … text.count); nil: none, the text only shown (a
        /// command sent).
        public var caret: Int?

        public init(prompt: String = "", text: String, caret: Int?) {
            self.prompt = prompt
            self.text = text
            self.caret = caret
        }
    }

    /// Where an `@question` conversation can go on (after its last round, or ⌘⏎): a title, and the destinations, each
    /// with the shortcut that picks it ("⌘1", "Ctrl+1").
    public struct Handoff: Equatable, Sendable {
        public struct Choice: Equatable, Sendable {
            public var shortcut: String
            public var name: String

            public init(shortcut: String, name: String) {
                self.shortcut = shortcut
                self.name = name
            }
        }

        public var title: String
        public var choices: [Choice]

        public init(title: String, choices: [Choice]) {
            self.title = title
            self.choices = choices
        }
    }

    /// Translate as You Type's chip (「中 → 英」): the language typed and the one it translates into, each a part to click.
    public struct Chip: Equatable, Sendable {
        public var source: String
        public var target: String

        public init(source: String, target: String) {
            self.source = source
            self.target = target
        }

        /// As the panel draws it in the interface language `language`: 「中 → 英」 in Chinese (「中 → 韓」 in Traditional
        /// Chinese), the language codes ("ZH → EN") in the others.
        public init(_ chip: TranslateMode.Chip, language: String) {
            let t = InterfaceWords(language: language)
            if t.chinese {
                self.init(source: t.chineseOnly(chip.sourceText), target: t.chineseOnly(chip.targetText))
            } else {
                self.init(source: chip.sourceTag, target: chip.targetTag)
            }
        }
    }

    /// A part of the chip, clicked.
    public enum ChipPart: Equatable, Sendable {
        case source, target
    }

    public var rows: [Row]
    public var highlighted: Int?
    public var status: Status
    /// The line of input with its caret, first (or after `handoff`).
    public var input: Input?
    /// Where a conversation can go on, on top.
    public var handoff: Handoff?
    /// The lines above the rows, each its own: what the panel works on (the text selected in the field), what the draft
    /// has attached (a screenshot's two), the refinements so far.
    public var header: [String]
    public var footer: String
    /// On the footer's right: the page, the time a result took, a notice.
    public var detail: String?
    /// The rows side by side, as macOS's own panel (`Config.candidateLayout`): the engine's candidates only.
    public var horizontal: Bool
    /// The rows are a conversation (`@question`): the panel is no taller than about half the screen, the rows scrolled
    /// to show the last one (or the highlighted one, when it's above).
    public var transcript: Bool
    /// Translate as You Type's chip on top; with it the panel is only as wide as it needs, unless a footer is there.
    public var chip: Chip?

    public init(rows: [Row] = [], highlighted: Int? = nil, status: Status = .none, input: Input? = nil, handoff: Handoff? = nil,
                header: [String] = [], footer: String = "", detail: String? = nil, horizontal: Bool = false,
                transcript: Bool = false, chip: Chip? = nil) {
        self.rows = rows
        self.highlighted = highlighted
        self.status = status
        self.input = input
        self.handoff = handoff
        self.header = header
        self.footer = footer
        self.detail = detail
        self.horizontal = horizontal
        self.transcript = transcript
        self.chip = chip
    }

    /// A short notice on its own ("英", "已复制" …): the panel when there's nothing else to show.
    public static func notice(_ text: String) -> PanelModel { PanelModel(status: .hint(text)) }
}
