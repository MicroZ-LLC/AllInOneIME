import AllInOneIMETestSupport
import Foundation
import Testing
@testable import AllInOneIMECore

/// The session where Claude Code is set up for a provider other than a Claude subscription (Amazon Bedrock …): the
/// user's provider settings passed with `--settings`, AWS credential errors, no answer in time; and what one long session
/// needs across questions: placeholders that never stand for two values, rounds it didn't see told once.
struct ClaudeSessionProviderTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("claude-provider-\(UUID().uuidString)")
    var folder: URL { root.appendingPathComponent("session") }
    var store: ClaudeSessionStore { ClaudeSessionStore(directory: folder) }
    var userFile: URL { root.appendingPathComponent("config/settings.json") }

    func manager(_ fake: FakeClaude, answerClock: any Clock<Duration> = ContinuousClock(),
                 userSettings: URL? = nil) -> ClaudeSessionManager {
        ClaudeSessionManager(launcher: fake, store: store, answerClock: answerClock, userSettings: { userSettings })
    }

    func writeUserSettings(_ object: [String: Any]) throws {
        try FileManager.default.createDirectory(at: userFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: userFile)
    }

    func collect(_ stream: AsyncThrowingStream<String, Error>) async -> (answers: [String], error: Error?) {
        var answers: [String] = []
        do {
            for try await answer in stream { answers.append(answer) }
            return (answers, nil)
        } catch {
            return (answers, error)
        }
    }

    func answer(_ process: FakeClaude.Process, _ text: String) {
        process.started()
        process.messageStarted()
        process.text(text)
        process.done(text)
    }

    /// Claude Code's failed turn: an `assistant` line with `code`, then the `result`, both saying `text`.
    func fail(_ process: FakeClaude.Process, code: String, _ text: String, status: Int? = nil) {
        process.started()
        process.say(["type": "assistant", "error": code, "message": ["content": [["type": "text", "text": text]]]])
        var result: [String: Any] = ["type": "result", "subtype": "success", "is_error": true, "result": text, "terminal_reason": "api_error"]
        if let status { result["api_error_status"] = status }
        process.say(result)
    }

    func converter(_ session: ClaudeSessionManager, redaction: Bool = false, provider: String = "From the provider.")
        -> (Converter, StubAppleModel) {
        var settings = Config.default
        settings.provider = .apple
        settings.questionBackend = .claudeSession
        if redaction { settings.redaction = RedactionSettings(enabled: true) }
        let config = settings
        let apple = StubAppleModel(answer: [provider])
        return (Converter(loadConfig: { config }, appleModel: apple, claudeSession: session), apple)
    }

    func final(_ stream: AsyncThrowingStream<ConversionUpdate, Error>) async throws -> ConversionUpdate? {
        var last: ConversionUpdate?
        for try await update in stream { last = update }
        return last
    }

    func turn(_ answer: String, _ instruction: String) -> Refinement.Turn {
        Refinement.Turn(answer: ConversionResult(versions: [CandidateLine(answer)]), instruction: instruction)
    }

    // MARK: - The provider's settings

    @Test func onlyTheProviderKeysOfTheUserSettingsAreKept() throws {
        let user: [String: Any] = [
            "env": ["CLAUDE_CODE_USE_BEDROCK": "1", "AWS_PROFILE": "work", "AWS_REGION": "us-west-2"],
            "awsAuthRefresh": "aws sso login --profile work", "awsCredentialExport": "/u/export.sh", "apiKeyHelper": "/u/key.sh",
            "model": "us.anthropic.claude-sonnet-4-5", "modelOverrides": ["claude-opus-4-6": "arn:aws:bedrock:x"],
            "hooks": ["Stop": []], "permissions": ["allow": ["Bash"]], "statusLine": ["type": "command"],
            "enabledPlugins": ["x": true], "enableAllProjectMcpServers": true, "theme": "dark",
        ]
        let kept = try #require(ClaudeSession.providerSettings(try JSONSerialization.data(withJSONObject: user)))
        let object = try #require(try JSONSerialization.jsonObject(with: kept) as? [String: Any])
        #expect(Set(object.keys) == ["env", "awsAuthRefresh", "awsCredentialExport", "apiKeyHelper", "model", "modelOverrides"])
        #expect((object["env"] as? [String: String])?["AWS_PROFILE"] == "work")
        // None of them (an empty env counts as none), or not settings at all: nothing.
        #expect(ClaudeSession.providerSettings(Data(#"{"env":{},"hooks":{},"theme":"dark"}"#.utf8)) == nil)
        #expect(ClaudeSession.providerSettings(Data("not json".utf8)) == nil)
        #expect(ClaudeSession.providerSettings(Data("[1]".utf8)) == nil)
        // Where the user's settings are.
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(ClaudeSession.userSettingsFile(environment: [:], home: home).path == "/Users/someone/.claude/settings.json")
        #expect(ClaudeSession.userSettingsFile(environment: ["CLAUDE_CONFIG_DIR": "/etc/cc"], home: home).path == "/etc/cc/settings.json")
        #expect(ClaudeSession.userSettingsFile(environment: ["CLAUDE_CONFIG_DIR": ""], home: home).path == "/Users/someone/.claude/settings.json")
    }

    @Test func theFlagsWithSettings() {
        let id = "8d6a1f6e-0d2c-4c4e-9a43-0c1a2b3c4d5e"
        let file = URL(fileURLWithPath: "/s/provider-settings.json")
        let args = ClaudeSession.arguments(sessionID: id, resume: true, settings: file)
        #expect(Array(args.suffix(5)) == ["--setting-sources", "project", "--settings", "/s/provider-settings.json", "--strict-mcp-config"])
        #expect(ClaudeSession.authStatusArguments(settings: file)
                == ["--setting-sources", "project", "--settings", "/s/provider-settings.json", "auth", "status", "--json"])
        #expect(ClaudeSession.authStatusArguments() == ["--setting-sources", "project", "auth", "status", "--json"])
    }

    @Test func eachStartGetsTheProviderSettingsAsTheyAreNow() async throws {
        try writeUserSettings(["env": ["CLAUDE_CODE_USE_BEDROCK": "1", "AWS_PROFILE": "work"], "awsAuthRefresh": "aws sso login",
                               "hooks": ["Stop": []], "permissions": ["allow": ["Bash"]]])
        let fake = FakeClaude()
        let session = manager(fake, userSettings: userFile)
        let stream = session.ask("hi", in: nil)
        let process = try #require(fake.last)
        let written = folder.appendingPathComponent("provider-settings.json")
        let at = try #require(process.arguments.firstIndex(of: "--settings"))
        #expect(process.arguments[at + 1] == written.path && process.arguments[at - 2] == "--setting-sources")
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: written)) as? [String: Any])
        #expect(Set(object.keys) == ["env", "awsAuthRefresh"])
        let mode = try FileManager.default.attributesOfItem(atPath: written.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        #expect(session.authStatusArguments() == ["--setting-sources", "project", "--settings", written.path, "auth", "status", "--json"])
        answer(process, "hello")
        _ = await collect(stream)

        // Bedrock taken out of the user's settings: the next start has no --settings, and the file goes.
        try writeUserSettings(["hooks": ["Stop": []]])
        session.stop()
        _ = session.ask("again", in: nil)
        #expect(fake.processes.count == 2 && fake.last?.arguments.contains("--settings") == false)
        #expect(!FileManager.default.fileExists(atPath: written.path))
        // No user settings at all (none there, or none given).
        try FileManager.default.removeItem(at: userFile)
        #expect(session.authStatusArguments() == ["--setting-sources", "project", "auth", "status", "--json"])
    }

    @Test func aFolderWithTheEarlierInstructionsGetsTheNewOnesAnEditedOneStays() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("CLAUDE.md")
        try Data(ClaudeSession.earlierInstructions[0].utf8).write(to: file)
        try store.prepare()
        let now = try String(contentsOf: file, encoding: .utf8)
        #expect(now == ClaudeSession.instructions && !now.contains("WebSearch") && now.contains("when you have a tool for it"))
        // Instructions, not what keeps it to its tools (its flags do): the user's own stay.
        try Data("My own.".utf8).write(to: file)
        try store.prepare()
        #expect(try String(contentsOf: file, encoding: .utf8) == "My own.")
    }

    // MARK: - Errors

    @Test func awsCredentialErrorsSayToSignInToAWSAndFallBack() {
        func error(_ code: String?, _ status: Int?, _ message: String) -> ClaudeSessionError {
            ClaudeSessionError.from(code: code, status: status, message: message)
        }
        #expect(error(nil, 403, "API Error: 403 The security token included in the request is expired") == .awsSignInExpired)
        #expect(error("authentication_failed", nil, "ExpiredTokenException: The security token included in the request is expired") == .awsSignInExpired)
        #expect(error(nil, 400, "API Error: 400 UnrecognizedClientException: The security token included in the request is invalid.") == .awsSignInExpired)
        #expect(error(nil, nil, "CredentialsProviderError: Could not load credentials from any providers") == .awsSignInExpired)
        #expect(error(nil, nil, "Error loading SSO Token: Token for work does not exist") == .awsSignInExpired)
        #expect(error(nil, nil, "The SSO session associated with this profile has expired or is otherwise invalid. To refresh this SSO session run aws sso login") == .awsSignInExpired)
        // Bedrock's other errors as before: the account's access isn't a sign-in.
        let denied = "API Error: 400 Error 002: Access to Bedrock models is not allowed for this account"
        #expect(error(nil, 400, denied) == .failed(denied))
        #expect(error("authentication_failed", nil, "Not logged in · Please run /login") == .signedOut)
        #expect(ClaudeSessionError.awsSignInExpired.errorDescription?.contains("aws sso login") == true)
    }

    @Test func anExpiredAWSSignInFailsTheTurnWithoutSigningTheSessionOut() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let stream = session.ask("hi", in: nil)
        let process = try #require(fake.last)
        // The error line says little, the result says what it was.
        process.started()
        process.say(["type": "assistant", "error": "authentication_failed", "message": ["content": [["type": "text", "text": "Please run /login"]]]])
        process.say(["type": "result", "subtype": "success", "is_error": true, "api_error_status": 403,
                     "result": "API Error: 403 The security token included in the request is expired"])
        #expect(await collect(stream).error as? ClaudeSessionError == .awsSignInExpired)
        #expect(session.availability != .signedOut)  // the next question tries again (after aws sso login)

        // Claude Code can't get credentials at all (awsCredentialExport failed): it ends before the session starts.
        session.stop()
        let next = session.ask("again", in: nil)
        try #require(fake.last).exit(1, "CredentialsProviderError: Could not load credentials from any providers")
        try #require(fake.last).exit(1, "CredentialsProviderError: Could not load credentials from any providers")
        #expect(await collect(next).error as? ClaudeSessionError == .awsSignInExpired)
    }

    @Test func theProviderAnswersWhenTheAWSSignInExpired() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let (converter, apple) = converter(session)
        let stream = converter.generate(.question, input: "what is rust")
        #expect(await Timing.eventually { fake.last?.messages.count == 1 })
        fail(try #require(fake.last), code: "unknown", "API Error: 403 ExpiredToken: The security token included in the request is expired", status: 403)
        let last = try await final(stream)
        #expect(last?.result.versions.first?.text == "From the provider." && apple.requests.count == 1)
        #expect(last?.note == ClaudeSessionError.awsSignInExpired.fallbackNote)
    }

    @Test func anErrorBeforeTextFallsBackButAnErrorAfterTextDoesNot() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let (converter, apple) = converter(session)
        let first = converter.generate(.question, input: "first")
        #expect(await Timing.eventually { fake.last?.messages.count == 1 })
        fail(try #require(fake.last), code: "unknown", "Network failed")
        let fallback = try await final(first)
        #expect(fallback?.result.versions.first?.text == "From the provider.")
        #expect(fallback?.note?.contains("Network failed") == true && apple.requests.count == 1)

        let second = converter.generate(.question, input: "second")
        #expect(await Timing.eventually { fake.last?.messages.count == 2 })
        let process = try #require(fake.last)
        process.started()
        process.text("Partial")
        process.say(["type": "result", "subtype": "error_during_execution", "is_error": true, "result": "Network failed"])
        do {
            _ = try await final(second)
            Issue.record("Expected the partial answer's error")
        } catch {
            #expect((error as? DescribedError) != nil)
        }
        #expect(apple.requests.count == 1)
    }

    /// Whatever the session failed with, the provider answers while none of the answer came: a crash too, its note
    /// saying so; once some of it came, the question fails saying why, and the provider isn't asked.
    @Test func aCrashBeforeAnyTextFallsBackAndOneAfterSaysWhy() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let (converter, apple) = converter(session)
        let crash = ClaudeSessionError.exited(134, "Segmentation fault")
        let first = converter.generate(.question, input: "first")
        #expect(await Timing.eventually { fake.last?.messages.count == 1 })
        let one = try #require(fake.last)
        one.started()
        one.exit(134, "Segmentation fault")
        let fallback = try await final(first)
        #expect(fallback?.result.versions.first?.text == "From the provider." && apple.requests.count == 1)
        #expect(fallback?.note == crash.fallbackNote(for: .claude))

        let second = converter.generate(.question, input: "second")
        #expect(await Timing.eventually { fake.processes.count == 2 && fake.last?.messages.count == 1 })
        let two = try #require(fake.last)
        two.started()
        two.text("Half")
        two.exit(134, "Segmentation fault")
        do {
            _ = try await final(second)
            Issue.record("the partial answer's crash was not said")
        } catch {
            #expect((error as? DescribedError)?.message == crash.description(for: .claude), "\(error)")
        }
        #expect(apple.requests.count == 1)
    }

    // MARK: - No answer in time

    @Test func noSignOfAnAnswerInTimeEndsTheProcessAndFallsBack() async throws {
        let fake = FakeClaude()
        let clock = ManualClock()
        let session = manager(fake, answerClock: clock)
        let stream = session.ask("hi", in: nil)
        let stuck = try #require(fake.last)
        stuck.started()  // and then nothing (a sign-in waiting in a browser)
        #expect(await clock.sleepers(1))
        clock.advance(by: .seconds(29))
        #expect(!stuck.terminated)
        clock.advance(by: .seconds(1))
        let got = await collect(stream)
        #expect(got.error as? ClaudeSessionError == .noResponse)
        #expect(stuck.terminated && !session.isRunning)
        stuck.exit(15)  // of no session now

        // The next question starts it again; once the model's message started, a long answer (a web search) is no timeout.
        let next = session.ask("again", in: nil)
        let process = try #require(fake.last)
        #expect(fake.processes.count == 2 && process.messages == ["again"])
        process.started()
        process.messageStarted()
        clock.advance(by: .seconds(120))
        #expect(!process.terminated)
        process.text("Here.")
        process.done("Here.")
        #expect(await collect(next).answers == ["Here."])
    }

    @Test func aQuestionWaitingBehindAStuckOneGetsItsOwnTime() async throws {
        let fake = FakeClaude()
        let clock = ManualClock()
        let session = manager(fake, answerClock: clock)
        let first = session.ask("one", in: nil)
        let second = session.ask("two", in: nil)
        #expect(await clock.sleepers(1))
        clock.advance(by: .seconds(30))
        #expect(await collect(first).error as? ClaudeSessionError == .noResponse)
        // The waiting one went to a new process.
        #expect(await Timing.eventually { fake.processes.count == 2 && fake.last?.messages == ["two"] })
        let process = try #require(fake.last)
        answer(process, "2")
        #expect(await collect(second).answers == ["2"])
    }

    // MARK: - One long session

    @Test func placeholdersAreNumberedAcrossTheSessionUntilStartOver() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let (converter, _) = converter(session, redaction: true)

        let one = converter.generate(.question, input: "write to ann@example.com")
        #expect(await Timing.eventually { fake.last?.messages.count == 1 })
        let process = try #require(fake.last)
        #expect(process.messages[0].hasPrefix("write to [EMAIL_1]") && !process.messages[0].contains("ann@"))
        answer(process, "Sent to [EMAIL_1].")
        #expect(try await final(one)?.result.versions.first?.text == "Sent to ann@example.com.")

        // Another question (a new conversation): a new value gets a new number, a known one keeps its own.
        let two = converter.generate(.question, input: "bob@example.org and ann@example.com")
        #expect(await Timing.eventually { process.messages.count == 2 })
        #expect(process.messages[1].hasPrefix("[EMAIL_2] and [EMAIL_1]"))
        answer(process, "[EMAIL_2] then [EMAIL_1]")
        #expect(try await final(two)?.result.versions.first?.text == "bob@example.org then ann@example.com")

        // The input method restarted: the numbers go on (the values were in memory only).
        let restarted = manager(fake)
        let (again, _) = self.converter(restarted, redaction: true)
        let three = again.generate(.question, input: "cat@example.net")
        #expect(await Timing.eventually { fake.processes.count == 2 && fake.last?.messages.count == 1 })
        let second = try #require(fake.last)
        #expect(second.messages[0].hasPrefix("[EMAIL_3]"))
        answer(second, "Hi [EMAIL_3]")
        #expect(try await final(three)?.result.versions.first?.text == "Hi cat@example.net")

        // Start over: a new session, numbered from 1.
        try restarted.startOver()
        let four = again.generate(.question, input: "dan@example.com")
        #expect(await Timing.eventually { fake.processes.count == 3 && fake.last?.messages.count == 1 })
        #expect(try #require(fake.last).messages[0].hasPrefix("[EMAIL_1]"))
        answer(try #require(fake.last), "ok [EMAIL_1]")
        #expect(try await final(four)?.result.versions.first?.text == "ok dan@example.com")
    }

    @Test func roundsTheSessionDidntSeeAreToldOnce() async throws {
        let fake = FakeClaude()
        fake.missing = true  // the first answer is the provider's
        let session = manager(fake)
        let (converter, _) = converter(session)
        let first = try await final(converter.generate(.question, input: "what is rust"))
        #expect(first?.result.versions.first?.text == "From the provider." && first?.note != nil)

        fake.missing = false
        var turns = [turn("From the provider.", "and go?")]
        let two = converter.generate(.question, input: "what is rust", turns: turns)
        #expect(await Timing.eventually { fake.last?.messages.count == 1 })
        let process = try #require(fake.last)
        let told = ClaudeSession.message("and go?", after: [QuestionChat.Round(question: "what is rust", answer: "From the provider.")])
        #expect(process.messages[0] == told && told.contains("From the provider.") && told.hasSuffix("\nand go?"))
        answer(process, "Go is simpler.")
        #expect(try await final(two)?.result.versions.first?.text == "Go is simpler.")

        // The next question: the session has all of it now, only the question goes.
        turns.append(turn("Go is simpler.", "which is faster?"))
        let three = converter.generate(.question, input: "what is rust", turns: turns)
        #expect(await Timing.eventually { process.messages.count == 2 })
        #expect(process.messages[1] == "which is faster?")
        answer(process, "Rust.")
        _ = try await final(three)

        // A conversation from the saved history whose rounds the session answered in an earlier run, and one it never saw.
        let restarted = manager(fake)
        let (again, _) = self.converter(restarted)
        let saved = [turn("Go is simpler.", "x"), turn("Rust.", "y"), turn("An answer from elsewhere.", "and now?")]
        let four = again.generate(.question, input: "what is rust", turns: saved)
        #expect(await Timing.eventually { fake.processes.count == 2 && fake.last?.messages.count == 1 })
        #expect(try #require(fake.last).messages[0]
                == ClaudeSession.message("and now?", after: [
                    .init(question: "what is rust", answer: "Go is simpler."),
                    .init(question: "x", answer: "Rust."),
                    .init(question: "y", answer: "An answer from elsewhere.")]))
        answer(try #require(fake.last), "Now.")
        _ = try await final(four)
    }

    @Test func toldRoundsAreHiddenToo() async throws {
        let fake = FakeClaude()
        let session = manager(fake)
        let (converter, _) = converter(session, redaction: true)
        let turns = [turn("Mail ann@example.com about it.", "and the subject?")]
        let stream = converter.generate(.question, input: "who knows bob@example.org", turns: turns)
        #expect(await Timing.eventually { fake.last?.messages.count == 1 })
        let message = try #require(fake.last).messages[0]
        #expect(!message.contains("@example") && message.contains("[EMAIL_1]") && message.contains("[EMAIL_2]"))
        answer(try #require(fake.last), "Ask [EMAIL_2].")
        #expect(try await final(stream)?.result.versions.first?.text.hasSuffix("example.com.") == true)
    }
}
