import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// This week's stats in the input method (`WeekStats`): the counts every text field adds to, the page's one preference,
/// and the picture copied or saved.
enum WeekStatsShared {
    /// The counts on this Mac (~/Library/Application Support/AllInOneIME/usage.json, `WeekStatsStore`, its salt in the
    /// keychain). The self-test and the images use their own (`use`), never the user's.
    static var store: WeekStatsStore = WeekStatsStore()
    /// Settings → This Week's "Hide my command names in the image".
    static let preferences = WeekStatsPagePreferences()

    /// `store` in place of the user's for the rest of the run (the self-test, the images): nothing of theirs is read or
    /// counted; `icons` (the samples') in place of the commands there are.
    static func use(_ store: WeekStatsStore, icons: ((WeekStats.Snapshot.CommandCount) -> IconToken)? = nil) {
        self.store = store
        shownIcons = icons
        isUsers = false
    }

    private static var shownIcons: ((WeekStats.Snapshot.CommandCount) -> IconToken)?
    /// Whether `store` is the user's (not one `use` gave).
    private static var isUsers = true

    /// The user's own commands deleted or renamed since they ran keep no name in the stats: their runs are kept among the
    /// earlier commands (`WeekStats.keepCommands`), by the config as it is (nothing while it doesn't parse). At launch,
    /// when the config changes (`LiveConfig.parsedAnew`) and before the week is shown or copied; never in a store `use`
    /// gave.
    static func keepOwnCommands() {
        guard isUsers, let config = LiveConfig.currentIfValid else { return }
        store.stats.keepCommands(Set(config.customCommands.map(\.name)), from: .own)
    }

    /// `week` as it is now, shown or copied (`keepOwnCommands` first).
    static func snapshot(_ week: WeekStats.Week) -> WeekStats.Snapshot {
        keepOwnCommands()
        return store.stats.snapshot(for: week)
    }

    /// A command by its name and where it comes from: the stats count the same name from two sources apart.
    private struct CommandName: Hashable {
        var id: String
        var source: WeekStats.CommandSource
    }

    /// Each command's icon as the command list draws it, from the commands there are now (one gone since, or now from
    /// elsewhere: its kind's). The extensions as last indexed: nothing is scanned for it.
    static func icons(_ config: Config = LiveConfig.current) -> (WeekStats.Snapshot.CommandCount) -> IconToken {
        if let shownIcons { return shownIcons }
        let index = LiveExtensions.current(config)
        let catalog = Command.catalog(config.customCommands, plugins: LivePlugins.current(),
                                      scripts: index.enabled(config.disabledExtensions),
                                      snippets: index.enabledSnippets(config.disabledExtensions))
        let byName = Dictionary(catalog.map { (CommandName(id: $0.name, source: WeekStats.CommandSource($0)), $0) },
                                uniquingKeysWith: { first, _ in first })
        return { command in
            byName[CommandName(id: command.id, source: command.source)].map(IconToken.command) ?? WeekStatsCard.builtInIcon(command)
        }
    }

    /// The week's picture on the clipboard, in the appearance the Mac is in, the user's names hidden if they asked
    /// (`@stats`'s ⌘C, the page's Copy Image). Whether it is there.
    @MainActor @discardableResult
    static func copyImage(_ week: WeekStats.Week = .current) -> Bool {
        do {
            try WeekStatsShareImage.copy(week: snapshot(week), language: UIText.language,
                                         hideOwnCommandNames: preferences.hideOwnCommandNames,
                                         appearance: .current, icon: icons())
            return true
        } catch {
            NSLog("AllInOneIME: the week's picture couldn't be made: \(error)")
            return false
        }
    }

    /// `@stats`'s ⌘C: `copyImage`, the picture made off the main thread once the key is answered, then put on the
    /// clipboard there; `done` told there whether it is.
    @MainActor
    static func copyImageSoon(then done: @escaping @MainActor (Bool) -> Void) {
        let (week, language, hide) = (snapshot(.current), UIText.language, preferences.hideOwnCommandNames)
        let (appearance, icon) = (WeekStatsShareImage.Appearance.current, icons())
        DispatchQueue.global(qos: .userInitiated).async {
            let png = try? WeekStatsShareImage.render(week: week, language: language, hideOwnCommandNames: hide,
                                                      appearance: appearance, icon: icon)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let png else {
                        NSLog("AllInOneIME: the week's picture couldn't be made")
                        return done(false)
                    }
                    let copied = WeekStatsShareImage.put(png)
                    if !copied { NSLog("AllInOneIME: the week's picture couldn't be put on the clipboard") }
                    done(copied)
                }
            }
        }
    }

    /// Save as Image…: the picture in a PNG where the user says (a save panel, over `window`).
    @MainActor
    static func saveImage(_ week: WeekStats.Week, over window: NSWindow?) {
        let snapshot = snapshot(week)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        let monday = snapshot.days.first.map { WeekStats.key($0.date, calendar: snapshot.calendar) } ?? ""
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
                    Button(model.copyLabel) { model.copy() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.text.privacyNote)
                    Text(model.text.keptNote)
                }
                .font(.caption).foregroundStyle(.secondary)
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
    @Published private(set) var snapshot = WeekStatsShared.snapshot(.current)
    @Published var hideOwnCommandNames = WeekStatsShared.preferences.hideOwnCommandNames {
        didSet { WeekStatsShared.preferences.hideOwnCommandNames = hideOwnCommandNames }
    }
    /// Copy Image says it copied (or couldn't), for a moment.
    @Published private(set) var copied: Bool?
    private var icons = WeekStatsShared.icons()

    var text: WeekStatsText { WeekStatsText(snapshot, language: UIText.language) }
    /// Copy Image's label, "Image copied" (or "Couldn't copy the image") for a moment after a click.
    var copyLabel: String { copied.map { $0 ? text.imageCopied : text.imageNotCopied } ?? text.copyImageLabel }
    var card: WeekStatsCard { WeekStatsCard(week: snapshot, language: UIText.language, style: .page, icon: icons) }

    func refresh() {
        let new = WeekStatsShared.snapshot(week)
        if new != snapshot { snapshot = new }
    }

    func copy() {
        icons = WeekStatsShared.icons()
        copied = WeekStatsShared.copyImage(week)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.copied = nil }
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
