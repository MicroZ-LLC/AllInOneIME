import Foundation
import Testing
@testable import AllInOneIMECore
@testable import AllInOneIMEMac

/// A new version's notification (`UpdateNotifier`, 0.7.0): when a check in the background finds a newer version this
/// Mac can install, one notification, once a version, with Update and Don't Show Again. Through a fake poster: no test
/// posts a real notification or asks macOS anything. Each test has defaults and a config file of its own.
@MainActor
struct UpdateNoticeTests {
    /// What it was asked and what it posted. `permission` as macOS would say it; `answer`: what the user says when asked.
    @MainActor
    final class FakePoster: UpdateNoticePoster {
        var state: UpdateNoticePermission
        var answer: Bool
        var asked = 0
        var posted: [UpdateNotice] = []

        init(_ state: UpdateNoticePermission = .allowed, answer: Bool = true) {
            self.state = state
            self.answer = answer
        }

        func permission() async -> UpdateNoticePermission { state }

        func askPermission() async -> Bool {
            asked += 1
            state = answer ? .allowed : .denied
            return answer
        }

        func post(_ notice: UpdateNotice) async { posted.append(notice) }
    }

    /// A notifier on a config file (`config`) and defaults of the test's own; `remove()` deletes them.
    final class Fixture {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("update-notice-\(UUID().uuidString)", isDirectory: true)
        let suite = "allinoneime-update-notice-\(UUID().uuidString)"
        var configURL: URL { folder.appendingPathComponent("config.json") }

        init(config: String) throws {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(config.utf8).write(to: configURL)
        }

        var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

        /// A notifier as the input method makes one at launch: a restart is another one on the same defaults.
        @MainActor
        func notifier(_ poster: FakePoster) -> UpdateNotifier {
            UpdateNotifier(poster: poster, defaults: defaults, configURL: configURL)
        }

        func remove() {
            UserDefaults.standard.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
    }

    static func manifest(_ version: String) throws -> UpdateManifest {
        try UpdateInstallTests.manifest(version: version, build: "1")
    }

    @Test func aNewerVersionIsToldOnce() async throws {
        let fixture = try Fixture(config: "{}")
        defer { fixture.remove() }
        let poster = FakePoster()
        let notifier = fixture.notifier(poster)
        let first = try Self.manifest("0.7.1")
        #expect(await notifier.found(first, availability: .available, installable: true))
        #expect(poster.posted.map(\.version) == ["0.7.1"] && poster.posted[0].kind == .available)
        #expect(notifier.lastNotified == "0.7.1")
        // The next day's check finds the same version: not again.
        #expect(!(await notifier.found(first, availability: .available, installable: true)))
        // Nor after a restart: what was told is kept.
        let restarted = fixture.notifier(poster)
        #expect(!(await restarted.found(first, availability: .available, installable: true)))
        #expect(poster.posted.count == 1)
        // An older one (a release taken back) isn't told either; a newer one is.
        #expect(!(await restarted.found(try Self.manifest("0.7.0.1"), availability: .available, installable: true)))
        #expect(await restarted.found(try Self.manifest("0.7.2"), availability: .available, installable: true))
        #expect(poster.posted.map(\.version) == ["0.7.1", "0.7.2"] && restarted.lastNotified == "0.7.2")
    }

    /// Never with checking off, with notifications off, or for an update this Mac doesn't install (not newer, for a newer
    /// macOS, or a copy that isn't the installed one); nor while the config file doesn't parse. macOS is never asked.
    @Test func notWhenOffOrNotInstallable() async throws {
        let manifest = try Self.manifest("0.7.1")
        for config in [#"{"checkForUpdates": false}"#, #"{"notifiesUpdates": false}"#,
                       #"{"checkForUpdates": false, "notifiesUpdates": true}"#, #"{"provider": "#] {
            let fixture = try Fixture(config: config)
            defer { fixture.remove() }
            let poster = FakePoster(.notAsked)
            #expect(!(await fixture.notifier(poster).found(manifest, availability: .available, installable: true)), "\(config)")
            #expect(poster.posted.isEmpty && poster.asked == 0, "\(config)")
        }
        let fixture = try Fixture(config: "{}")
        defer { fixture.remove() }
        let poster = FakePoster(.notAsked)
        let notifier = fixture.notifier(poster)
        for availability in [UpdateAvailability.upToDate, .needsNewerSystem] {
            #expect(!(await notifier.found(manifest, availability: availability, installable: true)))
        }
        #expect(!(await notifier.found(manifest, availability: .available, installable: false)))
        #expect(poster.posted.isEmpty && poster.asked == 0 && notifier.lastNotified == nil)
    }

