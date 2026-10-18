import Foundation
import Testing
@testable import AllInOneIMECore

// Independent acceptance tests for "script plugins learn the input method's own UI language", written from the spec
// (not from the implementation's own tests). They use `PluginScript.evaluate`, `PluginRunner.command` and
// `PluginHost.invocation` (main.swift's `--run-plugin` arguments), and, when it is built, the app binary itself
// ($ALLINONEIME_TEST_BINARY, or the repo root's .build/debug/AllInOneIME: `swift build` there) run as the child process
// with a plugin in a temporary folder.
//
// The spec, as tested here:
//   S1 the call: `run(input, context)`, context a plain object, exactly {language: "zh"} or {language: "en"};
//   S2 unknown language: no language, or any other value, gives {}; nothing else is ever in the context;
//   S3 the child process: `<app> --run-plugin <folder> --language zh|en`, parsed after the folder, only exact
//      `zh` / `en` count, anything else is {}; without a folder the exit status is 2;
//   S4 old plugins: `run(input)` works unchanged.
//
// Assumed where the spec is silent: with no language the argv is the one from before the change
// (`<app> --run-plugin <folder>`, no `--language`); the context is passed (as {}) even when no language is known,
// so `arguments.length` is always 2.

// MARK: - Fixtures

/// Answers from a table of URL → body (status 200); anything else can't be reached. Records what was asked.
final class PlugLangFetcher: PluginFetcher, @unchecked Sendable {
    private let lock = NSLock()
    private let answers: [String: String]
    private var _asked: [String] = []

    init(_ answers: [String: String] = [:]) { self.answers = answers }

    var asked: [String] { lock.withLock { _asked } }

    func fetch(_ requests: [PluginRequest]) -> [PluginResponse] {
        lock.withLock { _asked += requests.map(\.url) }
        return requests.map { request in
            guard let body = answers[request.url] else { return PluginResponse(error: "can't reach the host") }
            return PluginResponse(status: 200, text: body)
        }
    }
}

enum PlugLang {
    static let zh = #"{"language":"zh"}"#
    static let en = #"{"language":"en"}"#
    static let empty = "{}"

    /// What the context must be for `language`, as JSON.stringify prints it.
    static func expectedJSON(_ language: Language?) -> String {
        switch language {
        case .chinese?: return zh
        case .english?: return en
        default: return empty
        }
    }

    /// Every language the app knows, and none.
    static let allLanguages: [Language?] = [nil] + Language.allCases.map { Optional($0) }

    static func evaluate(_ source: String, input: String = "hello", language: Language?,
                         fetcher: PluginFetcher = PlugLangFetcher()) throws -> String {
        try PluginScript.evaluate(source: source, input: input, language: language, fetcher: fetcher)
    }

    /// `JSON.stringify(arguments[1])`.
    static let stringifyContext = "function run(input, context) { return JSON.stringify(arguments[1]); }"

    /// `arguments.length`.
    static let argumentCount = "function run(input, context) { return String(arguments.length); }"

    /// The context's shape: a plain, ordinary object (not null, an array, a wrapper or a class instance), its own
    /// property names (enumerable or not) and symbols, and the language's type.
    static let shape = """
        function run(input, context) {
          const c = arguments[1];
          return [typeof c, c === null, Array.isArray(c), Object.prototype.toString.call(c),
                  Object.getPrototypeOf(c) === Object.prototype, JSON.stringify(Object.getOwnPropertyNames(c)),
                  Object.getOwnPropertySymbols(c).length, typeof c.language].join("|");
        }
        """

    /// What `run`'s named second parameter is (the same object as arguments[1]).
    static let namedParameter = """
        function run(input, context) {
          return (context === arguments[1]) + "|" + (context.language === undefined ? "none" : context.language);
        }
        """

    /// The input, untouched, as the first argument.
    static let firstArgument = "function run(input, context) { return typeof arguments[0] + ':' + arguments[0]; }"

    /// An old plugin: `run(input)`, no context.
    static let oldStyle = "function run(input) { return input.split('').reverse().join('') + '!'; }"

    /// An old plugin that fetches, as plugins did before (`fetch`, `json()`).
    static let oldStyleFetching = """
        function run(input) {
          const r = fetch("https://quotes.test/q?s=" + encodeURIComponent(input));
          return input.toUpperCase() + " " + r.json().price + " " + r.ok;
        }
        """

