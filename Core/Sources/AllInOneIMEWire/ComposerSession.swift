import AllInOneIMECore
import Foundation

/// What the engine does for a session that the wire doesn't carry (§6 "What the engine does itself"): the engine's
/// equivalent of the Mac input controller's `perform`. Called on the session's connection queue; what it starts that
/// answers later (level two's stream, a search) comes back through `ComposerSession.feed`.
public protocol WireHost: AnyObject, Sendable {
    /// An effect the adapter doesn't map to outputs: level two's requests (`startConversion` …), `cancelConversion`,
    /// notices, opening things, the clipboard, voice …
    func perform(_ effect: Composer.Effect, in session: ComposerSession)
    /// The engine's own panel for `session`: shown (or drawn again, from `session.composer`), or hidden.
    func panel(shown: Bool, in session: ComposerSession)
    /// A caret report (`session.caret`): where the panel goes.
    func caretMoved(in session: ComposerSession)
    /// Whether the client's process owns the foreground window now: what a privileged effect from a key needs (§8).
    func ownsForeground(_ peer: WirePeer) -> Bool
    /// The session is gone (closed, or its connection): stop what runs for it.
    func sessionClosed(_ session: ComposerSession)
    /// The session took the focus (not a `focus` re-sent while it has it): the Mac's `activateServer`, where the shell
    /// applies its settings to the Composer (and gives it its level-one engine once that is ready).
    func sessionFocused(_ session: ComposerSession)
}

extension WireHost {
    public func caretMoved(in session: ComposerSession) {}
    public func ownsForeground(_ peer: WirePeer) -> Bool { true }
    public func sessionClosed(_ session: ComposerSession) {}
    public func sessionFocused(_ session: ComposerSession) {}
}

/// Who is at the other end of a connection (§2.1, §8), as the transport found out on connect.
public struct WirePeer: Equatable, Sendable {
    public enum Integrity: Int, Comparable, Sendable {
        case untrusted, low, medium, high, system
        public static func < (a: Integrity, b: Integrity) -> Bool { a.rawValue < b.rawValue }
    }

    /// The client's process (`GetNamedPipeClientProcessId`); nil where there is none (Android, tests).
    public var pid: UInt32?
    /// Its executable's name, worked out by the engine: overrides the client's `field.process`.
    public var process: String?
    /// "win:<exe>" or "win:<AUMID>", worked out by the engine: overrides the client's `field.app`.
    public var app: String?
    public var integrity: Integrity
    public var appContainer: Bool

    public init(pid: UInt32? = nil, process: String? = nil, app: String? = nil, integrity: Integrity = .medium,
                appContainer: Bool = false) {
        self.pid = pid
        self.process = process
        self.app = app
        self.integrity = integrity
        self.appContainer = appContainer
    }

    /// Medium integrity or higher, outside an AppContainer (§8). An untrusted session only types and rewrites.
    public var trusted: Bool { integrity >= .medium && !appContainer }
}

/// One text field's session, run by the core's `Composer`: the adapter until `InputSession` (plan step 8) exists (§11).
/// It builds the Composer's key events from `WindowsKeyCodes`, feeds it the field's context, does the Mac input
/// controller's checks before a key, and maps the Composer's effects to outputs: the marked text to `composition`
/// (UTF-16 caret; `draft`, or `converted` at level two; none while the draft is in the panel), the commits to `commit`,
/// the panel to the engine's own and to `panel` when that changes; the rest goes to the `WireHost`.
///
/// Only used on its connection's queue.
public final class ComposerSession: @unchecked Sendable {
    public let sid: UInt32
    public let peer: WirePeer
    public let composer: Composer
    /// The field, with the engine's own `app` and `process` where it knows them.
    public private(set) var field: FieldInfo
    /// The latest `focus` serial.
    public private(set) var focusSerial: UInt32 = 0
    public private(set) var isFocused = false
    /// The document as the last key or `applied` told it.
    public private(set) var context: FieldContext?
    /// The latest caret report: `[x, y, width, height]` in physical screen pixels, and whether it is the caret's own.
    public private(set) var caret: (rect: [Int], hwnd: UInt64?, exact: Bool)?
    /// The client asked for the `allowForeground` op (`hello.capabilities`).
    public let allowsForeground: Bool

