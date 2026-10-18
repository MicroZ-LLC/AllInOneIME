import Foundation

// MARK: - @reply, and a screenshot pasted into a draft

/// What ⌃V (or ⌘V where a draft takes pastes) found on the clipboard, as the shell read it: its text first, else an image
/// (PNG or TIFF, not marked concealed or transient), else nothing. Nothing is read during secure input.
public enum ClipboardContent: Equatable, Sendable {
    case text(String)
    case image(Data)
    case none
}

/// `@reply` writes three replies to the message being answered (`ReplyContext`): the text selected, a message copied and
/// pasted in, or a screenshot pasted with ⌃V, read on the device. A screenshot pasted into any other command works too:
/// the AI's commands take its text as context (`@question`) or as the text to work on (`@translate`, as a selection
/// would be), the others get it pasted as text (`@note` keeps its lines). The panel shows what is attached (`attachment`);
/// ⌫ with nothing typed after the command takes it away.
extension Composer {
    /// What the draft has besides its text.
    public enum Attachment: Equatable, Sendable {
        /// A screenshot pasted in (⌃V with an image on the clipboard), being read or read.
        case screenshot(Screenshot)
        /// A message copied and pasted into `@reply` (its lines kept, at most `ReplyContext.Limits.message`).
        case copiedText(String)
    }

    public enum Screenshot: Equatable, Sendable {
        /// Its text is being read on the device (`Effect.recognizeText`).
        case recognizing
        case ready(ScreenText)
    }

    /// The most of an image ⌃V takes (a screenshot is far smaller).
    public static let maxImageBytes = 30 * 1024 * 1024

    /// The instruction ⌘R sends for three more replies (`handleReplyKey`).
    public static let moreReplies = "Write three different replies."

    /// What the draft has besides its text (nil: nothing).
    public internal(set) var attachment: Attachment? {
        get { replyState.attachment }
        set { replyState.attachment = newValue }
    }

    /// The text around the caret in the field, without the draft (set by the shell; nil: none, or not to be read: secure
    /// input). `@reply` sends it as context.
    public var readFieldText: () -> FieldText? {
        get { replyState.readFieldText }
        set { replyState.readFieldText = newValue }
    }

    /// Whether `@reply` here takes the web page along (Chrome with its switch on, set by the shell): then it goes with
    /// nothing else to reply to, the page being the context.
    public var pageContextApplies: () -> Bool {
        get { replyState.pageContextApplies }
        set { replyState.pageContextApplies = newValue }
    }

    /// The provider requests go to (`Config.provider`, set by the shell): the on-device model gets a shorter screenshot
    /// (`ReplyContext.Limits.screenshotOnDevice`).
    public var provider: Provider {
        get { replyState.provider }
        set { replyState.provider = newValue }
    }

    /// What `@reply` was sent with (nil before it runs): the shell puts the outputs of commands inside its text into it
    /// (`@reply tell her @stock AAPL is up`: `Effect.startPlan`, then `Prompt.replyMessage` with the text they make).
    public var replyContext: ReplyContext? { replyState.context }

    /// `@reply` runs, or ran, with nothing selected, copied or pasted: the shell adds the web page, if it applies
    /// (`pageContextApplies`).
    public var replyTakesPage: Bool {
        draftCommand == .reply && selectionInUse == nil && attachment == nil
    }

    /// A screenshot's text was read for recognition `id` (`Effect.recognizeText`): the attachment is ready. The AI's
    /// commands keep it to use at the action key (`@translate` on a selection doesn't: the selection wins, as a notice
    /// says); the others get its text pasted into the draft. If the action key was pressed meanwhile, the command runs
    /// now. Nil text, or none in it: a notice. Another recognition's answer does nothing.
    public func recognized(_ text: ScreenText?, id: Int) -> [Effect] { forField(screenshotRead(text, id: id)) }

