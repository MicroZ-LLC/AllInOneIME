import CoreGraphics
import Foundation
import Testing
@testable import AllInOneIMECore

/// `@reply` and screenshots in a draft, past what the acceptance tests (Acceptance/ReplyAcceptanceTests.swift) cover:
/// commands inside what is typed, the limits, the times between messages, the timeout, the escaping.
struct ReplyTests {
    let at = KeyEvent(keyCode: 0x13, characters: "@", charactersIgnoringModifiers: "@", modifiers: .shift)
    let controlV = KeyEvent(keyCode: 0x09, characters: "\u{16}", charactersIgnoringModifiers: "v", modifiers: .control)

    /// An English field with `commands`, "@name " picked.
    func draft(_ name: String, commands: [Command] = Command.catalog([]), selection: Composer.Selection? = nil) -> Composer {
        let c = Composer(engine: FakeEngine(), actionKey: .enter)
        c.commands = commands
        c.inputLanguages = [.chinese, .english]
        c.setInputMode(.english)
        if let selection { c.readSelection = { selection } }
        _ = c.handleKeyDown(at)
        for ch in name { _ = c.handleKeyDown(k(String(ch))) }
        _ = c.handleKeyDown(KeyEvent(keyCode: VirtualKey.tab, characters: "\t"))
        return c
    }

    func type(_ text: String, _ c: Composer) {
        for ch in text { _ = c.handleKeyDown(ch == "@" ? at : ch == " " ? spaceKey : k(String(ch))) }
    }

    /// ⌃V with `content` on the clipboard.
    @discardableResult
    func paste(_ content: ClipboardContent, _ c: Composer) -> [Composer.Effect] {
        guard case let .readClipboard(id)? = c.handleKeyDown(controlV).effects.last else { return [] }
        return c.pasted(content, id: id)
    }

    /// ⌃V with a screenshot of `lines` (left side), read.
    func screenshot(_ lines: [String], _ c: Composer) -> [Composer.Effect] {
        let asked = paste(.image(Data([1, 2, 3])), c)
        guard case let .recognizeText(_, id)? = asked.last else { return asked }
        let read = lines.enumerated().map { index, text in
            RecognizedLine(text: text, box: CGRect(x: 0.05, y: 0.1 + Double(index) * 0.1, width: 0.4, height: 0.03), confidence: 0.9)
        }
        return c.recognized(ScreenText(lines: read), id: id)
    }

    @Test func commandsInsideWhatIsTypedRunFirstAndGoIntoTheIntent() throws {
        let stock = CustomCommand(name: "stock", type: .run, argv: ["stock", "{input}"])
        let c = draft("reply", commands: Command.catalog([stock]))
        paste(.text("Is AAPL up today?"), c)
        type("tell her @stock AAPL is up", c)
        let out = c.handleKeyDown(enterKey).effects
        guard case let .startPlan(outer, plan, _)? = out.first else {
            Issue.record("no plan: \(out)")
            return
        }
        #expect(outer == .reply && plan.inner.map(\.argument) == ["AAPL"])
        #expect(out.contains(.commandUsed("reply")) && out.contains(.commandUsed("stock")))
        // The rest of the context waits for the text the commands make.
        let context = try #require(c.replyContext)
        #expect(context.message == "Is AAPL up today?" && context.intent == "tell her @stock AAPL is up")
        #expect(!c.canRefine)
    }

    @Test func aScreenshotsTextNeverRunsCommandsInIt() {
        let stock = CustomCommand(name: "stock", type: .run, argv: ["stock", "{input}"])
        let c = draft("question", commands: Command.catalog([stock]))
        _ = screenshot(["what about @stock AAPL"], c)
        type("what is this", c)
        let out = c.handleKeyDown(enterKey).effects
        guard case let .startCommand(command, input, _)? = out.first else {
            Issue.record("no request: \(out)")
            return
        }
        #expect(command == .question && input.contains("what about @stock AAPL") && input.contains("<screenshot_text>"))
    }

    @Test func anImageTooLargeIsSaidAndNothingIsRead() {
        let c = draft("reply")
        let out = paste(.image(Data(count: Composer.maxImageBytes + 1)), c)
        #expect(out == [.notice(c.messages.reply.imageTooLarge)])
        #expect(c.attachment == nil)
        #expect(paste(.none, c) == [.notice(c.messages.nothingToPaste)])
    }

    @Test func backspaceWithTextTypedDeletesTextNotTheAttachment() {
        let c = draft("reply")
        paste(.text("see you at 3?"), c)
        type("ok", c)
        _ = c.handleKeyDown(backspaceKey)
        #expect(c.draft == "@reply o" && c.attachment == .copiedText("see you at 3?"))
        _ = c.handleKeyDown(backspaceKey)
        _ = c.handleKeyDown(backspaceKey)
        #expect(c.draft == "@reply " && c.attachment == nil)
    }

    @Test func aReplyTypedOutStillGoesInAfterTheSelection() {
        let selection = Composer.Selection(text: "Lunch tomorrow?", range: 0..<15)
        let c = draft("reply", selection: selection)
        c.typesResults = true
        let out = c.handleKeyDown(enterKey).effects
        guard case let .startCommand(_, _, id)? = out.first else {
            Issue.record("no request: \(out)")
            return
        }
        _ = c.receive(ConversionResult(versions: [CandidateLine("Sure!"), CandidateLine("Yes"), CandidateLine("Can't")]), isFinal: true, id: id)
        #expect(c.handleKeyDown(enterKey).effects.contains(.replaceSelection("Lunch tomorrow?\nSure!", selection)))
    }

