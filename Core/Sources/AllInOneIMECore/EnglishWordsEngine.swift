import Foundation

/// Level one's engine (librime with rime-ice) with English words among its candidates (`EnglishWords`), and without the
/// candidates the user removed (`RemovedCandidates`). While Latin letters alone are typed, the words of `words` whose
/// letters begin with them (all of a word's letters, or `EnglishWords.minPrefix` typed at least) go on the first page,
/// numbered with librime's candidates, unless the page (in any case) or rime-ice's English dictionary (`dictionary`:
/// librime offers those itself) has them. They go where rime-ice puts English (its `melt_eng` weighs less than pinyin; its
/// `reduce_english_filter` puts a short word pinyin reads too second): a word whose letters are all that was typed first,
/// or second when that is pinyin too ("xiaomi"); a longer one second, or after the page while what's typed may still be
/// pinyin ("zhon", and up to four letters, which rime-ice reads as initials: "bed" b-e-d). At most `maxPerPage`, the
/// shorter first. A candidate removed (`removedCandidates`) is left out of every page, librime's by its whole text, a word
/// by its letters. librime is given them, and leaves its own out itself where the schema has AllInOneIME's filter
/// (`PinyinEngine.setRemovedCandidates`): its pages laid out from what is left, each full. What it still shows of them
/// (without the filter: the user's own patch file, Windows; a text the property can't hold) is left out here, and a page
/// with nothing left is skipped (`skipEmptyPages`; back from the last). One removed here leaves the page where it was,
/// laid out anew without it (`deleteCandidate`).
///
/// While the page shown isn't librime's (words on it, candidates left out), ↑↓ (← → in a row), Space, the digits and a
/// click pick by the place shown, numbered as shown; a punctuation key puts the word highlighted in before its mark; a
/// key librime commits its highlighted candidate on (Space, a punctuation mark, rime-ice's [ ]) finds librime's highlight
/// moved onto the candidate shown highlighted first, never one left out; anything else goes to librime as it would.
/// Letters librime commits exactly as they were typed (⏎, a tap of Shift) are told (`rawCommitted`): what the session
/// learns words from. Main thread only, as librime.
public final class EnglishWordsEngine: PinyinEngine {
    public let base: PinyinEngine
    /// rime-ice's English words: those librime offers itself.
    public let dictionary: EnglishDictionary
    /// The words offered (`EnglishWords.offered`), as they are written; the first of two with the same letters counts.
    public var words: [String] {
        get { made.words }
        set {
            guard newValue != made.words else { return }
            made = Words(newValue)
        }
    }
    /// The words with their index, as made (`Words`): given whole, made ahead off the main thread (`Words.ahead`).
    public var made: Words
    /// Their letters (`EnglishWords.key`): what is learned isn't one of them (`EnglishWords.learns`).
    public var keys: Set<String> { made.keys }
    /// The candidates the user removed (`Config.removedCandidates`), by their text as shown, oldest first: on no page.
    /// One deleted here (`deleteCandidate`) goes on at once. librime is given them too (`setRemovedCandidates`).
    public var removedCandidates: [String] {
        didSet {
            guard removedCandidates != oldValue else { return }
            removed = Set(removedCandidates)
            removedKeys = RemovedCandidates.keys(removedCandidates)
            base.setRemovedCandidates(removedCandidates)
        }
    }
    /// The letters of those that are English words (`RemovedCandidates.keys`): what a word is left out by, and what is
    /// never learned again (`EnglishWords.learns`).
    public private(set) var removedKeys: Set<String>
    /// Letters librime committed exactly as they were typed, the whole composition (⏎, a tap of Shift).
    public var rawCommitted: ((String) -> Void)?
    /// The user's fuzzy pinyin (`Config.fuzzyPinyin`): what librime reads as pinyin with it is pinyin here too.
    public var fuzzyPinyin: [String] = []
    /// The most words put on a page.
    public static let maxPerPage = 3
    /// The most pages turned on past one with nothing shown (`skipEmptyPages`), and back from the last before those: the
    /// key never waits on many.
    public static let maxSkipped = 5
    /// The most pages turned on back to the one a candidate was removed on (`deleteCandidate`: librime lays the
    /// composition out anew from its first page), for the same reason.
    public static let maxReturned = 10

