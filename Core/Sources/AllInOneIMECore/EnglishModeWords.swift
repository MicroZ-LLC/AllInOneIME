import Foundation

/// The words typed in English mode (after a tap of Shift: letters go straight to the app, nothing is shown), followed key
/// by key in one text field, for the session to learn as it learns letters put in as typed while typing pinyin
/// (`InputSession`, by `EnglishWords.learnsTypedInEnglish`). Nothing in English mode changes: this only remembers.
///
/// A word is the Latin letters typed between two non-letters: after a space, a line, an opening mark ("(", a quote), the
/// field's start, or what the input method put in when that ends with a space or Chinese, Japanese or Korean text or marks
/// ("用kubectl"); before a space, ⏎, or marks that end it ("word," "word." "word)") then one of those, or before a tap of
/// Shift out of English mode, which ends a word typed among Chinese ("用 kubectl部署"). It stands once the next key leaves
/// it as it is: ⌫ or ⌦ after it (an edit), an arrow, Home, End or a shortcut (the caret moved, ⌘Z), a click since
/// (`pointerUsedSince`) drop it. Letters with a digit or another mark inside or around them are none ("example.com",
/// "user@host", "don't", "e-mail", "abc123", "#tag"), nor are letters edited with ⌫ while typed, letters typed where the
/// caret may be inside a word (after an arrow, a click, ⇥, letters the input method put in) or more than
/// `EnglishWords.maxLearned` of them: no word then until the next space or line. A word followed by marks when the field
/// loses the focus stands; letters alone ("frobn", maybe a search that completes itself) don't.
///
/// In memory only (the letters of the word being typed and of the one before it), the field's: forgotten with the focus.
/// Used from the session's thread.
public struct EnglishModeWords: Sendable {
    private enum Phase: Sendable {
        /// Where a word may start.
        case start
        /// Letters being typed.
        case word
        /// A word, then marks that may end it ("word," "word.)"): a word if a space or a line follows.
        case closed
        /// No word until the next space or line.
        case spoilt
    }

    private var phase = Phase.start
    private var letters = ""
    /// Since when the caret has been where the word starts: the key before its first letter (its first letter when it is
    /// the field's first key). A click since then may have moved it.
    private var since: TimeInterval = 0
    /// The word that ended, and when: it stands once the next key leaves it as it is.
    private var ended: (word: String, at: TimeInterval)?
    /// When the last key went in, or the input method put text in (nil: nothing yet in this field).
    private var last: TimeInterval?

    /// Marks a word may follow, and marks that may end one.
    static let opening: Set<Character> = ["(", "[", "{", "\"", "'", "“", "‘", "¿", "¡"]
    static let closing: Set<Character> = [",", ".", ";", ":", "!", "?", ")", "]", "}", "\"", "'", "”", "’", "…"]

    public init() {}

    /// A key that went straight to the app, at `time` (`ProcessInfo.systemUptime`), `english` in English mode (anywhere
    /// else letters make no word: a key that passes Chinese pinyin by, ⌫ or a space, still counts): the word that stood,
    /// if one did. `pointerUsedSince(t)`: whether the mouse or trackpad was used since `t`.
    public mutating func typed(_ key: KeyEvent, english: Bool, at time: TimeInterval,
                               pointerUsedSince: (TimeInterval) -> Bool) -> [String] {
        defer { last = time }
        guard key.modifiers.isDisjoint(with: [.command, .control]) else { return moved() }  // ⌘Z, ⌃A …
        switch key.key {
        case .backspace, .forwardDelete:
            return moved()
        case .space, .enter, .keypadEnter:
            return boundary(at: time, pointerUsedSince)
        case .tab, .escape:
            // ⇥ may take an editor's completion of the letters typed, Esc may close one: the word before stands.
            defer { spoil() }
            return stand(pointerUsedSince)
        case .character:
            guard let text = key.printableText else { return moved() }
            if text.allSatisfy(\.isWhitespace) { return boundary(at: time, pointerUsedSince) }
            let stood = stand(pointerUsedSince)
            for character in text { add(character, english: english, at: time, pointerUsedSince) }
            return stood
        default:
            return moved()  // an arrow, Home, End, Page Up or Down …: the caret moved
        }
    }

    /// The input method took a key and put `text` in (nil: nothing yet: pinyin being typed, a command): the word that
    /// ended stands. After a space, a line, Chinese, Japanese or Korean text or marks a word may start; after letters,
    /// digits or other marks none does (a word picked among pinyin's candidates, then "s").
    public mutating func inputMethodTook(inserting text: String?, at time: TimeInterval,
                                         pointerUsedSince: (TimeInterval) -> Bool) -> [String] {
        defer { last = time }
        let stood = stand(pointerUsedSince)
        if let end = text?.last {
            letters = ""
            phase = end.isWhitespace || Composer.isCJK(end) ? .start : .spoilt
        } else if phase == .word || phase == .closed {
            spoil()  // a dead key's accent in a word, say
        }
        return stood
    }

    /// English mode ended (a tap of Shift into Chinese): the word typed ends there as at a space ("kubectl部署").
    public mutating func leftEnglish(at time: TimeInterval, pointerUsedSince: (TimeInterval) -> Bool) -> [String] {
        boundary(at: time, pointerUsedSince)
    }

    /// The field lost the focus: the word that ended stands, and one followed by marks ("…frobnicate."); then all is
    /// forgotten (another field starts afresh). No click is looked for: the one that took the focus elsewhere changed
    /// nothing in this field.
    public mutating func leftField() -> [String] {
        let stood = (ended.map { [$0.word] } ?? []) + (phase == .closed ? [letters] : [])
        self = EnglishModeWords()
        return stood
    }

    // MARK: -

    /// A character typed in the word, or around it.
    private mutating func add(_ character: Character, english: Bool, at time: TimeInterval,
                              _ pointerUsedSince: (TimeInterval) -> Bool) {
        let letter = english && character.isASCII && character.isLetter
        switch phase {
        case .start:
            if letter {
                (phase, letters, since) = (.word, String(character), last ?? time)
            } else if !Self.opening.contains(character) {
                phase = .spoilt
            }
        case .word:
            if letter {
                letters.append(character)
                if letters.count > EnglishWords.maxLearned { spoil() }
            } else if Self.closing.contains(character), !pointerUsedSince(since) {
                phase = .closed
            } else {
                spoil()
            }
        case .closed:
            if !Self.closing.contains(character) { spoil() }
        case .spoilt:
            break
        }
    }

    /// A space, a line, English mode left: the word that ended before stands, and the one typed ends: it stands once the
    /// next key leaves it as it is, when the caret stayed where it started (no click since). A word may start after.
    private mutating func boundary(at time: TimeInterval, _ pointerUsedSince: (TimeInterval) -> Bool) -> [String] {
        let stood = stand(pointerUsedSince)
        if phase == .word && !pointerUsedSince(since) || phase == .closed { ended = (letters, time) }
        (phase, letters) = (.start, "")
        return stood
    }

    /// The word that ended stands: the key after it leaves it as it is, and nothing was clicked since (a click may have
    /// put the caret into it).
    private mutating func stand(_ pointerUsedSince: (TimeInterval) -> Bool) -> [String] {
        defer { ended = nil }
        guard let ended, !pointerUsedSince(ended.at) else { return [] }
        return [ended.word]
    }

    /// The text or the caret may have changed (⌫, an arrow, a shortcut): the word that ended goes, and none starts until
    /// a space or a line.
    private mutating func moved() -> [String] {
        ended = nil
        spoil()
        return []
    }

    private mutating func spoil() {
        (phase, letters) = (.spoilt, "")
    }
}
