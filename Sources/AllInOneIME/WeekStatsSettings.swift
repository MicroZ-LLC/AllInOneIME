import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// This week's stats in the input method (`WeekStats`): the counts every text field adds to, the page's one preference,
/// and the picture copied or saved.
enum WeekStatsShared {
    /// The counts on this Mac (~/Library/Application Support/AllInOneIME/usage.json, `WeekStatsStore`). The self-test and
    /// the images use their own (`use`), never the user's.
    static var store: WeekStatsStore = WeekStatsStore()
    /// Settings → This Week's "Hide my command names in the image".
    static let preferences = WeekStatsPagePreferences()

    /// `store` in place of the user's for the rest of the run (the self-test, the images): nothing of theirs is read or
    /// counted; `icons` (the samples') in place of the commands there are.
    static func use(_ store: WeekStatsStore, icons: ((WeekStats.Snapshot.CommandCount) -> IconToken)? = nil) {
        self.store = store
        shownIcons = icons
    }

    private static var shownIcons: ((WeekStats.Snapshot.CommandCount) -> IconToken)?

    /// Each command's icon as the command list draws it, from the commands there are now (one gone since: its kind's).
    /// The extensions as last indexed: nothing is scanned for it.
    static func icons(_ config: Config = LiveConfig.current) -> (WeekStats.Snapshot.CommandCount) -> IconToken {
        if let shownIcons { return shownIcons }
        let index = LiveExtensions.current(config)
        let catalog = Command.catalog(config.customCommands, plugins: LivePlugins.current(),
                                      scripts: index.enabled(config.disabledExtensions),
                                      snippets: index.enabledSnippets(config.disabledExtensions))
        let byName = Dictionary(catalog.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        return { command in byName[command.id].map(IconToken.command) ?? WeekStatsCard.builtInIcon(command) }
    }

    /// The week's picture on the clipboard, in the appearance the Mac is in, the user's names hidden if they asked
    /// (`@stats`'s ⌘C, the page's Copy Image). Whether it is there.
    @MainActor @discardableResult
    static func copyImage(_ week: WeekStats.Week = .current) -> Bool {
        do {
            try WeekStatsShareImage.copy(week: store.stats.snapshot(for: week), language: UIText.language,
                                         hideOwnCommandNames: preferences.hideOwnCommandNames,
                                         appearance: .current, icon: icons())
            return true
        } catch {
            NSLog("AllInOneIME: the week's picture couldn't be made: \(error)")
            return false
        }
    }

    /// `@stats`'s ⌘C: `copyImage`, the picture made off the main thread once the key is answered, then put on the
    /// clipboard there.
    @MainActor
    static func copyImageSoon() {
        let (week, language, hide) = (store.stats.snapshot(for: .current), UIText.language, preferences.hideOwnCommandNames)
        let (appearance, icon) = (WeekStatsShareImage.Appearance.current, icons())
        DispatchQueue.global(qos: .userInitiated).async {
            let png = try? WeekStatsShareImage.render(week: week, language: language, hideOwnCommandNames: hide,
                                                      appearance: appearance, icon: icon)
            DispatchQueue.main.async {
                guard let png else { return NSLog("AllInOneIME: the week's picture couldn't be made") }
                WeekStatsShareImage.put(png)
            }
        }
    }

    /// Save as Image…: the picture in a PNG where the user says (a save panel, over `window`).
    @MainActor
    static func saveImage(_ week: WeekStats.Week, over window: NSWindow?) {
        let snapshot = store.stats.snapshot(for: week)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        let monday = snapshot.days.first.map { WeekStatsSamples.day($0.date, calendar: snapshot.calendar) } ?? ""
        panel.nameFieldStringValue = "AllInOneIME \(WeekStatsText.pageTitle(language: UIText.language)) \(monday).png"
        let write: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let png = try WeekStatsShareImage.render(week: snapshot, language: UIText.language,
                                                         hideOwnCommandNames: preferences.hideOwnCommandNames,
                                                         appearance: .current, icon: icons())
                try png.write(to: url, options: .atomic)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: write) } else { write(panel.runModal()) }
    }
}

