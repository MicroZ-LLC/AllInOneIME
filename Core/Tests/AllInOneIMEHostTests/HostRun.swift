import Foundation
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// A scenario replayed against one profile, through the core alone: the session (`InputSession`) in a field of the
/// profile's host (`FakeHost`, told by `HostField`), with what a shell does between them done as the Mac's input
/// controller does it: what the session wants of the field read through the host's API (`FieldReader`), copies of events
/// dropped before the session sees them (`KeyEchoes`, `ModifierEchoes`, `CapsLockCopies`), the marked text watched
/// (`MarkedTextWatch`). Time is the run's own (`now`): the keys `keyGap` apart, a profile's copies and the session's
/// timers coming when it reaches them. Every check that fails is kept (`failures`), with the scenario's line.
final class HostRun {
    let scenario: HostCase
    let profile: HostProfile
    let host: FakeHost
    let field: HostField
    let clock: HostClock
    let settings: HostSettings

    /// Between two keys typed, and between Shift and the key it is held for.
    static let keyGap: TimeInterval = 0.08
    static let shiftLead: TimeInterval = 0.03

    var now: TimeInterval { clock.now }
    var agenda = HostAgenda()
    var keyEchoes = KeyEchoes()
    var modifierEchoes = ModifierEchoes()
    var capsLockCopies = CapsLockCopies()
    var ledger = CommitLedger()
    /// The marked text in the field is the session's (else the app's own, set by `TEXT`).
    var markedBySession = false
    /// The field has the focus; the session was given it at all; the input source is ABC (keys go to the app).
    var focused = false
    var started = false
    var inABC = false
    /// Caps Lock's lock, and the modifiers held.
    var lockOn = false
    var held: Modifiers = []
    /// Language switches since the last `EXPECT switches`, and the language last seen.
    var switches = 0
    var language: Language?
    /// The host calls each key made since the last `EXPECT calls`.
    var keyCalls: [(line: Int, key: String, calls: HostCallCount)] = []
    /// The app's undo: the field before each change, with what the ledger held then.
    var undo: [(document: String, caret: Int, ledger: CommitLedger)] = []
    var failures: [HostFailure] = []
    /// After every step, the stress runs' checks too (`checkStrictInvariants`), not only `checkInvariants`.
    var strict = false
    /// The modifier changes the session was told (their copies dropped), in order.
    var modifierChanges: [ModifierChange] = []
    var line = 0

    init(_ scenario: HostCase, profile: HostProfile) {
        self.scenario = scenario
        self.profile = profile
        // The scenarios' settings, the Mac's replayer's too (`HostScenarioSettings`), with the scenario's `SET` lines (read
        // and checked as it was parsed: one the config doesn't take never gets here).
        let language: Language = scenario.language == .chinese ? .chinese : .english
        let config = (try? HostScenarioSettings.config(startingIn: language, set: scenario.settings))
            ?? Config.default
        let settings = HostSettings(config)
        self.settings = settings
        let clock = HostClock()
        self.clock = clock
        var services = SessionServices(converter: Converter(loadConfig: { settings.config }, appleModel: HostScenarioSettings.SilentModel()),
                                       loadSettings: { settings.config })
        let engine = FakeEngine()
        services.levelOne = { .engine(engine) }
        services.uptime = { clock.now }
        services.pointerUsedWithin = { _ in clock.clicked }
        services.buttonUsedWithin = { _ in clock.clicked }
        let host = FakeHost(services: services)
        host.app = profile.app
        host.terminal = profile.terminal
        host.caretOffset = 0
        self.host = host
        field = HostField(host: host, profile: profile)
        host.reading = FakeHost.FieldReads(context: { [weak self] in self?.reader.everything() ?? FieldContext() },
                                           text: { [weak self] in self?.field.text(in: $0) })
        host.inserted = { [weak self] change in self?.changed(change) }
    }

    /// The shell's reading of the field now.
    var reader: FieldReader { FieldReader(field: field) }

    /// Runs the scenario's steps for this profile; what failed.
    func run() -> [HostFailure] {
        for step in scenario.steps where step.applies(to: profile) {
            line = step.line
            if case .text = step.action {} else if !started { start() }
            perform(step.action)
            checkInvariants()
            if strict { checkStrictInvariants() }
        }
        return failures
    }

    func fail(_ message: String) {
        failures.append(HostFailure(line: line, message: message))
    }

    private func perform(_ action: HostAction) {
        switch action {
        case let .text(markup): setField(markup)
        case let .type(text): text.forEach(type)
        case let .keys(keys): keys.forEach(press)
        case let .click(offset): click(at: offset)
        case let .focus(change): focus(change)
        case let .switchSource(toABC): switchSource(toABC: toABC)
        case .appClears: appClears()
        case let .wait(seconds): wait(seconds)
        case let .expect(expectation):
            settle()
            check(expectation)
        }
    }