    /// The screenshot of recognition `id` couldn't be read (`message` says why): the attachment goes, and a request
    /// waiting for it isn't sent. Another recognition's failure does nothing.
    public func recognitionFailed(_ message: String, id: Int) -> [Effect] {
        guard replyState.recognitionID == id, case .screenshot(.recognizing)? = attachment else { return [] }
        replyState.recognitionID = nil
        replyState.startWhenRead = false
        attachment = nil
        return forField([.notice(message), .updateMarkedText, wantsPanel ? .showPanel : .hidePanel])
    }

    /// A command is picked whose draft a screenshot can be pasted into (not `@tasks` or `@settings`, which take no
    /// text): the shell loads the recognizer ahead of time if the clipboard has an image (`TextRecognizer.prepare`).
    /// Not on "@" alone, which in a chat app is often a mention.
    public var draftTakesScreenshot: Bool {
        guard !isLevelTwo, let command = draftCommand else { return false }
        return command.kind != .agents && command.kind != .settings
    }

    /// Whether the action key waits for the screenshot being read.
    public var readingScreenshot: Bool {
        if case .screenshot(.recognizing)? = attachment { return true }
        return false
    }

    private func screenshotRead(_ text: ScreenText?, id: Int) -> [Effect] {
        guard replyState.recognitionID == id, readingScreenshot else { return [] }
        replyState.recognitionID = nil
        let start = replyState.startWhenRead
        replyState.startWhenRead = false
        guard let text, !text.text.isEmpty else {
            attachment = nil
            return [.notice(messages.reply.noText), .updateMarkedText, .showPanel]
        }
        var effects: [Effect]
        if let command = draftCommand, !isLevelTwo, !command.usesAI {
            // A command without AI: the text goes in as clipboard text would.
            attachment = nil
            effects = insertPasted(text.text)
        } else if draftCommand?.kind == .convert, selectionInUse != nil {
            // The selection is what `@improve` and `@translate` work on.
            attachment = nil
            effects = [.notice(messages.reply.screenshotUnused), .showPanel]
        } else {
            attachment = .screenshot(.ready(text))
            effects = [.updateMarkedText, .showPanel]
        }
        if start, !isLevelTwo, draftCommand != nil {
            setLevelOnePhase()
            effects += startAction().effects
        }
        return effects
    }

    /// An image pasted (`pasted`): read on the device (`Effect.recognizeText`), the attachment shown as being read.
    func pasteScreenshot(_ image: Data) -> [Effect] {
        guard image.count <= Self.maxImageBytes else { return [.notice(messages.reply.imageTooLarge)] }
        replyState.counter += 1
        replyState.recognitionID = replyState.counter
        replyState.startWhenRead = false
        attachment = .screenshot(.recognizing)
        return [.updateMarkedText, .showPanel, .recognizeText(image: image, id: replyState.counter)]
    }

    /// Text pasted into `@reply`: the message replied to (`Attachment.copiedText`), the draft as it was. Nil for every
    /// other command (the text goes into its draft).
    func pasteReplyMessage(_ clipboard: String) -> [Effect]? {
        guard draftCommand == .reply else { return nil }
        // A long one is cut before it is looked at (this runs on the main thread): its end, the latest of it.
        let limit = ReplyContext.Limits.message
        let text = ReplyContext.lastLines(Self.noteText(String(clipboard.suffix(limit * 2))), limit: limit)
        guard !text.isEmpty else { return [.notice(messages.nothingToPaste)] }
        replyState.recognitionID = nil
        replyState.startWhenRead = false
        attachment = .copiedText(text)
        return [.updateMarkedText, .showPanel]
    }

    /// ⌫ with nothing typed after the command: the attachment goes (a screenshot still being read is forgotten).
    func removeAttachment() -> Bool {
        guard attachment != nil, let command = draftCommand, draft == "@\(command.name) " else { return false }
        attachment = nil
        replyState.recognitionID = nil
        replyState.startWhenRead = false
        return true
    }

    /// The screenshot's text for `command` at the action key: the AI's commands' (nil for the others, which had it
    /// pasted, and when there is none).
    func screenshotText(for command: Command) -> String? {
        guard case let .screenshot(.ready(text))? = attachment, command.usesAI else { return nil }
        return text.text
    }