    let host: WireHost
    /// Runs work on the connection's queue, later.
    let enqueue: @Sendable (@escaping @Sendable () -> Void) -> Void
    /// Sends outputs to the client on the session's own (`apply`): set by the server.
    var pushOutputs: ([Output]) -> Void = { _ in }
    /// Logs, sizes and kinds only (never text).
    let log: @Sendable (String) -> Void

    /// The composition the document has, as we last set it (empty: none).
    private var documentComposition = ComposerSession.noComposition
    /// The client's panel state, as we last told it.
    private var panelShown = false
    private var markedWatch = MarkedTextWatch()
    private var secureNoticeShown = false
    private var alive = true
    /// Whether the client's process owned the foreground when the key being handled arrived (asked once, when needed).
    private var keyInForeground: Bool?

    static let noComposition = Output.composition(text: "")

    public init(sid: UInt32, field: FieldInfo, peer: WirePeer, composer: Composer, host: WireHost, allowsForeground: Bool,
                enqueue: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.sid = sid
        self.peer = peer
        self.composer = composer
        self.host = host
        self.allowsForeground = allowsForeground
        self.enqueue = enqueue
        self.log = log
        self.field = field
        composer.modifierRoles = .windows
        composer.readSelection = { [unowned self] in
            guard let context = self.context, !context.selText.isEmpty else { return nil }
            return Composer.Selection(text: context.selText, range: context.selection)
        }
        composer.characterBeforeCaret = { [unowned self] in self.context?.before.last }
        composer.secureInputActive = { [unowned self] in self.field.secure }
        applyIdentity()
    }

    // MARK: - Focus

    /// `focus`: the session takes the focus (or keeps it, with a new field).
    func focus(serial: UInt32, field newField: FieldInfo?) -> [Output] {
        var outputs: [Output] = []
        if let newField {
            let wasSecure = field.secure
            field = newField
            applyIdentity()
            // A field that turned into a password field: what is pending goes in as typed, as the Mac does.
            if newField.secure, !wasSecure, isFocused, composer.isComposing { outputs = map(composer.commitAsTyped(), from: .async) }
        }
        focusSerial = serial
        if !isFocused {
            isFocused = true
            documentComposition = Self.noComposition
            markedWatch.reset()
            secureNoticeShown = false
            context = nil
            host.sessionFocused(self)
        }
        return outputs
    }

    /// `blur` (§4): the Composer's policy, `commitAll`: pending text goes in, running requests stop.
    func blur() -> [Output] {
        guard isFocused else { return [] }
        let outputs = map(composer.commitAll(), from: .async) + hidePanel()
        isFocused = false
        documentComposition = Self.noComposition
        return outputs
    }

    /// `close`, or the connection gone: nothing more goes in, and whatever runs stops (§4 "Disconnects").
    func close() {
        guard alive else { return }
        for effect in composer.appTookMarkedText() {
            switch effect {
            case .hidePanel: host.panel(shown: false, in: self)
            default: host.perform(effect, in: self)
            }
        }
        alive = false
        isFocused = false
        host.sessionClosed(self)
    }

    /// `endComposition` (§5.5): the app ended our composition ("terminated": what is pending goes in, as `commitAll`
    /// has it), or the client gave up on a key ("timeout"). After a timeout the client has ended the composition itself,
    /// leaving the draft as typed in the document (`composition.typed`), and the app has had the key since: the draft
    /// starts over and the panel goes, with no composition sent, since an empty one would remove that text.
    func endComposition(reason: String) -> [Output] {
        guard reason == "timeout" else { return map(composer.commitAll(), from: .async) + hidePanel() }
        documentComposition = Self.noComposition
        markedWatch.reset()
        return map(composer.appTookMarkedText(), from: .async) + hidePanel()
    }

    /// `applied`'s document.
    func applied(context: FieldContext?) {
        if let context { self.context = context }
    }

    /// A caret report. The client reports only while the panel is shown (§6), so the caret is forgotten when it hides:
    /// a panel shown later waits for the report that follows, rather than going where the last one was.
    func caretReported(rect: [Int], hwnd: UInt64?, exact: Bool) {
        caret = (rect, hwnd, exact)
        host.caretMoved(in: self)
    }