    /// The field takes the focus for the first time.
    private func start() {
        started = true
        focusAgain()
    }

    // MARK: Time

    /// The clock moved on to `time`: what is due by then comes, in order.
    func advance(to time: TimeInterval) {
        while let (due, item) = agenda.next(until: time) {
            clock.now = max(now, due)
            switch item {
            case let .copy(event): deliver(event, copy: true)
            case let .timer(id): fire(id)
            case .lockOff: lockGoesOff()
            }
        }
        clock.now = max(now, time)
    }

    func pause(_ seconds: TimeInterval) { advance(to: now + seconds) }

    func wait(_ seconds: TimeInterval) {
        pause(seconds)
        host.settle(timeout: 0) { false }
    }

    /// Before a check: the copies still on their way come, and what the session's work answered meanwhile.
    func settle() {
        if let last = agenda.lastCopy { advance(to: last) }
        host.settle(timeout: 0) { false }
    }

    private func fire(_ timer: TimerID) {
        let start = host.outputs.count
        field.beginTurn()
        host.fireTimers { $0 == timer }
        field.endTurn()
        followOutputs(from: start)
        _ = field.takeCalls()  // a timer's reads aren't a key's
    }

    // MARK: Keys

    /// A character typed: Shift held around it where it needs it.
    func type(_ character: Character) {
        let key = HostKeys.event(typing: character)
        down(key, shifted: key.modifiers.contains(.shift))
        pause(Self.keyGap)
    }

    func press(_ spec: KeySpec) {
        switch spec {
        case let .tap(kind):
            modifier(kind, down: true)
            pause(Self.keyGap)
            modifier(kind, down: false)
        case .capsLock:
            lockOn.toggle()
            if lockOn { capsLockCopies.lockSeenOn(at: now) }
            changeModifiers(.capsLock, code: HostKeys.capsLockCode)
        case let .key(named, modifiers):
            for kind in modifiers {
                modifier(kind, down: true)
                pause(Self.shiftLead)
            }
            let key = HostKeys.event(named, modifiers: modifiers)
            down(key, shifted: key.modifiers.contains(.shift) && !modifiers.contains(.shift))
            for kind in modifiers.reversed() {
                pause(Self.shiftLead)
                modifier(kind, down: false)
            }
        }
        pause(Self.keyGap)
    }

    /// A key goes down (Shift down before it and up after, where it is typed with Shift not named); with Caps Lock's lock
    /// on, a letter is a capital.
    private func down(_ key: KeyEvent, shifted: Bool) {
        var key = key
        if lockOn {
            key.modifiers.insert(.capsLock)
            if key.characters.count == 1, key.characters.first?.isLetter == true, key.modifiers.isDisjoint(with: [.command, .control]) {
                key.characters = key.characters.uppercased()
            }
        }
        if shifted {
            modifier(.shift, down: true)
            pause(Self.shiftLead)
        }
        if focused, !inABC {
            deliver(.key(key, time: now), copy: false)
        } else if focused {
            appActs(on: key, typing: true)  // ABC: the app has it
        }
        if shifted {
            pause(Self.shiftLead)
            modifier(.shift, down: false)
        }
    }

    private func modifier(_ kind: Key.ModifierKind, down: Bool) {
        if down { held.formUnion(HostKeys.left(kind)) } else { held.subtract(HostKeys.left(kind)) }
        changeModifiers(.modifier(kind, .left), code: HostKeys.code(of: kind))
    }

    private func changeModifiers(_ key: Key, code: UInt16) {
        guard focused, !inABC else { return }
        let change = ModifierChange(key: key, modifiers: held.union(lockOn ? .capsLock : []), timestamp: now)
        deliver(.modifiers(change, code: code), copy: false)
    }

    /// The lock goes off as the input method asked (`PlatformAction.setCapsLock(false)`), and the host tells that change.
    private func lockGoesOff() {
        guard lockOn else { return }
        lockOn = false
        changeModifiers(.capsLock, code: HostKeys.capsLockCode)
    }

    // MARK: Events

    /// `event` handed to the session as a shell does: a copy of one handed over before is dropped first, and one that
    /// isn't is a failure (the session took one key or change for two).
    func deliver(_ event: HostEvent, copy: Bool) {
        field.beginTurn()
        defer { field.endTurn() }
        switch event {
        case let .key(key, time): deliverKey(key, time: time, copy: copy)
        case let .modifiers(change, code): deliverModifiers(change, code: code, copy: copy)
        }
    }

