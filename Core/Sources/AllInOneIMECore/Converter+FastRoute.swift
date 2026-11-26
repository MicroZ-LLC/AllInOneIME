import Foundation

/// Where a request that has to be fast goes (rewriting, translating, a reply, a custom prompt command, autocomplete),
/// with the AI chosen (`Config.ai`): with a provider, that provider; with a CLI, its fast fallback
/// (`Config.fastProvider`), else, with none, the CLI's session (`slow`), a second or more an answer.
struct FastRoute {
    /// The settings the request is made with: the fast fallback as the provider.
    var config: Config
    /// No fast provider can answer: the request goes to the CLI's `session` (none: it fails, `ClaudeSessionError
    /// .notInstalled`).
    var slow = false
    var session: ClaudeSessionManager?

    /// What the request's answer is cached under: the model, or the session's agent.
    var model: String {
        guard slow else { return config.activeModel }
        return "session:" + (session?.backend.agent.rawValue ?? "none")
    }
}

extension Converter {
    /// The settings a request that has to be fast is made with in `app` (`settings`, then `fast`).
    func fastSettings(app: String?) throws -> FastRoute {
        fast(try Self.settings(try loadConfig(), app: app))
    }

    /// `config` for a request that has to be fast (`FastRoute`): with a CLI chosen as the AI, its fast fallback put in as
    /// the provider (`fastConfig`), or none.
    func fast(_ config: Config) -> FastRoute {
        guard let fast = fastConfig(config) else { return FastRoute(config: config, slow: true, session: questionSession(config)) }
        return FastRoute(config: fast)
    }

    /// The settings what has to be fast is asked with, as a request finds them (`Config.fastConfig` by `isReady`: the
    /// keychain, the shell's variables, the AWS profile's files; never on the main thread): `config` with a provider
    /// chosen; with a CLI, its fast fallback's; nil: a CLI and no faster AI. What a shell's autocomplete switch shows
    /// (the Mac's input menu and menu-bar panel), as the field's own route goes (`InputSession.autocompleteLookUpRoute`).
    ///
    /// `readingKeys` false: a key is looked for by its item's attributes alone (`hasKey`), never read: what a switch
    /// shows while autocomplete is off, when no request is about to be made (reading a key may make the system ask for
    /// the login password, after an update signed otherwise).
    public func fastConfig(_ config: Config, readingKeys: Bool = true) -> Config? {
        guard case .cli = config.ai else { return config }
        return config.fastConfig(ready: { readingKeys ? isReady($0, config: config) : hasKey($0, config: config) },
                                 apple: client.apple.availability)
    }

    /// `isReady` without reading a key: for a provider with one, whether there is a key that goes to its base URL's
    /// host, by the keychain item's attributes and the login shell's variables (`APIKeys.Source.sent(by:to:savedFor:)`,
    /// as Settings' key rows tell it).
    func hasKey(_ provider: Provider, config: Config) -> Bool {
        switch provider {
        case .apple, .bedrock:
            return isReady(provider, config: config)
        case .anthropic, .gemini, .openai, .hosted:
            guard let host = HTTPProviders.host(of: config.settings(for: provider)) else { return false }
            return APIKeys.source(provider).sent(by: provider, to: host, savedFor: APIKeys.savedHost(provider)) != .none
        }
    }

    /// Whether `provider` has what it needs to answer, as a request to it would find it (`AIStatus.isReady`): a key for its
    /// base URL (`loadKey`), the hosted service's sign-in, the AWS profile (`hasAWSProfile`), Apple's model available.
    func isReady(_ provider: Provider, config: Config) -> Bool {
        switch provider {
        case .apple:
            return client.apple.availability == .available
        case .bedrock:
            return hasAWSProfile(config.awsProfile)
        case .anthropic, .gemini, .openai, .hosted:
            guard let host = HTTPProviders.host(of: config.settings(for: provider)),
                  let key = (try? loadKey(provider, host)) ?? nil else { return false }
            return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// A `Redaction` for `route`'s request, its texts hidden by `body`: numbered on from the session's earlier questions
    /// when the request goes to the CLI's session (one long conversation, `ClaudeSessionManager.redacting`), else a new one.
    func redacting<T>(_ route: FastRoute, _ body: (inout Redaction?) -> T) -> (redaction: Redaction?, result: T) {
        if route.slow, let session = route.session { return session.redacting(route.config.redaction, body) }
        var redaction = Redaction(route.config.redaction)
        let result = body(&redaction)
        return (redaction, result)
    }

    /// `request` sent where `route` says: the fast provider (`ChatClient.stream`), or the CLI's session.
    func stream(_ request: ConverseRequest, _ route: FastRoute) -> AsyncThrowingStream<BedrockStreamEvent, Error> {
        guard route.slow else {
            return client.stream(request, config: route.config, loadCredentials: loadCredentials, loadKey: loadKey)
        }
        guard let session = route.session else {
            return AsyncThrowingStream { $0.finish(throwing: ClaudeSessionError.notInstalled) }
        }
        return Self.sessionStream(request, session: session)
    }

    /// `request` asked of a CLI's `session` as one message (`sessionMessage`), its answer as a provider's stream gives
    /// it: the whole text so far each time more comes, then the end. What the session fails with is said for its agent.
    /// Each request is a conversation of its own (`QuestionConversation.oneOff`), never one of the `@question`
    /// conversations, with no web tools: what it rewrites, translates or replies to is often text the user didn't type (a
    /// selection, a message), which could tell the agent to send it somewhere. Both go with the request as it is made
    /// (`ClaudeSessionManager.ask(_:in:)`), however long it waits behind a question being answered.
    static func sessionStream(_ request: ConverseRequest, session: ClaudeSessionManager) -> AsyncThrowingStream<BedrockStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await text in session.ask(sessionMessage(request), in: .oneOff) {
                        continuation.yield(.textReplaced(text))
                    }
                    continuation.yield(.messageStop(reason: "end_turn"))
                    continuation.finish()
                } catch let error as ClaudeSessionError {
                    continuation.finish(throwing: ClaudeSessionError.failed(error.description(for: session.backend.agent)))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A request as one message to a CLI's session: its instructions (what a provider gets as the system prompt), then
    /// its messages, an earlier answer marked as the session's own. The session's own instructions are for questions, so
    /// it is told that this is a writing task first.
    static func sessionMessage(_ request: ConverseRequest) -> String {
        let instructions = request.system.map(\.text).joined(separator: "\n\n")
        let messages = request.messages.map { message in
            let text = message.content.map(\.text).joined(separator: "\n")
            return message.role == "assistant" ? "Your earlier answer:\n" + text : text
        }
        return "This is a writing task, not a question: follow these instructions exactly and write only what they ask for.\n\n"
            + "<instructions>\n" + instructions + "\n</instructions>\n\n" + messages.joined(separator: "\n\n")
    }
}
