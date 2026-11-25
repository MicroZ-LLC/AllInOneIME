import AllInOneIMECore
import AllInOneIMEMac
import AllInOneIMETestSupport
import AppKit
import InputMethodKit

/// Replays a host scenario (`HostCase`) on one profile's field (`ProfiledTextClient`) through the input method's own
/// reading and anchoring code, the Mac library's: a key's field context (`FieldReading`), the text autocomplete and the
/// AI read (`FieldTextReading`), the panel's anchor (`FieldAnchor`), typing a result out (`TypingField`), the keys and
/// modifier changes as AppKit hands them over and their copies (`MacKeyEvents`, `KeyEchoes`). The session is the core's
/// (`InputSession`, a stand-in engine: `FakeEngine`). What the input method's controller does with the session's
/// answers in the field (marked text, commits, replacements, the panel) is done here as it does it; its Chromium rows
/// marked during a key (`markRow`), the terminal's paste and the windows themselves are not.
///
/// The host: a click, the field losing the focus, the input source switched and the app emptying the field do to the
/// field what its profile says (`ProfiledTextClient`), and reach the input method as IMK hands them over:
/// `commitComposition` on a click outside the marked text (NSTextView, a terminal, WeChat; Chromium finishes the
/// composition itself first, then tells it), and when an AppKit field is emptied (a Chromium page tells it nothing),
/// `deactivateServer` when the field or the window loses the focus or the input source changes, `activateServer` when it
/// comes back; each click first of all as `SessionEvent.pointerDown` (the controller's global mouse-down monitor, which
/// needs no Accessibility: contract v1.4). A key the input method leaves the app is typed by the app.
@MainActor
final class HostReplayer {
    let scenario: HostCase
    let profile: HostProfile
    let client: ProfiledTextClient
    /// The client as the input method asks it: `client`, or a recorder's proxy of it (`IMKRecorder`).
    let field: IMKTextInput
    let session: InputSession
    private var events: HostEvents
    /// The session's clock (`SessionServices.uptime`): the events' (`HostEvents.now`).
    private let clock: Locked<TimeInterval>
    private let inbox = Locked<[SessionEvent]>(initialState: [])

    // The input method's own state, as its controller keeps it.
    private var keyEchoes = KeyEchoes()
    private var modifierEchoes = ModifierEchoes()
    private var capsLockCopies = CapsLockCopies()
    private var anchorMemory = PanelAnchor.Memory()
    private var lastAnchorByApp: [String: CGRect] = [:]
    private var fieldSession = 0
    /// What runs on the run loop's next turn after a key (`DispatchQueue.main.async`): after Chromium's view caught up.
    private var nextTurn: [() -> Void] = []
    private var timers: [(id: TimerID, at: TimeInterval)] = []
    private var reasksAnchor = false

    // The host's.
    /// AllInOneIME is the input source (`SWITCH abc`: ABC is, and the keys go to the app as they are).
    private var active = true
    private var capsLockOn = false

    // What was seen.
    private(set) var panel: PanelModel?
    private(set) var anchor: FieldAnchor.Placed?
    private(set) var failures: [String] = []
    private(set) var trace: [String] = []
    private var language: Language
    private var switches = 0
    /// Each key's calls through IMK since the last `EXPECT calls`.
    private var keyCalls: [[String: Int]] = []
    /// Every key's, modifier change's and read after a pause's calls in the run (`what`: "key", "modifiers", "pause"),
    /// and how long they took (`ProfiledTextClient.latency`).
    private(set) var everyTurn: [(what: String, calls: [String: Int], spent: TimeInterval)] = []
    /// What the session committed since the field was last emptied, and how many of each character the field should have:
    /// what it had, what the session committed, what the app typed or took out (`EXPECT nolost`).
    private var committed = ""
    private var expectedCounts: [Character: Int] = [:]
    /// The marked text Chromium's page made plain text itself (a click, the focus lost), until the session commits: the
    /// same text committed then is that text, in once (the page's insert dropped or not).
    private var pageFinished: String?

