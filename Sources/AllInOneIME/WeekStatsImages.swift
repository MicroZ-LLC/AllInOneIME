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

/// A made-up week for the images (`--settings-image`, `--week-stats-images`) and the self-test: the owner's design's numbers
/// (132 commands, 18% more than the same days last week, 5 days, 8 apps, @sig, @improve, @bm, @translate, @addr …), or its
/// first week (counting since Thursday), on Friday 13 November 2026. In a folder of its own, never the user's file.
enum WeekStatsSamples {
    /// Friday 13 November 2026, at noon, in this Mac's time zone.
    static var friday: Date {
        WeekStats.defaultCalendar().date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 12)) ?? Date()
    }

    /// The sample commands' icons, as the command list would draw them: @sig and @addr snippets of the user's, @todo and
    /// @mail AI instructions, @bm a bookmarks plugin; the built-in ones their own.
    static func icon(_ command: WeekStats.Snapshot.CommandCount) -> IconToken {
        switch command.id {
        case "sig", "addr": return IconToken.custom(CustomCommand(name: command.id, type: .snippet, text: "-"))
        case "todo", "mail": return IconToken.custom(CustomCommand(name: command.id, type: .prompt, prompt: "-"))
        case "bm": return IconToken(.symbol("bookmark.fill", fallback: .plugin), color: .blue)
        default: return WeekStatsCard.builtInIcon(command)
        }
    }

    /// A store in `folder` with the design's week (`firstWeek`: its first week), its clock stopped at `friday`.
    static func store(in folder: URL, firstWeek: Bool = false) -> WeekStatsStore {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let clock = SampleClock(friday)
        let store = WeekStatsStore(applicationSupportDirectory: folder, now: { clock.now })
        let stats = store.stats
        stats.clearHistory()
        let apps = ["com.apple.mail", "com.apple.notes", "com.tinyspeck.slackmacgap", "com.tencent.xinwechat",
                    "com.apple.safari", "com.microsoft.vscode", "com.apple.terminal", "notion.id"]
        var app = 0
        // Each run in the next of the apps (`in`: that one).
        func run(_ id: String, _ source: WeekStats.CommandSource, ai: Bool, times: Int, on day: Int, in fixed: Int? = nil) {
            clock.now = WeekStats.defaultCalendar().date(byAdding: .day, value: day - 4, to: friday) ?? friday
            for _ in 0..<times {
                stats.recordCommand(id: id, source: source, bundleID: apps[(fixed ?? app) % apps.count], usedAI: ai)
                app += 1
            }
        }
        // The characters typed on each of `counts`' days, Monday (0) on, of the week `week` weeks from this one.
        func typed(_ counts: [Int], week: Int = 0) {
            for (day, count) in counts.enumerated() where count > 0 {
                clock.now = WeekStats.defaultCalendar().date(byAdding: .day, value: 7 * week + day - 4, to: friday) ?? friday
                stats.recordTypedCharacters(count)
            }
        }
        if firstWeek {
            // Counting since Thursday: 7 commands on 2 days in 3 apps, 4 of them with AI, 3 pastes, 2,380 characters.
            run("improve", .builtIn, ai: true, times: 4, on: 3, in: 0)
            run("sig", .own, ai: false, times: 2, on: 4, in: 2)
            run("open", .builtIn, ai: false, times: 1, on: 4, in: 4)
            typed([0, 0, 0, 1_460, 920])
            clock.now = friday
            for _ in 0..<3 { stats.recordClipboardPaste() }
            return store
        }
        // Last week, Monday to Friday: 112 (and the weekend).
        for (day, count) in [25, 24, 20, 23, 20, 6, 3].enumerated() { run("improve", .builtIn, ai: true, times: count, on: day - 7) }
        // This week: Monday 31, Tuesday 27, Wednesday 22, Thursday 34, Friday (today) 18.
        let week: [(String, WeekStats.CommandSource, Bool, [Int])] = [
            ("sig", .own, false, [7, 6, 5, 7, 4]),
            ("improve", .builtIn, true, [5, 5, 4, 6, 3]),
            ("bm", .plugin, false, [4, 4, 3, 5, 3]),
            ("translate", .builtIn, true, [4, 3, 2, 4, 2]),
            ("addr", .own, false, [3, 3, 2, 4, 2]),
            ("todo", .own, false, [3, 2, 2, 2, 1]),
            ("mail", .own, true, [2, 2, 1, 2, 1]),
            ("question", .builtIn, true, [2, 1, 2, 2, 1]),
            ("open", .builtIn, false, [1, 1, 1, 2, 1]),
        ]
        for (id, source, ai, days) in week {
            for (day, count) in days.enumerated() { run(id, source, ai: ai, times: count, on: day) }
        }
        // Characters typed: 11,870 last week, 12,340 this week so far.
        typed([2_610, 2_480, 2_150, 2_390, 1_840, 300, 100], week: -1)
        typed([2_840, 2_510, 1_960, 3_120, 1_910])
        clock.now = friday
        for _ in 0..<47 { stats.recordClipboardPaste() }
        return store
    }

    private final class SampleClock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }
}
