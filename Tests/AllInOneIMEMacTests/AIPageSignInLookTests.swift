import Foundation
import Testing

/// Settings → AI looks at the CLIs' sign-in as little as it can (read from the input method's sources: the executable
/// target can't be linked into a test): the CLIs the page shows (#174: collapsed, the one in use; the others only while
/// choosing), each as last found unless that is too old (`ClaudeSessionManager.checkAvailability`'s cache,
/// tested in the core); only a refresh asked for forces a look.
struct AIPageSignInLookTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The Swift source at `path` without comments.
    func code(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in line.range(of: "//").map { line[..<$0.lowerBound] } ?? line }
            .joined(separator: "\n")
    }

    /// `code` from `start` to the end of its block (the first line closing at `start`'s indentation).
    func block(_ code: String, _ start: String) throws -> String {
        let begin = try #require(code.range(of: start))
        let lineStart = code[..<begin.lowerBound].lastIndex(of: "\n").map { code.index(after: $0) } ?? code.startIndex
        let indent = String(code[lineStart..<begin.lowerBound].prefix { $0 == " " })
        let rest = code[begin.lowerBound...]
        let end = rest.range(of: "\n" + indent + "}")?.upperBound ?? rest.endIndex
        return String(rest[..<end])
    }

    @Test func showingThePageLooksAtItsCLIsUnforced() throws {
        let settings = try code("Sources/AllInOneIME/ClaudeSessionSettings.swift")
        // Each look as the page shows, collapsed (the chosen row) or choosing (the cards), for the choices shown then.
        let page = try code("Sources/AllInOneIME/SettingsWindow.swift")
        let appears = (settings + "\n" + page).split(separator: "\n").filter { $0.contains(".onAppear {") && $0.contains("Shown(") }
        #expect(appears.count == 2, "\(appears)")
        #expect(appears.allSatisfy { $0.contains("model.aiPageShown()") }, "\(appears)")
        let shown = try block(settings, "func aiPageShown(")
        #expect(shown.contains("cards.choosing ? cards.visibleGroups.flatMap(\\.choices) : [cards.chosen]"), "\(shown)")
        #expect(shown.contains("refreshSessions(agents)") && !shown.contains("force"), "\(shown)")
        // The CLIs asked for, unforced.
        let refresh = try block(settings, "func refreshSessions(")
        #expect(refresh.contains("force: Bool = false") && refresh.contains("checkAvailability(agents, force: force)"), "\(refresh)")
        #expect(!settings.contains("refreshSessions(force: true)"), "a look forced where none was asked for")
    }

    @Test func aLookIsForcedOnlyWhenAskedFor() throws {
        let mac = try code("Sources/AllInOneIME/ClaudeSessionMac.swift")
        let check = try block(mac, "static func checkAvailability(")
        #expect(check.contains("force: Bool = false"), "\(check)")
        #expect(check.contains("force ? session.checkAvailability(force: true) : session.checkAvailability()"), "\(check)")
        #expect(check.contains("for (agent, session) in sessions") && !check.contains("in managers {"), "every CLI looked at: \(check)")
    }
}