    static let oldStyleThrowing = "function run(input) { throw new Error('no quote for ' + input); }"
    static let oldStyleNotText = "function run(input) { return 42; }"

    static func plugin(_ name: String = "langprobe", folder: String = "/tmp/plugins/langprobe") -> InstalledPlugin {
        InstalledPlugin(manifest: PluginManifest(name: name, version: "1.0.0", type: .script, script: "main.js"),
                        directory: URL(fileURLWithPath: folder, isDirectory: true), isLocal: true)
    }
}

// MARK: - S1 / S2: the context a script gets

@Suite("PluginLanguageAcceptance: the context")
struct PluginLanguageContextAcceptanceTests {
    @Test("S1: zh gives exactly {\"language\":\"zh\"} as arguments[1]")
    func chinese() throws {
        #expect(try PlugLang.evaluate(PlugLang.stringifyContext, language: .chinese) == PlugLang.zh)
    }

    @Test("S1: en gives exactly {\"language\":\"en\"} as arguments[1]")
    func english() throws {
        #expect(try PlugLang.evaluate(PlugLang.stringifyContext, language: .english) == PlugLang.en)
    }

    @Test("S2: no language known gives {}")
    func noLanguage() throws {
        #expect(try PlugLang.evaluate(PlugLang.stringifyContext, language: nil) == PlugLang.empty)
        // The default, when the caller says nothing about the language.
        #expect(try PluginScript.evaluate(source: PlugLang.stringifyContext, input: "hello", fetcher: PlugLangFetcher())
                == PlugLang.empty)
    }

    @Test("S2: any other language (one the UI can't be in) gives {}", arguments: Language.allCases.filter { $0 != .chinese && $0 != .english })
    func otherLanguages(_ language: Language) throws {
        #expect(try PlugLang.evaluate(PlugLang.stringifyContext, language: language) == PlugLang.empty)
    }

    @Test("S1/S2: every language, and none, maps to exactly one of the three contexts")
    func everyLanguage() throws {
        for language in PlugLang.allLanguages {
            #expect(try PlugLang.evaluate(PlugLang.stringifyContext, language: language) == PlugLang.expectedJSON(language),
                    "language \(String(describing: language))")
        }
    }

    @Test("S1: run is called with two arguments, whatever the language")
    func argumentsLength() throws {
        for language in PlugLang.allLanguages {
            #expect(try PlugLang.evaluate(PlugLang.argumentCount, language: language) == "2",
                    "language \(String(describing: language))")
        }
    }

    @Test("S1: the context is a plain object with only a string language")
    func plainObjectWithLanguage() throws {
        for language in [Language.chinese, .english] {
            #expect(try PlugLang.evaluate(PlugLang.shape, language: language)
                    == #"object|false|false|[object Object]|true|["language"]|0|string"#, "language \(language)")
        }
    }

    @Test("S2: the unknown-language context is a plain, empty object (not undefined or null)")
    func plainEmptyObject() throws {
        for language in PlugLang.allLanguages where language != .chinese && language != .english {
            #expect(try PlugLang.evaluate(PlugLang.shape, language: language)
                    == "object|false|false|[object Object]|true|[]|0|undefined", "language \(String(describing: language))")
        }
    }

    @Test("S1: the named context parameter is arguments[1] and reads context.language")
    func namedParameter() throws {
        #expect(try PlugLang.evaluate(PlugLang.namedParameter, language: .chinese) == "true|zh")
        #expect(try PlugLang.evaluate(PlugLang.namedParameter, language: .english) == "true|en")
        #expect(try PlugLang.evaluate(PlugLang.namedParameter, language: nil) == "true|none")
        #expect(try PlugLang.evaluate(PlugLang.namedParameter, language: .korean) == "true|none")
    }

    @Test("S1: the input is still the first argument, untouched")
    func inputFirst() throws {
        for language in PlugLang.allLanguages {
            #expect(try PlugLang.evaluate(PlugLang.firstArgument, input: "aapl 苹果 {\"x\":1}", language: language)
                    == "string:aapl 苹果 {\"x\":1}", "language \(String(describing: language))")
        }
    }

    @Test("S1: a script that branches on context.language answers in the UI's language")
    func branching() throws {
        let source = """
            function run(input, context) {
              if (context.language === "zh") return "价格：" + input;
              if (context.language === "en") return "Price: " + input;
              return "? " + input;
            }
            """
        #expect(try PlugLang.evaluate(source, input: "42", language: .chinese) == "价格：42")
        #expect(try PlugLang.evaluate(source, input: "42", language: .english) == "Price: 42")
        #expect(try PlugLang.evaluate(source, input: "42", language: nil) == "? 42")
        #expect(try PlugLang.evaluate(source, input: "42", language: .french) == "? 42")
    }
}

