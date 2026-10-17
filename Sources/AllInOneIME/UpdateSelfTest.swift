import AllInOneIMECore
import AppKit

extension SelfTest {
    /// The updater as the user sees it (nothing is checked, downloaded or installed): the About page's Updates
    /// card in each state, drawn offscreen (settings-about-update-*.png), and the input menu's item.
    static func testUpdates(_ controller: AllInOneIMEInputController, snapshotDirectory: URL) {
        section("updates (nothing checked, downloaded or installed)")
        let updates = UpdateController.shared
        let before = (updates.state, updates.lastChecked, updates.lastResult, updates.updatesInPlace)
        defer { (updates.state, updates.lastChecked, updates.lastResult, updates.updatesInPlace) = before }
        updates.updatesInPlace = true  // drawn as the installed copy shows it
        let pickedBefore = UIText.choice
        defer { UIText.choice = pickedBefore }
        UIText.choice = "en"
        let sample = UpdateManifest.sample(version: "9.9.0")
        updates.lastChecked = Date().addingTimeInterval(-3600)

        // The input menu (in the self-test's interface language, which it sets): "Check for Updates…" until a newer
        // version is known, then "Update to …".
        updates.state = .upToDate
        let titles = controller.menu()?.items.map(\.title) ?? []
        check(titles.last == tr("检查更新…", "Check for Updates…"), "the input menu ends with Check for Updates… (\(titles.suffix(2)))")
        updates.state = .available(sample)
        let offered = controller.menu()?.items.last?.title
        check(offered == tr("更新到 9.9.0…", "Update to 9.9.0…") && updates.available == sample,
              "…and offers the update once one is known (\(offered ?? "none"))")
        updates.state = .needsNewerSystem(sample)
        check(updates.available == nil && controller.menu()?.items.last?.title == tr("检查更新…", "Check for Updates…"),
              "an update for a newer macOS isn't offered")
        UIText.choice = "en"
        check(UpdateText.available("9.9.0") == "AllInOneIME 9.9.0 is available", "the panel's notice")
        UIText.choice = "zh"
        check(UpdateText.available("9.9.0") == "AllInOneIME 9.9.0 可以更新了"
              && UpdateText.describe(UpdateError.hashMismatch).hasPrefix("下载的文件"), "…in Chinese too")
        UIText.choice = "en"

        // Every state of the card renders (the images are looked at by hand).
        let model = SettingsModel(configURL: Config.defaultURL, persists: false)
        let states: [(String, UpdateController.State, UpdateResult?)] = [
            ("current", .upToDate, nil),
            ("checking", .checking, nil),
            ("available", .available(sample), nil),
            ("downloading", .downloading(sample, 0.42), nil),
            ("installing", .installing(sample), nil),
            ("failed", .failed(UpdateText.describe(UpdateError.hashMismatch), sample), nil),
            ("needs-macos", .needsNewerSystem(UpdateManifest.sample(version: "9.9.0", minimumSystem: "99.0")), nil),
            ("updated", .upToDate, UpdateResult(from: "0.6.2", to: AppVersion.string, ok: true)),
            ("rolled-back", .upToDate, UpdateResult(from: AppVersion.string, to: "9.9.0", ok: false, error: "it didn't start")),
        ]
        var rendered = 0
        for (name, state, result) in states {
            updates.state = state
            updates.lastResult = result
            let url = snapshotDirectory.appendingPathComponent("settings-about-update-\(name).png")
            try? FileManager.default.removeItem(at: url)
            SettingsImage.render(model, page: .about, to: url) { _ = pump(timeout: $0) { false } }
            if FileManager.default.fileExists(atPath: url.path) { rendered += 1 }
        }
        check(rendered == states.count, "the About page's Updates card renders in each state (\(rendered)/\(states.count))")
        check(Config.default.checkForUpdates, "checking for updates is on by default")
    }
}
