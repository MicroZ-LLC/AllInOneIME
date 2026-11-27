import AllInOneIMECore
import AllInOneIMEMac
import AllInOneIMERime
import AppKit
import Carbon
import InputMethodKit
import os

let log = Logger(subsystem: "com.allinoneime.inputmethod.AllInOneIME", category: "ime")

/// One converter (one URLSession, one cache, the input method's question sessions) shared by every input session in the
/// process. @question reads the app's user guide for a question about AllInOneIME. Bedrock is ready for what has to be
/// fast only with credentials its requests can be signed with (`AWSCredentialResolver.canAuthenticate`), not just a
/// profile of that name.
let sharedConverter = Converter(loadUserGuide: { BundledUserGuide.text }, userGuideFile: BundledUserGuide.url,
                                questionSessions: ClaudeSessionMac.managers,
                                hasAWSProfile: { AWSCredentialResolver.shared.canAuthenticate(profile: $0) })

/// AllInOneIME's user guide as the app ships it (Contents/Resources/user-guide.md, copied there by the Makefile), read
/// once, when a question first needs it.
enum BundledUserGuide {
    static let url = Bundle.main.url(forResource: "user-guide", withExtension: "md")
    static let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
}

/// Carries a main-thread-only object out of `MainActor.assumeIsolated` (we never leave the main thread).
struct MainThreadBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// A weak reference that crosses threads: what the session's work answers through finds the controller on the main
/// thread, if it's still there.
final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

/// What a controller's session still reaches once the controller is gone (`AllInOneIMEInputController.receivedAfterClose`):
/// the clipboard it copies to. Main thread only.
final class Leftovers: @unchecked Sendable {
    var copyText: (String) -> Void = { text in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

@objc(AllInOneIMEInputController)
final class AllInOneIMEInputController: IMKInputController {
    /// The field's session, the core's (`InputSession`): the composer and what goes on around it. This controller adapts
    /// IMK's events to it (`SessionEvent`: the keys with what the field says around them) and does what it answers
    /// (`SessionOutput`) to the field and on the screen; what the session's work answers later comes back here on the main
    /// thread (`received`).
    lazy var session: InputSession = makeSession()
    /// The input state machine (the session's).
    var composer: Composer { session.composer }
    /// What the session asks of this Mac, or has it do (`SessionServices.mac`; the self-test supplies stand-ins that
    /// leave the user's own alone).
    var services: SessionServices {
        get { session.services }
        set { session.services = newValue }
    }
    /// The notice up now, and what the panel says of the last result (the session's).
    var notice: String? {
        get { session.notice }
        set { session.notice = newValue }
    }
    var lastHidden: Int { session.lastHidden }
    var lastShortened: Bool { session.lastShortened }
    /// The app of the text field that became active last.
    var activeApp: String? { session.field.app }
    /// The bundle id of the app being typed in, as the client says it.
    var appID: String? { (clientOverride ?? client())?.bundleIdentifier() }
    /// Whether this text session has delivered a key yet (logged once, without the key).
    private var receivedKeys = false
    /// Whether the selection may be read with Accessibility when the field doesn't say (`SelectedText`). False in the
    /// self-test: it would reach the user's own frontmost app.
    var selectionByAccessibility = true
    /// Only set by the self-test: IMK refuses to create a controller for anything but its own
    /// client proxies, so the test injects its fake text field here.
    var clientOverride: IMKTextInput?
    /// Set for one `apply`: its outputs answer a key the session took that composes (see `apply`).
    private var keyComposes = false
    /// Keeps the app a text field became active in, for Settings → Apps' "Add App…" (the self-test keeps none).
    var recordApp: (String) -> Void = { app in MainActor.assumeIsolated { RecentApps.record(app) } }
    /// Opens an `@open` result: a web address in the default browser, anything else as a file, or shown in Finder where
    /// opening would run it (`FileOpenPolicy`; the self-test opens nothing).
    var openItem: (String) -> Void = { path in
        MainActor.assumeIsolated { FileOpenPolicy.open(path) }
    }
    /// Opens a background `@agent` task (Claude Code's) in Terminal.
    var openAgent: (String) -> Void = { id in MainActor.assumeIsolated { AgentMonitor.shared.open(id) } }
    /// Opens the settings window on `page`, pointing at `spot` there if given (the self-test records it instead).
    var openSettings: @MainActor (SettingsPage, SettingsSpot?) -> Void = { SettingsWindow.shared.show(page: $0, spot: $1) }
    /// Puts this week's picture on the clipboard (`@stats`'s ⌘C), then tells whether it is there.
    var copyWeekStatsImage: (@escaping @MainActor (Bool) -> Void) -> Void = { done in
        MainActor.assumeIsolated { WeekStatsShared.copyImageSoon(then: done) }
    }
    /// Turns Caps Lock's lock on or off (`CapsLockKey`; the self-test touches none).
    /// Off: kept off for a moment (`CapsLockKey.keepOff`).
    var setCapsLock: @MainActor (Bool) -> Void = { $0 ? CapsLockKey.setLock(true) : CapsLockKey.keepOff() }
    /// The browser's process when `@agent`'s page is to be read in `app` (`PageContextReader.applies`; the self-test reads
    /// none), and reading it: off the main thread (`SessionServices.page`).
    var pageProcess: (String?) -> pid_t? = { app in
        PageContextReader.applies(app: app, enabled: true) ? app.flatMap(PageContextReader.runningPID) : nil
    }
    var readPageContext: @Sendable (pid_t, CGPoint) -> PageContext? = { PageContextReader.read(pid: $0, pointer: $1) }
    /// Counts this controller's activations and deactivations: text inserted once a key is done goes nowhere if the
    /// field changed meanwhile (`SessionOutput.commitAfterKey`).
    private(set) var fieldSession = 0
    /// The controller of the text field being typed in, if any: where the outcome of a save is told once the
    /// field it came from is gone.
    private(set) static weak var activeController: AllInOneIMEInputController?
    /// Where script extensions run (`ScriptTasks.shared`).
    lazy var scriptTasks: ScriptTasks = MainActor.assumeIsolated { ScriptTasks.shared }
    /// What the session's work still reaches once this controller is gone (`receivedAfterClose`): its clipboard.
    private let leftovers = Leftovers()
    /// ⌘C on a result (the self-test leaves the clipboard alone).
    var copyText: (String) -> Void {
        get { leftovers.copyText }
        set { leftovers.copyText = newValue }
    }
    /// ⌘V or ⌃V in a draft: what the clipboard has for it (`clipboardContent`: its text, else an image), read only once
    /// the key is answered and never during secure input (the self-test supplies its own and never reads the real
    /// clipboard).
    var readClipboard: () -> ClipboardContent = { AllInOneIMEInputController.clipboardContent(NSPasteboard.general) }
    /// ⌃V opening clipboard history (a read with an id below 0): the clipboard's text, or that it has an image, told by its
    /// types (`.image` with no data: the panel's first row says so, and what is chosen there never needs it; in a command
    /// that row reads the clipboard again, with `readClipboard`). The self-test supplies its own.
    var peekClipboard: () -> ClipboardContent = { AllInOneIMEInputController.clipboardContent(NSPasteboard.general, imageData: false) }
    /// Whether a draft started with an image on the clipboard warms Vision up (`warmUpScreenshotReading`; not in the
    /// self-test: it would look at the real clipboard's types).
    var warmsUpVision = true
    /// The keyboard layout this text field was last told to type with (`applyKeyboardLayout`).
    private(set) var appliedLayout: String?
    /// The recording in progress (a `DictationSession`, which needs macOS 26).
    private var voiceSession: AnyObject?
    /// Self-test only: recognize this audio file instead of the microphone.
    var voiceFile: (url: URL, speed: Double)?
    /// False in the self-test: the microphone (and its permission prompt) is never touched.
    static var microphoneAllowed = true
    /// Whether marked text of ours is in the document: only a row marked during its key (`markRow`). What is being typed
    /// is never marked there (`InputSession+Preedit.swift`): the panel's input line shows it.
    var hasMarkedText: Bool { markedRow != nil }
    /// What a key the rows took put in as marked text in a Chromium or Electron app (a row, or the token's last character
    /// again), to commit once the key is done (`markRow`).
    private var markedRow: MarkedRow?
    private struct MarkedRow {
        let text: String
        let client: IMKTextInput
        /// The field session it went into (`fieldSession`): committed only while that one is on.
        let fieldSession: Int
        /// Taken out again rather than committed: a space marked at the start of an empty field (`markBeforeCaret`).
        var takenOut = false
        /// A snippet's caret, moved once it's in (`moveCaret`).
        var caret: (back: Int, after: String?)?
    }
    /// The selection clipboard history's panel opened over in a Chromium or Electron app: marked during ⌃V and committed
    /// back as it was (`markBeforeCaret`), so the caret is after it while the panel shows; what a row of the panel puts in
    /// goes in its place, as a paste over a selection does (`takePastedOver`). Only while that panel shows, in that field.
    private var pastedOver: (range: NSRange, text: String, fieldSession: Int)?
    /// Kept while the session waits for a web page a request takes along (`InputSession.waitsForPage`): the request
    /// starts even if the field is gone by then.
    private var keepAlive: AllInOneIMEInputController?
    /// Counts autocomplete's suggestions shown and taken down: a placement that comes after a newer one does nothing
    /// (`showGhost`); the suggestion is a line of the candidate panel (`placeGhost`).
    var ghostToken = 0
    var ghostInPanel = false
    /// The self-test's say whether the field is a password field, as autocomplete's read asks Accessibility
    /// (`readFieldAfterPause`, `readPasswordField`): its harness field is never the one focused. Nil: Accessibility's.
    var passwordField: (@MainActor () -> Bool)?
    /// Whether an app (its bundle id) is built on Chromium or Electron (`ChromiumApps`): a key the rows take there is kept
    /// from its page with marked text (`marksRow`). Each app told once found, for every field (`chromiumApps`); the
    /// self-test's say for its fake fields.
    var chromiumApp: (String?) -> Bool = { AllInOneIMEInputController.chromiumApps.isChromium($0) }
    static let chromiumApps = ChromiumApps.Known { id in
        NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }
    /// The field's frame the suggestion is cut at (`placeGhost`), asked once a suggestion (nil: not yet; .some(nil): not
    /// known); the self-test's own (`fieldFrame`: its harness field isn't the one focused), else Accessibility's.
    var ghostField: NSRect??
    /// Counts the field frames asked (`askGhostField`): an answer to an earlier one (another suggestion's, another
    /// field's) is gone by.
    var ghostFieldAsked = 0
    var fieldFrame: (@MainActor () -> NSRect?)?
    /// What a panel's anchor goes by in this field (`PanelAnchor.Memory`: the last rect to trust it told), and a count
    /// that ends the field's being asked again for one (`reaskAnchor`): a key, the panel placed anew, the field left.
    var panelAnchor = PanelAnchor.Memory()
    var anchorToken = 0
    /// What Accessibility told of the caret off the main thread, for the panel's anchor (`accessibilityCaret`).
    var anchorReads = AnchorReads()
    /// How many times the panel was placed (`anchor`): one placed while the field was asked holds what's newer.
    var placements = 0
    /// What the log said last of a panel's anchor not trusted (`anchor`).
    var anchorSaid: String?

    static let notFound = NSRange(location: NSNotFound, length: NSNotFound)

    /// The session, with this Mac's services and those that ask this controller (the page, the keyboard layout, pasting
    /// into a terminal, Translate as You Type's chip). Its work answers on the main queue: here while this controller is
    /// there, else where a save's outcome or a notice still has to go (`receivedAfterClose`).
    private func makeSession() -> InputSession {
        let box = WeakBox(self)
        var services = MainActor.assumeIsolated { MainThreadBox(SessionServices.mac) }.value
        services.pastesInTerminal = { MainActor.assumeIsolated { box.value?.canPasteInTerminal() ?? false } }
        services.keyTranslator = {
            MainActor.assumeIsolated { box.value?.appliedLayout.flatMap(KeyboardLayout.cached(id:)) ?? KeyboardLayout.current() }
        }
        services.translateChip = { MainActor.assumeIsolated { box.value?.translateChip() } }
        // Autocomplete: what it learns and counts, one for every field; an app's name for what it says of the app.
        services.autocomplete = MainActor.assumeIsolated { MainThreadBox(AutocompleteSwitch.store) }.value
        // What is learned (Settings v2 §3.2): the starting input each app learned, which this field's switches teach.
        services.learned = MainActor.assumeIsolated { LearnedShared.store }
        // Suggestions: one store for every field, the coding packs installed, and Translate as You Type the input method's
        // (this field turns it on and off for the session's long press of Shift).
        services.suggestions = MainActor.assumeIsolated { MainThreadBox(SuggestionsShared.services(field: box)) }.value
        // Clipboard history: one for every field (⌃V shows it).
        services.clipboardHistory = MainActor.assumeIsolated { MainThreadBox(ClipboardHistoryShared.services) }.value
        services.appName = { app in MainActor.assumeIsolated { AppNames.name(for: app) } }
        services.page = { app in
            MainActor.assumeIsolated { () -> MainThreadBox<PageSource?> in
                guard let controller = box.value, let pid = controller.pageProcess(app) else { return MainThreadBox(nil) }
                let read = controller.readPageContext
                return MainThreadBox(PageSource(wake: { PageContextReader.wake(pid: pid) }, release: { PageContextReader.release(pid: pid) }) {
                    let mouse = NSEvent.mouseLocation, height = NSScreen.screens.first?.frame.height ?? 0
                    let pointer = CGPoint(x: mouse.x, y: height - mouse.y)  // top-left origin, as Accessibility has it
                    return {
                        let context = read(pid, pointer)
                        PageContextReader.release(pid: pid)
                        return context
                    }
                })
            }.value
        }
        let leftovers = leftovers
        return InputSession(services: services, deliver: { event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let controller = box.value {
                        controller.received(event)
                    } else {
                        Self.receivedAfterClose(event, copy: leftovers.copyText)
                    }
                }
            }
        })
    }

