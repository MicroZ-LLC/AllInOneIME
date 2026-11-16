import AllInOneIMECore
import Foundation
import Testing

// #120: settings, a Common page first and the rest in More Settings. The acceptance tests, written from the issue and
// the integrator's contract by an author other than the implementation's (whose changes don't edit them).
//
// "A fresh install shows 46 rows on 8 settings pages, and most people need about ten of them. This puts those ten on a
// 常用 / Common page, opened first, and moves the rest into 更多设置 / More Settings: five groups with one row each,
// where a group opens as a short page of its own. Nothing is added or removed (rule 2). Every `SettingsSpot` keeps its
// config key and behaviour; only where it is shown changes."
//
// The issue's acceptance list, as seen here:
//   1. "`firstPage` is Common, and the sidebar lists the six pages above in that order" (常用 / Common · AI · 本周 / This
//      Week · 命令库 / Commands — divider — 更多设置 / More Settings · 关于 / About); "The General, Input, Privacy and
//      Advanced pages leave the sidebar"; the contract: More Settings' five groups are pages of their own, not in the
//      sidebar, whose parent is More Settings; the old `general` and `input` cases are gone.
//   2. "Every `SettingsSpot` lives in exactly one place: a page, or a group of More Settings": each on the page or group
//      the issue's lists put it in (Common's Typing and Commands and features, More Settings' table), never on More
//      Settings' index itself, and listed by that place only.
//   3. "The per-page and per-group counts on a fresh-install config are as in the tables" (with the contract's
//      clarification: `keyHints`, added by PR #99 after the issue, is in Interface and sync, so that group shows 4 and
//      the total is 47); Advanced's `useSelection` and `previousAppSettings` "when `isShown` says so".
//   4. "The search opens every spot where it now lives": each row's own title, in either interface language, finds it,
//      on its new page or group ("Picking a result opens the page or group the row is in now").
//   5. The pages' titles, as the issue and the contract name them, in Chinese and English.
//   6. "the Doctor's banners (`SettingsPage.of(_:)`) … land on the new places": a page that exists for every area.
//   7. "`pinyinScheme` and `chineseCharacters` become rows of their own, shown while Chinese is an input language, as
//      `isShown` already says."
// Not seen here: the window as drawn (the sidebar's divider, the groups' icons, the back button, the "Say what to
// change" field and the footer's wording), what the field does, that no config key changes (the core's config tests),
// that the Chinese chip no longer holds the scheme and characters, and `--settings-image`.
//
// The input method's own code can't be imported here (it is an executable target): as Settings075MacTests does it, all
// of Sources/AllInOneIME is compiled into a child process, with the Mac library, the core and librime, as the input
// method is built. Only main.swift's dispatch (what follows `let arguments = …`) is replaced: the child prints the
// window's pages and rows as the names of the contract give them, the rows each config shows, the pages' titles and
// what the sidebar's search lists, with the config each test asks for, in each interface language. The child's home is
// a folder of the test's: nothing reads the user's config.

@Suite(.serialized)
struct Settings120MacTests {
    typealias Ask = Settings120Child.Ask
    typealias Found = Settings120Child.Found

    /// The interface languages (config `uiLanguage`).
    static let interfaces = ["en", "zh"]

    /// "常用 / Common · AI · 本周 / This Week · 命令库 / Commands — divider — 更多设置 / More Settings · 关于 / About".
    static let sidebar = ["common", "ai", "week", "commands", "more", "about"]
    /// More Settings' groups, as the issue's table lists them (the contract's names).
    static let groups = ["inputAndKeys", "suggestions", "privacy", "interface", "advanced"]
    /// The places a row lives in: a sidebar page other than More Settings (its index lists the groups, not rows), or a
    /// group.
    static let places = sidebar.filter { $0 != "more" } + groups

