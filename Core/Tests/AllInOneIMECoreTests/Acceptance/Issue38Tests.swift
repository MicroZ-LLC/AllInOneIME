import Foundation
import Testing
@testable import AllInOneIMECore

// Issue #38: a Gemini reply cut off for RECITATION (or OTHER, LANGUAGE, …) is inserted and cached as complete. Gemini
// streams some text, then ends with `"finishReason": "RECITATION"`: the partial answer is offered as if it were whole,
// and the same request later gets the truncated text back from the cache. Expected: the answer is marked as cut off, or
// reported as an error, and is not cached. Only STOP is a normal end (and MAX_TOKENS the token limit, cut off as it is
// today). Asked as the user asks: `@question`, `@improve`/`@translate`, `@reply` and Translate as You Type, through the
// real `Converter` to a stubbed Gemini API (`StubURLProtocol`), each twice, so what reached the API is read back.

private enum Issue38 {
    /// The reasons Gemini stops early for that aren't the token limit or a refusal.
    static let cutOff = ["RECITATION", "OTHER", "LANGUAGE"]

    /// One `streamGenerateContent?alt=sse` chunk: `text` from the model, and its finish reason when given.
    static func chunk(_ text: String, finish: String? = nil) -> String {
        var candidate: [String: Any] = ["content": ["role": "model", "parts": [["text": text]]], "index": 0]
        if let finish { candidate["finishReason"] = finish }
        let object: [String: Any] = ["candidates": [candidate],
                                     "usageMetadata": ["promptTokenCount": 40, "candidatesTokenCount": 12]]
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// Gemini's answer to every request to `host`: `texts` in turn, the last one ending with `finish`.
    static func serve(_ host: String, _ texts: [String], finish: String) {
        let chunks = texts.enumerated().map { i, text in chunk(text, finish: i == texts.count - 1 ? finish : nil) }
        let sse = chunks.map { "data: \($0)\r\n\r\n" }.joined()
        StubURLProtocol.register(host: host, .init(status: 200, headers: ["Content-Type": "text/event-stream"],
                                                   chunks: [Data(sse.utf8)]))
    }

    /// A converter on the Gemini provider at `host`, with a key.
    static func converter(_ host: String) -> Converter {
        var config = Config.default
        config.provider = .gemini
        config.gemini.baseURL = "https://\(host)"
        config.rewriteStyles = []
        let fixed = config
        return Converter(client: BedrockClient(session: StubURLProtocol.session()), loadConfig: { fixed },
                         loadKey: { provider, _ in provider == .gemini ? "test-key" : nil })
    }

    /// The final update of a request, or the error it ended with.
    static func ask(_ stream: AsyncThrowingStream<ConversionUpdate, Error>) async -> Result<ConversionUpdate?, Error> {
        do {
            var final: ConversionUpdate?
            for try await update in stream where update.isFinal { final = update }
            return .success(final)
        } catch {
            return .failure(error)
        }
    }

    /// Whether the update is an answer from the cache.
    static func fromCache(_ result: Result<ConversionUpdate?, Error>) -> Bool {
        if case let .success(update?) = result { return update.fromCache }
        return false
    }

    /// What a request ended with, short: the text it got, or the error.
    static func describe(_ result: Result<ConversionUpdate?, Error>) -> String {
        switch result {
        case let .success(update): return update.map { "\($0.rawText.debugDescription), from cache: \($0.fromCache)" } ?? "no answer"
        case let .failure(error): return "\(error)"
        }
    }

    static func host(_ entry: String, _ reason: String) -> String { "issue38-\(entry)-\(reason.lowercased()).test" }
}

@Suite struct Issue38Tests {
    // MARK: The stream's events

    /// A chunk with text that ends for `reason` is not a normal end: it's reported as an error, or as cut off (the stop
    /// reason every caller treats as a cut-off answer, "max_tokens").
    @Test(arguments: Issue38.cutOff)
    func aChunkThatStopsEarlyIsNotANormalEnd(reason: String) {
        let payload = Issue38.chunk("The opening lines of the song go like", finish: reason)
        let events: [BedrockStreamEvent]
        do {
            events = try HTTPProviders.events(fromData: payload, provider: .gemini)
        } catch {
            return  // reported as an error: not inserted as a whole answer
        }
        #expect(events.last == .messageStop(reason: "max_tokens"),
                "\(reason) ends the answer as if it were whole: \(events)")
    }

