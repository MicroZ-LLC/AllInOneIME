import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// What a request sends of the text before the caret (the owner's decision for 0.6.7): the text is split into sentences
/// (at sentence ends and line breaks), each in a pool by its language; the caret's line goes whole, and before it the most
/// recent sentences of the line's pool, 200 characters at most, in their order, a line break where sentences were left
/// out. Before, the last 1,500 characters went as one block: with a Chinese paragraph above an English line, the model
/// saw Chinese and went on with the English in Chinese.
@Suite(.serialized)
struct AutocompletePoolsTests {
    /// What goes before the caret's line at most (`Autocomplete.poolLimit`).
    static let limit = 200

    /// What a request for the field's text `before` (the caret at its end) sends of it: what is between <before> and
    /// </before>.
    static func sent(_ before: String) -> String? {
        guard let context = Autocomplete.context(FieldText(before: before, after: "")) else { return nil }
        return Self.before(in: Prompt.autocompleteRequest(context, app: nil).messages.last?.content[0].text ?? "")
    }

    static func before(in message: String) -> String? {
        message.components(separatedBy: "<before>").dropFirst().first?.components(separatedBy: "</before>").first
    }

    /// `sent` without the caret's line `line` at its end: what went of the text before it.
    static func earlier(_ sent: String?, line: String) -> String? {
        guard let sent, sent.hasSuffix(line) else { return nil }
        return String(sent.dropLast(line.count))
    }

    static let chineseParagraph = "我原本计划明天去hiking，天气不太适合户外活动。图书馆有新书推荐。"
    static let mail = "Hi Sarah,\n\nThanks for sending the slides. I will review them and get back to you by Friday."

    // MARK: - The owner's example

    /// The owner's note: a Chinese paragraph, a blank line, an English line. The request holds no Chinese, ends with the
    /// English line, and holds no more than 200 characters of earlier English (here none).
    @Test func theOwnersEnglishLineUnderAChineseParagraphGetsNoChinese() throws {
        let line = "I have an appointment today, "
        let sent = try #require(Self.sent(Self.chineseParagraph + "\n\n" + line))
        #expect(!sent.contains { $0.isWideLetter }, "\(sent)")
        #expect(sent.hasSuffix(line))
        #expect(sent == line)
    }

    /// English above the Chinese paragraph goes, in its order, with a line break where the Chinese was.
    @Test func earlierEnglishGoesWithTheEnglishLine() throws {
        let line = "I have an appointment today, "
        let sent = try #require(Self.sent(Self.mail + "\n\n" + Self.chineseParagraph + "\n\n" + line))
        #expect(sent == Self.mail + "\n" + line, "\(sent.debugDescription)")
        #expect(!sent.contains { $0.isWideLetter })
    }

    /// Much English above it: the request still ends with the English line, has no Chinese, and no more than 200
    /// characters of the English before it.
    @Test func atMost200CharactersOfEarlierEnglish() throws {
        let line = "I have an appointment today, "
        let english = (1...30).map { "We went over item \($0) of the plan again." }.joined(separator: " ")
        let sent = try #require(Self.sent(english + "\n\n" + Self.chineseParagraph + "\n\n" + line))
        let earlier = try #require(Self.earlier(sent, line: line))
        #expect(!sent.contains { $0.isWideLetter })
        #expect(!earlier.isEmpty && earlier.count <= Self.limit, "\(earlier.count): \(earlier.debugDescription)")
        #expect(english.hasSuffix(earlier.dropLast()) && earlier.hasPrefix("We went over item "), "\(earlier.debugDescription)")
    }

    // MARK: - Each line its own pool

    /// A Chinese line after English paragraphs: only the Chinese sentences go.
    @Test func aChineseLineAfterEnglishGetsOnlyTheChinese() throws {
        let before = "Thanks for the update. I will review it tomorrow.\n\n会议改到明天下午。\n\nPlease bring the slides.\n\n我们明天"
        let sent = try #require(Self.sent(before))
        #expect(sent == "会议改到明天下午。\n我们明天", "\(sent.debugDescription)")
        #expect(!sent.contains { $0.isASCII && $0.isLetter })
        // Nothing of its language before it: the line alone.
        #expect(Self.sent(Self.mail + "\n\n明天下午三点开会") == "明天下午三点开会")
    }

