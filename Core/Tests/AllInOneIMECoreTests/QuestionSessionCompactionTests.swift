import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

/// An agent that begins compacting the conversation's context before it answers (`ClaudeSession.Event.compacting`)
/// isn't waited for: the question fails with `ClaudeSessionError.compacting` at once, the provider answers and the panel
/// says why, rather than after the 30-second first-answer timeout.
struct QuestionSessionCompactionTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("compaction-\(UUID().uuidString)")

    func event(_ text: String) -> ClaudeSession.Event { ClaudeSession.event(Data(text.utf8)) }

    func collect(_ stream: AsyncThrowingStream<String, Error>) async -> (answers: [String], error: Error?) {
        var answers: [String] = []
        do {
            for try await answer in stream { answers.append(answer) }
            return (answers, nil)
        } catch {
            return (answers, error)
        }
    }

    @Test func claudeCodesCompactionLinesAreRead() {
        #expect(event(#"{"type":"system","subtype":"compact_boundary","compact_metadata":{"trigger":"auto","pre_tokens":181203},"session_id":"s"}"#)
                == .compacting)
        #expect(event(#"{"type":"system","subtype":"status","status":"compacting","session_id":"s"}"#) == .compacting)
        #expect(event(#"{"type":"system","subtype":"status","status":null,"session_id":"s"}"#) == .other)
        #expect(event(#"{"type":"system","subtype":"init","session_id":"s"}"#) == .started)
    }

    @Test(TaskLanguage("en")) func compactingBeforeTheAnswerFallsBackAtOnceAndSaysWhy() async throws {
        let fake = FakeClaude()
        // A first-answer timeout far off: what ends the wait is the compaction, not the timeout.
        let session = ClaudeSessionManager(launcher: fake, store: ClaudeSessionStore(directory: folder),
                                           firstAnswerTimeout: .seconds(600), userSettings: { nil })
        defer { session.stop() }
        var config = Config.default
        config.provider = .apple
        config.questionBackend = .claudeSession
        let settings = config
        let converter = Converter(loadConfig: { settings }, appleModel: StubAppleModel(answer: ["From the provider."]),
                                  questionSessions: [.claude: session])
        let started = ContinuousClock.now
        let task = Task {
            var last: ConversionUpdate?
            for try await update in converter.generate(.question, input: "one more question") { last = update }
            return last
        }
        #expect(await Timing.eventually(within: 10) { fake.last?.messages.count == 1 })
        let process = try #require(fake.last)
        process.started()
        process.say(["type": "system", "subtype": "status", "status": "compacting"])
        let update = try await task.value
        #expect(ContinuousClock.now - started < .seconds(10))
        #expect(update?.result.versions.first?.text == "From the provider.")
        let note = try #require(update?.note)
        #expect(note == ClaudeSessionError.compacting.fallbackNote(for: .claude), "\(note)")
        // The turn stopped as Esc stops it; the process stays for the next question.
        #expect(process.interrupts == 1 && !process.terminated && session.isRunning)
    }

    @Test func compactingOnceTheAnswerCameGoesOn() async throws {
        let fake = FakeClaude()
        let session = ClaudeSessionManager(launcher: fake, store: ClaudeSessionStore(directory: folder), userSettings: { nil })
        defer { session.stop() }
        let stream = session.ask("a long one", in: nil)
        let process = try #require(fake.last)
        process.started()
        process.text("Part one.")
        process.say(["type": "system", "subtype": "compact_boundary", "compact_metadata": ["trigger": "auto"]])
        process.text(" Part two.")
        process.done()
        let (answers, error) = await collect(stream)
        #expect(error == nil && answers.last == "Part one. Part two." && process.interrupts == 0)
    }

    @Test func codexsCompactionFallsBack() async throws {
        for compaction in [["method": "thread/compacted", "params": ["threadId": "t1", "turnId": "turn_1"]] as [String: Any],
                           ["method": "item/started",
                            "params": ["threadId": "t1", "turnId": "turn_1", "item": ["type": "contextCompaction", "id": "c1"]]]] {
            let fake = FakeClaude()
            let session = ClaudeSessionManager(backend: CodexBackend(base: folder.appendingPathComponent(UUID().uuidString)), launcher: fake)
            defer { session.stop() }
            let stream = session.ask("hello", in: nil)
            let process = try #require(fake.last)
            func respond(_ method: String, _ result: [String: Any]) throws {
                let id = try #require(process.lines.last { $0["method"] as? String == method }?["id"])
                process.say(["id": id, "result": result])
            }
            try respond("initialize", ["userAgent": "test"])
            try respond("config/read", ["config": ["model": "gpt"]])
            try respond("thread/start", ["thread": ["id": "t1", "name": NSNull()]])
            try respond("turn/start", ["turn": ["id": "turn_1"]])
            process.say(compaction)
            let error = await collect(stream).error as? ClaudeSessionError
            #expect(error == .compacting, "\(compaction)")
            #expect(process.lines.contains { $0["method"] as? String == "turn/interrupt" })
        }
    }

    @Test func whatThePanelSays() async {
        await withInterfaceLanguage("en") {
            #expect(ClaudeSessionError.compacting.fallbackNote(for: .codex)
                    == "The Codex session is compacting the conversation; the AI provider answered this time")
        }
        await withInterfaceLanguage("zh-Hans") {
            #expect(ClaudeSessionError.compacting.fallbackNote(for: .claude) == "Claude 会话正在压缩对话，这次由 AI 服务回答")
        }
    }
}