    /// "打字 / Typing: `inputLanguages`, `pinyinScheme`, `chineseCharacters`, `switchKey`, `candidateLayout`" and "命令与功能
    /// / Commands and features: `magicKey`, `outputLanguages` (moved from AI → AI commands), `clipboardHistory`,
    /// `autocomplete`".
    static let common = ["inputLanguages", "pinyinScheme", "chineseCharacters", "switchKey", "candidateLayout",
                         "magicKey", "outputLanguages", "clipboardHistory", "autocomplete"]
    /// The issue's table of More Settings' groups; Interface and sync with `keyHints` (the contract's clarification);
    /// Advanced with `useSelection` and `previousAppSettings` ("when `isShown` says so").
    static let groupRows: [String: [String]] = [
        "inputAndKeys": ["fuzzyPinyin", "personalDictionaries", "removedCandidates", "englishWords", "codingLanguage", "actionKey"],
        "suggestions": ["suggestions", "suggestionsInsert", "appInserts"],
        "privacy": ["hideSensitive", "wordsToHide", "appsWithoutAI", "pageContext", "learnEnglishWords", "learned", "installID"],
        "interface": ["menuBarIcon", "interfaceLanguage", "iCloudSync", "keyHints"],
        "advanced": ["typeOut", "configFile", "rimeFolder", "useSelection", "previousAppSettings"],
    ]
    /// The pages that stay as they are: AI (its own rows and the AI commands' but Translate to, now Common's), "命令库 is
    /// today's Commands page, unchanged", About.
    static let unchangedRows: [String: [String]] = [
        "ai": ["provider", "model", "apiKey", "awsProfile", "baseURL", "testConnection",
               "rewriteStyles", "improveTranslates", "jargonList", "questionContinueIn", "rememberQuestions"],
        "commands": ["customCommands", "agent", "notes", "plugins", "scriptExtensions", "extensionSources"],
        "about": ["updates", "troubleshoot", "reportIssue"],
    ]

    /// Every row (`SettingsSpot`, by raw value) and the place it lives in now: "Nothing is added or removed".
    static let place: [String: String] = {
        var place: [String: String] = [:]
        for row in common { place[row] = "common" }
        for (page, rows) in groupRows.merging(unchangedRows, uniquingKeysWith: { a, _ in a }) {
            for row in rows { place[row] = page }
        }
        return place
    }()

    /// The rows a fresh install doesn't show, and a config of the test's that shows each: a provider with a key (the
    /// model, the key, the base URL), Amazon Bedrock (the AWS profile), a jargon list named, "Use the selected text"
    /// off, an app with a previous per-app setting.
    static let shownWith: [String: Settings120Child.Variant] = [
        "model": .keyed, "apiKey": .keyed, "baseURL": .keyed, "awsProfile": .bedrock, "jargonList": .jargon,
        "useSelection": .selectionOff, "previousAppSettings": .previous,
    ]

    /// "`firstPage` is Common, and the sidebar lists the six pages above in that order"; the contract: the groups, in the
    /// table's order, are pages of their own whose parent is More Settings (nil for the sidebar's pages); "The old
    /// `general` and `input` cases are gone."
    @Test func settingsOpenOnCommonAndTheSidebarListsTheSixPages() throws {
        let report = try Settings120Child.run([Ask(.fresh, "en", "facts")])
        #expect(report.value("FIRST") == "common", "Settings opens on \(report.value("FIRST") ?? "nothing"): \(report)")
        #expect(report.value("SIDEBAR") == Self.sidebar.joined(separator: ","), "\(report)")
        #expect(report.value("GROUPS") == Self.groups.joined(separator: ","), "\(report)")
        for page in Self.sidebar + Self.groups {
            #expect(report.value("CASE", page) == "1", "no page \(page): \(report)")
        }
        // "The General, Input, Privacy and Advanced pages leave the sidebar": General and Input are gone; Privacy and
        // Advanced are groups now (their names reused), not sidebar pages.
        for gone in ["general", "input"] {
            #expect(report.value("CASE", gone) == "0", "\(gone) is still a page: \(report)")
        }
        for page in Self.sidebar {
            #expect(report.value("PARENT", page) == "none", "\(page)'s parent: \(report.value("PARENT", page) ?? "?"): \(report)")
        }
        for group in Self.groups {
            #expect(report.value("PARENT", group) == "more", "\(group)'s parent: \(report.value("PARENT", group) ?? "?"): \(report)")
        }
    }

