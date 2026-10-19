import AllInOneIMECore
import AllInOneIMEWire
import Foundation

/// The engine's `WireHost`: what the wire doesn't carry, done in the engine (§6). The Mac's `InputController.perform`
/// for Windows:
///
/// - **Level one:** each field's Composer types pinyin with librime (`EngineRime`) once it has deployed, in the
///   settings' input languages (Shift switches), and Latin letters without it.
/// - **The panel:** what the Composer would show (`PanelBuilder`), drawn by the engine's candidate window
///   (`PanelPresenter`) at the caret the DLL reports; a click on a row picks it (`ComposerSession.choose`).
/// - **Level two:** the AI requests through the core's `Converter` and the provider the settings name, the API key from
///   the Credential Manager (`APIKeys`); programs, scripts, plugins and `@js` through the core's runners (the Windows
///   process launcher, QuickJS in a child process of this program).
/// - **The rest:** the clipboard, opening addresses and files, terminal windows (`SystemActions`). What only macOS has
///   (Apple Notes, Reminders, Messages, dictation) says so in a notice.
///
/// In test mode (`--test`) the Composer types Latin letters, level two comes from a golden's `ScriptedProvider`, and
/// the client is taken to own the foreground, as the goldens expect.
public final class EngineHost: WireHost, @unchecked Sendable {
    public struct Options {
        public var testMode = false
        /// Whether the client's process owns the foreground window (§8).
        public var foreground: @Sendable (WirePeer) -> Bool = { _ in true }
        public var settings = EngineSettings()
        /// Level one's pinyin; nil: Latin letters only.
        public var rime: EngineRime?
        public var panel: PanelPresenter = NoPanel()
        public var system: SystemActions
        /// This program, for `@js` and script plugins, which run in a child process of it (`--run-js`, `--run-plugin`).
        public var executable: String = CommandLine.arguments.first ?? ""
        /// The requests' converter; nil: one on `settings` and the platform's API keys.
        public var converter: Converter?

        public init(system: SystemActions) {
            self.system = system
        }
    }

    public let testMode: Bool
    public let clock: WireClock
    let log: @Sendable (String) -> Void
    let foreground: @Sendable (WirePeer) -> Bool
    public let settings: EngineSettings
    public let rime: EngineRime?
    public let panelPresenter: PanelPresenter
    let system: SystemActions
    let executable: String
    public let converter: Converter

    private let lock = NSLock()
    private var scripted: ScriptedProvider?
    private var language: Language?
    private var states: [ObjectIdentifier: SessionState] = [:]

    public init(clock: WireClock = SystemClock(), options: Options, log: @escaping @Sendable (String) -> Void) {
        testMode = options.testMode
        self.clock = clock
        self.log = log
        foreground = options.foreground
        settings = options.settings
        rime = options.rime
        panelPresenter = options.panel
        system = options.system
        executable = options.executable
        let settings = options.settings
        converter = options.converter ?? Converter(loadConfig: { settings.current })
    }

    /// Test mode: level two's script (`#! provider`).
    public var provider: ScriptedProvider? {
        get { lock.lock(); defer { lock.unlock() }; return scripted }
        set { lock.lock(); scripted = newValue; lock.unlock() }
    }

    /// The input language new Composers start in, over the settings' (`#! inputLanguage` in test mode).
    public var inputLanguage: Language? {
        get { lock.lock(); defer { lock.unlock() }; return language }
        set { lock.lock(); language = newValue; lock.unlock() }
    }

    // MARK: - Sessions

    /// What the engine keeps for a session besides its Composer: its request under way, how long the last one took,
    /// its last caret (where a notice goes once the panel is down), the panel's owner.
    final class SessionState: @unchecked Sendable {
        weak var session: ComposerSession?
        var task: Task<Void, Never>?
        var elapsed: TimeInterval?
        var fromCache = false
        var caret: CaretRect?
        var appliedDefaultInput: Language?
        let owner: PanelOwner

