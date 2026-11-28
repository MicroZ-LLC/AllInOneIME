import AllInOneIMECore
import Foundation
import Testing

// Independent acceptance contract for the Typing picker split (Settings → Typing, 0.7.6, spec of 2026-11-27): the
// settings search, written from the spec's text only. Implementers do not edit Acceptance tests (AGENTS.md rule 11).
//
// "Settings search still finds each scheme by name (xiaohe, 小鹤, ziranma, 自然码, wubi, 五笔, zhuyin, 注音 ...) and lands on
// the right row (row 1 for full/Zhuyin/Wubi/"shuangpin"; the scheme names land on the Typing section where the row is
// visible; the Shuangpin row must be visible when the search lands on a scheme name -> selecting that result must not
// leave the user on a hidden row)." Row 2 (双拼方案 / Shuangpin scheme) is shown only while Shuangpin is chosen.
//
// As seen here: with each way of typing saved (full pinyin, Xiaohe, Ziranma, Zhuyin, Wubi), in either interface
// language, searching a way's word (全拼, shuangpin, 双拼, zhuyin, 注音, wubi, 五笔 …) lists the Typing row
// (`SettingsSpot.pinyinScheme`, row 1) first; searching a Shuangpin scheme's name (xiaohe, 小鹤, ziranma, 自然码 …) lists
// the Typing row first whenever Shuangpin isn't chosen (row 2 is hidden then), and with Shuangpin chosen lists first a
// row of Common's that is shown; and no search lists a row the config doesn't show (nor one whose outlined row it
// doesn't show).
// Not seen here: the window as drawn (the two rows, the outline), what picking a result scrolls to.
//
// The input method's own code can't be imported here (it is an executable target): as Issue49Tests does it, all of
// Sources/AllInOneIME is compiled into a child process, with the Mac library, the core and librime, as the input method
// is built. Only main.swift's dispatch (what follows `let arguments = …`) is replaced: the child searches the settings
// as the sidebar does (`SettingsSpot.search(typed, trigger: config.commandTrigger, config: config)`), with the way of
// typing the test saves, in each interface language, and prints what each search lists. The child's home is a folder of
// the test's: nothing reads the user's config.

@Suite(.serialized)
struct TypingPickerSearchTests {
    /// What `Config.pinyinScheme` has saved: full pinyin, Shuangpin (Xiaohe, Ziranma), Zhuyin, Wubi 86.
    static let saved = ["full", "double_pinyin_flypy", "double_pinyin", "bopomofo", "wubi86"]

    /// The Typing row (row 1: 打字方式 / Typing), as `SettingsSpot` names it.
    static let typingRow = "pinyinScheme"

    /// Every way and every scheme is found, and lands on the Typing row (row 1) where row 2 isn't shown.
    @Test(arguments: saved)
    func eachWayAndSchemeIsFoundOnTheTypingRow(_ scheme: String) throws {
        let report = try TypingPickerSearchChild.run(scheme: scheme)
        #expect(report.searches.count == TypingPickerSearchChild.searches.count, "the child didn't search every time: \(report)")
        let shuangpin = scheme.hasPrefix("double_pinyin")
        for search in report.searches {
            let searched = "\(scheme) saved, interface \(search.interface): searching \"\(search.query)\""
            let first = try #require(search.found.first, "\(searched) finds nothing")
            if TypingPickerSearchChild.wayWords.contains(search.query) || !shuangpin {
                #expect(first.row == Self.typingRow, "\(searched) lands on \(first), not the Typing row: \(search.found)")
            } else {
                // Shuangpin chosen: row 2 is shown, below row 1; either is on Common's Typing.
                #expect(first.page == "common" && first.shown, "\(searched) lands on \(first): \(search.found)")
            }
        }
    }

    /// "Selecting that result must not leave the user on a hidden row": nothing a search lists is a row the saved way of
    /// typing doesn't show.
    @Test(arguments: saved)
    func noSearchListsAHiddenRow(_ scheme: String) throws {
        let report = try TypingPickerSearchChild.run(scheme: scheme)
        #expect(report.searches.count == TypingPickerSearchChild.searches.count, "the child didn't search every time: \(report)")
        for search in report.searches {
            for spot in search.found {
                #expect(spot.shown, "\(scheme) saved, interface \(search.interface): \"\(search.query)\" lists \(spot), not shown")
            }
        }
    }
}

enum TypingPickerSearchChild {
    /// Words for row 1's ways: full pinyin, Shuangpin, Zhuyin, Wubi, in either language.
    static let wayWords = ["全拼", "full pinyin", "shuangpin", "双拼", "zhuyin", "注音", "wubi", "五笔"]
    /// Shuangpin schemes' names (row 2's), in either language.
    static let schemeWords = ["xiaohe", "小鹤", "ziranma", "自然码", "微软", "sogou", "搜狗", "紫光", "拼音加加"]

    /// What the user searches the settings for, and in which interface language (config `uiLanguage`).
    static let searches: [(interface: String, query: String)] = ["en", "zh"].flatMap { interface in
        (wayWords + schemeWords).map { (interface, $0) }
    }

