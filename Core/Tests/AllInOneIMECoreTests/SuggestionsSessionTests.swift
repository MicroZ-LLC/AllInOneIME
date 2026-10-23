import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Suggestions through a text field's session beyond the acceptance tests: what an approval covers. The rig:
/// Acceptance/SuggestionsAcceptanceTests.swift.
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsSessionTests {
    func inEnglish(_ body: () throws -> Void) rethrows { try withInterfaceLanguage("en", body) }

    enum Change: String, CaseIterable, Sendable {
        case prefix, queryMinChars, compare
    }

    /// Enabling a source approves what its switch said (spec 1.5: "sends what you type after # to api.github.com"): an
    /// update that changes its prefix, how much is typed before its query is first asked, or how it compares needs
    /// enabling again; until then nothing is sent, and Settings says why.
    @Test(arguments: Change.allCases)
    func anApprovalCoversThePrefixAndWhenTheQueryIsAsked(_ change: Change) throws {
        try inEnglish {
            let world = SuggestionsWorld()
            let plugin = try world.github(enable: false)
            let issues = try #require(plugin.manifest.completions.first)
            world.switches.enabled = [try #require(CompletionSourceApproval(enabling: issues, of: plugin))]
            let warm = world.field()
            warm.type("#7")
            #expect(warm.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "\(warm.issuesShown)")

            var manifest = SuggestionsPlugins.githubManifest()
            switch change {
            case .prefix: manifest = manifest.replacingOccurrences(of: ##""prefix": "#""##, with: ##""prefix": "GH-""##)
            case .queryMinChars: manifest = manifest.replacingOccurrences(of: #""queryMinChars": 2"#, with: #""queryMinChars": 1"#)
            case .compare: manifest = manifest.replacingOccurrences(of: #""compare": "prefix""#, with: #""compare": "exact""#)
            }
            #expect(manifest != SuggestionsPlugins.githubManifest())
            let updated = try #require(try SuggestionsPlugins.install(manifest, in: world.folder))
            let changed = try #require(updated.manifest.completions.first)
            world.plugins = [updated]
            let typed = change == .prefix ? "GH-70" : "#70"
            let calls = world.runtime.calls.count
            let field = world.field(app: "com.apple.TextEdit")
            field.type(typed)
            field.idle()
            #expect(field.rows.isEmpty, "\(change) changed: off (\(field.issuesShown))")
            #expect(world.runtime.calls.count == calls, "\(change) changed: nothing sent (\(world.runtime.queries))")
            #expect(world.switches.enabled.first?.holds(for: changed, of: updated) == false, "Settings: enable it again")

            world.switches.enabled = [try #require(CompletionSourceApproval(enabling: changed, of: updated))]
            field.host.send(.configChanged)
            field.type(" " + typed)
            #expect(field.settle { world.runtime.queries.count > 0 }, "enabled again: asked (\(world.runtime.calls.count) calls)")
        }
    }
}
