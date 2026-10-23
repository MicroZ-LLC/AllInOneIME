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

extension SuggestionsSessionTests {
    /// Each call into a plugin's script carries the hosts the user approved with the source: its child process fetches
    /// from those only (that plugin.json still lists, `PluginHost.completion`).
    @Test func theCallsCarryTheApprovedHosts() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let field = world.field()
            field.type("#70")
            #expect(field.settle { !world.runtime.loads.isEmpty && !world.runtime.queryCalls.isEmpty }, "\(world.runtime.calls.count) calls")
            let calls = world.runtime.loads + world.runtime.queryCalls
            #expect(calls.allSatisfy { $0.hosts == ["api.github.com"] }, "\(calls.map(\.hosts))")
        }
    }
}

extension SuggestionsSessionTests {
    enum Gone: String, CaseIterable, Sendable {
        case uninstalled, updated
    }

    /// An approval that no longer holds (its plugin removed, or updated since in a way that needs enabling again) is
    /// dropped (the shell takes it out of the settings) and the source's cached list deleted, in memory and on disk:
    /// the same plugin installed again asks again.
    @Test(arguments: Gone.allCases)
    func anApprovalThatNoLongerHoldsIsDroppedWithItsCache(_ gone: Gone) throws {
        try inEnglish {
            let world = SuggestionsWorld()
            let cache = world.folder.appendingPathComponent("cache", isDirectory: true)
            world.cacheFolder = cache
            let plugin = try world.github(enable: false)
            let issues = try #require(plugin.manifest.completions.first)
            let approval = try #require(CompletionSourceApproval(enabling: issues, of: plugin))
            world.switches.enabled = [approval]
            let lapsed = Locked<[CompletionSourceApproval]>(initialState: [])
            func field() -> SuggestionsField {
                world.field(app: "com.apple.TextEdit") { services in
                    services.suggestions.approvalsLapsed = { dropped in
                        lapsed.withLock { $0 += dropped }
                        world.switches.enabled.removeAll { dropped.contains($0) }
                    }
                }
            }
            let file = cache.appendingPathComponent("github.issues.json")
            let first = field()
            first.type("#7")
            #expect(first.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "\(first.issuesShown)")
            #expect(first.settle { FileManager.default.fileExists(atPath: file.path) }, "cached")
            #expect(lapsed.withLock { $0 }.isEmpty, "it holds: kept")

            switch gone {
            case .uninstalled: world.plugins = []
            case .updated:
                let script = SuggestionsPlugins.script + "\nfunction extra() { return 1; }\n"
                world.plugins = [try #require(try SuggestionsPlugins.install(SuggestionsPlugins.githubManifest(), script: script, in: world.folder))]
            }
            let next = field()
            #expect(lapsed.withLock { $0 } == [approval], "\(gone): dropped (\(lapsed.withLock { $0 }))")
            #expect(next.settle { !FileManager.default.fileExists(atPath: file.path) }, "\(gone): its cached list deleted")

            // The plugin as it was, again: off until enabled again; nothing listed from before.
            world.plugins = [try #require(try SuggestionsPlugins.install(SuggestionsPlugins.githubManifest(), in: world.folder))]
            let calls = world.runtime.calls.count
            let again = field()
            again.type("#7")
            again.idle()
            #expect(again.rows.isEmpty && world.runtime.calls.count == calls, "\(gone), installed again: asks again (\(again.issuesShown))")
        }
    }
}

extension SuggestionsSessionTests {
    /// The list cached on disk (up to 4 MB of JSON) is read and decoded off the session's thread (the main thread on the
    /// Mac): a key never waits for the disk, the cached list shows once read, and no load starts before it is.
    @Test func theCachedListIsReadOffTheSessionsThread() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            let cache = world.folder.appendingPathComponent("cache", isDirectory: true)
            world.cacheFolder = cache
            try world.github()
            world.runtime.holdLoads = true
            var cached = SuggestionsStore.Source()
            cached.list = CompletionItems([SuggestionsItems.issue(7001, "From the cache")])
            cached.loadedAt = world.clock.now
            SuggestionsStore.write(cached, of: CompletionSourceKey(plugin: "github", source: "issues"), in: cache)
            SuggestionsStore.disk.sync {}

            // The disk busy for a while (another list being written, a slow volume).
            let busy = DispatchSemaphore(value: 0)
            SuggestionsStore.disk.async { _ = busy.wait(timeout: .now() + 3) }
            let clock = ContinuousClock()
            var field: SuggestionsField?
            let took = clock.measure {
                field = world.field()
                field?.type("#7")
            }
            busy.signal()
            let typed = try #require(field)
            #expect(took < .milliseconds(500), "the focus and the keys waited for the disk: \(took)")
            #expect(typed.waitForIssues(["#7001"]), "the cached list, once read: \(typed.issuesShown)")
            #expect(world.runtime.loads.isEmpty, "fresh enough: no load (\(world.runtime.loads.count))")
            world.runtime.releaseAll()
        }
    }
}

extension SuggestionsSessionTests {
    /// Tab in a terminal or code editor completes what every item matching the token shares, not only the 5 rows shown:
    /// "#1" with #100–#104 and #1999 adds nothing (the shown five share "#10", #1999 doesn't), and the Tab is the
    /// terminal's; "#10" with #1000–#1004 and #10099 adds the "0" they all share.
    @Test func tabInATerminalCompletesWhatEveryMatchingItemShares() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github(items: [100, 101, 102, 103, 104, 1999].map { SuggestionsItems.issue($0, "Issue \($0)") })
            let field = world.field(app: "com.apple.Terminal", terminal: true)
            field.type("#1")
            #expect(field.waitForIssues(["#100", "#101", "#102", "#103", "#104"]), "\(field.issuesShown)")
            #expect(!field.press(SuggestionKeys.tab), "#1999 matches too: nothing all of them share, the terminal's Tab")
            #expect(field.document == "#1", "\(field.document)")

            let other = SuggestionsWorld()
            try other.github(items: [1000, 1001, 1002, 1003, 1004, 10099].map { SuggestionsItems.issue($0, "Issue \($0)") })
            let next = other.field(app: "com.apple.Terminal", terminal: true)
            next.type("#10")
            #expect(next.waitForIssues(["#1000", "#1001", "#1002", "#1003", "#1004"]), "\(next.issuesShown)")
            #expect(next.press(SuggestionKeys.tab) && next.document == "#100", "all six share #100: \(next.document)")
            #expect(!next.press(SuggestionKeys.tab), "nothing more in common: the terminal's Tab")
            #expect(next.document == "#100", "\(next.document)")
        }
    }
}
