import Foundation

/// One text field's input session, the same on every platform: the `Composer`, and what goes on around it. Before a key:
/// secure input (nothing composed, keys go straight in), the app taking the marked text on its own, the settings and the
/// commands read again, dead keys, a selection moved under a command. Then what the composer asks for (`Composer.Effect`)
/// becomes what the shell does (`SessionOutput`) or work the session starts (`SessionTasks`): level two's requests,
/// refused during secure input; script extensions and lists; `@open`'s searches; notes, reminders, messages, agents, the
/// web page; the notices and the candidate panel (`PanelPresenter`).
///
/// The shell adapts its events (`SessionEvent`: keys with what the field says around them, the focus, a click in the
/// panel) and applies the outputs. What the session's work answers comes back through `deliver`, on any thread: the shell
/// hands it back on the session's own (the Mac: the main queue; the Windows engine: the session's queue), as timers.
///
/// Used from one thread only; not an actor.
public final class InputSession {
    /// The input state machine.
    public let composer: Composer
    /// What the session asks of the system, or has it do.
    public var services: SessionServices
    /// The work it started that answers later.
    public let tasks: SessionTasks

    /// The field that has the focus (`SessionEvent.focus`).
    public private(set) var field = FieldInfo()
    /// The notice up now ("已复制" …), on the panel's footer or on its own; it expires (`SessionOutput.startTimer`).
    public var notice: String?
    /// How long the last result took, whether it came from the cache, how many values its request hid from the AI
    /// (`Redaction`), whether an `@question` conversation was shortened to fit the model: the panel says so.
    public private(set) var lastElapsed: TimeInterval?
    public private(set) var lastFromCache = false
    public private(set) var lastHidden = 0
    public private(set) var lastShortened = false
    /// The coding agent `@agent` hands the text to, and a custom one's command (`Config.agent`).
    public private(set) var agent = AgentKind.claude
    public private(set) var agentCommand: [String] = []
    /// `@agent` in a web browser takes the page along (`Config.agentPageContext`).
    public private(set) var agentPageContext = true
    /// How a result is typed out (`Config.typeOutRate`, `typeOutVaries`, `typeOutMistakes`): the shell types.
    public private(set) var typeOutRate = TypeOut.defaultRate
    public private(set) var typeOutVaries = false
    public private(set) var typeOutMistakes = false
    /// Waiting for the web page a request takes along (`withPage`): a shell keeps the session until it's in, so the request
    /// starts even if the field is gone meanwhile.
    public var waitsForPage: Bool { !pageWaiters.isEmpty }

    /// The longest 「正在存到…」 / 「正在加到提醒事项…」 stays up: the outcome replaces it, but that can take a while (an
    /// app launching, a permission prompt). A test shortens it.
    public static var progressNoticeLimit: TimeInterval {
        get { progressLimit.withLock { $0 } }
        set { progressLimit.withLock { $0 = newValue } }
    }
    private static let progressLimit = Locked<TimeInterval>(initialState: 20)

    static let log = CoreLog(subsystem: "com.aipinyin.inputmethod.AIPinyin", category: "ime")
    private var log: CoreLog { Self.log }

    /// Level one's engine as `services.levelOne` gave it.
    private var engine: PinyinEngine?
    /// The default input mode last applied (applied again when the setting changes).
    private var appliedDefaultInput: Language?
    /// A dead key typed before the next key.
    private var deadKeys = DeadKeyComposer()
    /// The last character the user typed straight into the field (`characterBeforeCaret`).
    private var lastTyped = LastTyped()
    /// Shown once each time composing is paused for secure input.
    private var secureNoticeShown = false
    /// The key being handled, and what the field said with it; the field's text as last read (`@reply` after dictation).
    private var keyContext: FieldContext?
    private var fieldText: FieldText?
    /// What the field reported selected when a command started on its selection: a key finding it moved (a click, the
    /// app's own keys) gives the command up (`Composer.selectionMoved`).
    private var selectionReported: Range<Int>??
    /// Counts the focus coming and going: a save that comes back to another count is no longer in the field it came from.
    private var fieldSession = 0
    /// The latest notice's timer, and the voice key's (older ones do nothing).
    private var noticeToken = 0
    private var voiceArmToken = 0
    /// The text the last result put in: a snippet's caret goes back into it (`Composer.Effect.moveCaret`).
    private var lastInserted: String?
    /// The command list as last built from the settings and the extensions.
    private var catalog = CatalogCache()
    /// The commands whose programs were last checked (`setCommands`), and those whose program is missing; a check that
    /// ended while a command was being written applies once it's done; the latest check.
    private var checkedCommands: [Command] = []
    private var checkedAgent: [String] = []
    private var missingCommands: Set<String> = []
    private var missingCheckWaiting = false
    private var programCheck = 0
    /// The script extension run of the request in level two: its request and run, when it started; the script and its
    /// arguments of a request while its environment is made.
    private var scriptRun: (request: Int, run: Int)?
    private var scriptStarted = Date()
    private var preparingScripts: [Int: (script: ScriptCommand, arguments: [String])] = [:]
    /// The page asked for while `@agent …` is written (`wakePageIfAgent`), and the focus it was asked for in; what waits
    /// for a page being read.
    private var wokenPage: PageSource?
    private var pageLookedFor = -1
    private var pageWaiters: [TaskID: (PageContext?) -> Void] = [:]
    /// `@reply`'s message as the composer sent it and with the web page added, for its refines.
    private var replyWithPage: (input: String, full: String)?
    /// What the shell is to do, gathered while an event is handled.
    private var outputs: [SessionOutput] = []
    private var depth = 0

    public init(composer: Composer = Composer(), services: SessionServices, deliver: @escaping @Sendable (SessionEvent) -> Void) {
        self.composer = composer
        self.services = services
        tasks = SessionTasks(deliver: deliver)
        composer.secureInputActive = { [weak self] in self?.secureInputActive() ?? false }
        composer.readSelection = { [weak self] in self?.readSelection() }
        composer.characterBeforeCaret = { [weak self] in self?.characterBeforeCaret() }
        composer.aiRefusal = { [weak self] in self?.aiRefusal() }
        composer.readFieldText = { [weak self] in self?.readFieldText() }
        composer.pageContextApplies = { [weak self] in self.map { $0.agentPageContext && $0.services.page($0.app) != nil } ?? false }
    }

    // MARK: - Events

    public func handle(_ event: SessionEvent) -> SessionResponse {
        var handled = true
        let outputs = collect {
            switch event {
            case let .key(key, context):
                handled = self.key(key, context)
            case let .modifiers(change, context):
                handled = false  // the application sees modifier changes too
                modifiers(change, context)
            case let .focus(info):
                focus(info)
            case .blur:
                perform(composer.commitAll())
                releasePage()  // `@agent` asked for a page it didn't send
                fieldSession += 1
                fieldText = nil
            case .commit:
                perform(composer.commitAll())
            case let .pick(index):
                // A conversation's rows are its questions and answers: a click picks an answer (`SessionText.chatChoice`).
                if composer.isQuestionChat, !composer.refineIsComposing {
                    guard let answer = SessionText.chatChoice(row: index) else { return }
                    perform(composer.choose(index: answer))
                } else {
                    perform(composer.choose(index: index))
                }
            case let .scroll(steps):
                perform(composer.scrollPalette(by: steps))
            case let .clipboard(content, id):
                // Nothing is read during secure input (the shell doesn't read it then either).
                perform(composer.pasted(secureInputActive() ? .none : content, id: id))
            case let .task(id, update):
                guard tasks.isCurrent(id) else { return }
                received(update, from: id)
            case let .timer(id):
                timer(id)
            case let .voice(update):
                switch update {
                case let .text(text, id): perform(composer.voiceText(text, id: id))
                case let .finished(text, id): perform(composer.voiceFinished(text, id: id))
                case let .failed(message, id): perform(composer.voiceFailed(message, id: id))
                }
            case .configChanged:
                settings(app: nil)
            case .close:
                tasks.close()  // what runs for the field stops (a save, a message, an agent goes on)
                noticeToken += 1  // its timer does nothing now
                composer.engine = nil
                engine = nil
                fieldSession += 1  // a save still on its way tells its outcome elsewhere
            }
        }
        return SessionResponse(handled: handled, outputs: outputs)
    }

