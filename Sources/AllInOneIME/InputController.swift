import AllInOneIMECore
import AllInOneIMEMac
import AllInOneIMERime
import AppKit
import Carbon
import InputMethodKit
import os

let log = Logger(subsystem: "com.aipinyin.inputmethod.AIPinyin", category: "ime")

/// One converter (one URLSession, one cache) shared by every input session in the process.
let sharedConverter = Converter()

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
    /// Whether the app still has the text being typed (Slack may take it into a mention on its own).
    private var markedWatch = MarkedTextWatch()
    /// Whether this text session has delivered a key yet (logged once, without the key).
    private var receivedKeys = false
    /// Whether the selection may be read with Accessibility when the field doesn't say (`SelectedText`). False in the
    /// self-test: it would reach the user's own frontmost app.
    var selectionByAccessibility = true
    /// Only set by the self-test: IMK refuses to create a controller for anything but its own
    /// client proxies, so the test injects its fake text field here.
    var clientOverride: IMKTextInput?
    /// Keeps the app a text field became active in, for Settings → Apps' "Add App…" (the self-test keeps none).
    var recordApp: (String) -> Void = { app in MainActor.assumeIsolated { RecentApps.record(app) } }
    /// Opens an `@open` result: a web address in the default browser, anything else as a file (the self-test opens
    /// nothing).
    var openItem: (String) -> Void = {
        NSWorkspace.shared.open(SearchResult(name: "", path: $0).webURL ?? URL(fileURLWithPath: $0))
    }
    /// Opens a background `@agent` task (Claude Code's) in Terminal.
    var openAgent: (String) -> Void = { id in MainActor.assumeIsolated { AgentMonitor.shared.open(id) } }
    /// Opens the settings window on `page`, pointing at `spot` there if given (the self-test records it instead).
    var openSettings: @MainActor (SettingsPage, SettingsSpot?) -> Void = { SettingsWindow.shared.show(page: $0, spot: $1) }
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
    /// Whether a draft started with an image on the clipboard warms Vision up (`warmUpScreenshotReading`; not in the
    /// self-test: it would look at the real clipboard's types).
    var warmsUpVision = true
    /// The keyboard layout this text field was last told to type with (`applyKeyboardLayout`).
    private var appliedLayout: String?
    /// The recording in progress (a `DictationSession`, which needs macOS 26).
    private var voiceSession: AnyObject?
    /// Self-test only: recognize this audio file instead of the microphone.
    var voiceFile: (url: URL, speed: Double)?
    /// False in the self-test: the microphone (and its permission prompt) is never touched.
    static var microphoneAllowed = true
    /// Whether marked text this controller set may be in the document. Empty marked text is only sent
    /// to clear it: with nothing marked, NSTextView puts (empty) marked text in place of the selection,
    /// deleting the selected text (a Shift tap, a focus change).
    private var hasMarkedText = false
    /// Kept while the session waits for a web page a request takes along (`InputSession.waitsForPage`): the request
    /// starts even if the field is gone by then.
    private var keepAlive: AllInOneIMEInputController?
    /// Counts autocomplete's suggestions shown and taken down: a placement that comes after a newer one does nothing
    /// (`showGhost`); the suggestion is a line of the candidate panel (`placeGhost`).
    var ghostToken = 0
    var ghostInPanel = false
    /// The self-test's say whether the field is a password field, as autocomplete's read asks Accessibility
    /// (`passwordFieldByAccessibility`): its harness field is never the one focused. Nil: Accessibility's.
    var passwordField: (@MainActor () -> Bool)?
    /// The field's frame the suggestion is cut at (`placeGhost`), asked once a suggestion (nil: not yet; .some(nil): not
    /// known); the self-test's own (`fieldFrame`: its harness field isn't the one focused), else Accessibility's.
    var ghostField: NSRect??
    var fieldFrame: (@MainActor () -> NSRect?)?

    static let notFound = NSRange(location: NSNotFound, length: NSNotFound)

    /// The session, with this Mac's services and those that ask this controller (the page, the keyboard layout, pasting
    /// into a terminal, Translate as You Type's chip). Its work answers on the main queue: here while this controller is
    /// there, else where a save's outcome or a notice still has to go (`receivedAfterClose`).
    private func makeSession() -> InputSession {
        let box = WeakBox(self)
        var services = MainActor.assumeIsolated { MainThreadBox(SessionServices.mac) }.value
        services.pastesInTerminal = { MainActor.assumeIsolated { box.value?.canPasteInTerminal() ?? false } }
        services.keyTranslator = {
            MainActor.assumeIsolated { box.value?.appliedLayout.flatMap(KeyboardLayout.init(id:)) ?? KeyboardLayout.current() }
        }
        services.translateChip = { MainActor.assumeIsolated { box.value?.translateChip() } }
        // Autocomplete: what it learns and counts, one for every field; an app's name for what it says of the app.
        services.autocomplete = MainActor.assumeIsolated { MainThreadBox(AutocompleteSwitch.store) }.value
        // Suggestions: one store for every field, the coding packs installed, and Translate as You Type the input method's
        // (this field turns it on and off for the session's long press of Shift).
        services.suggestions = MainActor.assumeIsolated { MainThreadBox(SuggestionsShared.services(field: box)) }.value
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
        apply(session.handle(event).outputs, client: nil)
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

    // MARK: - IMK entry points

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else { return false }
        let client = sender as? IMKTextInput
        switch event.type {
        case .keyDown:
            return MainActor.assumeIsolated { handleKeyDown(event, client: client) }
        case .flagsChanged:
            MainActor.assumeIsolated { handleFlagsChanged(event, client: client) }
            return false  // the application must see modifier changes too
        default:
            return false
        }
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        MainActor.assumeIsolated {
            markedWatch.reset()  // another text field, maybe another app
            hasMarkedText = false
            appliedLayout = nil  // the layout is told to each text field
            fieldSession += 1
            Self.activeController = self
            let app = (sender as? IMKTextInput)?.bundleIdentifier()
            if let app { recordApp(app) }
            // The app's own starting language, rewrite styles, typing out (`AppProfile`); a terminal pastes on ⌘V itself.
            let field = FieldInfo(app: app, terminal: app.map(SecureInput.terminals.contains) ?? false)
            apply(session.handle(.focus(field)).outputs, client: sender as? IMKTextInput)
            // Translate as You Type's target removed: the first output language typed text goes into, else off.
            translateModeFollow(services.loadSettings())
            translateModeActivated(app: app)  // another app leaves Translate as You Type, unless it translates always
            // A custom command renamed because a built-in has its name now: said once, last (no notice above covers it)
            apply(session.tellBuiltinRenames(), client: sender as? IMKTextInput)
            // Once a day at most, in the background: comparing two dates here, never on a keystroke.
            UpdateController.shared.checkIfDue()
        }
    }

    override func commitComposition(_ sender: Any!) {
        MainActor.assumeIsolated {
            stopTyping(insertingRest: true)  // the app wants everything in now (a click elsewhere in it)
            apply(session.handle(.commit).outputs, client: sender as? IMKTextInput)
        }
    }

    // MARK: - Typing a result out

    /// How long typing out waits between steps, and its slips (the self-test waits less, and picks them); how fast and
    /// with typos fixed on the way is the session's (`Config.typeOutRate`, `typeOutVaries`, `typeOutMistakes`).
    var typeOutSleep: @Sendable (Double) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    var typeOutRandom: (() -> Double)?
    private var typingTask: Task<Void, Never>?
    /// The plan being typed, and the field it goes into (`TypeOut.Typist`: it keeps the field right while a typo is in it).
    private var typist = TypeOut.Typist([], start: 0)
    private var typingField: TypingField?
    private var typingClient: IMKTextInput? { typingField?.client }
    /// Line breaks go in as a paste (a terminal; `TerminalPaste`).
    private var typingPastes = false
    /// A snippet being typed out: where its caret goes once it's all in (`moveCaret`).
    private var caretAfterTyping: Int?

    /// Whether line breaks can go into a terminal as a paste, and pasting there (`TerminalPaste`; the
    /// self-test supplies its own and never posts keys or touches the clipboard).
    var canPasteInTerminal: @MainActor () -> Bool = { TerminalPaste.isAllowed() }
    var pasteInTerminal: @MainActor (String) async -> Void = { await TerminalPaste.paste($0) }

    /// Inserts `text` into `client`; into a terminal, text with line breaks goes in as a paste, so the
    /// line breaks don't run (or send) anything.
    @MainActor
    private func insert(_ text: String, into client: IMKTextInput?) {
        if text.contains("\n"), Self.isTerminal(client), canPasteInTerminal() {
            let paste = pasteInTerminal
            Task { @MainActor in await paste(text) }
        } else {
            client?.insertText(text, replacementRange: Self.notFound)
            hasMarkedText = false  // the inserted text took the marked text's place
        }
    }

    /// A result in place of the selection the command worked on (`Composer.Effect.replaceSelection`): by its range, which
    /// the text input protocol has fields honor; one that ignores it still has the text selected, and an insert replaces
    /// what is selected. A result that starts with the selection (`@reply`'s, after the message selected) only has the
    /// rest inserted after it (`afterSelection`): the selection is never rewritten, its formatting, links and images kept.
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
    }

    /// What of `text` goes in after `selection` and where (an empty range at its end): `SessionText.afterSelection`.
    static func afterSelection(_ text: String, _ selection: Composer.Selection) -> (String, NSRange)? {
        SessionText.afterSelection(text, selection).map { ($0.text, NSRange(location: $0.at, length: 0)) }
    }

    /// Types `text` into `client` character by character, like a person typing (`TypeOut.plan`), with an
    /// occasional typo fixed on the way (`typeOutMistakes`) where the field can take one back.
    ///
    /// A typo is taken back by replacing its range: `insertText` with a `replacementRange`, which the text input
    /// protocol has every text field honor (NSTextView, WebKit, Chromium and Electron do). Only in a field that
    /// says where its caret is, right where the text typed so far ends, and reads that text back as typed
    /// (`attributedSubstring`); while a typo is in the field, and after each fix, that's checked before every step
    /// (`TypeOut.Typist`). Never in a terminal (keys go to a shell). An app that doesn't keep a fix as asked is
    /// remembered (`TypoMemory`) and gets no typos again. (A ⌫ posted as a key would need the Accessibility
    /// permission and could reach the app after the next character: never here.)
    @MainActor
    private func typeOut(_ text: String, into client: IMKTextInput) {
        stopTyping(insertingRest: true)
        let field = TypingField(client, pastesLineBreaks: text.contains("\n") && Self.isTerminal(client) && canPasteInTerminal())
        typingField = field
        typingPastes = field.pastesLineBreaks
        let caret = field.caret
        let app = client.bundleIdentifier() ?? ""
        let mistakes = session.typeOutMistakes && !Self.isTerminal(client) && !TypoMemory.contains(app) && caret != nil
        // Wrong letters from the keys next to the right one on the keyboard the keys come from (AZERTY, QWERTZ …).
        let layout = appliedLayout.flatMap(KeyboardLayout.init(id:)) ?? KeyboardLayout.current()
        let keyboard = layout.map(TypeOut.Keyboard.init(layout:)) ?? .qwerty
        let random = typeOutRandom ?? { Double.random(in: 0..<1) }
        typist = TypeOut.Typist(TypeOut.plan(for: text, rate: session.typeOutRate, varies: session.typeOutVaries, mistakes: mistakes,
                                             keyboard: keyboard, random: random), start: caret ?? 0, length: field.length)
        let sleep = typeOutSleep
        log.notice("typing out \(text.count) characters (\(self.typist.typing.runs.filter(\.isSlip).count) typos to fix)")
        typingTask = Task { @MainActor [weak self] in
            var waited = false
            while true {
                if !waited, let delay = self?.typist.nextDelay { await sleep(delay) }
                guard let self, !Task.isCancelled, let field = self.typingField else { return }
                let progress = self.typist.step(in: field)
                self.rememberFailure(app)
                if progress == .done { break }
                waited = progress == .waiting
                if waited { await sleep(0.05) }  // the field catching up (Chromium tells its caret late)
                while field.lineBreaks > 0 {
                    field.lineBreaks -= 1
                    await self.pasteInTerminal("\n")
                }
            }
            guard let self, !Task.isCancelled else { return }
            let typedInto = self.typingField?.client
            self.typingTask = nil
            self.typingField = nil
            if let back = self.caretAfterTyping {
                self.caretAfterTyping = nil
                self.moveCaret(back: back, after: text, in: typedInto)
            }
        }
    }

    /// A snippet's `{cursor}` (`Composer.Effect.moveCaret`): the caret goes `back` UTF-16 units into the text just put in.
    /// Only in a field that says where its caret is and has that text right before it; not in a terminal (keys there go
    /// to a shell). Elsewhere the caret stays at the end, as after any result.
    ///
    /// A text view keeps its caret where it is when a range is replaced (`insertText` with a range), so the caret is
    /// moved with marked text, which puts it where it says: empty marked text at the place. Nothing else is tried: where
    /// that doesn't arrive or isn't taken (the input method connection may drop empty text with a range; a browser may
    /// report its caret late), the caret stays at the end, which is harmless. Marking a character of the text instead
    /// could lose or double it where the field's ranges lag behind.
    @MainActor
    func moveCaret(back: Int, after inserted: String?, in client: IMKTextInput?) {
        guard back > 0, let inserted, let client, !Self.isTerminal(client) else { return }
        let caret = client.selectedRange()
        let length = inserted.utf16.count
        guard caret.location != NSNotFound, caret.length == 0, back <= length, caret.location >= length else { return }
        // The end of what was inserted, before the caret (no more than a line or two of it is read back).
        let checked = min(length, 200)
        let expected = String(decoding: inserted.utf16.suffix(checked), as: UTF16.self)
        guard client.attributedSubstring(from: NSRange(location: caret.location - checked, length: checked))?.string == expected else {
            log.notice("caret not moved: the field doesn't have the snippet before its caret")
            return
        }
        let target = caret.location - back
        client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: target, length: 0))
        if client.selectedRange().location != target { log.notice("caret not moved: the field didn't take it; it stays at the end") }
    }

    /// Remembers `app` when its field didn't take a typo's fix (`TypoMemory`): no typos there again.
    @MainActor
    private func rememberFailure(_ app: String) {
        guard typist.fieldFailed, TypoMemory.remember(app) else { return }
        log.error("typing out: \(app, privacy: .public) didn't take a typo's fix (\(self.typist.failure ?? "", privacy: .public)); no typos there again")
    }

    /// Stops typing out: the rest goes in at once, or (Esc, the field lost) isn't typed. Either way a typo still
    /// in the field is taken out first, where it was typed, so it holds the text, or its start.
    @MainActor
    func stopTyping(insertingRest: Bool) {
        guard let task = typingTask else { return }
        task.cancel()
        if let field = typingField {
            // Checked like any fix, waiting a little in between for a field that tells its text late.
            let rest = typist.stop(insertingRest: insertingRest, in: field, wait: { usleep(20_000) })
            rememberFailure(field.client.bundleIdentifier() ?? "")
            if !rest.isEmpty { insert(rest, into: field.client) }
        }
        log.notice("typing out stopped (\(insertingRest ? "the rest inserted" : "the rest dropped"), privacy: .public)")
        (typingTask, typist, typingField, typingPastes) = (nil, TypeOut.Typist([], start: 0), nil, false)
        caretAfterTyping = nil  // a snippet's caret stays at the end
    }

    /// Whether a result is being typed out now (the self-test).
    var isTypingOut: Bool { typingTask != nil }

    override func deactivateServer(_ sender: Any!) {
        MainActor.assumeIsolated {
            stopTyping(insertingRest: false)  // another field has the focus now: the rest isn't typed anywhere
            apply(session.handle(.blur).outputs, client: sender as? IMKTextInput)
            fieldSession += 1
            if Self.activeController === self { Self.activeController = nil }
            hideTranslateChip()  // Translate as You Type's chip is for the field being typed in
        }
        super.deactivateServer(sender)
    }

    override func composedString(_ sender: Any!) -> Any! {
        composer.draftInPanel ? "" : composer.markedText  // a command on the selection is in the panel, not the field
    }

    override func inputControllerWillClose() {
        MainActor.assumeIsolated {
            cancelVoiceSession()
            apply(session.handle(.close).outputs, client: nil)
            hidePanelIfOwned()
            fieldSession += 1  // what is inserted once a key is done goes nowhere now
            if Self.activeController === self { Self.activeController = nil }
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

    @MainActor
    func handleKeyDown(_ event: NSEvent, client: IMKTextInput?) -> Bool {
        // A result still being typed out: Esc stops it there; any other key types the rest at once,
        // then goes on as usual.
        if TerminalPaste.isOurs(event) { return false }  // a line break being pasted into a terminal
        translateModeKeyDown()
        if typingTask != nil {
            if event.keyCode == VirtualKey.escape {
                stopTyping(insertingRest: false)
                return true
            }
            // In a terminal the rest is pasted, after this key would arrive: the key only finishes typing.
            let pastesRest = typingPastes && typist.rest.contains("\n")
            stopTyping(insertingRest: true)
            if pastesRest { return true }
        }
        if !receivedKeys {
            receivedKeys = true
            log.notice("receiving keys (engine ready: \(RimeService.shared.isReady))")
        }
        let target: IMKTextInput? = client ?? clientOverride ?? self.client()
        let key = KeyEvent(keyCode: event.keyCode, usage: MacKeyboard.usage(event.keyCode), characters: event.characters ?? "",
                           charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                           modifiers: Self.modifiers(event.modifierFlags), isRepeat: event.isARepeat)
        let context = fieldContext(for: key, in: target)
        // Translate as You Type's target removed from the settings: the first output language typed text is translated
        // into (else off), before the key.
        if !context.secure, !composer.isComposing { translateModeFollow(services.loadSettings()) }
        let response = session.handle(.key(key, context))
        apply(response.outputs, client: client)
        if !context.secure { warmUpScreenshotReading() }  // a command picked with an image on the clipboard: Vision loaded for it
        return response.handled
    }

    /// The latest time of each modifier change handed over, whatever the text field (a copy may reach another one).
    @MainActor private static var modifierEchoes = ModifierEchoes()

    @MainActor
    func handleFlagsChanged(_ event: NSEvent, client: IMKTextInput?) {
        // Chromium and Electron apps (Slack, VS Code, Chrome) hand every modifier change over twice, the same event,
        // after the next change too when the page is busy: the copy changes nothing, for the session's composer (a tap
        // of Shift or ⌥) and its long press of Shift (Translate as You Type) alike.
        guard !Self.modifierEchoes.isEcho(keyCode: event.keyCode, flags: event.modifierFlags.rawValue,
                                          timestamp: event.timestamp, now: ProcessInfo.processInfo.systemUptime) else {
            // Each copy dropped, how long after the event's time it came (`log stream --level debug --predicate
            // 'subsystem == "com.aipinyin.inputmethod.AIPinyin" AND eventMessage BEGINSWITH "modifier copy"'`): what
            // shows a real app hands the copy over with the event's own time.
            let late = (ProcessInfo.processInfo.systemUptime - event.timestamp) * 1000
            log.debug("""
                modifier copy dropped: key \(event.keyCode, privacy: .public), flags \
                \(event.modifierFlags.rawValue, format: .hex(includePrefix: true), privacy: .public), \
                \(late, format: .fixed(precision: 1), privacy: .public) ms after its time
                """)
            return
        }
        let target: IMKTextInput? = client ?? clientOverride ?? self.client()
        // The key was held up to the event; the pointer is asked later, so look back that much further. fn held with Shift
        // is no long press of it (only the session's long press minds fn).
        var modifiers = Self.flagsChangedModifiers(event.modifierFlags)
        if event.modifierFlags.contains(.function) { modifiers.insert(.function) }
        let change = ModifierChange(key: MacKeyCodes.key(event.keyCode), modifiers: modifiers,
                                    timestamp: event.timestamp, late: max(ProcessInfo.processInfo.systemUptime - event.timestamp, 0))
        var context = FieldContext(field: Self.fieldInfo(target))
        while true {
            let missing = session.fieldWants(forModifiers: change, given: context).subtracting(context.read)
            if missing.isEmpty { break }
            read(missing, of: target, into: &context)
        }
        // The session times a long press of Shift itself: Translate as You Type on or off (not in Code).
        apply(session.handle(.modifiers(change, context)).outputs, client: client)
    }

    /// What the field says around the caret as `key` goes down: what the session wants of it (`fieldWants`), asked again
    /// until it wants nothing more.
    @MainActor
    private func fieldContext(for key: KeyEvent, in target: IMKTextInput?) -> FieldContext {
        var context = FieldContext(field: Self.fieldInfo(target))
        while true {
            let missing = session.fieldWants(for: key, given: context).subtracting(context.read)
            if missing.isEmpty { return context }
            read(missing, of: target, into: &context)
        }
    }

    /// The field a key or a modifier change comes from.
    static func fieldInfo(_ client: IMKTextInput?) -> FieldInfo {
        FieldInfo(app: client?.bundleIdentifier(), terminal: isTerminal(client))
    }

    /// Reads `parts` of what the field says (`FieldContext`). Password fields and prompts turn on secure event input: the
    /// session composes nothing in the app that turned it on. A password field that doesn't is told by Accessibility
    /// (`passwordFieldByAccessibility`), asked only when the session wants it: once a field, where suggestions may show.
    /// The selection is read with Accessibility where the field doesn't tell it (only how it was read and how long it is
    /// are logged); the character before the caret, where "@" is typed; the text around the caret for `@reply`, or a
    /// snippet of more than one line put in (`readFieldText`).
    @MainActor
    private func read(_ parts: FieldContext.Parts, of target: IMKTextInput?, into context: inout FieldContext) {
        if parts.contains(.secure) { context.secure = SecureInput.blocksComposing(target) }
        if parts.contains(.passwordField), !context.secure { context.field?.secure = passwordFieldByAccessibility() }
        if parts.contains(.markedText), let target {
            context.markedTextTaken = markedWatch.appTookText(expected: composer.markedText, reportedLength: Self.markedLength(target))
        }
        if parts.contains(.selectedRange) { context.selectedRange = target.flatMap { Self.range($0.selectedRange()) } }
        if parts.contains(.selection), let read = SelectedText.read(from: target, accessibility: selectionByAccessibility) {
            log.notice("selection read (\(read.source.rawValue, privacy: .public), \(read.text.count) characters)")
            context.selection = Composer.Selection(text: read.text, range: read.range.map { $0.location..<NSMaxRange($0) })
        }
        if parts.contains(.beforeCaret) { context.beforeCaret = Self.beforeCaret(in: target) }
        if parts.contains(.text) {
            context.text = readFieldText(from: target, before: ReplyContext.Limits.fieldBefore, after: ReplyContext.Limits.fieldAfter,
                                         purpose: "a key (@reply, a snippet's indentation)")
        }
        context.read.formUnion(parts)
    }

    /// `range` as UTF-16 offsets; nil for a field that tells none.
    static func range(_ range: NSRange) -> Range<Int>? {
        range.location == NSNotFound || range.length == NSNotFound ? nil : range.location..<NSMaxRange(range)
    }

    /// What is right before the caret, as `target` tells it (`FieldContext.BeforeCaret`).
    static func beforeCaret(in target: IMKTextInput?) -> FieldContext.BeforeCaret {
        guard let target else { return .unknown }
        let caret = target.selectedRange()
        guard caret.location != NSNotFound else { return .unknown }  // a field that tells no caret
        guard caret.length == 0, caret.location > 0 else { return .nothing }  // a selection (a command may work on it), the start
        guard let before = target.attributedSubstring(from: NSRange(location: caret.location - 1, length: 1))?.string else {
            return .unknown  // a field that reads nothing back
        }
        return .text(before)
    }

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

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var result: KeyModifiers = []
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.capsLock) { result.insert(.capsLock) }
        return result
    }

    /// Device-dependent bits of NSEvent.modifierFlags (NX_DEVICELALTKEYMASK / NX_DEVICERALTKEYMASK).
    static let leftOptionBit: UInt = 0x20, rightOptionBit: UInt = 0x40
    /// All eight (IOKit's NX_DEVICE…KEYMASK): which side's key of each kind is down.
    static let sideBits: [(bit: UInt, side: KeyModifiers)] = [
        (0x01, .leftControl), (0x02, .leftShift), (0x04, .rightShift), (0x08, .leftCommand), (0x10, .rightCommand),
        (leftOptionBit, .leftOption), (rightOptionBit, .rightOption), (0x2000, .rightControl),
    ]

    /// Modifiers of a modifier-change event, including which side's keys are down.
    static func flagsChangedModifiers(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var result = modifiers(flags)
        for (bit, side) in sideBits where flags.rawValue & bit != 0 { result.insert(side) }
        return result
    }


    // MARK: - Outputs

    /// Does what the session answered, in order, in `client` (the field of the key; nil: the one being typed in).
    @MainActor
    func apply(_ outputs: [SessionOutput], client: IMKTextInput?) {
        let target: IMKTextInput? = client ?? clientOverride ?? self.client()
        for output in outputs {
            switch output {
            case let .commit(text):
                insert(text, into: target)
            case let .commitAfterKey(text):
                // Once this key is done: a terminal would send what is inserted during it in the key's place.
                let session = fieldSession
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.fieldSession == session else { return }
                    self.insert(text, into: target)
                }
            case let .replace(text, range):
                target?.insertText(text, replacementRange: range.map { NSRange(location: $0.lowerBound, length: $0.count) } ?? Self.notFound)
            case let .marked(text, cursor, converted):
                setMarkedText(text, cursor: cursor, converted: converted, in: target)
            case let .typeOut(text):
                if let target { typeOut(text, into: target) }
            case let .moveCaret(back, inserted):
                // A result being typed out: once it's all in.
                if isTypingOut { caretAfterTyping = back } else { moveCaret(back: back, after: inserted, in: target) }
            case let .panel(model):
                showPanel(model, target)
            case let .notice(text):
                // Its own small panel, under Translate as You Type's chip if it's on here.
                if !showTranslateChip(target), let target {
                    let panel = CandidatePanel.shared
                    panel.owner = self
                    panel.onSelect = nil
                    panel.show(.notice(text), anchor: anchor(target))
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
                case .translationLanguages?: openSettings(.writing, .outputLanguages)  // its Add… outlined
                case nil: SettingsWindow.shared.show()
                }
            case let .copy(text):
                copyText(text)
            case let .readClipboard(id):
                // After the key has been answered: if macOS asks whether this may read the clipboard, the app isn't left
                // waiting for the key (and doesn't paste on its own meanwhile).
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    // Nothing is read during secure input.
                    let content = self.services.secureInputActive() ? .none : self.readClipboard()
                    // Only how much: never the text or the image itself.
                    log.notice("clipboard for a command: \(Self.logged(content), privacy: .public)")
                    self.received(.clipboard(content, id: id))
                }
            case .keyboardLayout:
                applyKeyboardLayout(client: target)
                // The menu bar icon shows Code's mark while the field being typed in is in Code.
                if Self.activeController === self { MenuBarIcon.shared.setCode(composer.coding ? composer.messages.codeMode : nil) }
            case let .readField(id):
                readFieldAfterPause(id: id, in: target)
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
            }
        }
        keepAlive = session.waitsForPage ? self : nil
        if composer.translateMode != nil { scheduleChipRefresh() }  // Translate as You Type's chip follows the caret
    }

    /// The marked text in `client`: nothing of ours (empty) leaves the document, and any selection in it, alone.
    @MainActor
    private func setMarkedText(_ text: String, cursor: Int, converted: Bool, in client: IMKTextInput?) {
        guard let client else { return }
        guard !text.isEmpty else {
            guard hasMarkedText || (Self.markedLength(client) ?? 0) > 0 else { return }
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: Self.notFound)
            hasMarkedText = false
            return
        }
        let length = (text as NSString).length
        let style = converted ? kTSMHiliteSelectedConvertedText : kTSMHiliteRawText
        let attributed = NSAttributedString(
            string: text, attributes: markAttributes(style: style, range: NSRange(location: 0, length: length)))
        client.setMarkedText(
            attributed, selectionRange: NSRange(location: cursor, length: 0), replacementRange: Self.notFound)
        hasMarkedText = true
        markedWatch.didSet(expected: text, reportedLength: Self.markedLength(client))
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
    static func markedLength(_ client: IMKTextInput) -> Int? {
        let range = client.markedRange()
        return range.location == NSNotFound ? nil : range.length
    }

    private func markAttributes(style: Int, range: NSRange) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        for (key, value) in mark(forStyle: style, at: range) ?? [:] {
            if let name = key as? String {
                attributes[NSAttributedString.Key(name)] = value
            } else if let name = key as? NSAttributedString.Key {
                attributes[name] = value
            }
        }
        if attributes.isEmpty {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    /// Whether `client` is a terminal, which runs every line it is given.
    static func isTerminal(_ client: IMKTextInput?) -> Bool {
        client?.bundleIdentifier().map(SecureInput.terminals.contains) ?? false
    }

    // MARK: - Candidate panel

    @MainActor
    func anchor(_ client: IMKTextInput) -> NSRect {
        // A command on the selection: under the selection's last line (nothing is marked to go by).
        if let range = composer.selection?.range, !range.isEmpty {
            let rect = client.firstRect(forCharacterRange: NSRange(location: range.upperBound - 1, length: 1), actualRange: nil)
            if rect != .zero { return rect }
        }
        var lineRect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineRect)
        return lineRect
    }

    @MainActor
    func showPanel(_ model: PanelModel?, _ client: IMKTextInput?) {
        // Nothing to show: Translate as You Type's chip, if it's on here; its list of languages over anything else.
        guard let model, let client, !translateChipListShown else {
            if !showTranslateChip(client) { hidePanelIfOwned() }
            return
        }
        let panel = CandidatePanel.shared
        panel.owner = self
        panel.onSelect = { [weak self] index in self?.received(.pick(index)) }
        panel.onScroll = { [weak self] steps in self?.received(.scroll(steps)) }
        panel.onChip = { [weak self] part in self?.translateChipClicked(part) }
        panel.show(model, anchor: anchor(client))
        // Rows hold the caret (spec 0): autocomplete's gray text, still up where they are now (its placing waits a
        // moment), goes, as the session ends it. Never a window of ours behind the rows.
        if !model.rows.isEmpty, GhostOverlay.shared.isVisible, GhostOverlay.shared.frame.intersects(panel.frame) {
            GhostOverlay.shared.hide()
        }
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

    /// What the panel is made from besides the composer.
    @MainActor
    func panelPresenter() -> PanelPresenter { session.panelPresenter() }

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
        panel.owner = looseNoticeOwner
        panel.onSelect = nil
        panel.show(.notice(text), anchor: .zero)  // an empty anchor: at the mouse pointer
        DispatchQueue.main.asyncAfter(deadline: .now() + SessionText.noticeDuration(text, long: long)) {
            if panel.owner === looseNoticeOwner { panel.hide() }
        }
    }
}

/// The text field a result is typed into, for `TypeOut.Typist`. Into a terminal, line breaks are counted for
/// pasting (`TerminalPaste`), not typed.
final class TypingField: TypeOut.Field {
    let client: IMKTextInput
    let pastesLineBreaks: Bool
    var lineBreaks = 0

    init(_ client: IMKTextInput, pastesLineBreaks: Bool) {
        self.client = client
        self.pastesLineBreaks = pastesLineBreaks
    }

    var caret: Int? {
        let range = client.selectedRange()
        return range.location != NSNotFound && range.length == 0 ? range.location : nil
    }

    var length: Int? {
        let length = client.length()
        return length >= 0 && length != NSNotFound ? length : nil
    }

    func read(_ range: NSRange) -> String? { client.attributedSubstring(from: range)?.string }

    func type(_ text: String) {
        if pastesLineBreaks, text == "\n" { lineBreaks += 1 } else { client.insertText(text, replacementRange: AllInOneIMEInputController.notFound) }
    }

    func replace(_ range: NSRange, with text: String) { client.insertText(text, replacementRange: range) }
}