    /// "Every `SettingsSpot` lives in exactly one place: a page, or a group of More Settings": the rows are the ones
    /// there were ("Nothing is added or removed"), each on the page or group the issue puts it in, never on More
    /// Settings' index, and only that place lists it among its rows.
    @Test func everyRowLivesInExactlyOnePlace() throws {
        let report = try Settings120Child.run([Ask(.fresh, "en", "facts")])
        let rows = try #require(report.value("SPOTS"), "no rows listed: \(report)").split(separator: ",").map(String.init)
        let added = Set(rows).subtracting(Self.place.keys).sorted(), removed = Set(Self.place.keys).subtracting(rows).sorted()
        #expect(added.isEmpty && removed.isEmpty, "rows added: \(added), removed: \(removed)")
        #expect(rows.count == Set(rows).count, "a row listed twice: \(rows)")
        for row in rows {
            let page = report.value("SPOT", row)
            #expect(page == Self.place[row], "\(row) is on \(page ?? "no page"), not \(Self.place[row] ?? "anywhere")")
            #expect(page != "more", "\(row) is on More Settings' index, not in a group")
            #expect(page.map { Self.places.contains($0) } == true, "\(row) is on \(page ?? "no page"), not a sidebar page or a group")
            let listedBy = report.value("PLACES", row)?.split(separator: ",").map(String.init) ?? []
            #expect(listedBy == [page ?? ""], "\(row) is listed by \(listedBy), not by \(page ?? "its page") alone")
        }
    }