    /// The composer's answer to something the shell did to it (Translate as You Type turned on, the menu's commit): what
    /// the shell is to do.
    public func apply(_ effects: [Composer.Effect]) -> [SessionOutput] { collect { perform(effects) } }

    /// Runs `body`, gathering what it has the shell do: returned by the outermost call.
    private func collect(_ body: () -> Void) -> [SessionOutput] {
        depth += 1
        body()
        depth -= 1
        guard depth == 0 else { return [] }
        defer { outputs = [] }
        return outputs
    }

    private func emit(_ output: SessionOutput) { outputs.append(output) }

    /// The app of the key being handled, else the field's.
    private var app: String? { keyContext?.field?.app ?? field.app }
    private var terminal: Bool { keyContext?.field?.terminal ?? field.terminal }

    /// Whether secure input is on (nothing is sent to a model or run then): anywhere (`SessionServices`), or a password
    /// field here.
    public func secureInputActive() -> Bool { field.secure || services.secureInputActive() }

    // MARK: - Focus

    private func focus(_ info: FieldInfo) {
        lastTyped.forget()
        fieldText = nil
        fieldSession += 1
        field = info
        ensureLevelOne()
        settings(app: info.app)  // the app's own starting language, rewrite styles, typing out (`AppProfile`)
        // Terminals paste on ⌘V whatever the input method does: there ⌘V stays theirs…
        composer.pastesIntoDraft = !info.terminal
        // …and don't act on a key after text inserted during it (`Composer.appTakesKeysAfterInsert`).
        composer.appTakesKeysAfterInsert = composer.pastesIntoDraft
    }

    /// A custom command renamed because a built-in has its name now (`Config.freeBuiltinNames`): said once, in the
    /// field that takes the focus next. The shell tells it last, after its own notices of the focus (the Mac's
    /// Translate as You Type, on in an app that translates always): one said after it would take its place for good.
    public func tellBuiltinRenames() -> [SessionOutput] {
        collect {
            if let notice = services.takeRenameNotice(composer.messages.reply) { say(notice, long: true) }
        }
    }

    // MARK: - Level one

    /// Level one's engine, once librime has finished deploying (and again after a re-deploy). Without the Chinese pack it
    /// never starts: Latin letters (`LatinEngine`), so typing and commands work; while it deploys, keys go through.
    public func ensureEngine() -> [SessionOutput] { collect { ensureLevelOne() } }

    /// The engine let go (librime about to deploy again): none until it's back.
    public func dropEngine() {
        composer.engine = nil
        engine = nil
    }

    private func ensureLevelOne() {
        if let engine, services.engineIsValid(engine) { return }
        switch services.levelOne() {
        case let .engine(fresh):
            engine = fresh
            composer.engine = fresh
            appliedDefaultInput = nil  // a new session starts in the default input mode
            settings(app: nil)
        case .starting:
            engine = nil
            composer.engine = nil
        case .none:
            engine = nil
            if !(composer.primaryEngine is LatinEngine) {  // `engine` is Hindi's while Hindi is typed
                composer.engine = LatinEngine()
                appliedDefaultInput = nil
                settings(app: nil)
            }
        }
    }

    // MARK: - Settings

    /// Takes over the settings: the action key, voice, the commands, the languages, and the default input mode (applied
    /// to new fields, and again when the setting changes; a Shift toggle otherwise sticks). `app`: the field's app (else
    /// the one of the key, or of the field), whose profile may start it in another language and type results out or not.
    public func applySettings(app: String? = nil) -> [SessionOutput] { collect { settings(app: app) } }

    private func settings(app: String?) {
        let config = services.loadSettings()
        let app = app ?? self.app
        composer.voiceEnabled = config.voiceInput && services.voiceSupported()
        composer.actionKey = config.actionKey
        composer.typesResults = config.applying(app: app).typeOut
        composer.horizontalCandidates = config.candidateLayout == .horizontal
        composer.outputLanguages = config.outputLanguages
        composer.provider = config.provider  // the on-device model gets less of a screenshot (`ReplyContext.Limits`)
        // `@reportissue`: the versions and settings it shows, read when it runs (the extensions as this field has them).
        let fallback = services
        composer.issueDiagnostics = { [weak self] in
            let services = self?.services ?? fallback
            let config = services.loadSettings()
            return services.issueDiagnostics(config, services.plugins(false).count, services.loadExtensions(config, false).commands.count)
        }
        (typeOutRate, typeOutVaries, typeOutMistakes) = (config.typeOutRate, config.typeOutVaries, config.typeOutMistakes)
        applyAgent(config)  // before the program check: it's the agent's program `@agent` needs
        setCommandList(catalog.catalog(config.customCommands, plugins: services.plugins(true), index: services.loadExtensions(config, true),
                                       disabled: config.disabledExtensions).commands, recheck: true)
        // The interface language (config `uiLanguage`, else the system's) for the panel, notices and menu.
        UIText.choice = config.uiLanguage
        composer.messages = .make(language: UIText.language)
        composer.messages.actionKeyName = UIText.name(config.actionKey)
        // Where @note saves (named in the interface language): its name in the command list, and whether the note leaves
        // the device (then it isn't saved during secure input). A folder's name is what is remembered of it (never a walk
        // up its tree here: on a network volume that went away, that can hang); it is looked up in the background.
        let notes = services.noteDestination(config.notes)
        UIText.noteDestinationName = notes.name
        composer.noteLeavesDevice = notes.leavesDevice
        if let folder = notes as? MarkdownFolderDestination { tasks.nameFolder(folder, settings: config.notes) }
        composer.translateModeMessages = .make(language: UIText.language)
        nameAgent()  // the messages were just reset
        applyChatSettings(config)
        // Only the languages whose pack is installed: Chinese is no input mode while its pack downloads.
        // The Korean and Hindi packs' data, for their input (nil without the pack).
        composer.hangulTables = services.hangulTables()
        composer.hindiTables = services.hindiTables()
        let languages = services.usableLanguages(config.inputLanguages)
        let defaultInput = config.startingInput(in: app, among: languages)
        composer.inputLanguages = languages
        // With one input language, a field is always in it (it may have been switched before it was the only one).
        let onlyOne = languages.count == 1
        if appliedDefaultInput != defaultInput || onlyOne, composer.engine != nil, !composer.isComposing {
            composer.setInputMode(defaultInput)
            appliedDefaultInput = defaultInput
        }
        emit(.keyboardLayout)
    }

    /// The agent picked for `@agent`: only Claude Code runs in the background; the command list's summary names it.
    private func applyAgent(_ config: Config) {
        agent = config.agent
        agentCommand = config.agentCommand
        agentPageContext = config.agentPageContext
        composer.claudeInBackground = config.claudeInBackground && config.agent.supportsBackground
        UIText.agentName = config.agent.displayName(custom: config.agentCommand)
        nameAgent()
    }