    /// The words by their letters (`EnglishWords.key`), sorted: those a prefix begins are side by side.
    private var index: [(key: String, word: String)] { made.index }
    /// `removedCandidates`, what librime's candidates are looked up in.
    private var removed: Set<String>
    /// A place on the page as shown: librime's candidate (its place on librime's page), or a word.
    private enum Entry: Equatable {
        case base(Int)
        case word(String)
    }
    /// The word highlighted, by its place on the page as shown; nil: librime's own highlight.
    private var cursor: Int?
    /// The input, page and preedit (without its spaces) the page was last laid out for: a change sets the highlight anew.
    private var laidOutFor: String?
    /// The way the pages were last turned: back (a page with nothing shown is skipped that way, `skipEmptyPages`).
    private var pagedBack = false
    /// The word picked, for `takeCommit`.
    private var picked: String?
    /// The letters typed before the last key (what a commit as typed equals).
    private var rawBefore: String?

    public init(base: PinyinEngine, dictionary: EnglishDictionary, words: [String] = [], removedCandidates: [String] = []) {
        self.base = base
        self.dictionary = dictionary
        made = Words(words)
        self.removedCandidates = removedCandidates
        removed = Set(removedCandidates)
        removedKeys = RemovedCandidates.keys(removedCandidates)
        base.setRemovedCandidates(removedCandidates)
    }

    /// The words offered, with what finding them takes: their index by their letters, and the letters themselves. Made
    /// where they are given (`words`), or ahead, off the main thread (`ahead`), for what they are made of.
    public struct Words: Sendable {
        public let words: [String]
        let index: [(key: String, word: String)]
        let keys: Set<String>

        public init(_ words: [String]) {
            var seen = Set<String>()
            self.words = words
            index = words.map { (EnglishWords.key($0), $0) }.filter { !$0.0.isEmpty && seen.insert($0.0).inserted }.sorted { $0.key < $1.key }
            keys = Set(index.map(\.key))
        }

        /// The words `EnglishWords.offered` gives for `config` and `jargon`, made now on the caller's thread and kept for
        /// what they are made of (`madeOf`): the first field's session takes them instead of making them (`ahead`). The
        /// shell makes them once librime is ready, off the main thread.
        public static func prepare(_ config: Config, jargon: [JargonEntry]) {
            let words = Words(EnglishWords.offered(config, jargon: jargon))
            prepared.withLock { $0 = (madeOf(config, jargon: jargon), words) }
        }

        /// The words made ahead for what `madeOf` says they are made of (`prepare`); nil: none made for it.
        public static func ahead(for madeOf: [String]) -> Words? {
            prepared.withLock { $0.flatMap { $0.madeOf == madeOf ? $0.words : nil } }
        }

        /// What the words offered are made of: the user's, then the jargon list's terms.
        public static func madeOf(_ config: Config, jargon: [JargonEntry]) -> [String] {
            config.englishWords + ["\u{0}"] + jargon.map(\.term)
        }

        private static let prepared = Locked<(madeOf: [String], words: Words)?>(initialState: nil)
    }

    public var language: Language { base.language }
    public var rawInput: String { base.rawInput }

    // MARK: The page