    /// "The per-page and per-group counts on a fresh-install config are as in the tables" (signed in to AllInOneIME
    /// Cloud, Chinese and English as inputs): Common 9, AI 6, Commands 6, More Settings 23 (Input and keys 6,
    /// Suggestions 3, Privacy 7, Interface and sync 4 with `keyHints`, Advanced 3), About 3: 47 in all. Common's rows
    /// are its nine; each group shows the rows of its line of the table.
    @Test func aFreshInstallShowsTheTablesCounts() throws {
        let report = try Settings120Child.run([Ask(.fresh, "en", "facts"), Ask(.fresh, "en", "counts")])
        let expected = ["common": 9, "ai": 6, "commands": 6, "more": 23, "about": 3,
                        "inputAndKeys": 6, "suggestions": 3, "privacy": 7, "interface": 4, "advanced": 3]
        for (page, count) in expected {
            #expect(report.count(.fresh, page) == count, "\(page) shows \(report.countText(.fresh, page)), not \(count): \(report)")
        }
        // This Week has no rows; the sidebar's pages add up to the total (More Settings counting its groups').
        let total = Self.sidebar.compactMap { report.count(.fresh, $0) }.reduce(0, +)
        #expect(total == 47, "the sidebar's pages show \(total) rows, not 47: \(report)")
        #expect(report.count(.fresh, "more") == Self.groups.compactMap { report.count(.fresh, $0) }.reduce(0, +),
                "More Settings' count isn't its groups': \(report)")
        let shown = report.shown(.fresh)
        #expect(shown.count == 47, "a fresh install shows \(shown.count) rows, not 47: \(shown.sorted())")
        // The rows each place shows, by the place each row says it is in.
        func shownOn(_ page: String) -> Set<String> { shown.filter { report.value("SPOT", $0) == page } }
        #expect(shownOn("common") == Set(Self.common), "Common shows \(shownOn("common").sorted())")
        for (group, rows) in Self.groupRows {
            let freshRows = Set(rows).subtracting(["useSelection", "previousAppSettings"])
            #expect(shownOn(group) == freshRows, "\(group) shows \(shownOn(group).sorted()), not \(freshRows.sorted())")
        }
    }

    /// Advanced: "`typeOut`, `configFile`, `rimeFolder`, and `useSelection` and `previousAppSettings` when `isShown` says
    /// so": "Use the selected text" off in the config, or an app with a previous per-app setting, adds its row to
    /// Advanced, and to More Settings' count (the footer's N).
    @Test func advancedShowsUseSelectionAndPreviousSettingsWhenTheyAreThere() throws {
        let variants: [Settings120Child.Variant] = [.fresh, .selectionOff, .previous]
        let report = try Settings120Child.run([Ask(.fresh, "en", "facts")] + variants.map { Ask($0, "en", "counts") })
        for row in ["useSelection", "previousAppSettings"] {
            #expect(report.value("SPOT", row) == "advanced", "\(row) is on \(report.value("SPOT", row) ?? "no page")")
            #expect(!report.shown(.fresh).contains(row), "a fresh install shows \(row)")
        }
        #expect(report.shown(.selectionOff).contains("useSelection"), "useSelection off: no row: \(report)")
        #expect(report.shown(.previous).contains("previousAppSettings"), "an app's previous settings: no row: \(report)")
        for variant in [Settings120Child.Variant.selectionOff, .previous] {
            #expect(report.count(variant, "advanced") == 4, "\(variant.rawValue): Advanced shows \(report.countText(variant, "advanced")): \(report)")
            #expect(report.count(variant, "more") == 24, "\(variant.rawValue): More Settings shows \(report.countText(variant, "more")): \(report)")
        }
    }

    /// "The search opens every spot where it now lives": each row's own title, as the interface says it (Chinese and
    /// English), finds it, with a config that shows it, on the page or group the issue puts it in ("Picking a result
    /// opens the page or group the row is in now"); every other row a search lists is on its new place too.
    @Test func theSearchFindsEveryRowWhereItNowLives() throws {
        let rows = Self.place.keys.sorted()
        let asks = Self.interfaces.flatMap { interface in
            rows.map { Ask(Self.shownWith[$0] ?? .fresh, interface, "title:" + $0) }
        }
        let report = try Settings120Child.run(asks)
        for ask in asks {
            let row = String(ask.query.dropFirst("title:".count))
            let found = try #require(report.found(ask), "\(ask) not searched: \(report)")
            #expect(found.contains(Found(row, Self.place[row] ?? "")), "\(ask): \(row) isn't listed on \(Self.place[row] ?? "?"): \(found)")
            for other in found {
                #expect(other.page == Self.place[other.row], "\(ask) lists \(other), not on \(Self.place[other.row] ?? "?")")
            }
        }
    }

    /// The pages' titles: "常用 / Common · AI · 本周 / This Week · 命令库 / Commands … 更多设置 / More Settings · 关于 /
    /// About" ("命令库 is today's Commands page, unchanged; only its Chinese name changes (English stays 'Commands')"),
    /// and the groups' as the table names them.
    @Test func thePagesAreTitledAsTheIssueSays() throws {
        let titles: [String: (zh: String, en: String)] = [
            "common": ("常用", "Common"), "ai": ("AI", "AI"), "week": ("本周", "This Week"), "commands": ("命令库", "Commands"),
            "more": ("更多设置", "More Settings"), "about": ("关于", "About"),
            "inputAndKeys": ("输入与按键", "Input and keys"), "suggestions": ("建议", "Suggestions"), "privacy": ("隐私", "Privacy"),
            "interface": ("界面与同步", "Interface and sync"), "advanced": ("高级", "Advanced"),
        ]
        let report = try Settings120Child.run(Self.interfaces.map { Ask(.fresh, $0, "titles") })
        for (page, title) in titles {
            #expect(report.value("TITLE", "zh", page) == title.zh, "\(page) in Chinese: \(report.value("TITLE", "zh", page) ?? "?")")
            #expect(report.value("TITLE", "en", page) == title.en, "\(page) in English: \(report.value("TITLE", "en", page) ?? "?")")
        }
    }

    /// "`SettingsWindow.show(page:spot:)`, the Doctor's banners (`SettingsPage.of(_:)`) and every other link into
    /// settings land on the new places": each area's banner is on a page there is, in the sidebar or a group.
    @Test func everyDoctorBannerLandsOnAPageThereIs() throws {
        let report = try Settings120Child.run([Ask(.fresh, "en", "facts")])
        for area in Doctor.Area.allCases {
            let page = try #require(report.value("AREA", area.rawValue), "\(area.rawValue): no page told: \(report)")
            #expect((Self.sidebar + Self.groups).contains(page), "\(area.rawValue)'s banner is on \(page)")
        }
    }

    /// "`pinyinScheme` and `chineseCharacters` become rows of their own, shown while Chinese is an input language, as
    /// `isShown` already says": with Chinese and English, Common shows them (and the search finds them there); with
    /// English alone, neither is shown or found, and Common shows 7.
    @Test func theSchemeAndCharactersShowOnlyWithChinese() throws {
        let rows = ["pinyinScheme", "chineseCharacters"]
        var asks = [Ask(.fresh, "en", "counts"), Ask(.englishOnly, "en", "counts")]
        for variant in [Settings120Child.Variant.fresh, .englishOnly] {
            asks += Self.interfaces.flatMap { interface in rows.map { Ask(variant, interface, "title:" + $0) } }
        }
        let report = try Settings120Child.run(asks)
        for row in rows {
            #expect(report.shown(.fresh).contains(row), "with Chinese, \(row) isn't shown")
            #expect(!report.shown(.englishOnly).contains(row), "with English alone, \(row) is shown")
        }
        #expect(report.count(.fresh, "common") == 9, "\(report)")
        #expect(report.count(.englishOnly, "common") == 7, "with English alone, Common shows \(report.countText(.englishOnly, "common")): \(report)")
        for ask in asks.dropFirst(2) {
            let row = String(ask.query.dropFirst("title:".count))
            let found = try #require(report.found(ask), "\(ask) not searched: \(report)")
            if ask.variant == .fresh {
                #expect(found.contains(Found(row, "common")), "\(ask): \(found)")
            } else {
                #expect(!found.contains { $0.row == row }, "\(ask): \(found)")
            }
        }
    }
}