    /// Hands `event` to the session and does what it answers, in the field being typed in.
    @MainActor
    func received(_ event: SessionEvent) {
        commitRow()  // a row a key put in, before what comes after the key
        apply(session.handle(event).outputs, client: nil)
    }

    /// The selection only Accessibility tells (`SessionOutput.readSelection`), read off the main thread once the "@" key is
    /// answered (the app answers it on its own main thread, free once the key is), and handed back to the session as read
    /// `id` (`SessionEvent.selection`): a key parked for it is done then, and one that settled it as none dropped it. Only
    /// how long it is is logged.
    @MainActor
    func readSelectionAfterKey(id: Int) {
        let box = WeakBox(self)
        DispatchQueue.global(qos: .userInitiated).async {
            let text = SelectedText.readWithAccessibility()
            if let text { log.notice("selection read (AX, after the key, \(text.count) characters)") }
            let selection = text.map { Composer.Selection(text: $0) }
            DispatchQueue.main.async { MainActor.assumeIsolated { box.value?.received(.selection(selection, id: id)) } }
        }
    }

    /// The extensions or plugins changed in the background (`LiveExtensions.changed`, `LivePlugins.changed`): an "@" list
    /// open in this field shows them at once (`InputSession.commandsChanged`).
    @MainActor
    func commandsChanged() {
        apply(session.commandsChanged(), client: nil)
    }

    /// What the session's work answered once this controller was gone: a save's outcome (its text on the clipboard if it
    /// failed) and a notice, told in the field being typed in now, else near the pointer (a save's).
    @MainActor
    static func receivedAfterClose(_ event: SessionEvent, copy: (String) -> Void) {
        guard case let .task(_, update) = event else { return }
        switch update {
        case let .saved(outcome):
            let (notice, long, text) = outcome.elsewhere
            if let text { copy(text) }
            if let target = activeController {
                target.showNotice(notice, client: nil, long: long)
            } else {
                showLooseNotice(notice, long: long)
            }
        case let .notice(text):
            activeController?.showNotice(text, client: nil)
        default:
            break
        }
    }

