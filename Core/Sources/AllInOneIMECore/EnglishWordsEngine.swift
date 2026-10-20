import Foundation

/// Level one's engine (librime with rime-ice) with English words among its candidates (`EnglishWords`). While Latin
/// letters alone are typed, the words of `words` whose letters begin with them (all of a word's letters, or
/// `EnglishWords.minPrefix` typed at least) go on the first page, numbered with librime's candidates, unless the page (in
/// any case) or rime-ice's English dictionary (`dictionary`: librime offers those itself) has them. They go where rime-ice
/// puts English (its `melt_eng` weighs less than pinyin; its `reduce_english_filter` puts a short word pinyin reads too
/// second): a word whose letters are all that was typed first, or second when that is pinyin too ("xiaomi"); a longer one
/// second, or after the page while what's typed may still be pinyin ("zhon", and up to four letters, which rime-ice reads
/// as initials: "bed" b-e-d). At most `maxPerPage`, the shorter first.
///
/// ↑↓ (← → in a row), Space, the digits and a click pick them as they pick librime's own; a punctuation key puts the word
/// highlighted in before its mark; anything else goes to librime as it would. Letters librime commits exactly as they were
/// typed (⏎, a tap of Shift) are told (`rawCommitted`): what the session learns words from. Main thread only, as librime.
public final class EnglishWordsEngine: PinyinEngine {
    public let base: PinyinEngine
    /// rime-ice's English words: those librime offers itself.
    public let dictionary: EnglishDictionary
    /// The words offered (`EnglishWords.offered`), as they are written; the first of two with the same letters counts.
    public var words: [String] {
        didSet { if words != oldValue { index = Self.index(words) } }
    }
    /// Letters librime committed exactly as they were typed, the whole composition (⏎, a tap of Shift).
    public var rawCommitted: ((String) -> Void)?
    /// The most words put on a page.
    public static let maxPerPage = 3

    /// The words by their letters (`EnglishWords.key`), sorted: those a prefix begins are side by side.
    private var index: [(key: String, word: String)]
    /// A place on the page as shown: librime's candidate (its place on librime's page), or a word.
    private enum Entry: Equatable {
        case base(Int)
        case word(String)
    }
    /// The word highlighted, by its place on the page as shown; nil: librime's own highlight.
    private var cursor: Int?
    /// The input, page and preedit the page was last laid out for: a change sets the highlight anew.
    private var laidOutFor: String?
    /// The word picked, for `takeCommit`.
    private var picked: String?
    /// The letters typed before the last key (what a commit as typed equals).
    private var rawBefore: String?

    public init(base: PinyinEngine, dictionary: EnglishDictionary, words: [String] = []) {
        self.base = base
        self.dictionary = dictionary
        self.words = words
        index = Self.index(words)
    }

    private static func index(_ words: [String]) -> [(key: String, word: String)] {
        var seen = Set<String>()
        return words.map { (EnglishWords.key($0), $0) }.filter { !$0.0.isEmpty && seen.insert($0.0).inserted }.sorted { $0.key < $1.key }
    }

    public var language: Language { base.language }
    public var rawInput: String { base.rawInput }

    // MARK: The page

    /// librime's page with the words for what is typed put in.
    private func layout(_ snap: EngineSnapshot) -> [Entry] {
        let rime = snap.candidates.indices.map(Entry.base)
        guard snap.isComposing, !snap.isAsciiMode, snap.pageNumber == 0, !index.isEmpty else { return rime }
        let raw = base.rawInput
        guard !raw.isEmpty, raw.allSatisfy({ $0.isASCII && $0.isLetter }),
              // Nothing of it picked yet ("你好ma": the page is for the rest), and librime's numbering, which the page's follows.
              snap.preedit.filter({ $0 != " " }) == raw,
              snap.candidates.enumerated().allSatisfy({ $0.element.label == String(($0.offset + 1) % 10) }),
              snap.candidates.count + Self.maxPerPage <= 10 else { return rime }
        let typed = raw.lowercased()
        let shown = Set(snap.candidates.map { $0.text.lowercased() })
        let found = matches(typed).filter { !shown.contains($0.word.lowercased()) && !dictionary.contains($0.key) }.prefix(Self.maxPerPage)
        guard !found.isEmpty else { return rime }
        let pinyin = Pinyin.isPinyin(typed), maybePinyin = Pinyin.isPinyinBeingTyped(typed)
        // Before librime's candidate of each place (the last: after them all).
        var before = [[Entry]](repeating: [], count: rime.count + 1)
        for match in found {
            let place = match.key == typed ? (pinyin ? 1 : 0) : (maybePinyin ? rime.count : 1)
            before[min(place, rime.count)].append(.word(match.word))
        }
        return rime.indices.flatMap { before[$0] + [rime[$0]] } + before[rime.count]
    }

