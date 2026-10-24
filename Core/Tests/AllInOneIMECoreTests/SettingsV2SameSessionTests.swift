import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// The starting input learned from a second field of the same session (the independent review of 0.6.7): a page's next
/// field in Chrome, an Electron window's, keeps the last field's input, and a switch back to the app's own starting input
/// from there is no correction (Settings v2 §3.1: corrections count from the app's starting input).
@Suite(.serialized, SuggestionsOneAtATime())
struct SettingsV2SameSessionTests {
    @Test func aSwitchBackToTheAppsOwnInputInTheSameSessionTeachesNothing() async throws {
        try await withInterfaceLanguage("en") {
            let world = SettingsV2World()
            let app = SettingsV2Apps.notes
            let field = world.field(app)
            field.correct()  // Chinese → English, typed: English 1
            for _ in 0..<2 {
                field.host.send(.blur)
                field.host.focus()  // the same session's next field, still in English
                if field.host.composer.input != .language(.chinese) { field.correct() }  // back to Chinese, the app's own
                else { field.type("ok ") }
            }
            #expect(world.learnedInput(app) != .language(.chinese), "\(world.items().map(\.text))")
            #expect(!SettingsV2World.said(field).contains { $0.contains("from now on") }, "\(SettingsV2World.said(field))")
        }
    }
}