    init(_ scenario: HostCase, profile: HostProfile, recorder: IMKRecorder? = nil) {
        self.scenario = scenario
        self.profile = profile
        let text = scenario.field
        let client = ProfiledTextClient(profile, text: text.text, selection: text.selection, marked: text.marked)
        self.client = client
        field = recorder?.recording(client) ?? client
        events = HostEvents(profile: profile, seed: scenario.source + "/" + scenario.name)
        let clock = Locked(initialState: events.now)
        self.clock = clock
        // Chinese and English both (the default has English alone), the scenario's first: a tap of Shift goes between them.
        var config = Config.default
        for (key, value) in scenario.settings {
            config = (try? HostScenarioSettings.applying(key, value, to: config)) ?? config  // the core's parser refuses a wrong one
        }
        config.uiLanguage = "en"
        config.setOrder(scenario.language == .chinese ? [Language.chinese, .english] : [Language.english, .chinese])
        let settings = config
        var services = SessionServices(loadSettings: { settings })
        let engine = FakeEngine()
        services.levelOne = { .engine(engine) }
        services.uptime = { clock.withLock { $0 } }
        let inbox = inbox
        session = InputSession(services: services, deliver: { event in inbox.withLock { $0.append(event) } })
        language = session.composer.inputLanguage
        expectedCounts = Self.counts(client.doc)
    }

    /// The reading the controller does (`AllInOneIMEInputController.fieldReading`), with what only its process tells
    /// answered as nothing here does: no secure input, no password field, no Accessibility, no terminal.
    var reading: FieldReading {
        FieldReading(isTerminal: { _ in false }, secureInputActive: { false }, blocksComposing: { _ in false },
                     passwordField: { false }, selectionMayBeUntold: nil, chromiumApp: { [profile] _ in profile.isChromium })
    }

    // MARK: Running

    /// Runs the scenario: the field focused in its starting language, then each step that applies to this profile.
    func run() {
        activate()
        if scenario.language != session.composer.inputLanguage { session.composer.setInputMode(scenario.language) }
        (language, switches) = (session.composer.inputLanguage, 0)
        for step in scenario.steps where step.applies(to: profile) {
            perform(step)
        }
    }

    private func perform(_ step: HostCase.Step) {
        switch step.action {
        case let .type(text):
            for character in text {
                advance(by: 0.05)
                type(character)
            }
        case let .keys(keys):
            for key in keys {
                advance(by: 0.05)
                press(key)
            }
        case let .click(offset):
            advance(by: 0.05)
            click(offset)
        case let .focus(focus):
            advance(by: 0.05)
            self.focus(focus)
        case let .switchToABC(abc):
            advance(by: 0.05)
            switchSource(toABC: abc)
        case .appClears:
            advance(by: 0.05)
            note("the app empties the field")
            let marked = client.markedText != nil
            client.clear()
            // An AppKit text view tells the input method (a real NSTextField and NSTextView, 2026-11-15), and so do WebKit
            // and Qt (`HostProfile.tellsWhenEmptied`); a Chromium page tells it nothing (#115).
            if marked, profile.tellsWhenEmptied, active { commitComposition() }
            (committed, expectedCounts, pageFinished) = ("", [:], nil)
        case let .wait(seconds):
            advance(by: seconds)
        case let .expect(expectation):
            check(expectation, line: step.line)
        }
    }

    // MARK: Keys

    private func type(_ character: Character) {
        let key = HostKeys.key(for: character)
        if key.shift {
            modifier("shift", down: true)
            advance(by: 0.02)
        }
        let typed = capsLockOn && character.isLetter ? character.uppercased() : String(character)
        keyDown(code: key.code, characters: typed, ignoringModifiers: String(key.base), flags: heldFlags)
        if key.shift {
            advance(by: 0.02)
            modifier("shift", down: false)
        }
    }

    private func press(_ key: HostKey) {
        switch key.kind {
        case let .modifierTap(name):
            modifier(name, down: true)
            advance(by: 0.08)
            modifier(name, down: false)
        case .capsLock:
            capsLockOn.toggle()
            flagsChanged(code: UInt16(0x39), flags: capsLockOn ? [.capsLock] : [])
        case let .named(name):
            withModifiers(key.modifiers) { flags in
                guard let named = HostKeys.named[name] else { return }
                keyDown(code: named.code, characters: named.characters, ignoringModifiers: named.characters, flags: flags)
            }
        case let .character(character):
            withModifiers(key.modifiers) { flags in
                let found = HostKeys.key(for: character)
                let typed = flags.contains(.option) ? HostKeys.option[found.base] ?? String(character)
                    : flags.contains(.control) ? Self.control(found.base)
                    // Shift with a letter types its capital, as the keyboard does ("shift+a" is "A").
                    : flags.contains(.shift) && character.isLetter ? String(character).uppercased() : String(character)
                keyDown(code: found.code, characters: typed, ignoringModifiers: String(found.base), flags: flags)
            }
        }
    }