    /// "已在终端打开 Claude Code": the agent picked, by name, in the messages; a custom agent by its program's name in a
    /// hand-off's.
    private func nameAgent() {
        let base = Composer.Messages.make(language: UIText.language)
        composer.messages.openedTerminal = base.openedTerminal.replacingOccurrences(of: "Claude Code", with: UIText.agentName)
        composer.messages.secureInputTerminal = base.secureInputTerminal.replacingOccurrences(of: "Claude Code", with: UIText.agentName)
        // Only once it has a command: otherwise the messages stay the language's own.
        composer.messages.agentNames = AgentKind.custom.program(custom: agentCommand) == nil
            ? [:] : [.custom: AgentKind.custom.displayName(custom: agentCommand)]
    }

    /// An `@question` conversation's settings: the rounds, and where it can go on (`ChatHandoff`): the agents installed,
    /// the one `@agent` hands to first; what the hand-off says in the interface language.
    private func applyChatSettings(_ config: Config) {
        composer.questionRounds = config.questionRounds
        let installed = services.agentInstalled
        composer.handoffChoices = ChatHandoff.choices(config.questionContinueIn, picked: config.agent,
                                                      installed: { installed($0, config.agentCommand) })
        composer.pickedAgent = installed(config.agent, config.agentCommand) ? config.agent : nil
        composer.chatMessages = .make(language: UIText.language)
    }

    /// Whether the agent changed since its program was last checked (`setCommands`).
    private var agentChanged: Bool { [agent.rawValue] + agentCommand != checkedAgent }

    /// Takes over the commands "@" offers, without those whose program isn't installed (`@agent` without its agent, a
    /// custom command's missing `argv[0]`): "@agent …" is then just text, like "@name". Which are missing is checked in
    /// the background when the commands changed, or with `recheck` (a field took the focus: something may have been
    /// installed meanwhile).
    public func setCommands(_ commands: [Command], recheck: Bool = false) -> [SessionOutput] {
        collect { setCommandList(commands, recheck: recheck) }
    }

    private func setCommandList(_ commands: [Command], recheck: Bool) {
        composer.commands = commands.filter { !missingCommands.contains($0.name) }
        // Another agent picked is checked again too (its program may be missing).
        let checkedFor = [agent.rawValue] + agentCommand
        guard recheck || commands != checkedCommands || checkedFor != checkedAgent else { return }
        checkedCommands = commands
        checkedAgent = checkedFor
        programCheck += 1
        // A custom agent without a command needs a program that can't be found: `@agent` isn't offered.
        let needed = commands.compactMap { command -> (name: String, program: String)? in
            command == .agent ? (command.name, command.program(agent: agent, custom: agentCommand) ?? "")
                : command.program.map { (command.name, $0) }
        }
        tasks.checkPrograms(needed, check: programCheck, installed: services.programInstalled)
    }

    /// The programs' check came back: the commands without theirs aren't offered. Not while a command is being written:
    /// the draft keeps the commands it started with, and they're filtered once it's done (`missingCheckWaiting`).
    private func programsChecked(missing: Set<String>, check: Int) {
        guard programCheck == check else { return }
        if !missing.isEmpty { log.notice("commands hidden, their program isn't installed: \(missing.count)") }
        missingCommands = missing
        if composer.isComposing {
            missingCheckWaiting = true
        } else {
            composer.commands = checkedCommands.filter { !missing.contains($0.name) }
        }
    }

    // MARK: - Keys

    /// What of the field `key` may need, given what was read of it so far (`context`): what the shell reads before it hands
    /// the key on, asking again until there is nothing more (twice at most). A shell where reading is cheap reads it all.
    public func fieldWants(for key: KeyEvent, given context: FieldContext) -> FieldContext.Parts {
        // First whether anything is composed at all: nothing else is read in a password field.
        var wants: FieldContext.Parts = [.secure]
        guard context.read.contains(.secure), !context.secure, !field.secure else { return wants }
        if composer.isComposing, !composer.draftInPanel { wants.insert(.markedText) }
        if composer.draftInPanel, selectionReported != nil { wants.insert(.selectedRange) }
        // "@" may start a command: on the selection, unless it comes right after a word ("bob@example.com").
        if key.printableText == "@", !composer.isLevelTwo, composer.draft.isEmpty || composer.draftInPanel {
            let terminal = (context.field ?? field).terminal
            if lastTyped.character != nil, !terminal { wants.insert(.beforeCaret) }
            let afterWord = context.read.contains(.beforeCaret)
                && characterBeforeCaret(in: context).map(Composer.continuesWord) == true
            if !wants.contains(.beforeCaret) || context.read.contains(.beforeCaret), !afterWord, !terminal,
               services.loadSettings().useSelection, !secureInputActive() {
                wants.formUnion([.selection, .selectedRange])  // where it is, as the field reports it: a click moves it
            }
        }
        // `@reply` sends the text around the caret: read with the key that may run it.
        if composer.draftCommand == .reply,
           key.key == .enter || key.key == .keypadEnter || key.key == .space || composer.isActionKey(key) {
            wants.insert(.text)
        }
        return wants
    }

    /// What of the field a modifier change may need, given what was read of it so far: `@reply`'s text, where a tap of
    /// Option runs it.
    public func fieldWants(forModifiers change: ModifierChange, given context: FieldContext) -> FieldContext.Parts {
        guard context.read.contains(.secure), !context.secure, !field.secure else { return [.secure] }
        return composer.draftCommand == .reply && composer.actionKey == .optionTap ? [.secure, .text] : [.secure]
    }

    private func key(_ event: KeyEvent, _ context: FieldContext) -> Bool {
        if context.read.contains(.text) { fieldText = context.text }
        // Password fields and prompts turn on secure event input. Never compose (so nothing can be sent to the model) in
        // the app that turned it on; anything already typed goes in as typed.
        if context.secure || field.secure {
            if composer.isComposing {
                let ended = composer.commitAsTyped()
                perform(ended)
                // A note that couldn't go in as typed says its text is on the clipboard: that notice stays up.
                if ended.contains(where: { if case .notice = $0 { return true } else { return false } }) { secureNoticeShown = true }
            }
            if !secureNoticeShown, !event.characters.isEmpty, event.modifiers.isDisjoint(with: [.command, .control]) {
                secureNoticeShown = true
                perform([.notice(tr("安全输入中：输入法暂停，按键直接输入", "Secure input: the input method is paused, keys go straight in"))])
            }
            lastTyped.forget()
            return false
        }
        secureNoticeShown = false
        // The app took the text being typed without saying so (Slack, on an "@…"): start over rather than show the draft
        // again, doubled. This key is dropped, so ⏎ doesn't send half a sentence. (A command on the selection marks
        // nothing in the field: there's nothing for the app to take.)
        if composer.isComposing, !composer.draftInPanel, context.markedTextTaken {
            log.notice("the app took the marked text: starting over")
            perform(composer.appTookMarkedText())
            lastTyped.forget()
            return true
        }
        ensureLevelOne()
        // Commands added to the config apply from the next sentence on (the file is re-read only when it changed).
        if !composer.isComposing {
            // Built again only when what it's made of changed (`CatalogCache`): not for each key.
            let config = services.loadSettings()
            let (commands, changed) = catalog.catalog(config.customCommands, plugins: services.plugins(false),
                                                      index: services.loadExtensions(config, false), disabled: config.disabledExtensions)
            applyAgent(config)
            // Another agent picked in the settings: its program is checked (`setCommands` sees it changed).
            if changed || agentChanged && !checkedCommands.isEmpty {
                setCommandList(changed ? commands : checkedCommands, recheck: false)
            } else if missingCheckWaiting {
                // A check of the programs that ended while a command was being written.
                composer.commands = checkedCommands.filter { !missingCommands.contains($0.name) }
            }
            missingCheckWaiting = false
            composer.commandUsage = services.loadCommandUsage()  // another field may have run commands
            composer.remembersQuestions = services.loadSettings().rememberQuestions
            applyChatSettings(services.loadSettings())
            composer.questionHistory = services.loadQuestionHistory()  // asked in another field, or cleared
        }
        // Dead keys aren't composed for an input method (macOS): done here, from the layout the keys come from.
        if composer.pendingAccent == nil { deadKeys.reset() }
        let key = deadKeys.compose(event, in: services.keyTranslator())
        // The selection a command is written on changed (a click, the app's own keys): the command is given up, and the
        // key acts as it would.
        if composer.draftInPanel, let reported = selectionReported, context.read.contains(.selectedRange),
           context.selectedRange != reported {
            log.notice("the selection changed while a command was written on it: given up")
            perform(composer.selectionMoved())
        }
        keyContext = context
        let response = composer.handleKeyDown(key)
        keyContext = nil
        if composer.pendingAccent == nil { deadKeys.reset() }
        perform(response.effects)
        let inserted = response.effects.compactMap { if case let .commit(text) = $0 { text } else { nil } }.last
        lastTyped.answered(key, passedOn: !response.handled, inserted: inserted, at: ProcessInfo.processInfo.systemUptime)
        return response.handled
    }