enum Settings120Child {
    /// The config asked for. `fresh`, the contract's fresh install: `Config.default` with Chinese and English as inputs,
    /// signed in to AllInOneIME Cloud. Then as that: English the only input; "Use the selected text" off; an app with a
    /// previous per-app setting (its results typed out); a provider with a key (the Claude API); Amazon Bedrock; a
    /// jargon list named.
    enum Variant: String, Sendable {
        case fresh, englishOnly, selectionOff, previous, keyed, bedrock, jargon
    }

    /// What the child is asked: "facts" (the pages, their parents, each row's page, the Doctor's areas' pages),
    /// "counts" (how many rows each page shows with the config, and which rows are shown), "titles" (the pages' titles
    /// in the interface language), or a search (`query`: "title:<row>", the row's own title in the interface language,
    /// or what is typed).
    struct Ask: Hashable, CustomStringConvertible, Sendable {
        var variant: Variant
        var interface: String
        var query: String
        init(_ variant: Variant, _ interface: String, _ query: String) { (self.variant, self.interface, self.query) = (variant, interface, query) }
        var argument: String { [variant.rawValue, interface, query].joined(separator: "\t") }
        var description: String { "\(variant.rawValue), interface \(interface): \"\(query)\"" }
    }

    /// A row found, for the input method's `SettingsSpot` (which can't be imported): its raw value, and its page's.
    struct Found: Hashable, CustomStringConvertible {
        var row: String
        var page: String
        init(_ row: String, _ page: String) { (self.row, self.page) = (row, page) }
        var description: String { row + " (" + page + ")" }
    }

