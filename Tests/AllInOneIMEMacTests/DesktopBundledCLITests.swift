import Foundation
import Testing

/// A CLI that only came with a desktop app (`ClaudeSessionMac.desktopBundled`: the Claude app's Claude Code, the ChatGPT
/// app's codex, agy where its installer puts it) is looked for in the apps' own layout, as the input method finds it:
/// no environment variable switches the lookup off (the input method's sources and `make test` name none; read from
/// them: the executable target can't be linked into a test).
struct DesktopBundledCLITests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func noTestVariableSwitchesTheLookupOff() throws {
        let folder = Self.root.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        let texts = try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
        #expect(texts.filter { $0.1.contains("ALLINONEIME_NO_DESKTOP_CLIS") }.map(\.0).isEmpty)
        let makefile = try String(contentsOf: Self.root.appendingPathComponent("Makefile"), encoding: .utf8)
        #expect(!makefile.contains("ALLINONEIME_NO_DESKTOP_CLIS"))
    }
}
