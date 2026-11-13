import AllInOneIMECore
import AllInOneIMEMac
import Foundation
import Testing

/// A test doesn't find a CLI that only came with a desktop app on the Mac running it: it puts its own lookup in place of
/// the apps' layout (`DesktopCLILookup.inject`), which `ClaudeSessionMac.desktopBundled` goes through (read from the input
/// method's sources: the executable target can't be linked into a test). No environment variable switches it: the input
/// method reads none for it, and never injects a lookup. Serialized: the lookup injected is the process's.
@Suite(.serialized) struct DesktopCLILookupIsolationTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func anInjectedLookupTakesThePlaceOfTheAppsLayout() {
        let fake = URL(fileURLWithPath: "/tmp/test-codex")
        DesktopCLILookup.inject { $0 == .codex ? fake : nil }
        defer { DesktopCLILookup.inject(nil) }
        let layout: (SessionAgent) -> URL? = { agent in
            Issue.record("the apps' layout looked at for \(agent) with a lookup injected")
            return URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex")
        }
        #expect(DesktopCLILookup.bundled(.codex, layout: layout) == fake)
        #expect(DesktopCLILookup.bundled(.claude, layout: layout) == nil)
    }

    @Test func withoutOneTheAppsLayoutIsLookedAt() {
        let bundled = URL(fileURLWithPath: "/tmp/bundled-codex")
        #expect(DesktopCLILookup.bundled(.codex, layout: { $0 == .codex ? bundled : nil }) == bundled)
        #expect(DesktopCLILookup.bundled(.claude, layout: { $0 == .codex ? bundled : nil }) == nil)
    }

    @Test func theInputMethodGoesThroughItAndNoTestVariableSwitchesIt() throws {
        let mac = try String(contentsOf: Self.root.appendingPathComponent("Sources/AllInOneIME/ClaudeSessionMac.swift"),
                             encoding: .utf8)
        let start = try #require(mac.range(of: "static func desktopBundled("))
        let body = mac[start.upperBound...].drop { $0 != "{" }.dropFirst().prefix(200)
        let first = body.split(separator: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(first?.trimmingCharacters(in: .whitespaces) == "DesktopCLILookup.bundled(agent, layout: appLayout)",
                "the first thing it does: \(first ?? "")")
        // Neither the input method's sources nor `make test` name the environment switch there was, and nothing in the
        // input method injects a lookup.
        let folder = Self.root.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        let texts = try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
        #expect(texts.filter { $0.1.contains("ALLINONEIME_NO_DESKTOP_CLIS") }.map(\.0).isEmpty)
        #expect(texts.filter { $0.1.contains("DesktopCLILookup.inject") }.map(\.0).isEmpty)
        let makefile = try String(contentsOf: Self.root.appendingPathComponent("Makefile"), encoding: .utf8)
        #expect(!makefile.contains("ALLINONEIME_NO_DESKTOP_CLIS"))
    }
}
