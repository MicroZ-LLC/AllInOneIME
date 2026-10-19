import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The work a session starts that answers later (`SessionTasks`): what it delivers, in order; what a newer one in its slot
/// stops; what is waited for while it's typed. Nothing here reaches a network or a model: the streams are the tests' own.
@Suite(.serialized)
struct SessionTasksTests {
    /// What the tasks delivered, as the shell gets it (on any thread).
    final class Inbox: @unchecked Sendable {
        private let events = Locked<[SessionEvent]>(initialState: [])
        var all: [SessionEvent] { events.withLock { $0 } }
        func deliver(_ event: SessionEvent) { events.withLock { $0.append(event) } }

        /// The updates of the work that still counts for `tasks`, as the session would take them.
        func updates(counting tasks: SessionTasks) -> [TaskUpdate] {
            all.compactMap { event in
                guard case let .task(id, update) = event, tasks.isCurrent(id) else { return nil }
                return update
            }
        }
    }

    func update(_ text: String, final: Bool) -> ConversionUpdate {
        ConversionUpdate(result: ConversionResult(versions: [CandidateLine(text)]), rawText: text, isFinal: final, elapsed: 0.5,
                         firstTokenLatency: nil, fromCache: false)
    }

    func texts(_ updates: [TaskUpdate]) -> [String] {
        updates.compactMap { if case let .converted(update, _) = $0 { update.result.versions.first?.text } else { nil } }
    }

    @Test func aStreamIsDeliveredInOrderThenItsError() async {
        let inbox = Inbox()
        let tasks = SessionTasks(deliver: inbox.deliver)
        let (stream, continuation) = AsyncThrowingStream<ConversionUpdate, Error>.makeStream()
        tasks.consume(stream, id: 7)
        continuation.yield(update("Hel", final: false))
        continuation.yield(update("Hello", final: true))
        continuation.finish(throwing: DescribedError(message: "it broke"))
        #expect(await Timing.eventually { inbox.all.count == 3 })
        let updates = inbox.updates(counting: tasks)
        #expect(texts(updates) == ["Hel", "Hello"])
        guard case let .failed(error, request) = updates.last else { Issue.record("no failure: \(updates)"); return }
        #expect(request == 7 && (error as? DescribedError)?.message == "it broke")
    }

    @Test func aNewerRequestStopsTheOneBefore() async {
        let inbox = Inbox()
        let tasks = SessionTasks(deliver: inbox.deliver)
        let (first, firstContinuation) = AsyncThrowingStream<ConversionUpdate, Error>.makeStream()
        tasks.consume(first, id: 1)
        firstContinuation.yield(update("old", final: false))
        #expect(await Timing.eventually { inbox.all.count == 1 })
        let (second, secondContinuation) = AsyncThrowingStream<ConversionUpdate, Error>.makeStream()
        tasks.consume(second, id: 2)
        firstContinuation.yield(update("old again", final: true))
        secondContinuation.yield(update("new", final: true))
        secondContinuation.finish()
        #expect(await Timing.eventually { texts(inbox.updates(counting: tasks)) == ["new"] })
        tasks.cancel(.request)
        #expect(inbox.updates(counting: tasks).isEmpty, "once stopped, nothing of it counts")
    }

    @Test func aProgramsOutputGoesIntoATerminalOnOneLine() async throws {
        var services = SessionServices()
        services.runProgram = { _, _ in
            AsyncThrowingStream { $0.yield(ConversionUpdate(result: ConversionResult(versions: [CandidateLine("a\nb")]), rawText: "a\nb",
                                                            isFinal: true, elapsed: 0, firstTokenLatency: nil, fromCache: false))
                $0.finish() }
        }
        let run = Command.catalog([CustomCommand(name: "lines", type: .run, argv: ["/bin/echo"])]).first { $0.name == "lines" }
        let command = try #require(run)
        func output(terminal: Bool) async throws -> String? {
            let place = SessionTasks.Place(app: nil, terminal: terminal, pastesInTerminal: false, improveTranslates: false,
                                           pluginLanguage: .english)
            var text: String?
            for try await update in SessionTasks.stream(for: .init(input: "x", command: command), in: place, services: services) {
                text = update.result.versions.first?.text
            }
            return text
        }
        #expect(try await output(terminal: false) == "a\nb")
        #expect(try await output(terminal: true) == "a b")
    }

    @Test func openIsSearchedAsTypedOnceItStopsChanging() async {
        let inbox = Inbox()
        let tasks = SessionTasks(deliver: inbox.deliver)
        let searched = Locked<[String]>(initialState: [])
        let search: @Sendable (String, OpenHistory) async -> [SearchResult] = { query, _ in
            searched.withLock { $0.append(query) }
            return [SearchResult(name: query, path: "/tmp/" + query)]
        }
        tasks.searchAsTyped("n", history: { OpenHistory() }, with: search)  // one letter: only ⏎ searches it
        tasks.searchAsTyped("no", history: { OpenHistory() }, with: search)
        tasks.searchAsTyped("not", history: { OpenHistory() }, with: search)
        tasks.searchAsTyped("not", history: { OpenHistory() }, with: search)  // the same text: not again
        #expect(await Timing.eventually { !inbox.all.isEmpty })
        try? await Task.sleep(for: .milliseconds(300))
        #expect(searched.withLock { $0 } == ["not"])
        guard case let .live(results, query)? = inbox.updates(counting: tasks).first else { Issue.record("\(inbox.all)"); return }
        #expect(query == "not" && results.map(\.name) == ["not"])
    }

    @Test func recipientsWithoutTheAddressBookSaySo() async {
        let inbox = Inbox()
        let tasks = SessionTasks(deliver: inbox.deliver)
        withInterfaceLanguage("en") {
            tasks.findRecipients("+15550199", recent: { [] }, contacts: { nil })
        }
        #expect(await Timing.eventually { !inbox.all.isEmpty })
        guard case let .recipients(found, note, query)? = inbox.updates(counting: tasks).first else { Issue.record("\(inbox.all)"); return }
        #expect(query == "+15550199" && found.first?.handle == "+15550199")
        #expect(note?.hasPrefix("No access to Contacts") == true, "\(note ?? "-")")
    }

    @Test func aMissingPreferenceKeepsAScriptFromRunning() async {
        let folder = URL(fileURLWithPath: "/tmp/greeter", isDirectory: true)
        let script = ScriptCommand(source: .bundle("greeter"), file: folder.appendingPathComponent("greet.sh"), name: "greet")
        let bundle = ExtensionBundle(folder: folder, name: "greeter", title: "Greeter",
                                     preferences: [.init(name: "token", title: "Token", required: true)])
        let context = ScriptContext(language: "en", inputLanguage: "en", app: nil, query: "")
        let make = withInterfaceLanguage("en") {
            SessionTasks.environmentMaker(script, bundle: bundle, config: .default, context: context, preferences: { _, _ in [:] })
        }
        let missing = await make()
        let set = await SessionTasks.environmentMaker(script, bundle: bundle, config: .default, context: context,
                                                      preferences: { _, _ in ["token": "t"] })()
        withInterfaceLanguage("en") {
            guard case let .failure(error) = missing else { Issue.record("it would run"); return }
            #expect(error.message == "Set “Token” for Greeter in the settings first")
        }
        guard case let .success(environment) = set else { Issue.record("it wouldn't run"); return }
        #expect(environment["ALLINONEIME_PREF_TOKEN"] == "t" && environment["ALLINONEIME_LANGUAGE"] == "en")
    }
}
