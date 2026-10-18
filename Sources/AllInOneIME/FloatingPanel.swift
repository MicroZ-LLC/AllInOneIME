import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import Carbon
import EventKit
import SwiftUI

extension Notification.Name {
    /// The interface language changed (`UIText.choice`): the menu bar panel redraws in it. Main thread.
    static let allInOneIMEInterfaceLanguageChanged = Notification.Name("AllInOneIMEInterfaceLanguageChanged")
}

/// What the panel remembers between launches (its frame, whether it's collapsed, the notes @note
/// saved): UserDefaults; memory in the self-test, which leaves the user's alone.
protocol PanelDefaults: AnyObject {
    func data(forKey key: String) -> Data?
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: PanelDefaults {}

final class MemoryDefaults: PanelDefaults {
    private(set) var values: [String: Any] = [:]
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func string(forKey key: String) -> String? { values[key] as? String }
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

/// The notes @note saved (`SavedNotes`), as JSON under `savedNotes`.
enum SavedNotesStore {
    static let key = "savedNotes"

    static func load(_ defaults: PanelDefaults) -> SavedNotes {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(SavedNotes.self, from: $0) } ?? SavedNotes()
    }

    static func save(_ notes: SavedNotes, to defaults: PanelDefaults) {
        if let data = try? JSONEncoder().encode(notes) { defaults.set(data, forKey: key) }
    }
}

/// Whether the panel may read the reminders: macOS's answer, never a question to the user.
enum ReminderAccess: Equatable {
    case allowed, notDetermined, denied

    /// As macOS has it now. EventKit: off the main thread.
    static var current: ReminderAccess {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return .allowed
        case .notDetermined: return .notDetermined
        default: return .denied  // denied, restricted, or write-only (which only events have)
        }
    }

    /// System Settings → Privacy & Security → Reminders.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
}

/// Whether this process may send Notes Apple events without asking the user (allowed before, in
/// System Settings → Privacy & Security → Automation). Asked of the system without a prompt; Notes
/// must be running. Off the main thread: it waits for the system's answer.
enum NotesAccess {
    static func allowedWithoutAsking() -> Bool {
        let notes = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Notes")
        return withExtendedLifetime(notes) {
            guard let target = notes.aeDesc else { return false }
            return AEDeterminePermissionToAutomateTarget(target, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
                == OSStatus(noErr)
        }
    }
}

/// What Notes says of the AllInOneIME folder, for the panel (`DashboardSources.listNotes`).
enum NotesListing: Equatable {
    /// Asking would need the user's permission first (the panel never asks on its own).
    case notAllowed
    /// Notes has no such folder in its default account (the user switched the default account, or
    /// renamed the folder): that says nothing of the notes saved.
    case noFolder
    /// The folder's notes changed last, newest first (none: the folder is empty).
    case folder([NotesBridge.Note])

    /// What `NotesBridge.recent` listed: nil when there's no such folder, which says nothing of the notes
    /// saved (none is dropped when the user switched Notes' default account); an empty list is an empty
    /// folder, so the saved notes it no longer has are dropped.
    init(recent notes: [NotesBridge.Note]?) {
        self = notes.map { .folder($0) } ?? .noFolder
    }
}

/// Where the panel's rows come from and what its clicks do. `live`: Notes, Reminders and Claude Code;
/// the self-test passes stand-ins, so nothing real is read, changed or opened. Everything is called
/// on the main thread; what would block it (Apple events, EventKit, processes, files) runs elsewhere.
struct DashboardSources {
    /// Whether Notes runs now: only then is it asked about the notes (an Apple event would launch it).
    var notesRunning: @MainActor () -> Bool
    /// The notes in the AllInOneIME folder (`NotesBridge.recent`), unless that would need the user's
    /// permission first (the panel never asks on its own) or there's no such folder.
    var listNotes: @MainActor (_ limit: Int) async throws -> NotesListing
    var showNote: @MainActor (_ id: String) async throws -> Void
    var reminderAccess: @MainActor () async -> ReminderAccess
    /// The reminders not done (`RemindersBridge.incomplete`), the soonest first. Asks the user when
    /// access isn't decided yet: only called then from the panel's button.
    var reminders: @MainActor (_ now: Date) async throws -> [RemindersBridge.Reminder]
    var completeReminder: @MainActor (_ id: String) async throws -> Void
    var openReminders: @MainActor () -> Void
    var openReminderSettings: @MainActor () -> Void
    /// The background sessions `claude agents --json --all` lists; nil when Claude Code isn't installed.
    var listAgents: @MainActor () async throws -> [AgentSession]?
    /// The last replies of the sessions whose transcript is new or changed since `known`, read from
    /// the transcripts' ends (`AgentReplyCache.readChanged`): session id → what was read.
    var lastReplies: @MainActor (_ sessions: [AgentSession], _ known: [String: AgentReplyCache.Read]) async
        -> [String: AgentReplyCache.Read]
    /// Whether AgentMonitor looks at the tasks every few seconds now (its looks reach the panel).
    var monitorWatching: @MainActor () -> Bool
    /// The prompt @agent started a task with (short id), for one Claude Code hasn't named yet.
    var prompt: @MainActor (_ id: String) -> String?
    var openAgent: @MainActor (_ id: String) -> Void
    var defaults: PanelDefaults
    var now: @MainActor () -> Date

