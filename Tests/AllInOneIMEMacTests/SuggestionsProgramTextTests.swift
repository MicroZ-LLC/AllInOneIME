import Foundation
import Testing

/// The Mac's command editor says when a suggestions command's program runs in the core's words, the settings
/// document's (`UIText.suggestionsProgramRuns`): its list as a text field takes the focus, never "when you type the
/// prefix". Read from the source, as the editor can't be drawn here.
struct SuggestionsProgramTextTests {
    @Test func theEditorSaysWhenTheProgramRunsAsTheCoreDoes() throws {
        let url = StringCatalogTests.root.appendingPathComponent("Sources/AllInOneIME/CommandEditor.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(source.contains("UIText.suggestionsProgramRuns(on: .mac)"))
        #expect(!source.contains("when you type the prefix"))
    }
}
