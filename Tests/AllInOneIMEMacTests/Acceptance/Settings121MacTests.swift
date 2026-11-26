import AllInOneIMECore
import Foundation
import Testing

// #121's cards as retained by #161: the chosen AI has its own card above a folded list of other AI cards. These
// acceptance tests check the cards when the list is unfolded; Settings161MacTests checks the fold itself.
//
// The #121 properties unchanged by #161, as seen here:
//   1. Every offered other choice is a card in its `AIChoice.Group`, when the list is unfolded.
//   2. "and one click chooses": a card's pick, which is `SettingsModel.choose`, makes that choice the AI.
//   3. The chosen card says 「正在使用」 / 'In use'; no other card does (`AIChoiceCard.caption`).
//   4. "Unchosen cards never use the problem color": "A card that isn't chosen shows its status in secondary gray, never
//      orange", for every kind of status (not signed in, not installed, can't start, no key, no AWS profile, no AWS
//      credentials, Apple's model not available …) and for every card of a Mac with nothing set up.
//   5. "The search's AI terms ('kiro', 'bedrock', '订阅') still land on the AI page."
//   6. "There is no 「更换 ▾」": the input method's sources say it nowhere.
// Not seen here: the page as drawn (the outline, the gray and the orange themselves, the chosen AI's own rows above the
// cards, the AI commands below), and the CLI checks while the list is folded (the cache has AISignInCacheAcceptanceTests).
//
// The input method's own code can't be imported here (it is an executable target): as Settings120MacTests does it, all
// of Sources/AllInOneIME is compiled into a child process, with the Mac library, the core and librime, as the input
// method is built. Only main.swift's dispatch (what follows `let arguments = …`) is replaced: the child prints the
// cards and what each says, for each AI chosen in turn, in each interface language. The child's home is a folder of the
// test's, its keychain in memory: nothing of the user's is read, and no CLI is run.

@Suite(.serialized)
struct Settings121MacTests {
    typealias Report = Settings121Child.Report

    /// The interface languages (config `uiLanguage`).
    static let interfaces = ["en", "zh"]
    /// "The chosen card … says 「正在使用」 / 'In use'".
    static let inUse = ["en": "In use", "zh": "正在使用"]

    /// What the Mac has (the child's `AIFacts`): nothing set up, as "on a fresh install most cards are not set up" (each
    /// CLI signed out, not installed or unable to start; no key; no AWS profile; signed out of AllInOneIME Cloud; Apple
    /// Intelligence off); everything set up (and no Apple model on this system: not offered); nothing looked at yet.
    static let variants = ["unset", "setUp", "checking"]
    /// Whether the variant's system offers Apple's on-device model (`AppleModelAvailability.isOffered`).
    static let appleOffered = ["unset": true, "setUp": false, "checking": true]

    /// Every AI there is to choose (`AIChoice.all`), by `id`.
    static let choices = AIChoice.all.map(\.id)
    /// The choices offered whatever the Mac has: the CLIs, the API-key providers, Amazon Bedrock. (AllInOneIME Cloud is
    /// offered once the service is set up, Apple's model where the system has it, and the one chosen always.)
    static let alwaysOffered = AIChoice.all.filter { $0 != .provider(.hosted) && $0 != .provider(.apple) }.map(\.id)

    /// Every kind of status a card may say (the child's `AIStatus` values, by these names), and the ones that are a
    /// problem (`AIStatus.isProblem`: what the chosen AI says in orange).
    static let statuses = ["unknown", "signedIn", "signedOut", "notInstalled", "cannotStart", "keySaved", "keyShell", "keyMissing",
                           "keyLoading", "aws", "noAWSProfile", "noAWSCredentials", "appleAvailable", "appleUnsupportedSystem",
                           "appleDeviceNotEligible", "appleNotEnabled", "appleModelNotReady"]
    static let problems = ["signedOut", "notInstalled", "cannotStart", "keyMissing", "noAWSProfile", "noAWSCredentials",
                           "appleUnsupportedSystem", "appleDeviceNotEligible", "appleNotEnabled", "appleModelNotReady"]
    /// What the problem ones say on their card, as today.
    static let problemTexts: [String: (en: String, zh: String)] = [
        "signedOut": ("Not signed in", "没登录"), "notInstalled": ("Not installed", "没装"), "cannotStart": ("Can't start", "启动不了"),
        "keyMissing": ("No key", "没填 Key"), "noAWSProfile": ("No such AWS profile", "没有这个 AWS profile"),
    ]