    /// librime's page without the candidates removed, with the words for what is typed (`raw`, librime's input) put in.
    private func layout(_ snap: EngineSnapshot, raw: String) -> [Entry] {
        let rime = removed.isEmpty ? snap.candidates.indices.map(Entry.base)
            : snap.candidates.indices.filter { !removed.contains(snap.candidates[$0].text) }.map(Entry.base)
        guard snap.isComposing, !snap.isAsciiMode, snap.pageNumber == 0, !index.isEmpty else { return rime }
        guard !raw.isEmpty, raw.allSatisfy({ $0.isASCII && $0.isLetter }),
              // Nothing of it picked yet ("你好ma": the page is for the rest), and librime's numbering, which the page's follows.
              snap.preedit.filter({ $0 != " " }) == raw,
              snap.candidates.enumerated().allSatisfy({ $0.element.label == String(($0.offset + 1) % 10) }),
              snap.candidates.count + Self.maxPerPage <= 10 else { return rime }
        let typed = raw.lowercased()
        // Most keys have no word to offer: librime's candidates are gone through only for one that has some, and the
        // words only as far as the first `maxPerPage` that go on the page (the shorter first).
        let words = matches(typed)
        guard !words.isEmpty else { return rime }
        let shown = Set(snap.candidates.map { $0.text.lowercased() })
        var found: [(key: String, word: String)] = []
        for match in words where !shown.contains(match.word.lowercased()) && !dictionary.contains(match.key)
            && !removedKeys.contains(match.key) {
            found.append(match)
            if found.count == Self.maxPerPage { break }
        }
        guard !found.isEmpty else { return rime }
        let pinyin = Pinyin.isPinyin(typed, fuzzy: fuzzyPinyin)
        let maybePinyin = pinyin || Pinyin.endsInASpellingBegun(typed, fuzzy: fuzzyPinyin)
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
    /// librime's. librime's preedit splits the letters as its highlighted candidate reads them ("bei d rock", "bed rock"):
    /// without its spaces, so that moving onto its candidates doesn't set the highlight anew (back on the word).
    private func current() -> (snap: EngineSnapshot, entries: [Entry]) {
        let snap = base.snapshot()
        let raw = base.rawInput
        let entries = layout(snap, raw: raw)
        let laidOut = laidOutKey(snap, raw: raw)
        if laidOut != laidOutFor {
            laidOutFor = laidOut
            cursor = entries.first.map(Self.isWord) == true ? 0 : nil
        }
        if let at = cursor, !(entries.indices.contains(at) && Self.isWord(entries[at])) { cursor = nil }
        return (snap, entries)
    }

    /// What `laidOutFor` tells a page by: the input, librime's page and its preedit without its spaces.
    private func laidOutKey(_ snap: EngineSnapshot, raw: String) -> String {
        "\(raw)\u{0}\(snap.pageNumber)\u{0}\(snap.preedit.filter { $0 != " " })"
    }

    private static func isWord(_ entry: Entry) -> Bool {
        if case .word = entry { return true }
        return false
    }

    /// The text `entry` shows on `snap`'s page.
    private static func text(of entry: Entry, in snap: EngineSnapshot) -> String {
        switch entry {
        case let .base(i): return snap.candidates[i].text
        case let .word(word): return word
        }
    }

    /// Whether the page shown is librime's own: no word put in, no candidate left out.
    private static func isLibrimes(_ entries: [Entry], of snap: EngineSnapshot) -> Bool {
        entries.count == snap.candidates.count && !entries.contains(where: isWord)
    }

    /// The place shown highlighted: the word's (`cursor`), else librime's candidate highlighted; one left out, the next
    /// shown after it, else the last before it (the page came from the next one). Nil: nothing shown.
    private func highlighted(_ snap: EngineSnapshot, _ entries: [Entry]) -> Int? {
        if let cursor { return cursor }
        if let at = entries.firstIndex(of: .base(snap.highlighted)) { return at }
        func place(_ entry: Entry) -> Int? { if case let .base(i) = entry { return i } else { return nil } }
        return entries.firstIndex { place($0).map { $0 > snap.highlighted } ?? false }
            ?? entries.lastIndex { place($0) != nil } ?? entries.indices.first
    }

    public func snapshot() -> EngineSnapshot {
        let (shown, entries) = current()
        var snap = shown
        guard !Self.isLibrimes(entries, of: snap) else { return snap }
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
            snap.highlighted = highlighted(shown, entries) ?? 0
        }
        return snap
    }

    // MARK: Keys

    public func processKey(_ keycode: Int32, mask: Int32) -> Bool {
        let raw = base.rawInput
        if !raw.isEmpty { rawBefore = raw }
        if let handled = onPage(keycode, mask: mask) { return handled }
        let arrow = (keycode == RimeKey.up || keycode == RimeKey.down) && mask == 0
        return changing(arrow: arrow) { base.processKey(keycode, mask: mask) }
    }

