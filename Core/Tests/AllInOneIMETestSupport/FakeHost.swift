import Foundation
import AllInOneIMECore

/// A shell for an `InputSession`, for the core's tests and a shell's: a text field it types into (the document, a
/// selection; nothing is ever marked in it: what is being typed shows in the panel's input line, `preedit`), what the
/// session's outputs did there and on the screen, its work's answers handed back on the test's thread (`settle`), its
/// timers fired when the test says (`fireTimers`). Everything the field says goes with each key
/// (`FieldContext.Parts.all`), as a shell where reading the field is cheap gives it.
public final class FakeHost: @unchecked Sendable {
    public private(set) var session: InputSession!

    // MARK: The field

    /// The app and the kind of field the session is told at `focus`.
    public var app: String? = "com.example.editor"
    public var terminal = false
    /// Secure input is on in the field's app: keys go straight in.
    public var secure = false
    /// The field's text; the caret is at the end, or where the selection was.
    public var document = ""
    /// The field's marked text: the app's own (a test's), never the session's, which marks nothing there
    /// (`InputSession+Preedit.swift`).
    public var marked = ""
    /// What is being typed, as the panel's input line shows it (its prompt, then its text); empty: none.
    public var preedit: String { panel?.input.map { $0.prompt + $0.text } ?? "" }
    /// The selected part of `document` (UTF-16).
    public var selection: Range<Int>?
    /// What ⌘V or ⌃V finds on the clipboard (clipboard history's read of it with ⌃V too).
    public var clipboard = ClipboardContent.none
    /// Clipboard history as a shell keeps it (`ClipboardHistoryServices`), asked by the session once `keepClipboardHistory()`
    /// is called (the services given at `init` are used until then): the texts kept, newest first; whether it records
    /// (`.recording`) or may not read the clipboard (`.notAllowed`); whether the paste key can go to the app as it is (the
    /// Mac's Accessibility); that the next panel is the first on the device (said once, then false); the time now.
    public var clipboardHistory: [ClipboardHistoryItem] = []
    public var clipboardHistoryState = ClipboardHistoryState.recording
    public var passesPasteKey = true
    public var firstClipboardPanel = false
    public var clipboardNow = Date()
    /// Kept images' data by id (`ClipboardHistoryServices.imageData`), and whether the clipboard holds the history's newest
    /// copy still (`clipboardIsNewest`).
    public var clipboardImages: [String: Data] = [:]
    /// The clipboard's reads held back until `answerFieldReads()` (a large image read slowly: a key comes first).
    public var clipboardReadsWait = false
    public var clipboardIsNewest = false
    /// How many times the session opened where a history can be allowed (`ClipboardHistoryServices.openPermission`).
    public private(set) var permissionOpened = 0
    /// A key the session lets through types its text into the document, as the app does (off: the document has only what
    /// the session put in).
    public var appTypesKeys = false
    /// The field tells nothing of its text when it is read (`SessionOutput.readField`): WeChat's.
    public var tellsNoText = false
    /// The field is a password field by what the shell tells of it when it is read (the Mac's Accessibility:
    /// `AXSecureTextField`), though secure input isn't on: once a pause asks (`SessionOutput.readField`), with a key
    /// read as the Mac reads it (`readsWhatIsWanted`) where the session asks (`FieldContext.Parts.passwordField`), and
    /// once the key is answered where it asks that (`SessionOutput.readPasswordField`; held back with `fieldReadsWait`).
    public var passwordField = false
    /// The shell can't tell whether the field is a password field (the Mac without Accessibility): every read of it
    /// answers unknown (`FieldContext.passwordFieldUnknown`, `SessionEvent.passwordField` nil).
    public var cannotTellPasswordField = false
    /// A key reads only what the session wants of the field (`InputSession.fieldWants`), asked until it wants nothing
    /// more, as the Mac does: its text isn't told with every key, only once a pause asks for it (`SessionOutput.readField`).
    public var readsWhatIsWanted = false
    /// The field is read once the test says (`answerFieldReads`), not at once: keys may come before what it says.
    public var fieldReadsWait = false
    /// The same for the selection read after the "@" key (`SessionOutput.readSelection`): a slow Accessibility read, landed
    /// when the test says (`answerFieldReads`, or `selectionReadsGiveUp`). No key ever waits for it.
    public var selectionReadsWait = false
    /// Where the caret is while nothing is selected (UTF-16), for a field whose caret stays where text went in: set, what
    /// goes in moves it to the end of what went in, and the field tells the text after it. Nil: the end of the document
    /// (the caret goes back there after anything goes in).
    public var caretOffset: Int?
    /// How the field is read outside a key (`readField`, `readSelection`, and a replacement's read back), where the test
    /// models a host's own reading (the host scenarios' profiles). Nil: the field as it is, all of it (`context`, `read`).
    public var reading: FieldReads?
    /// The field takes what the session puts in (false: it dropped it, as a field that lost the focus does; the marked
    /// text it shows stays as it is).
    public var acceptsText = true
    /// Told of each change the session or the app (`appTypesKeys`) made to the document, and of what it dropped
    /// (`acceptsText`), as it is made.
    public var inserted: ((Insertion) -> Void)?