    /// What the child printed: each line a tag, its keys and a value, tab-separated.
    struct Report: CustomStringConvertible {
        var values: [String: String]
        var status: Int32
        var output: String
        /// The value of the line `tag` with these keys.
        func value(_ tag: String, _ keys: String...) -> String? { values[([tag] + keys).joined(separator: "\t")] }
        func count(_ variant: Variant, _ page: String) -> Int? { value("COUNT", variant.rawValue, page).flatMap { Int($0) } }
        func countText(_ variant: Variant, _ page: String) -> String { value("COUNT", variant.rawValue, page) ?? "?" }
        /// The rows `variant`'s config shows.
        func shown(_ variant: Variant) -> Set<String> {
            Set(value("SHOWN", variant.rawValue)?.split(separator: ",").map(String.init) ?? [])
        }
        func found(_ ask: Ask) -> [Found]? {
            value("FOUND", ask.variant.rawValue, ask.interface, ask.query).map { list in
                list.split(separator: ",").compactMap { pair in
                    let parts = pair.split(separator: ":").map(String.init)
                    return parts.count == 2 ? Found(parts[0], parts[1]) : nil
                }
            }
        }
        var description: String { "(the child exited \(status)):\n\(output)" }
    }

    struct Failure: Error, CustomStringConvertible { var description: String }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    /// The child run with `asks`, what it printed read back.
    static func run(_ asks: [Ask]) throws -> Report {
        let executable = try compiled.get()
        let fm = FileManager.default
        // The child's home: never the user's config.
        let home = fm.temporaryDirectory.appendingPathComponent("settings120-home-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let result = try command(executable, asks.map(\.argument), environment: ["CFFIXED_USER_HOME": home.path, "HOME": home.path],
                                 timeout: 60)
        var values: [String: String] = [:]
        for line in result.output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 2, let tag = fields.first, tag == tag.uppercased(), tag != "FAIL" else { continue }
            values[fields.dropLast().joined(separator: "\t")] = fields.last
        }
        if result.status != 0 { throw Failure(description: "the child failed (\(result.status)):\n\(result.output)") }
        return Report(values: values, status: result.status, output: result.output)
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("settings120-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        // main.swift as written up to its dispatch, then the harness.
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try (String(main[..<cut.upperBound]) + Settings120Harness.swift).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        // The Mac library, the core and librime's wrapper, as `swift test` built them.
        let executable = scratch.appendingPathComponent("settings120")
        let swift = try SourceCompiler.compile(repository: repository, sources: [mainFile.path] + others,
            executable: executable,
            timeout: 900)
        guard swift.status == 0 else { throw Failure(description: "compiling Sources/AllInOneIME with the harness:\n\(swift.output)") }
        return executable
    }

    private static func command(_ executable: URL, _ arguments: [String], environment: [String: String] = [:],
                                timeout: TimeInterval) throws -> (status: Int32, output: String) {
        // A file, not a pipe: a long output never blocks the child.
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("settings120-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: log)
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = repository
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.5)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw Failure(description: "timed out: \(executable.lastPathComponent) \(arguments.first ?? "")\n"
                          + ((try? String(contentsOf: log, encoding: .utf8)) ?? ""))
        }
        return (process.terminationStatus, (try? String(contentsOf: log, encoding: .utf8)) ?? "")
    }
}

