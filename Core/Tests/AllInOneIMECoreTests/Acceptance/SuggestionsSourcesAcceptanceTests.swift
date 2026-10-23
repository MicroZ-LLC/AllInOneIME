import Foundation
import Testing
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// Suggestions v1, spec 1.2 and 1.3: a source's list and its live query (merged, the query cancelled by a newer token,
/// its answers cached per prefix, asked again only as spec 6.4 says), the list refreshed (its age in the footer, a source
/// unused for 7 days, failures keeping the old list, backing off and pausing the source, what resumes it: spec 6.17;
/// "Refresh now"), the list cached on disk (6.17), what the script is told (`ctx`, the timeouts), and what the core makes
/// of the plugin's outputs (Fixtures/Suggestions/outputs/: good, oversized, not an object with items, control and bidi
/// characters, bad items dropped one by one, duplicates; spec 6.5, 6.6). The rig: SuggestionsAcceptanceTests.swift.
@Suite(.serialized, SuggestionsOneAtATime())
struct SuggestionsSourcesAcceptanceTests {
    func inEnglish(_ body: () throws -> Void) rethrows { try withInterfaceLanguage("en", body) }

    static let fixtureMatches = ["#6001", "#6002", "#6003", "#6004", "#6005", "#6007", "#6090", "#6800", "#9001", "#6066", "#6070"]
    static let allRows = ["#7001", "#7002", "#7090", "#7100", "#789"]

    // MARK: - List and query