    /// The action key on `@reply`, or on any command while its screenshot is read (it waits: the command runs once it
    /// is, `recognized`). `@reply` with nothing to reply to and nothing typed says what it needs (unless the page is the
    /// context: `pageContextApplies`); in an app with no AI it's refused, its draft kept. Otherwise its request starts
    /// (`Effect.startCommand(.reply, input: Prompt.replyMessage(context))`); with commands inside what is typed
    /// (`@stock AAPL`), they run first (`Effect.startPlan`), and their outputs go into the intent (`replyContext`). Nil:
    /// the command goes on as usual.
    func startReply(_ command: Command, typed: String) -> Response? {
        if readingScreenshot {
            replyState.startWhenRead = true
            return .consumed([.notice(messages.reply.reading), .showPanel])
        }
        guard command == .reply else { return nil }
        var message: String?
        var screen: ScreenText?
        switch attachment {
        case let .copiedText(text)?: message = text
        case let .screenshot(.ready(text))?: screen = text
        case .screenshot(.recognizing)?, nil: break
        }
        let context = ReplyContext.make(intent: typed, selection: selectionInUse, message: message, screen: screen,
                                        field: readFieldText(), provider: provider)
        if context.isEmpty, !pageContextApplies() { return .consumed([.notice(messages.reply.hint)]) }
        if let refusal = aiRefusal() { return .consumed([.updateMarkedText, .notice(refusal)]) }
        let (plan, codeLeft) = innerPlan(typed)
        let input = Prompt.replyMessage(context)
        replyState.context = context
        requestCounter += 1
        phase = .translating(id: requestCounter)
        result = .empty
        searchResults = []
        pendingReminder = nil
        highlightOverride = nil
        activeCommand = command
        let start: Effect
        if plan.isEmpty {
            refineRequest = .command(command, input: input)
            start = .startCommand(command, input: input, id: requestCounter)
        } else {
            // The model saw the commands' outputs, which the composer doesn't have: no refine.
            refineRequest = nil
            start = .startPlan(outer: command, plan: plan, id: requestCounter)
        }
        let usage = ([command] + plan.inner.map(\.command)).map(used)
        return .consumed([start, .updateMarkedText, .showPanel] + usage + (codeLeft ? [.notice(messages.codeNotRun)] : []))
    }

    /// `@reply`'s rows: "0" what was typed (none when nothing was), "1"–"3" the replies.
    var replyChoices: [Choice] {
        var out: [Choice] = []
        if !sentText.isEmpty { out.append(Choice(label: "0", kind: .original, text: sentText, isComplete: true)) }
        for (index, line) in result.versions.prefix(ReplyParser.maxReplies).enumerated() {
            out.append(Choice(label: String(index + 1), kind: .answer, text: line.text, isComplete: line.isComplete))
        }
        return out
    }

    /// `@reply`'s highlighted row: the first reply, even before it has come in (nil: not `@reply`).
    func replyHighlight(_ choices: [Choice]) -> Int? {
        guard activeCommand == .reply else { return nil }
        return choices.firstIndex { $0.kind == .answer } ?? (sentText.isEmpty ? 0 : 1)
    }

    /// A reply picked on a selected message goes in after it, on a line of its own (the message stays). Nil otherwise.
    func commitReply(_ choice: Choice) -> [Effect]? {
        guard activeCommand == .reply, choice.kind == .answer, let selected = selection else { return nil }
        return finish(committing: selected.text + "\n" + choice.text, selection: .replaced)
    }

    /// ⌘R on `@reply`'s replies: three more (a refine with `moreReplies`); Esc goes back to these. Nil: the key acts as
    /// usual.
    func handleReplyKey(_ event: KeyEvent) -> Response? {
        let modifiers = event.modifiers.subtracting(.capsLock), primary = Modifiers.kind(modifierRoles.primary)
        guard activeCommand == .reply, phase == .choosing, canRefine, modifiers == primary,
              event.charactersIgnoringModifiers.lowercased() == "r" else { return nil }
        if let engine, engine.snapshot().isComposing {
            engine.clearComposition()
            refreshEngineState()
        }
        refineText = Self.moreReplies
        return .consumed(runRefine())
    }