    // MARK: - Keys

    /// A key-down (§5): whether it was handled, and the outputs (applied whether or not it was).
    func keyDown(_ frame: KeyFrame) -> (handled: Bool, outputs: [Output]) {
        if let context = frame.ctx { self.context = context }
        keyInForeground = nil
        defer { keyInForeground = nil }
        guard let key = Self.read(frame.key) else { return (false, []) }  // a fake Shift: no key was pressed
        if case .modifier = key.key {
            // Held down, a modifier repeats its key-down: no change.
            if frame.key.isRepeat { return (false, []) }
            return (false, flagsChanged(key, t: frame.t))
        }
        var gate: [Output] = []
        // Password fields: never compose; anything typed already goes in as typed. (The DLL sends no keys from them.)
        if field.secure {
            if composer.isComposing { gate = map(composer.commitAsTyped(), from: .key) }
            if !secureNoticeShown, !key.text.isEmpty {
                secureNoticeShown = true
                host.perform(.notice(Self.secureNotice), in: self)
            }
            return (false, gate)
        }
        secureNoticeShown = false
        // The app took our composition without saying so (§5.1 `comp`): start over rather than set it again, doubled.
        // This key is dropped, so ⏎ doesn't send half a sentence.
        if let ctx = frame.ctx, composer.isComposing, !composer.draftInPanel {
            let expected = compositionText
            if markedWatch.appTookText(expected: expected, reportedLength: ctx.comp) {
                log("session \(sid): the app took the composition: starting over")
                let outputs = map(composer.appTookMarkedText(), from: .key)
                documentComposition = Self.noComposition
                markedWatch.reset()
                return (true, outputs)
            }
            markedWatch.didSet(expected: expected, reportedLength: ctx.comp)
        }
        // The selection a command is written on changed (a click, the app's own keys): the command is given up.
        if let written = composer.selection?.range, let now = frame.ctx?.selection, now != written {
            log("session \(sid): the selection moved under a command: given up")
            gate += map(composer.selectionMoved(), from: .key)
        }
        let event = key.event(modifiers: key.modifiers.subtracting(.sides))
        let response = composer.handleKeyDown(event)
        return (response.handled, gate + map(response.effects, from: .key))
    }

    /// A key-up (§5.2): a modifier's is a modifier change; others (sent with the `keyUps` capability only) do nothing.
    func keyUp(_ frame: KeyFrame) -> (handled: Bool, outputs: [Output]) {
        if let context = frame.ctx { self.context = context }
        guard let key = Self.read(frame.key), case .modifier = key.key, !field.secure else { return (false, []) }
        return (false, flagsChanged(key, t: frame.t))
    }

    private func flagsChanged(_ key: ReadKey, t: UInt64) -> [Output] {
        guard !field.secure else { return [] }
        return map(composer.handleFlagsChanged(key: key.key, modifiers: key.modifiers, timestamp: Double(t) / 1000), from: .key)
    }

    // MARK: - From the engine's side

    /// Where effects come from: a key (privileged ones need the client in the foreground), a click in the engine's
    /// own panel (the user's act there), or later work (a stream, a search).
    public enum Origin: Sendable { case key, click, async }

    /// Runs `body` with the Composer on the connection's queue, later, and sends the outputs of the effects it returns
    /// to the client (`apply`), if the session still has the focus: level two's results, a click in the panel.
    public func feed(from origin: Origin = .async, _ body: @escaping @Sendable (Composer) -> [Composer.Effect]) {
        enqueue { [self] in
            guard alive else { return }
            run(from: origin, body)
        }
    }

    /// `feed`, now: on the connection's queue already.
    func run(from origin: Origin, _ body: (Composer) -> [Composer.Effect]) {
        let outputs = map(body(composer), from: origin)
        guard !outputs.isEmpty else { return }
        guard isFocused else {
            log("session \(sid): \(outputs.count) outputs for a field no longer focused: dropped")
            return
        }
        pushOutputs(outputs)
    }

    /// A row clicked in the engine's panel (`Composer.choose(index:)`).
    public func choose(row: Int) {
        feed(from: .click) { $0.choose(index: row) }
    }

    // MARK: - Effects → outputs

