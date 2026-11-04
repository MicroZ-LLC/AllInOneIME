import Foundation

/// The candidates the user removed (「删掉的候选词」): a right-click on a candidate row (a Control-click), or ⌃⌦ on the
/// highlighted one, while pinyin is typed (`Composer.deleteCandidate(index:)`). One removed never comes up again as a
/// candidate of its own, whatever is typed, until the user restores it in Settings (`EnglishWordsEngine`: librime's by
/// its whole text, so a sentence or a longer phrase with it in it still comes; an English word put among them by its
/// letters, `EnglishWords.key`, so "Bedrock" removes "bedrock" too); librime forgets what it learned of it as well (its
/// `delete_candidate`). Removing one only leaves it out: an English word on the list is never learned again, but the
/// user's own English words stay as they are, so one restored comes back as it was.
///
/// Kept by their text as they were shown (`Config.removedCandidates`), oldest first, at most `maxCount`: the engine's
/// list changes at once, the file a moment later, off the key's thread (`EnglishWords.Writer`, only its key of them
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
    /// removed in the field that it doesn't have yet (written a moment later, `EnglishWords.Writer`; never while the file
    /// doesn't parse), so that neither a new engine (librime deployed again) nor a list read before they were written
    /// brings one back. One the list has is the list's from then on: restored there (Settings' ✕, the config without
    /// it), it comes back.
    public struct Given: Equatable, Sendable {
        /// The settings' list last taken (`taking`).
        private var listed: [String]?
        /// Those removed in the field the settings' list didn't have when last taken, oldest first.
        private var removedHere: [String] = []

        public init() {}

        /// `text` removed in the field (`Composer.Effect.candidateRemoved`): level one leaves it out already.
        public mutating func removed(_ text: String) {
            removedHere = adding(text, to: removedHere)
        }

        /// The settings' list as read now (`Config.removedCandidates`) taken: what level one is to be given, nil when the
        /// list is the one taken last. Those removed here that it has are its own from then on.
        public mutating func taking(_ listed: [String]) -> [String]? {
            guard listed != self.listed else { return nil }
            self.listed = listed
            let caughtUp = Set(listed)
            removedHere.removeAll { caughtUp.contains($0) }
            return listed + removedHere
        }
    }
}