    @MainActor static var live: DashboardSources {
        DashboardSources(
            notesRunning: { !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes").isEmpty },
            listNotes: { limit in
                guard await Task.detached(priority: .utility, operation: { NotesAccess.allowedWithoutAsking() }).value else {
                    return .notAllowed
                }
                return NotesListing(recent: try await NotesBridge.recent(limit: limit))
            },
            showNote: { try await NotesBridge.show(id: $0) },
            reminderAccess: { await Task.detached(priority: .utility) { ReminderAccess.current }.value },
            reminders: { try await RemindersBridge.incomplete(limit: FloatingPanel.reminderReadLimit, now: $0) },
            completeReminder: { try await RemindersBridge.complete(id: $0) },
            openReminders: { RemindersBridge.openApp() },
            openReminderSettings: { NSWorkspace.shared.open(ReminderAccess.settingsURL) },
            listAgents: {
                let claude = AgentMonitor.shared.claude
                return try await Task.detached(priority: .utility) { () -> [AgentSession]? in
                    // Where Terminal finds it, else on the login shell's PATH (read here, off the main thread).
                    guard TerminalLauncher.claudePath != nil
                            || CommandRunner.resolve("claude", path: ShellEnvironment.current["PATH"]) != nil else { return nil }
                    let output = try await AgentMonitor.run(claude, ClaudeAgents.listArguments)
                    return ClaudeAgents.sessions(from: Data(output.utf8))
                }.value
            },
            lastReplies: { sessions, known in
                await Task.detached(priority: .utility) { AgentReplyCache.readChanged(sessions, known: known) }.value
            },
            monitorWatching: { AgentMonitor.shared.isWatching },
            prompt: { AgentMonitor.shared.prompt(for: $0) },
            openAgent: { AgentMonitor.shared.open($0) },
            defaults: UserDefaults.standard,
            now: { Date() })
    }
}

/// The panel dropped down from the menu bar icon (`MenuBarIcon`): what AllInOneIME started, the notes
/// saved with @note, the reminders added with @reminder, @agent's background tasks. It never takes
/// focus from the app being typed in (but for its tasks' search field), and closes on a click elsewhere.
///
/// The notes @note saves are recorded from launch, shown or not (`recordSavedNotes`).
/// While it's shown it listens for @reminder (AppEvents), for EventKit's changes and for AgentMonitor's
/// looks at the tasks and the tasks @agent starts, and reads the reminders again every 60 s. It
/// asks Claude Code itself when it's opened or refreshed and when @agent starts a task, and every
/// 15 s only while it's expanded, a task it lists isn't done and AgentMonitor isn't looking anyway.
/// Notes is asked (for edited titles and deleted notes) only when it's running already. Off,
/// nothing else of it runs: no timers, no other observers, no window.
@MainActor
final class FloatingPanel: ObservableObject {
    static let shared = FloatingPanel(sources: .live)

    static let width: CGFloat = 300
    static let headerHeight: CGFloat = 42
    static let maxHeight: CGFloat = 420
    static let notesShown = 5
    static let remindersShown = 8
    /// Read in full for the header's count (EventKit reads the whole list anyway); 8 are shown.
    static let reminderReadLimit = 100
    /// Asked of Notes when it runs (the script reads the whole folder anyway).
    static let noteListLimit = 200


    enum RemindersState: Equatable {
        case loading
        /// macOS hasn't asked the user yet: a button asks.
        case notDetermined
        /// Not allowed: a button opens System Settings.
        case denied
        /// Not done, the soonest first (all of them, up to `reminderReadLimit`; the first 8 are shown).
        case list([RemindersBridge.Reminder])
        case failed(String)
    }

    enum TasksState: Equatable {
        case loading
        case notInstalled
        case list([AgentTaskRow])
        case failed(String)
    }

    let sources: DashboardSources
    /// How often the reminders are read and Claude Code is asked (the self-test makes them shorter).
    var reminderInterval: TimeInterval = 60
    var agentInterval: TimeInterval = 15
    /// Called with the window once it's made (the self-test makes it invisible and click-through).
    var prepareWindow: (NSPanel) -> Void = { _ in }
    /// Looks are skipped while the window can't be seen (screen locked, display asleep). The
    /// self-test's invisible window never can, so it turns this off.
    var checksOcclusion = true

    /// Shown under the menu bar icon; it closes on a click elsewhere.
    @Published private(set) var droppedDown = false

    /// What keeps its lists up to date.
    var isShowing: Bool { droppedDown }
    @Published private(set) var notes: [SavedNotes.Note] = []
    @Published private(set) var reminders: RemindersState = .loading
    /// Reminders being ticked off (their box is checked until they're gone from the list).
    @Published private(set) var completing: Set<String> = []
    @Published private(set) var tasks: TasksState = .loading
    /// The script extensions running in the background, and those done lately (`ScriptTasks.background`).
    @Published private(set) var scriptRuns: [ScriptTasks.Run] = []
    /// What's typed in the tasks' search field (shown once there are more than `AgentTaskList.shown`).
    @Published var taskQuery = ""
    /// The row swiped to the left (`swipeOffset`: how far; its 「移除」 button shows in the gap).
    @Published private(set) var swipedRow: PanelRow?
    @Published private(set) var swipeOffset: CGFloat = 0
    /// What went wrong with a click, for a few seconds.
    @Published private(set) var message: String?
    /// The time the rows are shown for ("10 分钟前", "明天 15:00").
    @Published private(set) var now: Date
    /// The interface language it was drawn in: it redraws when that changes.
    @Published private(set) var language = UIText.language
    /// The lists' height, measured by the view: the window is as tall as they need, up to `maxHeight`.
    @Published var listHeight: CGFloat = 0 {
        didSet { if listHeight != oldValue { resize() } }
    }

    private(set) var window: DashboardWindow?
    private var observers: [NSObjectProtocol] = []
    /// Records the notes @note saves, on or off (`recordSavedNotes`).
    private var noteRecorder: NSObjectProtocol?
    private var reminderTimer: Timer?
    private var agentTimer: Timer?
    private var changeTimer: Timer?
    private var messageTimer: Timer?
    /// Counts the times it was turned on: what an earlier time started is dropped when it arrives.
    private var generation = 0
    private var readingReminders = false, readRemindersAgain = false
    private var askingAgents = false, readingReplies = false, readRepliesAgain = false, askingNotes = false
    /// What the last look at the tasks listed (AgentMonitor's or its own).
    private var sessions: [AgentSession]?
    private var replies = AgentReplyCache()
    /// The window was hidden from view (looks skipped meanwhile): caught up once it's seen again.
    private var unseen = false
    /// Two-finger swipes on the trackpad, over a row (`swallows`).
    private var scrollMonitor: Any?
    private var hoveredRow: PanelRow?
    private var tracking: Swipe?
    /// A row was swiped and let go: the scroll's momentum after it moves nothing.
    private var swallowingMomentum = false

    init(sources: DashboardSources) {
        self.sources = sources
        now = sources.now()
    }

    // MARK: - On and off

    /// At launch (runServer), before `start`: from now on the notes @note saves are recorded whether
    /// the panel is on or not. It's off by default, and lists them once it's turned on.
    func recordSavedNotes() {
        guard noteRecorder == nil else { return }
        let center = NotificationCenter.default
        noteRecorder = center.addObserver(forName: .allInOneIMENoteSaved, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.noteSaved(note.userInfo) }
        }
    }

