import Foundation
import AllInOneIMECore

/// A shell for an `InputSession`, for the core's tests and a shell's: a text field it types into (the document, the marked
/// text, a selection), what the session's outputs did there and on the screen, its work's answers handed back on the
/// test's thread (`settle`), its timers fired when the test says (`fireTimers`). Everything the field says goes with each
/// key (`FieldContext.Parts.all`), as a shell where reading the field is cheap gives it.
public final class FakeHost: @unchecked Sendable {
    public private(set) var session: InputSession!

    // MARK: The field

    /// The app and the kind of field the session is told at `focus`.
    public var app: String? = "com.example.editor"
    public var terminal = false
    /// Secure input is on in the field's app: keys go straight in.
    public var secure = false
    /// The field's text, without the marked text; the caret is at the end, or where the selection was.
    public var document = ""
    public var marked = ""
    /// The selected part of `document` (UTF-16).
    public var selection: Range<Int>?
    /// The app took the marked text on its own (`FieldContext.markedTextTaken`), once.
    public var appTakesMarkedText = false
    /// What ⌘V or ⌃V finds on the clipboard.
    public var clipboard = ClipboardContent.none
    /// A key the session lets through types its text into the document, as the app does (off: the document has only what
    /// the session put in).
    public var appTypesKeys = false
    /// The field tells nothing of its text when it is read (`SessionOutput.readField`): WeChat's.
    public var tellsNoText = false

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

    private let inbox = Locked<[SessionEvent]>(initialState: [])
    private let arrived = DispatchSemaphore(value: 0)
    /// What goes in once the key being answered is done (`commitAfterKey`), and the clipboard read then.
    private var afterKey: [() -> Void] = []

    public init(services: SessionServices, composer: Composer = Composer()) {
        let (inbox, arrived) = (inbox, arrived)
        session = InputSession(composer: composer, services: services, deliver: { event in
            inbox.withLock { $0.append(event) }
            arrived.signal()
        })
    }

    public var composer: Composer { session.composer }

    /// The caret: where the selection starts, else the end of the document.
    public var caret: Int { selection?.lowerBound ?? (document as NSString).length }

    /// What the field says around the caret, all of it.
    public var context: FieldContext {
        let text = document as NSString
        let selected = selection.map { text.substring(with: NSRange(location: $0.lowerBound, length: $0.count)) }
        let before: FieldContext.BeforeCaret = selection != nil || caret == 0
            ? .nothing : .text(text.substring(with: NSRange(location: caret - 1, length: 1)))
        let end = selection?.upperBound ?? text.length
        return FieldContext(read: .all, secure: secure, markedTextTaken: appTakesMarkedText,
                            selectedRange: selection ?? caret..<caret,
                            selection: selected.map { Composer.Selection(text: $0, range: selection) },
                            beforeCaret: before,
                            text: FieldText(before: text.substring(to: caret), after: text.substring(from: end)))
    }

    // MARK: Events

    /// The field takes the focus; a rename to tell is said then (`InputSession.tellBuiltinRenames`).
    public func focus() {
        apply(session.handle(.focus(FieldInfo(app: app, terminal: terminal))).outputs)
        apply(session.tellBuiltinRenames())
    }

    /// A key goes down: whether the session took it.
    @discardableResult
    public func press(_ key: KeyEvent) -> Bool {
        let response = session.handle(.key(key, context))
        appTakesMarkedText = false
        apply(response.outputs)
        if appTypesKeys, !response.handled, let text = key.printableText { insert(text, replacing: selection) }
        let after = afterKey
        afterKey = []
        after.forEach { $0() }
        return response.handled
    }

    /// Types `text`, a key a character ("@" with Shift, " " the space bar).
    public func type(_ text: String) {
        for character in text {
            press(character == "@" ? FakeHost.at : character == " " ? FakeHost.space : KeyEvent(keyCode: 0, characters: String(character)))
        }
    }

    /// The modifier keys changed.
    public func modifiers(_ change: ModifierChange) {
        apply(session.handle(.modifiers(change, context)).outputs)
    }

    /// Hands `event` to the session, as the shell does what isn't a key.
    public func send(_ event: SessionEvent) {
        apply(session.handle(event).outputs)
    }

    /// Hands the session its work's answers as they come, on this thread, until `condition` holds (true) or `timeout`
    /// seconds have gone by (false).
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
    /// `timeout` seconds have gone by (false): the session hears it late, after what the test does meanwhile.
    @discardableResult
    public func waitForAnswer(timeout: TimeInterval = 10, where matches: (SessionEvent) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !inbox.withLock({ $0.contains(where: matches) }) {
            if Date() >= deadline { return false }
            _ = arrived.wait(timeout: .now() + 0.01)
        }
        return true
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
        for output in outputs {
            switch output {
            case let .commit(text):
                insert(text, replacing: selection)
            case let .commitAfterKey(text):
                afterKey.append { [weak self] in self?.insert(text, replacing: nil) }
            case let .replace(text, range):
                insert(text, replacing: range ?? selection)
            case let .marked(text, _, _):
                marked = text
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
                // Once the key is answered, as the Mac reads it.
                let content = clipboard
                afterKey.append { [weak self] in self?.send(.clipboard(content, id: id)) }
            case .keyboardLayout:
                break
            case let .startTimer(id, seconds):
                timers.append(id)
                timerDelays[id] = seconds
            case let .readField(id):
                // At once, as the Mac reads it (the field as it is now; nothing of its text where it tells none).
                fieldReads += 1
                var read = context
                if tellsNoText { read.text = nil }
                send(.field(read, id: id))
            case let .ghost(text):
                ghost = text
            case let .platform(action):
                platformActions.append(action)
            }
        }
    }

    /// `text` in place of the marked text, or of `range` (UTF-16).
    private func insert(_ text: String, replacing range: Range<Int>?) {
        let current = document as NSString
        if let range {
            document = current.replacingCharacters(in: NSRange(location: range.lowerBound, length: range.count), with: text)
        } else {
            document = current.replacingCharacters(in: NSRange(location: caret, length: 0), with: text)
        }
        selection = nil
        marked = ""
    }

    // MARK: Keys

    public static let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    public static let tab = KeyEvent(keyCode: VirtualKey.tab, characters: "\t")
    public static let enter = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r")
    public static let space = KeyEvent(keyCode: VirtualKey.space, characters: " ")
    public static let escape = KeyEvent(keyCode: VirtualKey.escape, characters: "\u{1B}")
    public static let controlV = KeyEvent(keyCode: 0x09, characters: "\u{16}", charactersIgnoringModifiers: "v", modifiers: .control)
}