        init(session: ComposerSession) {
            self.session = session
            owner = PanelOwner(pid: session.peer.pid, choose: { [weak session] row in session?.choose(row: row) },
                               scroll: { [weak session] steps in session?.feed(from: .click) { $0.scrollPalette(by: steps) } })
        }
    }

    func state(_ session: ComposerSession) -> SessionState {
        lock.lock()
        defer { lock.unlock() }
        if let state = states[ObjectIdentifier(session)] { return state }
        let state = SessionState(session: session)
        states[ObjectIdentifier(session)] = state
        return state
    }

    /// The sessions alive now.
    var liveSessions: [ComposerSession] {
        lock.lock()
        defer { lock.unlock() }
        return states.values.compactMap(\.session)
    }

    /// A field's Composer: pinyin (librime) once it is ready; Latin letters until then (librime deploys at the engine's
    /// start, a second or so, longer the first time in a user folder or with the disk busy), so English and the
    /// commands work from the first key; Latin letters only without librime, and in test mode, as the goldens have them.
    /// Its settings are applied as it takes the focus (`sessionFocused`).
    public func makeComposer(_ field: FieldInfo, _ peer: WirePeer) -> Composer {
        let engine: PinyinEngine = testMode ? LatinEngine() : rime?.makeEngine() ?? LatinEngine()
        let composer = Composer(engine: engine)
        if testMode { composer.setInputMode(inputLanguage ?? .english) }
        return composer
    }

    public func sessionFocused(_ session: ComposerSession) {
        let state = state(session)
        guard !testMode else { return }
        attachRime(to: session, state: state)
        apply(settings.current, to: session, state: state)
    }

    /// Gives `session`'s Composer a librime session in place of its Latin letters (or of a session a redeploy dropped),
    /// when librime is ready and nothing is being typed. Whether it did.
    @discardableResult
    func attachRime(to session: ComposerSession, state: SessionState) -> Bool {
        let composer = session.composer
        let current = composer.primaryEngine as? LockedRimeEngine
        guard current == nil || current?.isValid == false, !composer.isComposing, let engine = rime?.makeEngine() else { return false }
        composer.engine = engine
        state.appliedDefaultInput = nil  // a new session starts in the default input mode
        return true
    }

    /// librime finished deploying: the Composers made before get their session (those not in the middle of something;
    /// the others at their next focus).
    public func rimeBecameReady() {
        for session in liveSessions {
            session.feed { [weak self] _ in
                guard let self else { return [] }
                let state = self.state(session)
                if self.attachRime(to: session, state: state) { self.apply(self.settings.current, to: session, state: state) }
                return []
            }
        }
    }

    /// The settings on the Composer, as the Mac's `applySettings`: the action key, the candidates' layout, the
    /// languages, the commands, the interface language; the default input mode for a new session (and again when it
    /// changed in the settings).
    func apply(_ config: Config, to session: ComposerSession, state: SessionState) {
        let composer = session.composer
        let app = session.field.app
        composer.voiceEnabled = false  // no dictation on Windows yet
        composer.actionKey = config.actionKey
        composer.typesResults = false  // typed out step by step comes later (ComposerSession commits it in one go)
        composer.horizontalCandidates = config.candidateLayout == .horizontal
        composer.outputLanguages = config.outputLanguages
        composer.provider = config.provider
        let plugins = PluginStore.load().plugins
        composer.commands = Command.catalog(config.customCommands, plugins: plugins)
        let language = settings.interfaceLanguage(config)
        var messages = Composer.Messages.make(language: language)
        messages.actionKeyName = PanelBuilder(config: config, chinese: InterfaceLanguage.isChinese(language)).name(config.actionKey)
        composer.messages = messages
        // Chinese only with librime; Korean and Hindi need their packs, which Windows doesn't download yet; Latin
        // languages always.
        let usable = config.inputLanguages.filter { language in
            switch language {
            case .chinese: return composer.primaryEngine is LockedRimeEngine
            case .korean, .hindi: return false
            default: return true
            }
        }
        let languages = usable.isEmpty ? [.english] : usable
        composer.inputLanguages = languages
        let defaultInput = config.startingInput(in: app, among: languages)
        if state.appliedDefaultInput != defaultInput || languages.count == 1, composer.engine != nil, !composer.isComposing {
            composer.setInputMode(defaultInput)
            state.appliedDefaultInput = defaultInput
        }
    }

