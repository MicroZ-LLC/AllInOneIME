import Foundation
import Testing
@testable import AllInOneIMECore

// Regression acceptance tests for sync through iCloud, round 2: the second and third independent reviews of
// 0.6.5/icloud-fixes (aio-notes/icloud-r2/review.md, probes RP1-RP23b; review3.md, probes PB1, PB1j, PB1b, PB2),
// written by an independent reviewer; the implementer may not edit them. Every test says what the user sees: no Mac
// loses a real edit, and every Mac ends with the newest real change.
// They use the rig of ICloudSyncAcceptanceTests (`ICAWorld`, `ICAMac`) and of ICloudSyncRegressionAcceptanceTests
// (`ICAR`, `sync(at:whileSettingsSaves:)`).
//
// Left out on purpose, as known limits (not covered here):
// - RP3: a 0.6.4 Mac deleting on top of a 0.6.5 Mac's provisional join merge. 0.6.4 doesn't know `base`, so it falls
//   back to the old behaviour as documented: the first delete is undone, the second sticks.
// - RP11: a crash during a join after config.json and settings.json were written but before the Mac's record
//   (state.json) was; the Mac joins again under a new id and another Mac's delete meanwhile comes back. Tiny window.
// - RP12, RP12b: a join made offline settles on the Mac's own copy of the folder; when it comes online the two
//   settings.json files collide and one Mac's commands are lost.
// - RP21: two Macs join at once; the other joiner wakes and merges with the whole merged list again, so an existing
//   command a third Mac deleted meanwhile comes back.
// - PT5: A is the first Mac to turn sync on; while A sleeps, B joins with its own commands (a real merge) and then
//   deletes one of A's; A wakes and merges again (B's merge began a new base A doesn't know), so the delete comes back
//   once on both Macs.
// - PT2: the same with three Macs: B joins with its own (a merge), C joins and deletes one of A's before A and B
//   wake; A slept through B's merge, so the delete comes back once.

// MARK: - The rig's additions

extension ICAMac {
    /// One sync run at `seconds` by a 0.6.4 Mac: it neither reads nor writes `base` (taken out of its record before and
    /// after the run, and out of the entries it uploaded).
    @discardableResult
    func syncAs064(at seconds: TimeInterval) -> ICloudSyncEngine.Report {
        ICAR2.stripBase(stateURL, keys: nil, nested: "entries")
        let report = sync(at: seconds)
        ICAR2.stripBase(stateURL, keys: nil, nested: "entries")
        ICAR2.stripBase(folder.url.appendingPathComponent("settings.json"), keys: Set(report.uploaded), nested: nil)
        return report
    }
}

extension ICAMac {
    /// "Remove from iCloud…" on this Mac at `seconds`, as Settings and ICloudSyncController do it: sync turned off first
    /// (one run sees that), then the shared folder removed and this Mac's record forgotten. `newID`: the record is lost
    /// outright instead (state.json gone, so a new Mac id), the control for a Mac that joins again as a new Mac.
    func removeFromICloud(at seconds: TimeInterval, newID: Bool = false) {
        edit(at: seconds) { $0.iCloudSync.enabled = false }
        sync(at: seconds)
        try? FileManager.default.removeItem(at: folder.url)
        if newID { try? FileManager.default.removeItem(at: stateURL) } else { engine.forget() }
    }
}

enum ICAR2 {
    /// `url`'s entries (those under `nested`, or the top level) without `base`, for `keys` (nil: all of them).
    static func stripBase(_ url: URL, keys: Set<String>?, nested: String?) {
        guard let data = try? Data(contentsOf: url),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        func clean(_ entries: inout [String: Any]) {
            for (key, value) in entries where keys?.contains(key) ?? true {
                if var entry = value as? [String: Any] { entry["base"] = nil; entries[key] = entry }
            }
        }
        if let nested {
            var entries = object[nested] as? [String: Any] ?? [:]
            clean(&entries)
            object[nested] = entries
        } else {
            clean(&object)
        }
        try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }

    static func describe(_ profile: AppProfile?) -> String { profile.map { String(describing: $0) } ?? "none" }
}

// MARK: - The tests

@Suite("ICloudSyncRegression2Acceptance", .serialized)
struct ICloudSyncRegression2AcceptanceTests {

