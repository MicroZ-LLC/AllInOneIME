import Foundation

extension PluginScript {
    /// A completion script's function (spec 1.2).
    public enum CompletionFunction: String, Sendable {
        /// `load(ctx)`: the whole list.
        case load
        /// `query(text, ctx)`: a live lookup of what follows the prefix.
        case query
    }

    /// Runs `function` of a plugin's script `source` (`load(ctx)` or `query(text, ctx)`) with nothing but `fetch`, as
    /// `run` runs (`evaluate`): what it returned, as JSON (`JSON.stringify`), unchecked (the core checks it).
    public static func evaluateCompletion(source: String, function: CompletionFunction, text: String = "",
                                          context: CompletionContext, fetcher: PluginFetcher,
                                          engine: any ScriptEngine = Platform.current.scripts) throws -> String {
        guard let script = engine.makeContext() else { throw PluginScriptError.failed("JavaScript is not available") }
        var thrown: String? { script.exception.map { $0.toString() ?? "error" } }
        let native = script.function { arguments in
            let list = (arguments.first?.toArray() ?? []).map { "\($0)" }
            let fields = ((arguments.count > 1 ? arguments[1].toDictionary() : nil) ?? [:]).mapValues { "\($0)" }
            return fetcher.fetch(list.map { PluginRequest(url: $0, headers: fields) }).map { r -> [String: Any] in
                var out: [String: Any] = ["status": r.status, "text": r.text]
                if let error = r.error { out["error"] = error }
                return out
            }
        }
        script.setGlobal("__fetch", native)
        script.evaluate(prelude)
        script.evaluate(source)
        if let thrown { throw PluginScriptError.failed(clean(thrown)) }
        guard let declared = script.global(function.rawValue), declared.isObject, !declared.isUndefined else {
            throw PluginScriptError.failed(function == .load ? "The plugin has no load(ctx) function"
                                                             : "The plugin has no query(text, ctx) function")
        }
        let ctx: [String: Any] = ["source": context.source, "preferences": context.preferences, "language": context.language.rawValue]
        script.setGlobal("__ctx", ctx)
        script.setGlobal("__text", text)
        let call = function == .load ? "load(__ctx)" : "query(__text, __ctx)"
        let value = script.evaluate("(function () { const out = \(call); return out === undefined ? null : JSON.stringify(out); })()")
        if let thrown { throw PluginScriptError.failed(clean(thrown)) }
        guard let value, value.isString, let json = value.toString() else {
            throw PluginScriptError.failed("\(function.rawValue) must return an object with items")
        }
        return json
    }
}

extension PluginHost {
    /// `--run-plugin <folder> --completion load|query`: `function` of the plugin's completion script, its `ctx`, a
    /// query's text and the hosts the user approved as JSON on standard input (`CompletionInput`, so that no password is
    /// on a command line); what it returned as JSON on standard output, an error message on standard error (exit 1).
    public static func runCompletion(directory path: String, function: PluginScript.CompletionFunction,
                                     appVersion: String = AppVersion.string) -> Int32 {
        switch completion(directory: path, function: function, input: FileHandle.standardInput.readDataToEndOfFile(),
                          appVersion: appVersion) {
        case let .success(json):
            FileHandle.standardOutput.write(Data(json.utf8))
            return 0
        case let .failure(failure):
            FileHandle.standardError.write(Data((failure.message + "\n").utf8))
            return 1
        }
    }

    /// Why a completion call failed, as the child process prints it.
    public struct CompletionFailure: Error, Equatable, ExpressibleByStringLiteral {
        public var message: String
        public init(_ message: String) { self.message = message }
        public init(stringLiteral message: String) { self.message = message }
    }