    /// The words whose letters begin with `typed`: all of a word's letters, or `minPrefix` of them at least; the shorter
    /// first (the word that is all of them, then the next longest).
    private func matches(_ typed: String) -> [(key: String, word: String)] {
        var low = 0, high = index.count
        while low < high {
            let middle = (low + high) / 2
            if index[middle].key < typed { low = middle + 1 } else { high = middle }
        }
        var out: [(key: String, word: String)] = []
        for item in index[low...] {
            guard item.key.hasPrefix(typed) else { break }
            if item.key == typed || typed.count >= EnglishWords.minPrefix { out.append(item) }
        }
        return out.sorted { $0.key.count != $1.key.count ? $0.key.count < $1.key.count : $0.key < $1.key }
    }

    /// librime's state and the page as shown, the highlight set for a new input: on a word that comes first, else
    /// librime's.
    private func current() -> (snap: EngineSnapshot, entries: [Entry]) {
        let snap = base.snapshot()
        let entries = layout(snap)
        let laidOut = "\(base.rawInput)\u{0}\(snap.pageNumber)\u{0}\(snap.preedit)"
        if laidOut != laidOutFor {
            laidOutFor = laidOut
            cursor = entries.first.map(Self.isWord) == true ? 0 : nil
        }
        if let at = cursor, !(entries.indices.contains(at) && Self.isWord(entries[at])) { cursor = nil }
        return (snap, entries)
    }

    private static func isWord(_ entry: Entry) -> Bool {
        if case .word = entry { return true }
        return false
    }

    public func snapshot() -> EngineSnapshot {
        let (shown, entries) = current()
        var snap = shown
        guard entries.contains(where: Self.isWord) else { return snap }
        let rime = snap.candidates
        snap.candidates = entries.enumerated().map { place, entry in
            let label = String((place + 1) % 10)
            switch entry {
            case let .base(i): return EngineCandidate(label: label, text: rime[i].text, comment: rime[i].comment)
            case let .word(word): return EngineCandidate(label: label, text: word)
            }
        }
        if let cursor {
            // The letters as they were typed, as librime shows them with one of its English words highlighted.
            snap.highlighted = cursor
            snap.preedit = base.rawInput
            snap.cursor = snap.preedit.count
        } else {
            snap.highlighted = entries.firstIndex(of: .base(snap.highlighted)) ?? snap.highlighted
        }
        return snap
    }

    // MARK: Keys

    public func processKey(_ keycode: Int32, mask: Int32) -> Bool {
        let raw = base.rawInput
        if !raw.isEmpty { rawBefore = raw }
        if let handled = onPage(keycode, mask: mask) { return handled }
        return base.processKey(keycode, mask: mask)
    }