    /// A key that moves on the page or picks from it when the page shown isn't librime's; nil: librime's.
    private func onPage(_ keycode: Int32, mask: Int32) -> Bool? {
        guard mask & ~RimeKey.shiftMask == 0 else { return nil }  // releases and shortcuts are librime's
        let (snap, entries) = current()
        guard !Self.isLibrimes(entries, of: snap) else { return nil }
        guard let at = highlighted(snap, entries) else { return nothingShown(keycode, mask: mask) }
        let word: String? = cursor.flatMap { if case let .word(word) = entries[$0] { return word } else { return nil } }
        if mask == RimeKey.shiftMask {
            // ⇧Space picks as Space does; ⇧ and a punctuation key ("!", "?"): the word highlighted goes in before it.
            guard keycode == RimeKey.space || Self.isPunctuation(keycode) else { return nil }
            guard let word else { return toLibrime(highlighting: entries[at]) }
            if keycode == RimeKey.space { return pick(word) }
            return pick(word, then: keycode, mask: mask)
        }
        switch keycode {
        case RimeKey.down: return move(to: at + 1, in: entries, snap)
        case RimeKey.up: return move(to: at - 1, in: entries, snap)
        case RimeKey.space:
            guard let word else { return toLibrime(highlighting: entries[at]) }
            return pick(word)
        case 0x30...0x39:
            let place = keycode == 0x30 ? 9 : Int(keycode - 0x31)
            if entries.indices.contains(place) { return select(entries[place]) }
            // No row with that number: librime's own digit past its page (it would pick nothing there), else nothing (it
            // would pick a candidate not shown).
            return place >= snap.candidates.count ? toLibrime(highlighting: entries[at]) : true
        case 0x5B, 0x5D:
            // [ and ] pick a candidate's first or last character (rime-ice): a word has none to pick.
            guard word == nil else { return true }
            return toLibrime(highlighting: entries[at])
        default:
            guard Self.isPunctuation(keycode) else { return nil }
            guard let word else { return toLibrime(highlighting: entries[at]) }
            return pick(word, then: keycode, mask: mask)
        }
    }

    /// A key librime commits its highlighted candidate on (Space, a punctuation mark, [ ]), with `entry` (librime's
    /// candidate) shown highlighted: librime's highlight moved onto it first, then the key is librime's (nil).
    private func toLibrime(highlighting entry: Entry) -> Bool? {
        if case let .base(i) = entry { highlightBase(i) }
        return nil
    }

    /// A key on a page with nothing shown (each candidate on it removed, and on the pages `skipEmptyPages` turned past):
    /// Space puts the letters in as typed, as Return does, and a punctuation key puts them in before its mark; a digit,
    /// [ and ] pick nothing; anything else (a letter, ⌫, the page keys) is librime's.
    private func nothingShown(_ keycode: Int32, mask: Int32) -> Bool? {
        if keycode == RimeKey.space { return base.processKey(RimeKey.returnKey, mask: 0) }
        if Self.isPunctuation(keycode) {
            _ = base.processKey(RimeKey.returnKey, mask: 0)
            return base.processKey(keycode, mask: mask)
        }
        return mask == 0 && ((0x30...0x39).contains(keycode) || keycode == 0x5B || keycode == 0x5D) ? true : nil
    }

    /// Marks that go in after the word highlighted: not those librime uses while composing (' between syllables, - =
    /// turning the page).
    private static func isPunctuation(_ keycode: Int32) -> Bool {
        guard (0x21...0x7E).contains(keycode), let scalar = Unicode.Scalar(UInt32(keycode)) else { return false }
        let character = Character(scalar)
        return !character.isLetter && !character.isNumber && !"'-=[]".contains(character)
    }

