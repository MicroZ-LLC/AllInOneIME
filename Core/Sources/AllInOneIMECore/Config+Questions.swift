import Foundation

extension Config {
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
