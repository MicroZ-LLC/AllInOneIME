import Foundation
import Testing
@testable import AllInOneIMECore

/// Answers requests from a table of URL → (status, body), and records what was asked.
final class StubFetcher: PluginFetcher, @unchecked Sendable {
    var answers: [String: (Int, String)]
    private(set) var asked: [PluginRequest] = []

    init(_ answers: [String: (Int, String)] = [:]) { self.answers = answers }

    func fetch(_ requests: [PluginRequest]) -> [PluginResponse] {
        asked += requests
        return requests.map { request in
            guard let (status, body) = answers[request.url] else { return PluginResponse(error: "can't reach the host") }
            return PluginResponse(status: status, text: body)
        }
    }
}

struct PluginTests {
    func stockFolder() throws -> URL {
        try #require(Bundle.module.url(forResource: "stock", withExtension: nil, subdirectory: "Fixtures/plugins"))
    }

    func stockScript() throws -> String {
        try String(contentsOf: stockFolder().appendingPathComponent("main.js"), encoding: .utf8)
    }

    static func chart(_ symbol: String, _ name: String, _ price: Double, _ before: Double, _ currency: String) -> (Int, String) {
        (200, #"{"chart":{"result":[{"meta":{"symbol":"\#(symbol)","shortName":"\#(name)","currency":"\#(currency)","regularMarketPrice":\#(price),"chartPreviousClose":\#(before)}}],"error":null}}"#)
    }

    static func url(_ symbol: String) -> String {
        "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.!~*'()"))) ?? symbol)?range=1d&interval=1d"
    }

    // MARK: Manifest and store

    @Test func manifests() throws {
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: stockFolder().appendingPathComponent("plugin.json")))
        #expect(manifest.name == "stock" && manifest.type == .script && manifest.hosts == ["query1.finance.yahoo.com"])
        #expect(manifest.summary?.text(chinese: true).hasPrefix("股票行情") == true)
        #expect(manifest.problem(appVersion: "0.2.0") == nil)
        #expect(manifest.problem(appVersion: "0.1.9") == "needs AllInOneIME 0.2.0 or later")
        var newer = manifest
        newer.api = 2
        #expect(newer.problem(appVersion: "9.9.9")?.contains("plugin API") == true)
        var bad = manifest
        bad.script = "../evil.js"
        #expect(bad.problem(appVersion: "1.0") == "no script")
        bad = manifest
        bad.name = "Stock"
        #expect(bad.problem(appVersion: "1.0") != nil)
        // A summary may be plain text.
        let plain = try JSONDecoder().decode(PluginManifest.self, from: Data(#"{"name":"x","version":"1","type":"prompt","prompt":"Do it.","summary":"Plain"}"#.utf8))
        #expect(plain.summary == LocalizedText(en: "Plain") && plain.api == 1 && plain.hosts.isEmpty)
        #expect(SemVer.compare("0.10.0", "0.9.1") == 1 && SemVer.compare("1.0", "1.0.0") == 0 && SemVer.compare("1.2.0-beta", "1.3") == -1)
    }

    @Test func storeLoadsPluginsAndNoticesChangedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("plugins-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        // A library plugin (with its install record) and a local one.
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.copyItem(at: stockFolder(), to: root.appendingPathComponent("stock"))
        let files = ["plugin.json", "main.js"]
        let record = PluginInstallRecord(version: "1.0.0", files: Dictionary(uniqueKeysWithValues: files.map {
            ($0, PluginStore.sha256(of: root.appendingPathComponent("stock/\($0)"))!)
        }))
        try JSONEncoder().encode(record).write(to: root.appendingPathComponent("stock/install.json"))
        let local = root.appendingPathComponent("tone")
        try fm.createDirectory(at: local, withIntermediateDirectories: true)
        try Data(#"{"name":"tone","version":"0.1","type":"prompt","prompt":"Make it friendlier."}"#.utf8)
            .write(to: local.appendingPathComponent("plugin.json"))
        // Skipped: a folder named unlike its plugin, one without a manifest.
        try fm.copyItem(at: stockFolder(), to: root.appendingPathComponent("quotes"))
        try fm.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: true)

        var loaded = PluginStore.load(from: root, appVersion: "0.2.0")
        #expect(loaded.plugins.map(\.name) == ["stock", "tone"])
        #expect(loaded.plugins.map(\.isLocal) == [false, true])
        #expect(loaded.skipped.map(\.folder) == ["empty", "quotes"])

        // A library plugin edited after installing isn't used.
        try "function run() { return 'changed' }".write(to: root.appendingPathComponent("stock/main.js"), atomically: true, encoding: .utf8)
        loaded = PluginStore.load(from: root, appVersion: "0.2.0")
        #expect(loaded.plugins.map(\.name) == ["tone"])
        #expect(loaded.skipped.contains(PluginStore.Skipped(folder: "stock", reason: "its files changed since it was installed")))
    }

    @Test func pluginsInTheCommandList() throws {
        let stock = InstalledPlugin(manifest: try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: stockFolder().appendingPathComponent("plugin.json"))),
                                    directory: try stockFolder(), isLocal: true)
        let tone = InstalledPlugin(manifest: PluginManifest(name: "tone", version: "1", type: .prompt, prompt: "Make it friendlier."),
                                   directory: URL(fileURLWithPath: "/tmp/tone"), isLocal: true)
        var open = stock
        open.manifest.name = "open"  // a built-in's name: the built-in wins
        let custom = [CustomCommand(name: "stock", type: .run, argv: ["x"]), CustomCommand(name: "bc", type: .run, argv: ["bc"])]
        let catalog = Command.catalog(custom, plugins: [stock, tone, open])
        #expect(catalog.map(\.name) == ["improve", "translate", "question", "agent", "open", "reply", "note", "reminder", "py", "js",
                                        "tasks", "settings", "imessage", "reportissue", "stats", "stock", "tone", "bc"])
        let stockCommand = try #require(catalog.first { $0.name == "stock" })
        #expect(stockCommand.kind == .run && stockCommand.plugin == stock && stockCommand.custom == nil)  // not the custom one
        #expect(stockCommand.typesLatin && stockCommand.program == nil)  // never hidden for a missing program
        let toneCommand = try #require(catalog.first { $0.name == "tone" })
        #expect(toneCommand.kind == .generate && Prompt.commandSystem(toneCommand).hasSuffix("Make it friendlier."))
        // The editor won't take a plugin's name.
        #expect(CustomCommand(name: "stock", type: .run, argv: ["x"]).problem(among: [], plugins: ["stock"]) == .nameTaken)
        // The plugin runs in a child process of the given program, the text on standard input.
        let run = PluginRunner.command(for: stock, executable: "/Apps/AllInOneIME")
        #expect(run.argv == ["/Apps/AllInOneIME", "--run-plugin", try stockFolder().path])
        #expect(run.standardInput(for: "aapl") == "aapl" && run.timeout == 10)
        // Told the interface language after the folder, and nothing else.
        #expect(PluginRunner.command(for: stock, executable: "/Apps/AllInOneIME", language: .chinese).argv
                == ["/Apps/AllInOneIME", "--run-plugin", try stockFolder().path, "--language", "zh"])
        #expect(PluginRunner.command(for: stock, executable: "/Apps/AllInOneIME", language: .english).argv
                == ["/Apps/AllInOneIME", "--run-plugin", try stockFolder().path, "--language", "en"])
        #expect(PluginRunner.command(for: stock, executable: "/Apps/AllInOneIME", language: nil).argv == run.argv)
    }

    /// `--run-plugin <folder> [--language zh|en]`, as main.swift reads it.
    @Test func pluginHostArguments() {
        typealias Invocation = PluginHost.Invocation
        #expect(PluginHost.invocation(["/p/stock"]) == Invocation(directory: "/p/stock"))
        #expect(PluginHost.invocation(["/p/stock", "--language", "zh"]) == Invocation(directory: "/p/stock", language: .chinese))
        #expect(PluginHost.invocation(["/p/stock", "--language", "en"]) == Invocation(directory: "/p/stock", language: .english))
        // Unknown, not an interface language, or missing: no language (the script gets {}).
        #expect(PluginHost.invocation(["/p/stock", "--language", "xx"]) == Invocation(directory: "/p/stock"))
        #expect(PluginHost.invocation(["/p/stock", "--language", "fr"]) == Invocation(directory: "/p/stock"))
        #expect(PluginHost.invocation(["/p/stock", "--language", "ZH"]) == Invocation(directory: "/p/stock"))
        #expect(PluginHost.invocation(["/p/stock", "--language"]) == Invocation(directory: "/p/stock"))
        #expect(PluginHost.invocation(["/p/stock", "--other", "x", "--language", "en"]) == Invocation(directory: "/p/stock", language: .english))
        // No folder: main exits with 2.
        #expect(PluginHost.invocation([]) == nil)
    }

    // MARK: JavaScript

    @Test(.enabled(if: Available.javaScript)) func scriptsGetNothingButFetch() throws {
        let fetcher = StubFetcher(["https://a.test/x": (200, #"{"v": 41}"#)])
        let source = """
            function run(input) {
              const r = fetch("https://a.test/x", { headers: { "X-Test": "1" } });
              const env = [typeof require, typeof process, typeof setTimeout, typeof XMLHttpRequest].join(",");
              return input + " " + (r.json().v + 1) + " " + env;
            }
            """
        #expect(try PluginScript.evaluate(source: source, input: "hi", fetcher: fetcher) == "hi 42 undefined,undefined,undefined,undefined")
        #expect(fetcher.asked == [PluginRequest(url: "https://a.test/x", headers: ["X-Test": "1"])])
        // Errors: thrown, a syntax error, no run, not text, a failed fetch.
        #expect(throws: PluginScriptError.failed("nope")) {
            try PluginScript.evaluate(source: "function run() { throw new Error('nope') }", input: "", fetcher: fetcher)
        }
        #expect(throws: PluginScriptError.self) { try PluginScript.evaluate(source: "function run( {", input: "", fetcher: fetcher) }
        #expect(throws: PluginScriptError.noRunFunction) { try PluginScript.evaluate(source: "var x = 1", input: "", fetcher: fetcher) }
        #expect(throws: PluginScriptError.failed("run(input) must return text")) {
            try PluginScript.evaluate(source: "function run() { return 3 }", input: "", fetcher: fetcher)
        }
        #expect(throws: PluginScriptError.failed("can't reach the host")) {
            try PluginScript.evaluate(source: "function run() { return fetch('https://b.test/').text }", input: "", fetcher: fetcher)
        }
    }

    @Test(.enabled(if: Available.javaScript)) func scriptsAreToldTheInterfaceLanguageAndNothingElse() throws {
        let fetcher = StubFetcher()
        let whole = "function run(input, context) { return JSON.stringify(arguments[1]) + ' ' + arguments.length }"
        #expect(try PluginScript.evaluate(source: whole, input: "x", language: .chinese, fetcher: fetcher) == #"{"language":"zh"} 2"#)
        #expect(try PluginScript.evaluate(source: whole, input: "x", language: .english, fetcher: fetcher) == #"{"language":"en"} 2"#)
        #expect(try PluginScript.evaluate(source: whole, input: "x", language: nil, fetcher: fetcher) == "{} 2")
        #expect(try PluginScript.evaluate(source: whole, input: "x", fetcher: fetcher) == "{} 2")
        // Only the interface's two languages.
        #expect(try PluginScript.evaluate(source: whole, input: "x", language: .french, fetcher: fetcher) == "{} 2")
        // A plain object.
        let plain = "function run(input, context) { return String(Object.getPrototypeOf(context) === Object.prototype) }"
        #expect(try PluginScript.evaluate(source: plain, input: "x", language: .chinese, fetcher: fetcher) == "true")
        // The way the docs suggest reading it, older apps included.
        let reads = "function run(input, context) { return input + ' ' + ((context && context.language) || 'none') }"
        #expect(try PluginScript.evaluate(source: reads, input: "你好", language: .chinese, fetcher: fetcher) == "你好 zh")
        #expect(try PluginScript.evaluate(source: reads, input: "hi", language: .english, fetcher: fetcher) == "hi en")
        #expect(try PluginScript.evaluate(source: reads, input: "hi", fetcher: fetcher) == "hi none")
        // `run(input)` plugins work as before.
        let old = "function run(input) { return input.toUpperCase() }"
        #expect(try PluginScript.evaluate(source: old, input: "hi", language: .chinese, fetcher: fetcher) == "HI")
        #expect(try PluginScript.evaluate(source: old, input: "hi", fetcher: fetcher) == "HI")
        #expect(fetcher.asked.isEmpty)
    }

    @Test func fetchOnlyReachesTheListedHosts() {
        let fetcher = URLSessionFetcher(hosts: ["query1.finance.yahoo.com"])
        #expect(fetcher.allows(URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/AAPL")))
        #expect(fetcher.allows(URL(string: "https://QUERY1.finance.yahoo.com/x")))
        #expect(!fetcher.allows(URL(string: "http://query1.finance.yahoo.com/x")))  // HTTPS only
        #expect(!fetcher.allows(URL(string: "https://evil.test/?q=query1.finance.yahoo.com")))
        #expect(!fetcher.allows(URL(string: "https://query1.finance.yahoo.com.evil.test/")))
        #expect(!fetcher.allows(URL(string: "file:///etc/passwd")))
        let refused = fetcher.fetch([PluginRequest(url: "https://evil.test/", headers: [:])])
        #expect(refused.first?.error?.hasPrefix("not allowed: evil.test") == true)
    }

    // MARK: @stock

    @Test(.enabled(if: Available.javaScript)) func stockQuotes() throws {
        let fetcher = StubFetcher([
            Self.url("AAPL"): Self.chart("AAPL", "Apple Inc.", 336.64, 340.42, "USD"),
            Self.url("TSLA"): Self.chart("TSLA", "Tesla, Inc.", 382.7, 375.0, "USD"),
            Self.url("600519.SS"): Self.chart("600519.SS", "KWEICHOW MOUTAI", 1263, 1255.79, "CNY"),
            Self.url("000001.SZ"): Self.chart("000001.SZ", "PING AN BANK", 11.5, 11.5, "CNY"),
            Self.url("0700.HK"): Self.chart("0700.HK", "TENCENT", 424.8, 411.4, "HKD"),
            Self.url("^GSPC"): Self.chart("^GSPC", "S&P 500", 7811.54, 7765.36, "USD"),
            Self.url("NOPE"): (404, #"{"chart":{"result":null,"error":{"code":"Not Found"}}}"#),
        ])
        let script = try stockScript()
        func stock(_ input: String) throws -> String { try PluginScript.evaluate(source: script, input: input, fetcher: fetcher) }
        #expect(try stock("AAPL") == "Apple Inc. AAPL 336.64 USD −1.11%")
        #expect(try stock("aapl, tsla") == "Apple Inc. AAPL 336.64 USD −1.11% · Tesla, Inc. TSLA 382.70 USD +2.05%")
        // A shares and Hong Kong without the suffix; thousands separators; no change.
        #expect(try stock("600519 000001 700") == "KWEICHOW MOUTAI 600519.SS 1,263.00 CNY +0.57% · PING AN BANK 000001.SZ 11.50 CNY +0.00% · TENCENT 0700.HK 424.80 HKD +3.26%")
        #expect(try stock("^gspc").hasPrefix("S&P 500 ^GSPC 7,811.54 USD"))
        // One symbol missing: the others still show; all missing: an error.
        #expect(try stock("nope aapl") == "NOPE: not found · Apple Inc. AAPL 336.64 USD −1.11%")
        #expect(throws: PluginScriptError.failed("NOPE: not found")) { try stock("nope") }
        #expect(throws: PluginScriptError.failed("Type a stock symbol after @stock, e.g. AAPL")) { try stock("  ") }
        // At most 8 symbols a request; the browser User-Agent Yahoo wants.
        _ = try? stock("a b c d e f g h i j")
        #expect(fetcher.asked.suffix(8).count == 8 && fetcher.asked.last?.url.contains("/H?") == true)
        #expect(fetcher.asked.allSatisfy { $0.headers["User-Agent"] == "Mozilla/5.0" })
    }
}