    public func sessionClosed(_ session: ComposerSession) {
        provider?.cancel(in: session)
        lock.lock()
        let state = states.removeValue(forKey: ObjectIdentifier(session))
        lock.unlock()
        state?.task?.cancel()
        if let state {
            panelPresenter.hide(owner: state.owner)
            panelPresenter.forget(owner: state.owner)
        }
    }

    // MARK: - The panel

    public func panel(shown: Bool, in session: ComposerSession) {
        let state = state(session)
        guard shown else {
            panelPresenter.hide(owner: state.owner)
            return
        }
        guard session.composer.wantsPanel else {
            panelPresenter.hide(owner: state.owner)
            return
        }
        panelPresenter.show(model(for: session), owner: state.owner, caret: session.caret.flatMap { CaretRect($0.rect, exact: $0.exact) })
    }

    /// What the panel shows for `session` now.
    public func model(for session: ComposerSession) -> PanelModel {
        let state = state(session)
        let config = testMode ? Config.default : settings.current
        let language = settings.interfaceLanguage(config)
        return PanelBuilder(config: config, chinese: InterfaceLanguage.isChinese(language), elapsed: state.elapsed,
                            fromCache: state.fromCache).build(session.composer)
    }

    public func caretMoved(in session: ComposerSession) {
        guard let reported = session.caret, let caret = CaretRect(reported.rect, exact: reported.exact) else { return }
        let state = state(session)
        state.caret = caret
        panelPresenter.move(owner: state.owner, caret: caret)
    }

    public func ownsForeground(_ peer: WirePeer) -> Bool { testMode || foreground(peer) }

    // MARK: - Effects

    /// A notice, in the interface language.
    func notice(_ text: String, in session: ComposerSession) {
        let state = state(session)
        panelPresenter.notice(text, owner: state.owner, caret: state.caret)
    }

    func tr(_ zh: String, _ en: String) -> String {
        InterfaceLanguage.isChinese(settings.interfaceLanguage(testMode ? .default : settings.current)) ? zh : en
    }

    static let unscripted = "Not in the test provider's script"

    /// What isn't on Windows yet.
    var notOnWindows: String { tr("Windows 版还不支持", "Not available on Windows yet") }

