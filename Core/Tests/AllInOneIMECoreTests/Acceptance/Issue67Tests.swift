import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// #67: in a Chinese interface, code inside another command's text that fails shows in English on the panel. Run on its
/// own, `@py` that runs too long says "运行超过 10 秒，已停止"; inside a text (`@question x @py 1`, `@reply 答案是 @py …`)
/// the panel says "@py：Stopped after 10 seconds". Printing too much and a non-zero exit without a message stay in
/// English the same way, for `@js` and a custom run command too. Expected: the wording it has on its own, after the
/// command's name ("@py："). The programs are stand-ins that fail as `CommandRunner` does (`SessionServices.runProgram`);
/// the failure stops the text before the outer command, so no model is asked.
@Suite(.serialized)
struct Issue67Tests {
    /// How a program fails, and what the panel says for it in Chinese when it runs on its own.
    enum Failure: String, CaseIterable, Sendable, CustomTestStringConvertible {
        /// Still running after 10 seconds (`import time; time.sleep(20)`).
        case timedOut
        /// Printed more than it may (64 KB).
        case tooMuchOutput
        /// Exited with status 2, printing nothing (`sys.exit(2)`).
        case silentExit
        var testDescription: String { rawValue }

        var error: CommandRunner.RunError {
            switch self {
            case .timedOut: return .timedOut(10)
            case .tooMuchOutput: return .tooMuchOutput
            case .silentExit: return .failed(status: 2, message: "")
            }
        }

        var chinese: String {
            switch self {
            case .timedOut: return "运行超过 10 秒，已停止"
            case .tooMuchOutput: return "输出太多，已停止"
            case .silentExit: return "程序出错（退出码 2）"
            }
        }

        /// The English it shows now inside a text.
        var english: String { error.errorDescription ?? "" }
    }

    /// A run command of the user's own.
    static let custom = CustomCommand(name: "lines", type: .run, argv: ["/bin/echo"])

    final class Settings: @unchecked Sendable {
        var config: Config
        init() {
            config = .default
            config.uiLanguage = "zh"
            config.setOrder([Language.chinese, .english])
            config.customCommands = [Issue67Tests.custom]
        }
    }

    /// Every program (`@py`, `@js`, the custom command) fails with `failure`; what runs is counted.
    static func failing(_ failure: Failure, ran: Locked<[String]>) -> @Sendable (CustomCommand, String) -> AsyncThrowingStream<ConversionUpdate, Error> {
        { command, _ in
            ran.withLock { $0.append(command.name) }
            return AsyncThrowingStream { $0.finish(throwing: failure.error) }
        }
    }

    /// A session in an editor that has the focus, its programs failing with `failure`.
    func host(failing failure: Failure, ran: Locked<[String]>) -> FakeHost {
        let settings = Settings()
        let engine = FakeEngine()
        var services = SessionServices(loadSettings: { settings.config })
        services.levelOne = { .engine(engine) }
        services.programInstalled = { _ in true }
        services.runProgram = Self.failing(failure, ran: ran)
        let host = FakeHost(services: services)
        host.focus()
        return host
    }

    /// Picks `letters`' command from the list ("@", its letters, Tab), types `input` in English and runs it (⏎): what
    /// the panel says once it failed, nil if it didn't.
    func failed(_ letters: String, _ input: String, in host: FakeHost) -> String? {
        host.composer.setInputMode(.english)
        host.press(FakeHost.at)
        host.type(letters)
        host.press(FakeHost.tab)
        host.type(input)
        host.press(FakeHost.enter)
        _ = host.settle { if case .failed = host.composer.phase { true } else { false } }
        guard case let .failed(message) = host.composer.phase else { return nil }
        return message
    }

    // MARK: - @py and @js inside a text