    func map(_ effects: [Composer.Effect], from origin: Origin) -> [Output] {
        var outputs: [Output] = []
        for effect in effects {
            switch effect {
            case .updateMarkedText:
                let composition = currentComposition
                if composition != documentComposition {
                    outputs.append(composition)
                    documentComposition = composition
                }
            case let .commit(text), let .replaceSelection(text, _):
                outputs.append(.commit(text: text))
                documentComposition = Self.noComposition
            case let .commitAfterKey(text):
                outputs.append(.commit(text: text, afterKey: true))
                documentComposition = Self.noComposition
            case let .typeOut(text):
                // Typed out step by step (`apply` pushes, each after the last `applied`) comes later: in one go now.
                outputs.append(.commit(text: text))
                documentComposition = Self.noComposition
            case .showPanel:
                host.panel(shown: true, in: self)
                if !panelShown {
                    panelShown = true
                    outputs.append(.panel(shown: true))
                }
            case .hidePanel:
                host.panel(shown: false, in: self)
                if panelShown {
                    panelShown = false
                    caret = nil
                    outputs.append(.panel(shown: false))
                }
            default:
                if let refusal = refusal(of: effect, from: origin) {
                    outputs += refuse(effect, refusal, from: origin)
                } else {
                    if allowsForeground, Self.takesForeground(effect), !outputs.contains(.allowForeground) {
                        outputs.append(.allowForeground)
                    }
                    host.perform(effect, in: self)
                }
            }
        }
        return outputs
    }

    /// `panel` hidden, if the client still has it shown.
    private func hidePanel() -> [Output] {
        guard panelShown else { return [] }
        panelShown = false
        caret = nil
        host.panel(shown: false, in: self)
        return [.panel(shown: false)]
    }

    /// The composition for the Composer's marked text now, with the draft as typed when that isn't what is shown.
    private var currentComposition: Output {
        guard !composer.draftInPanel else { return Self.noComposition }
        let text = composer.markedText
        guard !text.isEmpty else { return Self.noComposition }
        let caret = String(text.prefix(max(composer.markedCursor, 0))).utf16.count
        let style = composer.isLevelTwo ? Segment.Style.converted : Segment.Style.draft
        let typed = composer.textAsTyped
        return .composition(text: text, caret: caret, segments: [Segment(from: 0, to: text.utf16.count, style: style)],
                            typed: typed.isEmpty || typed == text ? nil : typed)
    }

    private var compositionText: String {
        if case let .composition(text, _, _, _) = documentComposition { return text }
        return ""
    }

    // MARK: - Trust (§8)

    /// Why `effect` isn't done, if it isn't: an untrusted client gets no privileged effect, and one from a key needs the
    /// client in the foreground.
    private func refusal(of effect: Composer.Effect, from origin: Origin) -> String? {
        guard Self.isPrivileged(effect) else { return nil }
        if !peer.trusted { return Self.untrustedNotice }
        if origin == .key {
            if keyInForeground == nil { keyInForeground = host.ownsForeground(peer) }
            if keyInForeground == false { return Self.backgroundNotice }
        }
        return nil
    }

    private func refuse(_ effect: Composer.Effect, _ notice: String, from origin: Origin) -> [Output] {
        log("session \(sid): refused \(Self.kind(of: effect)) (\(peer.trusted ? "not in the foreground" : "untrusted client"))")
        host.perform(.notice(notice), in: self)
        switch effect {
        case let .startCommand(_, _, id), let .search(_, id), let .listAgents(id), let .previewReminder(_, id),
             let .startRun(_, _, id), let .startScript(_, _, _, id, _), let .reask(_, _, id), let .startPlan(_, _, id):
            return map(composer.fail(notice, id: id), from: origin)
        case let .readClipboard(id):
            return map(composer.pasted(nil, id: id), from: origin)
        case let .startVoice(id, _):
            return map(composer.voiceFailed(notice, id: id), from: origin)
        default:
            return []
        }
    }