// MARK: - S4: old plugins

@Suite("PluginLanguageAcceptance: old plugins")
struct PluginLanguageOldPluginAcceptanceTests {
    @Test("S4: run(input) gives the same result with zh, en, another language and none")
    func unchanged() throws {
        for language in PlugLang.allLanguages {
            #expect(try PlugLang.evaluate(PlugLang.oldStyle, input: "abc", language: language) == "cba!",
                    "language \(String(describing: language))")
        }
    }

    @Test("S4: run(input) that fetches still fetches and answers")
    func fetching() throws {
        for language in PlugLang.allLanguages {
            let fetcher = PlugLangFetcher(["https://quotes.test/q?s=aapl": #"{"price": 230.5}"#])
            #expect(try PlugLang.evaluate(PlugLang.oldStyleFetching, input: "aapl", language: language, fetcher: fetcher)
                    == "AAPL 230.5 true", "language \(String(describing: language))")
            #expect(fetcher.asked == ["https://quotes.test/q?s=aapl"])
        }
    }

    @Test("S4: run(input) errors are what they were, whatever the language")
    func errorsUnchanged() throws {
        for source in [PlugLang.oldStyleThrowing, PlugLang.oldStyleNotText] {
            var errors: [String] = []
            for language in PlugLang.allLanguages {
                do {
                    _ = try PlugLang.evaluate(source, input: "aapl", language: language)
                    Issue.record("\(source) should fail (language \(String(describing: language)))")
                } catch let error as PluginScriptError {
                    errors.append(error.localizedDescription)
                }
            }
            #expect(Set(errors).count == 1, "the same error for every language: \(errors)")
        }
        #expect(throws: PluginScriptError.failed("no quote for aapl")) {
            try PlugLang.evaluate(PlugLang.oldStyleThrowing, input: "aapl", language: .chinese)
        }
    }

    @Test("S4: a script without run is still refused, whatever the language")
    func noRun() {
        for language in PlugLang.allLanguages {
            #expect(throws: PluginScriptError.noRunFunction) {
                try PlugLang.evaluate("function main(input) { return input; }", language: language)
            }
        }
    }
}

// MARK: - S3: the child process's arguments

@Suite("PluginLanguageAcceptance: the child process's arguments")
struct PluginLanguageArgumentsAcceptanceTests {
    typealias Invocation = PluginHost.Invocation
    static let exe = "/Applications/AllInOneIME.app/Contents/MacOS/AllInOneIME"