    public func perform(_ effect: Composer.Effect, in session: ComposerSession) {
        let kind = ComposerSession.kind(of: effect)
        if effect == .cancelConversion {
            provider?.cancel(in: session)
            cancelRequest(in: session)
            return
        }
        if let provider, provider.start(effect, in: session) {
            log("session \(session.sid): \(kind): scripted")
            return
        }
        let composer = session.composer
        if testMode {
            // Test mode asks no model and runs nothing: what the script doesn't answer fails at once, as before M7.
            switch effect {
            case let .startConversion(_, id), let .startCommand(_, _, id), let .startRefine(_, id), let .search(_, id),
                 let .listAgents(id), let .previewReminder(_, id), let .startRun(_, _, id), let .startScript(_, _, _, id, _),
                 let .reask(_, _, id), let .startPlan(_, _, id), let .startTranslateMode(_, _, id):
                log("session \(session.sid): \(kind): no scripted provider, failed")
                session.feed { $0.fail(Self.unscripted, id: id) }
                return
            default:
                break
            }
        }
        switch effect {
        case let .notice(text):
            notice(text, in: session)
        case let .startConversion(input, id):
            // @improve / @translate: the mode (and a second one written inside) comes from the command.
            startConversion(input, id: id, command: composer.activeCommand?.kind == .convert ? composer.activeCommand : nil, in: session)
        case let .startCommand(command, input, id):
            startConversion(input, id: id, command: command, in: session)
        case let .startRefine(refinement, id):
            startRefine(refinement, id: id, in: session)
        case let .reask(command, input, id):
            startConversion(input, id: id, command: command, fresh: true, in: session)
        case let .startPlan(outer, plan, id):
            startConversion("", id: id, command: outer, plan: plan, in: session)
        case let .startRun(command, input, id):
            startConversion(input, id: id, command: command, in: session)
        case let .startTranslateMode(input, translateSession, id):
            log("session \(session.sid): request \(id): Translate as You Type (\(input.count) characters)")
            consume(converter.translateMode(input, target: translateSession.target, app: session.field.app), id: id, in: session)
        case let .startScript(command, arguments, query, id, _):
            startScript(command, arguments: arguments, query: query, id: id, in: session)
        case let .startBackgroundScript(command, arguments, query):
            startBackgroundScript(command, arguments: arguments, query: query, in: session)
        case let .search(query, id):
            let system = self.system
            let state = state(session)
            state.task?.cancel()
            state.task = Task { [weak session] in
                let results = system.search(query)
                guard !Task.isCancelled else { return }
                session?.feed { $0.receiveSearch(results, id: id) }
            }
        case let .open(path):
            open(SearchResult(name: "", path: path).webURL?.absoluteString ?? path, in: session)
        case let .openLink(url):
            open(url.isFileURL ? url.path : url.absoluteString, in: session)
        case let .copy(text):
            if !system.copy(text) { notice(tr("没能复制到剪贴板", "Couldn't copy to the clipboard"), in: session) }
        case let .readClipboard(id):
            // After the key has been answered (the feed runs once this key's work is done).
            let text = system.readClipboard()
            log("session \(session.sid): clipboard for a command: \(text.map { "\($0.count) characters" } ?? "nothing")")
            session.feed { $0.pasted(text, id: id) }
        case let .runInTerminal(prompt):
            let config = settings.current
            guard let argv = config.agent.terminalArguments(custom: config.agentCommand) else {
                notice(tr("还没有设置编程助手的命令", "No command set for the coding agent"), in: session)
                break
            }
            launch(argv + [prompt], in: session)
        case let .continueInClaudeCode(prompt):
            launch(["claude", prompt], in: session)
        case let .continueInAgent(agent, prompt):
            let config = settings.current
            guard let argv = agent.terminalArguments(custom: config.agentCommand) else {
                notice(tr("还没有设置编程助手的命令", "No command set for the coding agent"), in: session)
                break
            }
            launch(argv + [prompt], in: session)
        case let .launchInTerminal(argv):
            launch(argv, in: session)
        case let .saveNote(text):
            saveNote(text, in: session)
        case .openSettings:
            // No settings window yet: the folder with config.json, and a notice that says so.
            let folder = settings.url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            open(folder.path, in: session)
            notice(tr("Windows 版还没有设置窗口：设置在 config.json 里", "No settings window on Windows yet: the settings are in config.json"), in: session)
        case let .previewReminder(_, id), let .listAgents(id):
            session.feed { [notOnWindows] in $0.fail(notOnWindows, id: id) }
        case .addReminder, .sendMessage, .startBackgroundAgent:
            notice(notOnWindows, in: session)
        case let .recognizeText(_, id):
            session.feed { [notOnWindows] in $0.recognitionFailed(notOnWindows, id: id) }
        case let .startVoice(id, _):
            session.feed { [notOnWindows] in $0.voiceFailed(notOnWindows, id: id) }
        case .armVoice, .stopVoice, .cancelVoice, .inputLanguageChanged, .commandUsed, .rememberQuestion, .detachScript,
             .refreshList, .moveCaret:
            log("session \(session.sid): \(kind): nothing to do on Windows")
        case .updateMarkedText, .commit, .commitAfterKey, .replaceSelection, .typeOut, .showPanel, .hidePanel, .cancelConversion:
            break  // ComposerSession's own
        }
    }