/// A test whose Trash is a folder of its own (`FolderTrashFileOps`, through `Platform.override`), removed after it: what
/// it moves to the Trash never reaches the user's.
struct OwnTrash: TestTrait, TestScoping {
    func scopeProvider(for test: Test, testCase: Test.Case?) -> OwnTrash? {
        testCase == nil ? nil : self
    }

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        let trash = FileManager.default.temporaryDirectory.appendingPathComponent("trash-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: trash) }
        var platform = Platform.current
        platform.files = FolderTrashFileOps(trash: trash)
        try await Platform.$override.withValue(platform) { try await function() }
    }

    /// The Trash of the test running.
    static var folder: URL? { (Platform.current.files as? FolderTrashFileOps)?.folder }
}

/// Removing a plugin (Settings → Plugins → Remove, or the settings document's `remove`) moves its folder to the Trash,
/// never deletes it: a local plugin's folder is where its author writes it (docs/plugins.md), maybe the only copy.
struct PluginRemovalTests {
    /// A plugins folder with a library plugin (its install record) and a local one with a file of its author's.
    func plugins() throws -> (root: URL, store: SettingsStore) {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("plugin-removal-\(UUID().uuidString)", isDirectory: true)
        let root = folder.appendingPathComponent("plugins", isDirectory: true)
        let stock = root.appendingPathComponent("stock"), tone = root.appendingPathComponent("tone")
        try fm.createDirectory(at: stock, withIntermediateDirectories: true)
        try fm.createDirectory(at: tone, withIntermediateDirectories: true)
        try Data(#"{"name":"stock","version":"1.0.0","type":"prompt","prompt":"Quotes."}"#.utf8).write(to: stock.appendingPathComponent("plugin.json"))
        let record = PluginInstallRecord(version: "1.0.0", files: ["plugin.json": PluginStore.sha256(of: stock.appendingPathComponent("plugin.json"))!])
        try JSONEncoder().encode(record).write(to: stock.appendingPathComponent("install.json"))
        try Data(#"{"name":"tone","version":"0.1","type":"prompt","prompt":"Make it friendlier."}"#.utf8).write(to: tone.appendingPathComponent("plugin.json"))
        try Data("ideas for the next version".utf8).write(to: tone.appendingPathComponent("notes.md"))
        let url = folder.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: url)
        return (root, SettingsStore(configURL: url))
    }

    @Test(OwnTrash()) func aRemovedPluginsFolderGoesToTheTrash() throws {
        let (root, store) = try plugins()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let trash = try #require(OwnTrash.folder)
        let loaded = PluginStore.load(from: root).plugins
        #expect(loaded.map(\.name) == ["stock", "tone"] && loaded.map(\.isLocal) == [false, true])
        for plugin in loaded { #expect(store.uninstall(plugin) == nil, "\(plugin.name)") }
        #expect(PluginStore.load(from: root).plugins.isEmpty, "removed")
        // In the Trash as they were, the author's own file with the local one.
        #expect(FileManager.default.contents(atPath: trash.appendingPathComponent("tone/notes.md").path) == Data("ideas for the next version".utf8))
        #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent("stock/install.json").path))
    }

    /// Where the Trash can't take it (a volume without one), the folder stays, and Settings says why.
    @Test func aFolderTheTrashCantTakeStays() throws {
        struct NoTrash: FileOps {
            let system = SystemFileOps()
            func swap(_ source: URL, into destination: URL, exists: Bool) throws { try system.swap(source, into: destination, exists: exists) }
            func recoverInterruptedSwaps(in folder: URL) { system.recoverInterruptedSwaps(in: folder) }
            func writePrivate(_ data: Data, to url: URL, stagingIn staging: URL?) throws { try system.writePrivate(data, to: url, stagingIn: staging) }
            func modificationDate(atPath path: String) -> Date? { system.modificationDate(atPath: path) }
            func isQuarantined(_ url: URL) -> Bool { false }
            func trash(_ url: URL) throws { throw CocoaError(.fileWriteVolumeReadOnly) }
        }
        let (root, store) = try plugins()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let tone = try #require(PluginStore.load(from: root).plugins.first { $0.name == "tone" })
        var platform = Platform.current
        platform.files = NoTrash()
        let error = UIText.$scopedLanguage.withValue("en") {
            Platform.$override.withValue(platform) { store.uninstall(tone) }
        }
        #expect(error?.hasPrefix("Couldn't remove the plugin: ") == true, "\(error ?? "nil")")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("tone/notes.md").path), "not deleted")
        #expect(PluginStore.load(from: root).plugins.map(\.name) == ["stock", "tone"])
    }
}