    /// `body` with `modifiers` held: each pressed in turn, then released the other way round.
    private func withModifiers(_ modifiers: [String], _ body: (NSEvent.ModifierFlags) -> Void) {
        for name in modifiers {
            modifier(name, down: true)
            advance(by: 0.02)
        }
        body(heldFlags)
        for name in modifiers.reversed() {
            advance(by: 0.02)
            modifier(name, down: false)
        }
    }

    /// The modifiers held now, with their sides' bits, and the lock.
    private var heldFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = capsLockOn ? [.capsLock] : []
        for name in held {
            guard let modifier = HostKeys.modifiers[name] else { continue }
            flags.insert(modifier.flag)
            flags.insert(NSEvent.ModifierFlags(rawValue: modifier.side))
        }
        return flags
    }

    private var held: [String] = []

    private func modifier(_ name: String, down: Bool) {
        guard let modifier = HostKeys.modifiers[name] else { return }
        if down { held.append(name) } else { held.removeAll { HostKeys.modifiers[$0]?.code == modifier.code } }
        flagsChanged(code: modifier.code, flags: heldFlags)
    }

    private static func control(_ character: Character) -> String {
        guard let ascii = character.asciiValue, character.isLetter else { return String(character) }
        return String(UnicodeScalar(ascii & 0x1F))
    }

    /// A key down from the keyboard: to the input method when it is the input source, then to the app if it left it. None
    /// reaches a field that lost the focus (another field or app has the keys), as the core's runner has it.
    private func keyDown(code: UInt16, characters: String, ignoringModifiers: String, flags: NSEvent.ModifierFlags) {
        guard client.focused else { return }
        guard let event = events.keyDown(keyCode: code, characters: characters, ignoringModifiers: ignoringModifiers, flags: flags) else {
            failures.append("couldn't make a key down for \(characters.debugDescription)")
            return
        }
        guard active else {
            appHandles(event)
            return
        }
        let handled = handleKeyDown(event)
        if !handled {
            appHandles(event)
            events.sendsCopy(of: event)  // Chromium hands an unhandled key over again
        }
    }

    private func flagsChanged(code: UInt16, flags: NSEvent.ModifierFlags) {
        guard active, client.focused, let event = events.flagsChanged(keyCode: code, flags: flags) else { return }
        handleFlagsChanged(event)
        events.sendsCopy(of: event)
    }

    /// The controller's `handleKeyDown`: a copy of a key answered as the first was; a new one read, handed to the session,
    /// its answer done in the field; the run loop's next turn after it.
    @discardableResult
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let key = MacKeyEvents.echoKey(event)
        if let handled = keyEchoes.copy(of: key, now: events.now) {
            note("a key down came twice; the copy answered \(handled)")
            return handled
        }
        beginTurn()
        let keyEvent = MacKeyEvents.key(event)
        let context = reading.context(in: field) { session.fieldWants(for: keyEvent, given: $0) }
        let response = session.handle(.key(keyEvent, context))
        apply(response.outputs)
        keyEchoes.answered(key, now: events.now, handled: response.handled)
        note("key \(keyEvent.characters.debugDescription) \(response.handled ? "taken" : "left to the app")")
        everyTurn.append(("key", client.calls, client.spent))
        endTurn()
        return response.handled
    }

    /// The controller's `handleFlagsChanged`: a copy dropped (`MacKeyEvents.copy`); else read and handed to the session.
    private func handleFlagsChanged(_ event: NSEvent) {
        if let copy = MacKeyEvents.copy(event, now: events.now, echoes: &modifierEchoes, capsLock: &capsLockCopies,
                                        lockOn: { [capsLockOn] in capsLockOn }) {
            note("a modifier change came again (\(copy)); dropped")
            return
        }
        beginTurn()
        let change = MacKeyEvents.modifierChange(event, now: events.now)
        let context = reading.context(in: field) { session.fieldWants(forModifiers: change, given: $0) }
        apply(session.handle(.modifiers(change, context)).outputs)
        note("modifiers \(change.key) \(change.modifiers.rawValue)")
        everyTurn.append(("modifiers", client.calls, client.spent))
        endTurn()
    }

    /// A key the input method left the app, done by the app: it types what the key types, takes a character out (⌫),
    /// moves the caret (← →), undoes (⌘Z).
    private func appHandles(_ event: NSEvent) {
        let flags = event.modifierFlags
        let before = client.doc
        defer { appChanged(from: before) }
        switch Int(event.keyCode) {
        case 0x33: client.appDeletesBackward()
        case 0x7B: client.appMovesCaret(by: -1)
        case 0x7C: client.appMovesCaret(by: 1)
        case 0x35, 0x7D, 0x7E: break
        case 0x06 where flags.contains(.command): client.undo()
        case 0x00 where flags.contains(.command): client.appSelectsAll()
        default:
            guard !flags.contains(.command), !flags.contains(.control), let text = event.characters, !text.isEmpty else { return }
            client.appTypes(text == "\r" ? "\n" : text)
        }
    }

    // MARK: The host

    private func click(_ offset: Int?) {
        mouseDown()
        if let offset {
            note("a click at \(offset)")
            if profile.clickCommitsMarkedText {
                // The page commits the marked text, then tells the input method (IMK's commitComposition: a real Brave; Qt's
                // `discardMarkedText`, taken as cancelComposition).
                let marked = client.markedText != nil
                pageFinishes { client.finishComposingText() }
                if marked, profile == .qt { cancelComposition() } else if marked { commitComposition() }
            } else if !client.isInsideMarkedText(offset), client.markedText != nil {
                commitComposition()
            }
            client.moveCaret(to: offset)
        } else {
            note("a click outside the field")
            if !profile.clickCommitsMarkedText, client.markedText != nil { commitComposition() }
            loseFocus()
        }
    }

    private func focus(_ focus: HostCase.Focus) {
        note("focus \(focus.rawValue)")
        switch focus {
        case .away, .otherapp:
            loseFocus()
        case .back:
            client.becomeFocused()
            if active { activate() }
        case .closewindow:
            loseFocus()
            if active { apply(session.handle(.close).outputs) }
        }
    }

    private func switchSource(toABC abc: Bool) {
        note(abc ? "the input source switched to ABC" : "back to AllInOneIME")
        if abc, active {
            deactivate()
            active = false
        } else if !abc, !active {
            active = true
            activate()
        }
    }

    /// A mouse down outside the input method's windows, told by its global monitor (`watchPointerDowns`).
    private func mouseDown() {
        guard active else { return }
        apply(session.handle(.pointerDown).outputs)
        settle()
    }

    /// The field loses the focus (`HostProfile`: Chromium's page commits the marked text, and drops what comes after);
    /// then the input method lets it go.
    private func loseFocus() {
        pageFinishes { client.resign() }
        if active { deactivate() }
        client.deactivated()
    }

    /// `activateServer`: a field of its own (marked text, field session), the session told.
    private func activate() {
        fieldSession += 1
        apply(session.handle(.focus(FieldInfo(app: client.bundleIdentifier(), terminal: false))).outputs)
        apply(session.tellBuiltinRenames())
        settle()
    }

    /// `deactivateServer`: the session told the field is left (it commits), into the field still the client.
    private func deactivate() {
        apply(session.handle(.blur).outputs)
        fieldSession += 1
        anchorMemory.forget()
        settle()
    }

    /// `commitComposition`: the app wants everything in now (a click elsewhere in it).
    private func commitComposition() {
        apply(session.handle(.commit).outputs)
        settle()
    }

    /// `cancelComposition`: the app ended the composition itself (the controller's: `.cancel`).
    private func cancelComposition() {
        apply(session.handle(.cancel).outputs)
        settle()
    }

    // MARK: Turns and time

    private func beginTurn() {
        client.beginTurn()
        client.resetCalls()
    }

    /// The key is done: its calls counted, Chromium's view caught up, then what waits for the run loop's next turn.
    private func endTurn() {
        keyCalls.append(client.calls)
        client.endTurn()
        settle()
    }

    /// The run loop's next turn: what waited for it, the anchor asked again, the session's work's answers.
    private func settle() {
        while !nextTurn.isEmpty {
            let work = nextTurn
            nextTurn = []
            work.forEach { $0() }
        }
        if reasksAnchor { reaskAnchor() }
        let delivered = inbox.withLock { events -> [SessionEvent] in
            defer { events = [] }
            return events
        }
        for event in delivered { received(event) }
        noteLanguage()
    }

    /// The clock `seconds` on: each copy the host sends and each timer due on the way, in time order.
    private func advance(by seconds: TimeInterval) {
        let target = events.now + seconds
        while true {
            let copy = events.nextCopy.flatMap { $0 <= target ? $0 : nil }
            let timer = timers.min { $0.at < $1.at }.flatMap { $0.at <= target ? $0 : nil }
            if let timer, copy.map({ timer.at <= $0 }) ?? true {
                events.move(to: timer.at)
                syncClock()
                timers.removeAll { $0.id == timer.id && $0.at == timer.at }
                received(.timer(timer.id))
            } else if copy != nil, let event = events.takeCopy() {
                syncClock()
                guard active else { continue }
                if event.type == .keyDown { handleKeyDown(event) } else { handleFlagsChanged(event) }
            } else {
                break
            }
        }
        events.move(to: target)
        syncClock()
        settle()
    }

    private func syncClock() {
        let now = events.now
        clock.withLock { $0 = now }
    }

    private func received(_ event: SessionEvent) {
        apply(session.handle(event).outputs)
    }

    private func noteLanguage() {
        let now = session.composer.inputLanguage
        if now != language {
            switches += 1
            note("language \(now.rawValue)")
            language = now
        }
    }

    private func note(_ line: String) {
        trace.append(String(format: "%.3f ", events.now - 1_000) + line)
    }
}

