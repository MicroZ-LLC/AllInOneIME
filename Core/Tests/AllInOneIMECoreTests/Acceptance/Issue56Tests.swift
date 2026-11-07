import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// #56: what a run command prints on one line goes in trimmed, as before #44. Since #44 (several lines keep their first
/// line's indentation) one padded value kept its padding too: BSD `wc` right-aligns its count, so `pbpaste | wc -w`
/// inserted "      17", and `@question how long is @wc` sent the padding mid-sentence. Through `CommandRunner.run`, as
/// the input method runs them (the result, the "all of it" candidate), through a field's session (`FakeHost`): what
/// Return inserts, and as a command inside `@question`'s text: what the model is asked (the Claude API stubbed,
/// `RAStubProtocol`). Several lines keep their alignment (Issue44Tests).
@Suite(.serialized)
struct Issue56Tests {
    #if os(Windows)
    // Git for Windows' tools (sh, printf, wc), where the Mac has them in /usr/bin and /bin.
    let environment = ["PATH": WindowsTestTools.gitTools ?? ""]
    #else
    let environment = ["PATH": "/usr/bin:/bin"]
    #endif

    /// A run command that runs its text as a shell command line.
    let sh = CustomCommand(name: "sh", type: .run, argv: ["sh", "-c", "{input}"])

    /// A count as BSD `wc` prints it: right-aligned in 8 columns.
    static let wc = CustomCommand(name: "wc", type: .run, argv: ["sh", "-c", "printf '%8d\\n' 17"])

    /// What `command` gives for `input`, its result's text (the "all of it" candidate) once it exited.
    func run(_ command: CustomCommand, _ input: String) async -> Result<String, Error> {
        do {
            var text = ""
            for try await update in CommandRunner.run(command, input: input, environment: environment) where update.isFinal {
                text = update.result.versions.first?.text ?? ""
            }
            return .success(text)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - A run command

    @Test func oneLineComesWithoutItsPadding() async throws {
        let cases: [(script: String, result: String)] = [
            ("printf '%8d\\n' 17", "17"),  // the issue's: a count as BSD wc pads it
            ("printf '%5d' 42", "42"),  // printf %5d, without a line break at the end
            ("printf '\\t17\\n'", "17"),  // a tab
            ("printf '   4.0K\\t.\\n'", "4.0K\t."),  // a padded size and a column after it (du): the tab between stays
            ("printf '\\n\\n  17  \\n\\n'", "17"),  // blank lines around it, spaces after it
        ]
        for (script, result) in cases {
            let got = await run(sh, script)
            #expect((try? got.get()) == result, "\(script): \(got)")
        }
    }

    /// `wc` itself: BSD wc (the Mac's) pads its count, GNU wc reading standard input doesn't; either way just the number.
    @Test func wcsCountIsJustTheNumber() async throws {
        let got = await run(sh, "printf 'one two three' | wc -w")
        #expect((try? got.get()) == "3", "\(got)")
    }

    // MARK: - In a field

    final class Settings: @unchecked Sendable {
        var config: Config
        init() {
            config = .default
            config.uiLanguage = "en"
            config.setOrder([Language.chinese, .english])
        }
    }

    /// A session in an editor (not a terminal) that has the focus, with `settings`, its programs run for real with
    /// `environment` as their own, the model the Claude API at the config's host (`RAStubProtocol`).
    func host(_ settings: Settings) -> FakeHost {
        let engine = FakeEngine()
        let environment = self.environment
        var services = SessionServices(loadSettings: { settings.config })
        services.levelOne = { .engine(engine) }
        services.programInstalled = { _ in true }
        services.runProgram = { command, input in CommandRunner.run(command, input: input, environment: environment) }
        services.converter = Converter(client: BedrockClient(session: RAStubProtocol.session()), loadConfig: { settings.config },
                                       loadKey: { _, _ in "sk-test" }, loadJargon: { _ in [] })
        let host = FakeHost(services: services)
        host.focus()
        return host
    }

    /// Picks `letters`' command from the list ("@", its letters, Tab), types `input` in English and runs it (⏎): whether
    /// its result came (within `timeout` seconds) and is chosen. Its result goes in with the next ⏎.
    func run(_ letters: String, _ input: String, in host: FakeHost, timeout: TimeInterval = 60) -> Bool {
        host.composer.setInputMode(.english)
        host.press(FakeHost.at)
        host.type(letters)
        host.press(FakeHost.tab)
        host.type(input)
        host.press(FakeHost.enter)
        return host.settle(timeout: timeout) { host.composer.phase == .choosing }
    }

    @Test func aRunCommandsOneValueGoesInWithoutItsPadding() async throws {
        await withInterfaceLanguage("en") {
            let settings = Settings()
            settings.config.customCommands = [Self.wc]
            let host = host(settings)
            #expect(run("wc", "x", in: host), "\(host.composer.phase)")
            #expect(host.composer.choices.contains { $0.text == "17" }, "\(host.composer.choices.map(\.text))")
            host.press(FakeHost.enter)
            #expect(host.document == "17" && host.marked.isEmpty, "\(host.document.debugDescription)")
        }
    }

    // MARK: - Inside another command's text

    /// `@question how long is @wc x`: the count goes in the question as a word of it, not after a run of spaces.
    @Test func aCommandsOneValueGoesInTheQuestionWithoutItsPadding() async throws {
        try await withInterfaceLanguage("en") {
            let settings = Settings()
            let apiHost = "issue56-\(UUID().uuidString.lowercased()).test"
            settings.config.provider = .anthropic
            settings.config.anthropic.baseURL = "https://\(apiHost)"
            settings.config.anthropic.model = "claude-test"
            settings.config.rewriteStyles = []
            settings.config.customCommands = [Self.wc]
            RAStubProtocol.enqueue(apiHost, .answer("About a paragraph."))
            let host = host(settings)
            #expect(run("question", "how long is @wc x", in: host), "\(host.composer.phase)")
            let asked = try RAStubProtocol.bodies(apiHost).map(TCA.Sent.init).last?.last ?? ""
            #expect(asked.contains("how long is 17"), "\(asked.debugDescription)")
        }
    }
}