    @Test("S3: zh runs `<app> --run-plugin <folder> --language zh`")
    func argvChinese() {
        let plugin = PlugLang.plugin()
        #expect(PluginRunner.command(for: plugin, executable: Self.exe, language: .chinese).argv
                == [Self.exe, "--run-plugin", "/tmp/plugins/langprobe", "--language", "zh"])
    }

    @Test("S3: en runs `<app> --run-plugin <folder> --language en`")
    func argvEnglish() {
        let plugin = PlugLang.plugin()
        #expect(PluginRunner.command(for: plugin, executable: Self.exe, language: .english).argv
                == [Self.exe, "--run-plugin", "/tmp/plugins/langprobe", "--language", "en"])
    }

    @Test("S2/S3: no language runs `<app> --run-plugin <folder>` as before")
    func argvNone() {
        let plugin = PlugLang.plugin()
        let none = PluginRunner.command(for: plugin, executable: Self.exe, language: nil)
        #expect(none.argv == [Self.exe, "--run-plugin", "/tmp/plugins/langprobe"])
        #expect(PluginRunner.command(for: plugin, executable: Self.exe).argv == none.argv)
    }

    @Test("S3: a folder with spaces stays one argument, right after --run-plugin")
    func argvFolderWithSpaces() {
        let plugin = PlugLang.plugin(folder: "/Users/me/Library/My Plugins/lang probe")
        #expect(PluginRunner.command(for: plugin, executable: Self.exe, language: .english).argv
                == [Self.exe, "--run-plugin", "/Users/me/Library/My Plugins/lang probe", "--language", "en"])
    }

    @Test("S3: the language changes nothing else about the command (stdin, timeout, name, type)")
    func restOfTheCommandUnchanged() {
        let plugin = PlugLang.plugin()
        let none = PluginRunner.command(for: plugin, executable: Self.exe, language: nil)
        for language in [Language.chinese, .english] {
            let told = PluginRunner.command(for: plugin, executable: Self.exe, language: language)
            #expect(told.name == none.name && told.type == none.type && told.timeout == none.timeout)
            #expect(told.standardInput(for: "aapl") == none.standardInput(for: "aapl"))
            #expect(told.standardInput(for: "aapl") == "aapl")
        }
    }

    @Test("S3: what the app runs is read back by the child as the same language (every language, and none)")
    func roundTrip() throws {
        let plugin = PlugLang.plugin()
        for language in PlugLang.allLanguages {
            let argv = try #require(PluginRunner.command(for: plugin, executable: Self.exe, language: language).argv)
            #expect(Array(argv.prefix(3)) == [Self.exe, "--run-plugin", "/tmp/plugins/langprobe"])
            let invocation = PluginHost.invocation(Array(argv.dropFirst(2)))
            let expected: Language? = (language == .chinese || language == .english) ? language : nil
            #expect(invocation == Invocation(directory: "/tmp/plugins/langprobe", language: expected),
                    "language \(String(describing: language)): \(argv)")
        }
    }

    @Test("S3: `<folder> --language zh|en` is read as that language")
    func parsesExactValues() {
        #expect(PluginHost.invocation(["/p/x", "--language", "zh"]) == Invocation(directory: "/p/x", language: .chinese))
        #expect(PluginHost.invocation(["/p/x", "--language", "en"]) == Invocation(directory: "/p/x", language: .english))
        #expect(PluginHost.invocation(["/p/x", "--language", "zh"])?.language == .chinese)
        #expect(PluginHost.invocation(["/p/x", "--language", "en"])?.language == .english)
    }

    @Test("S3: just a folder: that folder, no language")
    func folderOnly() {
        #expect(PluginHost.invocation(["/p/x"]) == Invocation(directory: "/p/x", language: nil))
        #expect(PluginHost.invocation(["/Users/me/My Plugins/x"]) == Invocation(directory: "/Users/me/My Plugins/x"))
        // A folder named like a language is a folder.
        #expect(PluginHost.invocation(["zh"]) == Invocation(directory: "zh", language: nil))
    }

    @Test("S3: without a folder there is no invocation (main exits with 2)")
    func noFolder() {
        #expect(PluginHost.invocation([]) == nil)
    }

    @Test("S3: only exact zh or en count; anything else is no language", arguments: [
        "", "ZH", "Zh", "zH", "EN", "En", "zh-CN", "zh_CN", "zh-Hans", "zh-Hant", "en-US", "en_US", "en-GB",
        " zh", "zh ", "zh\n", "\tEN", "zh,en", "zhen", "z", "e", "chinese", "english", "Chinese", "中文", "英文",
        "fr", "ko", "hi", "de", "ja", "xx", "1", "--language",
    ])
    func inexactValues(_ value: String) {
        #expect(PluginHost.invocation(["/p/x", "--language", value]) == Invocation(directory: "/p/x", language: nil),
                "--language \(value.debugDescription)")
    }

    @Test("S3: --language with no value is no language")
    func missingValue() {
        #expect(PluginHost.invocation(["/p/x", "--language"]) == Invocation(directory: "/p/x", language: nil))
    }

    @Test("S3: a bare zh / en, or another spelling of the option, is no language")
    func notTheOption() {
        for arguments in [["/p/x", "zh"], ["/p/x", "en"], ["/p/x", "--language=zh"], ["/p/x", "--language=en"],
                          ["/p/x", "--lang", "zh"], ["/p/x", "-language", "en"], ["/p/x", "--Language", "zh"],
                          ["/p/x", "-l", "en"], ["/p/x", "--LANGUAGE", "en"], ["/p/x", "language", "zh"]] {
            #expect(PluginHost.invocation(arguments) == Invocation(directory: "/p/x", language: nil), "\(arguments)")
        }
    }

    @Test("S3: the folder is the first argument; the language is read after it")
    func folderFirst() {
        // The folder is never mistaken for the language, nor the language for the folder.
        #expect(PluginHost.invocation(["/p/--language", "--language", "en"]) == Invocation(directory: "/p/--language", language: .english))
        #expect(PluginHost.invocation(["/p/zh", "--language", "en"]) == Invocation(directory: "/p/zh", language: .english))
        // `--language zh` with no folder before it never yields Chinese (whether it counts as no folder or "--language"
        // is taken as the folder).
        let swapped = PluginHost.invocation(["--language", "zh"])
        #expect(swapped == nil || (swapped?.language == nil && swapped?.directory != "zh"), "\(String(describing: swapped))")
    }
}