/// Settings → This Week (本周统计), as the owner's design has it: the title with This Week / Last Week, the card
/// (`WeekStatsCard`, as the picture has it but for the page), "Hide my command names in the image" with what it does,
/// Save as Image… and Copy Image, and where the stats are kept.
struct WeekStatsPage: View {
    @StateObject private var model = WeekStatsPageModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Text(model.text.pageTitle).font(.system(size: 20, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 12)
                    Picker("", selection: $model.week) {
                        Text(model.text.tabTitles[0]).tag(WeekStats.Week.current)
                        Text(model.text.tabTitles[1]).tag(WeekStats.Week.previous)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .accessibilityLabel(model.text.pageTitle)
                }
                WeekStatsCardView(card: model.card)
                HStack(alignment: .center, spacing: 16) {
                    Toggle(isOn: $model.hideOwnCommandNames) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(model.text.hideNamesLabel)
                            Text(model.text.hideNamesNote).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    Spacer(minLength: 12)
                    Button(model.text.saveImageLabel) { model.save() }
                        .controlSize(.large)
                    Button(model.copied ? model.text.imageCopied : model.text.copyImageLabel) { model.copy() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                Text(model.text.privacyNote).font(.caption).foregroundStyle(.secondary)
            }
            .padding(EdgeInsets(top: 20, leading: 24, bottom: 24, trailing: 24))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear { model.refresh() }
        // Counted meanwhile (typing elsewhere, Settings left open): read again now and then, and when it comes back.
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in model.refresh() }
    }
}

/// What Settings → This Week shows: the week picked, its counts as last read, the preference.
@MainActor
final class WeekStatsPageModel: ObservableObject {
    @Published var week: WeekStats.Week = .current {
        didSet { refresh() }
    }
    @Published private(set) var snapshot = WeekStatsShared.store.stats.snapshot(for: .current)
    @Published var hideOwnCommandNames = WeekStatsShared.preferences.hideOwnCommandNames {
        didSet { WeekStatsShared.preferences.hideOwnCommandNames = hideOwnCommandNames }
    }
    /// Copy Image says it copied, for a moment.
    @Published private(set) var copied = false
    private var icons = WeekStatsShared.icons()

    var text: WeekStatsText { WeekStatsText(snapshot, language: UIText.language) }
    var card: WeekStatsCard { WeekStatsCard(week: snapshot, language: UIText.language, style: .page, icon: icons) }

    func refresh() {
        let new = WeekStatsShared.store.stats.snapshot(for: week)
        if new != snapshot { snapshot = new }
    }

    func copy() {
        icons = WeekStatsShared.icons()
        guard WeekStatsShared.copyImage(week) else { return }
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.copied = false }
    }

    func save() {
        icons = WeekStatsShared.icons()
        WeekStatsShared.saveImage(week, over: NSApp.keyWindow)
    }
}

/// The card on the page: `WeekStatsCard` drawn in the window's appearance, as tall as it needs for the page's width.
struct WeekStatsCardView: NSViewRepresentable {
    let card: WeekStatsCard

    func makeNSView(context: Context) -> WeekStatsCardNSView { WeekStatsCardNSView() }

    func updateNSView(_ view: WeekStatsCardNSView, context: Context) {
        view.card = card
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WeekStatsCardNSView, context: Context) -> CGSize? {
        let width = proposal.width ?? 600
        return CGSize(width: width, height: card.height(forWidth: width))
    }
}

final class WeekStatsCardNSView: NSView {
    var card: WeekStatsCard? {
        didSet {
            needsDisplay = true
            setAccessibilityLabel(card.map { $0.text.spoken() })
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: NSColor.systemColorsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    @objc private func redraw() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        card?.draw(in: bounds)
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

    /// "2026-11-09".
    static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
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
        if firstWeek {
            // Counting since Thursday: 7 commands on 2 days in 3 apps, 4 of them with AI, 3 pastes.
            run("improve", .builtIn, ai: true, times: 4, on: 3, in: 0)
            run("sig", .own, ai: false, times: 2, on: 4, in: 2)
            run("open", .builtIn, ai: false, times: 1, on: 4, in: 4)
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
        clock.now = friday
        for _ in 0..<47 { stats.recordClipboardPaste() }
        return store
    }

    private final class SampleClock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }
}
