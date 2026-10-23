import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `AllInOneIME --run-plugin <folder> [--language zh|en] [--with-preferences]`: the child process a script plugin runs
/// in. The text comes on standard input (with `--with-preferences`, `RunInput`: the text and the plugin's preferences,
/// as JSON); the result goes to standard output, an error message to standard error (exit 1).
public enum PluginHost {
    /// What follows `--run-plugin`.
    public struct Invocation: Equatable, Sendable {
        public var directory: String
        /// The input method's interface language, for the script's `context`; nil when missing or unknown.
        public var language: Language?
        /// Standard input is `RunInput` (`--with-preferences`): the plugin has preferences, for the script's `context`.
        public var preferences: Bool

        public init(directory: String, language: Language? = nil, preferences: Bool = false) {
            self.directory = directory
            self.language = language
            self.preferences = preferences
        }
    }

    /// The flag after the folder that says standard input is `RunInput`.
    public static let preferencesFlag = "--with-preferences"

    /// What a plugin with preferences gets on standard input: the text, and its preferences (passwords too, so never on
    /// a command line).
    public struct RunInput: Codable, Equatable, Sendable {
        public var input: String
        public var preferences: [String: String]

        public init(input: String, preferences: [String: String]) {
            self.input = input
            self.preferences = preferences
        }
    }

    /// `<folder> [--language zh|en] [--with-preferences]` (the arguments after `--run-plugin`); nil without a folder. A
    /// missing or unknown language is nil (the script then gets `{}`), other arguments are ignored.
    public static func invocation(_ arguments: [String]) -> Invocation? {
        guard let directory = arguments.first else { return nil }
        var language: Language?
        if let index = arguments.dropFirst().firstIndex(of: "--language"), index + 1 < arguments.count {
            language = Language(rawValue: arguments[index + 1]).flatMap { $0 == .chinese || $0 == .english ? $0 : nil }
        }
        return Invocation(directory: directory, language: language, preferences: arguments.dropFirst().contains(preferencesFlag))
    }

    public static func run(directory path: String, language: Language? = nil, preferences: Bool = false,
                           appVersion: String = AppVersion.string) -> Int32 {
        func fail(_ message: String) -> Int32 {
            FileHandle.standardError.write(Data((message + "\n").utf8))
            return 1
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("plugin.json")),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) else {
            return fail("The plugin has no readable plugin.json")
        }
        if let problem = manifest.problem(appVersion: appVersion) { return fail("Plugin \(manifest.name): \(problem)") }
        guard manifest.type == .script, let script = manifest.script,
              let source = try? Data(contentsOf: directory.appendingPathComponent(script)),
              source.count <= PluginManifest.maxScriptBytes else {
            return fail("Plugin \(manifest.name): no script, or larger than \(PluginManifest.maxScriptBytes / 1024) KB")
        }
        let read = FileHandle.standardInput.readDataToEndOfFile()
        var input = String(decoding: read, as: UTF8.self)
        var values: [String: String]?
        if preferences {
            guard let given = try? JSONDecoder().decode(RunInput.self, from: read) else { return fail("No input on standard input") }
            (input, values) = (given.input, given.preferences)
        }
        input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let text = try PluginScript.evaluate(source: String(decoding: source, as: UTF8.self), input: input,
                                                 language: language, preferences: values, fetcher: URLSessionFetcher(hosts: manifest.hosts))
            FileHandle.standardOutput.write(Data(text.utf8))
            return 0
        } catch {
            return fail((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }
}

/// Runs a script plugin: `<executable> --run-plugin <folder> [--language zh|en] [--with-preferences]` through
/// `CommandRunner` (timeout, output limit, Esc), with the text on standard input (and the plugin's preferences, where it
/// has some).
public enum PluginRunner {
    /// The program run for `plugin`, as a `run` command; `language` is the input method's interface language. A plugin
    /// with preferences is told its standard input is `PluginHost.RunInput` (`standardInput`).
    public static func command(for plugin: InstalledPlugin, executable: String, language: Language? = nil) -> CustomCommand {
        CustomCommand(name: plugin.name, type: .run,
                      argv: [executable, "--run-plugin", plugin.directory.path] + (language.map { ["--language", $0.rawValue] } ?? [])
                          + (plugin.manifest.preferences.isEmpty ? [] : [PluginHost.preferencesFlag]),
                      stdin: CustomCommand.placeholder, ascii: plugin.manifest.typesLatin,
                      timeoutSeconds: plugin.manifest.timeout)
    }

    /// What a plugin with preferences gets on standard input: `input` and `preferences`, as JSON.
    public static func standardInput(_ input: String, preferences: [String: String]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(PluginHost.RunInput(input: input, preferences: preferences))).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// `plugin` run on `input`. `preferences`: its preferences as the user set them (`PluginPreference.stored`), read
    /// off the caller's thread (passwords come from the secret store) where it has some; the defaults filled in.
    public static func run(_ plugin: InstalledPlugin, input: String, language: Language? = nil,
                           preferences: (@Sendable () -> [String: String])? = nil,
                           executable: String = Bundle.main.executablePath ?? CommandLine.arguments[0])
        -> AsyncThrowingStream<ConversionUpdate, Error> {
        let command = command(for: plugin, executable: executable, language: language)
        guard !plugin.manifest.preferences.isEmpty else { return CommandRunner.run(command, input: input) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let values = PluginPreference.values(for: plugin, set: preferences?() ?? [:])
                    for try await update in CommandRunner.run(command, input: standardInput(input, preferences: values)) {
                        continuation.yield(update)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
