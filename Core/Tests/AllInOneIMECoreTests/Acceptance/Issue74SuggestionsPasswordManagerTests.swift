import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Password managers have no suggestion rows or source lookups, including plain text fields that may display secrets.
@Suite(.serialized, SuggestionsOneAtATime())
struct Issue74SuggestionsPasswordManagerTests {
    @Test(arguments: ["com.1password.1password", "com.bitwarden.desktop"])
    func passwordManagerHasNoSuggestionClass(_ app: String) {
        #expect(PasswordManagers.contains(app))
        #expect(SuggestionsAppClass(app: app, terminal: false) == .none)
    }

    @Test(arguments: ["com.1password.1password", "com.bitwarden.desktop"])
    func typingSourcePrefixInPasswordManagerNeverCallsLookup(_ app: String) async throws {
        try await withInterfaceLanguage("en") {
            let world = SuggestionsWorld()
            try world.github()
            let field = world.field(app: app)
            field.type("#70")
            field.idle()
            #expect(field.rows.isEmpty, "a password manager shows no suggestion rows")
            #expect(world.runtime.loads.isEmpty, "the source list must not be loaded")
            #expect(world.runtime.queries.isEmpty, "typed text must not reach the source query")
        }
    }
}