    /// The issue's: `@question x @py 1` that times out, prints too much or exits with 2 says it in Chinese, as `@py 1` on
    /// its own does, after "@py：".
    @Test(arguments: Failure.allCases)
    func innerPyFailsInTheInterfaceLanguage(_ failure: Failure) async {
        await withInterfaceLanguage("zh-Hans") {
            let ran = Locked<[String]>(initialState: [])
            let alone = failed("py", "1", in: host(failing: failure, ran: ran))
            #expect(alone == failure.chinese, "on its own: \(alone ?? "no failure")")
            let inside = failed("question", "x @py 1", in: host(failing: failure, ran: ran))
            #expect(ran.withLock { $0.count } == 2, "the code ran both times (\(ran.withLock { $0 }))")
            #expect(inside == "@py：" + failure.chinese, "inside @question's text: \(inside ?? "no failure")")
            #expect(inside?.contains(failure.english) != true, "not in English: \(inside ?? "no failure")")
        }
    }

    @Test(arguments: Failure.allCases)
    func innerJsFailsInTheInterfaceLanguage(_ failure: Failure) async {
        await withInterfaceLanguage("zh-Hans") {
            let ran = Locked<[String]>(initialState: [])
            let alone = failed("js", "1", in: host(failing: failure, ran: ran))
            #expect(alone == failure.chinese, "on its own: \(alone ?? "no failure")")
            let inside = failed("question", "x @js 1", in: host(failing: failure, ran: ran))
            #expect(inside == "@js：" + failure.chinese, "inside @question's text: \(inside ?? "no failure")")
        }
    }

    // MARK: - A custom run command inside a text

    /// A run command of the user's own whose program fails: its name, then what it says on its own, in Chinese.
    @Test(arguments: Failure.allCases)
    func innerRunCommandFailsInTheInterfaceLanguage(_ failure: Failure) async {
        await withInterfaceLanguage("zh-Hans") {
            let ran = Locked<[String]>(initialState: [])
            let alone = failed("lines", "1", in: host(failing: failure, ran: ran))
            #expect(alone == failure.chinese, "on its own: \(alone ?? "no failure")")
            let inside = failed("question", "x @lines 1", in: host(failing: failure, ran: ran))
            #expect(inside?.hasPrefix("@lines") == true && inside?.hasSuffix(failure.chinese) == true,
                    "inside @question's text: \(inside ?? "no failure")")
            #expect(inside?.contains(failure.english) != true, "not in English: \(inside ?? "no failure")")
        }
    }

    // MARK: - The request's stream

    /// The issue's own test: the request for `@question x @py 1` in a task whose interface language is Simplified
    /// Chinese (`UIText.scopedLanguage`) fails with what the panel shows as "@py：运行超过 10 秒，已停止"; in English
    /// it stays "@py: Stopped after 10 seconds".
    @Test func theRequestsErrorIsInItsTasksLanguage() async {
        let ran = Locked<[String]>(initialState: [])
        var services = SessionServices()
        services.runProgram = Self.failing(.timedOut, ran: ran)
        let place = SessionTasks.Place(app: nil, terminal: false, pastesInTerminal: false, improveTranslates: false,
                                       pluginLanguage: .chinese)
        let request = SessionTasks.Request(input: "", command: .question, plan: CommandPlan.make("x @py 1", commands: Command.builtins))
        /// What the panel says for the request's error (`InputSession`: a `DescribedError`'s message, or the error
        /// described), in `language`.
        func shown(in language: String) async -> String? {
            await UIText.$scopedLanguage.withValue(language) {
                do {
                    for try await _ in SessionTasks.stream(for: request, in: place, services: services) {}
                    return nil
                } catch {
                    return (error as? DescribedError)?.message ?? UIText.describe(error)
                }
            }
        }
        let chinese = await shown(in: "zh-Hans")
        #expect(chinese == "@py：运行超过 10 秒，已停止", "\(chinese ?? "no failure")")
        let english = await shown(in: "en")
        #expect(english == "@py: Stopped after 10 seconds", "\(english ?? "no failure")")
        #expect(ran.withLock { $0.count } == 2)
    }
}