// MARK: - The session's answers, done in the field

extension HostReplayer {
    /// The controller's `apply`, for what reaches the field and the panel.
    private func apply(_ outputs: [SessionOutput]) {
        var check: ReplacementCheck?
        for output in outputs {
            switch output {
            case let .commit(text):
                insert(text)
            case let .commitAfterKey(text):
                let session = fieldSession
                nextTurn.append { [weak self] in
                    guard let self, self.fieldSession == session else { return }
                    self.insert(text)
                }
            case let .checkNextReplace(next):
                check = next
            case let .replace(text, range):
                if let next = check, let range {
                    _ = next.apply(text, range: range,
                                   read: { self.field.attributedSubstring(from: NSRange(location: $0.lowerBound, length: $0.count))?.string },
                                   replace: { self.insert($0, replacing: NSRange(location: $1.lowerBound, length: $1.count)) },
                                   insert: { self.insert($0) })
                } else {
                    insert(text, replacing: range.map { NSRange(location: $0.lowerBound, length: $0.count) })
                }
                check = nil
            case let .typeOut(text):
                typeOut(text)
            case let .panel(model):
                showPanel(model)
            case let .startTimer(id, seconds):
                timers.append((id, events.now + seconds))
            case let .readField(id):
                nextTurn.append { [weak self] in
                    guard let self else { return }
                    self.client.resetCalls()
                    let read = self.reading.contextAfterPause(in: self.field, id: id)
                    self.everyTurn.append(("pause", self.client.calls, self.client.spent))
                    self.received(.field(read, id: id))
                }
            case let .readPasswordField(focus):
                nextTurn.append { [weak self] in self?.received(.passwordField(false, focus: focus)) }
            case let .readSelection(id):
                nextTurn.append { [weak self] in self?.received(.selection(nil, id: id)) }
            case let .readClipboard(id):
                nextTurn.append { [weak self] in self?.received(.clipboard(.none, id: id)) }
            case let .platform(.setCapsLock(on)):
                capsLockOn = on
            default:
                note("not done here: \(output)")
            }
        }
    }