    /// A key that moves on the page or picks from it when it shows words; nil: librime's.
    private func onPage(_ keycode: Int32, mask: Int32) -> Bool? {
        guard mask & ~RimeKey.shiftMask == 0 else { return nil }  // releases and shortcuts are librime's
        let (snap, entries) = current()
        guard entries.contains(where: Self.isWord) else { return nil }
        let at = cursor ?? entries.firstIndex(of: .base(snap.highlighted)) ?? 0
        let word: String? = cursor.flatMap { if case let .word(word) = entries[$0] { return word } else { return nil } }
        if mask == RimeKey.shiftMask {
            // ⇧Space picks as Space does; ⇧ and a punctuation key ("!", "?"): the word highlighted goes in before it.
            guard let word else { return nil }
            if keycode == RimeKey.space { return pick(word) }
            return Self.isPunctuation(keycode) ? pick(word, then: keycode, mask: mask) : nil
        }
        switch keycode {
        case RimeKey.down: return move(to: at + 1, in: entries)
        case RimeKey.up: return move(to: at - 1, in: entries)
        case RimeKey.space:
            guard let word else { return nil }
            return pick(word)
        case 0x30...0x39:
            let place = keycode == 0x30 ? 9 : Int(keycode - 0x31)
            guard entries.indices.contains(place) else { return nil }
            return select(entries[place])
        case 0x5B, 0x5D:
            // [ and ] pick a candidate's first or last character (rime-ice): a word has none to pick.
            return word == nil ? nil : true
        default:
            guard let word, Self.isPunctuation(keycode) else { return nil }
            return pick(word, then: keycode, mask: mask)
        }
    }

    /// Marks that go in after the word highlighted: not those librime uses while composing (' between syllables, - =
    /// turning the page).
    private static func isPunctuation(_ keycode: Int32) -> Bool {
        guard (0x21...0x7E).contains(keycode), let scalar = Unicode.Scalar(UInt32(keycode)) else { return false }
        let character = Character(scalar)
        return !character.isLetter && !character.isNumber && !"'-=[]".contains(character)
    }

    /// The highlight moved to `place`: a word, or librime's candidate (its highlight moved there); past the page's
    /// ends, librime's key (its page turns).
    private func move(to place: Int, in entries: [Entry]) -> Bool? {
        if place < 0 { return cursor == nil ? nil : true }  // nothing before the first page
        guard place < entries.count else {
            cursor = nil
            if case let .base(last)? = entries.last(where: { !Self.isWord($0) }) { highlightBase(last) }
            return nil
        }
        switch entries[place] {
        case .word:
            cursor = place
        case let .base(i):
            cursor = nil
            highlightBase(i)
        }
        return true
    }

    /// librime's highlight on its candidate `i` of the page, moved there with its own ↑↓.
    private func highlightBase(_ i: Int) {
        for _ in 0..<10 {
            let now = base.snapshot().highlighted
            guard now != i else { return }
            _ = base.processKey(now < i ? RimeKey.down : RimeKey.up, mask: 0)
        }
    }

    /// A place on the page picked: a word goes in, librime's candidate is librime's to pick.
    private func select(_ entry: Entry) -> Bool {
        switch entry {
        case let .word(word): return pick(word)
        case let .base(i): return base.selectCandidate(onPage: i)
        }
    }

    /// `word` put in: what was typed for it goes, then `keycode` (a punctuation mark) to librime with nothing composed.
    private func pick(_ word: String, then keycode: Int32? = nil, mask: Int32 = 0) -> Bool {
        base.clearComposition()
        picked = (picked ?? "") + word
        cursor = nil
        rawBefore = nil
        if let keycode { _ = base.processKey(keycode, mask: mask) }
        return true
    }

    public func takeCommit() -> String? {
        let committed = base.takeCommit()
        if let word = picked {
            picked = nil
            return word + (committed ?? "")
        }
        if let committed, let before = rawBefore, committed == before, !base.snapshot().isComposing {
            rawCommitted?(committed)
        }
        if committed != nil { rawBefore = nil }
        return committed
    }

    public func selectCandidate(onPage index: Int) -> Bool {
        let raw = base.rawInput
        if !raw.isEmpty { rawBefore = raw }
        let (_, entries) = current()
        guard entries.contains(where: Self.isWord) else { return base.selectCandidate(onPage: index) }
        guard entries.indices.contains(index) else { return false }
        return select(entries[index])
    }

    /// The composition as converted text: the word highlighted, else librime's.
    public func commitComposition() -> String? {
        let (_, entries) = current()
        if let cursor, case let .word(word) = entries[cursor] {
            _ = pick(word)
            return takeCommit()
        }
        rawBefore = nil
        return base.commitComposition()
    }

    public func clearComposition() {
        cursor = nil
        rawBefore = nil
        base.clearComposition()
    }

    public func setAsciiMode(_ on: Bool) { base.setAsciiMode(on) }
}
