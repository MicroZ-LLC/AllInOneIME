import Foundation

/// The candidates the user removed (「删掉的候选词」): a right-click on a candidate row (a Control-click), or ⌃⌦ on the
/// highlighted one, while pinyin is typed (`Composer.deleteCandidate(index:)`). One removed never comes up again as a
/// candidate of its own, whatever is typed, until the user restores it in Settings (`EnglishWordsEngine`: librime's by
/// its whole text, so a sentence or a longer phrase with it in it still comes; an English word put among them by its
/// letters, `EnglishWords.key`, so "Bedrock" removes "bedrock" too); librime forgets what it learned of it as well (its
/// `delete_candidate`), but one a filter made from a word and put beside it (an emoji: 👏 after 鼓掌) is only left out,
/// the word as it was (`RimeSession.deleteCandidate`). Removing one only leaves it out: an English word on the list is
/// never learned again, but the user's own English words stay as they are, so one restored comes back as it was.
///
/// Kept by their text as they were shown (`Config.removedCandidates`), oldest first, at most `maxCount`: the engine's
/// list changes at once, the file a moment later, off the key's thread (`EnglishWords.Writer`, only its key of them
/// patched). Synced through iCloud with the words learned (`ICloudSync.removedCandidatesKey`).
public enum RemovedCandidates {
    /// The most kept: beyond it, the oldest go first.
    public static let maxCount = 5000

    /// librime's context property level one gives them as (`PinyinEngine.setRemovedCandidates`), one text per line;
    /// not starting with "_", which librime clears as transient.
    public static let property = "allinoneime_removed"
    /// AllInOneIME's Lua filter that reads it (Resources/rime/lua, in the app beside rime-ice's scripts), last of the
    /// schema's filters where the patch puts it (`PersonalDictionaryStore`): librime leaves them out itself, and lays its
    /// pages out from what is left, each full.
    public static let luaFilter = "allinoneime_removed"
    /// The context properties librime's delete of a candidate is asked about by (`RimeSession.deleteCandidate`): its
    /// place on the page put on `askedProperty`, the filter answers on `derivedProperty` at once, "1" for one a filter
    /// made from a word and put beside it (rime-ice's emoji: 👏 after 鼓掌), whose delete would forget that word, "0"
    /// for any other; nothing where the schema hasn't the filter.
    public static let askedProperty = "allinoneime_delete_asked"
    public static let derivedProperty = "allinoneime_derived"

    /// Whether a candidate shown as `text` may be a word librime's delete is asked for, where the filter can't tell
    /// (`derivedProperty`: the user's own patch file, Windows; the text alone is all librime gives then). One with no
    /// letter or digit of any script in it (an emoji, a symbol: 👏, ⺁) is no word of a pinyin dictionary but one rime-ice's
    /// emoji filter made from the word before it, and its delete would forget that word. The narrowest rule the text
    /// allows: what that filter makes of letters (January after 一月, 亻 after 单人旁) is taken for a word, as before; so
    /// is a character this Mac doesn't know yet (a new CJK extension's).
    public static func mayBeAWord(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .decimalNumber, .letterNumber, .otherNumber, .unassigned, .privateUse:
                return true
            default:
                return false
            }
        }
    }

    /// `list` with `text` removed too: at the end, once, within `maxCount`.
    public static func adding(_ text: String, to list: [String]) -> [String] {
        guard !text.isEmpty, !list.contains(text) else { return list }
        return Array((list + [text]).suffix(maxCount))
    }

    /// Settings' ✕: `list` without `text`, which comes up among the candidates again.
    public static func restoring(_ text: String, from list: [String]) -> [String] {
        list.filter { $0 != text }
    }

    /// Settings → English Words' Add (`EnglishWords.add`): `list` without the English words that have the letters of one
    /// of `words` (`keys`), which come up among the candidates again as the user asked.
    public static func restoring(words: [String], from list: [String]) -> [String] {
        let added = Set(words.map(EnglishWords.key))
        return list.filter { keys([$0]).isDisjoint(with: added) }
    }

    /// The letters (`EnglishWords.key`) of those of `list` that are English words (`EnglishWords.word`): what an
    /// English word put among the candidates is matched by, and what is never learned again.
    public static func keys(_ list: [String]) -> Set<String> {
        Set(list.compactMap { text in
            guard text.first?.isASCII == true, EnglishWords.word(text) != nil else { return nil }
            return EnglishWords.key(text)
        })
    }

    /// `config` with `text` removed: on the list (`adding`). Nothing else changes, the user's English words neither.
    public static func remove(_ text: String, from config: inout Config) {
        config.removedCandidates = adding(text, to: config.removedCandidates)
    }

    /// `text` removed in the config file at `url` (`remove(_:from:)`), in one write of the file as it is now: only its
    /// key of them changes (`removedCandidates`); a missing file is written with this Mac's new user's settings. Whether
    /// anything changed. What `EnglishWords.Writer` does off the key's thread, in order with the words learned.
    @discardableResult
    public static func remove(_ text: String, at url: URL) throws -> Bool {
        try EnglishWords.write([.remove(text)], at: url)
    }

    /// What a field's session gives level one of them (`Composer.removedCandidates`): the settings' list, with those
    /// removed that the file doesn't have yet (written a moment later, `EnglishWords.Writer`; never while the file doesn't
    /// parse), so that neither a new engine (librime deployed again) nor a list read before they were written brings one
    /// back: those of any field the writer hasn't written (`EnglishWords.Writer.unwrittenRemovals`), else, where the
    /// shell can't tell, those removed in the field until the list has them. One written, or that the list has, is the
    /// list's from then on: restored there (Settings' ✕, the config without it), whether before the field reads the
    /// settings again or after, it comes back.
    public struct Given: Equatable, Sendable {
        /// The settings' list last taken (`taking`).
        private var listed: [String]?
        /// Those removed the settings' list didn't have when last taken, oldest first: in the field, and in any field
        /// the shell told weren't written yet.
        private var pending: [String] = []

        public init() {}

        /// `text` removed in the field (`Composer.Effect.candidateRemoved`): level one leaves it out already.
        public mutating func removed(_ text: String) {
            pending = adding(text, to: pending)
        }

        /// The settings' list as read now (`Config.removedCandidates`) taken, with `unwritten`, those removed in any field
        /// that the shell told weren't written yet just before the list was read (nil: it can't tell): what level one is
        /// to be given, nil when the list is the one taken last and those it adds are the same. Those removed here that
        /// the list has, or that the shell no longer tells unwritten, are the list's from then on.
        public mutating func taking(_ listed: [String], unwritten: [String]? = nil) -> [String]? {
            let caughtUp = Set(listed), told = unwritten.map(Set.init)
            var adds = pending.filter { !caughtUp.contains($0) && told?.contains($0) != false }
            for text in unwritten ?? [] where !caughtUp.contains(text) { adds = adding(text, to: adds) }
            guard listed != self.listed || adds != pending else { return nil }
            (self.listed, pending) = (listed, adds)
            return listed + adds
        }
    }
}