    /// Text in, in place of the marked text (or `range`, or the selection): what the session committed, and what it took
    /// out of the field's text (a selection typed over), for `EXPECT nolost`.
    private func insert(_ text: String, replacing range: NSRange? = nil) {
        committed += text
        if pageFinished == text {
            pageFinished = nil  // in already: the page made the marked text plain text, and this is that text
        } else {
            for character in text { expectedCounts[character, default: 0] += 1 }
        }
        for character in replacedText(by: range) { expectedCounts[character, default: 0] -= 1 }
        field.insertText(text, replacementRange: range ?? NSRange(location: NSNotFound, length: NSNotFound))
        note("committed \(text.debugDescription)")
    }


    /// What of the field's own text an insertion takes out: `range` (where the field has it), else the selection; none
    /// in place of marked text (it isn't the field's text) or where the field drops what comes (it lost the focus).
    private func replacedText(by range: NSRange?) -> String {
        let state = client.state, length = (state.text as NSString).length
        guard client.focused else { return "" }
        let target: NSRange
        if let range, range.location != NSNotFound {
            target = range
        } else if state.marked != nil {
            return ""
        } else {
            target = state.selection
        }
        guard NSMaxRange(target) <= length else { return "" }
        return (state.text as NSString).substring(with: target)
    }

