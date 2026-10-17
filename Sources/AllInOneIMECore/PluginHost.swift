import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `AllInOneIME --run-plugin <folder> [--language zh|en]`: the child process a script plugin runs in. The
/// text comes on standard input; the result goes to standard output, an error message to standard error (exit 1).
public enum PluginHost {
    /// What follows `--run-plugin`.
    public struct Invocation: Equatable, Sendable {
        public var directory: String
        /// The input method's interface language, for the script's `context`; nil when missing or unknown.
        public var language: Language?

        public init(directory: String, language: Language? = nil) {
            self.directory = directory
            self.language = language
        }
    }

    /// `<folder> [--language zh|en]` (the arguments after `--run-plugin`); nil without a folder. A missing or
    /// unknown language is nil (the script then gets `{}`), other arguments are ignored.
    public static func invocation(_ arguments: [String]) -> Invocation? {
        guard let directory = arguments.first else { return nil }
        var language: Language?
        if let index = arguments.dropFirst().firstIndex(of: "--language"), index + 1 < arguments.count {
            language = Language(rawValue: arguments[index + 1]).flatMap { $0.isInterfaceLanguage ? $0 : nil }
        }
        return Invocation(directory: directory, language: language)
    }

    public static func run(directory path: String, language: Language? = nil, appVersion: String = AppVersion.string) -> Int32 {
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
        let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let text = try PluginScript.evaluate(source: String(decoding: source, as: UTF8.self), input: input,
                                                 language: language, fetcher: URLSessionFetcher(hosts: manifest.hosts))
            FileHandle.standardOutput.write(Data(text.utf8))
            return 0
        } catch {
            return fail((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }
}

/// Runs a script plugin: `<executable> --run-plugin <folder> [--language zh|en]` through `CommandRunner`
/// (timeout, output limit, Esc), with the text on standard input.
public enum PluginRunner {
    /// The program run for `plugin`, as a `run` command; `language` is the input method's interface language.
    public static func command(for plugin: InstalledPlugin, executable: String, language: Language? = nil) -> CustomCommand {
        CustomCommand(name: plugin.name, type: .run,
                      argv: [executable, "--run-plugin", plugin.directory.path] + (language.map { ["--language", $0.rawValue] } ?? []),
                      stdin: CustomCommand.placeholder, ascii: plugin.manifest.typesLatin,
                      timeoutSeconds: plugin.manifest.timeout)
    }

    public static func run(_ plugin: InstalledPlugin, input: String, language: Language? = nil,
                           executable: String = Bundle.main.executablePath ?? CommandLine.arguments[0])
        -> AsyncThrowingStream<ConversionUpdate, Error> {
        CommandRunner.run(command(for: plugin, executable: executable, language: language), input: input)
    }
}
