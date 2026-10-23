import Foundation

/// The models that refuse a temperature: reasoning models, and ones that won't take it along with top_p ("temperature
/// and top_p cannot both be specified"). A request whose temperature such a model refuses before any answer goes again
/// once without it (`adapting`), and the model is remembered by provider and model: for the process, and in
/// `unsupported-temperature.json` among the caches (`CorePaths.cacheDir`), never in config.json. Its requests then go
/// without a temperature from the start; every other model still gets the one the user set (on Bedrock, the request's own
/// where it has one: the Assistant's and Check for problems' 0; the Claude API and OpenAI-compatible services send the
/// provider's settings' one, `HTTPProviders.makeRequest`). Only the providers' and models' names are kept: no request,
/// answer or key. Bedrock, the Claude API and OpenAI-compatible services use it; Gemini and AllInOneIME Cloud send theirs
/// as before. Settings → AI Provider says how many are remembered and forgets them (`models`, `forget`).
public final class TemperatureSupport: Sendable {
    /// The app's own (`BedrockClient()`'s): in the caches.
    public static let shared = TemperatureSupport(file: CorePaths.cacheDir.appendingPathComponent("unsupported-temperature.json"))

    /// Where the models are kept (nil: for the process only).
    let file: URL?
    /// "provider:model" of each, read from `file` on first use.
    private let refused = Locked<Set<String>?>(initialState: nil)

    init(file: URL?) {
        self.file = file
    }

    func omits(_ provider: Provider, model: String) -> Bool {
        refused.withLock { refused in
            let known = refused ?? Self.read(file)
            refused = known
            return known.contains(Self.key(provider, model))
        }
    }

    func remember(_ provider: Provider, model: String) {
        refused.withLock { refused in
            var known = refused ?? Self.read(file)
            guard known.insert(Self.key(provider, model)).inserted else { return }
            // What another process (allinoneime-cli) added meanwhile stays.
            known.formUnion(Self.read(file))
            refused = known
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            guard let file, let data = try? encoder.encode(known.sorted()) else { return }
            // A cache: kept in memory when it can't be written.
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }

    /// The models remembered, "provider:model", sorted (another process's added since too).
    public var models: [String] {
        refused.withLock { refused in
            let known = (refused ?? []).union(Self.read(file))
            refused = known
            return known.sorted()
        }
    }

    /// Every model remembered forgotten, here and in `file` (another process, the command line, as it next starts): each
    /// gets the temperature again, and one that still refuses it is asked again without it, once, and remembered again.
    public func forget() {
        refused.withLock { refused in
            refused = []
            if let file { try? FileManager.default.removeItem(at: file) }
        }
    }

    private static func key(_ provider: Provider, _ model: String) -> String { provider.rawValue + ":" + model }

    private static func read(_ file: URL?) -> Set<String> {
        guard let file, let data = try? Data(contentsOf: file), let names = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(names)
    }

    /// The answer to a request that has a temperature: `send(false)` sends it as it is, `send(true)` without the
    /// temperature. A model that refused one before gets it without at once; else, refused for it before any answer came
    /// (`refuses`), the request goes again without it, once, and the model is remembered when that is answered.
    func adapting(_ provider: Provider, model: String,
                  _ send: @escaping @Sendable (_ withoutTemperature: Bool) -> AsyncThrowingStream<BedrockStreamEvent, Error>)
        -> AsyncThrowingStream<BedrockStreamEvent, Error> {
        if omits(provider, model: model) { return send(true) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                var without = false
                while true {
                    var answered = false
                    do {
                        for try await event in send(without) {
                            if without, !answered { self.remember(provider, model: model) }
                            answered = true
                            continuation.yield(event)
                        }
                        if without, !answered { self.remember(provider, model: model) }
                        continuation.finish()
                        return
                    } catch {
                        guard !without, !answered, !Task.isCancelled, Self.refuses(error) else {
                            continuation.finish(throwing: error)
                            return
                        }
                        without = true
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Whether `error` refused the request for its temperature, or for top_p, which some models won't take along with
    /// one: a validation error that names either. With an HTTP status, 400 or 422 (Bedrock's ValidationException, the
    /// Claude API's and OpenAI's invalid_request_error, a compatible service's bad request); in the stream, an error of a
    /// type that says so (Bedrock's validationException).
    static func refuses(_ error: Error) -> Bool {
        let status: Int?, type: String?, message: String
        if case let .http(code, kind, text)? = error as? BedrockError {
            (status, type, message) = (code, kind, text)
        } else if case let .stream(kind, text)? = error as? BedrockError {
            (status, type, message) = (nil, kind, text)
        } else if case let .http(_, code, kind, text)? = error as? ProviderError {
            (status, type, message) = (code, kind, text)
        } else if case let .stream(_, kind, text)? = error as? ProviderError {
            (status, type, message) = (nil, kind, text)
        } else {
            return false
        }
        let text = message.lowercased()
        guard ["temperature", "top_p", "top-p", "topp"].contains(where: text.contains) else { return false }
        if let status { return status == 400 || status == 422 }
        let kind = (type ?? "").lowercased()
        return ["validation", "invalid", "bad_request", "badrequest"].contains(where: kind.contains)
    }
}