    private func deliverKey(_ key: KeyEvent, time: TimeInterval, copy: Bool) {
        let echo = KeyEchoes.Key(keyCode: key.keyCode, characters: key.characters, modifiers: UInt(key.modifiers.rawValue),
                                 isRepeat: key.isRepeat, timestamp: time)
        if keyEchoes.copy(of: echo, now: now) != nil { return }
        if copy { fail("the copy of \(Self.describe(key)) reached the session as a key of its own") }
        _ = field.takeCalls()
        let start = host.outputs.count
        let before = (host.document, host.caret, ledger)
        let context = reader.context { host.session.fieldWants(for: key, given: $0) }
        let composing = host.composer.isComposing
        host.appTypesKeys = !copy
        let handled = host.press(key, with: context)
        host.appTypesKeys = false
        clock.clicked = false
        keyEchoes.answered(echo, now: now, handled: handled)
        if !handled, !copy {
            appActs(on: key, typing: false)
            if let delay = profile.copyDelay { agenda.add(.copy(.key(key, time: time)), at: now + delay) }
        }
        followOutputs(from: start)
        remember(before)
        // A terminal's shell gets a key the session took, where the Mac's shell wouldn't have kept it from it.
        if handled, !copy, terminalSends(composing: composing, outputs: host.outputs[start...]) {
            appActs(on: key, typing: true)
        }
        keyCalls.append((line, Self.describe(key), field.takeCalls()))
    }

    /// Whether a terminal sends a key the session took to its shell as well (`HostProfile.actsOnTakenKeys`): it does
    /// unless text went in during the key or marked text is in the field after it, and the Mac's shell marks a space
    /// during the key (`AllInOneIMEInputController.keepFromTerminal`) where the key composed (`keyComposes`: what is
    /// being written before or after it) or the rows took it (`rowByKey`, `rowsTookKey`). What goes in once the key is
    /// done (`commitAfterKey`) isn't during it.
    func terminalSends(composing: Bool, outputs: ArraySlice<SessionOutput>) -> Bool {
        guard profile.actsOnTakenKeys, host.marked.isEmpty else { return false }
        let rowsTook = outputs.contains { if case .rowByKey = $0 { true } else if case .rowsTookKey = $0 { true } else { false } }
        let inserted = outputs.contains {
            switch $0 {
            case .commit, .replace, .typeOut: true
            default: false
            }
        }
        let keptByShell = composing || host.composer.isComposing || rowsTook
        return !keptByShell && !inserted
    }

    private func deliverModifiers(_ change: ModifierChange, code: UInt16, copy: Bool) {
        let flags = UInt(change.modifiers.rawValue)
        if modifierEchoes.isEcho(keyCode: code, flags: flags, timestamp: change.timestamp, now: now) { return }
        if code == HostKeys.capsLockCode,
           capsLockCopies.isCopy(saysOn: change.modifiers.contains(.capsLock), lockOn: lockOn, timestamp: change.timestamp, now: now) {
            return
        }
        if copy { fail("the copy of a modifier change (\(change.key.name)) reached the session as a change of its own") }
        var change = change
        change.late = max(now - change.timestamp, 0)
        modifierChanges.append(change)
        let start = host.outputs.count
        let context = reader.context { [change] in host.session.fieldWants(forModifiers: change, given: $0) }
        host.send(.modifiers(change, context))
        clock.clicked = false
        if !copy, let delay = profile.copyDelay { agenda.add(.copy(.modifiers(change, code: code)), at: now + delay) }
        followOutputs(from: start)
        _ = field.takeCalls()
    }

    /// What the session's outputs since `start` ask of the shell: its timers started, the marked text it set watched,
    /// the lock it turned off; and whether the input language changed, as the user sees it: in the field with the focus
    /// (a session left, or closed with its engine, tells a language no one types in).
    func followOutputs(from start: Int) {
        for output in host.outputs[start...] {
            switch output {
            case let .startTimer(id, seconds):
                agenda.add(.timer(id), at: now + seconds)
            case .platform(.setCapsLock(false)) where lockOn:
                agenda.add(.lockOff, at: now + 0.01)
            default:
                break
            }
        }
        guard focused, !inABC else { return }
        let current = host.composer.inputLanguage
        if let language, language != current { switches += 1 }
        language = current
    }

    /// A change the session or the app made to the document (`FakeHost.inserted`).
    private func changed(_ change: FakeHost.Insertion) {
        if change.dropped {
            ledger.drop(change.text)
        } else {
            ledger.take(change.replaced)
            ledger.put(change.text)
        }
    }

    static func describe(_ key: KeyEvent) -> String {
        let names: [(Modifiers, String)] = [(.control, "ctrl+"), (.option, "opt+"), (.shift, "shift+"), (.command, "cmd+")]
        let held = names.filter { key.modifiers.contains($0.0) }.map(\.1).joined()
        let text = key.charactersIgnoringModifiers
        return held + (key.key == .character && !text.isEmpty ? text : key.key.name)
    }
}