    /// The highlight moved to `place`: a word, or librime's candidate (its highlight moved there); past the page's
    /// ends, librime's key (its page turns, from its own last or first candidate, whether shown or not).
    private func move(to place: Int, in entries: [Entry], _ snap: EngineSnapshot) -> Bool? {
        if place < 0 {
            // Nothing before the first page.
            guard snap.pageNumber > 0 else { return cursor == nil && entries.first == .base(snap.highlighted) ? nil : true }
            cursor = nil
            highlightBase(0)
            return nil
        }
        guard place < entries.count else {
            cursor = nil
            if !snap.candidates.isEmpty { highlightBase(snap.candidates.count - 1) }
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

    /// `change` made to librime; with candidates removed, a page it leaves with nothing shown skipped (`skipEmptyPages`;
    /// `arrow`: librime's ↑ or ↓, from a page's first or last candidate onto the page before or after).
    private func changing(arrow: Bool = false, _ change: () -> Bool) -> Bool {
        guard !removed.isEmpty else { return change() }
        let page = base.snapshot().pageNumber
        let done = change()
        skipEmptyPages(from: page, arrow: arrow)
        return done
    }

    /// librime's page, every candidate on it removed: the next page in the way the pages were turned (from `before`, the
    /// page before; on from the first), until one has something shown, `maxSkipped` at most. On to the last page with
    /// none shown yet (nothing after it): back to the nearest page before with something shown, past those just turned
    /// on and `maxSkipped` more at most. None has: the page shows no candidates (`snapshot`), and Space puts the letters
    /// in as typed (`nothingShown`). After ↑ or ↓ (`arrow`), the highlight on the page reached as the arrow puts it:
    /// back, on its last row shown; on, on its first.
    private func skipEmptyPages(from before: Int, arrow: Bool = false) {
        var snap = base.snapshot()
        if snap.pageNumber != before { pagedBack = snap.pageNumber < before }
        var skipped = false
        // The lowest page looked at (one after another): from it to the one reached, none shows anything but that one.
        var lowest = snap.pageNumber
        func empty() -> Bool { snap.isComposing && !snap.candidates.isEmpty && layout(snap, raw: base.rawInput).isEmpty }
        // librime's page turned back or on; false: it didn't turn.
        func turn(back: Bool) -> Bool {
            _ = base.processKey(back ? RimeKey.pageUp : RimeKey.pageDown, mask: 0)
            let next = base.snapshot()
            guard next.pageNumber != snap.pageNumber else { return false }
            snap = next
            lowest = min(lowest, snap.pageNumber)
            skipped = true
            return true
        }
        for _ in 0..<Self.maxSkipped {
            guard empty() else { break }
            if snap.pageNumber == 0 { pagedBack = false }  // nothing before it: on from there
            guard pagedBack || !snap.isLastPage else { break }
            guard turn(back: pagedBack) else { break }
        }
        // Nothing after the last page: back from it, over those looked at, to the nearest before them that shows some.
        if empty(), !pagedBack, snap.isLastPage, lowest > 0 {
            pagedBack = true
            for _ in 0..<(snap.pageNumber - lowest + Self.maxSkipped) {
                guard turn(back: true), empty(), snap.pageNumber > 0 else { break }
            }
        }
        // Page Up and Down, - and = leave the highlight where librime's page keys put it.
        guard arrow, skipped, !snap.candidates.isEmpty else { return }
        highlightBase(pagedBack ? snap.candidates.count - 1 : 0)
    }

    /// A place on the page picked: a word goes in, librime's candidate is librime's to pick.
    private func select(_ entry: Entry) -> Bool {
        switch entry {
        case let .word(word): return pick(word)
        case let .base(i): return changing { base.selectCandidate(onPage: i) }
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
        let (snap, entries) = current()
        guard !Self.isLibrimes(entries, of: snap) else { return changing { base.selectCandidate(onPage: index) } }
        guard entries.indices.contains(index) else { return false }
        return select(entries[index])
    }

    /// The candidate shown at `index` removed (a right-click, ⌃⌦): on `removedCandidates`, never shown again, and
    /// librime's deleted there too (`PinyinEngine.deleteCandidate`: what it learned of it forgotten; an emoji isn't, its
    /// word stays as it was). The page stays the one the user is on (librime lays the composition out anew from its
    /// first page: `returnToPage`), laid out anew without it, the highlight where it was; on the one removed, on its row
    /// (what moved up into its place: the one shown after it, from the page after too where librime refills the page),
    /// else the one before. A page left with nothing shown is skipped, on forward, else (the last) back: the highlight
    /// on the first row shown on a page after, the last on one before. Whether one was removed.
    public func deleteCandidate(onPage index: Int) -> Bool {
        let (snap, entries) = current()
        guard entries.indices.contains(index) else { return false }
        let shown = entries.map { Self.text(of: $0, in: snap) }
        let at = highlighted(snap, entries) ?? index
        // Deleted by librime on the page it is on, then on the list (librime's too): its filter lays the composition out
        // anew without it at once, each page full (`setRemovedCandidates`), whatever librime's delete did.
        if case let .base(i) = entries[index] { _ = base.deleteCandidate(onPage: i) }
        removedCandidates = RemovedCandidates.adding(shown[index], to: removedCandidates)
        let page = returnToPage(snap.pageNumber)
        pagedBack = false  // nothing shown on it now: on forward, else back from the last
        skipEmptyPages(from: page)
        let near = Array(shown[(index + 1)...]) + shown[..<index].reversed()
        let now = base.snapshot().pageNumber
        highlight(at == index ? near : [shown[at]] + near, row: at == index && now == snap.pageNumber ? index : nil,
                  orLast: now < snap.pageNumber)
        return true
    }

    /// librime on `page` again, the page a candidate was removed on, after its `delete_candidate` laid the composition
    /// out anew from its first: its pages turned on to it, as many as `page` and `maxReturned` at most. The page it is on.
    private func returnToPage(_ page: Int) -> Int {
        var snap = base.snapshot()
        for _ in 0..<min(page, Self.maxReturned) {
            guard snap.isComposing, snap.pageNumber < page, !snap.isLastPage else { break }
            _ = base.processKey(RimeKey.pageDown, mask: 0)
            let next = base.snapshot()
            guard next.pageNumber != snap.pageNumber else { break }
            snap = next
        }
        return snap.pageNumber
    }

    /// The page laid out anew, the highlight on `row` where the page has it (the removed one's, on the page it was on),
    /// else on the first of `texts` it shows (the one highlighted before a candidate was removed, else the one after it,
    /// else the one before); none: on its last row shown with `last` (a page before the one it was removed on: the one
    /// before it), else as on a page laid out anew (on a word that comes first, else librime's).
    private func highlight(_ texts: [String], row: Int? = nil, orLast last: Bool) {
        let snap = base.snapshot(), raw = base.rawInput
        let entries = layout(snap, raw: raw)
        laidOutFor = laidOutKey(snap, raw: raw)
        cursor = entries.first.map(Self.isWord) == true ? 0 : nil
        let shown = entries.map { Self.text(of: $0, in: snap) }
        guard let place = row.flatMap({ shown.indices.contains($0) ? $0 : nil })
            ?? texts.lazy.compactMap({ shown.firstIndex(of: $0) }).first ?? (last ? shown.indices.last : nil)
        else { return }
        switch entries[place] {
        case .word:
            cursor = place
        case let .base(i):
            cursor = nil
            // librime's highlight moved only when it isn't shown there already (on the one removed, say: the next shown).
            guard highlighted(snap, entries) != place else { return }
            highlightBase(i)
            laidOutFor = laidOutKey(base.snapshot(), raw: raw)  // librime's preedit follows its highlight
        }
    }

    /// The composition as converted text: the word highlighted, else librime's (its highlight moved onto the candidate
    /// shown highlighted first); with nothing shown, the letters as typed.
    public func commitComposition() -> String? {
        let (snap, entries) = current()
        if let cursor, case let .word(word) = entries[cursor] {
            _ = pick(word)
            return takeCommit()
        }
        rawBefore = nil
        if !Self.isLibrimes(entries, of: snap) {
            guard let at = highlighted(snap, entries) else {
                _ = base.processKey(RimeKey.returnKey, mask: 0)
                return takeCommit()
            }
            _ = toLibrime(highlighting: entries[at])
        }
        return base.commitComposition()
    }

    public func clearComposition() {
        cursor = nil
        rawBefore = nil
        base.clearComposition()
    }

    public func setAsciiMode(_ on: Bool) { base.setAsciiMode(on) }
}