    // MARK: A delete on top of another Mac's provisional join merge, more than one step on (RP1, RP2, RP2b, RP3b)

    @Test("merge (RP1): two quick edits on B on top of A's join merge, before A wakes: alpha stays deleted, delta kept")
    func twoEditsOnTopOfJoinMergeStick() throws {
        let world = ICAWorld()
        let b = world.mac("B") { $0.customCommands = [ICA.command("beta")] }
        b.sync(at: 10)
        let a = world.mac("A") { $0.customCommands = [ICA.command("alpha")] }
        a.sync(at: 20)  // A joins: [alpha, beta] goes up; A sleeps before its next run.
        b.sync(at: 30)
        b.edit(at: 40) { $0.customCommands.removeAll { $0.name == "alpha" } }
        b.sync(at: 40)
        b.edit(at: 45) { $0.customCommands.append(ICA.command("delta")) }
        b.sync(at: 45)
        a.sync(at: 50); b.sync(at: 60); a.sync(at: 70); b.sync(at: 80)
        for mac in [a, b] {
            #expect(ICAR.names(mac) == ["beta", "delta"], "Mac \(mac.name) has \(ICAR.names(mac)): B's delete of alpha was undone")
        }
    }

    @Test("merge (RP2): B deletes on top of A's join merge, C then edits on top of that, before A wakes: the delete sticks everywhere")
    func deleteRelayedThroughThirdMacSticks() throws {
        let world = ICAWorld()
        let b = world.mac("B") { $0.customCommands = [ICA.command("beta")] }
        b.sync(at: 10)
        let c = world.mac("C") { $0.customCommands = [ICA.command("beta")] }
        c.sync(at: 12)
        let a = world.mac("A") { $0.customCommands = [ICA.command("alpha")] }
        a.sync(at: 20)
        b.sync(at: 30)
        b.edit(at: 40) { $0.customCommands.removeAll { $0.name == "alpha" } }
        b.sync(at: 40)
        c.sync(at: 42)
        c.edit(at: 44) { $0.customCommands.append(ICA.command("delta")) }
        c.sync(at: 44)
        a.sync(at: 50); b.sync(at: 60); c.sync(at: 62); a.sync(at: 70); b.sync(at: 80); c.sync(at: 82)
        for mac in [a, b, c] {
            #expect(ICAR.names(mac) == ["beta", "delta"], "Mac \(mac.name) has \(ICAR.names(mac)): B's delete or C's add was undone")
        }
    }

    @Test("merge (RP2b): B deletes on top of A's join merge, C only syncs, before A wakes: the delete sticks everywhere")
    func deleteSyncedByThirdMacSticks() throws {
        let world = ICAWorld()
        let b = world.mac("B") { $0.customCommands = [ICA.command("beta")] }
        b.sync(at: 10)
        let c = world.mac("C") { $0.customCommands = [ICA.command("beta")] }
        c.sync(at: 12)
        let a = world.mac("A") { $0.customCommands = [ICA.command("alpha")] }
        a.sync(at: 20)
        b.sync(at: 30); c.sync(at: 31)
        b.edit(at: 40) { $0.customCommands.removeAll { $0.name == "alpha" } }
        b.sync(at: 40); c.sync(at: 42)
        a.sync(at: 50); b.sync(at: 60); c.sync(at: 62); a.sync(at: 70)
        for mac in [a, b, c] {
            #expect(ICAR.names(mac) == ["beta"], "Mac \(mac.name) has \(ICAR.names(mac)): B's delete of alpha was undone")
        }
    }

    @Test("merge (RP3b): a 0.6.4 Mac writing another setting between B's delete and A's wake doesn't undo the delete")
    func deleteSurvivesOldMacWritingAnotherKey() throws {
        let world = ICAWorld()
        let b = world.mac("B") { $0.customCommands = [ICA.command("beta")] }
        b.sync(at: 10)
        let c = world.mac("C") { $0.customCommands = [ICA.command("beta")] }  // C runs 0.6.4
        c.syncAs064(at: 12)
        let a = world.mac("A") { $0.customCommands = [ICA.command("alpha")] }
        a.sync(at: 20)
        b.sync(at: 30)
        b.edit(at: 40) { $0.customCommands.removeAll { $0.name == "alpha" } }
        b.sync(at: 40)
        c.syncAs064(at: 42)
        c.edit(at: 44) { $0.maxTokens = 3000 }
        c.syncAs064(at: 44)
        a.sync(at: 50); b.sync(at: 60); c.syncAs064(at: 62); a.sync(at: 70)
        for mac in [a, b, c] {
            #expect(ICAR.names(mac) == ["beta"], "Mac \(mac.name) has \(ICAR.names(mac)): B's delete of alpha was undone")
        }
        #expect(a.config.maxTokens == 3000, "C's maxTokens edit didn't reach A (\(a.config.maxTokens))")
    }