    /// Effects that run, open, search files, read the clipboard or history, send, record or keep (§8): an untrusted
    /// client gets none. Typing, and AI rewriting and translating its own text, are the rest.
    static func isPrivileged(_ effect: Composer.Effect) -> Bool {
        switch effect {
        case .startCommand, .search, .open, .openLink, .runInTerminal, .continueInClaudeCode, .continueInAgent,
             .launchInTerminal, .startBackgroundAgent, .listAgents, .openSettings, .saveNote, .previewReminder,
             .addReminder, .startRun, .startScript, .startBackgroundScript, .sendMessage, .rememberQuestion, .reask,
             .startPlan, .copy, .readClipboard, .startVoice, .armVoice:
            return true
        default:
            return false
        }
    }

    /// Effects after which the engine's window or another program comes to the front (§6 `allowForeground`).
    static func takesForeground(_ effect: Composer.Effect) -> Bool {
        switch effect {
        case .open, .openLink, .runInTerminal, .continueInClaudeCode, .continueInAgent, .launchInTerminal, .openSettings:
            return true
        default:
            return false
        }
    }

    /// An effect's name, for logs (never its text).
    public static func kind(of effect: Composer.Effect) -> String {
        String(String(describing: effect).prefix { $0 != "(" })
    }

    static let secureNotice = "Secure input: the input method is paused, keys go straight in"
    static let untrustedNotice = "Not available in this app (it runs sandboxed)"
    static let backgroundNotice = "Not run: the app isn't in the foreground"

    // MARK: - Fields

    /// The engine's own app identity over the client's (§4), and what the field's app is (a terminal).
    private func applyIdentity() {
        if let app = peer.app { field.app = app }
        if let process = peer.process { field.process = process }
        let terminal = Self.isTerminal(field.process)
        // Terminals send what is inserted during a key in its place, and paste on Ctrl+V themselves.
        composer.appTakesKeysAfterInsert = !terminal
        composer.pastesIntoDraft = !terminal
    }

    /// Windows' terminals (and their hosts), by executable name.
    static let terminals: Set<String> = [
        "windowsterminal.exe", "wt.exe", "openconsole.exe", "conhost.exe", "cmd.exe", "powershell.exe", "pwsh.exe",
        "mintty.exe", "alacritty.exe", "wezterm-gui.exe", "putty.exe", "kitty.exe", "tabby.exe", "hyper.exe",
        "conemu.exe", "conemu64.exe", "windterm.exe", "mobaxterm.exe", "warp.exe",
    ]

    public static func isTerminal(_ process: String) -> Bool { terminals.contains(process.lowercased()) }

    // MARK: - Reading a key

    /// A key as the Composer takes it: its `Key` and usage, worked out from the raw codes (`WindowsKeyCodes`) when the
    /// client sent them, and the modifiers normalized (§5.1).
    struct ReadKey {
        var key: Key
        var usage: UInt16
        var text: String
        var textIgnoringModifiers: String
        var modifiers: Modifiers
        var isRepeat: Bool
        var isDeadKey: Bool

        func event(modifiers: Modifiers) -> KeyEvent {
            var event = KeyEvent(key: key, usage: usage, characters: text, charactersIgnoringModifiers: textIgnoringModifiers,
                                 modifiers: modifiers, isRepeat: isRepeat)
            event.isDeadKey = isDeadKey
            return event
        }
    }

    /// Nil for a fake Shift (`WindowsKeyCodes.isFakeShift`): Windows' own, around a keypad key.
    static func read(_ wire: WireKey) -> ReadKey? {
        var modifiers = wire.modifiers
        let key: Key, usage: UInt16
        if let vk = wire.vk {
            let scan = UInt8(truncatingIfNeeded: wire.scan ?? 0)
            if [0x10, 0xA0, 0xA1].contains(vk), WindowsKeyCodes.isFakeShift(scanCode: scan, extended: wire.extended) { return nil }
            usage = wire.scan == nil ? 0 : WindowsKeyCodes.usage(scanCode: scan, extended: wire.extended)
            key = WindowsKeyCodes.key(virtualKey: vk, usage: usage)
            modifiers = WindowsKeyCodes.markingAltGraph(modifiers, rightAltDown: modifiers.contains(.rightOption))
        } else {
            usage = wire.usage ?? 0
            key = wire.key ?? .other
        }
        return ReadKey(key: key, usage: usage, text: wire.text, textIgnoringModifiers: wire.textIgnoringModifiers ?? wire.text,
                       modifiers: modifiers, isRepeat: wire.isRepeat, isDeadKey: wire.isDeadKey)
    }
}
