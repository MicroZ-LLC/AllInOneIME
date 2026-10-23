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

extension SuggestionsSessionTests {
    /// Presses `key` as the Mac's shell does: with only what the session asks of the field for it (`fieldWants`); a
    /// printable key the session lets through is typed by the app. Whether it asked for the field's text.
    @discardableResult
    func pressAsTheMacDoes(_ key: KeyEvent, in field: SuggestionsField) -> Bool {
        var askedText = false
        var context = FieldContext(field: FieldInfo(app: field.host.app, terminal: field.host.terminal))
        let all = field.host.context
        while true {
            let missing = field.host.session.fieldWants(for: key, given: context).subtracting(context.read)
            if missing.isEmpty { break }
            if missing.contains(.text) { askedText = true }
            if missing.contains(.secure) { context.secure = all.secure }
            if missing.contains(.selectedRange) { context.selectedRange = all.selectedRange }
            if missing.contains(.beforeCaret) { context.beforeCaret = all.beforeCaret }
            if missing.contains(.selection) { context.selection = all.selection }
            if missing.contains(.text) { context.text = all.text }
            context.read.formUnion(missing)
        }
        let before = field.host.outputs.count
        field.host.send(.key(key, context))
        let took = field.host.outputs.dropFirst(before).contains { if case .commit = $0 { true } else { false } }
        if !took, key.key == .character || key.key == .space, let typed = key.printableText { field.host.document += typed }
        field.noteTimers()
        return askedText
    }

    /// Types `text` (letters, digits, marks, spaces, in English) as the Mac's shell does (`pressAsTheMacDoes`). How many
    /// keys asked for the field's text.
    @discardableResult
    func typeAsTheMacDoes(_ text: String, into field: SuggestionsField) -> Int {
        text.filter { pressAsTheMacDoes(SuggestionKeys.key($0), in: field) }.count
    }

    /// Coding mode reads the field's text once a pause in typing (spec 2: "read once per pause"), asked of the shell after
    /// it (`SessionOutput.readField`), never with a key; its words are rows from then on.
    @Test func codingModeReadsTheFieldOncePerPause() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            world.codingMode = true
            let field = world.field()
            let reads = typeAsTheMacDoes("total_amount = total_amount + to", into: field)
            #expect(reads == 0, "a key asked for the field's text \(reads) times")
            #expect(field.host.fieldReads == 0, "no pause yet: \(field.host.fieldReads) reads")
            field.pause(1)
            #expect(field.host.fieldReads == 1, "one read after the pause: \(field.host.fieldReads)")
            #expect(field.settle { field.rows.contains { $0.text == "total_amount" } }, "the field's words: \(field.rows.map(\.text))")
            field.pause(1)
            #expect(field.host.fieldReads == 1, "no typing, no read: \(field.host.fieldReads)")
        }
    }

    /// A snippet of more than one line put in with Tab gets the caret's line's indentation as the field tells it with
    /// that Tab, typed in a hurry (no pause, no read since the line was indented); one line only, nothing is read.
    @Test func aSnippetIsIndentedAsTheLineIsWhenItGoesIn() throws {
        try inEnglish {
            let world = SuggestionsWorld()
            world.codingMode = true
            world.packs = [try SuggestionsCodingPacksTests.shipped("python")]
            let field = world.field()
            field.host.document = "def main():\n    "
            #expect(typeAsTheMacDoes("tr", into: field) == 0)
            #expect(field.settle { field.rows.first?.comment.contains("try/except") == true }, "\(field.rows.map(\.comment))")
            #expect(field.host.fieldReads == 0, "no pause")
            #expect(pressAsTheMacDoes(SuggestionKeys.tab, in: field), "Tab asked for the line it goes into")
            #expect(field.document == "def main():\n    try:\n        \n    except Exception as e:\n        print(e)",
                    "\(field.document.debugDescription)")
            field.host.document = "x = "
            typeAsTheMacDoes(" pri", into: field)
            #expect(field.settle { field.rows.first?.text == "print" }, "\(field.rows.map(\.text))")
            #expect(!pressAsTheMacDoes(SuggestionKeys.tab, in: field), "a keyword: nothing read")
        }
    }
}

extension SuggestionsSessionTests {
    /// fn held with Shift is no long press of Shift (the Mac tells fn as `.function`): no chooser; a tap of Shift with fn
    /// held still switches the input language, as it always did (the composer isn't told of fn).
    @Test func fnHeldOpensNoChooserAndATapStillSwitches() {
        inEnglish {
            let world = SuggestionsWorld()
            let field = world.field()
            let language = field.host.composer.inputLanguage
            field.host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.shift, .leftShift, .function],
                                                timestamp: world.clock.timestamp))
            field.noteTimers()
            world.clock.advance(0.1)
            field.host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.function], timestamp: world.clock.timestamp))
            #expect(field.host.composer.inputLanguage != language, "fn and a tap of Shift: the next input language")
            field.host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.shift, .leftShift, .function],
                                                timestamp: world.clock.timestamp))
            field.noteTimers()
            world.clock.advance(1.2)
            field.fireTimers()
            #expect(field.rows.isEmpty, "fn and Shift held: no chooser (\(field.rows.map(\.text)))")
            field.host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.function], timestamp: world.clock.timestamp))
        }
    }

    /// When the long press's time comes, Shift is asked of the system (`SuggestionsServices.shiftHeld`): its release went
    /// unseen (another app had it, an event lost), no chooser.
    @Test func aReleaseMissedOpensNoChooser() {
        inEnglish {
            let world = SuggestionsWorld()
            let held = Locked(initialState: true)
            let field = world.field { $0.suggestions.shiftHeld = { held.withLock { $0 } } }
            field.host.modifiers(ModifierChange(key: .modifier(.shift, .left), modifiers: [.shift, .leftShift], timestamp: world.clock.timestamp))
            field.noteTimers()
            held.withLock { $0 = false }  // let go, unseen
            world.clock.advance(1.2)
            field.fireTimers()
            #expect(field.rows.isEmpty, "Shift no longer down: no chooser (\(field.rows.map(\.text)))")
            held.withLock { $0 = true }
            field.holdShift()
            #expect(field.rows.map(\.text) == ["Translate as You Type", "Coding mode"], "held: the chooser (\(field.rows.map(\.text)))")
        }
    }
}

extension SuggestionsSessionTests {
    /// Translate as You Type coming on otherwise than from the chooser (an app set to translate always, as a field of it
    /// takes the focus) turns coding mode off: the two are exclusive (spec 2) however one comes on.
    @Test func translateAsYouTypeComingOnTurnsCodingModeOff() {
        inEnglish {
            let world = SuggestionsWorld()
            world.codingMode = true
            world.packs = [SuggestionsSessionTests.pack]
            let field = world.field()
            field.type("co")
            #expect(field.settle { !field.rows.isEmpty }, "coding mode's rows")
            world.translateAsYouType = true
            field.host.send(.configChanged)
            let outputs = field.host.session.translateAsYouTypeCameOn()
            #expect(!world.codingMode, "coding mode off")
            #expect(outputs.contains { if case .panel(nil) = $0 { true } else { false } }, "its rows gone: \(outputs)")
            world.codingMode = false
            #expect(field.host.session.translateAsYouTypeCameOn().isEmpty, "coding mode off already: nothing")
        }
    }

    static let pack = CodingLanguagePack(language: "example", title: "Example", version: "1.0.0", keywords: ["compute_total", "const"],
                                         snippets: [])
}
