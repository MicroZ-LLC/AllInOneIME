import Foundation
import Testing

/// The test runs don't find a CLI that only came with a desktop app (`ClaudeSessionMac.desktopBundled`, read from the
/// input method's sources: the executable target can't be linked into a test): `make test` sets
/// ALLINONEIME_NO_DESKTOP_CLIS for both packages' tests (and so for the input method they start), and the lookup finds
/// nothing then, so the Claude app's Claude Code or the ChatGPT app's codex on the Mac running them is never taken for a
/// test's own CLIs, or for none. The input method itself never sets it: there, the lookup is as before.
struct DesktopCLILookupIsolationTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let variable = "ALLINONEIME_NO_DESKTOP_CLIS"

    func text(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func theLookupFindsNothingWhenTheVariableIsSet() throws {
        let mac = try text("Sources/AllInOneIME/ClaudeSessionMac.swift")
        #expect(mac.contains("static let noDesktopBundledVariable = \"\(Self.variable)\""))
        let start = try #require(mac.range(of: "static func desktopBundled("))
        let body = mac[start.upperBound...].drop { $0 != "{" }.dropFirst().prefix(200)
        let first = body.split(separator: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(first?.trimmingCharacters(in: .whitespaces)
                == "guard ProcessInfo.processInfo.environment[noDesktopBundledVariable] == nil else { return nil }",
                "the first thing it does: \(first ?? "")")
    }

    @Test func makeTestSetsItForBothPackagesTests() throws {
        let makefile = try text("Makefile")
        #expect(makefile.contains("TEST_DESKTOP := \(Self.variable)=1"))
        let runs = makefile.split(separator: "\n").filter { $0.contains("swift test") && $0.contains("$(TEST_AWS)") }
        #expect(runs.count == 2 && runs.allSatisfy { $0.contains("$(TEST_DESKTOP)") }, "\(runs)")
    }

    @Test func theInputMethodNeverSetsIt() throws {
        let folder = Self.root.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        let naming = try files.filter { try String(contentsOf: $0, encoding: .utf8).contains(Self.variable) }
        #expect(naming.map(\.lastPathComponent) == ["ClaudeSessionMac.swift"], "\(naming.map(\.path))")
    }
}