    private func modifiers(_ change: ModifierChange, _ context: FieldContext) {
        if context.read.contains(.text) { fieldText = context.text }
        guard !(context.secure || field.secure) else {
            // A password field took over: stop any recording (its release may never arrive here).
            if composer.voice != .off { perform(composer.commitAsTyped()) }
            return
        }
        ensureLevelOne()
        // The key was held up to the event; the pointer is asked later, so look back that much further.
        let (late, pointerUsedWithin) = (change.late, services.pointerUsedWithin)
        composer.pointerUsedWithin = { pointerUsedWithin($0 + late) }
        keyContext = context
        perform(composer.handleFlagsChanged(key: change.key, modifiers: change.modifiers, timestamp: change.timestamp))
        keyContext = nil
    }

    // MARK: - What the composer asks of the field

    /// The selection a draft starts on (`Composer.readSelection`), as the field said it with the key: with the setting on
    /// (`useSelection`), never during secure input, nor in a terminal (its selection is no text being edited: what goes
    /// back would be typed at the prompt).
    private func readSelection() -> Composer.Selection? {
        guard let context = keyContext, context.read.contains(.selection), services.loadSettings().useSelection,
              !secureInputActive(), !terminal, let selection = context.selection else { return nil }
        selectionReported = .some(context.read.contains(.selectedRange) ? context.selectedRange : selection.range)
        return selection
    }

    /// The character right before the caret where "@" is typed (`Composer.characterBeforeCaret`): the last one the user
    /// typed into the field (`lastTyped`), unless the pointer was used since (a click may have moved the caret). A field
    /// that tells its text (not a terminal) must have that character there, with nothing selected: what the app did with
    /// its text meanwhile (cleared it, moved the caret) the input method doesn't see.
    private func characterBeforeCaret() -> Character? {
        keyContext.flatMap { characterBeforeCaret(in: $0) }
    }

    private func characterBeforeCaret(in context: FieldContext) -> Character? {
        guard let typed = lastTyped.character,
              !services.pointerUsedWithin(ProcessInfo.processInfo.systemUptime - lastTyped.time) else { return nil }
        guard !(context.field ?? field).terminal, context.read.contains(.beforeCaret) else { return typed }
        switch context.beforeCaret {
        case .unknown: return typed  // a field that tells no caret, or reads nothing back
        case .nothing: return nil  // a selection (a command may work on it), the start
        case let .text(before): return before == String(typed) ? typed : nil
        }
    }

    /// The text around the caret, for `@reply` (`Composer.readFieldText`): as the field told it with the key that runs it
    /// (or last: after dictation). None during secure input, nor in a terminal.
    private func readFieldText() -> FieldText? {
        guard !secureInputActive(), !terminal else { return nil }
        if let context = keyContext, context.read.contains(.text) { return context.text }
        return fieldText
    }

    /// The notice of an AI command in an app with no AI (`AppProfile.noAI`), read when the command starts; nil: AI may run.
    private func aiRefusal() -> String? {
        guard !services.loadSettings().allowsAI(in: app) else { return nil }
        log.notice("AI command refused: no AI in this app")
        return Self.aiRefusal
    }

    /// The notice of an AI command refused in an app with no AI.
    public static var aiRefusal: String {
        tr("这个 App 里关了 AI，没有发给 AI（设置 → 按 App 设置）", "AI is off in this app: nothing was sent (Settings → Apps)")
    }

    // MARK: - Effects