    /// The control: STOP ends an answer normally, MAX_TOKENS at the token limit (as today).
    @Test func stopIsANormalEndAndMaxTokensTheLimit() throws {
        let stop = try HTTPProviders.events(fromData: Issue38.chunk("Done.", finish: "STOP"), provider: .gemini)
        #expect(stop.first == .textDelta("Done."))
        if case let .messageStop(reason)? = stop.last { #expect(reason != "max_tokens") } else { Issue.record("no stop: \(stop)") }
        let limit = try HTTPProviders.events(fromData: Issue38.chunk("Cut", finish: "MAX_TOKENS"), provider: .gemini)
        #expect(limit.last == .messageStop(reason: "max_tokens"))
    }

    // MARK: Asked as the user asks

    /// `@question`: the answer cut off for `reason` isn't kept; asking the same question again asks Gemini again.
    @Test(arguments: Issue38.cutOff)
    func aQuestionCutOffIsNotCached(reason: String) async throws {
        let host = Issue38.host("question", reason)
        Issue38.serve(host, ["The opening lines of the song are:\n", "Is this the real life? Is this just"], finish: reason)
        let converter = Issue38.converter(host)
        let first = await Issue38.ask(converter.generate(.question, input: "what are the lyrics of bohemian rhapsody"))
        let asked = StubURLProtocol.requests(host: host).count
        #expect(asked >= 1)
        let again = await Issue38.ask(converter.generate(.question, input: "what are the lyrics of bohemian rhapsody"))
        let cached = Issue38.fromCache(again)
        #expect(!cached, "the answer cut off for \(reason) came back from the cache")
        #expect(StubURLProtocol.requests(host: host).count > asked, "asked again, Gemini wasn't (\(reason)); first: \(Issue38.describe(first))")
    }

    /// `@improve`/`@translate`: the line Gemini was writing when it stopped for `reason` isn't offered as a finished
    /// candidate, and the result isn't cached.
    @Test(arguments: Issue38.cutOff)
    func aConversionCutOffIsNotCached(reason: String) async throws {
        let host = Issue38.host("convert", reason)
        Issue38.serve(host, ["EN: Thanks for all your help.\n", "EN: You worked so"], finish: reason)
        let converter = Issue38.converter(host)
        let first = await Issue38.ask(converter.convert("辛苦了"))
        if case let .success(update?) = first {
            #expect(!update.result.versions.contains { $0.text == "You worked so" && $0.isComplete },
                    "the line cut off for \(reason) is offered as finished: \(update.result.versions)")
        }
        let asked = StubURLProtocol.requests(host: host).count
        #expect(asked >= 1)
        let again = await Issue38.ask(converter.convert("辛苦了"))
        let cached = Issue38.fromCache(again)
        #expect(!cached, "the result cut off for \(reason) came back from the cache")
        #expect(StubURLProtocol.requests(host: host).count > asked, "asked again, Gemini wasn't (\(reason)); first: \(Issue38.describe(first))")
    }

    /// `@reply`: replies cut off for `reason` aren't cached.
    @Test(arguments: Issue38.cutOff)
    func repliesCutOffAreNotCached(reason: String) async throws {
        let host = Issue38.host("reply", reason)
        Issue38.serve(host, ["Sounds good, see you then!\n---\n", "Thanks for letting me"], finish: reason)
        let converter = Issue38.converter(host)
        let first = await Issue38.ask(converter.generate(.reply, input: "Can we meet at 3pm tomorrow?"))
        let asked = StubURLProtocol.requests(host: host).count
        #expect(asked >= 1)
        let again = await Issue38.ask(converter.generate(.reply, input: "Can we meet at 3pm tomorrow?"))
        let cached = Issue38.fromCache(again)
        #expect(!cached, "the replies cut off for \(reason) came back from the cache")
        #expect(StubURLProtocol.requests(host: host).count > asked, "asked again, Gemini wasn't (\(reason)); first: \(Issue38.describe(first))")
    }

    /// Translate as You Type: a translation cut off for `reason` isn't cached.
    @Test(arguments: Issue38.cutOff)
    func aTranslationAsYouTypeCutOffIsNotCached(reason: String) async throws {
        let host = Issue38.host("translatemode", reason)
        Issue38.serve(host, ["EN: Thank you for all", " your hard"], finish: reason)
        let converter = Issue38.converter(host)
        let first = await Issue38.ask(converter.translateMode("感谢你的辛苦付出", target: .english))
        let asked = StubURLProtocol.requests(host: host).count
        #expect(asked >= 1)
        let again = await Issue38.ask(converter.translateMode("感谢你的辛苦付出", target: .english))
        let cached = Issue38.fromCache(again)
        #expect(!cached, "the translation cut off for \(reason) came back from the cache")
        #expect(StubURLProtocol.requests(host: host).count > asked, "asked again, Gemini wasn't (\(reason)); first: \(Issue38.describe(first))")
    }

    /// The control: the same answers ended with STOP are whole, and asked again they come from the cache.
    @Test func answersEndedWithStopAreCached() async throws {
        let question = Issue38.host("question", "STOP")
        Issue38.serve(question, ["The opening lines of the song are:\n", "Is this the real life?"], finish: "STOP")
        let questions = Issue38.converter(question)
        _ = await Issue38.ask(questions.generate(.question, input: "what are the lyrics of bohemian rhapsody"))
        let asked = await Issue38.ask(questions.generate(.question, input: "what are the lyrics of bohemian rhapsody"))
        #expect(Issue38.fromCache(asked), "\(Issue38.describe(asked))")
        #expect(StubURLProtocol.requests(host: question).count == 1)

        let convert = Issue38.host("convert", "STOP")
        Issue38.serve(convert, ["EN: Thanks for all your help.\n", "EN: You worked so hard."], finish: "STOP")
        let converter = Issue38.converter(convert)
        let first = await Issue38.ask(converter.convert("辛苦了"))
        if case let .success(update?) = first {
            #expect(update.result.versions.map(\.text) == ["Thanks for all your help.", "You worked so hard."])
        } else {
            Issue.record("\(Issue38.describe(first))")
        }
        let again = await Issue38.ask(converter.convert("辛苦了"))
        #expect(Issue38.fromCache(again), "\(Issue38.describe(again))")
        #expect(StubURLProtocol.requests(host: convert).count == 1)
    }
}