// MARK: - S1-S4 end to end: the app binary as the child process

/// The built app binary, run as `--run-plugin` with the text on standard input.
enum PlugLangCLI {
    /// The core's package folder, Core/.
    static let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    /// The repo root, Core/'s parent: the macOS app, whose binary this is, is the package there.
    static let repoRoot = package.deletingLastPathComponent()

    /// $ALLINONEIME_TEST_BINARY, else the debug build at the repo root (`swift build` there), else one in Core/ (the
    /// core builds no app, so normally there is none).
    static let binary: String? = {
        if let given = ProcessInfo.processInfo.environment["ALLINONEIME_TEST_BINARY"], FileManager.default.isExecutableFile(atPath: given) {
            return given
        }
        return [repoRoot, package].map { $0.appendingPathComponent(".build/debug/AllInOneIME").path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    static var available: Bool { binary != nil }

    struct Ran {
        var status: Int32
        var output: String
        var errors: String
    }

    enum Failure: Error { case harness(String) }

    /// A temporary script plugin folder: plugin.json and main.js.
    static func pluginFolder(name: String, script: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pluglang-acc-\(UUID().uuidString)/\(name)",
                                                                                  isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = #"{"name": "\#(name)", "version": "1.0.0", "type": "script", "script": "main.js"}"#
        try manifest.write(to: folder.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        try script.write(to: folder.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)
        return folder
    }

    static func remove(_ folder: URL) { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }

    /// `<binary> <arguments>` with `input` on standard input; posix_spawn and files, stopped after `timeout`.
    static func run(_ arguments: [String], input: String = "", timeout: TimeInterval = 60) throws -> Ran {
        guard let binary else { throw Failure.harness("no app binary built") }
        let io = FileManager.default.temporaryDirectory.appendingPathComponent("pluglang-acc-io-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: io, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: io) }
        let inFile = io.appendingPathComponent("in").path, outFile = io.appendingPathComponent("out").path
        let errFile = io.appendingPathComponent("err").path
        try input.write(toFile: inFile, atomically: true, encoding: .utf8)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, inFile, O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, outFile, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        posix_spawn_file_actions_addopen(&actions, 2, errFile, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

        var environment = ProcessInfo.processInfo.environment
        // No DYLD_LIBRARY_PATH: the binary finds librime by its own rpath (the debug build's, to the folder it linked,
        // $ALLINONEIME_THIRDPARTY's or the repo root's ThirdParty; a bundled app's, @executable_path/../Frameworks), so
        // nothing here has to know where ThirdParty is. An inherited one is dropped: dyld would search it first.
        environment.removeValue(forKey: "DYLD_LIBRARY_PATH")
        let argv: [UnsafeMutablePointer<CChar>?] = ([binary] + arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, binary, &actions, &attributes, argv, envp)
        guard spawned == 0 else { throw Failure.harness("can't start \(binary): \(spawned)") }

        let deadline = Date().addingTimeInterval(timeout)
        var status: Int32 = 0
        while true {
            let done = waitpid(pid, &status, WNOHANG)
            if done == pid { break }
            if done == -1 && errno != EINTR { throw Failure.harness("waitpid \(errno)") }
            if Date() > deadline {
                kill(pid, SIGKILL)
                _ = waitpid(pid, &status, 0)
                throw Failure.harness("\(arguments.joined(separator: " ")) didn't finish")
            }
            usleep(5_000)
        }
        let code: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        let read = { (path: String) in (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }
        return Ran(status: code, output: read(outFile), errors: read(errFile))
    }
}

@Suite("PluginLanguageAcceptance: the app binary as the child process",
       .enabled(if: PlugLangCLI.available, "build the app first: swift build at the repo root, or set ALLINONEIME_TEST_BINARY"))
struct PluginLanguageChildProcessAcceptanceTests {
    /// Prints arguments.length, JSON.stringify(arguments[1]) and the input.
    static let probe = "function run(input, context) { return arguments.length + ' ' + JSON.stringify(arguments[1]) + ' ' + input; }"

    @Test("S1/S3: --language zh and --language en reach the script as its context")
    func knownLanguages() throws {
        let folder = try PlugLangCLI.pluginFolder(name: "langprobe", script: Self.probe)
        defer { PlugLangCLI.remove(folder) }
        let zh = try PlugLangCLI.run(["--run-plugin", folder.path, "--language", "zh"], input: "hello\n")
        #expect(zh.status == 0, "\(zh.errors)")
        #expect(zh.output == "2 \(PlugLang.zh) hello")
        let en = try PlugLangCLI.run(["--run-plugin", folder.path, "--language", "en"], input: "hello\n")
        #expect(en.status == 0, "\(en.errors)")
        #expect(en.output == "2 \(PlugLang.en) hello")
    }

    @Test("S2/S3: no --language, or anything but exact zh / en, gives the script {}")
    func unknownLanguages() throws {
        let folder = try PlugLangCLI.pluginFolder(name: "langprobe", script: Self.probe)
        defer { PlugLangCLI.remove(folder) }
        let extras: [[String]] = [[], ["--language"], ["--language", ""], ["--language", "ZH"], ["--language", "zh-CN"],
                                  ["--language", "fr"], ["--language", "xx"], ["--language=zh"], ["zh"]]
        for extra in extras {
            let ran = try PlugLangCLI.run(["--run-plugin", folder.path] + extra, input: "hello")
            #expect(ran.status == 0, "\(extra): \(ran.errors)")
            #expect(ran.output == "2 {} hello", "\(extra)")
        }
    }

    @Test("S3: --run-plugin without a folder exits with 2")
    func noFolder() throws {
        let ran = try PlugLangCLI.run(["--run-plugin"])
        #expect(ran.status == 2, "\(ran.output) \(ran.errors)")
    }

    @Test("S4: an old run(input) plugin runs as before, told a language or not")
    func oldPlugin() throws {
        let folder = try PlugLangCLI.pluginFolder(name: "oldstyle", script: PlugLang.oldStyle)
        defer { PlugLangCLI.remove(folder) }
        let extras: [[String]] = [[], ["--language", "zh"], ["--language", "en"], ["--language", "fr"]]
        for extra in extras {
            let ran = try PlugLangCLI.run(["--run-plugin", folder.path] + extra, input: "abc")
            #expect(ran.status == 0, "\(extra): \(ran.errors)")
            #expect(ran.output == "cba!", "\(extra)")
        }
    }

    @Test("S1/S3: the argv PluginRunner builds, run for real, gives the script the matching context")
    func runnerArgvEndToEnd() throws {
        let folder = try PlugLangCLI.pluginFolder(name: "langprobe", script: Self.probe)
        defer { PlugLangCLI.remove(folder) }
        let plugin = InstalledPlugin(manifest: PluginManifest(name: "langprobe", version: "1.0.0", type: .script, script: "main.js"),
                                     directory: folder, isLocal: true)
        for language in PlugLang.allLanguages {
            let argv = try #require(PluginRunner.command(for: plugin, executable: "AllInOneIME", language: language).argv)
            let ran = try PlugLangCLI.run(Array(argv.dropFirst()), input: "hello")
            #expect(ran.status == 0, "\(argv): \(ran.errors)")
            #expect(ran.output == "2 \(PlugLang.expectedJSON(language)) hello", "language \(String(describing: language))")
        }
    }
}
