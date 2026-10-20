import AllInOneIMECore
import Foundation

/// The settings from the command line, while Windows has no settings window (`allinoneime-cli`):
///
///     set-provider <name> [--model ID] [--base-url URL]   the provider requests go to, written to config.json
///     set-key <provider>                                  its API key, read from standard input (never an argument),
///                                                         kept in the Credential Manager for the provider's host
///     remove-key <provider>                               the key taken out of the Credential Manager
///     set-input <languages>                               the input languages, the first the default: zh,en | en,zh | en
///     show-config                                         what the engine will use (never a key, only its ending)
///
/// Each takes `--config FILE` (default: %APPDATA%\AllInOneIME\config.json, the engine's). The engine reads the file
/// again when it changes, and a key when it is saved again: nothing needs restarting.
public enum SettingsCommands {
    public static let names: Set<String> = ["set-provider", "set-key", "remove-key", "set-input", "show-config"]

    public static let usage = """
        usage: allinoneime-cli set-provider <anthropic|openai|gemini|bedrock|hosted> [--model ID] [--base-url URL]
               allinoneime-cli set-key <anthropic|openai|gemini>      (the key on standard input, or typed when asked)
               allinoneime-cli remove-key <anthropic|openai|gemini>
               allinoneime-cli set-input <zh,en | en,zh | en | ...>   (the first is the one typing starts in)
               allinoneime-cli show-config
               each with [--config FILE] (default: %APPDATA%\\AllInOneIME\\config.json)
        """

    /// Where a command reads and writes.
    public struct IO {
        /// The key, as standard input gives it (one line, or all of it); nil when there is none.
        public var readKey: () -> String?
        public var print: (String) -> Void
        public var fail: (String) -> Void

        public init(readKey: @escaping () -> String?, print: @escaping (String) -> Void, fail: @escaping (String) -> Void) {
            self.readKey = readKey
            self.print = print
            self.fail = fail
        }
    }