    /// The controller's `showPanel` and `anchor`: shown under the rect the field tells (`FieldAnchor.place`), its window
    /// learned once, no Accessibility; asked again on the next turn where that wasn't one to trust.
    private func showPanel(_ model: PanelModel?) {
        guard let model else {
            (panel, anchor, reasksAnchor) = (nil, nil, false)
            return
        }
        let app = client.bundleIdentifier()
        anchorMemory.enter(PanelAnchor.Field(client: ObjectIdentifier(self), app: app, session: fieldSession))
        anchorMemory.learnWindow { (ProfiledTextClient.window, false) }
        let placed = FieldAnchor.place(in: field, app: app, selection: session.composer.selection?.range, memory: &anchorMemory,
                                       lastByApp: &lastAnchorByApp, screens: [ProfiledTextClient.screen],
                                       pointer: { CGPoint(x: 700, y: 500) }, accessibility: { _ in nil })
        (panel, anchor, reasksAnchor) = (model, placed, placed.placement.reasks)
    }

    private func reaskAnchor() {
        reasksAnchor = false
        guard panel != nil else { return }
        let (found, _) = FieldAnchor.reasked(in: field, selection: session.composer.selection?.range, memory: &anchorMemory,
                                             screens: [ProfiledTextClient.screen])
        if let found { anchor = FieldAnchor.Placed(told: found, placement: PanelAnchor.Placement(rect: found, source: .field)) }
    }

    /// The controller's `typeOut`, at once: `TypeOut.Typist` into the field (`TypingField`), no typos, a turn for a field
    /// that tells its caret late.
    private func typeOut(_ text: String) {
        let typing = TypingField(field, pastesControls: false)
        let plan = TypeOut.plan(for: text, rate: session.typeOutRate, varies: false, mistakes: false)
        var typist = TypeOut.Typist(plan, start: typing.caret ?? 0, length: typing.length)
        for _ in 0..<(text.count * 4 + 16) {
            let progress = typist.step(in: typing)
            if progress == .done { break }
            if progress == .waiting { client.endTurn() }
        }
        committed += text
        for character in text { expectedCounts[character, default: 0] += 1 }
        note("typed out \(text.debugDescription)")
    }

    /// `body` has Chromium's page make the marked text plain text itself (`finishComposingText`): in the field now, as
    /// the app's own (`EXPECT nolost`), and the text the session commits next if it is the same.
    private func pageFinishes(_ body: () -> Void) {
        let marked = client.markedText
        let before = client.doc
        body()
        guard client.doc != before, let marked else { return }
        appChanged(from: before)
        pageFinished = marked
    }

    /// The app changed the field on its own (`appHandles`): what it typed or took out counts for `EXPECT nolost`.
    private func appChanged(from before: String) {
        let (old, new) = (Self.counts(before), Self.counts(client.doc))
        for character in Set(old.keys).union(new.keys) {
            expectedCounts[character, default: 0] += new[character, default: 0] - old[character, default: 0]
        }
    }