    /// What `@reply` and a screenshot in a draft say, in the interface language.
    public struct ReplyMessages: Equatable, Sendable {
        /// `@reply` with nothing to reply to and nothing typed.
        public var hint: String
        /// The action key while the screenshot is read: the command runs once it is.
        public var reading: String
        public var noText: String
        public var unsupported: String
        public var imageTooLarge: String
        public var timedOut: String
        /// `@improve` / `@translate` with a selection and a screenshot: the selection was used.
        public var screenshotUnused: String
        /// The interface language they're in (`InterfaceWords`), for the ones made with what they say (`renamed`).
        public var language: String

        /// What `problem` means, to say it.
        public func describe(_ problem: ScreenText.Problem) -> String {
            switch problem {
            case .unsupported: return unsupported
            case .noText: return noText
            case .timedOut: return timedOut
            }
        }

        /// A custom command renamed for a built-in that has its name now (`Config.freeBuiltinNames`): "Your own @reply
        /// is now @myreply: @reply is built in"; when that built-in is off (`Command.off`, not offered), only the rename.
        public func renamed(old: String, new: String) -> String {
            let t = InterfaceWords(language: language)
            let old = old.lowercased()
            guard !Command.off.contains(where: { $0.name == old }) else {
                return t.tr("你自己的 @\(old) 改名为 @\(new)", "Your own @\(old) is now @\(new)")
            }
            return t.tr("你自己的 @\(old) 改名为 @\(new)：@\(old) 现在是内置命令", "Your own @\(old) is now @\(new): @\(old) is built in")
        }

        public static func make(language: String) -> ReplyMessages {
            let t = InterfaceWords(language: language)
            return ReplyMessages(
                hint: t.tr("先选中或复制对方的消息，或截图后按 ⌃V；也可以直接写要回什么",
                           "Select or copy their message, or take a screenshot and press ⌃V; or write what to reply"),
                reading: t.tr("正在本机识别截图（第一次较慢）…", "Reading the screenshot on this Mac (slower the first time)…"),
                noText: t.tr("截图里没有认出文字", "No text found in the screenshot"),
                unsupported: t.tr("这台设备不能识别图片里的文字", "This device can't read text in images"),
                imageTooLarge: t.tr("图片太大：最多 30 MB", "The image is too large: 30 MB at most"),
                timedOut: t.tr("识别截图超时，再试一次", "Reading the screenshot took too long; try again"),
                screenshotUnused: t.tr("已有选中的文字，截图没有用上", "Text is selected: the screenshot wasn't used"),
                language: language)
        }

        public static let chinese = make(language: "zh-Hans")
        public static let english = make(language: "en")
    }
}

extension Composer.Messages {
    /// `@reply` with nothing to reply to and nothing typed (`ReplyMessages.hint`).
    public var replyHint: String { reply.hint }
    /// A selection and a screenshot: the selection was used (`ReplyMessages.screenshotUnused`).
    public var screenshotUnused: String { reply.screenshotUnused }
}

/// The composer's `@reply` and screenshot state, and the shell's hooks for them (Composer+Reply.swift).
struct ReplyState {
    var attachment: Composer.Attachment?
    /// The recognition the screenshot attached waits for (`Effect.recognizeText`), and the last one's id.
    var recognitionID: Int?
    var counter = 0
    /// The action key was pressed while the screenshot was read: the command runs once it is.
    var startWhenRead = false
    /// What `@reply` was sent with.
    var context: ReplyContext?
    var readFieldText: () -> FieldText? = { nil }
    var pageContextApplies: () -> Bool = { false }
    var provider = Provider.bedrock

    /// The draft is done: what it had attached goes (the hooks stay).
    mutating func draftEnded() {
        attachment = nil
        recognitionID = nil
        startWhenRead = false
        context = nil
    }
}
