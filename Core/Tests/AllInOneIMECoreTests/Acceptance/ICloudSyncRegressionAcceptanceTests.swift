import Foundation
import Testing
@testable import AllInOneIMECore

// Regression acceptance tests for sync through iCloud, from the re-check of 2026-10-17 (icloud-recheck-20261017.md:
// S26, S26b, D26c, D27b, S30, translateAlways), written by an independent reviewer; the implementer may not edit them.
// The app-level cases of the same re-check (S33, S34 and its variants), which live in Settings and can't be reached from
// the core, are specified for `make selftest` in ICloudSyncAppLevelCases.md beside this file.
//
// Every test says what the user sees: no Mac loses a real edit, and every Mac ends with the newest real change. They use
// the rig of ICloudSyncAcceptanceTests (`ICAWorld`, `ICAMac`); `sync(at:whileSettingsSaves:)` below is a run during
// which Settings saves another item under the same top-level key of config.json (another app's settings, a redaction
// switch, the hidden words) just before the run writes the file, as the app's sync queue and Settings' main thread can.

// MARK: - The rig's additions

extension ICAMac {
    /// One sync run at `seconds` during which Settings saves `change` (`AIConfig.writing`, the keys it changes, the file
    /// stamped with this Mac's clock) just before the run writes config.json; the run then writes as it always does
    /// (`ICloudSync.writeConfig`: a key changed meanwhile is left as Settings saved it).
    @discardableResult
    func sync(at seconds: TimeInterval, whileSettingsSaves change: @escaping (inout Config) -> Void) -> ICloudSyncEngine.Report {
        clock = ICA.t(seconds)
        let when = clock
        let saved = ICARSaved()
        var engine = self.engine
        engine.writeConfig = { config, old, keys, url in
            if !saved.done {
                saved.done = true
                let before = try Config.load(from: url)
                var after = before
                change(&after)
                try AIConfig.writing(after, from: before, keys: AIConfig.changedKeys(before, after), at: url)
                ICA.touch(url, when)
            }
            return try ICloudSync.writeConfig(config, readAs: old, keys: keys, at: url)
        }
        let report = engine.run()
        if !saved.done {
            // The run didn't write the config: the scenario didn't happen as described. Settings' save, after it.
            Issue.record("Mac \(name)'s run at \(seconds) wrote nothing into config.json: Settings' save came after it")
            edit(at: seconds, change)
        }
        return report
    }
}

/// Whether Settings' save in `sync(at:whileSettingsSaves:)` happened.
final class ICARSaved: @unchecked Sendable {
    var done = false
}

/// Several iCloud Drives that haven't met yet (each Mac sees only its own), and how they meet.
enum ICAR {
    /// A drive of its own in `world`, with its AllInOneIME folder (made on the first sync).
    static func folder(_ world: ICAWorld, _ name: String) -> ICloudSyncFolder {
        let drive = world.root.appendingPathComponent("Drive-\(name)", isDirectory: true)
        try! FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        return ICloudSyncFolder(url: drive.appendingPathComponent("AllInOneIME", isDirectory: true))
    }

    /// `to` now holds what `from` holds (iCloud brought one Mac's files to another).
    static func copy(_ from: ICloudSyncFolder, to: ICloudSyncFolder) {
        try? FileManager.default.removeItem(at: to.url)
        try! FileManager.default.createDirectory(at: to.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! FileManager.default.copyItem(at: from.url, to: to.url)
    }

    /// iCloud Drive meeting two Macs' independently written files of the same name: `server`'s keeps the name, `other`'s
    /// becomes "name 2.ext" (the same content: one file).
    static func collide(server: ICloudSyncFolder, other: ICloudSyncFolder, into out: ICloudSyncFolder) {
        copy(server, to: out)
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: other.url.path)) ?? [] {
            let source = other.url.appendingPathComponent(name), target = out.url.appendingPathComponent(name)
            if fm.fileExists(atPath: target.path) {
                if (try? Data(contentsOf: source)) == (try? Data(contentsOf: target)) { continue }
                let ext = (name as NSString).pathExtension, stem = (name as NSString).deletingPathExtension
                try? fm.copyItem(at: source, to: out.url.appendingPathComponent("\(stem) 2" + (ext.isEmpty ? "" : "." + ext)))
            } else {
                try? fm.copyItem(at: source, to: target)
            }
        }
    }

    static func names(_ mac: ICAMac) -> [String] { mac.config.customCommands.map(\.name).sorted() }
    static func hidden(_ mac: ICAMac) -> [String] { mac.config.redaction.customWords.sorted() }
}

