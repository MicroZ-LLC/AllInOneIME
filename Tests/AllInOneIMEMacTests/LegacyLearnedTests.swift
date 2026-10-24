import AllInOneIMECore
import AllInOneIMEMac
import Foundation
import Testing

/// What 0.6.6 and earlier learned outside the one local store (`LegacyLearned`): the apps where typos couldn't be fixed
/// (the defaults) and the suggestion rows picked (suggestion-picks.json), moved into `LearnedStore` at launch, removed
/// from where they were only once the store's file has them; nothing lost, nothing else touched.
struct LegacyLearnedTests {
    /// A folder, defaults and a store of the test's own: the user's are never read.
    final class Place {
        let folder: URL
        let suite = "com.aipinyin.tests.learned.\(UUID().uuidString)"
        let defaults: UserDefaults

        init() throws {
            folder = FileManager.default.temporaryDirectory.appendingPathComponent("learned-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defaults = try #require(UserDefaults(suiteName: suite))
        }

        deinit {
            UserDefaults.standard.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }

        var picksURL: URL { folder.appendingPathComponent("suggestion-picks.json") }
        var storeURL: URL { folder.appendingPathComponent("learned.json") }

        func store(at url: URL? = nil) -> LearnedStore {
            LearnedStore(file: url ?? storeURL, autocomplete: AutocompleteStore(), temperature: TemperatureSupport(file: nil))
        }

        func writePicks(_ picks: [SuggestionPick]) throws {
            try JSONEncoder().encode(picks).write(to: picksURL)
        }
    }

    static func pick(_ n: Int) -> SuggestionPick { SuggestionPick(plugin: "github", source: "issues", match: "#\(n)") }

    @Test func movesTheOldTyposAndPicksIntoTheStoreAndRemovesThem() throws {
        let place = try Place()
        place.defaults.set(["com.example.ignores-ranges", "com.example.other"], forKey: LegacyLearned.typosKey)
        try place.writePicks([Self.pick(1), Self.pick(2)])
        let store = place.store()
        store.recordPick(Self.pick(3))  // picked with this version before the move: after the old ones

        #expect(LegacyLearned.move(into: store, defaults: place.defaults, picksURL: place.picksURL) == .moved(typosOff: 2, picks: 2))
        #expect(store.typosOff(in: "com.example.ignores-ranges") && store.typosOff(in: "COM.EXAMPLE.OTHER"))
        #expect(store.picks == [Self.pick(1), Self.pick(2), Self.pick(3)])
        #expect(place.defaults.object(forKey: LegacyLearned.typosKey) == nil)
        #expect(!FileManager.default.fileExists(atPath: place.picksURL.path))

        // In the store's file: a new launch has them.
        let again = place.store()
        #expect(again.typosOffApps == ["com.example.ignores-ranges", "com.example.other"])
        #expect(again.picks == [Self.pick(1), Self.pick(2), Self.pick(3)])
        #expect(LegacyLearned.move(into: again, defaults: place.defaults, picksURL: place.picksURL) == .nothingToMove)
    }

    /// An older version run again meanwhile writes them again: moved in at the next launch, added to what is there.
    @Test func whatAnOlderVersionAddedLaterIsMovedInToo() throws {
        let place = try Place()
        let store = place.store()
        store.turnTyposOff(in: "com.example.first")
        place.defaults.set(["com.example.first", "com.example.later"], forKey: LegacyLearned.typosKey)
        #expect(LegacyLearned.move(into: store, defaults: place.defaults, picksURL: place.picksURL) == .moved(typosOff: 2, picks: 0))
        #expect(place.store().typosOffApps == ["com.example.first", "com.example.later"])
    }

    /// The store's file can't be written: what was kept the old way stays where it is.
    @Test func nothingIsRemovedWhenTheStoreCantBeWritten() throws {
        let place = try Place()
        let blocker = place.folder.appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: blocker)
        place.defaults.set(["com.example.app"], forKey: LegacyLearned.typosKey)
        try place.writePicks([Self.pick(1)])
        let store = place.store(at: blocker.appendingPathComponent("learned.json"))
        #expect(LegacyLearned.move(into: store, defaults: place.defaults, picksURL: place.picksURL) == .failed)
        #expect(place.defaults.stringArray(forKey: LegacyLearned.typosKey) == ["com.example.app"])
        #expect(FileManager.default.fileExists(atPath: place.picksURL.path))
    }

    @Test func nothingKeptTheOldWayIsNothingToMove() throws {
        let place = try Place()
        let store = place.store()
        #expect(LegacyLearned.move(into: store, defaults: place.defaults, picksURL: place.picksURL) == .nothingToMove)
        #expect(!FileManager.default.fileExists(atPath: place.storeURL.path), "nothing written")
    }
}
