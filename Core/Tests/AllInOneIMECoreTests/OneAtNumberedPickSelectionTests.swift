import Testing
@testable import AllInOneIMECore

/// ⌥ and a digit while the selection read after "@" is in flight (the Mac's Accessibility read, `selectionFollows`):
/// taken as a click on that row is, the row parked until the read lands, so the selection that lands is the row's text
/// (review of #99: it used to settle the read as nothing selected and drop it).
extension OneAtTests {
    @Test func aNumberedPickWaitsForTheSelectionReadAsAClickDoes() async throws {
        try await withInterfaceLanguage("en") {
            let optionOne = KeyEvent(keyCode: 0x12, characters: "¡", charactersIgnoringModifiers: "1", modifiers: .option)
            let host = reading(selected: true)
            let first = try #require(host.composer.oneAtVisible.first)
            #expect(host.press(optionOne), "taken at once")
            #expect(host.composer.selectionPending && host.composer.parkedForSelection == .row(first),
                    "parked on its row, the read still awaited: \(String(describing: host.composer.parkedForSelection))")
            #expect(host.document == "hello there" && !host.composer.isLevelTwo, "nothing done on the key")
            host.answerFieldReads()
            // The same as a click on that row in the same state (`chooseOneAt` parks it), the selection kept for it.
            let clicked = reading(selected: true)
            _ = clicked.composer.choose(index: 0)
            clicked.answerFieldReads()
            #expect(host.composer.selection?.text == "hello there" && clicked.composer.selection?.text == "hello there",
                    "the selection kept, not dropped")
            #expect(host.composer.draft == clicked.composer.draft && host.composer.draftCommand == clicked.composer.draftCommand
                    && host.composer.isLevelTwo == clicked.composer.isLevelTwo,
                    "as the click: \(host.composer.draft) / \(clicked.composer.draft)")
            #expect(host.platformActions.isEmpty)
        }
    }
}