// MARK: - The tests

@Suite("ICloudSyncRegressionAcceptance")
struct ICloudSyncRegressionAcceptanceTests {

    // MARK: A join during which Settings saves a sibling (S26, S26b, D26c, D27b)

    @Test("join (S26): Settings saving another app's settings during a join never lets this Mac's pre-join value of an app beat iCloud's")
    func joinWithSiblingAppSavePreJoinValue() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.appProfiles["com.apple.mail"] = AppProfile(typeOut: true) }
        a.sync(at: 10)
        let b = world.mac("B") { $0.appProfiles["com.apple.mail"] = AppProfile(typeOut: false) }
        // B turns sync on; while its join runs, Settings on B saves Safari's settings (the same top-level key, appProfiles).
        b.sync(at: 20) { $0.appProfiles["com.apple.Safari"] = AppProfile(noAI: true) }
        b.sync(at: 30)
        a.sync(at: 40)
        b.sync(at: 50)
        for mac in [a, b] {
            #expect(mac.config.appProfiles["com.apple.mail"]?.typeOut == true,
                    "Mac \(mac.name): a joining Mac's pre-join Mail setting beat iCloud's (typeOut \(String(describing: mac.config.appProfiles["com.apple.mail"]?.typeOut)))")
            #expect(mac.config.appProfiles["com.apple.Safari"]?.noAI == true, "Mac \(mac.name): the Safari setting saved on B was lost")
        }
    }

    @Test("join (S26b): Settings saving another app's settings during a join never undoes another Mac's real edit of an app")
    func joinWithSiblingAppSaveRealEdit() throws {
        let world = ICAWorld()
        let a = world.mac("A")
        a.sync(at: 10)
        a.edit(at: 20) { $0.appProfiles["com.apple.mail"] = AppProfile(typeOut: true); $0.maxTokens = 2000 }
        a.sync(at: 20)
        let b = world.mac("B") { $0.appProfiles["com.apple.mail"] = AppProfile(typeOut: false) }
        b.sync(at: 100) { $0.appProfiles["com.apple.Safari"] = AppProfile(noAI: true) }
        b.sync(at: 110)
        a.sync(at: 120)
        b.sync(at: 130)
        for mac in [a, b] {
            #expect(mac.config.appProfiles["com.apple.mail"]?.typeOut == true,
                    "Mac \(mac.name): A's real Mail edit was lost to B's pre-join value (typeOut \(String(describing: mac.config.appProfiles["com.apple.mail"]?.typeOut)))")
            #expect(mac.config.maxTokens == 2000, "Mac \(mac.name): maxTokens \(mac.config.maxTokens)")
            #expect(mac.config.appProfiles["com.apple.Safari"]?.noAI == true, "Mac \(mac.name): the Safari setting saved on B was lost")
        }
    }

    @Test("join (D26c): Settings saving the hidden words during a join never undoes another Mac's real edit of a redaction switch")
    func joinWithSiblingRedactionSaveRealSwitchEdit() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.redaction.enabled = true }
        a.sync(at: 10)
        a.edit(at: 20) { $0.redaction.phones = false }  // A turns off hiding phone numbers
        a.sync(at: 20)
        let b = world.mac("B") { $0.redaction.enabled = true }  // phone numbers hidden (the default); hidden words not synced
        #expect(b.config.redaction.phones == true)
        // While B's join runs, Settings on B saves a hidden word (the same top-level key, redaction; this Mac's only).
        b.sync(at: 100) { $0.redaction.customWords.append("Bolt") }
        b.sync(at: 110)
        a.sync(at: 120)
        b.sync(at: 130)
        for mac in [a, b] {
            #expect(mac.config.redaction.phones == false,
                    "Mac \(mac.name): A's switch (phone numbers off) was turned back on by B's pre-join value")
        }
        #expect(b.config.redaction.customWords == ["Bolt"], "B's own hidden word: \(b.config.redaction.customWords)")
    }

    @Test("join (D27b): Settings saving a redaction switch during a join never drops another Mac's real hidden-word edit")
    func joinWithSiblingRedactionSaveRealHiddenWords() throws {
        let world = ICAWorld()
        let a = world.mac("A") { $0.iCloudSync.hiddenWords = true }
        a.sync(at: 10)
        a.edit(at: 20) { $0.redaction.customWords = ["Acme"] }  // a real edit, after A joined
        a.sync(at: 20)
        let b = world.mac("B") { $0.iCloudSync.hiddenWords = true; $0.redaction.customWords = ["Bolt"] }
        // While B's join runs, Settings on B saves the phone-number switch (the same top-level key, redaction).
        b.sync(at: 100) { $0.redaction.phones = false }
        for i in 0..<3 {
            b.sync(at: 110 + Double(i) * 20)
            a.sync(at: 120 + Double(i) * 20)
        }
        for mac in [a, b] {
            #expect(ICAR.hidden(mac) == ["Acme", "Bolt"], "Mac \(mac.name) hides \(ICAR.hidden(mac)): a hidden word was lost")
            #expect(mac.config.redaction.phones == false, "Mac \(mac.name): the switch saved on B was lost")
        }
    }

    // MARK: Provisional merges: a delete sticks, simultaneous joins drop nothing (S30, S30b, S18, S31)

    @Test("merge (S30): a command deleted on a Mac that already has another Mac's join merge stays deleted on every Mac")
    func deleteAfterSeeingJoinMergeSticks() throws {
        let world = ICAWorld()
        let b = world.mac("B") { $0.customCommands = [ICA.command("beta")] }
        b.sync(at: 10)
        let a = world.mac("A") { $0.customCommands = [ICA.command("alpha")] }
        a.sync(at: 20)  // A joins: [beta, alpha] goes up. A then sleeps before its own upload brings it another run.
        b.sync(at: 30)
        #expect(ICAR.names(b) == ["alpha", "beta"], "B got A's join merge: \(ICAR.names(b))")
        // B, having seen A's merge, deletes alpha.
        b.edit(at: 40) { $0.customCommands.removeAll { $0.name == "alpha" } }
        b.sync(at: 40)
        a.sync(at: 50)  // A wakes
        b.sync(at: 60)
        a.sync(at: 70)
        for mac in [a, b] {
            #expect(ICAR.names(mac) == ["beta"], "Mac \(mac.name) has \(ICAR.names(mac)): B's delete of alpha was undone")
        }
        // Deleted again (if it came back): it must stick this time at the latest.
        b.edit(at: 100) { $0.customCommands.removeAll { $0.name == "alpha" } }
        b.sync(at: 100)
        a.sync(at: 110)
        b.sync(at: 120)
        a.sync(at: 130)
        for mac in [a, b] {
            #expect(ICAR.names(mac) == ["beta"], "Mac \(mac.name) has \(ICAR.names(mac)) after the second delete")
        }
    }

    @Test("merge (S30b, guard): a delete after the joining Mac's merge settled stays deleted")
    func deleteAfterJoinMergeSettledSticks() throws {
        let world = ICAWorld()
        let b = world.mac("B") { $0.customCommands = [ICA.command("beta")] }
        b.sync(at: 10)
        let a = world.mac("A") { $0.customCommands = [ICA.command("alpha")] }
        a.sync(at: 20)
        a.sync(at: 21)  // the run A's own upload brings it (its folder watcher)
        b.sync(at: 30)
        b.edit(at: 40) { $0.customCommands.removeAll { $0.name == "alpha" } }
        b.sync(at: 40)
        a.sync(at: 50)
        b.sync(at: 60)
        for mac in [a, b] {
            #expect(ICAR.names(mac) == ["beta"], "Mac \(mac.name) has \(ICAR.names(mac))")
        }
    }

    @Test("merge (S18, guard): three Macs turning sync on at once, before they see each other's files, all end with every Mac's commands")
    func threeMacsJoinAtOnceKeepEveryCommand() throws {
        let world = ICAWorld()
        let fa = ICAR.folder(world, "a"), fb = ICAR.folder(world, "b"), fc = ICAR.folder(world, "c")
        let a = world.mac("A") { $0.customCommands = [ICA.command("alpha")] }
        let b = world.mac("B") { $0.customCommands = [ICA.command("beta")] }
        let c = world.mac("C") { $0.customCommands = [ICA.command("gamma")] }
        a.folder = fa; b.folder = fb; c.folder = fc
        a.sync(at: 60); b.sync(at: 66); c.sync(at: 72)
        // iCloud keeps A's files; B and C each see A's (not each other's yet) and merge.
        ICAR.copy(fa, to: fb); ICAR.copy(fa, to: fc)
        b.sync(at: 120); c.sync(at: 126)
        // B's and C's settings.json meet: C's keeps the name.
        ICAR.collide(server: fc, other: fb, into: world.folder)
        for mac in [a, b, c] { mac.folder = world.folder }
        for i in 0..<4 {
            let at = 180 + Double(i) * 60
            a.sync(at: at); b.sync(at: at + 18); c.sync(at: at + 36)
        }
        for mac in [a, b, c] {
            #expect(ICAR.names(mac) == ["alpha", "beta", "gamma"], "Mac \(mac.name) has \(ICAR.names(mac)): a command was dropped")
        }
    }

    @Test("merge (S31, guard): three Macs joining at once with clashing names settle, every Mac's commands and hidden words kept, the same everywhere")
    func threeMacsJoinAtOnceWithClashesSettle() throws {
        func command(_ name: String, _ prompt: String) -> CustomCommand { CustomCommand(name: name, type: .prompt, prompt: prompt) }
        let world = ICAWorld()
        let fa = ICAR.folder(world, "a"), fb = ICAR.folder(world, "b"), fc = ICAR.folder(world, "c")
        let a = world.mac("A") { c in
            c.customCommands = [command("x", "from A"), ICA.command("alpha")]
            c.iCloudSync.hiddenWords = true
            c.redaction.customWords = ["one", "Two"]
        }
        let b = world.mac("B") { c in
            c.customCommands = [command("X", "from B"), ICA.command("beta")]
            c.iCloudSync.hiddenWords = true
            c.redaction.customWords = ["two", "three"]
        }
        let c = world.mac("C") { c in
            c.customCommands = [command("x", "from C"), ICA.command("gamma")]
            c.iCloudSync.hiddenWords = true
            c.redaction.customWords = ["THREE", "four"]
        }
        a.folder = fa; b.folder = fb; c.folder = fc
        a.sync(at: 60); b.sync(at: 66); c.sync(at: 72)
        ICAR.copy(fa, to: fb); ICAR.copy(fa, to: fc)
        b.sync(at: 120); c.sync(at: 126)
        ICAR.collide(server: fc, other: fb, into: world.folder)
        for mac in [a, b, c] { mac.folder = world.folder }
        var uploads: [Int] = []
        for i in 0..<8 {
            let at = 180 + Double(i) * 60
            uploads.append(a.sync(at: at).uploaded.count)
            uploads.append(b.sync(at: at + 18).uploaded.count)
            uploads.append(c.sync(at: at + 36).uploaded.count)
        }
        #expect(uploads.suffix(6).allSatisfy { $0 == 0 }, "the runs never settle: uploads \(uploads)")
        #expect(Set(ICAR.names(a).map { $0.lowercased() }) == ["x", "alpha", "beta", "gamma"], "A has \(ICAR.names(a))")
        #expect(ICAR.names(a) == ICAR.names(b) && ICAR.names(b) == ICAR.names(c),
                "the commands differ: A \(ICAR.names(a)), B \(ICAR.names(b)), C \(ICAR.names(c))")
        #expect(Set(ICAR.hidden(a).map { $0.lowercased() }) == ["one", "two", "three", "four"], "A hides \(ICAR.hidden(a))")
        #expect(ICAR.hidden(a) == ICAR.hidden(b) && ICAR.hidden(b) == ICAR.hidden(c),
                "the hidden words differ: A \(ICAR.hidden(a)), B \(ICAR.hidden(b)), C \(ICAR.hidden(c))")
    }

    // MARK: An app's "Always Translate as You Type"

    @Test("what (translateAlways): an app's \"Always Translate as You Type\" turned on, then off, on one Mac is so on the other")
    func translateAlwaysOffReachesOtherMac() throws {
        let (_, a, b) = ICA.pair()
        a.edit(at: 100) { $0.appProfiles["com.apple.mail"] = AppProfile(typeOut: true, translateAlways: true) }
        a.sync(at: 110)
        b.sync(at: 120)
        #expect(b.config.appProfiles["com.apple.mail"]?.translateAlways == true, "turning it on didn't reach B")
        // Off in Settings → Apps (the switch leaves it out); Mail keeps its other setting.
        a.edit(at: 200) { $0.appProfiles["com.apple.mail"]?.translateAlways = nil }
        a.sync(at: 210)
        b.sync(at: 220)
        a.sync(at: 230)
        b.sync(at: 240)
        for mac in [a, b] {
            let mail = mac.config.appProfiles["com.apple.mail"]
            #expect(mail?.translateAlways != true, "Mac \(mac.name): Mail still translates always after it was turned off on A")
            #expect(mail?.typeOut == true, "Mac \(mac.name): Mail's other setting was lost")
        }
    }
}