    /// Runs `arguments` (the command first); 0 when it worked, 1 when it failed, 2 for a wrong command line.
    public static func run(_ arguments: [String], io: IO) -> Int32 {
        var args = ArraySlice(arguments)
        guard let command = args.popFirst() else {
            io.fail(usage)
            return 2
        }
        var url = Config.userURL
        var model: String?
        var baseURL: String?
        var words: [String] = []
        while let arg = args.popFirst() {
            switch arg {
            case "--config", "--model", "--base-url":
                guard let value = args.popFirst() else {
                    io.fail("\(arg) needs a value")
                    return 2
                }
                switch arg {
                case "--config": url = URL(fileURLWithPath: value)
                case "--model": model = value
                default: baseURL = value
                }
            case "-h", "--help":
                io.print(usage)
                return 0
            default:
                if arg.hasPrefix("--") {
                    io.fail("unknown option \(arg)\n\(usage)")
                    return 2
                }
                words.append(arg)
            }
        }
        let exists = FileManager.default.fileExists(atPath: url.path)
        func load() -> Config? {
            guard exists else { return EngineSettings.fresh }
            do {
                return try Config.load(from: url)
            } catch {
                io.fail("\(shown(url)) can't be read, so it isn't changed: \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
                return nil
            }
        }
        func save(_ config: Config) -> Bool {
            do {
                try config.write(to: url)
                return true
            } catch {
                io.fail("couldn't write \(shown(url)): \(error)")
                return false
            }
        }

        switch command {
        case "set-provider":
            guard words.count == 1, let provider = Provider(rawValue: words[0].lowercased()), provider != .apple else {
                io.fail("set-provider needs one of anthropic, openai, gemini, bedrock, hosted\n\(usage)")
                return 2
            }
            guard var config = load() else { return 1 }
            config.provider = provider
            if model != nil || baseURL != nil {
                guard [.anthropic, .openai, .gemini].contains(provider) else {
                    io.fail("--model and --base-url are for anthropic, openai and gemini (Bedrock's model is modelId)")
                    return 2
                }
                var settings = Self.settings(of: config, provider)
                if let model { settings.model = model }
                if let baseURL { settings.baseURL = baseURL }
                Self.set(&config, provider, settings)
            }
            guard save(config) else { return 1 }
            let resolved = config.settings(for: provider)
            io.print("provider: \(provider.rawValue) (\(provider.displayName))"
                     + (resolved.model.map { ", model \($0)" } ?? "") + (resolved.baseURL.map { ", \($0)" } ?? ""))
            io.print("written to \(shown(url))")
            if [.anthropic, .openai, .gemini].contains(provider), APIKeys.source(provider) == .none {
                io.print("no key yet: allinoneime-cli set-key \(provider.rawValue)")
            }
            if provider == .hosted {
                io.print("AllInOneIME Cloud needs a sign-in, which Windows doesn't have yet: use your own key instead")
            }
            return 0

        case "set-key", "remove-key":
            guard words.count == 1, let provider = Provider(rawValue: words[0].lowercased()),
                  [.anthropic, .openai, .gemini].contains(provider) else {
                if words.count > 1 {
                    io.fail("the key is never an argument (it would stay in the shell's history): give it on standard input")
                } else {
                    io.fail("\(command) needs one of anthropic, openai, gemini\n\(usage)")
                }
                return 2
            }
            if command == "remove-key" {
                do {
                    try APIKeys.remove(provider)
                    io.print("the \(provider.displayName) key is removed")
                    return 0
                } catch {
                    io.fail("couldn't remove the key: \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
                    return 1
                }
            }
            guard let config = load() else { return 1 }
            let settings = config.settings(for: provider)
            guard let host = HTTPProviders.host(of: settings) else {
                io.fail("the \(provider.rawValue) base URL (\(settings.baseURL ?? "none")) has no host to keep the key for")
                return 1
            }
            guard let key = io.readKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
                io.fail("no key on standard input: nothing saved")
                return 1
            }
            do {
                try APIKeys.save(key, for: provider, host: host)
            } catch {
                io.fail("couldn't save the key: \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
                return 1
            }
            io.print("the \(provider.displayName) key is saved for \(host)" + (APIKeys.ending(of: key).map { " (…\($0))" } ?? ""))
            if config.provider != provider { io.print("requests go to \(config.provider.rawValue) now: allinoneime-cli set-provider \(provider.rawValue)") }
            return 0

        case "set-input":
            let codes = words.joined(separator: ",").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            let languages = codes.compactMap { code -> Language? in
                switch code {
                case "zh", "chinese", "中文": return .chinese
                case "en", "english": return .english
                default: return Language(rawValue: code)
                }
            }
            guard !languages.isEmpty, languages.count == codes.count else {
                io.fail("set-input needs input languages, the first the default: zh,en | en,zh | en\n\(usage)")
                return 2
            }
            guard var config = load() else { return 1 }
            config.setOrder(languages)
            guard save(config) else { return 1 }
            io.print("input: \(config.inputLanguages.map(\.rawValue).joined(separator: ", ")) (typing starts in \(config.defaultInput.rawValue))")
            return 0

        case "show-config":
            guard let config = load() else { return 1 }
            io.print("config: \(shown(url))\(exists ? "" : " (none yet: the defaults)")")
            io.print("provider: \(config.provider.rawValue) (\(config.provider.displayName))")
            if config.provider == .bedrock {
                io.print("model: \(config.modelId), AWS profile \(config.awsProfile)")
            } else {
                let settings = config.settings(for: config.provider)
                io.print("model: \(settings.model ?? "-")" + (settings.baseURL.map { ", \($0)" } ?? ""))
            }
            for provider in [Provider.anthropic, .openai, .gemini] {
                let source: String
                switch APIKeys.source(provider) {
                case .keychain:
                    source = "saved" + (APIKeys.keyEnding(account: provider.rawValue).map { " (…\($0))" } ?? "")
                case let .environment(name): source = "from \(name)"
                case .none: source = "none"
                }
                io.print("key \(provider.rawValue): \(source)")
            }
            if config.provider == .hosted {
                io.print("AllInOneIME Cloud needs a sign-in, which Windows doesn't have yet: set a provider and its key")
            }
            io.print("input: \(config.inputLanguages.map(\.rawValue).joined(separator: ", ")) (typing starts in \(config.defaultInput.rawValue))")
            io.print("output: \(config.outputLanguages.map(\.code).joined(separator: ", "))")
            io.print("action key: \(config.actionKey)")
            return 0

        default:
            io.fail("unknown command \(command)\n\(usage)")
            return 2
        }
    }

    /// A file's path as Windows writes it.
    static func shown(_ url: URL) -> String {
        #if os(Windows)
        url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } ?? url.path }.replacingOccurrences(of: "/", with: "\\")
        #else
        url.path
        #endif
    }

    static func settings(of config: Config, _ provider: Provider) -> ProviderSettings {
        switch provider {
        case .anthropic: return config.anthropic
        case .gemini: return config.gemini
        case .openai: return config.openai
        default: return ProviderSettings()
        }
    }

    static func set(_ config: inout Config, _ provider: Provider, _ settings: ProviderSettings) {
        switch provider {
        case .anthropic: config.anthropic = settings
        case .gemini: config.gemini = settings
        case .openai: config.openai = settings
        default: break
        }
    }
}
