import AllInOneIMECore
import AllInOneIMEMac
import AppKit

/// `AllInOneIME --week-stats-images OUT-DIR`: this week's stats as the owner's design shows them, drawn offscreen with
/// the design's sample week (`WeekStatsSamples`, never the user's counts), in Chinese and English (`-en`), light and dark
/// (`-dark`): Settings → This Week (`week-settings`, and its first week, `week-settings-first`), the picture copied
/// with the user's names hidden (`week-share`, and the first week's, `week-share-first`), the menu bar panel with its
/// row on top (`week-menubar`, its stand-ins' notes, reminders and tasks) and `@stats` in the @ list (`week-atstats`).
/// The settings window reads the config file as it is and saves nothing.
@MainActor
enum WeekStatsImages {
    static func run(output: URL) -> Never {
        NSApplication.shared.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let samples = FileManager.default.temporaryDirectory.appendingPathComponent("allinoneime-week-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: samples) }
        let full = WeekStatsSamples.store(in: samples.appendingPathComponent("full"))
        let first = WeekStatsSamples.store(in: samples.appendingPathComponent("first"), firstWeek: true)
        SettingsModel.looksUpKeys = false
        let language = UIText.choice
        defer { UIText.choice = language }
        for chinese in [true, false] {
            UIText.choice = chinese ? "zh" : "en"
            let suffix = chinese ? "" : "-en"
            for (appearance, dark) in [(NSAppearance.Name.aqua, ""), (.darkAqua, "-dark")] {
                let name = suffix + dark
                WeekStatsShared.use(full, icons: WeekStatsSamples.icon)
                settings("week-settings" + name, output, appearance)
                share("week-share" + name, full, output, appearance)
                menuBar("week-menubar" + name, full, output, appearance, chinese: chinese)
                atStats("week-atstats" + name, full, output, appearance)
                WeekStatsShared.use(first, icons: WeekStatsSamples.icon)
                settings("week-settings-first" + name, output, appearance)
                share("week-share-first" + name, first, output, appearance, hideNames: false)
            }
        }
        exit(0)
    }

    private static func settle(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    /// Settings → This Week, as tall as its content.
    private static func settings(_ name: String, _ output: URL, _ appearance: NSAppearance.Name) {
        let model = SettingsModel(configURL: Config.defaultURL, persists: false)
        SettingsImage.render(model, page: .week, to: output.appendingPathComponent(name + ".png"), appearance: appearance,
                             settle: settle)
    }

    /// The picture Copy Image puts on the clipboard (`WeekStatsShareImage`), the user's own names hidden.
    private static func share(_ name: String, _ store: WeekStatsStore, _ output: URL, _ appearance: NSAppearance.Name,
                              hideNames: Bool = true) {
        let url = output.appendingPathComponent(name + ".png")
        do {
            let png = try WeekStatsShareImage.render(week: store.stats.snapshot(for: .current), language: UIText.language,
                                                     hideOwnCommandNames: hideNames, appearance: appearance == .darkAqua ? .dark : .light,
                                                     icon: WeekStatsSamples.icon)
            try png.write(to: url)
            print("  \(url.path)")
        } catch {
            print("  \(name): \(error)")
        }
    }

    /// The menu bar panel dropped down, its row of the week on top, with the self-test's stand-ins for the rest.
    private static func menuBar(_ name: String, _ store: WeekStatsStore, _ output: URL, _ appearance: NSAppearance.Name,
                                chinese: Bool) {
        let stand = PanelStandIns()
        stand.sample(chinese: chinese)
        var sources = stand.sources
        sources.weekStats = { WeekStatsMenuBar.row(stats: store.stats, language: UIText.language) }
        let panel = FloatingPanel(sources: sources)
        panel.prepareWindow = { window in
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.appearance = NSAppearance(named: appearance)
        }
        panel.checksOcclusion = false
        let screen = NSScreen.screens.first?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 875)
        panel.toggleDropDown(below: CGRect(x: screen.maxX - 200, y: screen.maxY, width: 22, height: 24))
        defer { panel.closeDropDown() }
        _ = SelfTest.pump(timeout: 3) {
            guard case let .list(items) = panel.reminders, !items.isEmpty, case let .list(rows) = panel.tasks else { return false }
            return panel.weekStats != nil && rows.allSatisfy { $0.reply != nil }
        }
        guard let window = panel.window, let view = window.contentView else { return print("  \(name): no window") }
        FloatingPanelView.glass = false  // nothing behind an offscreen rendering to blur
        panel.objectWillChange.send()
        defer {
            FloatingPanelView.glass = true
            panel.objectWillChange.send()
        }
        _ = SelfTest.pump(timeout: 0.5) { false }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = output.appendingPathComponent(name + ".png")
        if let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: url)) != nil { print("  \(url.path)") }
    }

    /// "@stats" typed: the one @ list as the core's presenter makes it, drawn by the candidate panel.
    private static func atStats(_ name: String, _ store: WeekStatsStore, _ output: URL, _ appearance: NSAppearance.Name) {
        let composer = Composer(engine: LatinEngine())  // as a field without the Chinese pack types: Latin letters
        composer.messages.language = UIText.language
        composer.commands = Command.catalog([])
        composer.setInputMode(.english)
        for character in "@stats" { _ = composer.handleKeyDown(KeyEvent(keyCode: 0, characters: String(character))) }
        let presenter = PanelPresenter(config: .default, language: UIText.language,
                                       weekStats: { store.stats.snapshot(for: .current) })
        CandidatePanel.shared.appearance = NSAppearance(named: appearance)
        let model = presenter.model(for: composer)
        CandidatePanel.shared.show(model, anchor: NSRect(x: 240, y: 640, width: 2, height: 20))
        settle(0.3)
        SelfTest.snapshot(name, in: output, appearance: appearance)
        CandidatePanel.shared.hide()
        CandidatePanel.shared.appearance = nil
    }
}
