import Foundation
import Testing
@testable import AllInOneIMECore

/// The command trigger syncs with the other settings, checked as Settings checks it; and every key of the config is
/// either synced or named as never synced, so that a new one is decided on rather than left behind.
@Suite(.serialized)
struct ICloudSyncCommandTriggerTests {
    let t0 = SyncRig.t0
    func t(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    @Test func theTriggerComesToTheOtherMacsAndBackToAt() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A"), b = try rig.mac("B")
        a.sync(at: t(0))
        b.sync(at: t(1))
        try a.edit(at: t(2)) { $0.commandTrigger = "~" }
        #expect(a.sync(at: t(3)).uploaded == ["commandTrigger"])
        #expect(b.sync(at: t(4)).applied == ["commandTrigger"])
        #expect(try b.config().commandTrigger == "~")
        let entry = try #require(try rig.settingsJSON()["commandTrigger"] as? [String: Any])
        #expect(entry["value"] as? String == "~")
        // Back to @ on B: A follows, and its file no longer names one (as a config at @ is written).
        try b.edit(at: t(5)) { $0.commandTrigger = "@" }
        #expect(b.sync(at: t(6)).uploaded == ["commandTrigger"])
        #expect(a.sync(at: t(7)).applied == ["commandTrigger"])
        #expect(try a.config().commandTrigger == "@")
        #expect(!(try String(contentsOf: a.configURL, encoding: .utf8)).contains("commandTrigger"))
        #expect(a.sync(at: t(8)).applied.isEmpty && b.sync(at: t(9)).uploaded.isEmpty)
    }

    /// A trigger Settings would refuse (a symbol typing needs, a letter, not a string) never comes in: this Mac's stays.
    @Test func aTriggerSettingsRefusesIsRefusedFromICloud() throws {
        let env = ICloudSync.Environment()
        for trigger in Config.commandTriggers {
            #expect(ICloudSync.problem("commandTrigger", .string(trigger), environment: env) == nil, "\(trigger)")
        }
        for refused in ["-", ",", "'", "a", "7", " ", "~~", ""] {
            #expect(ICloudSync.problem("commandTrigger", .string(refused), environment: env) == .outOfRange, "\(refused)")
        }
        #expect(ICloudSync.problem("commandTrigger", .number(1), environment: env) == .wrongType)
        #expect(ICloudSync.problem("commandTrigger", nil, environment: env) == .cannotDelete)

        var config = Config.default
        config.commandTrigger = "~"
        let applied = ICloudSync.applying(["commandTrigger": .string("-")], to: config, environment: env)
        #expect(applied.config.commandTrigger == "~" && applied.applied.isEmpty && applied.rejected == ["commandTrigger": .outOfRange])
        let taken = ICloudSync.applying(["commandTrigger": .string("#")], to: config, environment: env)
        #expect(taken.config.commandTrigger == "#" && taken.applied == ["commandTrigger"])
    }

    /// Each key a config file may hold syncs (as itself, or with the key that carries it) or never does.
    @Test func everyConfigKeyIsSyncedOrNeverSynced() {
        // Synced under other keys: the apps one by one, the hidden words as `redaction.customWords`.
        let carried: Set = ["appProfiles"]
        for key in Config.allKeys {
            #expect(ICloudSync.category(of: key) != nil || ICloudSync.neverSynced.contains(key) || carried.contains(key),
                    "\(key): neither synced nor in ICloud.neverSynced")
        }
        let synced = ICloudSync.values(of: .default, in: Set(ICloudSync.Category.allCases))
        #expect(synced["commandTrigger"] == .string("@"))
    }
}
