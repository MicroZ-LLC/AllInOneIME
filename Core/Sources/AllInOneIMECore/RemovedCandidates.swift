import Foundation

/// The candidates the user removed (「删掉的候选词」): a right-click on a candidate row (a Control-click), or ⌃⌦ on the
/// highlighted one, while pinyin is typed (`Composer.deleteCandidate(index:)`). One removed never comes up again as a
/// candidate of its own, whatever is typed, until the user restores it in Settings (`EnglishWordsEngine`: librime's by
/// its whole text, so a sentence or a longer phrase with it in it still comes; an English word put among them by its
/// letters, `EnglishWords.key`, so "Bedrock" removes "bedrock" too); librime forgets what it learned of it as well (its
/// `delete_candidate`). One of the user's English words removed is taken out of them, and never learned again.
///
/// Kept by their text as they were shown (`Config.removedCandidates`), oldest first, at most `maxCount`: the engine's
/// list changes at once, the file a moment later, off the key's thread (`EnglishWords.Writer`, only its keys of them
/// patched). Synced through iCloud with the words learned (`ICloudSync.removedCandidatesKey`).
public enum RemovedCandidates {
    /// The most kept: beyond it, the oldest go first.
    public static let maxCount = 5000

    /// `list` with `text` removed too: at the end, once, within `maxCount`.
    public static func adding(_ text: String, to list: [String]) -> [String] {
        guard !text.isEmpty, !list.contains(text) else { return list }
        return Array((list + [text]).suffix(maxCount))
    }

    /// Settings' ✕: `list` without `text`, which comes up among the candidates again.
    public static func restoring(_ text: String, from list: [String]) -> [String] {
        list.filter { $0 != text }
    }

    /// The letters (`EnglishWords.key`) of those of `list` that are English words (`EnglishWords.word`): what an
    /// English word put among the candidates is matched by, and what is never learned again.
    public static func keys(_ list: [String]) -> Set<String> {
        Set(list.compactMap { text in
            guard text.first?.isASCII == true, EnglishWords.word(text) != nil else { return nil }
            return EnglishWords.key(text)
        })
    }

    /// `config` with `text` removed: on the list (`adding`), and gone from the user's English words, added or learned
    /// (`EnglishWords.remove`), when it is an English word.
    public static func remove(_ text: String, from config: inout Config) {
        config.removedCandidates = adding(text, to: config.removedCandidates)
        if EnglishWords.word(text) != nil { EnglishWords.remove(text, from: &config) }
    }

    /// `text` removed in the config file at `url` (`remove(_:from:)`), in one write of the file as it is now: only its
    /// keys of them change (`removedCandidates`, and the English words); a missing file is written with this Mac's new
    /// user's settings. Whether anything changed. What `EnglishWords.Writer` does off the key's thread, in order with
    /// the words learned.
    @discardableResult
    public static func remove(_ text: String, at url: URL) throws -> Bool {
        try EnglishWords.write([.remove(text)], at: url)
    }
}