    func open(_ target: String, in session: ComposerSession) {
        do {
            try system.open(target)
            log("session \(session.sid): opened \(target.hasPrefix("http") ? "an address" : "a file")")
        } catch {
            notice(Self.describe(error), in: session)
        }
    }

    func launch(_ argv: [String], in session: ComposerSession) {
        do {
            try system.launchInTerminal(argv)
            log("session \(session.sid): started a terminal window (\(argv.count) arguments)")
        } catch {
            notice(Self.describe(error), in: session)
        }
    }

    /// `@note`: a folder of Markdown files or Notion, as the settings say (the core's destinations); Apple Notes, the
    /// Mac's default, isn't on Windows: the text goes on the clipboard, so it isn't lost, and a notice says so.
    func saveNote(_ text: String, in session: ComposerSession) {
        let destination = NoteDestinations.make(settings.current.notes, system: UnavailableNotes())
        let system = self.system
        let saved = tr("已保存到 ", "Saved to ")
        let unsaved = tr("Windows 版还不能存到 Apple 备忘录：文字已复制到剪贴板", "Apple Notes isn't on Windows: the note is on the clipboard")
        Task { [weak self, weak session] in
            do {
                _ = try await destination.save(NoteDraft(text: text))
                if let self, let session { self.notice(saved + destination.name, in: session) }
            } catch {
                _ = system.copy(text)
                if let self, let session {
                    self.notice(error is UnavailableNotes.Unavailable ? unsaved : Self.describe(error), in: session)
                }
            }
        }
    }

    // MARK: - Level two

    func cancelRequest(in session: ComposerSession) {
        let state = state(session)
        state.task?.cancel()
        state.task = nil
    }

    /// A request, as the Mac's `startConversion`: `@improve` / `@translate` through the converter (`WritingMode`), a
    /// `.generate` command (`@question`, a prompt command, a plugin's prompt), a program (`run`: a custom command, a
    /// script plugin, `@py`, `@js`), `@read`, `@search`, a link or a message; commands inside the text first (`plan`).
    func startConversion(_ input: String, id: Int, command: Command?, plan: CommandPlan? = nil, fresh: Bool = false,
                         in session: ComposerSession) {
        let config = settings.current
        let app = session.field.app
        let converter = self.converter
        let executable = self.executable
        let language: Language = InterfaceLanguage.isChinese(settings.interfaceLanguage(config)) ? .chinese : .english
        let terminal = ComposerSession.isTerminal(session.field.process)
        let improveTranslates = config.improveTranslates
        func logged(_ command: Command) -> String { command.custom == nil || command.plugin != nil ? command.name : "custom" }
        log("session \(session.sid): request \(id) (\(input.count) characters\(command.map { ", @\(logged($0))" } ?? "")"
            + (plan.map { ", \($0.inner.count) inside" } ?? "") + ")")
        let streamFor: @Sendable (Command?, String) -> AsyncThrowingStream<ConversionUpdate, Error> = { command, input in
            if command == .read { return WebReader.stream(input) }
            if let command, let code = InlineCode.definition(for: command, executable: executable) { return CommandRunner.run(code, input: input) }
            if command == .webSearch { return WebSearch.stream(input, output: terminal ? .line : .list) }
            if let command, command.kind == .link { return LinkTemplate.passThrough(input) }
            if command?.kind == .message { return CommandPipeline.unchanged(input) }
            if let command, command.kind == .run, let plugin = command.plugin {
                return PluginRunner.run(plugin, input: input, language: language, executable: executable)
            }
            if let command, command.kind == .run, let custom = command.custom { return CommandRunner.run(custom, input: input) }
            if command == nil || command?.kind == .convert {
                let (mode, text) = WritingMode.parse(command, input, improveTranslates: improveTranslates)
                return converter.convert(text, mode: mode, app: app)
            }
            return command.map { converter.generate($0, input: input, app: app, fresh: fresh) } ?? converter.convert(input, app: app)
        }
        let stream: AsyncThrowingStream<ConversionUpdate, Error>
        if let plan, !plan.isEmpty {
            let replyContext = command == .reply ? session.composer.replyContext : nil
            let innerSearch = WebSearch.Output.inside(command)
            stream = CommandPipeline.run(plan, inner: { inner, argument in
                inner == .webSearch ? WebSearch.stream(argument, output: innerSearch) : streamFor(inner, argument)
            }, outer: { text in
                guard let context = replyContext else { return streamFor(command, text) }
                return streamFor(command, Prompt.replyMessage(context.withIntent(text)))
            })
        } else {
            stream = streamFor(command, input)
        }
        consume(terminal && command?.kind == .run ? Self.oneLine(stream) : stream, id: id, in: session)
    }

