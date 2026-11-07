import Foundation

/// The candidate panel as data, the same on every platform: what `PanelPresenter` makes of the composer, and what each
/// shell draws (the Mac: `CandidateView`). From top to bottom: Translate as You Type's chip, where a conversation can go
/// on (`handoff`), the input line, the header's lines, the rows, the status, and the footer with the detail on its right;
/// the pinyin candidates shown with the rows (`candidates`) on the side nearest the caret. Its text is in the language
/// and with the key names it was made with; what is structure (a caret, a list of choices, lines) is data, for each
/// shell to draw its own way.
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

        // What follows only says how the row looks: a shell may draw the row without it, from what is above.

        /// What picking it does, in a word or two of the interface language ("打开", "上屏", "保留原文"): one @'s rows, said
        /// on the highlighted one, and the sentence as typed (row 0), said beside it. Nil: not said.
        public var action: String?
        /// The start of `comment` as a tag of its own: a rewrite's style ("润色"), a translation's language. Nil: none.
        public var tag: Tag?
        /// Whether `comment` only describes what the row does (a built-in command's summary in the one @ list): a shell
        /// that keeps those rows short may leave it out.
        public var commentDescribes: Bool
        /// Smaller, before the text: what an arithmetic result answers ("23*17", its text "= 391"). Nil: none.
        public var lead: String?

        /// A tag on a row: its text, and what it is for a shell that tints it (a rewrite style's `RewriteStyle.tag`:
        /// "POLISH", "CONCISE", "FORMAL" …; "": none, neutral).
        public struct Tag: Equatable, Sendable {
            public var text: String
            public var tint: String

            public init(text: String, tint: String = "") {
                self.text = text
                self.tint = tint
            }
        }

        public init(label: String, text: String, comment: String = "", kind: Kind, isComplete: Bool = true,
                    icon: IconToken? = nil, pickable: Bool = true, choice: Int? = nil, action: String? = nil, tag: Tag? = nil,
                    commentDescribes: Bool = false, lead: String? = nil) {
            self.label = label
            self.text = text
            self.comment = comment
            self.kind = kind
            self.isComplete = isComplete
            self.icon = icon
            self.pickable = pickable
            self.choice = choice
            self.action = action
            self.tag = tag
            self.commentDescribes = commentDescribes
            self.lead = lead
        }
    }

    /// A key and what it does ("⏎" "上屏"), as a shell draws the footer: the key on a keycap, the words after it.
    public struct Hint: Equatable, Sendable {
        public var key: String
        public var text: String

        public init(_ key: String, _ text: String) {
            self.key = key
            self.text = text
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
    /// The row the key that picks takes (⏎, Space; Tab too on suggestions' rows): drawn selected.
    public var highlighted: Int?
    public var status: Status
    /// The line of input with its caret, first (or after `handoff`).
    public var input: Input?
    /// Where a conversation can go on, on top.
    public var handoff: Handoff?
    /// The lines above the rows, each its own: what the panel works on (the text selected in the field), what the draft
    /// has attached (a screenshot's two), the refinements so far.
    public var header: [String]
    /// The pinyin candidates on one line ("1 你好   2 拟好 …"), while they are composed with rows that aren't them (one @'s
    /// after the magic key), on the side of the panel nearest the caret, the rows on the far side: the word is picked
    /// first, then what to do with it. Below the caret, at the top, under the input line; above it, under the rows and the
    /// status, just above the footer. The header (a selection's line) stays just above the rows either way. Nil: none
    /// (plain typing's candidates are the rows).
    public var candidates: String?
    public var footer: String
    /// On the footer's right: the page, the time a result took, a notice.
    public var detail: String?
    /// The footer as a few keys, for a shell that draws them as keycaps (the Mac): the two or three that matter here, and
    /// before them a line of what is going on (`note`: "Claude Haiku 4.5 在写…"), the detail on the right as with `footer`.
    /// Empty and nil: `footerHints`, from `footer`. `footer` still says it all.
    public var hints: [Hint]
    public var note: String?
    /// What Space does with the pinyin candidates' line ("空格" "选词"), said at its end. Nil: not said.
    public var candidatesHint: Hint?
    /// How many more rows are on their way (an AI's versions not in yet): a shell may hold their places. 0: none.
    public var pending: Int
    /// The rows side by side, as macOS's own panel (`Config.candidateLayout`): the engine's candidates only.
    public var horizontal: Bool
    /// The rows are a conversation (`@question`): the panel is no taller than about half the screen, the rows scrolled
    /// to show the last one (or the highlighted one, when it's above).
    public var transcript: Bool
    /// Translate as You Type's chip on top; with it the panel is only as wide as it needs, unless a footer is there.
    public var chip: Chip?

    public init(rows: [Row] = [], highlighted: Int? = nil, status: Status = .none, input: Input? = nil,
                handoff: Handoff? = nil, header: [String] = [], candidates: String? = nil, footer: String = "", detail: String? = nil,
                horizontal: Bool = false, transcript: Bool = false, chip: Chip? = nil, hints: [Hint] = [], note: String? = nil,
                candidatesHint: Hint? = nil, pending: Int = 0) {
        self.rows = rows
        self.highlighted = highlighted
        self.status = status
        self.input = input
        self.handoff = handoff
        self.header = header
        self.candidates = candidates
        self.footer = footer
        self.detail = detail
        self.horizontal = horizontal
        self.transcript = transcript
        self.chip = chip
        self.hints = hints
        self.note = note
        self.candidatesHint = candidatesHint
        self.pending = pending
    }

    /// A short notice on its own ("英", "已复制" …): the panel when there's nothing else to show.
    public static func notice(_ text: String) -> PanelModel { PanelModel(status: .hint(text)) }
}

// MARK: - The footer as keys

extension PanelModel {
    /// The footer as a shell draws it with keycaps: `hints` and `note` where the presenter chose them, else read from
    /// `footer`'s text: each of its parts (between " · ") that starts with a key, as that key ("⏎" for "空格 / ⏎ 上屏")
    /// and the words after it; a part without one as its words (key ""), the first, when it says something is going on
    /// ("生成中…"), as the note. Left out: ↑↓ and digits (every list moves and picks so), and Esc where another key is
    /// said (it always backs out); three at most. None: the footer is only words, drawn as they are.
    public var footerHints: (note: String?, hints: [Hint]) {
        if !hints.isEmpty || note != nil { return (note, hints) }
        var note: String?
        var parts: [(hint: Hint, escape: Bool)] = []
        for (index, part) in footer.components(separatedBy: " · ").enumerated() {
            let words = part.split(separator: " ", omittingEmptySubsequences: true)
            guard let first = words.first else { continue }
            guard Self.isKey(first) else {
                if index == 0, part.hasSuffix("…") { note = part } else { parts.append((Hint("", part), false)) }
                continue
            }
            // The keys at its start ("空格 / ⏎", "Tab 或 ⏎", "→ or Esc"): the action key's if there, else the first.
            var keys = [first], rest = words.dropFirst()
            while rest.count >= 2, ["/", "或", "or"].contains(rest[rest.startIndex]), Self.isKey(rest[rest.startIndex + 1]) {
                keys.append(rest[rest.startIndex + 1])
                rest = rest.dropFirst(2)
            }
            guard !keys.contains(where: { $0.contains("↑") || $0.contains("↓") || $0.allSatisfy { $0.isNumber || $0 == "–" || $0 == "-" } })
            else { continue }
            let key = keys.first { ["⏎", "↩", "Enter", "Return"].contains($0) } ?? keys[0]
            parts.append((Hint(String(key), rest.joined(separator: " ")), key == "Esc"))
        }
        guard parts.contains(where: { !$0.hint.key.isEmpty }) else { return (nil, []) }
        if parts.contains(where: { !$0.hint.key.isEmpty && !$0.escape }) { parts.removeAll { $0.escape } }
        return (note, parts.prefix(3).map(\.hint))
    }

    /// Whether a word of the footer names a key: a key's symbol (⏎, ⌘C, ⇧⏎, →, ↑↓ …), its name (Esc, Tab, 空格 …), a
    /// shortcut written out (Ctrl+C), or a digit or range of them (0, 1–9).
    static func isKey(_ word: Substring) -> Bool {
        guard let first = word.unicodeScalars.first else { return false }
        if "⌘⌥⇧⌃⏎↩⌫⌦⇥⎋→←↑↓".unicodeScalars.contains(first) { return true }
        if ["Esc", "Tab", "Enter", "Return", "Space", "空格", "Backspace", "Delete", "Del"].contains(word) { return true }
        if let plus = word.firstIndex(of: "+"), ["Ctrl", "Shift", "Alt", "Win"].contains(word[..<plus]) { return true }
        return word.first?.isNumber == true && word.allSatisfy { $0.isNumber || $0 == "–" || $0 == "-" }
    }
}
