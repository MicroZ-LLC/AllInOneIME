import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// When a custom suggestions command's program runs, as Settings says it and as it is (spec Suggestions v1, decision 24;
/// final review, low 5): its list is loaded when a text field gets the focus (nothing of the field is given to it, so it
/// may be a password field), then at its refresh interval; a query runs only with what is typed after the prefix, and
/// never in a password field (secure input on, or one Accessibility tells). The Mac's key handling is
/// `SuggestionsSessionTests`' (`typeAsTheMac`).
extension SuggestionsSessionTests {
    /// The editor's line about the program (the settings document's, Windows' too), and the status of one not loaded
    /// yet, say when it runs: its list at the focus, not when its prefix is typed.
    @Test func theSettingsSayWhenTheProgramRuns() async throws {
        try await inEnglish {
            for terms in [PlatformTerms.mac, .windows] {
                let field = try #require(SettingsSchema.commandSchema(terms).first { $0.id == "suggestionsProgram" })
                let text = try #require(field.value?.string)
                #expect(text.contains("for its list when a text field gets the focus (it may be a password field: nothing of the field is given to it), then at the refresh interval"),
                        "\(text)")
                #expect(text.contains("with what you type after the prefix as one argument, never in a password field"), "\(text)")
                #expect(!text.contains("when you type the prefix"), "\(text)")
            }
            let jira = CustomCommand(name: "jira", type: .suggestions, argv: ["jira-list"], prefix: "JIRA-")
            #expect(jira.suggestionsState(.default, status: nil)?.text == "Not loaded yet: it loads when a text field next gets the focus.")
        }
    }

    /// As it is: the list loads at a field's focus, nothing typed, with no argument (the program is given nothing of the
    /// field: `CommandCompletionRuntime` takes the command alone); what is typed after the prefix is looked up only in
    /// a field that is no password field, never where Accessibility tells one or secure input is on.
    @Test func theListLoadsAtTheFocusAndQueriesNeverInAPasswordField() async throws {
        try await inEnglish {
            let programs = CommandsFromAnotherMacTests.Programs()
            let world = SuggestionsWorld()
            var jira = CommandsFromAnotherMacTests.jira()
            (jira.query, jira.queryMinChars) = (true, 1)
            world.switches.commands = [jira]
            let field = world.field { $0.suggestions.commandRuntime = programs }
            #expect(field.settle { !programs.all.isEmpty }, "the list, at the focus")
            #expect(programs.all == [CommandsFromAnotherMacTests.Programs.Run(argv: CommandsFromAnotherMacTests.program)],
                    "nothing typed, no argument: \(programs.all)")

            // A password field Accessibility tells, secure input off: nothing typed there is looked up.
            typeAsTheMac("JIRA-12", into: field, passwordField: true)
            field.idle()
            #expect(programs.all.count == 1 && field.rows.isEmpty, "\(programs.all)")
            // Secure input on: neither.
            world.secureInputAnywhere = true
            field.host.focus()
            field.host.document = ""
            field.type("JIRA-12")
            field.idle()
            #expect(programs.all.count == 1 && field.rows.isEmpty, "\(programs.all)")

            // A field that is none: looked up, with what follows the prefix only.
            world.secureInputAnywhere = false
            field.host.focus()
            field.host.document = ""
            typeAsTheMac("JIRA-12", into: field, passwordField: false)
            #expect(field.settle { programs.all.contains { $0.query != nil } }, "\(programs.all)")
            #expect(programs.all.compactMap(\.query).allSatisfy { "12".hasPrefix($0) }, "\(programs.all)")
        }
    }
}