    private func perform(_ effects: [Composer.Effect]) {
        defer {
            wakePageIfAgent()
            if !composer.isComposing { replyWithPage = nil }  // the draft is done: the page's text goes with it
        }
        for effect in effects {
            switch effect {
            case .updateMarkedText:
                // A command on the selection is written in the panel: the field keeps its selection, nothing marked over it.
                guard !composer.draftInPanel else { break }
                let text = composer.markedText
                emit(.marked(text, cursor: String(text.prefix(composer.markedCursor)).utf16.count, converted: composer.isLevelTwo))
            case .inputLanguageChanged:
                emit(.keyboardLayout)
            case let .commit(text):
                emit(.commit(text))
                lastInserted = text
                lastTyped.forget()  // a key that typed it says so (`key`)
            case let .commitAfterKey(text):
                // Once this key is done: a terminal would send what is inserted during it in the key's place.
                emit(.commitAfterKey(text))
                lastTyped.forget()
            case let .replaceSelection(text, selection):
                if let (rest, end) = SessionText.afterSelection(text, selection).map({ ($0.text, $0.at) }) {
                    emit(.replace(rest, range: end..<end))
                    log.notice("inserted after the selection (\(rest.count) characters)")
                } else {
                    emit(.replace(text, range: selection.range))
                    log.notice("selection replaced (\(selection.range == nil ? "what is selected" : "its range"), \(text.count) characters)")
                }
                lastInserted = text
                lastTyped.forget()
            case let .typeOut(text):
                emit(.typeOut(text))
                lastInserted = nil
                lastTyped.forget()
            case let .moveCaret(back):
                emit(.moveCaret(back: back, after: lastInserted))
            case let .startConversion(input, id):
                if refusedForSecureInput(id: id) { break }
                // @improve / @translate: the mode (and a second one written inside) comes from the command.
                startConversion(input, id: id, command: composer.activeCommand?.kind == .convert ? composer.activeCommand : nil)
            case let .startCommand(command, input, id):
                if refusedForSecureInput(id: id) { break }
                // @reply with nothing selected, copied or pasted: the web page as its context, when that applies.
                if command == .reply, composer.replyTakesPage {
                    withPage(input, render: { Prompt.replyMessage($1, page: $0) }) { [weak self] prompt, _ in
                        guard let self else { return }
                        // ⌘R and refines send the page again (while the draft is up).
                        if self.composer.isComposing { self.replyWithPage = (input, prompt) }
                        self.startConversion(prompt, id: id, command: command)
                    }
                    break
                }
                startConversion(input, id: id, command: command)
            case let .startRefine(refinement, id):
                // Sent to the model like the request it refines: refused during secure input the same way.
                if refusedForSecureInput(id: id) { break }
                startRefine(refinement, id: id)
            case let .reask(command, input, id):
                if refusedForSecureInput(id: id) { break }
                startConversion(input, id: id, command: command, fresh: true)
            case let .startPlan(outer, plan, id):
                // Inner commands run programs or reach the network: refused during secure input like any.
                if refusedForSecureInput(id: id, running: true) { break }
                // @reply with nothing selected, copied or pasted: the web page goes along with the text the commands
                // inside it make, as without them.
                if outer == .reply, composer.replyTakesPage {
                    withPage("", render: { Prompt.replyMessage($1, page: $0) }) { [weak self] page, _ in
                        self?.startConversion("", id: id, command: outer, plan: plan, replyPage: page)
                    }
                    break
                }
                startConversion("", id: id, command: outer, plan: plan)
            case let .startRun(command, input, id):
                if refusedForSecureInput(id: id, running: true) { break }
                startConversion(input, id: id, command: command)
            case let .startScript(command, arguments, query, id, action):
                if refusedForSecureInput(id: id, running: true) { break }
                startScript(command, arguments: arguments, query: query, id: id, action: action)
            case let .startBackgroundScript(command, arguments, query):
                startInBackground(command, arguments: arguments, query: query)
            case let .detachScript(id):
                // The field was left while a `show` runs: it goes on, and says when it's done.
                if let run = scriptRun, run.request == id {
                    services.detachScript(run.run)
                    tasks.cancel(.script)
                }
                scriptRun = nil
            case .refreshList:
                scheduleListRun(now: true)  // now, not after its delay
            case let .search(query, id):
                tasks.search(query, id: id, history: services.loadOpenHistory(), with: services.searchFiles)
            case let .open(path):
                if let agent = SearchResult(name: "", path: path).agentID {
                    emit(.openAgent(agent))  // a background task: in a terminal
                    break
                }
                log.notice("opening an @open result")
                emit(.open(path))
                // Listed first by the next searches (files only: a web address is typed again).
                if SearchResult(name: "", path: path).webURL == nil { services.recordOpen(path) }
            case let .openLink(url):
                // The site is public (a plugin's or the user's own template); the text in it is not.
                log.notice("link command: opening \(url.isFileURL ? "a file" : url.host ?? "-")")
                // A file (a script list's row) by its path, which isn't kept in @open's history.
                emit(.open(url.isFileURL ? url.path : url.absoluteString))
            case let .startBackgroundAgent(prompt):
                // Started even if the field is gone by the time the page is read (`waitsForPage`).
                withPage(prompt) { [weak self] prompt, page in
                    guard let self else { return }
                    self.tasks.startAgent(prompt, page: page, with: self.services.startAgent)
                }
            case .openSettings:
                emit(.openSettings(nil))
            case let .listAgents(id):
                tasks.listAgents(id: id, with: services.listAgents)
            case let .runInTerminal(prompt):
                // A custom agent without a command isn't offered; one emptied meanwhile starts nothing.
                guard let arguments = agent.terminalArguments(custom: agentCommand) else {
                    log.error("@agent: no command for the custom agent")
                    break
                }
                withPage(prompt) { [weak self] prompt, page in  // started even if the field is gone meanwhile (see above)
                    guard let self else { return }
                    do {
                        try self.services.runInTerminal(arguments, prompt)
                        self.log.notice("@agent: \(self.agent.rawValue) started in a terminal (\(prompt.count) chars)")
                        if let page { self.say(self.composer.messages.openedTerminal + UIText.withPage(page)) }
                    } catch {
                        self.log.error("@agent: could not start the terminal: \(String(describing: error))")
                        self.say(UIText.describe(error))
                    }
                }
            case let .continueInClaudeCode(prompt):
                handOff(prompt, to: .claude)
            case let .continueInAgent(kind, prompt):
                handOff(prompt, to: kind)
            case .commandUsed:
                services.saveCommandUsage(composer.commandUsage)
            case let .rememberQuestion(entry):
                // Kept only on this device, never while secure input is on (the composer checks too).
                guard services.loadSettings().rememberQuestions, !secureInputActive() else { break }
                services.recordQuestion(entry)
            case let .launchInTerminal(argv):
                do {
                    try services.launchInTerminal(argv)
                    log.notice("custom command: terminal started (\(argv.count) arguments)")
                } catch {
                    log.error("custom command: could not start the terminal: \(String(describing: error))")
                    say(UIText.describe(error))
                }
            case let .saveNote(text):
                // Nothing goes to a model: kept on this device (Notes, a folder), not refused while secure input is on,
                // unlike the requests above; to Notion it is (the composer refuses it, and so does `saveToNotes`).
                saveToNotes(text)
            case let .previewReminder(input, id):
                // Read here by the clock now (the date detector and the parser's own rules), quick enough for a
                // keystroke. Nothing leaves the device, so secure input doesn't hold it back either.
                perform(composer.receiveReminder(services.parseReminder(input), id: id))
            case let .startTranslateMode(input, session, id):
                if refusedForSecureInput(id: id) { break }
                tasks.cancel(.request)
                (lastElapsed, lastFromCache, lastHidden, lastShortened) = (nil, false, 0, false)
                log.notice("conversion \(id) started (Translate as You Type, \(input.count) chars, into \(session.target.code))")
                tasks.translate(input, session: session, id: id, in: place(generates: false), converter: services.converter)
            case let .addReminder(reminder, input):
                addToReminders(reminder, input: input)
            case let .copy(text):
                emit(.copy(text))
            case let .sendMessage(recipient, text, command):
                sendMessage(text, to: recipient, command: command)
            case let .readClipboard(id):
                // After the key has been answered: if the system asks whether this may read the clipboard, the app isn't
                // left waiting for the key (and doesn't paste on its own meanwhile).
                emit(.readClipboard(id: id))
            case let .recognizeText(image, id):
                // On the device: the image goes nowhere.
                tasks.recognize(image, id: id, languages: ScreenText.languages(services.loadSettings()), with: services.recognizeText)
            case .cancelConversion:
                tasks.cancel(.request)
                if let run = scriptRun { services.cancelScript(run.run) }
                scriptRun = nil
                tasks.cancel(.script)
            case .showPanel:
                showPanel()
            case .hidePanel:
                emit(.panel(nil))
            case let .notice(text):
                // A note left unsaved, its text on the clipboard: up as long as the other "on the clipboard" notices.
                say(text, long: text == composer.messages.noteNotSaved)
            case let .armVoice(delay):
                voiceArmToken += 1
                emit(.startTimer(.voiceHold(voiceArmToken), after: delay))
            case let .startVoice(id, language):
                emit(.platform(.startVoice(id: id, language: language)))
            case let .stopVoice(id):
                emit(.platform(.stopVoice(id: id)))
            case let .cancelVoice(id):
                emit(.platform(.cancelVoice(id: id)))
            }
        }
        scheduleLiveSearch()
        scheduleRecipientSearch()
        scheduleListRun()
        refreshStatuses()
    }