    static func counts(_ text: String) -> [Character: Int] {
        text.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    /// `text` without its syllable splits: the spaces between two Latin letters.
    static func unsplit(_ text: String) -> String {
        let characters = Array(text)
        var kept = ""
        for (index, character) in characters.enumerated() {
            if character == " ", index > 0, index + 1 < characters.count,
               characters[index - 1].isASCII && characters[index - 1].isLetter,
               characters[index + 1].isASCII && characters[index + 1].isLetter { continue }
            kept.append(character)
        }
        return kept
    }
}

// MARK: - Expectations

extension HostReplayer {
    private func check(_ expectation: HostCase.Expectation, line: Int) {
        func fail(_ message: String) { failures.append("line \(line): \(message)") }
        switch expectation {
        case let .doc(expected):
            // `|` and `[…]` in it are the caret and the selection, checked too (contract v1.3, as the core's runner does).
            let markup = (try? HostText(markup: expected)) ?? HostText()
            if client.doc != markup.text {
                fail("doc is \(client.doc.debugDescription), expected \(markup.text.debugDescription)")
            } else if expected.contains("|") || expected.contains("["), client.state.marked == nil,
                      client.state.selection != markup.selection {
                fail("the selection is \(client.state.selection), expected \(markup.selection) (\(expected.debugDescription))")
            }
        case let .marked(expected):
            if client.markedText != expected {
                fail("marked is \(client.markedText?.debugDescription ?? "none"), expected \(expected?.debugDescription ?? "none")")
            }
        case let .preedit(expected, caret):
            let input = panel?.input
            let line = input.map { $0.prompt + $0.text }.flatMap { $0.isEmpty ? nil : $0 }
            // A syllable split isn't compared (the core's runner does the same): librime shows "ni hao", the fake "nihao".
            if line.map(Self.unsplit) != expected.map(Self.unsplit) {
                fail("preedit is \(line?.debugDescription ?? "none"), expected \(expected?.debugDescription ?? "none")")
            } else if let caret, let expected, let line, let input {
                let before = input.caret.map { String(line.prefix(input.prompt.count + $0)) }
                if before.map(Self.unsplit) != Self.unsplit(String(expected.prefix(caret))) {
                    fail("the preedit's caret is after \(before?.debugDescription ?? "none"), expected after \(String(expected.prefix(caret)).debugDescription)")
                }
            }
        case let .panel(shown):
            checkPanel(shown: shown, fail: fail)
        case let .language(expected):
            let now = session.composer.inputLanguage
            if now != expected { fail("language is \(now.rawValue), expected \(expected.rawValue)") }
        case let .contextBefore(expected):
            // What a pause reads (autocomplete's `SessionOutput.readField`), as the field tells it now.
            let read = reading.contextAfterPause(in: client, id: 1).text?.before
            if read != expected {
                fail("context before is \(read?.debugDescription ?? "unreadable"), expected \(expected?.debugDescription ?? "unreadable")")
            }
        case let .switches(expected):
            if switches != expected { fail("\(switches) language switches, expected \(expected)") }
            switches = 0
        case let .calls(budgets):
            for budget in budgets {
                let counts = keyCalls.map { $0[budget.method, default: 0] }
                if let worst = counts.max(), !budget.holds(worst) {
                    fail("\(worst) calls of \(budget.method) in one key, expected \(budget) (per key: \(counts))")
                }
            }
            keyCalls = []
        case .noLost:
            let have = Self.counts(client.doc)
            let lost = Set(committed).filter { have[$0, default: 0] != expectedCounts[$0, default: 0] }
            if !lost.isEmpty {
                let detail = lost.sorted().map { "\($0) \(have[$0, default: 0])/\(expectedCounts[$0, default: 0])" }
                fail("committed characters not in the doc exactly once (have/expected): \(detail.joined(separator: ", ")); doc \(client.doc.debugDescription)")
            }
        }
    }

    /// Shown: the session has a panel up, and the Mac put it on the screen (`FieldAnchor`).
    private func checkPanel(shown: Bool, fail: (String) -> Void) {
        guard shown else {
            if panel != nil { fail("the panel is shown, expected hidden") }
            return
        }
        guard panel != nil else { return fail("the panel is hidden, expected shown") }
        guard let anchor else { return fail("the panel is shown with no anchor") }
        if !ProfiledTextClient.screen.insetBy(dx: -2, dy: -2).intersects(anchor.placement.rect.insetBy(dx: -1, dy: -1)) {
            fail("the panel is anchored off the screen: \(anchor.placement.rect) (\(anchor.placement.source))")
        }
    }
}
