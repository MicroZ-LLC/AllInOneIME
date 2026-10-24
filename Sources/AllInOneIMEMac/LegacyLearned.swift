import AllInOneIMECore
import Foundation

/// What 0.6.6 and earlier learned on this Mac outside the one local store of what is learned (`LearnedStore`, Settings
/// v2 §3.2): the apps where typos couldn't be fixed (UserDefaults' `typeOutNoTyposApps`) and the suggestion rows picked
/// (suggestion-picks.json in the app's data folder). Moved into the store at launch: added to what it has, and removed
/// from where it was only once the store's file has it. An older version run meanwhile writes them again: they are moved
/// in at the next launch, nothing lost. The config file, and what syncs, are never touched.
public enum LegacyLearned {
    /// Where the apps where typos couldn't be fixed were kept (the input method's defaults).
    public static let typosKey = "typeOutNoTyposApps"
    /// Where the suggestion rows picked were kept.
    public static var picksURL: URL { CorePaths.dataDir.appendingPathComponent("suggestion-picks.json") }

    public enum Outcome: Equatable, Sendable {
        /// Nothing was kept the old way.
        case nothingToMove
        /// In the store now, and gone from where it was: how many apps without typos, how many rows picked.
        case moved(typosOff: Int, picks: Int)
        /// The store's file couldn't be written: left where it was, for the next launch.
        case failed
    }

    /// Moves what was kept the old way (in `defaults` and at `picksURL`) into `store`.
    @discardableResult
    public static func move(into store: LearnedStore, defaults: UserDefaults = .standard, picksURL: URL = picksURL) -> Outcome {
        let typos = defaults.stringArray(forKey: typosKey) ?? []
        let hasPicks = FileManager.default.fileExists(atPath: picksURL.path)
        guard !typos.isEmpty || hasPicks || defaults.object(forKey: typosKey) != nil else { return .nothingToMove }
        // A file that can't be read held nothing to keep (it was a cache of choices, never text typed).
        let picks = (try? Data(contentsOf: picksURL)).flatMap { try? JSONDecoder().decode([SuggestionPick].self, from: $0) } ?? []
        guard store.moveIn(typosOff: typos, picks: picks) else { return .failed }
        defaults.removeObject(forKey: typosKey)
        if hasPicks { try? FileManager.default.removeItem(at: picksURL) }
        return .moved(typosOff: typos.count, picks: picks.count)
    }
}