    /// How a test's host reads the field outside a key (`FakeHost.reading`).
    public struct FieldReads {
        /// What the field says when it is read (`SessionOutput.readField`, `readSelection`).
        public var context: () -> FieldContext
        /// The document's text in a range (UTF-16), as a replacement reads it back (`ReplacementCheck`); nil: none told.
        public var text: (Range<Int>) -> String?

        public init(context: @escaping () -> FieldContext, text: @escaping (Range<Int>) -> String?) {
            (self.context, self.text) = (context, text)
        }
    }

    /// A change to the document (`FakeHost.inserted`): `text` in place of `replaced`, or dropped (the field took nothing).
    public struct Insertion: Equatable, Sendable {
        public var text: String
        public var replaced: String
        public var dropped: Bool
    }

    // MARK: What the session did

    /// Every output, in order.
    public private(set) var outputs: [SessionOutput] = []
    /// The candidate panel as shown (nil: hidden), and a notice shown on its own.
    public private(set) var panel: PanelModel?
    public private(set) var noticeAlone: String?
    public private(set) var copied: [String] = []
    public private(set) var opened: [String] = []
    public private(set) var openedAgents: [String] = []
    public private(set) var settingsOpened: [SettingsPlace?] = []
    public private(set) var typedOut: [String] = []
    public private(set) var noticesElsewhere: [String] = []
    public private(set) var platformActions: [PlatformAction] = []
    /// The timers started and not fired yet, and how long each was to wait.
    public private(set) var timers: [TimerID] = []
    public private(set) var timerDelays: [TimerID: TimeInterval] = [:]
    /// Autocomplete's suggestion up after the caret (`SessionOutput.ghost`), and the reads of the field it asked for.
    public private(set) var ghost: String?
    public private(set) var fieldReads = 0
    /// The reads of whether the field is a password field asked off the key's thread (`SessionOutput.readPasswordField`).
    public private(set) var passwordFieldReads = 0
    /// The replacements read back before they were made (`SessionOutput.checkNextReplace`).
    public private(set) var replacementsChecked = 0
    /// What the reads asked for while `fieldReadsWait` say, not handed to the session yet.
    private var waitingReads: [SessionEvent] = []

    private let inbox = Locked<[SessionEvent]>(initialState: [])
    private let arrived = DispatchSemaphore(value: 0)
    /// The interface language and command trigger the session sets as it reads its settings, and its texts read
    /// (`UIText.scopedInterface`): the test's own where it has one (`withInterfaceLanguage`), else this host's. Never the
    /// process's, which the tests running alongside read (one in its turn at the interface language, off its task): a
    /// session that set it switched it under them (to its language, to its "~" as the command trigger).
    private let interface: UIText.ScopedInterface
    /// What goes in once the key being answered is done (`commitAfterKey`), and the clipboard read then.
    private var afterKey: [() -> Void] = []
    /// What is done before the next key is handled: the answers to what was asked outside a key (the focus).
    private var beforeKey: [() -> Void] = []
    /// A key is being handled (`press`).
    private var inKey = false