    private func timer(_ id: TimerID) {
        switch id {
        case let .notice(token):
            guard token == noticeToken else { return }
            noticeExpired()
        case let .voiceHold(token):
            guard token == voiceArmToken else { return }
            perform(composer.voiceHoldElapsed(stillHeld: services.isVoiceKeyHeld()))
        }
    }

    /// An `@question` conversation handed to `kind` (`ChatHandoff`): started in a terminal as `@agent` starts it, the
    /// conversation its first message. A custom agent without a command isn't offered; one emptied meanwhile starts nothing.
    private func handOff(_ prompt: String, to kind: AgentKind) {
        guard let arguments = kind.terminalArguments(custom: agentCommand) else {
            log.error("@question: no command for the custom agent")
            return
        }
        do {
            try services.continueInAgent(arguments, prompt)
            log.notice("@question: conversation handed to \(kind.rawValue) (\(prompt.count) chars)")
        } catch {
            log.error("@question: could not start the terminal: \(String(describing: error))")
            say(UIText.describe(error))
        }
    }

    // MARK: - Level two

    /// While secure input is on anywhere (a password field or prompt may be active), nothing is sent off the device: the
    /// request fails at once. True if refused.
    private func refusedForSecureInput(id: Int, running: Bool = false) -> Bool {
        guard secureInputActive() else { return false }
        log.info("conversion \(id) not sent: secure input")
        let message = running
            ? tr("系统安全输入已开启（密码框或锁屏），没有运行命令",
                 "Secure input is on (a password field or the lock screen): the command was not run")
            : tr("系统安全输入已开启（密码框或锁屏），未发送给 AI",
                 "Secure input is on (a password field or the lock screen): nothing was sent to the AI")
        perform(composer.fail(message, id: id))
        return true
    }

    /// Streams level two for `input` (`SessionTasks.convert`): the improve conversion, a `.generate` command's answer, or
    /// what a `.run` command's program printed. `replyPage`: `@reply`'s web page (`Prompt.replyMessage(_:page:)` of
    /// nothing), added after its message once the commands inside it have run (`plan`).
    private func startConversion(_ input: String, id: Int, command: Command? = nil, plan: CommandPlan? = nil, fresh: Bool = false,
                                 replyPage: String = "") {
        tasks.cancel(.request)
        lastElapsed = nil
        lastFromCache = false
        lastHidden = 0
        lastShortened = false
        // Plugin names are public (from the library); custom command names are the user's own.
        func logged(_ command: Command) -> String { command.custom == nil || command.plugin != nil ? command.name : "custom" }
        let inner = plan.map { ", inside: " + $0.inner.map { "@" + logged($0.command) }.joined(separator: " ") } ?? ""
        log.notice("conversion \(id) started (\(input.count) chars\(command.map { ", @\(logged($0))" } ?? "")\(inner))")
        // @translate with no language to translate into but the sentence's own (a new user whose system has no other
        // language): nothing is sent; the settings open where languages are added.
        if command == .translate, !SessionText.hasTranslationTarget(for: input, config: services.loadSettings()) {
            log.notice("conversion \(id): no language to translate into")
            perform(composer.fail(tr("还没有要翻译成的语言：在设置的「翻译与改写」里加一种", "No language to translate into yet: add one under Translate & Rewrite in the settings"),
                                  id: id))
            emit(.openSettings(.outputLanguages))
            return
        }
        let request = SessionTasks.Request(input: input, command: command, plan: plan, fresh: fresh, replyPage: replyPage,
                                           replyContext: command == .reply ? composer.replyContext : nil)
        tasks.convert(request, id: id, in: place(generates: command?.kind == .generate), services: services)
    }

    /// Where a request runs (`SessionTasks.Place`): the app's own rewrite styles, or no AI at all (`AppProfile`); a terminal
    /// runs each line it is given, and an answer (`generates`) keeps its line breaks there only as a paste (asked only
    /// then: the Mac may ask for a permission); script plugins get the language this request's own texts are in.
    private func place(generates: Bool) -> SessionTasks.Place {
        let terminal = self.terminal
        return SessionTasks.Place(app: app, terminal: terminal, pastesInTerminal: terminal && generates && services.pastesInTerminal(),
                                  improveTranslates: services.loadSettings().improveTranslates, pluginLanguage: UIText.pluginLanguage)
    }

    /// Asks again for the results shown, revised as the refinement's last instruction says ("shorter"; `SessionTasks.refine`).
    /// The new results replace the shown ones as they stream in (`Composer.receive`). In the app's settings: its rewrite
    /// styles, and nothing sent where it has no AI.
    private func startRefine(_ refinement: Refinement, id: Int) {
        tasks.cancel(.request)
        lastElapsed = nil
        lastFromCache = false
        lastShortened = false
        let step = composer.isQuestionChat ? "@question round \(refinement.turns.count + 1)" : "refine, step \(refinement.turns.count)"
        log.notice("conversion \(id) started (\(step))")
        var sent: String?
        var generates = false
        if case let .command(command, input) = refinement.request {
            // @reply with the web page: asked again with it (the composer has the message without it).
            sent = command == .reply && replyWithPage?.input == input ? replyWithPage?.full ?? input : input
            generates = true
        }
        tasks.refine(refinement, id: id, sent: sent, in: place(generates: generates), converter: services.converter)
    }

    /// What the session's work answered, while it still counts.
    private func received(_ update: TaskUpdate, from id: TaskID) {
        switch update {
        case let .converted(update, request):
            lastHidden = update.hidden
            lastShortened = update.shortened
            if update.isFinal {
                lastElapsed = update.elapsed
                lastFromCache = update.fromCache
                log.notice("conversion \(request) done in \(String(format: "%.2f", update.elapsed))s cache=\(update.fromCache)")
            }
            perform(composer.receive(update.result, isFinal: update.isFinal, id: request))
        case let .failed(error, request):
            if id.slot == .script, scriptRun?.request == request { scriptRun = nil }
            let message: String
            if let error = error as? DescribedError {
                message = error.message
            } else {
                log.error("conversion \(request) failed: \(errorKind(error))")
                message = UIText.describe(error)
            }
            perform(composer.fail(message, id: request))
        case let .searched(results, request):
            perform(composer.receiveSearch(results, id: request))
        case let .environment(environment, request):
            startScript(request, environment: environment)
        case let .script(update, request):
            if update.isFinal {
                lastElapsed = Date().timeIntervalSince(scriptStarted)
                if scriptRun?.request == request { scriptRun = nil }
            }
            perform(composer.receiveScript(update.output, isFinal: update.isFinal, id: request))
        case let .list(output, query):
            perform(composer.receiveList(output, for: query))
        case let .live(results, query):
            perform(composer.receiveLive(results, for: query))
        case let .recipients(found, note, query):
            perform(composer.receiveRecipients(found, note: note, for: query))
        case let .page(context):
            pageWaiters.removeValue(forKey: id)?(context)
        case let .notice(text):
            say(text)
        case let .agentStarted(page):
            say(composer.messages.startedInBackground + UIText.withPage(page))
        case let .agentFailed(message):
            say(message)
        case let .sent(recipient):
            services.saveRecentHandles(RecipientSearch.remember(recipient.handle, in: services.loadRecentHandles()))
            say(tr("已发送给 ", "Sent to ") + recipient.displayName)
        case let .saved(outcome):
            saved(outcome)
        case let .recognized(text, request):
            perform(composer.recognized(text, id: request))
        case let .recognitionFailed(error, request):
            let message = (error as? ScreenText.Problem).map(composer.messages.reply.describe) ?? UIText.describe(error)
            perform(composer.recognitionFailed(message, id: request))
        case let .programs(missing, check):
            programsChecked(missing: missing, check: check)
        case let .noteFolderNamed(name, settings):
            guard UIText.noteDestinationName != name, services.loadSettings().notes == settings else { return }
            UIText.noteDestinationName = name
        case .statusEnded:
            guard composer.paletteQuery != nil else { return }
            perform([.showPanel])
        }
    }