    /// A Chinese sentence with English words in it is Chinese: the line keeps them, and so does such a sentence before it.
    @Test func aMixedChineseLineKeepsItsEnglishWords() throws {
        #expect(Self.sent("Sounds good, see you then.\n我原本计划明天去hiking，") == "我原本计划明天去hiking，")
        let before = "我们明天 review the new design。\nThe meeting is at ten.\n然后我们"
        #expect(Self.sent(before) == "我们明天 review the new design。\n然后我们")
        // The owner's own line.
        #expect(Self.sent(Self.chineseParagraph + "我们明天") == Self.chineseParagraph + "我们明天")
    }

    /// Japanese (kana, though it has kanji too) and Korean (Hangul) have pools of their own, apart from Chinese.
    @Test func japaneseAndKoreanGoToTheirOwnPools() throws {
        #expect(Self.sent("明日の会議は十時からです。\n今天天气很好。\n資料を") == "明日の会議は十時からです。\n資料を")
        #expect(Self.sent("明日の会議は十時からです。\n我们明天") == "我们明天")
        #expect(Self.sent("오늘 회의는 열 시입니다.\n我们明天开会。\nSee you there.\n회의 자료를") == "오늘 회의는 열 시입니다.\n회의 자료를")
        #expect(Self.sent("오늘 회의는 열 시입니다.\nSee you at the") == "See you at the")
    }

    /// Other scripts by script: Hindi (Devanagari, its sentences ending with ।), Russian (Cyrillic).
    @Test func otherScriptsByScript() throws {
        #expect(Self.sent("मैं कल दिल्ली जाऊँगा। I will call you.\nहम कल मिलेंगे") == "मैं कल दिल्ली जाऊँगा।\nहम कल मिलेंगे")
        #expect(Self.sent("Спасибо за письмо.\nSee you tomorrow.\nДо встречи") == "Спасибо за письмо.\nДо встречи")
        // French and English are one pool: Latin letters.
        #expect(Self.sent("Merci pour le message.\n明天见。\nSee you at the") == "Merci pour le message.\nSee you at the")
    }

    /// A line with under two words to tell by goes by the lines above it (`Autocomplete.languageText`), as the examples do.
    @Test func aLineWithTooLittleToTellByGoesByTheTextAboveIt() throws {
        #expect(Self.sent("Thanks for the update.\n" + Self.chineseParagraph + "\nOK ") == Self.chineseParagraph + "\nOK ")
    }

    // MARK: - 200 characters

    /// The sentences go whole: as many of the most recent ones as fit in 200 characters (with what is between them),
    /// exactly 200 included.
    @Test func twoHundredCharactersAtSentenceBoundaries() throws {
        let sentences = (1...12).map { "This is sentence number \($0) of the note." }
        let line = "And then we"
        let sent = try #require(Self.sent(sentences.joined(separator: " ") + "\n" + line))
        let fits = (1...sentences.count).map { sentences.suffix($0).joined(separator: " ") + "\n" }.last { $0.count <= Self.limit }
        #expect(sent == (fits ?? "") + line, "\(sent.debugDescription)")
        #expect(Self.earlier(sent, line: line)?.count ?? 0 <= Self.limit)
        // One sentence more would be over.
        let count = fits.map { $0.components(separatedBy: ". ").count } ?? 0
        #expect(sentences.suffix(count + 1).joined(separator: " ").count + 1 > Self.limit)
        // Exactly 200 goes: a sentence of 199 characters and its line break.
        let exact = String(repeating: "word ", count: 39) + "done."  // 200 characters
        #expect(Self.sent("First.\n" + String(exact.dropFirst()) + "\n" + line) == String(exact.dropFirst()) + "\n" + line)
    }