    public init(services: SessionServices, composer: Composer = Composer()) {
        // The interface language the test picked before making the host (its task's own, `UIText.scopedInterface`:
        // never the process's, which a test alongside may have set) stays the session's where the config names none: a
        // focused field applies the config's, nil following the system's, which is this Mac's.
        var services = services
        if let chosen = UIText.scopedInterface?.choice {
            let load = services.loadSettings
            services.loadSettings = {
                var config = load()
                if config.uiLanguage == nil { config.uiLanguage = chosen }
                return config
            }
        }
        let (inbox, arrived) = (inbox, arrived)
        interface = UIText.scopedInterface ?? UIText.ScopedInterface(choice: nil)
        session = UIText.$scopedInterface.withValue(interface) {
            InputSession(composer: composer, services: services, deliver: { event in
                inbox.withLock { $0.append(event) }
                arrived.signal()
            })
        }
    }

    /// `body`, which calls into the session, in its interface (`interface`).
    private func inInterface<T>(_ body: () throws -> T) rethrows -> T {
        try UIText.$scopedInterface.withValue(interface, operation: body)
    }

    public var composer: Composer { session.composer }

    /// The session asks this host for clipboard history (`clipboardHistory`, `clipboardHistoryState`, `passesPasteKey`,
    /// `firstClipboardPanel`, `clipboardNow`), as the Mac's shell answers it.
    public func keepClipboardHistory() {
        session.services.clipboardHistory = ClipboardHistoryServices(
            state: { [unowned self] in clipboardHistoryState }, items: { [unowned self] in clipboardHistory },
            canPassPasteKey: { [unowned self] in passesPasteKey },
            firstShowing: { [unowned self] in
                defer { firstClipboardPanel = false }
                return firstClipboardPanel
            },
            openPermission: { [unowned self] in permissionOpened += 1 }, now: { [unowned self] in clipboardNow },
            imageData: { [unowned self] in clipboardImages[$0] }, clipboardIsNewest: { [unowned self] in clipboardIsNewest })
    }

    /// The kept images pasted (`PlatformAction.pasteImage`), their ids in order.
    public var imagesPasted: [String] {
        platformActions.compactMap { if case let .pasteImage(id) = $0 { id } else { nil } }
    }

    /// Times `PlatformAction.passPasteKey` was asked for: the app's own paste key (clipboard history's image row, ⌃V again).
    public var pasteKeysPassed: Int { platformActions.filter { $0 == .passPasteKey }.count }

    /// The caret: where the selection starts, else `caretOffset` (within the document), else the end of the document.
    public var caret: Int {
        let length = (document as NSString).length
        return selection?.lowerBound ?? caretOffset.map { min(max($0, 0), length) } ?? length
    }

    /// What the field says around the caret, all of it.
    public var context: FieldContext {
        let text = document as NSString
        let selected = selection.map { text.substring(with: NSRange(location: $0.lowerBound, length: $0.count)) }
        let before: FieldContext.BeforeCaret = selection != nil || caret == 0
            ? .nothing : .text(text.substring(with: NSRange(location: caret - 1, length: 1)))
        let end = selection?.upperBound ?? caret
        return FieldContext(read: .all, secure: secure,
                            selectedRange: selection ?? caret..<caret,
                            selection: selected.map { Composer.Selection(text: $0, range: selection) },
                            beforeCaret: before,
                            text: FieldText(before: text.substring(to: caret), after: text.substring(from: end)),
                            passwordFieldUnknown: cannotTellPasswordField)
    }