    /// An error's kind without any server-provided text (safe for the public log).
    public func errorKind(_ error: Error) -> String { services.errorKind(error) ?? Self.errorKind(error) }

    public static func errorKind(_ error: Error) -> String {
        switch error {
        case let BedrockError.http(status, type, _): return "http \(status) \(type ?? "-")"
        case let BedrockError.stream(type, _): return "stream \(type)"
        case BedrockError.invalidResponse: return "invalid response"
        case BedrockError.invalidRegion: return "invalid region"
        case let ProviderError.http(provider, status, type, _): return "\(provider.rawValue) http \(status) \(type ?? "-")"
        case let ProviderError.stream(provider, type, _): return "\(provider.rawValue) stream \(type)"
        case let ProviderError.missingKey(provider): return "\(provider.rawValue) no key"
        case let ProviderError.refused(provider): return "\(provider.rawValue) refused"
        case ProviderError.signedOut: return "hosted signed out"
        case ProviderError.quotaExhausted: return "hosted quota exhausted"
        case let NoteError.notionRefused(code): return "notion refused \(code)"
        case let NoteError.notionTrouble(status): return "notion http \(status)"
        case let error as NoteError: return "note \(String(describing: error).prefix { $0 != "(" })"
        case let urlError as URLError: return "url \(urlError.code.rawValue)"
        default: return String(describing: type(of: error))
        }
    }

    // MARK: - Script extensions

    /// What a script extension is told about where it runs (`ScriptContext`).
    private func scriptContext(query: String) -> ScriptContext {
        ScriptContext(language: UIText.chinese ? "zh" : "en", inputLanguage: composer.inputLanguage.rawValue, app: field.app, query: query)
    }

    /// What builds `command`'s environment (`SessionTasks.environmentMaker`), with what it needs of the field taken now:
    /// it needs nothing of the field afterwards, which may be gone by the time it runs.
    private func environmentMaker(_ command: ScriptCommand, query: String, status: Bool = false,
                                  action: Bool = false) -> @Sendable () async -> Result<[String: String], DescribedError> {
        let config = services.loadSettings()
        return SessionTasks.environmentMaker(command, bundle: services.loadExtensions(config, false).bundle(of: command), config: config,
                                             context: scriptContext(query: query), preferences: services.extensionPreferences,
                                             status: status, action: action)
    }

    /// Runs a script extension for this field's request: what it prints goes to the composer as it comes. It starts once
    /// its environment is ready (the request may be gone by then: Esc, another key).
    private func startScript(_ command: Command, arguments: [String], query: String, id: Int, action: Bool) {
        guard let script = command.script else { return }
        if let run = scriptRun { services.cancelScript(run.run) }
        scriptRun = nil
        tasks.cancel(.script)
        lastElapsed = nil
        lastFromCache = false
        lastHidden = 0
        log.notice("conversion \(id) started (an extension, \(arguments.count) arguments)")
        preparingScripts[id] = (script, arguments)
        tasks.prepareScript(id: id, environment: environmentMaker(script, query: query, action: action))
    }

    /// The environment of request `id`'s script extension is ready: it runs, if the request is still on.
    private func startScript(_ id: Int, environment: [String: String]) {
        guard let (script, arguments) = preparingScripts.removeValue(forKey: id), composer.phase == .translating(id: id) else { return }
        scriptStarted = Date()
        let token = tasks.token(.script)
        let deliver = tasks.deliver
        let run = services.startScript(script, arguments, environment) { event in
            switch event {
            case let .update(update): deliver(.task(token, .script(update, request: id)))
            case let .failed(error): deliver(.task(token, .failed(error, request: id)))
            }
        }
        scriptRun = run.map { (id, $0) }
    }

    /// A `background` script extension: started on its own (the shell lists it, and says how it went). Not during secure
    /// input (nothing runs then), nor twice at once, nor more than four.
    private func startInBackground(_ command: Command, arguments: [String], query: String) {
        guard let script = command.script else { return }
        guard !secureInputActive() else {
            say(tr("系统安全输入已开启（密码框或锁屏），没有运行命令",
                          "Secure input is on (a password field or the lock screen): the command was not run"))
            return
        }
        // Held by the shell while the environment is made, not by this field: it starts even if the field is gone by
        // then. What went wrong is said here, or in the field being typed in then.
        let post = tasks.poster()
        services.startScriptInBackground(script, arguments, environmentMaker(script, query: query)) { post(.notice($0)) }
    }

    /// A `list` command as it's typed (`SessionTasks.runList`). `now`: without the delay.
    private func scheduleListRun(now: Bool = false) {
        tasks.runList(composer.listQuery, command: composer.draftCommand, now: now, secureInput: secureInputActive()) { script, query in
            environmentMaker(script, query: query)
        }
    }

    /// The status lines of the commands the list shows, when they're due (`SessionServices.refreshStatuses`); each one
    /// that ends redraws the list.
    private func refreshStatuses() {
        guard composer.paletteQuery != nil else { return }
        let shown = composer.paletteVisible.compactMap(\.script).filter { $0.status != nil }
        guard !shown.isEmpty, !secureInputActive() else { return }
        let config = services.loadSettings()
        let (index, context, preferences) = (services.loadExtensions(config, false), scriptContext(query: ""), services.extensionPreferences)
        let post = tasks.poster()
        services.refreshStatuses(shown, { command in
            let make = SessionTasks.environmentMaker(command, bundle: index.bundle(of: command), config: config, context: context,
                                                     preferences: preferences, status: true)
            guard case let .success(environment) = await make() else { return nil }
            return environment
        }, { post(.statusEnded) })
    }

    /// A send command's recipient as it is typed (`SessionTasks.findRecipients`).
    private func scheduleRecipientSearch() {
        tasks.findRecipients(composer.recipientQuery, recent: services.loadRecentHandles, contacts: services.loadContacts)
    }

    /// `@open` as you type (`SessionTasks.searchAsTyped`).
    private func scheduleLiveSearch() {
        tasks.searchAsTyped(composer.liveQuery, history: services.loadOpenHistory, with: services.searchFiles)
    }

    /// Sends a confirmed message (`SessionTasks.send`); a notice says how it went.
    private func sendMessage(_ text: String, to recipient: Recipient, command: Command) {
        guard !secureInputActive() else {
            say(tr("系统安全输入已开启（密码框或锁屏），没有发送", "Secure input is on (a password field or the lock screen): nothing was sent"))
            return
        }
        log.notice("@\(command.name): sending (\(text.count) chars)")
        tasks.send(text, to: recipient, command: command, with: services.messageSender)
    }

    // MARK: - The web page

    /// `@agent …` being written in a web browser: its page is asked for now, ready by ⏎; the draft given up (Esc, deleted,
    /// refused, another command), it's given back.
    private func wakePageIfAgent() {
        // `@reply` with nothing selected, copied or pasted takes the page too.
        let writingAgent = composer.draftCommand == .agent || composer.draftCommand == .reply && composer.replyTakesPage
        if wokenPage != nil, !writingAgent { return releasePage() }
        guard agentPageContext, wokenPage == nil, pageLookedFor != fieldSession, writingAgent else { return }
        pageLookedFor = fieldSession
        guard let page = services.page(app) else { return }
        wokenPage = page
        page.wake()
    }

    /// The page given back, if `@agent` asked for it.
    private func releasePage() {
        wokenPage?.release()
        wokenPage = nil
        pageLookedFor = -1  // written again in this field, asked for again
    }

    deinit {
        wokenPage?.release()  // let go while it asked for a page
    }

    /// `prompt` with the page `@agent` (or `@reply`) was typed in (`PageContext`) when that applies (a browser, the
    /// setting, the permission), read off the session's thread, as `render` puts them together (`@agent`'s:
    /// `PageContext.prompt`); `start` then gets it, with the page's title (nil: no page taken along, `prompt` as typed —
    /// at once). Until the page is in, the session waits (`waitsForPage`): the request starts even if the field is gone.
    private func withPage(_ prompt: String, render: @escaping @Sendable (PageContext, String) -> String = { $0.prompt(request: $1) },
                          _ start: @escaping (String, String?) -> Void) {
        guard agentPageContext, let page = wokenPage ?? services.page(app) else { return start(prompt, nil) }
        if wokenPage == nil { page.wake() }  // typed fast (or pasted): asked for now
        wokenPage = nil  // given back once read
        pageLookedFor = -1  // another `@agent` in this field asks again
        let log = self.log
        pageWaiters[tasks.readPage(page.reader())] = { context in
            guard let context, !context.isEmpty else {
                log.notice("@agent: no page context")
                return start(prompt, nil)
            }
            let full = render(context, prompt)
            log.notice("@agent: page context \(full.count - prompt.count) chars")
            start(full, context.title.isEmpty ? context.url : context.title)
        }
    }

    // MARK: - Notes and Reminders

    /// `@note`: the text goes where `Config.notes` says (`SessionServices.noteDestination`), in the background (the first
    /// time, the system may ask whether this may save there, and the save waits for the answer). 「正在存到 Notion…」 at
    /// once, up until a notice says where it is saved, or why not (`progressNoticeLimit` at most); a text that couldn't be
    /// saved is never lost (`SaveOutcome`). Only its length is logged.
    private func saveToNotes(_ text: String) {
        let destination = services.noteDestination(services.loadSettings().notes)
        let name = destination.name
        // The composer refuses it already; the setting may have changed since it was told.
        if destination.leavesDevice, secureInputActive() {
            log.notice("@note: not sent to Notion while secure input is on")
            if let effects = composer.restoreDraft(.note, text: text) { perform(effects) } else { emit(.copy(text)) }
            say(composer.messages.secureInputNote)
            return
        }
        // The kind of place, not its name (a folder's may say something of the user).
        log.notice("@note: saving \(text.count) chars to \(String(describing: type(of: destination)))")
        let zhName = UIText.afterChineseWord(name)
        let progress = tr("正在存到\(zhName)…", "Saving to \(name)…")
        say(progress, lasting: Self.progressNoticeLimit)
        tasks.saveNote(NoteDraft(text: text), to: destination, progress: progress, fieldSession: fieldSession, saved: services.noteSaved,
                       needsTheUser: services.needsTheUser, errorKind: errorKinds)
    }

    /// A confirmed `@reminder`: added in the background (the first time, the system asks for access, and this waits for
    /// the answer). 「正在加到提醒事项…」 at once, up until the notice says when it is due (「已加到提醒事项：明天 15:00」),
    /// or why it wasn't added (`progressNoticeLimit` at most): then `input`, the text it was read from, comes back.
    private func addToReminders(_ reminder: ReminderDraft, input: String) {
        let kind = reminder.due == nil ? "no date" : reminder.hasTime ? "a time" : "a day"
        log.notice("@reminder: adding one with \(kind)")
        let progress = tr("正在加到提醒事项…", "Adding to Reminders…")
        say(progress, lasting: Self.progressNoticeLimit)
        tasks.addReminder(reminder, input: input, progress: progress, fieldSession: fieldSession, with: services.addReminder,
                          needsTheUser: services.needsTheUser, errorKind: errorKinds)
    }

    /// `errorKind` from any thread.
    private var errorKinds: @Sendable (Error) -> String {
        let shell = services.errorKind
        return { shell($0) ?? Self.errorKind($0) }
    }

    /// How a save went, told where the user is: in this field while it's the one the save came from, else in the one being
    /// typed in now, else near the pointer (`SessionOutput.noticeElsewhere`). A failed save loses nothing: its text is back
    /// in the draft when nothing else is being typed here, else on the clipboard; on the clipboard as well when the user has
    /// to fix something first (going to the settings takes the focus, which commits the draft).
    private func saved(_ outcome: SaveOutcome) {
        guard outcome.fieldSession == fieldSession else {
            let (notice, long, copy) = outcome.elsewhere
            if let copy { emit(.copy(copy)) }
            emit(.noticeElsewhere(notice, long: long, endingHere: outcome.progress))
            return
        }
        switch outcome.result {
        case let .saved(notice):
            say(notice)
        case let .failed(reason, command, text, needsTheUser):
            if let effects = composer.restoreDraft(command, text: text) {
                perform(effects)
                if needsTheUser { emit(.copy(text)) }
                say(needsTheUser ? tr("原文也复制到了剪贴板。", "The text is on the clipboard too. ") + reason : reason, long: needsTheUser)
            } else {
                let (notice, long, copy) = outcome.elsewhere
                if let copy { emit(.copy(copy)) }
                say(notice, long: long)
            }
        }
    }

    // MARK: - The candidate panel and notices

    /// The candidate panel for the composer as it is now (`PanelPresenter`).
    public func panelModel() -> PanelModel { panelPresenter().model(for: composer) }

    /// What the panel is made from besides the composer: the settings now, this field's notice, app and last result.
    public func panelPresenter() -> PanelPresenter {
        let config = services.loadSettings()
        let jargon = services.jargon
        return PanelPresenter(config: config, app: field.app, notice: notice, elapsed: lastElapsed, fromCache: lastFromCache,
                              hidden: lastHidden, shortened: lastShortened, agent: agent, agentCommand: agentCommand,
                              jargon: { jargon(config) }, scriptStatus: services.scriptStatus, chip: services.translateChip)
    }

    private func showPanel() {
        emit(.panel(composer.wantsPanel ? panelModel() : nil))
    }

    /// A short status message ("英" English mode, "已复制" copied, …): on the panel's footer when it's shown, else on its
    /// own. `long`: something the user has to act on (a permission), up longer; `lasting`: up this long instead, unless
    /// another notice replaces it first (a save under way, until its outcome).
    public func showNotice(_ text: String, long: Bool = false, lasting: TimeInterval? = nil) -> [SessionOutput] {
        collect { say(text, long: long, lasting: lasting) }
    }

    private func say(_ text: String, long: Bool = false, lasting: TimeInterval? = nil) {
        notice = text
        noticeToken += 1
        emit(.startTimer(.notice(noticeToken), after: lasting ?? SessionText.noticeDuration(text, long: long)))
        if composer.wantsPanel {
            showPanel()
        } else {
            emit(.notice(text))
        }
    }

    /// Takes `text` down if it is still the notice here: a save's progress, once its outcome is told in another field.
    public func endNotice(_ text: String) -> [SessionOutput] {
        collect {
            guard notice == text else { return }
            noticeToken += 1
            noticeExpired()
        }
    }

    private func noticeExpired() {
        notice = nil
        showPanel()
    }
}