    /// Don't Show Again turns `notifiesUpdates` off in the config file, and only that: nothing is posted after, a newer
    /// version neither.
    @Test func dontShowAgainTurnsItOff() async throws {
        let fixture = try Fixture(config: #"{"provider": "anthropic", "aKeyOfALaterVersion": 1}"#)
        defer { fixture.remove() }
        let poster = FakePoster()
        let notifier = fixture.notifier(poster)
        #expect(await notifier.found(try Self.manifest("0.7.1"), availability: .available, installable: true))
        try notifier.respond(.dontShowAgain)
        let config = try Config.load(from: fixture.configURL)
        #expect(!config.notifiesUpdates && config.checkForUpdates && config.provider == .anthropic)
        let file = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.configURL)) as? [String: Any]
        #expect(file?["notifiesUpdates"] as? Bool == false && file?["aKeyOfALaterVersion"] as? Int == 1)
        #expect(!(await notifier.found(try Self.manifest("0.7.2"), availability: .available, installable: true)))
        #expect(poster.posted.map(\.version) == ["0.7.1"])
        // On again (Settings → About): the next version is told.
        try Config.change(at: fixture.configURL) { $0.notifiesUpdates = true }
        #expect(await notifier.found(try Self.manifest("0.7.2"), availability: .available, installable: true))
    }

    /// Update starts the About page's install; clicking the notification opens About. An install from a notification
    /// that fails, before the restart or in the helper after it, gets a short notification; one from About doesn't.
    @Test func updateStartsTheInstall() async throws {
        let fixture = try Fixture(config: "{}")
        defer { fixture.remove() }
        let poster = FakePoster()
        let notifier = fixture.notifier(poster)
        var installs = 0, opened = 0
        notifier.install = { installs += 1; return "0.7.1" }
        notifier.openAbout = { opened += 1 }
        try notifier.respond(.open)
        #expect(opened == 1 && installs == 0)
        try notifier.respond(.update)
        #expect(installs == 1 && opened == 1)
        // It failed before the restart: said once.
        await notifier.installFailed("0.7.1")
        await notifier.installFailed("0.7.1")
        #expect(poster.posted == [.failed("0.7.1")])
        // Started again; the helper rolled it back: said by the input method that starts next.
        try notifier.respond(.update)
        let next = fixture.notifier(poster)
        await next.restarted(after: nil)  // started again before the helper was done: nothing known yet
        await next.restarted(after: UpdateResult(from: "0.7.0", to: "0.7.1", ok: false, error: "it didn't start"))
        #expect(poster.posted == [.failed("0.7.1"), .failed("0.7.1")])
        // Installed: nothing to say.
        try notifier.respond(.update)
        await fixture.notifier(poster).restarted(after: UpdateResult(from: "0.7.0", to: "0.7.1", ok: true))
        // Not started (busy, say): nothing is waited for.
        notifier.install = { nil }
        try notifier.respond(.update)
        await notifier.installFailed("0.7.1")
        // An update from the About page that fails: About says so, no notification.
        await fixture.notifier(poster).restarted(after: UpdateResult(from: "0.7.0", to: "0.7.1", ok: false, error: "it didn't start"))
        #expect(poster.posted.count == 2)
    }

