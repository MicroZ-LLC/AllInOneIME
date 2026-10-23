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

    /// Autocomplete in an app is each Mac's own, as its switch is: the app's other settings sync, its autocomplete never
    /// goes up, and another Mac's settings for the app never replace this one's choice, nor delete it with theirs.
    @Test func anAppsAutocompleteIsEachMacsOwn() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A"), b = try rig.mac("B")
        a.sync(at: t(0))
        b.sync(at: t(1))
        try b.edit(at: t(2)) { $0.appProfiles["com.apple.mail"] = AppProfile(autocomplete: false) }
        #expect(b.sync(at: t(3)).uploaded.isEmpty, "only autocomplete: nothing to sync")
        try a.edit(at: t(4)) { $0.appProfiles["com.apple.mail"] = AppProfile(noAI: true, autocomplete: true) }
        #expect(a.sync(at: t(5)).uploaded == ["appProfiles.com.apple.mail"])
        let entry = try #require(try rig.settingsJSON()["appProfiles.com.apple.mail"] as? [String: Any])
        #expect(entry["value"] as? [String: Bool] == ["noAI": true], "\(entry)")
        #expect(b.sync(at: t(6)).applied == ["appProfiles.com.apple.mail"])
        #expect(try b.config().profile(for: "com.apple.mail") == AppProfile(noAI: true, autocomplete: false))
        #expect(try a.config().profile(for: "com.apple.mail") == AppProfile(noAI: true, autocomplete: true))
        // A removes Mail's settings: B's own autocomplete there stays.
        try a.edit(at: t(7)) { $0.appProfiles["com.apple.mail"] = nil }
        a.sync(at: t(8))
        b.sync(at: t(9))
        #expect(try b.config().profile(for: "com.apple.mail") == AppProfile(autocomplete: false))
        #expect(a.sync(at: t(10)).applied.isEmpty && b.sync(at: t(11)).uploaded.isEmpty)
    }

    /// Suggestions in an app are each Mac's own too, as their switch is: turned off and on again on one Mac (on is no
    /// value, as Settings writes it), they never go up, never come back from iCloud, and never reach another Mac.
    @Test func anAppsSuggestionsAreEachMacsOwn() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A"), b = try rig.mac("B")
        let slack = "com.tinyspeck.slackmacgap"
        a.sync(at: t(0))
        b.sync(at: t(1))
        try a.edit(at: t(2)) { $0.appProfiles[slack] = AppProfile(noAI: true) }
        #expect(a.sync(at: t(3)).uploaded == ["appProfiles.\(slack)"])
        #expect(b.sync(at: t(4)).applied == ["appProfiles.\(slack)"])
        func iCloudsSlack() throws -> [String: Any]? {
            try #require(try rig.settingsJSON()["appProfiles.\(slack)"] as? [String: Any])["value"] as? [String: Any]
        }
        // Off on A: nothing to sync.
        try a.edit(at: t(5)) { $0.changeProfile(for: slack) { $0.suggestions = false } }
        #expect(a.sync(at: t(6)).uploaded.isEmpty, "only suggestions: nothing to sync")
        #expect(try iCloudsSlack()?["suggestions"] == nil)
        #expect(b.sync(at: t(7)).applied.isEmpty)
        #expect(try b.config().profile(for: slack) == AppProfile(noAI: true))
        #expect(try a.config().profile(for: slack) == AppProfile(noAI: true, suggestions: false))
        // On again on A, and B changes Slack meanwhile: A keeps on, B's change comes, and neither copy holds suggestions.
        try a.edit(at: t(8)) { $0.changeProfile(for: slack) { $0.suggestions = nil } }
        try b.edit(at: t(9)) { $0.changeProfile(for: slack) { $0.typeOut = true } }
        #expect(b.sync(at: t(10)).uploaded == ["appProfiles.\(slack)"])
        a.sync(at: t(11))
        #expect(try a.config().profile(for: slack) == AppProfile(typeOut: true, noAI: true))
        #expect(try b.config().profile(for: slack) == AppProfile(typeOut: true, noAI: true))
        #expect(try iCloudsSlack()?["suggestions"] == nil)
        // Off again on A, then A changes Slack: A's off stays A's.
        try a.edit(at: t(12)) { $0.changeProfile(for: slack) { $0.suggestions = false } }
        try a.edit(at: t(13)) { $0.changeProfile(for: slack) { $0.typeOut = false } }
        #expect(a.sync(at: t(14)).uploaded == ["appProfiles.\(slack)"])
        #expect(try iCloudsSlack()?["suggestions"] == nil)
        b.sync(at: t(15))
        #expect(try b.config().profile(for: slack) == AppProfile(typeOut: false, noAI: true))
        #expect(try a.config().profile(for: slack) == AppProfile(typeOut: false, noAI: true, suggestions: false))
        // A stale value in iCloud (written by a build that synced it) doesn't come down either, and goes with A's next change.
        var stale = try rig.settingsJSON()
        var entry = try #require(stale["appProfiles.\(slack)"] as? [String: Any])
        entry["value"] = ["noAI": true, "typeOut": false, "suggestions": false]
        stale["appProfiles.\(slack)"] = entry
        try JSONSerialization.data(withJSONObject: stale).write(to: rig.folder.url.appendingPathComponent(ICloudSync.settingsFile))
        try b.edit(at: t(16)) { $0.changeProfile(for: slack) { $0.typeOut = nil } }
        b.sync(at: t(17))
        #expect(try b.config().profile(for: slack) == AppProfile(noAI: true))
        #expect(try iCloudsSlack()?["suggestions"] == nil)
        #expect(a.sync(at: t(18)).applied == ["appProfiles.\(slack)"])
        #expect(try a.config().profile(for: slack) == AppProfile(noAI: true, suggestions: false))
        #expect(a.sync(at: t(19)).uploaded.isEmpty && b.sync(at: t(20)).uploaded.isEmpty)
    }

    /// Every field of an app's settings is one this version knows (never carried up from iCloud as a newer version's).
    @Test func everyAppFieldIsKnown() throws {
        let every = AppProfile(inputLanguage: .english, rewriteStyles: [], typeOut: true, noAI: true, translateAlways: true,
                               autocomplete: true, suggestions: false)
        let data = try JSONEncoder().encode(every)
        let fields = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(fields.keys) == ICloudSync.knownFields(of: ICloudSync.appPrefix + "com.apple.mail"))
        #expect(ICloudSync.thisMacsOwnAppFields.isSubset(of: Set(fields.keys)))
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