    /// Each interface, each variant of what the Mac has, each AI chosen in turn.
    static var pages: [(interface: String, variant: String, chosen: String)] {
        interfaces.flatMap { interface in variants.flatMap { variant in choices.map { (interface, variant, $0) } } }
    }

    /// #161 keeps #121's cards for the other choices when the disclosure is open. The chosen choice has its own
    /// outlined card above the disclosure, so only the other offered choices belong to this grid.
    @Test func everyOtherOfferedChoiceIsACardWhenUnfolded() throws {
        let report = try Settings121Child.report.get()
        for (interface, variant, chosen) in Self.pages {
            let page = "\(interface), \(variant), \(chosen) chosen"
            let offered = try #require(report.list("OFFERED", interface, variant, chosen), "\(page): no choices told: \(report)")
            let cards = try #require(report.list("CARDS", interface, variant, chosen), "\(page): no cards told: \(report)")
            #expect(cards == offered.filter { $0 != chosen }, "\(page): the other cards are \(cards), the choices offered \(offered)")
            #expect(cards.count == Set(cards).count, "\(page): a card twice: \(cards)")
            #expect(!cards.contains(chosen), "\(page): the chosen AI is repeated among the other cards: \(cards)")
            #expect(Set(cards).isSuperset(of: Set(Self.alwaysOffered).subtracting([chosen])), "\(page): no card for \(Set(Self.alwaysOffered).subtracting(cards).subtracting([chosen]).sorted())")
            #expect(Set(cards).isSubset(of: Self.choices), "\(page): cards for \(Set(cards).subtracting(Self.choices).sorted())")
            let apple = AIChoice.provider(.apple).id
            #expect(cards.contains(apple) == (Self.appleOffered[variant] == true && chosen != apple), "\(page): Apple's other card: \(cards)")
            // The cards in `AIChoice.all`'s order: each group's, the groups in order.
            #expect(cards == Self.choices.filter { cards.contains($0) }, "\(page): the cards' order: \(cards)")
            let groups = try #require(report.list("GROUPS", interface, variant, chosen), "\(page): no groups told: \(report)")
            #expect(groups == AIChoice.Group.allCases.map(\.rawValue).filter { groups.contains($0) }, "\(page): the groups' order: \(groups)")
            var grouped: [String] = []
            for group in groups {
                let under = try #require(report.list("GROUP", interface, variant, chosen, group), "\(page): \(group) has no cards: \(report)")
                #expect(!under.isEmpty, "\(page): \(group) is shown with no card")
                for card in under {
                    #expect(AIChoice(id: card)?.group.rawValue == group, "\(page): \(card) is under \(group)")
                }
                grouped += under
            }
            #expect(grouped == cards, "\(page): the groups hold \(grouped), the cards are \(cards)")
        }
    }

    /// #161 moves the outlined chosen card above the other cards; no card under the disclosure says "In use".
    @Test func noOtherCardIsInUseForEachAIChosenInTurn() throws {
        let report = try Settings121Child.report.get()
        for (interface, variant, chosen) in Self.pages {
            let page = "\(interface), \(variant), \(chosen) chosen"
            let cards = try #require(report.list("CARDS", interface, variant, chosen), "\(page): no cards told: \(report)")
            let inUse = cards.filter { report.value("TONE", interface, variant, chosen, $0) == "inUse" }
            #expect(inUse.isEmpty, "\(page): other cards in use are \(inUse)")
            let says = cards.filter { report.value("TEXT", interface, variant, chosen, $0) == Self.inUse[interface] }
            #expect(says.isEmpty, "\(page): other cards saying \(Self.inUse[interface] ?? "?") are \(says)")
        }
    }

