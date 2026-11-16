import Foundation

extension Config {
    /// `questionContinueIn` as the file has it: names this version doesn't know (a service a later one added) are left
    /// out, not an error.
    static func questionContinueIn(in c: KeyedDecodingContainer<CodingKeys>) -> [ChatHandoff.Destination]? {
        (try? c.decodeIfPresent([String].self, forKey: .questionContinueIn)).flatMap { $0 }?
            .compactMap(ChatHandoff.Destination.init(rawValue:))
    }

    /// `questionBackend` as the file has it: one this version doesn't know (a later one's), and 0.7.4's "provider", are
    /// none: the AI is the provider. Gemini CLI's session (0.7.4's earlier builds) is Antigravity's
    /// (`QuestionBackend.init(file:)`).
    static func questionBackend(in c: KeyedDecodingContainer<CodingKeys>) -> QuestionBackend? {
        (try? c.decodeIfPresent(String.self, forKey: .questionBackend)).flatMap { $0 }
            .flatMap(QuestionBackend.init(file:)).flatMap { $0 == .provider ? nil : $0 }
    }

    /// The `@question` settings and the sessions' MCP servers: rounds only when set, the MCP servers only once some are
    /// checked, so that a file that never had them doesn't gain them.
    func encodeQuestions(into c: inout KeyedEncodingContainer<CodingKeys>) throws {
        try c.encode(rememberQuestions, forKey: .rememberQuestions)
        // Only when set: a file that never had them doesn't gain them.
        if questionRounds != QuestionChat.defaultRounds { try c.encode(questionRounds, forKey: .questionRounds) }
        try c.encodeIfPresent(questionContinueIn, forKey: .questionContinueIn)
        try c.encodeIfPresent(questionBackend, forKey: .questionBackend)
        try c.encodeIfPresent(sessionMCP.isEmpty ? nil : sessionMCP, forKey: .sessionMCP)
    }
}