    /// No longer records them (the self-test's panel, when its test is over).
    func stopRecordingSavedNotes() {
        noteRecorder.map(NotificationCenter.default.removeObserver)
        noteRecorder = nil
    }

    /// Whether anything of it still runs but the record of saved notes (the self-test checks that closed
    /// means closed).
    var isIdle: Bool {
        observers.isEmpty && reminderTimer == nil && agentTimer == nil && changeTimer == nil && messageTimer == nil
            && window == nil && outsideClicks.isEmpty && scrollMonitor == nil
    }

    // MARK: - Dropped down from the menu bar

    private var outsideClicks: [Any] = []

    /// The menu bar icon was clicked: drops the panel down under it, or closes it when it's down.
    func toggleDropDown(below anchor: CGRect) {
        if droppedDown { closeDropDown() } else { show(below: anchor) }
    }

    /// Shown right under `anchor` (the icon's frame on the screen), until a click elsewhere.
    func show(below anchor: CGRect) {
        guard !droppedDown else { return }
        droppedDown = true
        generation += 1
        open(below: anchor)
        // A click anywhere but in the panel closes it, like a menu; the icon's own click toggles it.
        let close: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.droppedDown, event.window !== self.window, !MenuBarIcon.shared.owns(event) else { return }
                self.closeDropDown()
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: close) {
            outsideClicks.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { close($0); return $0 }) {
            outsideClicks.append(local)
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.swallows(event) == true } ? nil : event
        }
        log.notice("panel dropped down from the menu bar")
    }

    /// Closed: nothing of it runs any more but the record of saved notes.
    func closeDropDown() {
        guard droppedDown else { return }
        outsideClicks.forEach(NSEvent.removeMonitor)
        outsideClicks = []
        scrollMonitor.map(NSEvent.removeMonitor)
        scrollMonitor = nil
        droppedDown = false
        generation += 1
        shut()
    }

    private func open(below anchor: CGRect) {
        language = UIText.language
        now = sources.now()
        notes = SavedNotesStore.load(sources.defaults).newest(Self.notesShown)
        scriptRuns = ScriptTasks.shared.background
        (reminders, tasks, completing, message, sessions, replies) = (.loading, .loading, [], nil, nil, AgentReplyCache())
        (swipedRow, swipeOffset, hoveredRow, tracking, swallowingMomentum) = (nil, 0, nil, nil, false)
        unseen = false
        let window = makeWindow()
        window.setFrame(PanelPlacement.below(anchor, size: CGSize(width: Self.width, height: height),
                                             visible: NSScreen.screens.map(\.visibleFrame)), display: false)
        window.orderFrontRegardless()
        observe(window)
        reminderTimer = repeating(reminderInterval) { $0.tick() }
        scheduleAgents()
        refreshReminders()
        lookAtTasks(force: true)
        refreshNoteTitles()
    }

    private func shut() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        for timer in [reminderTimer, agentTimer, changeTimer, messageTimer] { timer?.invalidate() }
        (reminderTimer, agentTimer, changeTimer, messageTimer) = (nil, nil, nil, nil)
        window?.orderOut(nil)
        window = nil
        (readingReminders, readRemindersAgain, askingAgents, askingNotes) = (false, false, false, false)
        (readingReplies, readRepliesAgain) = (false, false)
    }

    // MARK: - The window

    private func makeWindow() -> DashboardWindow {
        let window = DashboardWindow()
        let host = DashboardHostingView(rootView: FloatingPanelView(panel: self))
        host.sizingOptions = []  // sized here, keeping its top edge in place
        window.contentView = host
        prepareWindow(window)
        self.window = window
        return window
    }

    /// The window's height now: the header, and the lists up to `maxHeight`.
    var height: CGFloat {
        min(Self.headerHeight + 1 + listHeight, Self.maxHeight)
    }

    /// To the height the lists need, its top edge in place (moved up if it would leave the screen).
    private func resize() {
        guard let window else { return }
        let frame = CGRect(x: window.frame.minX, y: window.frame.maxY - height, width: Self.width, height: height)
        let placed = PanelPlacement.onScreen(frame, visible: NSScreen.screens.map(\.visibleFrame))
        guard placed != window.frame else { return }
        window.setFrame(placed, display: true)
        window.invalidateShadow()
    }

    private var isOnScreen: Bool {
        guard let window, window.isVisible else { return false }
        return !checksOcclusion || window.occlusionState.contains(.visible)
    }

    // MARK: - Listening and looking

    private func observe(_ window: NSWindow) {
        let center = NotificationCenter.default
        func on(_ name: Notification.Name, _ object: AnyObject? = nil, _ handle: @escaping (FloatingPanel, Notification) -> Void) {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, self.isShowing else { return }
                    handle(self, note)
                }
            })
        }
        on(.allInOneIMEReminderAdded) { panel, _ in panel.refreshReminders() }
        // Reminders changed anywhere (the Reminders app, another Mac); they come in bursts.
        on(.EKEventStoreChanged) { panel, _ in panel.remindersChanged() }
        // Collapsed too: the header counts them.
        on(.allInOneIMEAgentsPolled) { panel, note in
            if let sessions = note.userInfo?["sessions"] as? [AgentSession] { panel.show(sessions) }
        }
        // It doesn't look by itself while none runs: a look at once shows the new one.
        on(.allInOneIMEAgentStarted) { panel, _ in panel.lookAtTasks(force: true) }
        on(.allInOneIMEScriptRunsChanged) { panel, _ in panel.scriptRuns = ScriptTasks.shared.background }
        // Displays changed (one unplugged, the resolution): closed, like a menu; the icon opens it again.
        on(NSApplication.didChangeScreenParametersNotification) { panel, _ in panel.closeDropDown() }
        on(.allInOneIMEInterfaceLanguageChanged) { panel, _ in panel.language = UIText.language }
        // Seen again after a while unseen (the screen unlocked, the display awake): what changed meanwhile.
        on(NSWindow.didChangeOcclusionStateNotification, window) { panel, _ in
            guard panel.isOnScreen else {
                panel.unseen = true
                return
            }
            guard panel.unseen else { return }
            panel.unseen = false
            panel.tick()
            if panel.tasksUnfinished { panel.lookAtTasks(force: false) }
        }
    }

    private func repeating(_ interval: TimeInterval, _ work: @escaping (FloatingPanel) -> Void) -> Timer {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if let self { work(self) } }
        }
        timer.tolerance = interval / 10
        return timer
    }

    /// Every 60 s: the reminders (also when collapsed: the header counts them), the times shown, and
    /// the notes' titles when Notes runs.
    private func tick() {
        guard isOnScreen else { return }
        now = sources.now()
        refreshReminders()
        refreshNoteTitles()
    }

    /// Its own looks at the tasks, every 15 s while it's expanded and a task it lists isn't done
    /// (skipped while AgentMonitor looks). Finished tasks don't change: `claude agents` isn't run
    /// for them.
    private func scheduleAgents() {
        let wanted = isShowing
        if wanted, agentTimer == nil {
            agentTimer = repeating(agentInterval) { panel in
                if panel.isOnScreen, panel.tasksUnfinished { panel.lookAtTasks(force: false) }
            }
        } else if !wanted {
            agentTimer?.invalidate()
            agentTimer = nil
        }
    }

    /// Whether a task the last look listed (among those shown) is running or waiting for the user.
    private var tasksUnfinished: Bool {
        sessions.map { AgentTaskList.newest($0).contains { $0.progress != .done } } ?? false
    }

    /// The refresh button: everything, now.
    func refresh() {
        now = sources.now()
        notes = SavedNotesStore.load(sources.defaults).newest(Self.notesShown)
        refreshReminders()
        lookAtTasks(force: true)
        refreshNoteTitles()
    }

    // MARK: - Notes

    /// @note saved a note (heard on or off): recorded, and listed at once when it's on.
    private func noteSaved(_ info: [AnyHashable: Any]?) {
        guard let id = info?["id"] as? String, !id.isEmpty else { return }
        var saved = SavedNotesStore.load(sources.defaults)
        saved.add(id: id, title: info?["title"] as? String ?? "", at: sources.now())
        SavedNotesStore.save(saved, to: sources.defaults)
        log.notice("menu bar panel: a note was saved (\(saved.notes.count) kept)")
        guard isShowing else { return }
        now = sources.now()
        notes = saved.newest(Self.notesShown)
    }

    /// Titles edited in Notes, notes deleted there: asked only while it's on, when Notes runs already,
    /// and only with its permission given before.
    private func refreshNoteTitles() {
        guard isShowing, !askingNotes, !SavedNotesStore.load(sources.defaults).notes.isEmpty, sources.notesRunning() else {
            return
        }
        askingNotes = true
        let generation = self.generation
        Task { [weak self] in
            let listing: NotesListing
            do {
                listing = try await self?.sources.listNotes(Self.noteListLimit) ?? .notAllowed
            } catch {
                listing = .notAllowed
                log.error("menu bar panel: Notes didn't list the notes: \(String(describing: error), privacy: .public)")
            }
            guard let self, generation == self.generation else { return }
            self.askingNotes = false
            let listed: [NotesBridge.Note]?
            switch listing {
            case .notAllowed: return
            case .noFolder: listed = nil  // nothing changes
            case let .folder(notes): listed = notes
            }
            var saved = SavedNotesStore.load(self.sources.defaults)
            if saved.reconcile(with: listed?.map { ($0.id, $0.title, $0.modified) }, limit: Self.noteListLimit) {
                SavedNotesStore.save(saved, to: self.sources.defaults)
                log.notice("menu bar panel: \(saved.notes.count) notes after asking Notes")
            }
            self.notes = saved.newest(Self.notesShown)
        }
    }

    /// Shows the note in Notes; a note that's gone is dropped once Notes (running now) lists the folder.
    /// Turned off meanwhile, it's left at that.
    func open(_ note: SavedNotes.Note) {
        let generation = self.generation
        Task { [weak self] in
            guard let self else { return }
            var failure: String?
            do {
                try await self.sources.showNote(note.id)
            } catch let error as NotesBridge.NotesError where error == .notPermitted {
                failure = UIText.describe(error)
            } catch {
                log.error("menu bar panel: could not show a note: \(String(describing: error), privacy: .public)")
                failure = tr("打不开这条笔记", "Couldn't open this note")
            }
            guard generation == self.generation else { return }
            if let failure { self.say(failure) }
            self.refreshNoteTitles()
        }
    }

    // MARK: - Reminders

    private func remindersChanged() {
        changeTimer?.invalidate()
        changeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.changeTimer = nil
                self?.refreshReminders()
            }
        }
    }

    /// Reads them if allowed (never asks: when macOS hasn't asked the user yet, a button does).
    private func refreshReminders() {
        guard !readingReminders else {
            readRemindersAgain = true
            return
        }
        readingReminders = true
        let generation = self.generation
        Task { [weak self] in
            guard let self else { return }
            let state: RemindersState
            switch await self.sources.reminderAccess() {
            case .notDetermined: state = .notDetermined
            case .denied: state = .denied
            case .allowed:
                do {
                    let dismissed = self.dismissed(Self.dismissedRemindersKey)
                    state = .list(try await self.sources.reminders(self.sources.now()).filter { !dismissed.contains($0.id) })
                } catch RemindersBridge.RemindersError.notPermitted {
                    state = .denied
                } catch {
                    log.error("menu bar panel: could not read the reminders: \(String(describing: error), privacy: .public)")
                    state = .failed(UIText.describe(error))
                }
            }
            guard generation == self.generation else { return }
            self.readingReminders = false
            self.reminders = state
            if case let .list(items) = state { self.completing.formIntersection(items.map(\.id)) }
            if self.readRemindersAgain {
                self.readRemindersAgain = false
                self.refreshReminders()
            }
        }
    }

    /// The button 「允许读取提醒事项」: macOS asks the user now.
    func requestReminderAccess() {
        let generation = self.generation
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.sources.reminders(self.sources.now())
            } catch {
                log.notice("menu bar panel: reminders not allowed: \(String(describing: error), privacy: .public)")
            }
            if generation == self.generation { self.refreshReminders() }
        }
    }

    func openReminderSettings() { sources.openReminderSettings() }

    func openReminders() { sources.openReminders() }

    /// The checkbox: ticks it off in Reminders; its box stays checked until it's gone from the list.
    func complete(_ reminder: RemindersBridge.Reminder) {
        guard !completing.contains(reminder.id) else { return }
        completing.insert(reminder.id)
        let generation = self.generation
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sources.completeReminder(reminder.id)
                log.notice("menu bar panel: a reminder was completed")
            } catch {
                log.error("menu bar panel: could not complete a reminder: \(String(describing: error), privacy: .public)")
                self.completing.remove(reminder.id)
                self.say(UIText.describe(error))
            }
            if generation == self.generation { self.refreshReminders() }
        }
    }

    // MARK: - Claude Code

    /// Asks Claude Code for the tasks, unless AgentMonitor looks every few seconds anyway (`force`:
    /// asks all the same: when it's opened or refreshed, when @agent starts a task).
    private func lookAtTasks(force: Bool) {
        if !force, sources.monitorWatching(), let sessions {
            readReplies(of: AgentTaskList.newest(sessions))
            return
        }
        guard !askingAgents else { return }
        askingAgents = true
        let generation = self.generation
        Task { [weak self] in
            guard let self else { return }
            let result: Result<[AgentSession]?, Error>
            do { result = .success(try await self.sources.listAgents()) } catch { result = .failure(error) }
            guard generation == self.generation else { return }
            self.askingAgents = false
            switch result {
            case .success(nil):
                self.sessions = nil  // nothing to look at again
                self.tasks = .notInstalled
            case let .success(sessions?):
                self.show(sessions)
            case let .failure(error):
                // Not the error's text: Claude Code's message may quote a task.
                log.error("menu bar panel: could not list the background tasks")
                // A list shown before stays up: the next look may work again.
                if case .list = self.tasks {} else { self.tasks = .failed(UIText.describe(error)) }
            }
        }
    }

    /// A look at the tasks (its own or AgentMonitor's, collapsed or not): the newest 6, with the replies
    /// read so far; while it's expanded, the transcripts that changed are read again.
    private func show(_ sessions: [AgentSession]) {
        self.sessions = sessions
        let newest = AgentTaskList.newest(sessions)
        replies.keep(only: newest)
        tasks = .list(taskRows(newest))
        readReplies(of: newest)
    }

    private func readReplies(of newest: [AgentSession]) {
        guard !newest.isEmpty else { return }
        guard !readingReplies else {
            readRepliesAgain = true
            return
        }
        readingReplies = true
        let (generation, known) = (self.generation, replies.known)
        Task { [weak self] in
            guard let self else { return }
            let read = await self.sources.lastReplies(newest, known)
            guard generation == self.generation else { return }
            self.readingReplies = false
            self.replies.store(read)
            if let sessions = self.sessions {
                let newest = AgentTaskList.newest(sessions)
                self.replies.keep(only: newest)
                if !read.isEmpty {
                    self.tasks = .list(self.taskRows(newest))
                }
                if self.readRepliesAgain {
                    self.readRepliesAgain = false
                    self.readReplies(of: newest)
                }
            }
        }
    }

    func open(_ task: AgentTaskRow) { sources.openAgent(task.id) }

    /// The rows of the newest tasks, but those swiped away.
    private func taskRows(_ newest: [AgentSession]) -> [AgentTaskRow] {
        let dismissed = dismissed(Self.dismissedTasksKey)
        return AgentTaskList.rows(newest, replies: replies.replies, prompt: sources.prompt).filter { !dismissed.contains($0.id) }
    }

    // MARK: - Swiping rows away

    static let dismissedRemindersKey = "dismissedReminders"
    static let dismissedTasksKey = "dismissedTasks"

    private func dismissed(_ key: String) -> DismissedRows {
        sources.defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(DismissedRows.self, from: $0) } ?? DismissedRows()
    }

    /// The 「移除」 button, a full swipe, the right-click menu: no longer listed. The note stays in Notes,
    /// the reminder in Reminders, the task in Claude Code.
    func dismiss(_ row: PanelRow) {
        withAnimation(.easeOut(duration: 0.2)) {
            (swipedRow, swipeOffset) = (nil, 0)
            switch row {
            case let .note(id):
                var saved = SavedNotesStore.load(sources.defaults)
                saved.remove(id: id)
                SavedNotesStore.save(saved, to: sources.defaults)
                notes = saved.newest(Self.notesShown)
            case let .reminder(id):
                remember(id, under: Self.dismissedRemindersKey)
                if case let .list(items) = reminders { reminders = .list(items.filter { $0.id != id }) }
            case let .task(id):
                remember(id, under: Self.dismissedTasksKey)
                if case let .list(rows) = tasks { tasks = .list(rows.filter { $0.id != id }) }
            case let .scriptRun(id):
                ScriptTasks.shared.remove(id)  // stopped if it still runs
                scriptRuns = ScriptTasks.shared.background
            }
        }
        log.notice("menu bar panel: a row was removed")
    }

    private func remember(_ id: String, under key: String) {
        var rows = dismissed(key)
        rows.dismiss(id)
        if let data = try? JSONEncoder().encode(rows) { sources.defaults.set(data, forKey: key) }
    }

    /// The pointer is over a row (or left it): a swipe there moves it.
    func hover(_ row: PanelRow, _ inside: Bool) {
        if inside { hoveredRow = row } else if hoveredRow == row { hoveredRow = nil }
    }

    /// A click on a row: with a row swiped open, it only closes that one.
    func click(_ action: () -> Void) {
        guard swipedRow == nil else {
            closeSwipe()
            return
        }
        action()
    }

    /// `row` swiped open, its 「移除」 button showing (`--showcase`'s image).
    func showSwiped(_ row: PanelRow) { (swipedRow, swipeOffset) = (row, -RowSwipe.buttonWidth) }

    func closeSwipe() {
        guard swipedRow != nil else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { (swipedRow, swipeOffset) = (nil, 0) }
    }

    private struct Swipe {
        let row: PanelRow
        /// Where the row was when the fingers touched (open already, or not).
        let start: CGFloat
        var dx: CGFloat = 0, dy: CGFloat = 0
        var sideways: Bool?
        var velocity: CGFloat = 0
        var time: TimeInterval
    }

    /// A scroll in its window: two fingers moving sideways over a row move that row (and nothing
    /// scrolls); up and down, the list scrolls as before. A mouse wheel only scrolls.
    private func swallows(_ event: NSEvent) -> Bool {
        guard event.window === window else { return false }
        if !event.momentumPhase.isEmpty {
            let swallow = swallowingMomentum
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) { swallowingMomentum = false }
            return swallow
        }
        guard event.hasPreciseScrollingDeltas, !event.phase.isEmpty else { return false }
        if event.phase.contains(.began) {
            swallowingMomentum = false
            tracking = hoveredRow.map { Swipe(row: $0, start: swipedRow == $0 ? swipeOffset : 0, time: event.timestamp) }
        }
        guard var swipe = tracking else { return false }
        // The fingers' way, leftwards negative, whichever way scrolling is set to go.
        let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        swipe.dx += dx
        swipe.dy += abs(event.scrollingDeltaY)
        if swipe.sideways == nil, abs(swipe.dx) + swipe.dy > 6 {
            swipe.sideways = abs(swipe.dx) > swipe.dy
            if swipe.sideways == false { closeSwipe() }
        }
        guard swipe.sideways == true else {
            tracking = swipe.sideways == false ? nil : swipe
            return false
        }
        if dx != 0, event.timestamp > swipe.time { swipe.velocity = dx / (event.timestamp - swipe.time) }
        swipe.time = event.timestamp
        let offset = swipe.start + swipe.dx
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            tracking = nil
            swallowingMomentum = true
            switch RowSwipe.rest(offset: offset, velocity: swipe.velocity) {
            case .closed: closeSwipe()
            case .open:
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    (swipedRow, swipeOffset) = (swipe.row, -RowSwipe.buttonWidth)
                }
            case .dismissed: dismiss(swipe.row)
            }
        } else {
            tracking = swipe
            (swipedRow, swipeOffset) = (swipe.row, RowSwipe.clamp(offset))
        }
        return true
    }

    // MARK: - What the header and the rows say

    /// 「3 个提醒 · 1 个任务进行中 · 1 个等你」 (nothing when there's nothing).
    var counts: String {
        var reminderCount = 0, more = false
        if case let .list(items) = reminders {
            reminderCount = items.count
            more = items.count >= Self.reminderReadLimit
        }
        var running = 0, waiting = 0
        if case let .list(rows) = tasks {
            running = rows.filter { $0.progress == .working }.count
            waiting = rows.filter { $0.progress == .needsYou }.count
        }
        return DashboardText.counts(reminders: reminderCount, moreReminders: more, running: running, waiting: waiting,
                                    language: UIText.language)
    }

    /// When a reminder is due, as @reminder says it (nil without a date).
    func due(_ reminder: RemindersBridge.Reminder) -> String? {
        guard reminder.due != nil else { return nil }
        return UIText.when(ReminderDraft(title: reminder.title, due: reminder.due, hasTime: reminder.hasTime), now: now)
    }

    /// The checkbox's VoiceOver label: 「完成「交房租」」 / "Complete “Pay the rent”".
    static func completeLabel(_ title: String) -> String {
        tr("完成「\(title)」", "Complete \u{201C}\(title)\u{201D}")
    }

    static func progressName(_ progress: AgentSession.Progress) -> String {
        switch progress {
        case .working: return tr("进行中", "running")
        case .done: return tr("完成了", "done")
        case .needsYou: return tr("在等你", "waiting for you")
        }
    }

    /// What went wrong with a click, for 6 s (only while it's on: off, nothing of it runs).
    private func say(_ text: String) {
        guard isShowing else { return }
        message = text
        messageTimer?.invalidate()
        messageTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.message = nil
                self?.messageTimer = nil
            }
        }
    }
}