    /// "A card that isn't chosen shows its status in secondary gray, never orange: on a fresh install most cards are not
    /// set up": every card but the chosen one says its status's text, in `.secondary`. With nothing set up, the cards
    /// with a problem to tell are most of them, and each is gray all the same.
    @Test func everyUnchosenCardSaysItsStatusInSecondary() throws {
        let report = try Settings121Child.report.get()
        for (interface, variant, chosen) in Self.pages {
            let page = "\(interface), \(variant), \(chosen) chosen"
            let cards = try #require(report.list("CARDS", interface, variant, chosen), "\(page): no cards told: \(report)")
            var problems = 0
            for card in cards where card != chosen {
                let tone = report.value("TONE", interface, variant, chosen, card)
                #expect(tone == "secondary", "\(page): \(card)'s caption is \(tone ?? "not told")")
                let status = try #require(report.value("STATUSTEXT", interface, variant, chosen, card), "\(page): \(card)'s status not told")
                #expect(!status.isEmpty, "\(page): \(card) has no status to say")
                #expect(report.value("TEXT", interface, variant, chosen, card) == status,
                        "\(page): \(card) says \(report.value("TEXT", interface, variant, chosen, card) ?? "nothing"), its status \(status)")
                if report.value("STATUSPROBLEM", interface, variant, chosen, card) == "1" { problems += 1 }
            }
            // The fresh install the issue speaks of: the test's cards do have problems to tell.
            if variant == "unset" { #expect(problems >= cards.count - 1, "\(page): only \(problems) of \(cards.count) cards have a problem") }
        }
    }

    /// The same for every kind of status there is (`AIStatus`), the problem ones too ("never orange"): not chosen, the
    /// caption is the status's text in `.secondary`; chosen, it is 「正在使用」 / "In use" in `.inUse`, whatever the
    /// status.
    @Test func everyKindOfStatusIsSecondaryOnAnUnchosenCard() throws {
        let report = try Settings121Child.report.get()
        for interface in Self.interfaces {
            for kind in Self.statuses {
                let status = try #require(report.value("KINDSTATUS", interface, kind), "\(interface), \(kind): not told: \(report)")
                #expect(!status.isEmpty, "\(interface): \(kind) has no text")
                #expect(report.value("KINDPROBLEM", interface, kind) == (Self.problems.contains(kind) ? "1" : "0"),
                        "\(interface): \(kind) a problem: \(report.value("KINDPROBLEM", interface, kind) ?? "?")")
                #expect(report.value("KINDTONE", interface, kind, "unchosen") == "secondary",
                        "\(interface): \(kind), not chosen, is \(report.value("KINDTONE", interface, kind, "unchosen") ?? "not told")")
                #expect(report.value("KINDTEXT", interface, kind, "unchosen") == status,
                        "\(interface): \(kind), not chosen, says \(report.value("KINDTEXT", interface, kind, "unchosen") ?? "nothing"), not \(status)")
                #expect(report.value("KINDTONE", interface, kind, "chosen") == "inUse",
                        "\(interface): \(kind), chosen, is \(report.value("KINDTONE", interface, kind, "chosen") ?? "not told")")
                #expect(report.value("KINDTEXT", interface, kind, "chosen") == Self.inUse[interface],
                        "\(interface): \(kind), chosen, says \(report.value("KINDTEXT", interface, kind, "chosen") ?? "nothing")")
            }
            // What the problem ones say, as their cards said it before.
            for (kind, text) in Self.problemTexts {
                #expect(report.value("KINDTEXT", interface, kind, "unchosen") == (interface == "zh" ? text.zh : text.en),
                        "\(interface): \(kind) says \(report.value("KINDTEXT", interface, kind, "unchosen") ?? "nothing")")
            }
        }
    }

    /// "A click on a card chooses it, as picking does today (`SettingsModel.choose`)": "one click chooses". Each card's
    /// pick in turn makes its choice the AI (`Config.ai`), and then that card alone is the one in use.
    @Test func aClickOnACardChoosesIt() throws {
        let report = try Settings121Child.report.get()
        for choice in Self.choices {
            #expect(report.value("PICKED", choice) == choice, "\(choice) picked, the AI is \(report.value("PICKED", choice) ?? "not told"): \(report)")
            #expect(report.list("PICKEDINUSE", choice) == [choice], "\(choice) picked, in use: \(report.list("PICKEDINUSE", choice) ?? [])")
        }
    }

    /// "The search's AI terms ('kiro', 'bedrock', '订阅') still land on the AI page": each finds a row of the AI page, in
    /// either interface language.
    @Test func theSearchsAITermsLandOnTheAIPage() throws {
        let report = try Settings121Child.report.get()
        for interface in Self.interfaces {
            for term in ["kiro", "bedrock", "订阅"] {
                let found = try #require(report.list("FOUND", interface, term), "\(interface): \(term) not searched: \(report)")
                #expect(found.contains { $0.hasSuffix(":ai") }, "\(interface): \"\(term)\" finds \(found), nothing on the AI page")
            }
        }
    }

    /// "There is no 「更换 ▾」 and no Cancel": nothing in the input method's sources says 「更换 ▾」 or "Change ▾" any more
    /// (read from the sources, comments apart: what a view draws can't be asked here).
    @Test func nothingSaysChangeAnyMore() throws {
        let sources = Settings121Child.repository.appendingPathComponent("Sources/AllInOneIME")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty, "no sources in \(sources.path)")
        for file in files {
            let code = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
                .map { line in line.range(of: "//").map { line[..<$0.lowerBound] } ?? line }
                .joined(separator: "\n")
            for gone in ["更换 ▾", "Change ▾"] {
                #expect(!code.contains(gone), "\(file.lastPathComponent) still says \(gone)")
            }
        }
    }
}