    /// The query is called once the part after the prefix has `queryMinChars` characters, with that part only; its
    /// items come after the list's, one row per match (the list's first).
    @Test func theListAndTheQueryMerge() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            world.runtime.query("70", items: [SuggestionsItems.issue(7066, "Filed a minute ago"),
                                              SuggestionsItems.issue(7001, "From the query")])
            let field = world.field()
            field.type("#7")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]))
            field.idle()
            #expect(world.runtime.queries.isEmpty, "one character after the prefix: no query yet (\(world.runtime.queries))")
            field.type("0")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7066"]), "\(field.issuesShown)")
            #expect(world.runtime.queries == ["70"], "only the part after the prefix (\(world.runtime.queries))")
            let first = try #require(field.rows.first)
            #expect(!(first.text + first.comment).contains("From the query"), "the list's item, not the query's again")
        }
    }

    /// A newer token's query takes the place of one still running: the older call is cancelled, what it would have
    /// answered never shows.
    @Test func aNewerTokenCancelsTheQueryInFlight() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            world.runtime.query("70", items: [SuggestionsItems.issue(7066, "Late")])
            world.runtime.query("80", items: [SuggestionsItems.issue(8070, "Current")])
            world.runtime.holdQueries = true
            let field = world.field()
            field.type("#70")
            #expect(field.settle { world.runtime.waiting == ["70"] }, "\(world.runtime.waiting)")
            field.type(" #80")
            #expect(field.settle { world.runtime.queries.contains("80") }, "\(world.runtime.queries)")
            #expect(field.settle { world.runtime.cancelled.contains("70") }, "the older query is cancelled (\(world.runtime.cancelled))")
            world.runtime.release("80")
            world.runtime.release("70")
            #expect(field.waitForIssues(["#8001", "#8070"]), "\(field.issuesShown)")
            field.idle()
            #expect(!field.issuesShown.contains("#7066"))
        }
    }

    /// A query's answer is kept for its text: more characters typed filter it at once, and the same text typed again
    /// later asks nothing.
    @Test func queryAnswersAreCachedPerPrefixAndFilteredAsYouType() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let found = [SuggestionsItems.issue(7060, "Sixty"), SuggestionsItems.issue(7007, "Seven"),
                         SuggestionsItems.issue(7099, "Ninety-nine")]
            world.runtime.query("70", items: found)
            world.runtime.query("700", items: [SuggestionsItems.issue(7007, "Seven")])
            let field = world.field()
            field.type("#70")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7060", "#7007"]), "5 rows at most: \(field.issuesShown)")
            field.type("0")
            #expect(field.issuesShown == ["#7001", "#7002", "#7007"], "filtered at once, before any answer: \(field.issuesShown)")
            field.idle()
            #expect(field.issuesShown == ["#7001", "#7002", "#7007"], "\(field.issuesShown)")
            field.type(" #70")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7060", "#7007"]), "\(field.issuesShown)")
            #expect(world.runtime.queries.filter { $0 == "70" }.count == 1, "\"70\" asked once: \(world.runtime.queries)")
        }
    }

    /// A source without `query` is never queried, however much is typed.
    @Test func aSourceWithoutQueryIsNeverQueried() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github(manifest: SuggestionsPlugins.githubManifest(query: false))
            let field = world.field()
            field.type("#7009")
            field.idle()
            #expect(world.runtime.queries.isEmpty)
            #expect(world.runtime.loads.count == 1)
        }
    }

    /// Issues numbered `numbers`, as a query finds them.
    static func found(_ numbers: [Int]) -> [CompletionItem] { numbers.map { SuggestionsItems.issue($0, "Found \($0)") } }

    /// After the first query, another is asked only when what is kept of the answers (for the longest text asked) leaves
    /// fewer than 5 rows (spec 6.4): "#700" still has 8 of the answers for "70", nothing is asked; "#7001" has one, "7001"
    /// is asked.
    @Test func aQueryIsAskedAgainOnlyWhenTheKeptAnswersLeaveFewerThanFiveRows() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github(items: [])
            let found = Self.found(Array(7001...7008))
            world.runtime.query("70", items: found)
            world.runtime.query("7001", items: Self.found([7001]))
            let matches = found.map(\.match)
            let field = world.field()
            field.type("#70")
            #expect(field.settle { field.shown(matches) == ["#7001", "#7002", "#7003", "#7004", "#7005"] }, "\(field.rows.map(\.text))")
            #expect(world.runtime.queries == ["70"])
            field.type("0")
            field.idle(0.5)
            #expect(field.shown(matches) == ["#7001", "#7002", "#7003", "#7004", "#7005"], "\(field.rows.map(\.text))")
            #expect(world.runtime.queries == ["70"], "8 kept still match: nothing asked (\(world.runtime.queries))")
            field.type("1")
            #expect(field.settle { world.runtime.queries == ["70", "7001"] }, "one left: asked (\(world.runtime.queries))")
            #expect(field.settle { field.shown(matches) == ["#7001"] }, "\(field.rows.map(\.text))")
        }
    }

    /// A query asked again waits for a pause of 150 ms in typing (spec 6.4): nothing is asked while the keys come, then
    /// once, for the text they made.
    @Test func aQueryAskedAgainWaitsForAPauseInTyping() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github(items: [])
            let found = Self.found([7001, 7002, 7090, 7091, 7092])
            world.runtime.query("70", items: found)
            let field = world.field()
            field.type("#70")
            #expect(field.settle { field.shown(found.map(\.match)).count == 5 }, "\(field.rows.map(\.text))")
            #expect(world.runtime.queries == ["70"])
            field.type("0")
            field.idleWithoutTime(0.3)
            #expect(world.runtime.queries == ["70"], "\"#700\" leaves 2 rows, but no pause yet: \(world.runtime.queries)")
            field.type("1")
            field.idleWithoutTime(0.3)
            #expect(world.runtime.queries == ["70"], "\(world.runtime.queries)")
            field.pause(0.2)
            #expect(field.settle { world.runtime.queries == ["70", "7001"] }, "after the pause, once: \(world.runtime.queries)")
            field.idle(0.5)
            #expect(world.runtime.queries == ["70", "7001"], "\(world.runtime.queries)")
        }
    }

    /// One query at a time for a source (spec 6.4): one asked while another is out waits for it, or takes its place.
    @Test func oneQueryAtATimeForASource() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github(items: [])
            let found = Self.found([7001, 7002, 7090, 7091, 7092])
            world.runtime.query("70", items: found)
            world.runtime.query("7001", items: Self.found([7001]))
            world.runtime.holdQueries = true
            let field = world.field()
            field.type("#70")
            #expect(field.settle { world.runtime.waiting == ["70"] }, "\(world.runtime.waiting)")
            field.type("01")
            field.pause(0.2)
            field.idle(0.5)
            #expect(world.runtime.mostQueriesInFlight == 1, "\(world.runtime.mostQueriesInFlight) at once")
            world.runtime.holdQueries = false
            world.runtime.releaseAll()
            #expect(field.settle { field.shown(found.map(\.match)) == ["#7001"] }, "\(field.rows.map(\.text))")
            field.idle()
            #expect(world.runtime.mostQueriesInFlight == 1, "\(world.runtime.mostQueriesInFlight) at once")
        }
    }

    // MARK: - The list in memory, refreshed

    /// The list is kept in memory for every field: another field (another app) shows its rows without loading it again.
    @Test func theListIsKeptForEveryField() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let one = world.field()
            one.type("#7")
            #expect(one.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]))
            let other = world.field(app: "com.apple.TextEdit")
            other.type("#8")
            #expect(other.issuesShown == ["#8001"], "at once: \(other.issuesShown)")
            other.idle()
            #expect(world.runtime.loads.count == 1, "\(world.runtime.loads.count) loads")
        }
    }

    /// Past its `refresh` (15 minutes), the list is loaded again; meanwhile the old one shows.
    @Test func theListIsLoadedAgainOnceItsRefreshIsDue() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let field = world.field()
            field.type("#7")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]))
            #expect(world.runtime.loads.count == 1)
            world.clock.advance(10 * 60)
            field.fireTimers()
            field.type(" #7")
            field.idle()
            #expect(world.runtime.loads.count == 1, "not due yet: \(world.runtime.loads.count) loads")

            world.runtime.list("issues", items: [SuggestionsItems.issue(7055, "New since")] + SuggestionsItems.issues)
            world.runtime.holdLoads = true
            world.clock.advance(6 * 60)
            field.fireTimers()
            field.type(" #7")
            #expect(field.settle { world.runtime.loads.count == 2 }, "due: \(world.runtime.loads.count) loads")
            #expect(field.issuesShown == ["#7001", "#7002", "#7090", "#7100", "#789"], "the old list meanwhile: \(field.issuesShown)")
            world.runtime.release("load:issues")
            field.type("0")
            #expect(field.waitForIssues(["#7055", "#7001", "#7002", "#7090"]), "the new list: \(field.issuesShown)")
        }
    }

    /// The footer says the list's age once it is older than 10 minutes ("2 h ago"), counted from its `fetchedAt`.
    @Test func theFooterSaysTheListsAgeOnceOlderThanTenMinutes() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github(fetchedAt: world.clock.now.addingTimeInterval(-2 * 3600 - 60))
            world.runtime.holdLoads = false
            let field = world.field()
            field.type("#7")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]))
            #expect(field.footer.contains("GitHub issues") && field.footer.contains("2 h ago"), "\(field.footer)")

            let fresh = SuggestionsWorld()
            try fresh.github(fetchedAt: fresh.clock.now.addingTimeInterval(-5 * 60))
            let other = fresh.field()
            other.type("#7")
            #expect(other.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]))
            #expect(other.footer.contains("GitHub issues") && !other.footer.contains("ago"), "5 minutes old: \(other.footer)")
        }
    }

    /// A list without `fetchedAt` is as old as its load: shown while it loads again, the footer says so.
    @Test func aListWithoutFetchedAtIsAsOldAsItsLoad() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let field = world.field()
            field.type("#7")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]))
            world.runtime.holdLoads = true
            world.clock.advance(3 * 3600)
            field.type(" #7")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]))
            #expect(field.footer.contains("3 h ago"), "\(field.footer)")
            world.runtime.releaseAll()
        }
    }

    /// A source unused for 7 days stops refreshing; when it's used again, its old list shows (the footer says how old)
    /// while it loads again.
    @Test func aSourceUnusedForSevenDaysStopsRefreshing() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let field = world.field()
            field.type("#7")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]))
            field.type(" ")
            var loadsAtSevenAndAHalfDays = 0
            for hour in 1...(8 * 24) {
                world.clock.advance(3600)
                field.fireTimers()
                field.settle(timeout: 0.05) { false }
                if hour == 7 * 24 + 12 { loadsAtSevenAndAHalfDays = world.runtime.loads.count }
            }
            #expect(world.runtime.loads.count == loadsAtSevenAndAHalfDays,
                    "no refresh past 7 days unused: \(loadsAtSevenAndAHalfDays) → \(world.runtime.loads.count)")
            let before = world.runtime.loads.count
            world.runtime.holdLoads = true
            field.type("#7")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "the old list: \(field.issuesShown)")
            #expect(field.footer.contains("ago"), "its age: \(field.footer)")
            #expect(field.settle { world.runtime.loads.count == before + 1 }, "loaded again on use")
            world.runtime.releaseAll()
        }
    }

    /// Uses the source in `field` as the user would after a while: the timers due fire, " #7" is typed; then waits for the
    /// loads to number `loads` (true), or `timeout` seconds (false).
    @discardableResult
    func use(_ field: SuggestionsField, untilLoads loads: Int, timeout: TimeInterval = 1) -> Bool {
        field.fireTimers()
        field.type(" #7")
        return field.settle(timeout: timeout) { field.world.runtime.loads.count >= loads }
    }

    /// A load that fails (an error, a timeout, a bad output) keeps the old list, and Settings hears why. Failures back off
    /// (spec 6.17): after each, no load for 1 min, 5 min, 30 min, 2 h, one after; the fifth in a row pauses the source: no
    /// more loads (a day later still none), the old list still shown, Settings says it's paused and why.
    @Test func failuresBackOffAndTheFifthInARowPausesTheSource() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let field = world.field()
            field.type("#7")
            #expect(field.waitForIssues(Self.allRows))
            #expect(field.settle { world.lastStatus?.items == SuggestionsItems.issues.count }, "\(String(describing: world.lastStatus))")
            world.runtime.list("issues", .failure("GitHub said 503"))
            world.clock.advance(16 * 60)
            #expect(use(field, untilLoads: 2), "the refresh is due: \(world.runtime.loads.count) loads")
            #expect(field.settle { world.lastStatus?.error != nil }, "\(String(describing: world.lastStatus))")
            for (failure, backOff) in [(1, 60.0), (2, 5 * 60), (3, 30 * 60), (4, 2 * 3600)] {
                let loads = world.runtime.loads.count
                world.clock.advance(backOff - 20)
                use(field, untilLoads: loads + 1, timeout: 0.5)
                #expect(world.runtime.loads.count == loads, "failure \(failure): no load within \(Int(backOff)) s")
                world.clock.advance(40)
                #expect(use(field, untilLoads: loads + 1), "failure \(failure): a load after \(Int(backOff)) s (\(world.runtime.loads.count))")
                #expect(field.waitForIssues(Self.allRows), "failure \(failure): the old list (\(field.issuesShown))")
            }
            #expect(world.runtime.loads.count == 6, "1 load and 5 failures: \(world.runtime.loads.count)")
            #expect(field.settle { world.lastStatus?.paused == true }, "\(String(describing: world.lastStatus))")
            let status = try #require(world.lastStatus)
            #expect(status.paused && status.error?.isEmpty == false, "\(status)")
            #expect(status.items == SuggestionsItems.issues.count, "the old list's items: \(status)")
            for _ in 1...3 {
                world.clock.advance(7 * 3600)
                use(field, untilLoads: 7, timeout: 0.3)
            }
            #expect(world.runtime.loads.count == 6, "paused: no load 21 h later (\(world.runtime.loads.count))")
            #expect(field.waitForIssues(Self.allRows), "the old list: \(field.issuesShown)")
        }
    }

    /// Fails the source's loads until it pauses (five in a row, each once its back-off is over).
    func failUntilPaused(_ field: SuggestionsField) {
        let world = field.world
        world.runtime.list("issues", .failure("GitHub said 503"))
        for _ in 1...5 {
            world.clock.advance(2 * 3600 + 60)
            use(field, untilLoads: world.runtime.loads.count + 1)
        }
        field.settle { world.lastStatus?.paused == true }
    }

    enum Resume: String, CaseIterable, Sendable {
        case refreshNow, pluginUpdate, aDayLater
    }

    /// A paused source loads again (spec 6.17) on "Refresh now", an update of its plugin, or 24 hours later; a good load
    /// then unpauses it, its new list shows.
    @Test(arguments: Resume.allCases)
    func aPausedSourceResumes(_ resume: Resume) throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let field = world.field()
            field.type("#7")
            #expect(field.waitForIssues(Self.allRows))
            failUntilPaused(field)
            let loads = world.runtime.loads.count
            #expect(loads == 6 && world.lastStatus?.paused == true, "\(loads) loads, \(String(describing: world.lastStatus))")
            world.clock.advance(3600)
            use(field, untilLoads: loads + 1, timeout: 0.3)
            #expect(world.runtime.loads.count == loads, "paused")

            world.runtime.list("issues", items: [SuggestionsItems.issue(7055, "New since")] + SuggestionsItems.issues)
            switch resume {
            case .refreshNow:
                world.switches.refreshes = [CompletionSourceRefresh(plugin: "github", source: "issues", requested: world.clock.now)]
                field.host.send(.configChanged)
            case .pluginUpdate:
                let manifest = SuggestionsPlugins.githubManifest().replacingOccurrences(of: #""version": "1.0.0""#, with: #""version": "1.1.0""#)
                world.plugins = [try #require(try SuggestionsPlugins.install(manifest, in: world.folder))]
                field.host.send(.configChanged)
            case .aDayLater:
                world.clock.advance(24 * 3600)
            }
            #expect(use(field, untilLoads: loads + 1), "\(resume): loaded again (\(world.runtime.loads.count))")
            field.type("0")
            #expect(field.waitForIssues(["#7055", "#7001", "#7002", "#7090"]), "\(resume): the new list (\(field.issuesShown))")
            #expect(field.settle { world.lastStatus?.paused == false && world.lastStatus?.error == nil },
                    "\(resume): \(String(describing: world.lastStatus))")
        }
    }

    /// "Refresh now" loads a source again before its refresh is due, once: a request no newer than the last load asks
    /// nothing more.
    @Test func refreshNowLoadsTheListAgainOnce() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let field = world.field()
            field.type("#7")
            #expect(field.waitForIssues(Self.allRows))
            #expect(world.runtime.loads.count == 1)
            world.clock.advance(60)
            world.runtime.list("issues", items: [SuggestionsItems.issue(7055, "New since")] + SuggestionsItems.issues)
            world.switches.refreshes = [CompletionSourceRefresh(plugin: "github", source: "issues", requested: world.clock.now)]
            field.host.send(.configChanged)
            #expect(use(field, untilLoads: 2), "\(world.runtime.loads.count) loads")
            field.type("0")
            #expect(field.waitForIssues(["#7055", "#7001", "#7002", "#7090"]), "\(field.issuesShown)")
            world.clock.advance(60)
            field.host.send(.configChanged)
            use(field, untilLoads: 3, timeout: 0.5)
            #expect(world.runtime.loads.count == 2, "the same request again: \(world.runtime.loads.count) loads")
        }
    }

    // MARK: - The list on disk

    /// The regular files in `folder` and below.
    static func files(in folder: URL) -> [URL] {
        guard let all = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return all.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }

    /// The list is cached on disk, readable by the user only (0600); the next launch shows it while it loads again; the
    /// source disabled, its file is deleted (spec 1.5, 6.17).
    @Test func theListIsCachedOnDiskForTheUserOnlyAndDeletedWhenDisabled() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            let cache = world.folder.appendingPathComponent("cache", isDirectory: true)
            world.cacheFolder = cache
            try world.github()
            let field = world.field()
            field.type("#7")
            #expect(field.waitForIssues(Self.allRows))
            #expect(field.settle { !Self.files(in: cache).isEmpty }, "cached in \(cache.path)")
            for file in Self.files(in: cache) {
                let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
                #expect(permissions == 0o600, "\(file.lastPathComponent): \(String(permissions ?? 0, radix: 8))")
            }

            let next = SuggestionsWorld()
            next.cacheFolder = cache
            next.plugins = world.plugins
            next.switches = world.switches
            next.runtime.list("issues", .failure("offline"))  // nothing new to cache: the file stays the first launch's
            next.runtime.holdLoads = true
            let launched = next.field()
            launched.type("#7")
            #expect(launched.waitForIssues(Self.allRows), "the next launch, while it loads: \(launched.issuesShown)")
            next.runtime.releaseAll()
            launched.settle(timeout: 1) { next.lastStatus?.error != nil }

            world.disable("github", "issues")
            field.host.send(.configChanged)
            field.type(" #7")
            #expect(field.settle { Self.files(in: cache).isEmpty }, "disabled: \(Self.files(in: cache).map(\.lastPathComponent))")
        }
    }

    /// One failure is told to Settings, and the next good load clears it.
    @Test func aFailureIsToldAndTheNextGoodLoadClearsIt() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            world.runtime.list("issues", .failure("GitHub said 503"))
            let field = world.field()
            field.type("#7")
            #expect(field.settle { world.lastStatus?.error != nil }, "\(String(describing: world.lastStatus))")
            #expect(field.issuesShown.isEmpty, "no list yet")
            world.runtime.list("issues", items: SuggestionsItems.issues)
            world.clock.advance(24 * 3600)
            field.fireTimers()
            field.type(" #7")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]), "\(field.issuesShown)")
            #expect(field.settle { world.lastStatus?.error == nil && world.lastStatus?.items == SuggestionsItems.issues.count },
                    "\(String(describing: world.lastStatus))")
            #expect(world.lastStatus?.refreshed == world.clock.now, "when: \(String(describing: world.lastStatus))")
        }
    }

    // MARK: - What the script is told

    /// `load` may take the plugin's `timeoutSeconds` (20 s at most: over it, spec 6.9 refuses the plugin's completions,
    /// SuggestionsManifestAcceptanceTests), `query` 3 s at most.
    @Test func theLoadAndTheQueryHaveTheirTimeouts() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            let manifest = SuggestionsPlugins.githubManifest().replacingOccurrences(of: #""script": "main.js","#,
                                                                                   with: #""script": "main.js", "timeoutSeconds": 15,"#)
            try world.github(manifest: manifest)
            let field = world.field()
            field.type("#70")
            #expect(field.settle { !world.runtime.loads.isEmpty && !world.runtime.queryCalls.isEmpty })
            #expect(world.runtime.loads.first?.timeout == 15, "\(String(describing: world.runtime.loads.first?.timeout))")
            let query = try #require(world.runtime.queryCalls.first)
            #expect(query.timeout > 0 && query.timeout <= 3, "\(query.timeout)")

            let plain = SuggestionsWorld()
            let plugin = try plain.github()
            let other = plain.field()
            other.type("#7")
            #expect(other.settle { !plain.runtime.loads.isEmpty })
            #expect(plain.runtime.loads.first?.timeout == plugin.manifest.timeout, "the plugin's default (10 s)")
        }
    }

    /// `ctx` is the source's name, the plugin's preferences (the password too, a preference not set its default) and
    /// the interface language; nothing else.
    @Test func theScriptIsToldItsSourceItsPreferencesAndTheLanguage() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            world.preferenceValues.withLock { $0["github"] = ["token": "ghp_exampletoken0000"] }
            let field = world.field()
            field.type("#70")
            #expect(field.settle { !world.runtime.loads.isEmpty && !world.runtime.queryCalls.isEmpty })
            for call in world.runtime.loads + world.runtime.queryCalls {
                #expect(call.context == CompletionContext(source: "issues",
                                                          preferences: ["repos": "octo-org/octo-repo", "token": "ghp_exampletoken0000"],
                                                          language: .english), "\(call.context)")
                #expect(call.plugin.name == "github" && call.source.name == "issues")
            }

            let chinese = SuggestionsWorld()
            chinese.config.uiLanguage = "zh-Hans"
            try chinese.github()
            let zh = chinese.field()
            zh.type("#7")
            #expect(zh.settle { !chinese.runtime.loads.isEmpty })
            #expect(chinese.runtime.loads.first?.context.language == .chinese)
        }
    }

    // MARK: - The plugin's outputs

    /// A good list (Fixtures/Suggestions/outputs/good-list.json): its items in its order, its age from `fetchedAt`; a
    /// good query's answer merged after it (good-query.json).
    @Test func aGoodListAndQueryFromThePluginShowAsRows() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github(items: [])
            world.runtime.list("issues", .output(try SuggestionsFixtures.output("good-list")))
            world.runtime.query("60", .output(try SuggestionsFixtures.output("good-query")))
            let field = world.field()
            field.type("#6")
            #expect(field.settle { field.shown(Self.fixtureMatches) == ["#6001", "#6007", "#6090", "#6800"] },
                    "\(field.rows.map(\.text))")
            #expect(field.footer.contains("2 h ago"), "fetchedAt was 2 hours ago: \(field.footer)")
            #expect(field.rows.contains { ($0.text + $0.comment).contains("Settings: a switch per app") }, "titles are shown")
            field.type("0")
            #expect(field.settle { field.shown(Self.fixtureMatches) == ["#6001", "#6007", "#6090", "#6066"] },
                    "\(field.rows.map(\.text))")
        }
    }

    /// More than 20,000 items, or more than 4 MiB: refused, the old list kept, Settings told why.
    @Test(arguments: ["items", "bytes"])
    func anOversizedListIsRefusedAndTheOldOneKept(_ what: String) throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let field = world.field()
            field.type("#7")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090", "#7100", "#789"]))
            world.runtime.list("issues", .output(what == "items" ? SuggestionsFixtures.tooManyItems() : SuggestionsFixtures.tooManyBytes()))
            world.clock.advance(24 * 3600)
            field.fireTimers()
            field.type(" #7")
            #expect(field.settle { world.runtime.loads.count == 2 })
            #expect(field.settle { world.lastStatus?.error != nil }, "Settings hears why: \(String(describing: world.lastStatus))")
            field.type("0")
            #expect(field.waitForIssues(["#7001", "#7002", "#7090"]), "the old list: \(field.issuesShown)")
            #expect(world.lastStatus?.items == SuggestionsItems.issues.count)

            let first = SuggestionsWorld()
            try first.github()
            first.runtime.list("issues", .output(what == "items" ? SuggestionsFixtures.tooManyItems() : SuggestionsFixtures.tooManyBytes()))
            let empty = first.field()
            empty.type("#1")
            #expect(empty.settle { first.lastStatus?.error != nil })
            #expect(empty.shown(["#1", "#10", "#11", "#12", "#13", "#14", "#15", "#16", "#17", "#18", "#19"]).filter { $0 != "?" }.isEmpty,
                    "none of it shows: \(empty.rows.map(\.text))")
        }
    }

    enum NotAnObjectWithItems: String, CaseIterable, Sendable {
        case itemsNotAList, anArray, noItems, null, notJSON
    }

    /// An output that isn't a JSON object with an `items` array (spec 6.5) is a failure: the old list kept, Settings told.
    @Test(arguments: NotAnObjectWithItems.allCases)
    func anOutputThatIsntAnObjectWithAnItemsArrayIsAFailure(_ output: NotAnObjectWithItems) throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github()
            let field = world.field()
            field.type("#7")
            #expect(field.waitForIssues(Self.allRows))
            let data: Data
            switch output {
            case .itemsNotAList: data = try SuggestionsFixtures.output("not-a-list")
            case .anArray: data = Data(##"[{ "match": "#7066", "title": "In an array" }]"##.utf8)
            case .noItems: data = Data(##"{ "list": [{ "match": "#7066", "title": "Under another key" }] }"##.utf8)
            case .null: data = Data("null".utf8)
            case .notJSON: data = Data("#7066 In plain text".utf8)
            }
            world.runtime.list("issues", .output(data))
            world.clock.advance(24 * 3600)
            field.fireTimers()
            field.type(" #7")
            #expect(field.settle { world.runtime.loads.count == 2 && world.lastStatus?.error != nil },
                    "\(output): \(String(describing: world.lastStatus))")
            #expect(field.waitForIssues(Self.allRows), "\(output): the old list (\(field.issuesShown))")
            #expect(world.lastStatus?.items == SuggestionsItems.issues.count)
        }
    }

    /// Control, bidi and zero-width characters (control-characters.json) are never shown, nor inserted.
    @Test func controlBidiAndZeroWidthCharactersAreNeverShownOrInserted() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github(items: [])
            world.runtime.list("issues", .output(try SuggestionsFixtures.output("control-characters")))
            let field = world.field(app: SuggestionsApps.slack)
            field.type("#60")
            #expect(field.settle { field.shown(Self.fixtureMatches) == ["#6001", "#6007", "#6090"] }, "\(field.rows.map(\.text))")
            for row in field.rows {
                #expect(!Self.hasHiddenCharacters(row.text) && !Self.hasHiddenCharacters(row.comment),
                        "\(row.text.unicodeScalars.map { String($0.value, radix: 16) }) \(row.comment.unicodeScalars.map { String($0.value, radix: 16) })")
            }
            #expect(field.rows.contains { ($0.text + $0.comment).contains("build") }, "the rest of the title shows")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document.hasPrefix("#6001"), "\(field.document)")
            #expect(!Self.hasHiddenCharacters(field.document), "\(field.document.unicodeScalars.map { String($0.value, radix: 16) })")
            #expect(field.document.contains("https://github.com/octo-org/octo-repo/issues/6001"), "\(field.document)")
        }
    }

    /// Characters that would change what the user sees or a terminal does: control (Cc), format (Cf: bidi controls,
    /// zero-width, BOM), line and paragraph separators.
    static func hasHiddenCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            switch $0.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: return true
            default: return false
            }
        }
    }

    /// Bad items (bad-matches.json: a `match` that breaks the rules, an item that isn't an object) are dropped one by one
    /// (spec 6.5): they never show, the good ones around them do, and the list is a good one (no error, its good items).
    @Test func badItemsAreDroppedOneByOne() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github(items: [])
            world.runtime.list("issues", .output(try SuggestionsFixtures.output("bad-matches")))
            let field = world.field()
            field.type("#6")
            #expect(field.settle { field.shown(Self.fixtureMatches) == ["#6001", "#6070"] }, "\(field.rows.map(\.text))")
            for token in [" #60", " #600"] {
                field.type(token)
                field.settle(timeout: 1) { !field.rows.isEmpty }
                #expect(!field.rows.contains { ($0.text + $0.comment).contains("BAD") }, "\(token): \(field.rows.map(\.text))")
            }
            #expect(field.settle { world.lastStatus?.items == 2 }, "\(String(describing: world.lastStatus))")
            #expect(world.lastStatus?.error == nil && world.lastStatus?.paused == false, "\(String(describing: world.lastStatus))")
            #expect(world.runtime.loads.count == 1)
        }
    }

    /// Control, bidi and zero-width characters are taken out first, then the `match` is checked (spec 6.6,
    /// stripped-matches.json): "#60\u{200B}02" is #6002, shown and inserted so; one with nothing left, or a space left, is
    /// dropped.
    @Test func hiddenCharactersAreTakenOutBeforeTheMatchIsChecked() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github(items: [])
            world.runtime.list("issues", .output(try SuggestionsFixtures.output("stripped-matches")))
            let field = world.field()
            field.type("#60")
            #expect(field.settle { field.shown(Self.fixtureMatches) == ["#6002", "#6003", "#6004"] }, "\(field.rows.map(\.text))")
            #expect(!field.rows.contains { ($0.text + $0.comment).contains("BAD") }, "\(field.rows.map(\.text))")
            #expect(field.press(SuggestionKeys.tab))
            #expect(field.document == "#6002", "\(field.document.unicodeScalars.map { String($0.value, radix: 16) })")
        }
    }

    /// The same `match` twice in a list (duplicates.json): one row, the first item's.
    @Test func aMatchListedTwiceShowsOnce() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            try world.github(items: [])
            world.runtime.list("issues", .output(try SuggestionsFixtures.output("duplicates")))
            let field = world.field()
            field.type("#60")
            #expect(field.settle { field.shown(Self.fixtureMatches) == ["#6001", "#6007", "#6090"] }, "\(field.rows.map(\.text))")
            #expect(field.rows.contains { ($0.text + $0.comment).contains("first of 6007") })
            #expect(!field.rows.contains { ($0.text + $0.comment).contains("second") }, "\(field.rows.map(\.text))")
        }
    }
}