    /// Asks again for the results shown, revised as the refinement's last instruction says.
    func startRefine(_ refinement: Refinement, id: Int, in session: ComposerSession) {
        let config = settings.current
        let app = session.field.app
        log("session \(session.sid): request \(id) (refine, step \(refinement.turns.count))")
        let stream: AsyncThrowingStream<ConversionUpdate, Error>
        switch refinement.request {
        case let .writing(command, input):
            let (mode, text) = WritingMode.parse(command?.kind == .convert ? command : nil, input,
                                                 improveTranslates: config.improveTranslates)
            stream = converter.convert(text, mode: mode, app: app, turns: refinement.turns)
        case let .command(command, input):
            stream = converter.generate(command, input: input, app: app, fresh: refinement.fresh, turns: refinement.turns)
        }
        consume(stream, id: id, in: session)
    }

    /// Hands `stream`'s updates for request `id` to the session's Composer, and its error if it fails.
    func consume(_ stream: AsyncThrowingStream<ConversionUpdate, Error>, id: Int, in session: ComposerSession) {
        let state = state(session)
        state.task?.cancel()
        state.elapsed = nil
        state.fromCache = false
        let log = self.log
        let sid = session.sid
        state.task = Task { [weak session, weak state] in
            do {
                for try await update in stream {
                    guard !Task.isCancelled, let session else { return }
                    if update.isFinal {
                        state?.elapsed = update.elapsed
                        state?.fromCache = update.fromCache
                        log("session \(sid): request \(id) done in \(String(format: "%.2f", update.elapsed)) s\(update.fromCache ? " (cache)" : "")")
                    }
                    session.feed { $0.receive(update.result, isFinal: update.isFinal, id: id) }
                }
            } catch {
                guard !Task.isCancelled, let session else { return }
                log("session \(sid): request \(id) failed: \(Self.errorKind(error))")
                let message = Self.describe(error)
                session.feed { $0.fail(message, id: id) }
            }
        }
    }

    /// A script extension for this field's request: what it prints goes to the Composer as it comes.
    func startScript(_ command: Command, arguments: [String], query: String, id: Int, in session: ComposerSession) {
        guard let script = command.script else { return }
        let environment = scriptEnvironment(script, query: query, session: session)
        let state = state(session)
        state.task?.cancel()
        state.elapsed = nil
        let started = Date()
        log("session \(session.sid): request \(id) (an extension, \(arguments.count) arguments)")
        state.task = Task { [weak session, weak state] in
            do {
                for try await update in CommandRunner.run(script, arguments: arguments, environment: environment) {
                    guard !Task.isCancelled, let session else { return }
                    if update.isFinal { state?.elapsed = Date().timeIntervalSince(started) }
                    session.feed { $0.receiveScript(update.output, isFinal: update.isFinal, id: id) }
                }
            } catch {
                guard !Task.isCancelled, let session else { return }
                let message = Self.describe(error)
                session.feed { $0.fail(message, id: id) }
            }
        }
    }