    /// A row a search lists, for the input method's `SettingsSpot` (which can't be imported): its raw value, its page's,
    /// and whether the config shows it (and the row outlined for it).
    struct Spot: Hashable, CustomStringConvertible {
        var row: String
        var page: String
        var shown: Bool
        var description: String { row + " (" + page + (shown ? "" : ", hidden") + ")" }
    }

    struct Search {
        var interface: String
        var query: String
        var found: [Spot]
    }

    struct Report: CustomStringConvertible {
        var searches: [Search]
        var status: Int32
        var output: String
        var description: String { "(the child exited \(status)):\n\(output)" }
    }

    struct Failure: Error, CustomStringConvertible { var description: String }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    /// The searches, with `scheme` saved as `Config.pinyinScheme` ("full" for full pinyin) and Chinese and English as
    /// the inputs.
    static func run(scheme: String) throws -> Report {
        let executable = try compiled.get()
        let fm = FileManager.default
        // The child's home: never the user's config.
        let home = fm.temporaryDirectory.appendingPathComponent("typing-picker-home-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let arguments = [scheme] + searches.flatMap { [$0.interface, $0.query] }
        let result = try command(executable, arguments, environment: ["CFFIXED_USER_HOME": home.path, "HOME": home.path], timeout: 60)
        if result.status != 0 { throw Failure(description: "the child failed (\(result.status)):\n\(result.output)") }
        let found = result.output.split(separator: "\n").filter { $0.hasPrefix("FOUND\t") }.compactMap { line -> Search? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 5 else { return nil }
            let spots = fields[4].split(separator: ",").compactMap { item -> Spot? in
                let parts = item.split(separator: ":").map(String.init)
                return parts.count == 3 ? Spot(row: parts[0], page: parts[1], shown: parts[2] == "1") : nil
            }
            return Search(interface: fields[2], query: fields[3], found: spots)
        }
        return Report(searches: found, status: result.status, output: result.output)
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("typing-picker-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        // main.swift as written up to its dispatch, then the harness.
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try (String(main[..<cut.upperBound]) + TypingPickerSearchHarness.swift).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        // The Mac library, the core and librime's wrapper, as `swift test` built them.
        let executable = scratch.appendingPathComponent("typing-picker-search")
        let swift = try SourceCompiler.compile(repository: repository, sources: [mainFile.path] + others,
            executable: executable,
            timeout: 900)
        guard swift.status == 0 else { throw Failure(description: "compiling Sources/AllInOneIME with the harness:\n\(swift.output)") }
        return executable
    }

    private static func command(_ executable: URL, _ arguments: [String], environment: [String: String] = [:],
                                timeout: TimeInterval) throws -> (status: Int32, output: String) {
        // A file, not a pipe: a long output never blocks the child.
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("typing-picker-\(UUID().uuidString).log")
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

/// What follows main.swift's `let arguments = …` in the child: the scheme saved (`Config.pinyinScheme`'s value, "full"
/// for full pinyin), then pairs of an interface language and a query; each searched as the sidebar searches, one
/// `FOUND` line each (the scheme, the interface, the query, then each row listed as raw value, page and 1 when shown).
/// Only what the window had before (`SettingsSpot.search`, `page`, `row`, `isShown`) is used.
private enum TypingPickerSearchHarness {
    static let swift = #"""

// MARK: - TypingPickerSearchTests' child (in place of main.swift's dispatch)

MainActor.assumeIsolated {
    // Never the user's config: the test's home.
    let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
    guard !home.isEmpty, Config.defaultURL.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path) else {
        print("FAIL the config file isn't in the test's home: \(Config.defaultURL.path)")
        exit(3)
    }
    guard let scheme = arguments.first, arguments.count % 2 == 1 else {
        print("FAIL usage: SCHEME [INTERFACE QUERY]…")
        exit(2)
    }
    // A fresh install's inputs, Chinese and English, with the way of typing saved as the test says.
    var config = Config.default
    config.setOrder([Language.chinese, .english])
    config.pinyinScheme = PinyinScheme(setting: scheme).setting
    guard config.typedPinyin.rawValue == scheme else {
        print("FAIL the scheme saved is \(config.typedPinyin.rawValue), not \(scheme)")
        exit(3)
    }
    for pair in stride(from: 1, to: arguments.count, by: 2) {
        let interface = arguments[pair], query = arguments[pair + 1]
        config.uiLanguage = interface
        UIText.choice = interface
        // As the sidebar searches (SettingsWindow: what is typed in its search field, with the window's config).
        let found = SettingsSpot.search(query, trigger: config.commandTrigger, config: config)
        let rows = found.map { spot in
            spot.rawValue + ":" + spot.page.rawValue + ":" + (spot.isShown(config) && spot.row.isShown(config) ? "1" : "0")
        }
        print("FOUND\t\(scheme)\t\(interface)\t\(query)\t\(rows.joined(separator: ","))")
    }
    fflush(stdout)
}
exit(0)
"""#
}