/// What follows main.swift's `let arguments = …` in the child: each argument a variant of the config, an interface
/// language and a query (tab-separated), answered in lines of a tag, keys and a value (tab-separated): "facts" (FIRST,
/// SIDEBAR, GROUPS, CASE, PARENT, SPOTS, SPOT, PLACES, AREA), "counts" (COUNT, SHOWN), "titles" (TITLE), or a search as
/// the sidebar searches (FOUND: the rows found, each with its page). Only the contract's names of #120 and what the
/// window had before (`SettingsSpot`'s cases, `title`, `isShown`, `search`, `SettingsPage.spots`) are used.
private enum Settings120Harness {
    static let swift = #"""

// MARK: - Settings120MacTests' child (in place of main.swift's dispatch)

MainActor.assumeIsolated {
    // Never the user's config: the test's home.
    let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
    guard !home.isEmpty, Config.defaultURL.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path) else {
        print("FAIL the config file isn't in the test's home: \(Config.defaultURL.path)")
        exit(3)
    }
    // The contract's pages by their raw values; "general" and "input" are gone.
    let named = ["common", "ai", "week", "commands", "more", "about", "inputAndKeys", "suggestions", "privacy", "interface",
                 "advanced"]
    let pages = named.compactMap { SettingsPage(rawValue: $0) }
    // Where a row may live: a sidebar page other than More Settings, or a group.
    let places = SettingsPage.sidebar.filter { $0 != .more } + SettingsPage.groups
    for argument in arguments {
        let parts = argument.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else {
            print("FAIL usage: VARIANT<tab>INTERFACE<tab>QUERY, not \(argument)")
            exit(2)
        }
        let (variant, interface, query) = (parts[0], parts[1], parts[2])
        // The fresh install: Chinese and English as inputs, signed in to AllInOneIME Cloud.
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.ai = .provider(.hosted)
        switch variant {
        case "fresh": break
        case "englishOnly": config.setOrder([Language.english])
        case "selectionOff": config.useSelection = false
        case "previous": config.appProfiles["com.example.editor"] = AppProfile(typeOut: true)
        case "keyed": config.ai = .provider(.anthropic)
        case "bedrock": config.ai = .provider(.bedrock)
        case "jargon": config.jargonFile = "~/team-jargon.txt"
        default:
            print("FAIL no variant \(variant)")
            exit(2)
        }
        config.uiLanguage = interface
        UIText.choice = interface
        switch query {
        case "facts":
            print("FIRST\t\(SettingsView.firstPage.rawValue)")
            print("SIDEBAR\t\(SettingsPage.sidebar.map(\.rawValue).joined(separator: ","))")
            print("GROUPS\t\(SettingsPage.groups.map(\.rawValue).joined(separator: ","))")
            for name in named + ["general", "input"] {
                print("CASE\t\(name)\t\(SettingsPage(rawValue: name) == nil ? 0 : 1)")
            }
            for page in pages {
                print("PARENT\t\(page.rawValue)\t\(page.parent?.rawValue ?? "none")")
            }
            print("SPOTS\t\(SettingsSpot.allCases.map(\.rawValue).joined(separator: ","))")
            for spot in SettingsSpot.allCases {
                print("SPOT\t\(spot.rawValue)\t\(spot.page.rawValue)")
                print("PLACES\t\(spot.rawValue)\t\(places.filter { $0.spots.contains(spot) }.map(\.rawValue).joined(separator: ","))")
            }
            for area in Doctor.Area.allCases {
                print("AREA\t\(area.rawValue)\t\(SettingsPage.of(area).rawValue)")
            }
        case "counts":
            for page in pages {
                print("COUNT\t\(variant)\t\(page.rawValue)\t\(page.shownCount(config))")
            }
            print("SHOWN\t\(variant)\t\(SettingsSpot.allCases.filter { $0.isShown(config) }.map(\.rawValue).joined(separator: ","))")
        case "titles":
            for page in pages {
                print("TITLE\t\(interface)\t\(page.rawValue)\t\(page.title)")
            }
        default:
            // A row's own title, as the interface says it; else what is typed.
            let typed: String
            if query.hasPrefix("title:") {
                guard let spot = SettingsSpot(rawValue: String(query.dropFirst("title:".count))) else {
                    print("FAIL no row \(query)")
                    exit(2)
                }
                typed = spot.title
            } else {
                typed = query
            }
            // As the sidebar searches (SettingsWindow: what is typed in its search field, with the window's config).
            let found = SettingsSpot.search(typed, trigger: config.commandTrigger, config: config)
            print("FOUND\t\(variant)\t\(interface)\t\(query)\t\(found.map { $0.rawValue + ":" + $0.page.rawValue }.joined(separator: ","))")
        }
    }
    fflush(stdout)
}
exit(0)
"""#
}