    /// macOS is asked only as the first notification is about to be posted: not when the notifier is made (at launch),
    /// not for a version that isn't told, not again once it answered.
    @Test func permissionIsAskedAtTheFirstPost() async throws {
        let fixture = try Fixture(config: "{}")
        defer { fixture.remove() }
        let poster = FakePoster(.notAsked, answer: true)
        let notifier = fixture.notifier(poster)
        await notifier.restarted(after: nil)
        #expect(!(await notifier.found(try Self.manifest("0.7.1"), availability: .needsNewerSystem, installable: true)))
        #expect(poster.asked == 0)
        #expect(await notifier.found(try Self.manifest("0.7.1"), availability: .available, installable: true))
        #expect(poster.asked == 1 && poster.posted.count == 1)
        #expect(await notifier.found(try Self.manifest("0.7.2"), availability: .available, installable: true))
        #expect(poster.asked == 1 && poster.posted.count == 2)
    }

    /// Not allowed: nothing is posted and nothing else happens (no error, no second prompt); the version isn't counted
    /// as told, so it is once notifications are allowed in System Settings.
    @Test func deniedPostsNothing() async throws {
        let fixture = try Fixture(config: "{}")
        defer { fixture.remove() }
        let poster = FakePoster(.notAsked, answer: false)
        let notifier = fixture.notifier(poster)
        let manifest = try Self.manifest("0.7.1")
        #expect(!(await notifier.found(manifest, availability: .available, installable: true)))
        #expect(!(await notifier.found(manifest, availability: .available, installable: true)))
        #expect(poster.asked == 1 && poster.posted.isEmpty && notifier.lastNotified == nil)
        // An install from a notification that fails says nothing either.
        notifier.install = { "0.7.1" }
        try notifier.respond(.update)
        await notifier.installFailed("0.7.1")
        #expect(poster.posted.isEmpty)
        poster.state = .allowed
        #expect(await notifier.found(manifest, availability: .available, installable: true))
        #expect(poster.asked == 1 && poster.posted.map(\.version) == ["0.7.1"])
    }

    /// A check the user asked for shows the version on the About page: it counts as told.
    @Test func theUsersOwnCheckCountsAsTold() async throws {
        let fixture = try Fixture(config: "{}")
        defer { fixture.remove() }
        let poster = FakePoster()
        let notifier = fixture.notifier(poster)
        notifier.shown(try Self.manifest("0.7.1"), availability: .available)
        notifier.shown(try Self.manifest("0.7.0.1"), availability: .available)  // older: what was told stays
        notifier.shown(try Self.manifest("9.0"), availability: .needsNewerSystem)  // not offered: not told
        #expect(notifier.lastNotified == "0.7.1")
        #expect(!(await notifier.found(try Self.manifest("0.7.1"), availability: .available, installable: true)))
        #expect(await notifier.found(try Self.manifest("0.7.2"), availability: .available, installable: true))
    }

    /// The title names the version; the body is the release's summary in the interface language if the manifest has
    /// it (English and Chinese; Traditional Chinese reads the Chinese, as About shows it), else a line asking to update.
    @Test func theTextIsInTheInterfaceLanguage() async throws {
        let manifest = try Self.manifest("0.7.1")
        #expect(UpdateNotice.summary(of: manifest, language: "en") == "One-click updates.")
        #expect(UpdateNotice.summary(of: manifest, language: "zh-Hans") == "一键更新。")
        #expect(UpdateNotice.summary(of: manifest, language: "zh-Hant") == "一键更新。")
        #expect(UpdateNotice.summary(of: manifest, language: "ja") == nil)
        var bare = manifest
        bare.summary = ["en": " "]
        #expect(UpdateNotice.summary(of: bare, language: "en") == nil)
        UIText.$scopedLanguage.withValue("en") {
            #expect(UpdateNotice.available(manifest) == UpdateNotice(kind: .available, version: "0.7.1", title: "AllInOneIME 0.7.1 is available",
                                                                    body: "One-click updates."))
            #expect(UpdateNotice.available(bare).body == "Update now to get the latest fixes.")
            #expect(UpdateNotice.failed("0.7.1").title == "Couldn't update to 0.7.1")
        }
        UIText.$scopedLanguage.withValue("zh-Hans") {
            #expect(UpdateNotice.available(manifest).title == "AllInOneIME 0.7.1 可以更新了" && UpdateNotice.available(manifest).body == "一键更新。")
            #expect(UpdateNotice.available(bare).body == "现在更新，获得最新的修正。")
        }
    }
}