enum Settings121Child {
    /// What the child printed: each line a tag, its keys and a value, tab-separated.
    struct Report: CustomStringConvertible {
        var values: [String: String]
        var status: Int32
        var output: String
        /// The value of the line `tag` with these keys.
        func value(_ tag: String, _ keys: String...) -> String? { values[([tag] + keys).joined(separator: "\t")] }
        /// The comma-separated value of the line `tag` with these keys.
        func list(_ tag: String, _ keys: String...) -> [String]? {
            values[([tag] + keys).joined(separator: "\t")].map { $0.split(separator: ",").map(String.init) }
        }
        /// The child's output is long (a line for each card of each page): its failures, else its first lines.
        var description: String {
            let lines = output.split(separator: "\n")
            let failures = lines.filter { $0.hasPrefix("FAIL") }
            return "(the child exited \(status)):\n" + (failures.isEmpty ? lines.prefix(12) : failures.prefix(12)).joined(separator: "\n")
        }
    }

    struct Failure: Error, CustomStringConvertible { var description: String }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }
    /// The child run once, for every test: everything it is asked, in both interface languages.
    static let report: Result<Report, Error> = Result { try run(Settings121MacTests.interfaces) }

    /// The child run with the interface languages `interfaces`, what it printed read back.
    static func run(_ interfaces: [String]) throws -> Report {
        let executable = try compiled.get()
        let fm = FileManager.default
        // The child's home: never the user's config.
        let home = fm.temporaryDirectory.appendingPathComponent("settings121-home-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let result = try command(executable, interfaces, environment: ["CFFIXED_USER_HOME": home.path, "HOME": home.path],
                                 timeout: 120)
        var values: [String: String] = [:]
        for line in result.output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 2, let tag = fields.first, tag == tag.uppercased(), tag != "FAIL" else { continue }
            values[fields.dropLast().joined(separator: "\t")] = fields.last
        }
        if result.status != 0 { throw Failure(description: "the child failed (\(result.status)):\n\(result.output.suffix(4000))") }
        return Report(values: values, status: result.status, output: result.output)
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("settings121-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        // main.swift as written up to its dispatch, then the harness.
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try (String(main[..<cut.upperBound]) + Settings121Harness.swift).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        // The Mac library, the core and librime's wrapper, as `swift test` built them.
        let executable = scratch.appendingPathComponent("settings121")
        let swift = try SourceCompiler.compile(repository: repository, sources: [mainFile.path] + others,
            executable: executable,
            timeout: 900)
        guard swift.status == 0 else { throw Failure(description: "compiling Sources/AllInOneIME with the harness:\n\(swift.output)") }
        return executable
    }

    private static func command(_ executable: URL, _ arguments: [String], environment: [String: String] = [:],
                                timeout: TimeInterval) throws -> (status: Int32, output: String) {
        // A file, not a pipe: a long output never blocks the child.
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("settings121-\(UUID().uuidString).log")
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

/// What follows main.swift's `let arguments = …` in the child: each argument an interface language, answered in lines of
/// a tag, keys and a value (tab-separated). For each kind of status: what it says and whether it is a problem
/// (KINDSTATUS, KINDPROBLEM), and its card's caption chosen and not (KINDTONE, KINDTEXT). For each variant of what the
/// Mac has and each AI chosen in turn: the choices offered (OFFERED), the grid's cards (CARDS) and groups (GROUPS,
/// GROUP), and each card's caption (TONE, TEXT) and status (STATUSTEXT, STATUSPROBLEM). The search's AI terms (FOUND).
/// Once: each card picked in turn (PICKED: the AI then; PICKEDINUSE: the cards in use then). Only the contract's names
/// of #121 (`AIChoiceCard.caption`, `Tone`, `AIChoicesGrid(chosen:groups:status:pick:)`) and what was there before are
/// used.
private enum Settings121Harness {
    static let swift = #"""

// MARK: - Settings121MacTests' child (in place of main.swift's dispatch)

// Never the user's keychain: an in-memory one, and the settings look up no keys (as the self-test has it).
Platform.current.secrets = .inMemory()
MainActor.assumeIsolated { SettingsModel.looksUpKeys = false }

MainActor.assumeIsolated {
    // Never the user's config: the test's home.
    let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
    guard !home.isEmpty, Config.defaultURL.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path) else {
        print("FAIL the config file isn't in the test's home: \(Config.defaultURL.path)")
        exit(3)
    }
    func name(_ tone: AIChoiceCard.Tone) -> String { tone == .inUse ? "inUse" : tone == .secondary ? "secondary" : "other" }
    func ids(_ choices: [AIChoice]) -> String { choices.map(\.id).joined(separator: ",") }

    // Every kind of status a card may say.
    let statuses: [(String, AIStatus)] = [
        ("unknown", .unknown), ("signedIn", .signedIn), ("signedOut", .signedOut),
        ("notInstalled", .notInstalled(program: "kiro-cli")), ("cannotStart", .cannotStart),
        ("keySaved", .key(.saved(ending: "MPLE"))), ("keyShell", .key(.shell("EXAMPLE_API_KEY"))), ("keyMissing", .key(.missing)),
        ("keyLoading", .key(.loading)),
        ("aws", .aws(profile: "default", region: "us-west-2")), ("noAWSProfile", .noAWSProfile("work")),
        ("noAWSCredentials", .noAWSCredentials("work")),
        ("appleAvailable", .apple(.available)), ("appleUnsupportedSystem", .apple(.unsupportedSystem)),
        ("appleDeviceNotEligible", .apple(.deviceNotEligible)), ("appleNotEnabled", .apple(.appleIntelligenceNotEnabled)),
        ("appleModelNotReady", .apple(.modelNotReady)),
    ]
    // What the Mac has: nothing set up (a fresh install's cards), everything set up, nothing looked at yet.
    let keyed: [Provider] = [.anthropic, .gemini, .openai]
    let macs: [(String, AIFacts)] = [
        ("unset", AIFacts(sessions: [.claude: .signedOut, .codex: .notInstalled, .antigravity: .cannotStart, .kiro: .notInstalled],
                          keys: Dictionary(uniqueKeysWithValues: keyed.map { ($0, KeyState.missing) }),
                          hostedSignedIn: false, awsProfiles: [], apple: .appleIntelligenceNotEnabled)),
        ("setUp", AIFacts(sessions: Dictionary(uniqueKeysWithValues: SessionAgent.allCases.map { ($0, ClaudeSession.Availability.ready) }),
                          keys: Dictionary(uniqueKeysWithValues: keyed.map { ($0, KeyState.saved(ending: "MPLE")) }),
                          hostedSignedIn: true,
                          awsProfiles: [AWSProfileSummary(name: Config.default.awsProfile, region: "us-west-2", kind: .staticKeys)],
                          apple: .unsupportedSystem)),
        ("checking", AIFacts(sessions: [:], keys: [:], hostedSignedIn: false, awsProfiles: nil, apple: .available)),
    ]

    for interface in arguments {
        UIText.choice = interface
        for (kind, status) in statuses {
            print("KINDSTATUS\t\(interface)\t\(kind)\t\(status.text)")
            print("KINDPROBLEM\t\(interface)\t\(kind)\t\(status.isProblem ? 1 : 0)")
            for chosen in [false, true] {
                let caption = AIChoiceCard.caption(status, chosen: chosen)
                print("KINDTONE\t\(interface)\t\(kind)\t\(chosen ? "chosen" : "unchosen")\t\(name(caption.tone))")
                print("KINDTEXT\t\(interface)\t\(kind)\t\(chosen ? "chosen" : "unchosen")\t\(caption.text)")
            }
        }
        for (variant, facts) in macs {
            for chosen in AIChoice.all {
                var config = Config.default
                config.uiLanguage = interface
                config.ai = chosen
                let page = "\(interface)\t\(variant)\t\(chosen.id)"
                // The page's cards: the grid, with the choices offered (as the page makes it).
                let offered = AIChoice.groups(apple: facts.apple, keeping: chosen)
                let others = offered.compactMap { entry -> (group: AIChoice.Group, choices: [AIChoice])? in
                    let choices = entry.choices.filter { $0 != chosen }
                    return choices.isEmpty ? nil : (entry.group, choices)
                }
                let grid = AIChoicesGrid(chosen: config.ai, groups: others, status: { facts.status($0, config: config) }, pick: { _ in })
                print("OFFERED\t\(page)\t\(ids(offered.flatMap(\.choices)))")
                print("CARDS\t\(page)\t\(ids(grid.groups.flatMap(\.choices)))")
                print("GROUPS\t\(page)\t\(grid.groups.map(\.group.rawValue).joined(separator: ","))")
                for entry in grid.groups {
                    print("GROUP\t\(page)\t\(entry.group.rawValue)\t\(ids(entry.choices))")
                    for card in entry.choices {
                        let status = grid.status(card)
                        let caption = AIChoiceCard.caption(status, chosen: card == grid.chosen)
                        print("TONE\t\(page)\t\(card.id)\t\(name(caption.tone))")
                        print("TEXT\t\(page)\t\(card.id)\t\(caption.text)")
                        print("STATUSTEXT\t\(page)\t\(card.id)\t\(status.text)")
                        print("STATUSPROBLEM\t\(page)\t\(card.id)\t\(status.isProblem ? 1 : 0)")
                    }
                }
            }
        }
        // As the sidebar searches (SettingsWindow: what is typed in its search field, with the window's config): a fresh
        // install, Chinese and English as inputs, AllInOneIME Cloud chosen.
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.ai = .provider(.hosted)
        config.uiLanguage = interface
        for term in ["kiro", "bedrock", "订阅"] {
            let found = SettingsSpot.search(term, trigger: config.commandTrigger, config: config)
            print("FOUND\t\(interface)\t\(term)\t\(found.map { $0.rawValue + ":" + $0.page.rawValue }.joined(separator: ","))")
        }
    }

    // A click on a card: its pick is `SettingsModel.choose` (a model that writes nothing, in the test's home).
    UIText.choice = "en"
    let model = SettingsModel(persists: false)
    for choice in AIChoice.all {
        let facts = model.aiFacts
        let grid = AIChoicesGrid(chosen: model.config.ai, groups: AIChoice.groups(apple: facts.apple, keeping: choice),
                                 status: { facts.status($0, config: model.config) }, pick: { model.choose($0) })
        grid.pick(choice)
        print("PICKED\t\(choice.id)\t\(model.config.ai.id)")
        // The cards as the page shows them now.
        let now = model.config.ai
        let inUse = AIChoice.groups(apple: facts.apple, keeping: now).flatMap(\.choices).filter { card in
            AIChoiceCard.caption(model.aiFacts.status(card, config: model.config), chosen: card == now).tone == .inUse
        }
        print("PICKEDINUSE\t\(choice.id)\t\(ids(inUse))")
    }
    fflush(stdout)
}
exit(0)
"""#
}