    /// `runCompletion` with `input` (standard input's): the plugin.json in `path` read again, `fetch` allowed to the hosts
    /// it lists that the user approved (`CompletionInput.hosts`, in any case: an update may have added one since), by
    /// way of `fetcher` (the network's, `URLSessionFetcher`).
    public static func completion(directory path: String, function: PluginScript.CompletionFunction, input: Data,
                                  appVersion: String = AppVersion.string,
                                  fetcher: ([String]) -> PluginFetcher = { URLSessionFetcher(hosts: $0) }) -> Result<String, CompletionFailure> {
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("plugin.json")),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) else {
            return .failure("The plugin has no readable plugin.json")
        }
        if let problem = manifest.problem(appVersion: appVersion) { return .failure(.init("Plugin \(manifest.name): \(problem)")) }
        guard manifest.type == .script, let script = manifest.script,
              let source = try? Data(contentsOf: directory.appendingPathComponent(script)),
              source.count <= PluginManifest.maxScriptBytes else {
            return .failure(.init("Plugin \(manifest.name): no script, or larger than \(PluginManifest.maxScriptBytes / 1024) KB"))
        }
        guard let input = try? JSONDecoder().decode(CompletionInput.self, from: input),
              let language = Language(rawValue: input.language) else { return .failure("No completion context on standard input") }
        let approved = Set(input.hosts.map { $0.lowercased() })
        let hosts = manifest.hosts.filter { approved.contains($0.lowercased()) }
        let context = CompletionContext(source: input.source, preferences: input.preferences, language: language)
        do {
            return .success(try PluginScript.evaluateCompletion(source: String(decoding: source, as: UTF8.self), function: function,
                                                                text: input.text ?? "", context: context, fetcher: fetcher(hosts)))
        } catch {
            return .failure(.init((error as? LocalizedError)?.errorDescription ?? "\(error)"))
        }
    }

    /// What `--completion` reads on standard input: the script's `ctx`, a query's text, and the hosts the user approved
    /// (`CompletionCall.hosts`).
    public struct CompletionInput: Codable, Equatable, Sendable {
        public var source: String
        public var preferences: [String: String]
        public var language: String
        public var text: String?
        public var hosts: [String]

        public init(_ context: CompletionContext, text: String?, hosts: [String] = []) {
            source = context.source
            preferences = context.preferences
            language = context.language.rawValue
            self.text = text
            self.hosts = hosts
        }
    }

    /// The completion function after `--completion` in the arguments after `--run-plugin`; nil without one.
    public static func completionFunction(_ arguments: [String]) -> PluginScript.CompletionFunction? {
        guard let index = arguments.firstIndex(of: "--completion"), index + 1 < arguments.count else { return nil }
        return PluginScript.CompletionFunction(rawValue: arguments[index + 1])
    }
}

/// Runs plugins' completion scripts (spec 1.2) as script plugins run: in a child process of the input method
/// (`<executable> --run-plugin <folder> --completion load|query`, `PluginHost.runCompletion`), `fetch` to the plugin's
/// hosts the user approved only (`CompletionCall.hosts`), stopped after the call's timeout (or when the task is cancelled); what it printed, as it is (the core
/// checks it). `inProcess`: the script runs here, on a thread of its own, with the `fetcher` given (the self-test's
/// stand-in for the network); stopped at its timeout where the engine can.
public struct PluginCompletionRuntime: CompletionRuntime {
    public enum Mode: Sendable {
        case childProcess(executable: String)
        case inProcess(fetcher: @Sendable (InstalledPlugin) -> PluginFetcher)
    }

    public var mode: Mode

    public init(mode: Mode) { self.mode = mode }

    /// The child process of this program.
    public init(executable: String = Bundle.main.executablePath ?? CommandLine.arguments[0]) {
        mode = .childProcess(executable: executable)
    }

    /// The most a script may print: a list's 4 MiB, with room for its JSON.
    static let maxOutput = CompletionList.maxBytes + 64 * 1024

    public func load(_ call: CompletionCall) async throws -> Data {
        try await run(.load, text: nil, call)
    }

    public func query(_ text: String, _ call: CompletionCall) async throws -> Data {
        try await run(.query, text: text, call)
    }

    private func run(_ function: PluginScript.CompletionFunction, text: String?, _ call: CompletionCall) async throws -> Data {
        switch mode {
        case let .childProcess(executable):
            let input = try JSONEncoder().encode(PluginHost.CompletionInput(call.context, text: text, hosts: call.hosts))
            let argv = [executable, "--run-plugin", call.plugin.directory.path, "--completion", function.rawValue]
            let output = try await CommandRunner.output(argv, stdin: String(decoding: input, as: UTF8.self), timeout: call.timeout,
                                                        maxOutput: Self.maxOutput)
            return Data(output.utf8)
        case let .inProcess(fetcher):
            guard let script = call.plugin.scriptURL, let source = try? String(contentsOf: script, encoding: .utf8) else {
                throw PluginScriptError.failed("The plugin has no script")
            }
            let fetch = fetcher(call.plugin)
            return try await withCheckedThrowingContinuation { continuation in
                Thread.detachNewThread {
                    do {
                        let json = try PluginScript.evaluateCompletion(source: source, function: function, text: text ?? "",
                                                                       context: call.context, fetcher: fetch)
                        continuation.resume(returning: Data(json.utf8))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}