    /// What the field says around the caret as the Mac reads it for `key` (`readsWhatIsWanted`): only the parts the
    /// session wants, the others unknown.
    public func context(wantedFor key: KeyEvent) -> FieldContext {
        let full = context
        var told = FieldContext()
        while true {
            let missing = inInterface { session.fieldWants(for: key, given: told) }.subtracting(told.read)
            if missing.isEmpty { return told }
            told.read.formUnion(missing)
            if missing.contains(.secure) { told.secure = full.secure }
            if missing.contains(.selectedRange) { told.selectedRange = full.selectedRange }
            if missing.contains(.selection) { told.selection = full.selection }
            if missing.contains(.beforeCaret) { told.beforeCaret = full.beforeCaret }
            if missing.contains(.text) { told.text = full.text }
            if missing.contains(.passwordField) {
                told.field = FieldInfo(app: app, terminal: terminal, secure: passwordField && !cannotTellPasswordField)
                told.passwordFieldUnknown = cannotTellPasswordField
            }
        }
    }

    // MARK: Events

    /// The field takes the focus; a rename to tell is said then (`InputSession.tellBuiltinRenames`).
    public func focus() {
        apply(inInterface { session.handle(.focus(FieldInfo(app: app, terminal: terminal))).outputs })
        apply(inInterface { session.tellBuiltinRenames() })
    }

    /// A key goes down: whether the session took it.
    @discardableResult
    public func press(_ key: KeyEvent) -> Bool {
        answerBeforeKey()  // before the key's reads of the field, which go by what the session knows of it
        return press(key, with: readsWhatIsWanted ? context(wantedFor: key) : context)
    }

    /// A key goes down with `context` what the field says (a shell's reads of it, made by the test): whether the session
    /// took it.
    @discardableResult
    public func press(_ key: KeyEvent, with context: FieldContext) -> Bool {
        answerBeforeKey()
        inKey = true
        let response = inInterface { session.handle(.key(key, context)) }
        apply(response.outputs)
        inKey = false
        if appTypesKeys, !response.handled, let text = key.printableText { insert(text, replacing: selection) }
        let after = afterKey
        afterKey = []
        after.forEach { $0() }
        return response.handled
    }

    /// Hands the session what was asked outside a key (`beforeKey`), before the next one.
    private func answerBeforeKey() {
        let before = beforeKey
        beforeKey = []
        before.forEach { $0() }
    }

    /// The answer to a read of whether the field is a password field (`SessionOutput.readPasswordField`) for `focus`:
    /// held back with `fieldReadsWait`, else handed over once the key is answered (`after`) or now.
    private func tellPasswordField(focus: Int, after: Bool) {
        let told = SessionEvent.passwordField(cannotTellPasswordField ? nil : passwordField, focus: focus)
        if fieldReadsWait {
            waitingReads.append(told)
        } else if after {
            afterKey.append { [weak self] in self?.send(told) }
        } else {
            send(told)
        }
    }

    /// Types `text`, a key a character ("@" with Shift, " " the space bar).
    public func type(_ text: String) {
        for character in text {
            press(character == "@" ? FakeHost.at : character == " " ? FakeHost.space : KeyEvent(keyCode: 0, characters: String(character)))
        }
    }

    /// The modifier keys changed.
    public func modifiers(_ change: ModifierChange) {
        apply(inInterface { session.handle(.modifiers(change, context)).outputs })
    }

    /// The shell says `text` in the field (`InputSession.showNotice`), as the Mac says what it tells there (Autocomplete
    /// turned on in the input menu, a save's outcome).
    public func showNotice(_ text: String) {
        apply(inInterface { session.showNotice(text) })
    }

    /// The shell found the field that took the focus to be the one it kept a draft for (`InputSession.releaseKeptDraft`,
    /// after `holdKeptDraft` and the focus).
    public func releaseKeptDraft() {
        apply(inInterface { session.releaseKeptDraft() })
    }

    /// Hands `event` to the session, as the shell does what isn't a key.
    public func send(_ event: SessionEvent) {
        if case .key = event { answerBeforeKey() }  // a key a test hands over itself comes after the focus's answer too
        apply(inInterface { session.handle(event).outputs })
    }