    /// Chinese is counted in characters too.
    @Test func twoHundredChineseCharacters() throws {
        let sentences = (1...20).map { "这是第\($0)句话，我们一起讨论项目的进度。" }
        let line = "然后我们"
        let sent = try #require(Self.sent(sentences.joined() + "\n" + line))
        let earlier = try #require(Self.earlier(sent, line: line))
        #expect(earlier.count <= Self.limit && earlier.count > Self.limit - 25, "\(earlier.count)")
        #expect(earlier.hasPrefix("这是第") && sentences.joined().hasSuffix(earlier.dropLast()))
    }

    /// A sentence longer than all of it: its end, cut from its start between characters (never in the middle of one:
    /// a character outside the BMP, an emoji of several).
    @Test func aVeryLongSentenceIsCutFromItsStart() throws {
        let long = String(repeating: "我们𠮷👨‍👩‍👧", count: 100) + "。"
        let line = "然后我们"
        let sent = try #require(Self.sent(long + "\n" + line))
        let earlier = try #require(Self.earlier(sent, line: line))
        #expect(earlier == String(long.suffix(Self.limit - 1)) + "\n", "\(earlier.count): \(earlier.prefix(10))")
        #expect(["我", "们", "𠮷", "👨‍👩‍👧"].contains(earlier.first.map(String.init) ?? ""))
        // In English too, on a line of its own with no full stop.
        let english = Array(repeating: "and then some more", count: 30).joined(separator: " ")
        let cut = try #require(Self.earlier(Self.sent(english + "\nSee you at the"), line: "See you at the"))
        #expect(cut == String(english.suffix(Self.limit - 1)) + "\n", "\(cut.debugDescription)")
        // Only the most recent one is cut: an earlier one that doesn't fit is left out whole.
        let fitting = "我们见面了。"
        let both = try #require(Self.earlier(Self.sent(long + fitting + "\n" + line), line: line))
        #expect(both == fitting + "\n", "\(both.debugDescription)")
    }

    /// The text before the caret is still looked at only as far back as `beforeLimit`.
    @Test func noFurtherBackThanBeforeLimit() throws {
        let before = "Old news here.\n" + String(repeating: "这是很长的一段中文。", count: 160) + "\nSee you at the"
        #expect(Self.sent(before) == "See you at the")
    }

    // MARK: - Where text was left out