    /// A `background` script extension: started on its own; a notice says how it went.
    func startBackgroundScript(_ command: Command, arguments: [String], query: String, in session: ComposerSession) {
        guard let script = command.script else { return }
        let environment = scriptEnvironment(script, query: query, session: session)
        let done = tr("已完成：", "Done: ") + script.title
        Task { [weak self, weak session] in
            var failure: String?
            do {
                for try await _ in CommandRunner.run(script, arguments: arguments, environment: environment) {}
            } catch {
                failure = Self.describe(error)
            }
            if let self, let session { self.notice(failure ?? done, in: session) }
        }
    }

    func scriptEnvironment(_ script: ScriptCommand, query: String, session: ComposerSession) -> [String: String] {
        let config = settings.current
        let context = ScriptContext(language: InterfaceLanguage.isChinese(settings.interfaceLanguage(config)) ? "zh" : "en",
                                    inputLanguage: session.composer.inputLanguage.rawValue, app: session.field.app, query: query)
        return context.environment(for: script, base: ProcessInfo.processInfo.environment)
    }

    /// `stream` with each result on one line: what goes into a terminal, which runs every line it is given.
    static func oneLine(_ stream: AsyncThrowingStream<ConversionUpdate, Error>) -> AsyncThrowingStream<ConversionUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await update in stream {
                        var update = update
                        update.result = CommandRunner.oneLine(update.result)
                        continuation.yield(update)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// An error as the panel says it.
    static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "The request timed out"
            case .notConnectedToInternet, .networkConnectionLost: return "No network connection"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "Couldn't reach the AI service"
            default: break
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    /// An error's kind, without any text of the user's or a server's: for the log.
    static func errorKind(_ error: Error) -> String {
        switch error {
        case let ProviderError.http(provider, status, type, _): return "\(provider.rawValue) http \(status) \(type ?? "-")"
        case let ProviderError.stream(provider, type, _): return "\(provider.rawValue) stream \(type)"
        case let ProviderError.missingKey(provider): return "\(provider.rawValue) no key"
        case let ProviderError.refused(provider): return "\(provider.rawValue) refused"
        case ProviderError.signedOut: return "hosted signed out"
        case ProviderError.quotaExhausted: return "hosted quota exhausted"
        case let urlError as URLError: return "url \(urlError.code.rawValue)"
        default: return String(describing: type(of: error))
        }
    }

    // MARK: - Test mode

    /// Test mode's directives the server leaves to the engine: `provider <file>` (the fixture comes in the frame) and
    /// `inputLanguage <name>`.
    public func testDirective(_ directive: String, _ frame: TestFrame) -> Bool {
        let words = directive.split(separator: " ").map(String.init)
        switch (words.first, words.count) {
        case ("provider", 2):
            guard let fixture = frame.fixture else { return false }
            provider = ScriptedProvider(fixture: fixture, clock: clock)
            return true
        case ("inputLanguage", 2):
            guard let named = Self.language(words[1]) else { return false }
            inputLanguage = named
            return true
        default:
            return false
        }
    }

    public static func language(_ name: String) -> Language? {
        switch name {
        case "english": return .english
        case "chinese": return .chinese
        case "french": return .french
        case "korean": return .korean
        case "hindi": return .hindi
        default: return nil
        }
    }
}

/// Apple Notes, where the Mac's `@note` saves by default: not on Windows.
struct UnavailableNotes: NoteDestination {
    struct Unavailable: Error {}
    var name: String { "Apple Notes" }
    var leavesDevice: Bool { false }
    func save(_ draft: NoteDraft) async throws -> SavedNoteRef { throw Unavailable() }
    func check() async throws -> String { throw Unavailable() }
}