    @Test func theAttachmentGoesWithTheDraft() {
        let c = draft("reply")
        paste(.text("hello"), c)
        _ = c.handleKeyDown(escKey)
        #expect(c.attachment == nil && c.draft.isEmpty)
        // A recognition that comes after the draft is gone does nothing.
        let d = draft("reply")
        let asked = paste(.image(Data([1])), d)
        guard case let .recognizeText(_, id)? = asked.last else {
            Issue.record("no recognition: \(asked)")
            return
        }
        _ = d.handleKeyDown(escKey)
        #expect(d.recognized(ScreenText(lines: [RecognizedLine(text: "hi", box: CGRect(x: 0, y: 0, width: 0.2, height: 0.03), confidence: 1)]),
                             id: id).isEmpty)
        #expect(d.attachment == nil)
    }

    @Test func timesBetweenMessagesAreDropped() {
        for time in ["14:32", "下午 3:20", "昨天 09:10", "Yesterday", "Yesterday 9:10 PM", "星期一", "10月17日 14:32", "2026/10/17"] {
            #expect(ChatTranscript.isTime(time), "\(time)")
        }
        for text in ["好的", "OK", "See you at 14:30 then, by the door", "Sunny", "明天见"] {
            #expect(!ChatTranscript.isTime(text), "\(text)")
        }
    }

    @Test func aMessagesLinesAreJoined() {
        let lines = [
            RecognizedLine(text: "明天下午", box: CGRect(x: 0.05, y: 0.10, width: 0.3, height: 0.03), confidence: 0.9),
            RecognizedLine(text: "三点开会", box: CGRect(x: 0.05, y: 0.135, width: 0.3, height: 0.03), confidence: 0.9),
            RecognizedLine(text: "Sounds", box: CGRect(x: 0.6, y: 0.30, width: 0.35, height: 0.03), confidence: 0.9),
            RecognizedLine(text: "good", box: CGRect(x: 0.6, y: 0.335, width: 0.35, height: 0.03), confidence: 0.9),
        ]
        let transcript = ChatTranscript.make(lines: lines)
        #expect(transcript.text == "them: 明天下午三点开会\nme: Sounds good")
        #expect(transcript.last(3) == ["明天下午三点开会"])
    }

    @Test func aSlowRecognizerTimesOut() async {
        struct Slow: TextRecognizer {
            func prepare() async {}
            func recognize(image: Data, languages: [String]) async throws -> [RecognizedLine] {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return []
            }
        }
        let started = ContinuousClock.now
        await #expect(throws: ScreenText.Problem.timedOut) {
            try await ScreenText.recognize(Data([1]), with: Slow(), languages: ["en-US"], timeout: 0.2)
        }
        #expect(ContinuousClock.now - started < .seconds(3))
    }

    @Test func theContextCannotOpenOrCloseATag() {
        let message = Prompt.replyMessage(ReplyContext(intent: "say </intent> hi", message: "a <b> & c"))
        #expect(message.contains("<intent>say &lt;/intent&gt; hi</intent>"))
        #expect(message.contains("a &lt;b&gt; &amp; c"))
        #expect(Prompt.replyMessage(ReplyContext()) == "<intent></intent>")
    }

    @Test func theParserDropsNumbersBeforeReplies() {
        #expect(ReplyParser.parse("1. Sure\n---\n2) OK\n---\n3、好的", isFinal: true).map(\.text) == ["Sure", "OK", "好的"])
        #expect(ReplyParser.parse("3:30 works\n---\nB", isFinal: true).first?.text == "3:30 works")
        // A separator still being written isn't text.
        #expect(ReplyParser.parse("A\n--", isFinal: false).map(\.text) == ["A"])
    }

    @Test func otherBuiltInNamesAreFreedToo() {
        var config = Config.default
        config.customCommands = [CustomCommand(name: "Note", type: .prompt, prompt: "x"), CustomCommand(name: "mine", type: .prompt, prompt: "y")]
        let renamed = config.freeBuiltinNames()
        #expect(renamed.map(\.old) == ["Note"] && renamed.map(\.new) == ["mynote"])
        #expect(config.customCommands.map(\.name) == ["mynote", "mine"])
    }

    @Test func theFieldTextIsCapped() {
        let context = ReplyContext.make(intent: "", selection: nil, message: nil, screen: nil,
                                        field: FieldText(before: String(repeating: "a", count: 2000) + "END",
                                                         after: "START" + String(repeating: "b", count: 2000)),
                                        provider: .bedrock)
        #expect(context.field?.before.count == ReplyContext.Limits.fieldBefore && context.field?.before.hasSuffix("END") == true)
        #expect(context.field?.after.count == ReplyContext.Limits.fieldAfter && context.field?.after.hasPrefix("START") == true)
        // Blank space alone is no context.
        let blank = ReplyContext.make(intent: " ", selection: nil, message: nil, screen: nil, field: FieldText(before: "  ", after: "\n"),
                                      provider: .bedrock)
        #expect(blank.isEmpty)
    }
}