/// The panel's window, under the menu bar icon: it never takes focus from the app being typed in (key
/// only for the tasks' search field, never main, and clicking it doesn't activate the input method),
/// and shows on every Space and over full-screen apps.
final class DashboardWindow: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: FloatingPanel.width, height: FloatingPanel.headerHeight),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        title = "AllInOneIME"  // for VoiceOver; a borderless window shows none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
    }

    /// Only to type in the tasks' search field (`becomesKeyOnlyIfNeeded`): a click anywhere else in it
    /// leaves the keyboard with the app being typed in.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Clicks reach the buttons at once, in a window that's never key.
final class DashboardHostingView: NSHostingView<FloatingPanelView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A row of the panel, to swipe away.
enum PanelRow: Hashable {
    case note(String), reminder(String), task(String), scriptRun(Int)
}

private struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// What the menu bar panel shows: a header with the counts and three buttons, then the notes, the
/// reminders and the Claude tasks. Follows light and dark mode and the interface language (`tr`).
struct FloatingPanelView: View {
    @ObservedObject var panel: FloatingPanel
    /// A new version, as one quiet line at the top (`UpdateController`).
    @ObservedObject var updates: UpdateController = .shared
    @ObservedObject var extensionSources: ExtensionSourceController = .shared
    @Environment(\.colorScheme) private var scheme

