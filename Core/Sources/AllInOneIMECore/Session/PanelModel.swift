import Foundation

/// The candidate panel as data, the same on every platform: what `PanelPresenter` makes of the composer, and what each
/// shell draws (the Mac: `CandidateView`). From top to bottom: Translate as You Type's chip, the input line, the header,
/// the rows, the status, and the footer with the detail on its right.
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

        /// Its number ("1"), or "" (a row nothing picks by number), or a mark ("✓", "›").
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

        public init(label: String, text: String, comment: String = "", kind: Kind, isComplete: Bool = true,
                    icon: IconToken? = nil, pickable: Bool = true) {
            self.label = label
            self.text = text
            self.comment = comment
            self.kind = kind
            self.isComplete = isComplete
            self.icon = icon
            self.pickable = pickable
        }
    }

    /// The line under the rows.
    public enum Status: Equatable, Sendable {
        case none
        /// Waiting for something (dimmed).
        case loading(String)
        case hint(String)
        /// Drawn in red, after "⚠︎".
        case error(String)
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
    /// The command being written, as a line of input with its caret (▏), first: it isn't marked in the field (a
    /// command on the selected text).
    public var input: String?
    /// A line above the rows: what the panel works on (the text selected in the field).
    public var header: String?
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

    public init(rows: [Row] = [], highlighted: Int? = nil, status: Status = .none, input: String? = nil, header: String? = nil,
                footer: String = "", detail: String? = nil, horizontal: Bool = false, transcript: Bool = false, chip: Chip? = nil) {
        self.rows = rows
        self.highlighted = highlighted
        self.status = status
        self.input = input
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
