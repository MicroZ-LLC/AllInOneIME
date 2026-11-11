import Foundation

/// Clipboard history's filter (0.7.3, owner feedback #1): what is typed while the panel shows keeps the rows that have
/// it. Each row is searched as the history keeps it, nothing read anew: a text anywhere in it, in any case; one with
/// Chinese in it by its pinyin too, each character's syllable spelled in full ("nihao" finds 你好) or its initial ("nh"),
/// whatever else is in it as it is, without spaces (发布 v2 by "fabuv2" or "fbv2"); an image by "image", "图片", its row's
/// words in the interface language and its size ("1280", "1280×720"). The row saying how to keep a history is never
/// found.
enum ClipboardFilter {
    /// What a row is found by, worked out once, on the first key that filters.
    struct Key {
        /// The text (an image's words), lowercased.
        var text: String
        /// A text with Chinese in it, in pinyin (`pinyin`); nil without.
        var spelled: String?
        var initials: String?
    }

    /// The most of a text read for its pinyin, in characters (Unicode scalars): a longer one is found by its pinyin in
    /// that much of it, by its text anywhere.
    static let pinyinLength = 10_000

    /// What `row` is found by, its words in `language` (an image's); nil: never found.
    static func key(_ row: ClipboardHistoryField.Row, language: String) -> Key? {
        switch row {
        case let .text(text, _):
            let pinyin = pinyin(text)
            return Key(text: text.lowercased(), spelled: pinyin?.spelled, initials: pinyin?.initials)
        case let .keptImage(image, _):
            let words = InputSession.clipboardRowText(row, now: .distantPast, passesPasteKey: true, in: InterfaceWords(language: language)).text
            return Key(text: ["image", "图片", words, "\(image.width)×\(image.height)", "\(image.width)x\(image.height)"]
                .joined(separator: " ").lowercased())
        case .image:
            let words = InputSession.clipboardRowText(row, now: .distantPast, passesPasteKey: true, in: InterfaceWords(language: language)).text
            return Key(text: ["image", "图片", words].joined(separator: " ").lowercased())
        case .permission:
            return nil
        }
    }

    /// Whether a row with `key` has `filter`: in its text, any case; with Chinese in it, the filter's letters without
    /// its spaces in its pinyin, spelled or by initials.
    static func matches(_ key: Key, _ filter: String) -> Bool {
        let filter = filter.lowercased()
        if key.text.contains(filter) { return true }
        guard let spelled = key.spelled, let initials = key.initials else { return false }
        let letters = filter.filter { !$0.isWhitespace }
        return !letters.isEmpty && (spelled.contains(letters) || initials.contains(letters))
    }

    /// `text` in pinyin, lowercased and without whitespace: each Chinese character as its syllable in full (`spelled`,
    /// "你好 v2" → "nihaov2") or its initial (`initials`, "nhv2"), anything else as it is in both. Nil without Chinese.
    static func pinyin(_ text: String) -> (spelled: String, initials: String)? {
        guard text.containsHan else { return nil }
        var spelled = "", initials = ""
        for scalar in text.unicodeScalars.prefix(pinyinLength) where !scalar.properties.isWhitespace {
            if scalar.properties.isIdeographic, let syllable = syllable(scalar), let initial = syllable.first {
                spelled += syllable
                initials.append(initial)
            } else {
                let lower = String(scalar).lowercased()
                spelled += lower
                initials += lower
            }
        }
        return (spelled, initials)
    }

    /// A Chinese character's syllable without tone marks ("好" → "hao"), as ICU reads it (Mandarin, its most common
    /// reading), looked up once a process; nil where it has none.
    private static func syllable(_ scalar: Unicode.Scalar) -> String? {
        if let known = syllables.withLock({ $0[scalar] }) { return known.isEmpty ? nil : known }
        let latin = String(scalar).applyingTransform(.mandarinToLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false)?.lowercased().filter { $0.isASCII && $0.isLetter } ?? ""
        syllables.withLock { $0[scalar] = latin }
        return latin.isEmpty ? nil : latin
    }

    /// The syllables looked up so far ("": none).
    private static let syllables = Locked<[Unicode.Scalar: String]>(initialState: [:])
}