    /// Hands the session its work's answers as they come, on this thread, until `condition` holds (true) or `timeout`
    /// seconds have gone by (false). This thread is blocked meanwhile, and the work runs on the concurrency pool: never
    /// wait here holding what other tests wait for blocked (a lock), which would leave the work no thread; a test's turn
    /// at the process's state is a `TestTurn`, waited for suspended.
    @discardableResult
    public func settle(timeout: TimeInterval = 10, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let events = inbox.withLock { events -> [SessionEvent] in
                defer { events = [] }
                return events
            }
            for event in events { send(event) }
            if condition() { return true }
            if Date() >= deadline { return false }
            _ = arrived.wait(timeout: .now() + 0.01)
        }
    }

    /// Waits until an answer of the session's work that `matches` has come in, handing nothing to the session (true), or
    /// `timeout` seconds have gone by (false): the session hears it late, after what the test does meanwhile. Blocking,
    /// as `settle`.
    @discardableResult
    public func waitForAnswer(timeout: TimeInterval = 10, where matches: (SessionEvent) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !inbox.withLock({ $0.contains(where: matches) }) {
            if Date() >= deadline { return false }
            _ = arrived.wait(timeout: .now() + 0.01)
        }
        return true
    }

    /// Hands the session what the field said for the reads waiting (`fieldReadsWait`, `selectionReadsWait`), in order:
    /// the field as it was when each was asked for.
    public func answerFieldReads() {
        let reads = waitingReads
        waitingReads = []
        for read in reads { send(read) }
    }

    /// The selection reads waiting (`selectionReadsWait`) give up, whatever is selected (Accessibility answered nothing in
    /// time): each answers none, in order. The other reads still wait.
    public func selectionReadsGiveUp() {
        let reads = waitingReads.compactMap { if case let .selection(_, id) = $0 { id } else { nil } }
        waitingReads.removeAll { if case .selection = $0 { true } else { false } }
        for id in reads { send(.selection(nil, id: id)) }
    }

    /// The ids of the selection reads asked for so far (`SessionOutput.readSelection`), in order.
    public var selectionReads: [Int] {
        outputs.compactMap { if case let .readSelection(id) = $0 { id } else { nil } }
    }

    /// Fires the timers started so far, in order.
    public func fireTimers() {
        let fired = timers
        timers = []
        for timer in fired { send(.timer(timer)) }
    }

    /// Fires the timers started so far that `matches`, in order; the others wait.
    public func fireTimers(where matches: (TimerID) -> Bool) {
        let fired = timers.filter(matches)
        timers.removeAll(where: matches)
        for timer in fired { send(.timer(timer)) }
    }

    // MARK: Outputs

    private func apply(_ outputs: [SessionOutput]) {
        self.outputs += outputs
        // What the next `replace` must take out (`checkNextReplace`): read back from the document, as the Mac reads it.
        var check: ReplacementCheck?
        for output in outputs {
            switch output {
            case let .commit(text):
                insert(text, replacing: selection)
            case let .commitAfterKey(text):
                afterKey.append { [weak self] in self?.insert(text, replacing: nil) }
            case let .checkNextReplace(next):
                check = next
            case .rowByKey, .rowsTookKey:
                break
            case let .replace(text, range):
                if let next = check, let range {
                    replacementsChecked += 1
                    next.apply(text, range: range, read: { self.reading?.text($0) ?? self.read($0) }, replace: { insert($0, replacing: $1) }, insert: { insert($0, replacing: selection) })
                } else {
                    insert(text, replacing: range ?? selection)
                }
                check = nil
            case let .typeOut(text):
                typedOut.append(text)
                insert(text, replacing: nil)
            case .moveCaret:
                break
            case let .panel(model):
                panel = model
                noticeAlone = nil
            case let .notice(text):
                noticeAlone = text
            case let .noticeElsewhere(text, _, _):
                noticesElsewhere.append(text)
            case let .open(item):
                opened.append(item)
            case let .openAgent(id):
                openedAgents.append(id)
            case let .openSettings(topic):
                settingsOpened.append(topic)
            case let .copy(text):
                copied.append(text)
            case let .readClipboard(id):
                // Once the key is answered, as the Mac reads it (held back with `clipboardReadsWait`: a slow read).
                let content = clipboard
                if clipboardReadsWait {
                    waitingReads.append(.clipboard(content, id: id))
                } else {
                    afterKey.append { [weak self] in self?.send(.clipboard(content, id: id)) }
                }
            case .keyboardLayout:
                break
            case let .startTimer(id, seconds):
                timers.append(id)
                timerDelays[id] = seconds
            case let .readField(id, focus):
                // At once, as the Mac reads it (the field as it is now; nothing of its text where it tells none).
                fieldReads += 1
                var read = reading?.context() ?? context
                if tellsNoText { read.text = nil }
                if passwordField, !cannotTellPasswordField { read.field = FieldInfo(app: app, terminal: terminal, secure: true) }
                let told = SessionEvent.field(read, id: id, focus: focus)
                if fieldReadsWait { waitingReads.append(told) } else { send(told) }
            case let .readPasswordField(focus):
                passwordFieldReads += 1
                // Asked as the field takes the focus: answered by the time the next key comes, as the Mac's read off
                // the main thread usually is, with what the field is then (a test sets it after `focus()`).
                guard inKey else {
                    beforeKey.append { [weak self] in self?.tellPasswordField(focus: focus, after: false) }
                    continue
                }
                // Once the key is answered, off its thread as the Mac reads it (held back with `fieldReadsWait`).
                tellPasswordField(focus: focus, after: true)
            case let .readSelection(id):
                // Once the key is answered, as the Mac reads it with Accessibility: the field's selection.
                let told = SessionEvent.selection((reading?.context() ?? context).selection, id: id)
                if selectionReadsWait { waitingReads.append(told) } else { afterKey.append { [weak self] in self?.send(told) } }
            case let .ghost(text):
                ghost = text
            case let .platform(action):
                platformActions.append(action)
            }
        }
    }

    /// The document's text in `range` (UTF-16); nil where it has none (past its end).
    public func read(_ range: Range<Int>) -> String? {
        let text = document as NSString
        guard range.lowerBound >= 0, range.upperBound <= text.length else { return nil }
        return text.substring(with: NSRange(location: range.lowerBound, length: range.count))
    }

    /// `text` at the caret, or in place of `range` (UTF-16).
    /// A range past the document's end (a field that told it stale) is cut to the document, as an app's text view does.
    private func insert(_ text: String, replacing range: Range<Int>?) {
        let current = document as NSString
        let start = min(max(range?.lowerBound ?? caret, 0), current.length)
        let end = min(max(range?.upperBound ?? caret, start), current.length)
        let replaced = current.substring(with: NSRange(location: start, length: end - start))
        guard acceptsText else {
            inserted?(Insertion(text: text, replaced: replaced, dropped: true))
            return
        }
        document = current.replacingCharacters(in: NSRange(location: start, length: end - start), with: text)
        selection = nil
        if caretOffset != nil { caretOffset = start + (text as NSString).length }
        inserted?(Insertion(text: text, replaced: replaced, dropped: false))
    }

    // MARK: Keys

    public static let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    public static let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
    public static let enter = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r")
    public static let space = KeyEvent(keyCode: VirtualKey.space, characters: " ")
    public static let escape = KeyEvent(keyCode: VirtualKey.escape, characters: "\u{1B}")
    public static let controlV = KeyEvent(keyCode: 0x09, characters: "\u{16}", charactersIgnoringModifiers: "v", modifiers: .control)
    public static let down = KeyEvent(keyCode: VirtualKey.down, characters: "\u{F701}")
    public static let up = KeyEvent(keyCode: VirtualKey.up, characters: "\u{F700}")
    public static let right = KeyEvent(keyCode: VirtualKey.right, characters: "\u{F703}")
    public static let shiftDown = KeyEvent(keyCode: VirtualKey.down, characters: "\u{F701}", modifiers: .shift)
    public static let shiftUp = KeyEvent(keyCode: VirtualKey.up, characters: "\u{F700}", modifiers: .shift)
}
