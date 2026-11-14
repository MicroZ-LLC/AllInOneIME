import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The key that switches the input language (`Config.switchKey`, 0.7.4): Shift by default, or Caps Lock. Its config key,
/// its sync through iCloud, its field in the settings document, and the session going by it.
@Suite(.serialized)
struct SwitchKeyTests {
    let t0 = SyncRig.t0
    func t(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    func decode(_ json: String) throws -> Config { try JSONDecoder().decode(Config.self, from: Data(json.utf8)) }
    func encoded(_ config: Config) throws -> String { String(decoding: try JSONEncoder().encode(config), as: UTF8.self) }

    // MARK: The config

    @Test func shiftByDefaultAndCapsLockWrittenOnlyWhenChosen() throws {
        // Shift: a new install, a file from before the setting, a value a later version added, one of the wrong type.
        #expect(Config.default.switchKey == .shift && Config.fresh.switchKey == .shift)
        #expect(try decode("{}").switchKey == .shift)
        #expect(try decode(#"{"switchKey": "rightOption"}"#).switchKey == .shift)
        #expect(try decode(#"{"switchKey": 1}"#).switchKey == .shift)
        #expect(try decode(#"{"switchKey": "shift"}"#).switchKey == .shift)
        // Chosen: kept, and written.
        let capsLock = try decode(#"{"switchKey": "capsLock"}"#)
        #expect(capsLock.switchKey == .capsLock)
        #expect(try encoded(capsLock).contains(#""switchKey":"capsLock""#))
        #expect(try decode(try encoded(capsLock)).switchKey == .capsLock)
        // Shift isn't written: a file from before the setting doesn't gain the key, nor one back on Shift.
        var back = capsLock
        back.switchKey = .shift
        let (written, fresh) = (try encoded(back), try encoded(.default))
        #expect(!written.contains("switchKey") && !fresh.contains("switchKey"))
        #expect(Config.allKeys.contains("switchKey") && SwitchKey.allCases.map(\.rawValue) == ["shift", "capsLock"])
    }

    // MARK: iCloud

    @Test func syncedWithTheOtherSettingsEitherWay() throws {
        #expect(ICloudSync.settingsKeys.contains("switchKey") && ICloudSync.category(of: "switchKey") == .settings)
        // Synced at Shift too (not written into the file then), so another Mac goes back to Shift with this one.
        #expect(ICloudSync.values(of: .default, in: [.settings])["switchKey"] == .string("shift"))
        var config = Config.default
        config.switchKey = .capsLock
        #expect(ICloudSync.values(of: config, in: [.settings])["switchKey"] == .string("capsLock"))
        #expect(ICloudSync.values(of: config, in: [.jargon])["switchKey"] == nil)
    }

    @Test func aValueThisVersionDoesntKnowIsRefused() {
        let env = ICloudSync.Environment()
        #expect(ICloudSync.problem("switchKey", .string("shift"), environment: env) == nil)
        #expect(ICloudSync.problem("switchKey", .string("capsLock"), environment: env) == nil)
        #expect(ICloudSync.problem("switchKey", .string("rightOption"), environment: env) == .unknownValue)
        #expect(ICloudSync.problem("switchKey", .bool(true), environment: env) == .wrongType)
        #expect(ICloudSync.problem("switchKey", nil, environment: env) == .cannotDelete)
        var config = Config.default
        config.switchKey = .capsLock
        let refused = ICloudSync.applying(["switchKey": .string("rightOption")], to: config, environment: env)
        #expect(refused.config.switchKey == .capsLock && refused.applied.isEmpty && refused.rejected == ["switchKey": .unknownValue])
        let taken = ICloudSync.applying(["switchKey": .string("shift")], to: config, environment: env)
        #expect(taken.config.switchKey == .shift && taken.applied == ["switchKey"])
    }

    @Test func capsLockComesToTheOtherMacsAndBackToShift() throws {
        let rig = try SyncRig()
        let a = try rig.mac("A"), b = try rig.mac("B")
        a.sync(at: t(0))
        b.sync(at: t(1))
        try a.edit(at: t(2)) { $0.switchKey = .capsLock }
        #expect(a.sync(at: t(3)).uploaded == ["switchKey"])
        #expect(b.sync(at: t(4)).applied == ["switchKey"])
        #expect(try b.config().switchKey == .capsLock)
        let entry = try #require(try rig.settingsJSON()["switchKey"] as? [String: Any])
        #expect(entry["value"] as? String == "capsLock")
        // Back to Shift on B: A follows, and its file no longer names one.
        try b.edit(at: t(5)) { $0.switchKey = .shift }
        #expect(b.sync(at: t(6)).uploaded == ["switchKey"])
        #expect(a.sync(at: t(7)).applied == ["switchKey"])
        #expect(try a.config().switchKey == .shift)
        #expect(!(try String(contentsOf: a.configURL, encoding: .utf8)).contains("switchKey"))
        #expect(a.sync(at: t(8)).applied.isEmpty && b.sync(at: t(9)).uploaded.isEmpty)
    }

    // MARK: The settings document

    @Test func underTheInputLanguagesOnTheMacOnly() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("switch-key-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("config.json")
        try Data(#"{"inputLanguages": ["zh", "en"]}"#.utf8).write(to: url)
        let library = PluginLibrary(directory: folder.appendingPathComponent("plugins", isDirectory: true))
        let mac = SettingsService(store: SettingsStore(configURL: url), platform: .mac, library: library)
        let input = try #require(mac.document().sections.first { $0.id == "input" })
        let ids = input.fields.map(\.id)
        // Under them, after Code, before the candidate layout (as the Mac's window has it).
        #expect(ids.firstIndex(of: "switchKey").map { $0 + 1 } == ids.firstIndex(of: "candidateLayout"), "\(ids)")
        #expect(ids.firstIndex(of: "inputLanguages").map { $0 < (ids.firstIndex(of: "switchKey") ?? 0) } == true, "\(ids)")
        let field = try #require(input.fields.first { $0.id == "switchKey" })
        #expect(field.kind == .choice && field.value == .string("shift") && field.label == UIText.switchKeyLabel && field.help == nil)
        #expect(field.choices?.map(\.value) == [.string("shift"), .string("capsLock")])
        #expect(input.fields.first { $0.id == "inputLanguages" }?.help == UIText.inputLanguagesHelp(.shift, switches: true))
        #expect(try mac.set("switchKey", to: .string("capsLock")).get() == ())
        #expect(try Config.load(from: url).switchKey == .capsLock)
        guard case .failure = mac.set("switchKey", to: .string("rightOption")) else {
            Issue.record("a key this version doesn't know is refused")
            return
        }
        // Caps Lock chosen: its row says it no longer locks capitals, and the input languages' names it.
        let after = try #require(mac.document().sections.first { $0.id == "input" })
        #expect(after.fields.first { $0.id == "switchKey" }?.help == UIText.switchKeyHelp(.capsLock))
        #expect(after.fields.first { $0.id == "inputLanguages" }?.help == UIText.inputLanguagesHelp(.capsLock, switches: true))
        // Windows doesn't turn the lock off: no field there.
        let windows = SettingsService(store: SettingsStore(configURL: url), platform: .windows, library: library)
        #expect(windows.document().field("switchKey") == nil)
    }

    @Test func theInterfaceNamesTheKeyChosen() {
        UIText.$scopedLanguage.withValue("en") {
            #expect(UIText.inputLanguagesHelp(.shift, switches: true) == "Tap Shift to switch; new text fields start in the first.")
            #expect(UIText.inputLanguagesHelp(.capsLock, switches: true) == "Press Caps Lock to switch; new text fields start in the first.")
            #expect(UIText.inputLanguagesHelp(.capsLock, switches: false) == "With one, Caps Lock doesn't switch")
            #expect(UIText.switchKeyHelp(.shift) == nil)
            #expect(UIText.switchKeyHelp(.capsLock) == "Caps Lock no longer locks capitals; type them with Shift.")
            #expect(SwitchKey.allCases.map(UIText.name) == ["Tap Shift", "Caps Lock"])
        }
    }

    // MARK: The session

    final class Rig {
        var config: Config
        let host: FakeHost
        var now: TimeInterval = 100

        init(_ key: SwitchKey) {
            var config = Config.default
            config.inputLanguages = [.chinese, .english]
            config.defaultInput = .chinese
            config.switchKey = key
            self.config = config
            var services = SessionServices(loadSettings: { config })
            let engine = FakeEngine()
            services.levelOne = { .engine(engine) }
            host = FakeHost(services: services)
            host.focus()
        }

        var input: Input { host.session.composer.input }

        func capsLock(on: Bool, held: Modifiers = []) {
            host.modifiers(ModifierChange(key: .capsLock, modifiers: held.union(on ? .capsLock : []), timestamp: now))
            now += 0.3
        }

        func shiftTap() {
            host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.shift, .leftShift], timestamp: now))
            now += 0.1
            host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [], timestamp: now))
            now += 0.3
        }
    }

    @Test func withShiftCapsLockIsCapsLock() {
        let rig = Rig(.shift)
        rig.capsLock(on: true)
        rig.capsLock(on: false)
        #expect(rig.input == .language(.chinese) && rig.host.platformActions.isEmpty)
        rig.shiftTap()
        #expect(rig.input == .language(.english))
    }

    @Test func withCapsLockEachPressSwitchesAndTurnsTheLockOff() {
        let rig = Rig(.capsLock)
        rig.capsLock(on: true)
        #expect(rig.input == .language(.english) && rig.host.platformActions == [.setCapsLock(false)])
        // The lock turned off, as asked: no second switch.
        rig.capsLock(on: false)
        #expect(rig.input == .language(.english) && rig.host.platformActions == [.setCapsLock(false)])
        rig.capsLock(on: true)
        #expect(rig.input == .language(.chinese) && rig.host.platformActions == [.setCapsLock(false), .setCapsLock(false)])
        // A tap of Shift is just Shift.
        rig.shiftTap()
        #expect(rig.input == .language(.chinese))
        // With another modifier held, Caps Lock is the system's; fn doesn't count.
        rig.capsLock(on: false)
        rig.capsLock(on: true, held: [.command, .leftCommand])
        #expect(rig.input == .language(.chinese) && rig.host.platformActions.count == 2)
        rig.capsLock(on: false)
        rig.capsLock(on: true, held: .function)
        #expect(rig.input == .language(.english) && rig.host.platformActions.count == 3)
    }
}