    // MARK: A join during which Settings saves something (RP4, RP5, RP5b)

    @Test("join (RP4): Settings saving an app iCloud already has during B's join keeps that save, and iCloud's other app")
    func joinWithSettingsSavingKnownAppKeepsTheSave() throws {
        let world = ICAWorld()
        let a = world.mac("A") {
            $0.appProfiles["com.apple.mail"] = AppProfile(typeOut: true)
            $0.appProfiles["com.apple.Safari"] = AppProfile(typeOut: true)
        }
        a.sync(at: 10)
        let b = world.mac("B") { $0.appProfiles["com.apple.mail"] = AppProfile(typeOut: false) }
        // While B's join runs, the user saves Safari's settings on B (after the join has read iCloud's Safari).
        b.sync(at: 20) { $0.appProfiles["com.apple.Safari"] = AppProfile(noAI: true) }
        b.sync(at: 30); a.sync(at: 40); b.sync(at: 50)
        for mac in [a, b] {
            #expect(mac.config.appProfiles["com.apple.Safari"] == AppProfile(noAI: true),
                    "Mac \(mac.name): B's Safari save during the join was lost (\(ICAR2.describe(mac.config.appProfiles["com.apple.Safari"])))")
            #expect(mac.config.appProfiles["com.apple.mail"]?.typeOut == true,
                    "Mac \(mac.name): iCloud's Mail lost to B's pre-join value (\(ICAR2.describe(mac.config.appProfiles["com.apple.mail"])))")
        }
    }

    @Test("join (RP5): an edit on B in the seconds after a join that Settings interrupted, before the next run, is kept")
    func editRightAfterInterruptedJoinIsKept() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.maxTokens = 2000; $0.appProfiles["com.apple.mail"] = AppProfile(typeOut: true) }
        a.sync(at: 10)
        let b = world.mac("B") { $0.appProfiles["com.apple.mail"] = AppProfile(typeOut: false) }
        b.sync(at: 20) { $0.appProfiles["com.apple.Safari"] = AppProfile(noAI: true) }
        b.edit(at: 22) { $0.maxTokens = 3000 }
        b.sync(at: 27); a.sync(at: 40); b.sync(at: 50)
        for mac in [a, b] {
            #expect(mac.config.maxTokens == 3000, "Mac \(mac.name): B's maxTokens edit was undone (\(mac.config.maxTokens))")
        }
    }

    @Test("join (RP5b): an edit on B, right after an interrupted join, of an app only B had is kept")
    func editOfOwnAppRightAfterInterruptedJoinIsKept() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.appProfiles["com.apple.mail"] = AppProfile(typeOut: true) }
        a.sync(at: 10)
        let b = world.mac("B") {
            $0.appProfiles["com.apple.mail"] = AppProfile(typeOut: false)
            $0.appProfiles["com.apple.Notes"] = AppProfile(typeOut: true)
        }
        b.sync(at: 20) { $0.appProfiles["com.apple.Safari"] = AppProfile(noAI: true) }
        b.edit(at: 22) { $0.appProfiles["com.apple.Notes"] = AppProfile(noAI: true) }
        b.sync(at: 27); a.sync(at: 40); b.sync(at: 50)
        for mac in [a, b] {
            #expect(mac.config.appProfiles["com.apple.Notes"] == AppProfile(noAI: true),
                    "Mac \(mac.name): B's Notes edit was undone (\(ICAR2.describe(mac.config.appProfiles["com.apple.Notes"])))")
        }
    }

    // MARK: Sync turned back on, interrupted by Settings (RP6, RP7)

    /// A and B synced; B turns sync off, edits Mail offline; A then makes a newer Mail edit; B turns sync on again
    /// (with Settings saving Safari during that run when `interrupted`).
    private func rejoinWithMailEdits(interrupted: Bool) -> (ICAMac, ICAMac) {
        let (_, a, b) = ICA.pair { $0.appProfiles["com.apple.mail"] = AppProfile(typeOut: true) }
        b.edit(at: 10) { $0.iCloudSync.enabled = false }; b.sync(at: 10)
        b.edit(at: 50) { $0.appProfiles["com.apple.mail"] = AppProfile(typeOut: false) }
        a.edit(at: 60) { $0.appProfiles["com.apple.mail"] = AppProfile(typeOut: true, noAI: true) }; a.sync(at: 60)
        b.edit(at: 100) { $0.iCloudSync.enabled = true }
        if interrupted {
            b.sync(at: 100) { $0.appProfiles["com.apple.Safari"] = AppProfile(noAI: true) }
        } else {
            b.sync(at: 100)
        }
        b.sync(at: 110); a.sync(at: 120); b.sync(at: 130)
        return (a, b)
    }

    @Test("rejoin (RP6): sync turned back on while Settings saves another app: A's newer Mail edit wins, as without the save")
    func rejoinWithSiblingSaveKeepsNewerEdit() throws {
        let (ca, cb) = rejoinWithMailEdits(interrupted: false)
        for mac in [ca, cb] {
            #expect(mac.config.appProfiles["com.apple.mail"] == AppProfile(typeOut: true, noAI: true),
                    "without the save, Mac \(mac.name): Mail is \(ICAR2.describe(mac.config.appProfiles["com.apple.mail"]))")
        }
        let (a, b) = rejoinWithMailEdits(interrupted: true)
        for mac in [a, b] {
            #expect(mac.config.appProfiles["com.apple.mail"] == AppProfile(typeOut: true, noAI: true),
                    "Mac \(mac.name): A's newer Mail edit lost to B's older offline one (\(ICAR2.describe(mac.config.appProfiles["com.apple.mail"])))")
        }
    }

    /// A and B synced with hidden words on; B turns sync off and adds b1; A adds a1; B turns sync on again (with
    /// Settings saving a redaction switch during that run when `interrupted`).
    private func rejoinWithWordEdits(interrupted: Bool) -> (ICAMac, ICAMac) {
        let world = ICAWorld()
        let a = world.mac("A") { $0.iCloudSync.hiddenWords = true; $0.redaction.customWords = ["x"] }
        let b = world.mac("B") { $0.iCloudSync.hiddenWords = true }
        a.sync(at: 1); b.sync(at: 2); a.sync(at: 3); b.sync(at: 4)
        b.edit(at: 10) { $0.iCloudSync.enabled = false }; b.sync(at: 10)
        b.edit(at: 50) { $0.redaction.customWords.append("b1") }
        a.edit(at: 60) { $0.redaction.customWords.append("a1") }; a.sync(at: 60)
        b.edit(at: 100) { $0.iCloudSync.enabled = true }
        if interrupted {
            b.sync(at: 100) { $0.redaction.phones = false }
        } else {
            b.sync(at: 100)
        }
        b.sync(at: 110); a.sync(at: 120); b.sync(at: 130); a.sync(at: 140)
        return (a, b)
    }

    @Test("rejoin (RP7): sync turned back on while Settings saves a redaction switch: both Macs' hidden words added meanwhile are kept")
    func rejoinWithRedactionSaveKeepsBothWords() throws {
        let (ca, cb) = rejoinWithWordEdits(interrupted: false)
        for mac in [ca, cb] {
            #expect(ICAR.hidden(mac) == ["a1", "b1", "x"], "without the save, Mac \(mac.name) hides \(ICAR.hidden(mac))")
        }
        let (a, b) = rejoinWithWordEdits(interrupted: true)
        for mac in [a, b] {
            #expect(ICAR.hidden(mac) == ["a1", "b1", "x"], "Mac \(mac.name) hides \(ICAR.hidden(mac)): a word added meanwhile was lost")
        }
    }

    // MARK: A join during which Settings saves the collection itself (RP8, RP8b)

    @Test("join (RP8): Settings adding a command during B's join keeps every Mac's commands, A's real edit too")
    func joinWithSettingsAddingCommandKeepsAll() throws {
        let world = ICAWorld()
        let a = world.mac("A")
        a.sync(at: 10)
        a.edit(at: 15) { $0.customCommands = [ICA.command("alpha")] }  // a real edit, after A joined
        a.sync(at: 15)
        let b = world.mac("B") { $0.customCommands = [ICA.command("beta")] }
        b.sync(at: 20) { $0.customCommands.append(ICA.command("delta")) }
        b.sync(at: 30); a.sync(at: 40); b.sync(at: 50)
        for mac in [a, b] {
            #expect(ICAR.names(mac) == ["alpha", "beta", "delta"], "Mac \(mac.name) has \(ICAR.names(mac)): a command was lost")
        }
    }

    @Test("join (RP8b): Settings adding a hidden word during B's join keeps every Mac's words, A's real edit too")
    func joinWithSettingsAddingWordKeepsAll() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.iCloudSync.hiddenWords = true }
        a.sync(at: 10)
        a.edit(at: 15) { $0.redaction.customWords = ["Acme"] }
        a.sync(at: 15)
        let b = world.mac("B") { $0.iCloudSync.hiddenWords = true; $0.redaction.customWords = ["Bolt"] }
        b.sync(at: 20) { $0.redaction.customWords.append("Coil") }
        b.sync(at: 30); a.sync(at: 40); b.sync(at: 50)
        for mac in [a, b] {
            #expect(ICAR.hidden(mac) == ["Acme", "Bolt", "Coil"], "Mac \(mac.name) hides \(ICAR.hidden(mac)): a word was lost")
        }
    }

    // MARK: The hidden-words field (RP9)

    @Test("Settings (RP9): editing the hidden words while another Mac deleted one: the deletion sticks, the typed word is added")
    func hiddenWordsFieldKeepsAnotherMacsDelete() throws {
        // The field showed "Acme"; meanwhile another Mac deleted Acme (the list as it is now: []); the user types Bolt.
        let out = RedactionSettings.edited([], field: "Acme, Bolt", shown: ["Acme"])
        #expect(out == ["Bolt"], "the words saved are \(out): Acme, deleted on another Mac, came back")
        // The same with another word added elsewhere meanwhile: it stays.
        let withOther = RedactionSettings.edited(["Coil"], field: "Acme, Bolt", shown: ["Acme"])
        #expect(Set(withOther) == ["Bolt", "Coil"], "the words saved are \(withOther)")
    }

    // MARK: The first Mac's collection, still join-stamped (RP22, RP22b)

    @Test("merge (RP22): commands of the first Mac to turn sync on; a second Mac joins and deletes one; it stays deleted")
    func deleteOfFirstMacsCommandSticks() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.customCommands = [ICA.command("alpha"), ICA.command("beta")] }
        a.sync(at: 10); a.sync(at: 15)  // into an empty iCloud
        let b = world.mac("B")
        b.sync(at: 20); b.sync(at: 25)
        b.edit(at: 30) { $0.customCommands.removeAll { $0.name == "alpha" } }
        b.sync(at: 30)
        a.sync(at: 40); b.sync(at: 50); a.sync(at: 60)
        for mac in [a, b] {
            #expect(ICAR.names(mac) == ["beta"], "Mac \(mac.name) has \(ICAR.names(mac)): B's delete of alpha was undone")
        }
    }

    @Test("merge (RP22b): hidden words of the first Mac to turn sync on; the second Mac deletes one; it stays deleted")
    func deleteOfFirstMacsHiddenWordSticks() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.iCloudSync.hiddenWords = true; $0.redaction.customWords = ["Acme", "Bolt"] }
        let b = world.mac("B") { $0.iCloudSync.hiddenWords = true }
        a.sync(at: 1); b.sync(at: 2); a.sync(at: 3)
        b.edit(at: 30) { $0.redaction.customWords.removeAll { $0 == "Acme" } }
        b.sync(at: 30)
        a.sync(at: 40); b.sync(at: 50); a.sync(at: 60)
        for mac in [a, b] {
            #expect(ICAR.hidden(mac) == ["Bolt"], "Mac \(mac.name) hides \(ICAR.hidden(mac)): B's delete of Acme was undone")
        }
    }

    // MARK: Remove from iCloud, then turned on again while the other Mac sleeps (PB1, PB1j, PB2)

    /// A, the first Mac to turn sync on, with alpha and the hidden word Acme; B joins with nothing and adds beta and
    /// Bolt. A does "Remove from iCloud…", adds gamma and Coil while sync is off, and turns sync on again while B sleeps
    /// (iCloud is empty). B wakes and puts its own back.
    private func removeThenRejoinWhileOtherSleeps(newID: Bool) -> (ICAMac, ICAMac) {
        let world = ICAWorld()
        let a = world.mac("A") {
            $0.customCommands = [ICA.command("alpha")]
            $0.iCloudSync.hiddenWords = true; $0.redaction.customWords = ["Acme"]
        }
        a.sync(at: 10)
        let b = world.mac("B") { $0.iCloudSync.hiddenWords = true }
        b.sync(at: 20)
        b.edit(at: 30) { $0.customCommands.append(ICA.command("beta")); $0.redaction.customWords.append("Bolt") }
        b.sync(at: 30)
        a.sync(at: 40)
        a.removeFromICloud(at: 50, newID: newID)
        a.edit(at: 60) { $0.customCommands.append(ICA.command("gamma")); $0.redaction.customWords.append("Coil") }
        a.edit(at: 70) { $0.iCloudSync.enabled = true }
        a.sync(at: 70)  // into an empty iCloud
        b.sync(at: 80)  // B wakes and puts its own back
        a.sync(at: 90); b.sync(at: 100); a.sync(at: 110); b.sync(at: 120)
        return (a, b)
    }

    @Test("rejoin (PB1): Remove from iCloud on A, a command and a hidden word added while off, turned on while B sleeps: both kept on both Macs")
    func removeThenRejoinKeepsAddsMadeWhileOff() throws {
        let (a, b) = removeThenRejoinWhileOtherSleeps(newID: false)
        for mac in [a, b] {
            #expect(ICAR.names(mac) == ["alpha", "beta", "gamma"], "Mac \(mac.name) has \(ICAR.names(mac)): gamma, added on A while sync was off, was lost")
            #expect(ICAR.hidden(mac) == ["Acme", "Bolt", "Coil"], "Mac \(mac.name) hides \(ICAR.hidden(mac)): Coil, added on A while sync was off, was lost")
        }
    }

    @Test("rejoin (PB1j): Remove from iCloud on A, a jargon line added while off, turned on while B sleeps: kept on both Macs")
    func removeThenRejoinKeepsJargonAddedWhileOff() throws {
        let world = ICAWorld()
        let a = world.mac("A")
        a.writeJargon("alpha\n", at: 5)
        a.sync(at: 10)
        let b = world.mac("B")
        b.sync(at: 20)
        b.writeJargon("alpha\nbeta\n", at: 30)
        b.sync(at: 30)
        a.sync(at: 40)
        a.removeFromICloud(at: 50)
        a.writeJargon("alpha\nbeta\ngamma\n", at: 60)
        a.edit(at: 70) { $0.iCloudSync.enabled = true }
        a.sync(at: 70); b.sync(at: 80); a.sync(at: 90); b.sync(at: 100); a.sync(at: 110); b.sync(at: 120)
        for mac in [a, b] {
            #expect(ICA.lines(mac.jargon) == ["alpha", "beta", "gamma"], "Mac \(mac.name) jargon \(ICA.lines(mac.jargon)): gamma, added on A while sync was off, was lost")
        }
    }

    @Test("rejoin (PB2): Remove from iCloud on A while B holds A's own last edit, gamma added while off, turned on while B sleeps: kept")
    func removeThenRejoinKeepsAddWhenOtherHoldsOwnEdit() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.customCommands = [ICA.command("alpha")] }
        a.sync(at: 10)
        let b = world.mac("B") { $0.customCommands = [ICA.command("beta")] }
        b.sync(at: 20); b.sync(at: 25); a.sync(at: 27); b.sync(at: 28)
        a.edit(at: 30) { $0.customCommands.append(ICA.command("delta")) }  // B's list is now stamped by A
        a.sync(at: 30); b.sync(at: 35)
        a.removeFromICloud(at: 50)
        a.edit(at: 60) { $0.customCommands.append(ICA.command("gamma")) }
        a.edit(at: 70) { $0.iCloudSync.enabled = true }
        a.sync(at: 70); b.sync(at: 80); a.sync(at: 90); b.sync(at: 100); a.sync(at: 110)
        for mac in [a, b] {
            #expect(ICAR.names(mac) == ["alpha", "beta", "delta", "gamma"], "Mac \(mac.name) has \(ICAR.names(mac)): gamma, added on A while sync was off, was lost")
        }
    }

    // MARK: Guards (RP20, RP22c, RP23, RP23b, RP13, PB1 control, PB1b): these pass now and must keep passing

    @Test("rejoin (PB1 control, guard): the same as PB1 with A's record lost (a new Mac id): the adds made while off are kept")
    func rejoinUnderNewIDKeepsAddsMadeWhileOff() throws {
        let (a, b) = removeThenRejoinWhileOtherSleeps(newID: true)
        for mac in [a, b] {
            #expect(ICAR.names(mac) == ["alpha", "beta", "gamma"], "Mac \(mac.name) has \(ICAR.names(mac))")
            #expect(ICAR.hidden(mac) == ["Acme", "Bolt", "Coil"], "Mac \(mac.name) hides \(ICAR.hidden(mac))")
        }
    }

    @Test("rejoin (PB1b, guard): Remove from iCloud on A, B puts its own back first, A adds gamma and turns sync on: kept")
    func removeThenRejoinAfterOtherPutsBackKeepsAdd() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.customCommands = [ICA.command("alpha")] }
        a.sync(at: 10)
        let b = world.mac("B")
        b.sync(at: 20)
        b.edit(at: 30) { $0.customCommands.append(ICA.command("beta")) }
        b.sync(at: 30); a.sync(at: 40)
        a.removeFromICloud(at: 50)
        b.sync(at: 55)  // B is awake: it puts its own back before A turns sync on again
        a.edit(at: 60) { $0.customCommands.append(ICA.command("gamma")) }
        a.edit(at: 70) { $0.iCloudSync.enabled = true }
        a.sync(at: 70); b.sync(at: 80); a.sync(at: 90); b.sync(at: 100)
        for mac in [a, b] {
            #expect(ICAR.names(mac) == ["alpha", "beta", "gamma"], "Mac \(mac.name) has \(ICAR.names(mac))")
        }
    }

    @Test("merge (RP20, guard): after three Macs' simultaneous join settles, a delete on one Mac sticks on all three")
    func deleteAfterThreeWayJoinSticks() throws {
        let world = ICAWorld()
        let fa = ICAR.folder(world, "a"), fb = ICAR.folder(world, "b"), fc = ICAR.folder(world, "c")
        let a = world.mac("A") { $0.customCommands = [ICA.command("alpha")] }
        let b = world.mac("B") { $0.customCommands = [ICA.command("beta")] }
        let c = world.mac("C") { $0.customCommands = [ICA.command("gamma")] }
        a.folder = fa; b.folder = fb; c.folder = fc
        a.sync(at: 60); b.sync(at: 66); c.sync(at: 72)
        ICAR.copy(fa, to: fb); ICAR.copy(fa, to: fc)
        b.sync(at: 120); c.sync(at: 126)
        ICAR.collide(server: fc, other: fb, into: world.folder)
        for mac in [a, b, c] { mac.folder = world.folder }
        for i in 0..<4 { let at = 180 + Double(i) * 60; a.sync(at: at); b.sync(at: at + 18); c.sync(at: at + 36) }
        for mac in [a, b, c] {
            #expect(ICAR.names(mac) == ["alpha", "beta", "gamma"], "before the delete, Mac \(mac.name) has \(ICAR.names(mac))")
        }
        b.edit(at: 500) { $0.customCommands.removeAll { $0.name == "alpha" } }
        b.sync(at: 500)
        for i in 0..<3 { let at = 520 + Double(i) * 60; a.sync(at: at); c.sync(at: at + 18); b.sync(at: at + 36) }
        for mac in [a, b, c] {
            #expect(ICAR.names(mac) == ["beta", "gamma"], "Mac \(mac.name) has \(ICAR.names(mac)): B's delete of alpha was undone")
        }
    }

    @Test("merge (RP22c, guard): B joins with its own command, then deletes one of the first Mac's commands; it stays deleted")
    func deleteAfterRealJoinMergeSticks() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.customCommands = [ICA.command("alpha"), ICA.command("beta")] }
        a.sync(at: 10); a.sync(at: 15)
        let b = world.mac("B") { $0.customCommands = [ICA.command("gamma")] }
        b.sync(at: 20); b.sync(at: 25)
        a.sync(at: 27)
        b.edit(at: 30) { $0.customCommands.removeAll { $0.name == "alpha" } }
        b.sync(at: 30)
        a.sync(at: 40); b.sync(at: 50); a.sync(at: 60)
        for mac in [a, b] {
            #expect(ICAR.names(mac) == ["beta", "gamma"], "Mac \(mac.name) has \(ICAR.names(mac))")
        }
    }

    @Test("merge (RP23, guard): two Macs turning sync on at once into an empty iCloud keep both; a third joins and deletes one; it sticks")
    func simultaneousFirstJoinsThenDeleteSticks() throws {
        let world = ICAWorld()
        let fa = ICAR.folder(world, "a"), fc = ICAR.folder(world, "c")
        let a = world.mac("A") { $0.customCommands = [ICA.command("alpha")] }
        let c = world.mac("C") { $0.customCommands = [ICA.command("gamma")] }
        a.folder = fa; c.folder = fc
        a.sync(at: 10); a.sync(at: 15); c.sync(at: 12); c.sync(at: 17)
        ICAR.collide(server: fc, other: fa, into: world.folder)
        a.folder = world.folder; c.folder = world.folder
        a.sync(at: 30); c.sync(at: 35); a.sync(at: 40); c.sync(at: 45)
        for mac in [a, c] {
            #expect(ICAR.names(mac) == ["alpha", "gamma"], "after the simultaneous first joins, Mac \(mac.name) has \(ICAR.names(mac))")
        }
        let b = world.mac("B")
        b.sync(at: 50); b.sync(at: 55)
        b.edit(at: 60) { $0.customCommands.removeAll { $0.name == "gamma" } }
        b.sync(at: 60)
        for i in 0..<3 { let at = 70 + Double(i) * 30; a.sync(at: at); c.sync(at: at + 10); b.sync(at: at + 20) }
        for mac in [a, b, c] {
            #expect(ICAR.names(mac) == ["alpha"], "Mac \(mac.name) has \(ICAR.names(mac)): B's delete of gamma was undone")
        }
    }

    @Test("merge (RP23b, guard): two Macs at once into an empty iCloud; a third joins and adds before the first wakes: every command kept")
    func simultaneousFirstJoinsThenAddKeepsAll() throws {
        let world = ICAWorld()
        let fa = ICAR.folder(world, "a"), fc = ICAR.folder(world, "c")
        let a = world.mac("A") { $0.customCommands = [ICA.command("alpha")] }
        let c = world.mac("C") { $0.customCommands = [ICA.command("gamma")] }
        a.folder = fa; c.folder = fc
        a.sync(at: 10); a.sync(at: 15); c.sync(at: 12); c.sync(at: 17)
        ICAR.collide(server: fc, other: fa, into: world.folder)
        c.folder = world.folder
        let b = world.mac("B")
        b.sync(at: 20); b.sync(at: 22)
        b.edit(at: 25) { $0.customCommands.append(ICA.command("beta")) }
        b.sync(at: 25)
        a.folder = world.folder
        for i in 0..<3 { let at = 30 + Double(i) * 30; a.sync(at: at); c.sync(at: at + 10); b.sync(at: at + 20) }
        for mac in [a, b, c] {
            #expect(ICAR.names(mac) == ["alpha", "beta", "gamma"], "Mac \(mac.name) has \(ICAR.names(mac)): a command was dropped")
        }
    }

    @Test("questions (RP13, guard): Clear on A reaches C, which slept through it; C's question asked after it is kept everywhere")
    func clearReachesSleepingMacAndLaterQuestionKept() throws {
        let world = ICAWorld()
        let on: (inout Config) -> Void = { $0.iCloudSync.recentQuestions = true }
        let a = world.mac("A", on), b = world.mac("B", on), c = world.mac("C", on)
        a.ask("old one", at: 1)
        a.sync(at: 2); b.sync(at: 3); c.sync(at: 4); a.sync(at: 5)
        a.clearQuestions(at: 100)
        a.sync(at: 100); b.sync(at: 110)
        c.ask("new one", at: 150)
        c.sync(at: 151); a.sync(at: 160); b.sync(at: 170); c.sync(at: 180)
        for mac in [a, b, c] {
            #expect(mac.questions == ["new one"], "Mac \(mac.name) has \(mac.questions)")
        }
    }
}
