import Foundation
import Testing
@testable import AllInOneIMECore

/// 0.7.6 regress finding 1 (aio-notes/regress076.md): a `FileRead` started at an older file date must not replace what
/// the store has read or written since. Offline: a config file of its own in a temporary folder.
@Suite(.serialized)
struct SettingsFileReadOrderTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("fileread-order-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    /// Writes `config` to `url` with the file dated `age` seconds ago (distinct, past dates).
    private func put(_ config: Config, at url: URL, age: TimeInterval) throws {
        try config.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
    }

    /// Scenario A: two reads of two writes arrive out of order; the older read (D2) arrives after the newer (D3).
    @Test func anOlderReadArrivingAfterANewerOneIsDropped() throws {
        let url = tempURL()
        var c1 = Config.default
        c1.voiceInput = false
        try put(c1, at: url, age: 300)
        let store = SettingsStore(configURL: url, persists: true)
        let d1 = store.fileDate

        var c2 = c1
        c2.voiceInput = true
        try put(c2, at: url, age: 200)
        let older = try #require(SettingsStore.FileRead(url, since: d1))

        var c3 = c1
        c3.voiceInput = false
        c3.rememberQuestions = !c1.rememberQuestions
        try put(c3, at: url, age: 100)
        let newer = try #require(SettingsStore.FileRead(url, since: d1))

        #expect(store.reloadIfChanged(newer))
        #expect(store.config == c3)
        let dateAfterNewer = store.fileDate

        let took = store.reloadIfChanged(older)
        #expect(!took, "the read of the older file replaced the newer one")
        #expect(store.config == c3, "the older read's config is shown")
        #expect(store.fileDate == dateAfterNewer)
    }

    /// Scenario B: a read starts at D1, the user saves a change (the file is now D2), then the read arrives.
    @Test func aReadStartedBeforeASaveDoesNotUndoTheSave() throws {
        let url = tempURL()
        var c1 = Config.default
        c1.voiceInput = false
        c1.rememberQuestions = false
        try put(c1, at: url, age: 300)
        let store = SettingsStore(configURL: url, persists: true)

        // Something else changed the file; its read starts (off the store's thread) but has not arrived.
        var external = c1
        external.voiceInput = true
        try put(external, at: url, age: 200)
        let read = try #require(SettingsStore.FileRead(url, since: store.fileDate))

        // Meanwhile the user flips a switch and the store saves it.
        store.config.rememberQuestions = true
        store.save()
        #expect(store.canSave)
        let saved = store.config
        #expect(saved.rememberQuestions)
        let dateAfterSave = store.fileDate

        let took = store.reloadIfChanged(read)
        #expect(!took, "the stale read was taken after a save")
        #expect(store.config == saved, "the switch just saved is shown as it was before")
        #expect(store.config.rememberQuestions)
        #expect(store.fileDate == dateAfterSave)
    }
}