    /// A single line break where sentences of another pool were left out, so the model doesn't glue two sentences that
    /// weren't next to each other; what is between two that were, as it is.
    @Test func aLineBreakWhereTextWasSkipped() throws {
        #expect(Self.sent("Good morning team. 会议改到明天。 Please bring the slides.\nThanks for coming")
            == "Good morning team.\nPlease bring the slides.\nThanks for coming")
        // However much was left out, and the blank lines around it: one line break.
        #expect(Self.sent("Dear team,\n\n我们今天开会。\n\n今天的议程。\n\nThe meeting moved to") == "Dear team,\nThe meeting moved to")
        // Next to each other: the spaces and line breaks between them as they were.
        #expect(Self.sent("Hi Ann,\n\nThanks a lot.  See you.\n\n\nThe meeting moved to") == "Hi Ann,\n\nThanks a lot.  See you.\n\n\nThe meeting moved to")
        // A sentence ends at . ! ? before a space, and at 。！？ anywhere; "3.5" and "example.com" go on.
        #expect(Self.sent("It costs 3.5 dollars at example.com today!会议改到明天。Right?\nSee you at the")
            == "It costs 3.5 dollars at example.com today!\nRight?\nSee you at the")
        // Text with no letters (a date, a number) is of no language: it goes with any.
        #expect(Self.sent("Meeting notes\n2026-10-23\n我们今天开会。\nWe talked about") == "Meeting notes\n2026-10-23\nWe talked about")
    }

    // MARK: - What the request does with it

    /// The request: the examples and the space at the start by the caret's line as before; the text the pool's.
    @Test func theRequestSendsThePoolWithTheLinesExamples() throws {
        let before = Self.chineseParagraph + "\n\nI have an appointment today, "
        let request = Prompt.autocompleteRequest(Autocomplete.Context(before: before), app: "com.apple.Notes", onDevice: true)
        #expect(request.messages.filter { $0.role == "assistant" }.map { $0.content[0].text }
            == Prompt.autocompleteEnglishExamples.map { String($0.answer.drop { $0 == " " }) })
        #expect(request.system[0].text.contains("Never start with a space"))
        #expect(request.messages.last?.content[0].text == "<before>I have an appointment today, </before>")
        // The text after the caret as before.
        let after = Prompt.autocompleteRequest(Autocomplete.Context(before: before, after: "\nCheers,"), app: nil)
        #expect(after.messages.last?.content[0].text == "<before>I have an appointment today, </before>\n<after>\nCheers,</after>")
    }

    /// AC-13 still goes by all of the text before the caret, not only what was sent: a sentence copied from another pool's
    /// part of it, or from further back than the 200 characters, is still a copy.
    @Test(.bug(id: "AC-13", "a sentence already in the text before the caret is shown again"))
    func aCopyFromAnotherPoolIsStillACopy() async throws {
        func ask(_ before: String, answer: String) async throws -> (shown: String?, prompt: String?) {
            let model = ContinuingModel { _ in answer }
            var config = Config.default
            config.provider = .apple
            let fixed = config
            let converter = Converter(loadConfig: { fixed }, loadJargon: { _ in [] }, appleModel: model)
            let result = try await converter.autocomplete(Autocomplete.Context(before: before), app: nil)
            return (result.text, model.requests.first?.prompt)
        }
        // English copied on a Chinese line: the English wasn't sent.
        let english = try await ask(Self.mail + "\n\n好的，我", answer: " I will review them and get back to you by Friday.")
        #expect(english.prompt == "<before>好的，我</before>")
        #expect(english.shown == nil, "AC-13: shown \(english.shown ?? "")")
        // Chinese copied on a Japanese line.
        let chinese = try await ask("图书馆有新书推荐。\nSee you.\n明日は図書館で", answer: "图书馆有新书推荐。")
        #expect(chinese.prompt == "<before>明日は図書館で</before>")
        #expect(chinese.shown == nil, "AC-13: shown \(chinese.shown ?? "")")
        // A sentence of the line's own language from further back than what was sent.
        let far = "图书馆有新书推荐。" + (1...12).map { "这是第\($0)句话，我们一起讨论项目的进度。" }.joined() + "\n然后我们"
        let back = try await ask(far, answer: "图书馆有新书推荐。")
        #expect(back.prompt.map { !$0.contains("图书馆") } == true)
        #expect(back.shown == nil, "AC-13: shown \(back.shown ?? "")")
        // Not a copy: shown.
        let fresh = try await ask(Self.mail + "\n\n好的，我", answer: "明天下午给你回复。")
        #expect(fresh.shown == "明天下午给你回复。")
    }

    /// A cloud provider gets the pool, the hidden words removed (hidden in all the text first, then sorted).
    @Test func theProviderGetsThePoolWithHiddenWordsRemoved() async throws {
        let host = "autocomplete-pools.test"
        StubURLProtocol.register(host: host, .init(status: 200, headers: ["Content-Type": "text/event-stream"],
                                                    chunks: AutocompleteTests.claudeEvents))
        var config = Config.default
        config.provider = .anthropic
        config.anthropic = ProviderSettings(baseURL: "https://\(host)")
        config.redaction = RedactionSettings(enabled: true)
        let before = "我们明天开会。\nPlease write to ann@example.com today.\n记得带伞。\nI will also cc"
        _ = try await AutocompleteTests.stubbed(config, model: ContinuingModel()).autocomplete(Autocomplete.Context(before: before), app: nil)
        let body = try AutocompleteTests.sent(to: host)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.last?["content"] as? String == "<before>Please write to [EMAIL_1] today.\nI will also cc</before>")
    }
}