    private static let cornerRadius: CGFloat = 14
    /// Frosted glass (what's behind the window, blurred). Off for the self-test's images: an offscreen
    /// rendering has nothing behind it, so they show the solid color instead.
    static var glass = true

    var body: some View {
        let _ = panel.language  // drawn again in the other language
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        let dark = scheme == .dark
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.primary.opacity(dark ? 0.12 : 0.08)).frame(height: 0.5).padding(.horizontal, 12)
            ScrollView(.vertical) {
                lists.background(GeometryReader { proxy in
                    Color.clear.preference(key: ListHeightKey.self, value: proxy.size.height)
                })
            }
            .frame(height: max(0, min(panel.listHeight, FloatingPanel.maxHeight - FloatingPanel.headerHeight - 1)))
        }
        .frame(width: FloatingPanel.width)
        .background {
            ZStack {
                if Self.glass { GlassView(cornerRadius: Self.cornerRadius) } else { Color(nsColor: CandidateView.background) }
                // Light falling on the glass from above (Liquid Glass lights itself).
                if !GlassView.isLiquid {
                    LinearGradient(colors: [.white.opacity(dark ? 0.07 : 0.28), .white.opacity(0)],
                                   startPoint: .top, endPoint: .center)
                }
            }
        }
        .clipShape(shape)
        .overlay {
            // A bright upper edge fading downwards, the edge of a glass pane, over a hairline that keeps it
            // apart from a background of the same color (Liquid Glass draws its own edge).
            if !GlassView.isLiquid || !Self.glass {
                ZStack {
                    shape.strokeBorder(Color.black.opacity(dark ? 0.5 : 0.1), lineWidth: 0.5)
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.28 : 0.75), .white.opacity(dark ? 0.04 : 0.2)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 1)
                        .padding(0.5)
                }
            }
        }
        .onPreferenceChange(ListHeightKey.self) { height in
            // Collapsed, the lists are gone: their height is kept for when they're back.
            MainActor.assumeIsolated { panel.listHeight = height }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text("AllInOneIME").font(.system(size: 12, weight: .semibold))
                let counts = panel.counts
                if !counts.isEmpty {
                    Text(counts).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            headerButton("arrow.clockwise", tr("刷新", "Refresh")) { panel.refresh() }

        }
        .padding(.horizontal, 12)
        .frame(height: FloatingPanel.headerHeight)
    }

    private func headerButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
                .hoverHighlight(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Lists

    private var lists: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let message = panel.message {
                Text(message).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if let update = updates.available { updateNotice(update) }
            ExtensionSourceNotice(sources: extensionSources) { panel.click { SettingsWindow.shared.show(page: .commands) } }
            section(tr("备忘录", "Notes"), CommandIcons.icon(for: .note)) { notes }
            section(tr("提醒事项", "Reminders"), CommandIcons.icon(for: .reminder)) { reminders }
            section(tr("Claude 任务", "Claude Tasks"), CommandIcons.icon(for: .agent)) { tasks }
            if !panel.scriptRuns.isEmpty {
                section(tr("后台命令", "Background Commands"), CommandIcons.scripts) { scriptRuns }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)  // short lines (the empty ones) stay on the left
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var notes: some View {
        if panel.notes.isEmpty {
            line(tr("用 @note 存的笔记会显示在这里", "Notes saved with @note show up here"))
        }
        ForEach(panel.notes) { note in
            let title = note.title.isEmpty ? tr("（无标题）", "(Untitled)") : note.title
            swipeable(.note(note.id)) {
                Button { panel.click { panel.open(note) } } label: {
                    HStack(spacing: 6) {
                        Text(title).font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(DashboardText.ago(note.saved, now: panel.now, language: UIText.language))
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .rowHover()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityHint(tr("在备忘录里打开", "Opens it in Notes"))
            }
        }
    }

    @ViewBuilder
    private var reminders: some View {
        switch panel.reminders {
        case .loading:
            line(tr("正在读取…", "Loading…"))
        case .notDetermined:
            line(tr("要列出提醒事项，需要你允许 AllInOneIME 读取。", "To list your reminders, AllInOneIME needs your permission."))
            Button(tr("允许读取提醒事项", "Allow Access to Reminders")) { panel.requestReminderAccess() }
                .buttonStyle(.link).font(.system(size: 12))
        case .denied:
            HStack(spacing: 6) {
                line(tr("没有读取提醒事项的权限", "No access to Reminders"))
                Spacer(minLength: 4)
                Button(tr("打开系统设置", "Open System Settings")) { panel.openReminderSettings() }
                    .buttonStyle(.link).font(.system(size: 12))
            }
        case let .failed(text):
            Text(text).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
        case let .list(items) where items.isEmpty:
            line(tr("用 @reminder 加的提醒会显示在这里", "Reminders added with @reminder show up here"))
        case let .list(items):
            ForEach(items.prefix(FloatingPanel.remindersShown), id: \.id) { reminder in reminderRow(reminder) }
            if items.count > FloatingPanel.remindersShown {
                let more = items.count - FloatingPanel.remindersShown
                Button { panel.openReminders() } label: {
                    Text(items.count >= FloatingPanel.reminderReadLimit ? tr("还有更多…", "More…") : tr("还有 \(more) 个…", "\(more) more…"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityHint(tr("打开提醒事项", "Opens Reminders"))
            }
        }
    }

    private func reminderRow(_ reminder: RemindersBridge.Reminder) -> some View {
        let done = panel.completing.contains(reminder.id)
        let due = panel.due(reminder)
        return swipeable(.reminder(reminder.id)) { reminderRowContent(reminder, done: done, due: due).rowHover() }
    }

    private func reminderRowContent(_ reminder: RemindersBridge.Reminder, done: Bool, due: String?) -> some View {
        HStack(spacing: 6) {
            Button { panel.click { panel.complete(reminder) } } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(done ? Color.accentColor : Color.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(FloatingPanel.completeLabel(reminder.title))
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(done ? tr("已完成", "completed") : "")
            Button { panel.click { panel.openReminders() } } label: {
                HStack(spacing: 6) {
                    Text(reminder.title).font(.system(size: 13)).lineLimit(1)
                        .foregroundStyle(done ? Color.secondary : Color.primary)
                    Spacer(minLength: 6)
                    if let due {
                        Text(due).font(.system(size: 11)).lineLimit(1)
                            .foregroundStyle(reminder.overdue ? Color.red : Color.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(reminder.title + (due.map { tr("，", ", ", key: "panel.clauseSeparator") + $0 } ?? ""))
            .accessibilityHint(tr("打开提醒事项", "Opens Reminders"))
        }
    }

    @ViewBuilder
    private var tasks: some View {
        switch panel.tasks {
        case .loading:
            line(tr("正在读取…", "Loading…"))
        case .notInstalled:
            line(tr("没有安装 Claude Code（找不到 claude 命令）", "Claude Code isn't installed (no claude command)"))
        case let .failed(text):
            Text(text).font(.system(size: 11)).foregroundStyle(.red).lineLimit(3)
        case let .list(rows) where rows.isEmpty:
            line(tr("用 @agent 交给 Claude Code 后台的任务会显示在这里", "Tasks @agent hands to Claude Code in the background show up here"))
        case let .list(rows):
            // A few at a time: the rest scroll into view, or a search finds them.
            let shown = AgentTaskList.matching(rows, panel.taskQuery)
            if rows.count > AgentTaskList.shown {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField(tr("搜索任务", "Search tasks"), text: $panel.taskQuery)
                        .textFieldStyle(.plain).font(.system(size: 12))
                    if !panel.taskQuery.isEmpty {
                        Button { panel.taskQuery = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .accessibilityLabel(tr("清除搜索", "Clear the search"))
                    }
                }
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(Color.primary.opacity(scheme == .dark ? 0.1 : 0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            }
            if shown.isEmpty {
                line(tr("没有匹配的任务", "No matching tasks"))
            } else if shown.count > AgentTaskList.shown {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 6) { ForEach(shown) { row in taskRow(row) } }
                }
                .frame(height: CGFloat(AgentTaskList.shown) * Self.taskRowHeight)
            } else {
                ForEach(shown) { row in taskRow(row) }
            }
        }
    }

    /// A task row with its reply line, and the space between rows: five of them fill the scrolled list.
    private static let taskRowHeight: CGFloat = 38

    private func taskRow(_ row: AgentTaskRow) -> some View {
        let ago = row.started.map { DashboardText.ago($0, now: panel.now, language: UIText.language) }
        return swipeable(.task(row.id)) { taskButton(row, ago: ago) }
    }

    private func taskButton(_ row: AgentTaskRow, ago: String?) -> some View {
        Button { panel.click { panel.open(row) } } label: {
            HStack(alignment: .top, spacing: 8) {
                IconView(icon: CommandIcons.icon(for: row.progress), size: 16).padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(row.title).font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 6)
                        if let ago { Text(ago).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    if let reply = row.reply {
                        Text(reply).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .rowHover()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([row.title, FloatingPanel.progressName(row.progress), ago, row.reply].compactMap { $0 }
            .joined(separator: tr("，", ", ", key: "panel.clauseSeparator")))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(tr("在终端里打开", "Opens it in Terminal"))
    }

    /// The script extensions in the background: running, done or failed; a click opens what they printed.
    @ViewBuilder
    private var scriptRuns: some View {
        ForEach(panel.scriptRuns) { run in
            let progress: AgentSession.Progress = run.outcome == .running ? .working : run.outcome == .done ? .done : .needsYou
            let ago = DashboardText.ago(run.finished ?? run.started, now: panel.now, language: UIText.language)
            let line: String? = {
                if case let .failed(message) = run.outcome { return message }
                return run.output?.headline
            }()
            swipeable(.scriptRun(run.id)) {
                Button { panel.click { ScriptTasks.shared.openResult(run.id) } } label: {
                    HStack(alignment: .top, spacing: 8) {
                        IconView(icon: CommandIcons.icon(for: progress), size: 16).padding(.top, 1)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(run.command.title).font(.system(size: 13)).lineLimit(1)
                                Spacer(minLength: 6)
                                Text(ago).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            if let line { Text(line).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    }
                    .rowHover()
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([run.command.title, FloatingPanel.progressName(progress), ago, line].compactMap { $0 }
                    .joined(separator: tr("，", ", ", key: "panel.clauseSeparator")))
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(tr("打开它的输出", "Opens what it printed"))
            }
        }
    }

    // MARK: Parts

    /// A row two fingers swipe to the left, to its 「移除」 button (or, far enough, away at once); the
    /// right-click menu and VoiceOver remove it too.
    private func swipeable<Content: View>(_ row: PanelRow, @ViewBuilder _ content: () -> Content) -> some View {
        let offset = panel.swipedRow == row ? panel.swipeOffset : 0
        let label = tr("移除", "Remove")
        let gap = max(0, -offset - 6)
        return content()
            .offset(x: offset)
            .background(alignment: .trailing) {
                if gap > 0 {
                    Button { panel.dismiss(row) } label: {
                        Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            .lineLimit(1).fixedSize()
                            .opacity(min(1, gap / 44))
                            .frame(width: gap)
                            .frame(maxHeight: .infinity)
                            .background(Color.red.opacity(scheme == .dark ? 0.75 : 0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, -5)
                    .accessibilityHidden(true)
                }
            }
            // Slid away into the card's margin, not over the next card; the hover highlight still shows.
            .padding(.horizontal, 5).padding(.vertical, 2)
            .clipShape(Rectangle())
            .padding(.horizontal, -5).padding(.vertical, -2)
            .onHover { panel.hover(row, $0) }
            .contextMenu { Button(label) { panel.dismiss(row) } }
            .accessibilityAction(named: label) { panel.dismiss(row) }
    }

    private func section<Content: View>(_ title: String, _ icon: CandidateView.Icon,
                                        @ViewBuilder content: () -> Content) -> some View {
        // A card of its own on the glass, a shade lighter, like Control Center's modules.
        let card = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let dark = scheme == .dark
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                IconView(icon: icon, size: 16)
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card.fill(Color.white.opacity(dark ? 0.06 : 0.42)))
        .overlay(card.strokeBorder(Color.white.opacity(dark ? 0.08 : 0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(dark ? 0.2 : 0.05), radius: 3, y: 1)
    }

    /// "AllInOneIME 0.7.0 is available": a click opens Settings → About, where Update is.
    private func updateNotice(_ update: UpdateManifest) -> some View {
        Button { panel.click { SettingsWindow.shared.show(page: .about) } } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.accentColor)
                Text(UpdateText.available(update.version)).font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 4)
                Text(tr("更新…", "Update…")).font(.system(size: 12)).foregroundStyle(Color.accentColor)
            }
            .rowHover()
        }
        .buttonStyle(.plain)
        .accessibilityHint(tr("打开设置里的「关于」", "Opens Settings → About"))
    }

    private func line(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// The panel's glass, the system's own like the candidate panel's: Liquid Glass on macOS 26 (Clear or
/// Tinted, as set in Appearance), a frosted material before; both solid with Reduce Transparency.
private struct GlassView: NSViewRepresentable {
    var cornerRadius: CGFloat

    static var isLiquid: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            return glass
        }
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active  // the window is never key: keep it frosted, not flat gray
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

/// A soft highlight under the pointer.
private struct HoverHighlight<S: Shape>: ViewModifier {
    let shape: S
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(shape.fill(Color.primary.opacity(hovering ? 0.08 : 0)))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private extension View {
    func hoverHighlight<S: Shape>(_ shape: S) -> some View { modifier(HoverHighlight(shape: shape)) }

    /// A list row: the whole row is clickable and lights up under the pointer, its text where it was.
    func rowHover() -> some View {
        padding(.horizontal, 5).padding(.vertical, 2)
            .contentShape(Rectangle())
            .hoverHighlight(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.horizontal, -5).padding(.vertical, -2)
    }
}

/// A symbol drawn white on a colored rounded square, like the command list's icons.
private struct IconView: View {
    let icon: CandidateView.Icon
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: icon.symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).fill(Color(nsColor: icon.color)))
            .accessibilityHidden(true)
    }
}
