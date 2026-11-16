import Foundation

// MARK: - A screenshot asked about (⌃V into a question or a follow-up)

/// ⌃V (⌘V where a draft takes pastes) with an image on the clipboard while asking AI: an `@question` draft, one @'s text
/// (Ask AI goes first then), or a follow-up being typed in the conversation. Its text is read on the device as for any
/// command (Composer+Reply.swift); the image, made smaller (`PromptImage`), goes with the question to an AI that can see
/// it (`aiSeesImages`), the text with it either way (`QuestionConversation.attachments`). A screenshot with no text is
/// kept only for such an AI. A question asked with one isn't kept in the recent questions (`rememberAnswer`).
extension Composer {
    /// Whether the AI the questions go to can see an image (set by the session from the AI chosen:
    /// `Provider.seesImages`, or a question session's CLI, which all can).
    public var aiSeesImages: () -> Bool {
        get { replyState.seesImages }
        set { replyState.seesImages = newValue }
    }

    /// A screenshot pasted while a follow-up is typed: being read, then ready; sent with the follow-up (`runRefine`).
    public var followUpAttachment: Attachment? { replyState.followUp }

    /// The draft asks AI a question: `@question`, or one @'s text (Ask AI is offered first with a screenshot).
    var asksWithScreenshot: Bool { draftCommand == .question || (draftCommand == nil && oneAt != nil) }

    /// A screenshot went with the question or a follow-up: the conversation isn't kept (`rememberAnswer`).
    var hasQuestionScreenshot: Bool { !(questionConversation?.attachments.isEmpty ?? true) }

    /// The first question's attachment (`QuestionConversation.attachments[0]`): the screenshot's text and its image.
    func questionAttachments(_ command: Command) -> [Int: QuestionConversation.Attachment] {
        guard command == .question, let text = screenshotText(for: command) else { return [:] }
        return [0: QuestionConversation.Attachment(text: text, image: replyState.image)]
    }

    /// `conversation` with the follow-up's screenshot, ready, as the round just added (`runRefine`); it goes from the line.
    func withFollowUpAttachment(_ conversation: QuestionConversation) -> QuestionConversation {
        guard case let .screenshot(.ready(text))? = replyState.followUp else { return conversation }
        var conversation = conversation
        conversation.attachments[refinements.count] = QuestionConversation.Attachment(text: text.text, image: replyState.followUpImage)
        replyState.followUpEnded()
        return conversation
    }

    /// ⌘V or ⌃V while a follow-up can be typed: the clipboard is read for it (`followUpPasted`). Nil: another key.
    func followUpPasteKey(_ event: KeyEvent) -> Response? {
        guard typesRefine, !showsHandoff, event.charactersIgnoringModifiers.lowercased() == "v" else { return nil }
        let modifiers = event.modifiers.subtracting(.capsLock), roles = modifierRoles
        guard modifiers == Modifiers.kind(roles.primary) || roles.pasteAnywhere.map({ modifiers == Modifiers.kind($0) }) == true
        else { return nil }
        var effects: [Effect] = []
        if let engine, engine.snapshot().isComposing { effects += convertComposition(engine) }
        return .consumed(effects + [.showPanel, requestClipboard()])
    }

    /// The clipboard read for a follow-up: its text goes on the line (one line), an image is a screenshot for it.
    func followUpPasted(_ content: ClipboardContent) -> [Effect] {
        guard isQuestionChat, typesRefine else { return [] }
        switch content {
        case let .text(text):
            if text.utf16.count > Self.maxPasteLength * 8 { return [.notice(messages.pasteTooLong)] }
            let line = Self.oneLine(text)
            guard !line.isEmpty else { return [.notice(messages.nothingToPaste)] }
            guard (refineText + line).count <= Self.maxPasteLength else { return [.notice(messages.pasteTooLong)] }
            refineText += line
            return [.showPanel]
        case let .image(image):
            guard image.count <= Self.maxImageBytes else { return [.notice(messages.reply.imageTooLarge), .showPanel] }
            replyState.counter += 1
            replyState.followUpRecognition = replyState.counter
            replyState.followUp = .screenshot(.recognizing)
            replyState.followUpImage = nil
            return [.showPanel, .recognizeText(image: image, id: replyState.counter)]
        case .none:
            return [.notice(messages.nothingToPaste), .showPanel]
        }
    }

    /// The follow-up's screenshot read: ready (with no text, only for an AI that can see the image), or gone with a notice.
    func followUpScreenshotRead(_ text: ScreenText?, image: PromptImage?) -> [Effect] {
        replyState.followUpRecognition = nil
        guard case .screenshot(.recognizing)? = replyState.followUp else { return [] }
        let imageAlone = image != nil && aiSeesImages()
        guard let text = text ?? (imageAlone ? ScreenText(lines: []) : nil), !text.text.isEmpty || imageAlone else {
            replyState.followUpEnded()
            return [.notice(messages.reply.noText), .showPanel]
        }
        replyState.followUp = .screenshot(.ready(text))
        replyState.followUpImage = image
        return [.showPanel]
    }

    /// The follow-up's screenshot couldn't be read (`message` says why): it goes.
    func followUpRecognitionFailed(_ message: String) -> [Effect] {
        guard replyState.followUp != nil else { return [] }
        replyState.followUpEnded()
        return [.notice(message), .showPanel]
    }

    /// ⏎ on a follow-up while its screenshot is read: it waits (the reading is quick). ⌫ on an empty line with one
    /// attached: it goes, before ⌫ steps back a round. Nil: neither.
    func followUpAttachmentKey(_ event: KeyEvent) -> Response? {
        guard replyState.followUp != nil, event.modifiers.subtracting(.capsLock).isEmpty else { return nil }
        if event.key == .enter || event.key == .keypadEnter, case .screenshot(.recognizing)? = replyState.followUp {
            return .consumed([.notice(messages.reply.reading), .showPanel])
        }
        if event.key == .backspace, refineText.isEmpty, !(engine?.snapshot().isComposing ?? false) {
            replyState.followUpEnded()
            return .consumed([.showPanel])
        }
        return nil
    }

    /// One @'s rows with a screenshot attached: Ask AI first (it is what a screenshot is pasted for).
    func screenshotFirst(_ rows: [OneAt.Action]) -> [OneAt.Action] {
        guard attachment != nil, let ask = rows.firstIndex(where: { if case .write(.question) = $0 { true } else { false } })
        else { return rows }
        var rows = rows
        rows.insert(rows.remove(at: ask), at: 0)
        return rows
    }
}