    // MARK: - IMK entry points (the keys': InputController+Recording.swift)

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        IMKRecorder.shared.event("activate", client: sender)
        MainActor.assumeIsolated {
            commitRow()  // in the field it went into, while that one's session is on
            appliedLayout = nil  // the layout is told to each text field
            fieldSession += 1
            Self.activeController = self
            attachKeyGuard()
            let app = (sender as? IMKTextInput)?.bundleIdentifier()
            if let app { recordApp(app) }
            // The app's own starting language, rewrite styles, typing out (`AppProfile`); a terminal pastes on ⌘V itself.
            let field = FieldInfo(app: app, terminal: Self.isTerminal(app: app))
            apply(session.handle(.focus(field)).outputs, client: sender as? IMKTextInput)
            // Translate as You Type's target removed: the first output language typed text goes into, else off.
            translateModeFollow(services.loadSettings())
            // The candidates' characters, when they follow the system's languages and those changed (`RimeFuzzy.follow`);
            // by the file as it parses, not its defaults.
            RimeFuzzy.follow(LiveConfig.currentIfValid)
            translateModeActivated(app: app)  // another app leaves Translate as You Type, unless it translates always
            // A custom command renamed because a built-in has its name now: said once, last (no notice above covers it)
            apply(session.tellBuiltinRenames(), client: sender as? IMKTextInput)
            // Once a day at most, in the background: comparing two dates here, never on a keystroke.
            UpdateController.shared.checkIfDue()
            // The step to add the input source, while it's shown: this text field says it is added now.
            InputSourceStatus.shared.textFieldActivated()
        }
    }

    override func commitComposition(_ sender: Any!) {
        // The app wants everything in now (a click elsewhere in it): what is typed out goes in, the pinyin doesn't.
        IMKRecorder.shared.event("commitComposition", client: sender)
        MainActor.assumeIsolated { leaveField(.commit, client: sender as? IMKTextInput, insertingRest: true) }
    }

    // MARK: - Typing a result out

    /// How long typing out waits between steps, and its slips (the self-test waits less, and picks them); how fast and
    /// with typos fixed on the way is the session's (`Config.typeOutRate`, `typeOutVaries`, `typeOutMistakes`).
    var typeOutSleep: @Sendable (Double) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    var typeOutRandom: (() -> Double)?
    var typingTask: Task<Void, Never>?
    /// The plan being typed, and the field it goes into (`TypeOut.Typist`: it keeps the field right while a typo is in it).
    var typist = TypeOut.Typist([], start: 0)
    /// Typing out stopped, the field looked at again a little later (`settleStop`): whether the rest goes in then.
    var stopsInsertingRest: Bool?
    /// The keys that type, typed while a stop settles (`keyWhileTypingOut`), each with its field: handled once it has.
    var keysWhileStopping: [(event: NSEvent, client: IMKTextInput?)] = []
    var typingField: TypingField?
    /// Line breaks, tabs and other control characters go in as a paste (a terminal; `TerminalPaste`).
    var typingPastes = false
    /// A snippet being typed out: where its caret goes once it's all in (`moveCaret`).
    var caretAfterTyping: Int?

    /// Whether line breaks can go into a terminal as a paste, and pasting there: false where it wasn't pasted after all,
    /// nil where it was stopped and nothing goes in (another app frontmost now: `TerminalPaste.paste`; the self-test
    /// supplies its own and never posts keys or touches the clipboard).
    var canPasteInTerminal: @MainActor () -> Bool = { TerminalPaste.isAllowed() }
    var pasteInTerminal: @MainActor (String) async -> Bool? = { await TerminalPaste.paste($0) }
    /// ⌃V to the app, marked as ours: the app's own paste in a terminal or a code editor (clipboard history's image, ⌃V
    /// again: `TerminalPaste.postControlV`; the self-test counts it instead).
    var passPasteKey: @MainActor () -> Void = { TerminalPaste.postControlV() }
    /// ⌘V to the app, marked as ours (an app's own paste: clipboard history's image, ⌃V again; the self-test counts it).
    var passCommandV: @MainActor () -> Void = { TerminalPaste.postCommandV() }
    /// A kept image pasted with the app's paste key, the clipboard put back after (`TerminalPaste.pasteImage`; the
    /// self-test records it instead).
    var pasteImage: @MainActor (Data, Bool) async -> Void = { await TerminalPaste.pasteImage($0, controlV: $1) }

    /// Whether the app's own paste key in `client` is ⌃V (a terminal, a code editor: its terminal's Claude Code takes
    /// images on it, its Vim mode selects a block), not ⌘V (0.6.8.2, clipboard history's image and ⌃V again).
    static func pastesOnControlV(_ client: IMKTextInput?) -> Bool {
        isTerminal(client) || CodeEditors.contains(client?.bundleIdentifier())
    }

    /// Clipboard history's kept image `id` (0.6.8.2), once the key being answered is done: pasted with the app's own paste
    /// key where Accessibility lets it be posted; else put on the clipboard, for the user's own ⌘V (the row said so).
    @MainActor
    private func pasteKeptImage(_ id: String, into target: IMKTextInput?) {
        guard let png = services.clipboardHistory.imageData(id) else {
            log.notice("clipboard history: a kept image is gone")
            showNotice(composer.messages.nothingToPaste, client: target)
            return
        }
        let controlV = Self.pastesOnControlV(target)
        guard services.clipboardHistory.canPassPasteKey() else {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            log.notice("clipboard history: a kept image put on the clipboard (no Accessibility to paste it)")
            return
        }
        let paste = pasteImage
        Task { @MainActor in await paste(png, controlV) }
    }

    /// Inserts `text` into `client`; into a terminal, text with line breaks, tabs or other control characters goes in as
    /// a paste (`Composer.actsInTerminal`), so they don't run (or send, or complete) anything; on one line where it
    /// couldn't be pasted after all (what is on the clipboard couldn't be kept: `TerminalPaste.paste`), while the field
    /// is still the one typed in. Nothing where the paste was stopped (another app frontmost now).
    @MainActor
    private func insert(_ text: String, into client: IMKTextInput?, replacing range: NSRange = AllInOneIMEInputController.notFound) {
        commitRow()  // a row marked during the key goes in first: the text would take its place
        if Composer.actsInTerminal(text), Self.isTerminal(client), canPasteInTerminal() {
            let paste = pasteInTerminal, session = fieldSession
            Task { @MainActor [weak self] in
                guard await paste(text) == false, self?.fieldSession == session else { return }
                client?.insertText(Composer.oneLine(text), replacementRange: Self.notFound)
            }
        } else {
            client?.insertText(text, replacementRange: range)
            insertedDuringKey = true
        }
    }

    /// Whether text went into the field during the key being answered (`insert`), for `keepFromTerminal`.
    private var insertedDuringKey = false

    /// A key the rows took (↓ ↑ → Esc, ⌃V opening clipboard history, ⏎ on a row that goes in as a paste) in a terminal,
    /// where nothing went in during it and no marked text is there: a space marked at the caret during the key and taken
    /// out once it's done (`markRow`), so the terminal doesn't send the key to the shell as well. A terminal (Ghostty,
    /// Terminal, iTerm2) sends a key the input method took itself unless text went in during it or marked text is there
    /// after it: ↓ ↑ after ⌃V went to the shell's history (0.6.8), and ⏎ on a row with line breaks (a paste, after the
    /// key) ran the line. Marked text never reaches the shell; text inserted during the key goes in the key's place.
    @MainActor
    private func keepFromTerminal(_ target: IMKTextInput) {
        guard !atTap, Self.isTerminal(target), !hasMarkedText, !insertedDuringKey else { return }
        KeyGuard.shared.markedInstead()
        markRow(" ", replacing: nil, in: target, for: "a key the rows took in a terminal", takenOut: true)
    }

    /// A result in place of the selection the command worked on (`Composer.Effect.replaceSelection`): by its range, which
    /// the text input protocol has fields honor; one that ignores it still has the text selected, and an insert replaces
    /// what is selected. A result that starts with the selection (`@reply`'s, after the message selected) only has the
    /// rest inserted after it (`afterSelection`): the selection is never rewritten, its formatting, links and images kept.
    /// A field that doesn't take the result in its place is remembered (`rememberIfNotReplaced`).
    @MainActor
    func replaceSelection(_ text: String, _ selection: Composer.Selection, in client: IMKTextInput?) {
        guard let client else { return }
        if let (rest, end) = Self.afterSelection(text, selection) {
            client.insertText(rest, replacementRange: end)
            log.notice("inserted after the selection (\(rest.count) characters)")
            return
        }
        let range = selection.range.map { NSRange(location: $0.lowerBound, length: $0.count) } ?? Self.notFound
        client.insertText(text, replacementRange: range)
        log.notice("selection replaced (\(selection.range == nil ? "what is selected" : "its range", privacy: .public), \(text.count) characters)")
        rememberIfNotReplaced(text, selection, in: client)
    }

    /// How long after a result went in place of the selection its field is read back, and again: a browser tells its text
    /// late, so only what it says both times counts.
    static let replacementChecks: [TimeInterval] = [0.3, 1]

    /// Remembers the app (`LearnedShared`) when its field didn't take `text` in place of `selection`, read back at each of
    /// `replacementChecks` (`SessionText.selectionNotReplaced`: the selection's text still where it was, not the result):
    /// its selection isn't used again, as an app that can't take a typo back gets none (Privacy → Learned… lists it).
    /// Nothing is learned where it can't be told (no range, the field doesn't say).
    @MainActor
    private func rememberIfNotReplaced(_ text: String, _ selection: Composer.Selection, in client: IMKTextInput) {
        let app = client.bundleIdentifier() ?? ""
        guard !app.isEmpty, selection.range != nil else { return }
        Task { @MainActor in
            var waited: TimeInterval = 0
            for check in Self.replacementChecks {
                try? await Task.sleep(nanoseconds: UInt64((check - waited) * 1_000_000_000))
                waited = check
                let notReplaced = SessionText.selectionNotReplaced(selection, by: text) { range in
                    client.attributedSubstring(from: NSRange(location: range.lowerBound, length: range.count))?.string
                }
                guard notReplaced == true else { return }
            }
            guard LearnedShared.store.turnSelectionOff(in: app) else { return }
            log.error("\(app, privacy: .public) didn't take a result in place of the selection; its selection isn't used there again")
        }
    }

    /// What of `text` goes in after `selection` and where (an empty range at its end): `SessionText.afterSelection`.
    static func afterSelection(_ text: String, _ selection: Composer.Selection) -> (String, NSRange)? {
        SessionText.afterSelection(text, selection).map { ($0.text, NSRange(location: $0.at, length: 0)) }
    }

    // Typing a result out (`typeOut`), a snippet's caret after it (`moveCaret`), a stop that settles later
    // (`settleStop`): InputController+TypeOut.swift.

    /// Stops typing out: the rest goes in at once, or (Esc, the field lost) isn't typed. Either way a typo still
    /// in the field is taken out first, where it was typed, so it holds the text, or its start. Checked like any fix: a
    /// field that tells its text late is looked at again a little later, never waited for here (`settleStop`), the rest as
    /// the first stop asked; `waiting` false: done now, with the field as it looks. Whether it stopped now. Once it has,
    /// the keys typed meanwhile go on (`keysWhileStopping`), in the order typed.
    @MainActor @discardableResult
    func stopTyping(insertingRest: Bool, waiting: Bool = true) -> Bool {
        guard let task = typingTask else { return true }
        task.cancel()
        let insertingRest = stopsInsertingRest ?? insertingRest
        if let field = typingField {
            guard let rest = typist.stopping(insertingRest: insertingRest, in: field, waiting: waiting) else {
                settleStop(in: field, insertingRest: insertingRest)
                return false
            }
            // Judged without waiting, a field that tells its text late may look as if it didn't take a fix: not remembered.
            if waiting { rememberFailure(field.client.bundleIdentifier() ?? "") }
            if !rest.isEmpty { insert(rest, into: field.client) }
        }
        log.notice("typing out stopped (\(insertingRest ? "the rest inserted" : "the rest dropped"), privacy: .public)")
        (typingTask, typist, typingField, typingPastes, stopsInsertingRest) = (nil, TypeOut.Typist([], start: 0), nil, false, nil)
        caretAfterTyping = nil  // a snippet's caret stays at the end
        typeHeldKeys()
        return true
    }

    /// Whether a result is being typed out now (the self-test).
    var isTypingOut: Bool { typingTask != nil }

    override func deactivateServer(_ sender: Any!) {
        IMKRecorder.shared.event("deactivate", client: sender)
        MainActor.assumeIsolated {
            // Still this field's session; another field has the focus now: the rest of a result isn't typed anywhere.
            leaveField(.blur, client: sender as? IMKTextInput, insertingRest: false)
            fieldSession += 1
            panelAnchor.forget()  // the last rect to trust was this field's
            (anchorToken, anchorSaid) = (anchorToken + 1, nil)
            if Self.activeController === self { Self.activeController = nil }
            KeyGuard.shared.detach(self)
            if Self.pointerOwner === self { Self.pointerOwner = nil }
            hideTranslateChip()  // Translate as You Type's chip is for the field being typed in
        }
        super.deactivateServer(sender)
    }

    override func composedString(_ sender: Any!) -> Any! {
        ""  // what is being typed is in the panel, never in the field
    }

    override func inputControllerWillClose() {
        MainActor.assumeIsolated {
            commitRow()
            cancelVoiceSession()
            apply(session.handle(.close).outputs, client: nil)
            hidePanelIfOwned()
            fieldSession += 1  // what is inserted once a key is done goes nowhere now
            if Self.activeController === self { Self.activeController = nil }
            KeyGuard.shared.detach(self)
        }
        super.inputControllerWillClose()
    }

    override func menu() -> NSMenu! {
        log.notice("input menu requested")
        return MainActor.assumeIsolated { MainThreadBox(addingSuggestions(to: addingAutocomplete(to: addingCode(to: makeMenu())))) }.value
    }

    // MARK: - The session

    /// Takes over the settings (`InputSession.applySettings`); Translate as You Type follows a target removed from them.
    @MainActor
    func applySettings(app: String? = nil) {
        apply(session.applySettings(app: app), client: nil)
        translateModeFollow(services.loadSettings())
    }

    /// Level one's engine, once librime has deployed (`InputSession.ensureEngine`).
    @MainActor
    func ensureEngine() {
        apply(session.ensureEngine(), client: nil)
    }

    /// The commands "@" offers (`InputSession.setCommands`).
    @MainActor
    func setCommands(_ commands: [Command], recheck: Bool = false) {
        apply(session.setCommands(commands, recheck: recheck), client: nil)
    }

    /// What the composer answered something done to it here (Translate as You Type, the menu, the self-test).
    @MainActor
    func perform(_ effects: [Composer.Effect], client: IMKTextInput?) {
        apply(session.apply(effects), client: client)
    }

    // MARK: - Keys

    /// The key downs answered lately, whatever the text field (a copy may reach another one).
    @MainActor private static var keyEchoes = KeyEchoes()

    @MainActor
    func handleKeyDown(_ event: NSEvent, client: IMKTextInput?) -> Bool {
        // A V posted here (a paste into a terminal, a kept image's paste key, ⌃V again), handed over by the app: the app's.
        // (At the tap it never comes here: `KeyGuard` lets it go on.)
        if !atTap, TerminalPaste.isOurs(event) { return false }
        if !atTap, !KeyGuard.shared.isAttached(self) { attachKeyGuard() }
        commitRow()  // a row the key before put in, if this key came first
        // The same key down handed over a second time (the owner's "#17" had the session's token one "1" longer than
        // the field): answered as the first was, before anything sees it (the session, typing out, Translate as You
        // Type's long press).
        let key = MacKeyEvents.echoKey(event)
        let now = ProcessInfo.processInfo.systemUptime
        if let handled = Self.keyEchoes.copy(of: key, now: now) {
            // `log stream --level debug --predicate 'subsystem == "com.allinoneime.inputmethod.AllInOneIME" AND eventMessage
            // BEGINSWITH "a keyDown came twice"'`: how long after the event's time the copy came, never the key.
            let late = (now - event.timestamp) * 1000
            log.debug("a keyDown came twice; the copy was dropped (\(late, format: .fixed(precision: 1), privacy: .public) ms after its time)")
            return handled
        }
        let handled = handleNewKeyDown(event, client: client)
        Self.keyEchoes.answered(key, now: now, handled: handled)
        return handled
    }

    /// A key down at the key tap (`KeyGuard`), before any app has it: nil when it's no key for us there (the app hands it
    /// over as usual); else answered here as when the app hands it over (`handleKeyDown`): true, the tap keeps it from the
    /// app; false, it goes on to the app, which hands it over again and has the same answer (`KeyEchoes`). Ours while this
    /// is the field being typed in, nothing of ours is marked in it (marked text keeps keys from any app already), and a
    /// panel shows (suggestion rows, clipboard history's), this field's autocomplete suggestion shows after the caret
    /// (`GhostOverlay`: its Esc and Tab, which a Chromium page acted on too), or the key is ⌃V (which opens clipboard
    /// history's); and ⌘V into a command not run yet, with its text marked. The tap's event is made an NSEvent only then:
    /// the tap has every key of every app.
    @MainActor
    func keyAtTap(_ event: CGEvent) -> Bool? {
        // ⌃ (or ⌘) alone of the four (a key posted by another program carries other bits besides).
        let flags = event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]), isV = event.getIntegerValueField(.keyboardEventKeycode) == 0x09
        // ⌘V in a command not run yet pastes into it in every app (`Composer.pastesIntoCommand`): taken here, marked text
        // or not, before a terminal or Notes, which paste on ⌘V whatever the input method says, have it.
        let commandV = isV && flags == .maskCommand && composer.pastesIntoCommand
        guard !hasMarkedText || commandV, let client = client() else { return nil }
        let controlV = isV && flags == .maskControl, ghost = GhostOverlay.shared.isVisible && GhostOverlay.shared.owner === self
        guard CandidatePanel.shared.isShowing || ghost || controlV || commandV, let key = NSEvent(cgEvent: event) else { return nil }
        atTap = true
        defer { atTap = false }
        return handleKeyDown(key, client: client)
    }

    /// This controller's `keyAtTap` the one the key tap asks: from its field's activation, and from a key it is handed
    /// without one (the input method started again while its field had the focus: no activation comes then).
    @MainActor
    private func attachKeyGuard() {
        KeyGuard.shared.attach(self) { [weak self] event in self?.keyAtTap(event) ?? nil }
        watchPointerDowns()  // the clicks that leave what is being typed
    }

    /// The key being answered came from the key tap (`keyAtTap`), or was held while typing out stopped and answered then
    /// (`typeHeldKeys`): no app will have it, so nothing is marked to keep it from one (`marksRow`, `keepFromTerminal`).
    var atTap = false

    /// A key down handed over for the first time (or held while typing out stopped, now that it has: `typeHeldKeys`).
    @MainActor
    func handleNewKeyDown(_ event: NSEvent, client: IMKTextInput?) -> Bool {
        // A result still being typed out: Esc stops it there; any other key types the rest at once,
        // then goes on as usual (`keyWhileTypingOut`).
        translateModeKeyDown()
        if typingTask != nil, let taken = keyWhileTypingOut(event, client: client) { return taken }
        anchorToken += 1  // the field isn't asked again for the panel's rect: this key places the panel anew, if it's up
        if !receivedKeys {
            receivedKeys = true
            log.notice("receiving keys (engine ready: \(RimeService.shared.isReady))")
        }
        let target: IMKTextInput? = client ?? clientOverride ?? self.client()
        let key = MacKeyEvents.key(event)
        let context = fieldContext(in: target) { session.fieldWants(for: key, given: $0) }
        // Translate as You Type's target removed from the settings: the first output language typed text is translated
        // into (else off), before the key.
        if !context.secure, !composer.isComposing { translateModeFollow(services.loadSettings()) }
        if !session.clipboardShown { pastedOver = nil }
        // ⌃V's panel only where the keys it takes can be kept from the app.
        if !context.secure, session.isPasteAnywhere(key) { session.clipboardPanelAllowed = clipboardPanelFits(in: target) }
        let composing = composer.isComposing
        let response = session.handle(.key(key, context))
        keyComposes = response.handled && (composing || composer.isComposing)
        apply(response.outputs, client: client)
        if !context.secure { warmUpScreenshotReading() }  // a command picked with an image on the clipboard: Vision loaded for it
        return response.handled
    }

    /// What the field says around the caret as a key goes down or a modifier changes (`FieldReading.context`).
    @MainActor
    private func fieldContext(in target: IMKTextInput?, wants: (FieldContext) -> FieldContext.Parts) -> FieldContext {
        fieldReading.context(in: target, wants: wants)
    }

    /// How this controller reads the field (`FieldReading`): secure input as the session's services and this Mac tell it,
    /// a password field as Accessibility does, asked off the main thread before the read after a pause
    /// (`readFieldAfterPause`; unknown here), the selection Accessibility may tell after the key (`SelectedText`, not in
    /// the self-test: `selectionByAccessibility`).
    @MainActor
    var fieldReading: FieldReading {
        FieldReading(isTerminal: Self.isTerminal(app:), secureInputActive: services.secureInputActive,
                     blocksComposing: SecureInput.blocksComposing, passwordField: { nil },
                     selectionMayBeUntold: selectionByAccessibility ? { SelectedText.mayBeUntold(in: $0, chromium: $1) } : nil,
                     chromiumApp: chromiumApp)
    }

    /// The field a key or a modifier change comes from (its app asked of the client once).
    static func fieldInfo(_ client: IMKTextInput?) -> FieldInfo {
        FieldReading.fieldInfo(client, isTerminal: isTerminal(app:))
    }

    /// `range` as UTF-16 offsets; nil for a field that tells none.
    static func range(_ range: NSRange) -> Range<Int>? { FieldReading.range(range) }

    /// What is right before the caret, as `target` tells it (`FieldContext.BeforeCaret`).
    static func beforeCaret(in target: IMKTextInput?) -> FieldContext.BeforeCaret { FieldReading.beforeCaret(in: target) }

    /// Types with the keyboard layout of the input language in effect: French with its own (AZERTY by
    /// default, `Config.keyboardLayouts`), the others with the one the user picked in the system (or for
    /// English). macOS translates the keys with it for this text field, typing and shortcuts alike.
    @MainActor
    private func applyKeyboardLayout(config: Config? = nil, client: IMKTextInput? = nil) {
        let config = config ?? services.loadSettings()
        let language = composer.inputLanguage
        let id = config.keyboardLayout(for: language.isLatin ? language : .english) ?? Self.systemLayoutID
        guard let id, id != appliedLayout, let target = client ?? clientOverride ?? self.client() else { return }
        target.overrideKeyboard(withKeyboardNamed: id)
        appliedLayout = id
    }

    /// The layout the user types Latin letters with in the system's input sources (U.S., ABC, AZERTY …).
    private static var systemLayoutID: String? {
        TISCopyCurrentASCIICapableKeyboardLayoutInputSource().flatMap { KeyboardLayout(source: $0.takeRetainedValue())?.id }
    }

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyModifiers { MacKeyEvents.modifiers(flags) }

    /// Device-dependent bits of NSEvent.modifierFlags (`MacKeyEvents`).
    static let leftOptionBit = MacKeyEvents.leftOptionBit, rightOptionBit = MacKeyEvents.rightOptionBit


    // MARK: - Outputs

    /// Does what the session answered, in order, in `client` (the field of the key; nil: the one being typed in).
    /// The session's outputs, done in `client`. `keyComposes`: they answer a key the session took that types what is being
    /// written, or ends it (a letter of pinyin, ⌫ in it, Space or a digit picking a candidate, a key of a command's draft).
    /// Nothing is marked in the field for it (`InputSession+Preedit.swift`), so the key is kept from apps that act on a
    /// key the input method took when nothing is marked during it, as a key the rows take is (`rowByKey`): Chromium's
    /// pages and Electron's apps (`marksRow`), terminals (`keepFromTerminal`).
    @MainActor
    func apply(_ outputs: [SessionOutput], client: IMKTextInput?) {
        let keyComposes = self.keyComposes
        self.keyComposes = false
        let target: IMKTextInput? = client ?? clientOverride ?? self.client()
        // What the next `replace` must take out (`checkNextReplace`): a row in the token's place.
        var check: ReplacementCheck?
        // A row the key being answered put in (`rowByKey`), or what a key that composes puts in (`keyComposes`), until what
        // puts it in: whether it goes in as marked text.
        var rowByKey: Bool? = keyComposes ? composingKeyMarks(in: target) : nil
        // The rows took the key and put nothing in (`rowsTookKey`): whether the key is kept from the app (`markBeforeCaret`).
        var keepKey = false
        // The rows (suggestions', clipboard history's) took the key, or it composes, whatever it puts in: in a terminal it
        // is kept from the shell below (`keepFromTerminal`).
        var tookKey = keyComposes
        insertedDuringKey = false
        // ⌃V opening clipboard history's panel (its read of the clipboard), and whether the panel changed yet: a row of it
        // goes in before it hides; a key that hides it and goes on puts its text in after.
        var opensHistory = false, panelChanged = false
        for output in outputs {
            switch output {
            case .rowByKey:
                tookKey = true
                rowByKey = marksRow(in: target)
                if rowByKey == false {
                    let why = target.map { Self.isTerminal($0) ? "a terminal" : hasMarkedText ? "marked text of ours in the field" : "an app that doesn't give it the key" } ?? "no field"
                    log.notice("a row put in by a key: inserted, as 0.6.7.1 did (\(why, privacy: .public))")
                }
            case .rowsTookKey:
                tookKey = true
                keepKey = marksRow(in: target)
            case let .commit(text):
                if !panelChanged, let target, let range = takePastedOver(in: target) {
                    // A row of clipboard history's panel in place of the selection it opened over, marked during its key.
                    if rowByKey == true {
                        markRow(text, replacing: range, in: target, for: "a row put in by a key over a selection")
                    } else {
                        insert(text, into: target, replacing: range)
                    }
                } else if rowByKey == true, let target, text.utf16.count < 2 {
                    markRow(text, replacing: nil, in: target, for: "a row put in by a key")
                } else {
                    if rowByKey == true {
                        log.notice("what a key put in, in a Chromium or Electron app: inserted during the key (\(text.utf16.count, privacy: .public) UTF-16 units: the page has the key as the input method's)")
                    }
                    insert(text, into: target)
                }
                rowByKey = nil
            case let .commitAfterKey(text):
                // Once this key is done: a terminal would send what is inserted during it in the key's place.
                let session = fieldSession
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.fieldSession == session else { return }
                    self.insert(text, into: target)
                }
            case let .checkNextReplace(next):
                check = next
            case let .replace(text, range):
                if let next = check, let range, let target {
                    replaceToken(text, range: range, check: next, marking: rowByKey == true, in: target)
                } else {
                    target?.insertText(text, replacementRange: range.map { NSRange(location: $0.lowerBound, length: $0.count) } ?? Self.notFound)
                }
                (check, rowByKey) = (nil, nil)
            case let .typeOut(text):
                if let target { typeOut(text, into: target) }
            case let .moveCaret(back, inserted):
                // A result being typed out: once it's all in; a row marked during the key: once it's committed.
                if isTypingOut {
                    caretAfterTyping = back
                } else if markedRow != nil {
                    markedRow?.caret = (back, inserted)
                } else {
                    moveCaret(back: back, after: inserted, in: target)
                }
            case let .panel(model):
                panelChanged = true
                showPanel(model, target)
            case let .notice(text):
                // Its own small panel, under Translate as You Type's chip if it's on here.
                if !showTranslateChip(target), let target {
                    // The wheel over it is this field's: no pointer use in it (GitHub #66).
                    let panel = CandidatePanel.shared
                    panel.take(by: self, .session({ [weak self] in self?.received($0) }))
                    show(.notice(text), anchoredIn: target)
                }
            case let .noticeElsewhere(text, long, progress):
                // In the field being typed in now, else near the pointer; the progress notice here goes.
                let field = Self.activeController
                if field !== self, let progress { endNotice(progress) }
                if let field { field.showNotice(text, client: nil, long: long) } else { Self.showLooseNotice(text, long: long) }
            case let .open(item):
                openItem(item)
            case let .openAgent(id):
                openAgent(id)  // in Terminal
            case let .openSettings(place):
                switch place {
                case .translationLanguages?: openSettings(SettingsSpot.outputLanguages.page, .outputLanguages)  // its Add… outlined
                case .weekStats?: openSettings(.week, nil)  // `@stats`
                case nil: SettingsWindow.shared.show()
                }
            case let .copy(text):
                copyText(text)
            case let .readClipboard(id):
                if id < 0 { opensHistory = true }
                // After the key has been answered: if macOS asks whether this may read the clipboard, the app isn't left
                // waiting for the key (and doesn't paste on its own meanwhile).
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    // Nothing is read during secure input.
                    let content = self.services.secureInputActive() ? .none : id < 0 ? self.peekClipboard() : self.readClipboard()
                    // Only how much: never the text or the image itself.
                    log.notice("clipboard for \(id < 0 ? "clipboard history" : "a command", privacy: .public): \(Self.logged(content), privacy: .public)")
                    self.received(.clipboard(content, id: id))
                }
            case .keyboardLayout:
                applyKeyboardLayout(client: target)
                // The menu bar icon shows Code's mark while the field being typed in is in Code.
                if Self.activeController === self { MenuBarIcon.shared.setCode(composer.coding ? composer.messages.codeMode : nil) }
            case let .readField(id, focus):
                readFieldAfterPause(id: id, in: target, focus: focus)
            case let .readPasswordField(focus):
                readPasswordField(focus: focus, in: target)
            case let .readSelection(id):
                readSelectionAfterKey(id: id)
            case let .ghost(text):
                showGhost(text, in: target)
            case let .startTimer(.notice(token), seconds):
                // In the run loop's default mode, as a notice always expired: not while a menu is tracked.
                let box = WeakBox(self)
                let timer = Timer(timeInterval: seconds, repeats: false) { _ in
                    MainActor.assumeIsolated { box.value?.received(.timer(.notice(token))) }
                }
                RunLoop.main.add(timer, forMode: .default)
            case let .startTimer(id, seconds):
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.received(.timer(id)) }
            case let .platform(.startVoice(id, language)):
                startVoice(id: id, language: language)
            case let .platform(.stopVoice(id)):
                stopVoice(id: id)
            case let .platform(.cancelVoice(id)):
                cancelVoiceSession(id: id)
            case .platform(.passPasteKey):
                // Once this key is done: the app's own paste (clipboard history's image on the clipboard, ⌃V again): ⌃V in a
                // terminal or a code editor (Claude Code's image paste, vim's and the shell's ⌃V), ⌘V in any other app
                // (0.6.8.2: Slack's and WeChat's ⌃V paste nothing).
                let pass = Self.pastesOnControlV(target) ? passPasteKey : passCommandV
                DispatchQueue.main.async { pass() }
            case let .platform(.pasteImage(id)):
                pasteKeptImage(id, into: target)
            case .platform(.copyWeekStatsImage):
                // `@stats`'s ⌘C: the week's picture, as Settings → This Week copies it; the session says it's copied once
                // it is on the clipboard, or that it couldn't be: in this field only, nowhere once it was left.
                let asked = fieldSession
                copyWeekStatsImage { [weak self] copied in
                    guard let self, self.fieldSession == asked else { return }
                    self.apply(self.session.weekStatsImageCopied(copied), client: nil)
                }
            case let .platform(.setCapsLock(on)):
                setCapsLock(on)  // a press of Caps Lock, the switch key, switched the language: its lock off again
            }
        }
        // A row the key put in that adds nothing, a key the rows took that puts nothing in (↓ ↑ → Esc): the key is still the
        // input method's.
        if rowByKey == true, !keepKey, let target { markKeyAddingNothing(in: target, composes: keyComposes) }
        if keepKey, let target, case let .selection(range, text)? = markBeforeCaret(in: target, for: "a key the rows took"),
           opensHistory {
            pastedOver = (range, text, fieldSession)
        }
        if tookKey, let target { keepFromTerminal(target) }
        keepAlive = session.waitsForPage ? self : nil
        if composer.translateMode != nil { scheduleChipRefresh() }  // Translate as You Type's chip follows the caret
    }

    /// A row in the token's place (0.6.7.1 §1): the field's text in `range` read back first (`attributedSubstring`), and
    /// replaced only where it is the token the session expects there; else (a click or a drag moved things since the
    /// key that told the range, a page that told its selection late) what a plain insertion would put in goes in at the
    /// caret. Only how long the range is, and which was done, are logged: never the text. `marking`: a row a key put in,
    /// in a Chromium or Electron app, marked during the key in the token's place (`markRow`); else inserted with its
    /// range, as 0.6.7.1 did.
    @MainActor
    private func replaceToken(_ text: String, range: Range<Int>, check: ReplacementCheck, marking: Bool, in target: IMKTextInput) {
        let what = "a row put in by a key"
        let replaced = check.apply(text, range: range,
                                   read: { target.attributedSubstring(from: NSRange(location: $0.lowerBound, length: $0.count))?.string },
                                   replace: { text, range in
                                       let range = NSRange(location: range.lowerBound, length: range.count)
                                       if marking { markRow(text, replacing: range, in: target, for: what) } else { target.insertText(text, replacementRange: range) }
                                   },
                                   insert: { text in
                                       if marking, text.utf16.count < 2 { markRow(text, replacing: nil, in: target, for: what) } else { insert(text, into: target) }
                                   })
        guard !replaced else { return }
        if marking, check.otherwise.isEmpty { markBeforeCaret(in: target, for: what + ", adding nothing") }
        let instead = check.otherwise.isEmpty ? "nothing" : "its plain insertion"
        log.notice("a row didn't take the token's place: other text in its range now (\(range.count, privacy: .public) UTF-16 units); \(instead, privacy: .public) put in instead")
    }

    /// What a key the rows took puts in, in an app built on Chromium or Electron (`marksRow`): a row in place of `range`
    /// (nil: at the caret), or the token's last character again in its own place (`markBeforeCaret`), as marked text
    /// during the key, committed once it's done (`commitRow`). Chromium's view (Slack, Chrome, Google Docs, every Electron
    /// app) gives the page the key as the input method's ("Process", 229) only while there is marked text, or when more
    /// than one character goes in during the key with no range; a replacement (text in with its range), a single
    /// character and nothing go in as they come, and the page gets the key itself: Return sent Slack's message with the
    /// row in it, ↑ moved its caret into the conversation (the Electron harness measured each). A longer plain insertion
    /// goes in as before; so does a click on a row (no key). Where the field then says its marked text is
    /// (`markedRange`) isn't asked: Chromium's view tells another place during the key even where it marked the text as
    /// asked, and 0.6.7.2, which took it out again for that and put the row in with its range, had Slack send the
    /// message. Nothing is taken out during the key. `what` the log says it is; only lengths are logged, never the text.
    @MainActor
    func markRow(_ text: String, replacing range: NSRange?, in client: IMKTextInput, for what: String, takenOut: Bool = false) {
        let length = (text as NSString).length
        client.setMarkedText(text, selectionRange: NSRange(location: length, length: 0), replacementRange: range ?? Self.notFound)
        markedRow = MarkedRow(text: text, client: client, fieldSession: fieldSession, takenOut: takenOut)
        DispatchQueue.main.async { [weak self] in self?.commitRow() }
        let place = range.map { " in place of \($0.length)" } ?? " at the caret"
        log.notice("\(what, privacy: .public): marked until the key is done (\(length, privacy: .public) UTF-16 units\(place, privacy: .public))")
    }

    /// The row marked during its key (`markRow`) committed, and a snippet's caret moved in it (`moveCaret`): on the run
    /// loop's next turn, or first thing for anything that reaches this controller before (a key, a modifier change, the
    /// session's work, the app wanting everything in, another field). Only in the field session it went into, as
    /// `commitAfterKey`; each way out of it commits the row first, so nothing of it is left marked there.
    @MainActor
    func commitRow() {
        guard let row = markedRow else { return }
        markedRow = nil
        guard row.fieldSession == fieldSession else { return }
        if row.takenOut {
            row.client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: Self.notFound)
        } else {
            row.client.insertText(row.text, replacementRange: Self.notFound)
        }
        if let caret = row.caret { moveCaret(back: caret.back, after: caret.after, in: row.client) }
    }

    /// A key the rows took that puts nothing in (↓ ↑ → Esc, ⌃V opening clipboard history, a row that adds nothing: it is
    /// what was typed), in an app built on Chromium or Electron (`marksRow`): what is there marked in its own place and
    /// committed as it was once the key is done (`markRow`), so the page doesn't act on the key either (the harness: 229,
    /// its text as it was), as `ChromiumApps.keyMark` tells it. The selection itself (clipboard history opens with nothing
    /// composed, over a selection to replace: the caret is after it then, `pastedOver`); else the character before the
    /// caret, the token's last, whole (an emoji's surrogate pair, a letter with its accents); with nothing before the caret
    /// (an empty field, where clipboard history's panel shows: Slack's ↑ there edits the last message), a space marked at
    /// the caret and taken out again once the key is done (the harness: 229, nothing acted on, the field as it was). Where
    /// the field tells no caret or reads nothing back, nothing (said in the log, `what` the key): ⌃V doesn't open the panel
    /// there (`clipboardPanelFits`).
    @MainActor @discardableResult
    func markBeforeCaret(in client: IMKTextInput, for what: String) -> ChromiumApps.KeyMark? {
        let mark = Self.keyMark(in: client)
        switch mark {
        case let .selection(range, text)?:
            markRow(text, replacing: range, in: client, for: what + " over a selection")
        case let .character(range, text)?:
            markRow(text, replacing: range, in: client, for: what)
        case .space?:
            markRow(" ", replacing: nil, in: client, for: what + " at the field's start", takenOut: true)
        case nil:
            log.notice("\(what, privacy: .public) in a Chromium or Electron app: nothing marked (the field tells no caret, or doesn't read back what is there)")
        }
        return mark
    }

    /// What a key would be marked with in `client` (`ChromiumApps.keyMark`), read through IMK.
    @MainActor
    static func keyMark(in client: IMKTextInput) -> ChromiumApps.KeyMark? {
        ChromiumApps.keyMark(caret: client.selectedRange(), read: { client.attributedSubstring(from: $0)?.string })
    }

    /// Whether clipboard history's panel may open in `client` (`InputSession.clipboardPanelAllowed`): everywhere but in an
    /// app built on Chromium or Electron (`marksRow`) whose field tells no caret or doesn't read back what is before it,
    /// where nothing could keep the panel's keys from the page (`markBeforeCaret`); ⌃V is as before 0.6.8 there. Other
    /// fields never needed it.
    @MainActor
    private func clipboardPanelFits(in client: IMKTextInput?) -> Bool {
        guard let client, marksRow(in: client) else { return true }
        guard Self.keyMark(in: client) != nil else {
            log.notice("⌃V in a Chromium or Electron app: no clipboard history here (the field tells no caret, or doesn't read back what is there)")
            return false
        }
        return true
    }

    /// The selection clipboard history's panel opened over (`pastedOver`), once: its range, where it is still right before
    /// the caret as it was (else nil, and the row goes in at the caret).
    @MainActor
    private func takePastedOver(in client: IMKTextInput) -> NSRange? {
        guard let over = pastedOver else { return nil }
        pastedOver = nil
        let caret = client.selectedRange()
        guard over.fieldSession == fieldSession, caret.location == NSMaxRange(over.range), caret.length == 0,
              client.attributedSubstring(from: over.range)?.string == over.text else {
            log.notice("a row of clipboard history: the selection its panel opened over changed since; at the caret instead")
            return nil
        }
        return over.range
    }

    // MARK: - Voice

    @MainActor
    private func startVoice(id: Int, language: Language) {
        // Voice input is off for now (`Features.voiceInput`): the session never asks, and the microphone stays untouched.
        guard Features.voiceInput, #available(macOS 26.0, *), VoiceInput.isSupported else {
            received(.voice(.failed(UIText.describe(VoiceError.unsupportedSystem), id: id)))
            return
        }
        if voiceFile == nil {
            guard Self.microphoneAllowed else {
                received(.voice(.failed(tr("（自检）没有音频文件，不使用麦克风", "(self-test) no audio file; the microphone stays off"),
                                        id: id)))
                return
            }
            switch VoiceInput.microphoneAccess {
            case .granted:
                break
            case .notDetermined:
                received(.voice(.failed(tr("请在弹窗里允许使用麦克风，然后再按住右 ⌥ 说话",
                                           "Allow the microphone in the dialog, then hold right ⌥ again"), id: id)))
                Task { _ = await VoiceInput.requestMicrophoneAccess() }
                return
            case .denied:
                received(.voice(.failed(tr("没有麦克风权限：系统设置 → 隐私与安全性 → 麦克风 → 打开 AllInOneIME",
                                           "No microphone access: System Settings → Privacy & Security → Microphone → turn on AllInOneIME"),
                                        id: id)))
                return
            }
        }
        if let progress = VoiceInput.downloads[language] {
            received(.voice(.failed(String(format: tr("%@语音模型下载中 %.0f%%，好了会提示",
                                                      "Downloading the %@ speech model: %.0f%%. You'll be told when it's ready"),
                                           UIText.name(language), progress * 100), id: id)))
            return
        }
        cancelVoiceSession()  // never two recordings at once
        let session = DictationSession(
            id: id, language: language,
            onText: { [weak self] text in self?.received(.voice(.text(text, id: id))) },
            onFinish: { [weak self] result in
                self?.voiceDidFinish(result, id: id, language: language)
            })
        voiceSession = session
        log.notice("voice \(id) started (\(language.rawValue, privacy: .public))")
        session.start(source: voiceFile.map { .file($0.url, speed: $0.speed) } ?? .microphone)
    }

    @MainActor
    private func stopVoice(id: Int) {
        guard #available(macOS 26.0, *), let session = voiceSession as? DictationSession, session.id == id else { return }
        session.stop()
        scheduleVoiceFallback(id: id, heard: composer.voice.text, waited: 0)
    }

    /// If recognition never finishes, keep what was heard so far. While text is still coming in
    /// (e.g. the model was loading when the key was released) it waits longer, up to 20 s.
    @MainActor
    private func scheduleVoiceFallback(id: Int, heard: String, waited: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.composer.voice.id == id else { return }
            let now = self.composer.voice.text
            if now != heard || now.isEmpty, waited < 15 {
                self.scheduleVoiceFallback(id: id, heard: now, waited: waited + 5)
                return
            }
            log.error("voice \(id): no final transcript after \(waited + 5)s")
            self.cancelVoiceSession(id: id)
            self.received(.voice(.finished(now, id: id)))
        }
    }

    /// Stops the recording `id` (any recording when nil) and discards its result.
    @MainActor
    private func cancelVoiceSession(id: Int? = nil) {
        guard #available(macOS 26.0, *), let session = voiceSession as? DictationSession,
              id == nil || session.id == id else { return }
        session.cancel()
        voiceSession = nil
    }

    @MainActor
    private func voiceDidFinish(_ result: Result<String, Error>, id: Int, language: Language) {
        if #available(macOS 26.0, *), (voiceSession as? DictationSession)?.id == id { voiceSession = nil }
        switch result {
        case let .success(text):
            log.notice("voice \(id) finished (\(text.count) chars)")
            received(.voice(.finished(text, id: id)))
        case let .failure(VoiceError.modelMissing(missing)):
            let name = UIText.name(missing)
            received(.voice(.failed(tr("首次使用：正在下载\(name)语音模型，好了会提示",
                                       "First use: downloading the \(name) speech model. You'll be told when it's ready"),
                                    id: id)))
            VoiceInput.startDownload(missing) { [weak self] error in
                self?.showNotice(error.map { tr("语音模型下载失败：", "Speech model download failed: ") + UIText.describe($0) }
                                 ?? tr("\(name)语音模型已就绪：按住右 ⌥ 说话", "\(name) speech model ready: hold right ⌥ to talk"),
                                 client: nil)
            }
        case let .failure(error):
            log.error("voice \(id) failed: \(String(describing: error), privacy: .public)")
            received(.voice(.failed(UIText.describe(error), id: id)))
        }
    }

    /// The length of the app's marked text, or nil when it reports none.
    static func markedLength(_ client: IMKTextInput) -> Int? { FieldReading.markedLength(client) }

    /// Whether `client` is a terminal, which runs every line it is given.
    static func isTerminal(_ client: IMKTextInput?) -> Bool {
        isTerminal(app: client?.bundleIdentifier())
    }

    /// Whether `app` (a bundle id) is a terminal.
    static func isTerminal(app: String?) -> Bool {
        app.map(SecureInput.terminals.contains) ?? false
    }

    // MARK: - Candidate panel

    /// Where a panel of ours goes in `client` (`PanelAnchor`): the rect it tells (`toldAnchor`) where it is one to trust;
    /// else the caret Accessibility tells, the last rect to trust in this field, or the rect as told, and then the field
    /// is asked again a moment later (`reaskAnchor`). Said in the log, numbers only (`log stream --predicate 'subsystem
    /// == "com.allinoneime.inputmethod.AllInOneIME" AND eventMessage BEGINSWITH "panel anchor"'`).
    @MainActor
    func anchor(_ client: IMKTextInput) -> NSRect {
        (anchorToken, placements) = (anchorToken + 1, placements + 1)
        let placing = placements
        // The field's app, asked of the client once.
        let app = client.bundleIdentifier()
        // Copies: asking the field (and Accessibility) below waits on the app, running the run loop, and a key handled
        // meanwhile places the panel too, writing these; an access held open across that crashed the input method.
        var (memory, lastByApp) = (panelAnchor, Self.lastAnchorByApp)
        // The field by this controller and its focus session: the client object handed over may be another proxy each time.
        let field = PanelAnchor.Field(client: ObjectIdentifier(self), app: app, session: fieldSession)
        memory.enter(field)
        // The window's frame once in the field (a rect on its left edge near its top is the page's corner, `PanelAnchor`):
        // as the window server lists it, else Accessibility's once it is in (`windowFrame`).
        if clientOverride == nil, !session.secureInputActive(), let app {
            memory.learnWindow { windowFrame(in: app, for: field, client: client) }
        }
        var asked = "Accessibility not asked"
        // Where the field puts it (`FieldAnchor.place`): the rect it tells, else Accessibility's caret, the last rect to
        // trust in the field or the app, the pointer, the rect as told.
        let placed = FieldAnchor.place(in: client, app: app, selection: composer.selection?.range, memory: &memory,
                                       lastByApp: &lastByApp, screens: NSScreen.screens.map(\.frame),
                                       pointer: { NSEvent.mouseLocation }) { needsPage in
            // Never read with the key: the last read in this field meanwhile, the panel placed again by the next (`accessibilityCaret`).
            let read = accessibilityCaret(in: app, page: needsPage, field: field, client: client)
            asked = read == nil ? "Accessibility read after the key" : read?.timedOut == true ? "Accessibility timed out"
                : read?.caret == nil ? "Accessibility told no caret" : "Accessibility's caret"
            return read
        }
        let (told, placement) = (placed.told, placed.placement)
        // A placement came in while the field was asked: it holds what's newer, and asks the field again itself.
        guard placements == placing else { return placement.rect }
        learnWindowTold(into: &memory, field: field, client: client)
        // Only this app's entry, and only where this placement trusted the field's rect (`FieldAnchor.place` keeps it then)
        // or dropped it, on no screen now, and it is still that one: the dictionary is every controller's, and another
        // may have written it meanwhile.
        (panelAnchor, Self.lastAnchorByApp[app ?? ""]) = (memory, placement.source == .field ? placement.rect : Self.lastAnchorByApp[app ?? ""].flatMap { $0 == placed.dropped ? nil : $0 })
        guard placement.reasks else {
            anchorSaid = nil
            // Every placement, numbers only (`log stream --level debug --predicate 'subsystem ==
            // "com.allinoneime.inputmethod.AllInOneIME" AND eventMessage BEGINSWITH "panel anchor"'`): what Google Docs told.
            log.debug("""
                panel anchor trusted: told \(Self.describe(told), privacy: .public), line \(Self.describe(self.toldAnchor(client)), privacy: .public), \
                caret \(Self.describe(FieldAnchor.caretRect(client)), privacy: .public), window \(Self.describe(self.panelAnchor.window), privacy: .public), \
                page \(Self.describe(self.panelAnchor.page), privacy: .public), screen \(Self.describe(NSScreen.screens.first?.frame), privacy: .public)
                """)
            return placement.rect
        }
        // Once while the field tells the same (an app that never tells a rect to trust would have it said at every key).
        let said = "\(Self.describe(told)) \(placement.source.rawValue) \(Self.describe(placement.rect))"
        if said != anchorSaid {
            anchorSaid = said
            log.notice("""
                panel anchor not trusted in \(app ?? "", privacy: .private): told \(Self.describe(told), privacy: .public), \
                caret \(Self.describe(FieldAnchor.caretRect(client)), privacy: .public), window \(Self.describe(self.panelAnchor.window), privacy: .public); \
                \(placement.source.rawValue, privacy: .public) used, \(Self.describe(placement.rect), privacy: .public) (\(asked, privacy: .public)), \
                pointer \(Self.describe(NSRect(origin: NSEvent.mouseLocation, size: .zero)), privacy: .public)
                """)
        }
        reaskAnchor(client)
        return placement.rect
    }

    @MainActor
    func showPanel(_ model: PanelModel?, _ client: IMKTextInput?) {
        // Nothing to show: Translate as You Type's chip, if it's on here; its list of languages over anything else.
        guard let model, let client, !translateChipListShown else {
            if !showTranslateChip(client) { hidePanelIfOwned() }
            return
        }
        let panel = CandidatePanel.shared
        panel.take(by: self, .session({ [weak self] in self?.received($0) }, rows: true,
                                      chip: { [weak self] part in self?.translateChipClicked(part) }))
        show(model, anchoredIn: client)
        hideGhostBehindRows()
    }

    /// The panel as the composer has it now, in `client`.
    @MainActor
    func showPanel(_ client: IMKTextInput?) {
        showPanel(composer.wantsPanel ? session.panelModel() : nil, client)
    }

    @MainActor
    private func hidePanelIfOwned() {
        let panel = CandidatePanel.shared
        if panel.owner == nil || panel.owner === self {
            panel.hide()
        }
    }

    /// Short status message ("英" English mode, "已复制" copied, …): its own small panel when nothing else is shown,
    /// otherwise the right side of the footer (`InputSession.showNotice`). `long`: something the user has to act on (a
    /// permission), up longer; `lasting`: up this long instead, unless another notice replaces it first.
    @MainActor
    func showNotice(_ text: String, client: IMKTextInput?, long: Bool = false, lasting: TimeInterval? = nil) {
        apply(session.showNotice(text, long: long, lasting: lasting), client: client)
    }

    /// Takes `text` down if it is still the notice here: a save's progress, once its outcome is told in another
    /// text field.
    @MainActor
    func endNotice(_ text: String) {
        apply(session.endNotice(text), client: nil)
    }

    /// The candidate panel for the composer as it is now (`InputSession.panelModel`).
    @MainActor
    func panelModel() -> PanelModel { session.panelModel() }

    /// The longest 「正在存到备忘录…」 / 「正在加到提醒事项…」 stays up (`InputSession.progressNoticeLimit`; the self-test
    /// shortens it).
    static var progressNoticeLimit: TimeInterval {
        get { InputSession.progressNoticeLimit }
        set { InputSession.progressNoticeLimit = newValue }
    }

    /// Error category without any server-provided text (safe for the public log): this Mac's own, else the core's.
    static func errorKind(_ error: Error) -> String { SessionServices.macErrorKind(error) ?? InputSession.errorKind(error) }

    /// Owns the candidate panel while it shows a notice no text field is there for.
    private static let looseNoticeOwner = NSObject()

    /// A notice with no text field to show it at: on its own, near the pointer.
    @MainActor
    static func showLooseNotice(_ text: String, long: Bool) {
        let panel = CandidatePanel.shared
        panel.take(by: looseNoticeOwner, .none)  // no text field's
        panel.show(.notice(text), anchor: .zero)  // an empty anchor: at the mouse pointer
        DispatchQueue.main.asyncAfter(deadline: .now() + SessionText.noticeDuration(text, long: long)) {
            if panel.owner === looseNoticeOwner { panel.hide() }
        }
    }
}
