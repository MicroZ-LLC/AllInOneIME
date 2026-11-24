import AllInOneIMECore
import AllInOneIMETestSupport
@testable import AllInOneIMERime
import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// Acceptance for shape-code filtering (辅助码 / 形码筛选, spec of 2026-11-23) on the real rime-ice data and librime,
// written from the spec alone, independent of the implementation (AGENTS.md rule 11: the implementer doesn't edit it).
// Pinyin (full pinyin or 微软双拼) + "`" + one or two shape letters lists only the candidates whose characters match:
// a character when its code starts with the letters, a word when any of its characters does, the words whose first
// character does first; with no letter after "`" the list is as it was. Off is today's rime-ice, its own "`" filter
// (search.lua@radical_pinyin) included; on, the shape-code filter takes "`" instead. Zhuyin is unaffected.
//
// Each scenario runs in a process and a temporary Rime folder of its own (librime starts once per process), set up as the
// app sets it up: the Chinese pack (rime-ice's data, linked), the app's scripts, what the app carries for shape codes,
// the patches it writes for the settings, the schema list. The app's session (`InputSession` in the core's `FakeHost`)
// types on the real librime session where a test is about keys and what reaches the field.
//
// The codes are the upstream tables' (HowcanoeWang/rime-lua-aux-code at f9780033396f8998697c2a004d40bd543c46308b,
// aux_code/*.txt, line numbers below), and every expectation was checked on 2026-11-24 against rime-ice 2026.06.30 and
// librime 1.16.1 (the Makefile's pins) with that commit's lua/aux_code.lua: of "yu"'s candidates 鱼 is the 12th and
// 蝓 about the 90th; of "ying"'s 瀛 is the 25th. Expected API is in the adapter below, and nowhere else.

// MARK: - Adapter: the implementation's names this file assumes (retarget here only)

private enum ShapeCodeAdapter {
    /// The tables Settings offers, by `Config.shapeCode`'s value (nil: off). A table left out of the app (its licence)
    /// comes out of this list; its `TableCase` is then skipped.
    static let shipped = ["moqi", "flypy", "wubi86", "cangjie"]  // ziranma: not shipped (no licence, "禁止商用")

    /// `config` with shape codes `table` (nil: off).
    static func setShapeCode(_ table: String?, in config: inout Config) {
        config.shapeCode = table
    }

    /// Where `make deps` puts what the app carries for shape codes (as Zhuyin's data is in ThirdParty/rime-zhuyin):
    /// rime-lua-aux-code's `lua/aux_code.lua` and its tables, `aux_code/<table>.txt`.
    static let data = RimeFixture.thirdParty.appendingPathComponent("rime-aux-code")

    static var dataAvailable: Bool {
        FileManager.default.fileExists(atPath: data.appendingPathComponent("lua/aux_code.lua").path)
            && FileManager.default.fileExists(atPath: data.appendingPathComponent("aux_code").path)
    }

    /// The app's shape-code files put where librime finds them, as `RimeStartup` does: the Lua among the app's scripts
    /// (`code`, which the pack's `lua/` links to), the tables' folder linked into the Chinese pack (`aux_code/`, where
    /// aux_code.lua reads them from the shared data). What is there already (`make deps` put it in rime-data) stays.
    static func install(store: LanguagePackStore, code: URL) throws {
        let lua = code.appendingPathComponent("aux_code.lua")
        if !FileManager.default.fileExists(atPath: lua.path) {
            try FileManager.default.copyItem(at: data.appendingPathComponent("lua/aux_code.lua"), to: lua)
        }
        try store.linkData(.chinesePinyin, from: data, names: ["aux_code"])
    }

    /// The patches the app writes for `config` (`RimeStartup` → `FuzzyPinyin.apply` → `PersonalDictionaryStore`), the
    /// shape codes with them; what the write came to (`.unchanged`: nothing to deploy again).
    static func writePatches(_ config: Config, pack: URL, user: URL) throws -> FuzzyPinyin.Outcome {
        try FuzzyPinyin.apply(config.fuzzyPinyin, characters: config.typedChinese, scheme: config.typedPinyin,
                              shapeCode: config.shapeCode.flatMap(ShapeCode.init(rawValue:)),
                              schema: pack.appendingPathComponent("rime_ice.schema.yaml"), userDir: user)
    }
}

// MARK: - The tables' codes

/// One table's codes and what they pick, checked as the header says.
private struct TableCase: Sendable {
    let table: String
    /// 鱼's first two letters: "yu" + "`" + these lists 鱼 first (the spec's example).
    let fish: String
    /// 蝓's (a rare "yu", about the 90th): first.
    let rare: String
    /// 瀛's ("ying", in 微软双拼 "y;": its final is ";", why the trigger is "`" and not the plugin's ";"): first.
    let ying: String
    /// "jiyu" (ji yu in full pinyin and 微软双拼 alike) + "`" + `letters`: `first`, a word whose first character matches,
    /// is listed before `later`, one whose second character alone does (listed before `first` without the filter), and
    /// `gone`, none of whose characters does, isn't listed.
    let letters: String
    let first: String
    let later: String
    let gone: String
}

private let tableCases = [
    // moqi_aux_code.txt: 鱼=da (36742), 蝓=id (36668), 瀛=dn (35923); 激=dw (12864), 鲫=ye (13036), 鱼=da;
    // 给=sk (9266), 予=sl (36497).
    TableCase(table: "moqi", fish: "da", rare: "id", ying: "dn", letters: "d", first: "激欲", later: "鲫鱼", gone: "给予"),
    // flypy_full.txt (鹤形): 鱼=da (7185), 蝓=id (7213), 瀛=df (7081); 激=dw (2423), 鲫=ae (2497); 给=sk (1752), 予=sl (7216).
    TableCase(table: "flypy", fish: "da", rare: "id", ying: "df", letters: "d", first: "激欲", later: "鲫鱼", gone: "给予"),
    // ZRM_Aux-code_4.3.txt (自然码): 鱼=da (27439), 蝓=iy (27500), 瀛=dy (27760); 激=dj (9230), 鲫=yj (9575);
    // 给=sh (6095), 予=aa sa su vu (27400, 27613, 27616, 27651).
    TableCase(table: "ziranma", fish: "da", rare: "iy", ying: "dy", letters: "d", first: "激欲", later: "鲫鱼", gone: "给予"),
    // wubi86-code.txt: 鱼=qgf (4730), 蝓=jwgj (2986), 瀛=iyny (2710); 几=wtn (7286), 觊=mnm (3775), 觎=wgeq (7102);
    // 给=xw (7564), 予=cnhj (785).
    TableCase(table: "wubi86", fish: "qg", rare: "jw", ying: "iy", letters: "w", first: "几欲", later: "觊觎", gone: "给予"),
    // cangjie5_quick_code.txt: 鱼=nm (64536), 蝓=ln (48268), 瀛=ev (18087); 鲫=nl (62766), 给=vr (97316), 予=nn (61673);
    // 基=tg (86006), 于=md (51805).
    TableCase(table: "cangjie", fish: "nm", rare: "ln", ying: "ev", letters: "n", first: "鲫鱼", later: "给予", gone: "基于"),
]

// MARK: - Scenarios

private enum ShapeCodeRime {
    static let workerKey = "ALLINONEIME_SHAPE_CODE_ACCEPTANCE_WORKER"
    static let rootKey = "ALLINONEIME_SHAPE_CODE_ACCEPTANCE_ROOT"
    static var worker: String? { ProcessInfo.processInfo.environment[workerKey] }
    static var rimeData: Bool {
        ["rime_ice.schema.yaml", "double_pinyin_mspy.schema.yaml", "build/rime_ice.table.bin"].allSatisfy {
            FileManager.default.fileExists(atPath: RimeFixture.sharedData.appendingPathComponent($0).path)
        }
    }
    static var dataAvailable: Bool { rimeData && ShapeCodeAdapter.dataAvailable }
    static let openCC = RimeFixture.thirdParty.appendingPathComponent("opencc")
    static let zhuyin = RimeFixture.thirdParty.appendingPathComponent("rime-zhuyin")
    static var zhuyinAvailable: Bool {
        FileManager.default.fileExists(atPath: zhuyin.path) && FileManager.default.fileExists(atPath: openCC.path)
    }

    /// What rime-ice types for "`" with nothing composed in Chinese, today (its punctuator/half_shape: '`' : '·',
    /// seen 2026-11-24 with shape codes off): the same with them on. The spec's "still types a backtick" is read as
    /// "as it does now"; in English, and in an app's own Latin input, it is "`" as ever.
    static let nothingComposedGrave = "·"

    static func run(_ scenario: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shape-code-rime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("worker-output.txt")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try #require(CommandLine.arguments.first))
        if let index = CommandLine.arguments.firstIndex(of: "--test-bundle-path"), index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            process.arguments = ["--test-bundle-path", path, "--filter", "ShapeCodeRimeAcceptanceWorker", path,
                                 "--testing-library", "swift-testing"]
        } else {
            process.arguments = ["--testing-library", "swift-testing", "--filter", "ShapeCodeRimeAcceptanceWorker"]
        }
        var environment = ProcessInfo.processInfo.environment
        environment[workerKey] = scenario
        environment[rootKey] = root.path
        environment["ALLINONEIME_THIRDPARTY"] = RimeFixture.thirdParty.path
        process.environment = environment
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(300)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        let report = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
        try #require(process.terminationReason == .exit && process.terminationStatus == 0, "\(scenario):\n\(report)")
        try #require(report.contains("SHAPE_CODE_WORKER_FINISHED:\(scenario)"), "\(scenario) didn't run:\n\(report)")
    }

    static func scenario(_ name: String, root: URL) throws {
        if name.hasPrefix("table:") {
            let table = String(name.dropFirst("table:".count))
            try tableScenario(try #require(tableCases.first { $0.table == table }, "no case for \(table)"), root: root)
        } else if name == "on-and-off" {
            try onAndOff(root)
        } else if name == "zhuyin" {
            try zhuyinScenario(root)
        } else {
            Issue.record("unknown scenario \(name)")
        }
    }

    // MARK: Setting up as the app does

    struct Folders {
        let root: URL
        let pack: URL
        let user: URL
        var store: LanguagePackStore { LanguagePackStore(directory: root.appendingPathComponent("LanguagePacks")) }
    }

    /// The Chinese pack in `root` as the app has it: rime-ice's data, its `lua/` the app's scripts (rime-ice's, the
    /// app's filter of the candidates removed) and the shape-code files the app carries. Nothing deployed yet.
    static func prepare(_ root: URL) throws -> Folders {
        let removed = try String(contentsOf: RemovedCandidatesFilterRimeTests.script, encoding: .utf8)
        let pack = try RemovedCandidatesFilterRimeTests.pack(root, code: "rime-lua", script: removed)
        let folders = Folders(root: root, pack: pack, user: root.appendingPathComponent("Rime"))
        try ShapeCodeAdapter.install(store: folders.store, code: root.appendingPathComponent("rime-lua"))
        return folders
    }

    /// Chinese typed in Simplified characters with `scheme`, shape codes `table` (nil: off).
    static func config(_ table: String?, scheme: PinyinScheme, characters: ChineseCharacters = .simplified) -> Config {
        var config = Config.default
        config.setOrder([Language.chinese, .english])
        config.chineseCharacters = characters
        config.pinyinScheme = scheme.setting
        ShapeCodeAdapter.setShapeCode(table, in: &config)
        return config
    }

    /// What the app writes for `config` (the patches, the schema list), then librime started on it, in full.
    static func start(_ folders: Folders, _ config: Config) throws {
        _ = try ShapeCodeAdapter.writePatches(config, pack: folders.pack, user: folders.user)
        _ = try PinyinScheme.applySchemaList(config.typedPinyin, userDir: folders.user)
        try RimeService.shared.start(sharedDataDir: folders.pack, userDataDir: folders.user, logDir: nil, fullCheck: true,
                                     openCCDir: openCC)
        try #require(RimeService.shared.waitUntilReady(timeout: 180), "librime didn't deploy")
        try #require(RimeService.shared.deploymentStatus == .succeeded)
    }

    /// The settings changed: what the app writes for `config`, deployed again if that changed anything (as the app
    /// does: `RimeService.redeploy`). What the write came to.
    @discardableResult
    static func change(_ folders: Folders, to config: Config) throws -> FuzzyPinyin.Outcome {
        let outcome = try ShapeCodeAdapter.writePatches(config, pack: folders.pack, user: folders.user)
        let listed = try PinyinScheme.applySchemaList(config.typedPinyin, userDir: folders.user)
        if outcome != .unchanged || listed == .written {
            RimeService.shared.redeploy()
            try #require(RimeService.shared.waitUntilReady(timeout: 180), "librime didn't deploy again")
            try #require(RimeService.shared.deploymentStatus == .succeeded)
        }
        return outcome
    }

    /// `schema` as librime deployed it (the user folder's build/): what the patches made of rime-ice's.
    static func deployed(_ schema: String, _ folders: Folders) throws -> String {
        try String(contentsOf: folders.user.appendingPathComponent("build/\(schema).schema.yaml"), encoding: .utf8)
    }

    static func session(_ schema: String) throws -> RimeSession {
        let session = try #require(RimeService.shared.makeSession())
        try #require(session.selectSchema(schema), "couldn't select \(schema)")
        return session
    }

    /// Every candidate's text for `keys` typed afresh, page after page.
    static func list(_ keys: String, in session: RimeSession) -> [String] {
        session.clearComposition()
        for byte in keys.utf8 { _ = session.processKey(Int32(byte), mask: 0) }
        var texts: [String] = []
        for _ in 0..<80 {
            let snapshot = session.snapshot()
            texts += snapshot.candidates.map(\.text)
            if snapshot.isLastPage || snapshot.candidates.isEmpty { break }
            _ = session.processKey(RimeKey.pageDown, mask: 0)
        }
        session.clearComposition()
        return texts
    }

    /// The app's session typing on `session` with `config`, in a field whose app types the keys let through.
    static func host(_ session: RimeSession, _ config: Config) -> FakeHost {
        let fixed = config
        var services = SessionServices(loadSettings: { fixed })
        services.levelOne = { .engine(session) }
        let host = FakeHost(services: services)
        host.appTypesKeys = true
        host.focus()
        return host
    }

    static let backspace = KeyEvent(keyCode: VirtualKey.delete, characters: "\u{7F}")

    static func rows(_ host: FakeHost) -> [String] { host.panel?.rows.map(\.text) ?? [] }

    /// Only Chinese characters: nothing of "`" or of the letters typed.
    static func isHan(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { $0.properties.isIdeographic }
    }

    /// "`" alone left `plain`'s list as it was: the same candidates in the same order, but for those at its end that spell
    /// more than the letters typed (rime-ice's English words and completions: yum, Yukon, 月K线), which "`" ends with
    /// shape codes off as well.
    static func isUnchanged(_ grave: [String], from plain: [String]) -> Bool {
        !grave.isEmpty && plain.starts(with: grave)
            && plain.dropFirst(grave.count).allSatisfy { !($0.count == 1 && isHan($0)) }
    }

    // MARK: Each table, in 微软双拼 and full pinyin

    static func tableScenario(_ table: TableCase, root: URL) throws {
        let folders = try prepare(root)
        try start(folders, config(table.table, scheme: .microsoft))
        for schema in ["rime_ice", "double_pinyin_mspy"] {
            #expect(try deployed(schema, folders).contains("lua_filter@*aux_code"), "\(table.table): \(schema)'s filters")
        }
        let session = try session("rime_ice")
        for scheme in [PinyinScheme.full, .microsoft] {
            try #require(session.selectSchema(scheme.schema))
            try filters(table, scheme: scheme, session: session)
        }
        for scheme in [PinyinScheme.full, .microsoft] {
            try typesThroughTheApp(table, scheme: scheme, session: session)
        }
    }

    /// What "`" and the shape letters list (librime's session itself).
    static func filters(_ table: TableCase, scheme: PinyinScheme, session: RimeSession) throws {
        let name = "\(table.table) in \(scheme)"
        let yu = list("yu", in: session)
        try #require(yu.contains("鱼") && yu.contains("蝓") && yu.first != "鱼", "\(name): yu → \(yu.prefix(20))")
        // No letter after "`": the list as it was.
        let grave = list("yu`", in: session)
        #expect(isUnchanged(grave, from: yu), "\(name): yu` → \(grave.suffix(10)), yu → \(yu.suffix(10))")
        // Two letters: the character first, only matching candidates, all of them "yu"'s.
        let fish = list("yu`" + table.fish, in: session)
        #expect(fish.first == "鱼", "\(name): yu`\(table.fish) → \(fish.prefix(10))")
        #expect(Set(fish).isSubset(of: Set(yu)), "\(name): only yu's candidates")
        #expect(!fish.contains(yu[0]) && fish.count < yu.count, "\(name): the unmatched aren't listed: \(fish.prefix(10))")
        let rare = list("yu`" + table.rare, in: session)
        #expect(rare.first == "蝓", "\(name): yu`\(table.rare) → \(rare.prefix(10))")
        // One letter: fewer than none, more than two.
        let one = list("yu`" + table.fish.prefix(1), in: session)
        #expect(one.contains("鱼") && Set(one).isSubset(of: Set(yu)) && one.count < yu.count, "\(name): \(one.prefix(10))")
        #expect(Set(fish).isSubset(of: Set(one)), "\(name): a second letter narrows what one listed")
        // 微软双拼's ";" final (ying: y;) and then "`".
        let ying = scheme == .microsoft ? "y;" : "ying"
        let yings = list(ying + "`" + table.ying, in: session)
        #expect(yings.first == "瀛", "\(name): \(ying)`\(table.ying) → \(yings.prefix(10))")
        // Words: any character matches; those whose first character does first; the others left out.
        let jiyu = list("jiyu", in: session)
        let unfirst = try #require(jiyu.firstIndex(of: table.first), "\(name): \(table.first) among jiyu's")
        let unlater = try #require(jiyu.firstIndex(of: table.later), "\(name): \(table.later) among jiyu's")
        try #require(unlater < unfirst && jiyu.contains(table.gone), "\(name): jiyu → \(jiyu.prefix(20))")
        let words = list("jiyu`" + table.letters, in: session)
        #expect(!words.contains(table.gone), "\(name): \(table.gone) has no matching character: \(words.prefix(20))")
        #expect(Set(words).isSubset(of: Set(jiyu)), "\(name): only jiyu's candidates")
        if let first = words.firstIndex(of: table.first), let later = words.firstIndex(of: table.later) {
            #expect(first < later, "\(name): the first character's match first: \(words.prefix(20))")
        } else {
            Issue.record("\(name): jiyu`\(table.letters) lists both \(table.first) and \(table.later): \(words.prefix(20))")
        }
    }

    /// Through the app's session: Backspace, picks, what reaches the field.
    static func typesThroughTheApp(_ table: TableCase, scheme: PinyinScheme, session: RimeSession) throws {
        let name = "\(table.table) in \(scheme)"
        let config = config(table.table, scheme: scheme)
        try #require(session.selectSchema(scheme.schema))
        let yu = list("yu", in: session), one = list("yu`" + table.fish.prefix(1), in: session)
        let host = host(session, config)
        // Backspace: the shape letters, then "`", then the pinyin. Nothing in the field meanwhile, nothing marked there.
        host.type("yu`" + table.fish)
        #expect(session.rawInput == "yu`" + table.fish && rows(host).first == "鱼", "\(name): \(rows(host))")
        #expect(host.document.isEmpty && host.marked.isEmpty && !host.preedit.isEmpty, "\(name): only the panel shows it")
        host.press(backspace)
        #expect(session.rawInput == "yu`" + table.fish.prefix(1) && rows(host) == Array(one.prefix(rows(host).count)),
                "\(name): \(session.rawInput) \(rows(host))")
        host.press(backspace)
        #expect(session.rawInput == "yu`" && rows(host) == Array(yu.prefix(rows(host).count)) && !rows(host).isEmpty,
                "\(name): \(session.rawInput) \(rows(host))")
        host.press(backspace)
        #expect(session.rawInput == "yu", "\(name): \(session.rawInput)")
        host.press(backspace)
        #expect(session.rawInput == "y", "\(name): \(session.rawInput)")
        host.press(backspace)
        #expect(session.rawInput.isEmpty && host.document.isEmpty && host.panel == nil, "\(name): \(host.document)")

        // Space picks; "`" and the letters go with the pick.
        host.type("yu`" + table.fish)
        host.press(FakeHost.space)
        #expect(host.document == "鱼" && session.rawInput.isEmpty, "\(name): \(host.document)")
        // A digit picks (a word for both syllables: the first on the page).
        host.type("jiyu`" + table.letters)
        let word = try #require(rows(host).firstIndex { $0.count == 2 && isHan($0) }, "\(name): \(rows(host))")
        let wordText = rows(host)[word]
        host.type(String(word + 1))
        #expect(host.document == "鱼" + wordText && session.rawInput.isEmpty, "\(name): \(host.document)")
        // A character for the first syllable only, then Space for the rest: only Chinese characters reach the field.
        let before = host.document
        host.type("jiyu`" + table.letters)
        let single = try #require(rows(host).firstIndex { $0.count == 1 && isHan($0) }, "\(name): \(rows(host))")
        let picked = rows(host)[single]
        host.type(String(single + 1))
        #expect(host.document == before, "\(name): a part picked stays in the panel")
        for _ in 0..<4 where !session.rawInput.isEmpty { host.press(FakeHost.space) }
        let added = String(host.document.dropFirst(before.count))
        #expect(added.hasPrefix(picked) && isHan(added) && session.rawInput.isEmpty, "\(name): \(added)")
        // "`" with nothing composed: as with shape codes off, nothing composed after it.
        let typed = host.document
        host.type("`")
        #expect(host.document == typed + nothingComposedGrave && session.rawInput.isEmpty && host.panel == nil,
                "\(name): \(host.document)")
    }

    // MARK: Off, on, another table, off again: without a restart, deployed again only when it changes

    static func onAndOff(_ root: URL) throws {
        let shipped = tableCases.filter { ShapeCodeAdapter.shipped.contains($0.table) }
        let on = try #require(shipped.first, "no table shipped")
        let folders = try prepare(root)
        var settings = config(nil, scheme: .microsoft)
        try start(folders, settings)
        try isAsToday(folders, "off")

        ShapeCodeAdapter.setShapeCode(on.table, in: &settings)
        #expect(try change(folders, to: settings) != .unchanged, "turned on: written, deployed again")
        #expect(try ShapeCodeAdapter.writePatches(settings, pack: folders.pack, user: folders.user) == .unchanged,
                "the same setting again: nothing to deploy")
        for schema in ["rime_ice", "double_pinyin_mspy"] {
            #expect(try deployed(schema, folders).contains("lua_filter@*aux_code"), "on: \(schema)'s filters")
            let session = try session(schema)
            #expect(list("yu`" + on.fish, in: session).first == "鱼", "\(on.table) in \(schema)")
            // rime-ice's own "`" filter no longer answers: "ren" is read as shape letters, not as 亻's pinyin.
            let ren = list("ni`ren", in: session)
            #expect(ren != ["你", "倪", "伲"], "\(schema): ni`ren → \(ren)")
        }

        // Another table (one whose code for 鱼 differs): it takes over, the first one's code no longer applies.
        if let other = shipped.first(where: { $0.fish != on.fish }) {
            ShapeCodeAdapter.setShapeCode(other.table, in: &settings)
            #expect(try change(folders, to: settings) != .unchanged, "another table: written, deployed again")
            for schema in ["rime_ice", "double_pinyin_mspy"] {
                let session = try session(schema)
                #expect(list("yu`" + other.fish, in: session).first == "鱼", "\(other.table) in \(schema)")
                #expect(list("yu`" + on.fish, in: session).first != "鱼", "\(schema): \(on.table)'s code no longer applies")
            }
        }

        ShapeCodeAdapter.setShapeCode(nil, in: &settings)
        #expect(try change(folders, to: settings) != .unchanged, "turned off: written, deployed again")
        #expect(try ShapeCodeAdapter.writePatches(settings, pack: folders.pack, user: folders.user) == .unchanged)
        try isAsToday(folders, "off again")
    }

    /// Shape codes off: rime-ice as it is today, its "`" radical filter (search.lua@radical_pinyin) included.
    static func isAsToday(_ folders: Folders, _ when: String) throws {
        for schema in ["rime_ice", "double_pinyin_mspy"] {
            let text = try deployed(schema, folders)
            #expect(!text.contains("lua_filter@*aux_code") && text.contains("lua_filter@*search@radical_pinyin"),
                    "\(when): \(schema)")
            let session = try session(schema)
            // "`" + the radicals' pinyin: 亻 (ren) → 你 倪 伲, as rime-ice lists them (seen 2026-11-24).
            #expect(list("ni`ren", in: session) == ["你", "倪", "伲"], "\(when): \(schema)")
            let grave = list("yu`", in: session), yu = list("yu", in: session)
            #expect(isUnchanged(grave, from: yu), "\(when): \(schema): \(grave.suffix(10)), \(yu.suffix(10))")
        }
        let session = try session("double_pinyin_mspy")
        let host = host(session, config(nil, scheme: .microsoft))
        host.type("`")
        #expect(host.document == nothingComposedGrave && session.rawInput.isEmpty, "\(when): \(host.document)")
        host.type("ni`ren")
        host.press(FakeHost.space)
        #expect(host.document == nothingComposedGrave + "你", "\(when): \(host.document)")
    }

    // MARK: Zhuyin: unaffected

    static func zhuyinScenario(_ root: URL) throws {
        let folders = try prepare(root)
        // The pack has no Zhuyin data of its own: the app's linked in, as `RimeStartup` links it.
        for name in PinyinScheme.zhuyinData { try? FileManager.default.removeItem(at: folders.pack.appendingPathComponent(name)) }
        try folders.store.linkData(.chinesePinyin, from: zhuyin, names: PinyinScheme.zhuyinData)
        var settings = config(nil, scheme: .zhuyin, characters: .taiwan)
        try start(folders, settings)
        let keys = ["su3cl3", "ji3", "u", "su3"]
        let before = try keys.map { list($0, in: try session("bopomofo")) }
        #expect(before[0].contains("你好"))

        ShapeCodeAdapter.setShapeCode(try #require(ShapeCodeAdapter.shipped.first), in: &settings)
        try change(folders, to: settings)
        #expect(!(try deployed("bopomofo", folders)).contains("lua_filter@*aux_code"), "no shape codes in Zhuyin's schema")
        let session = try session("bopomofo")
        #expect(keys.map { list($0, in: session) } == before, "Zhuyin's candidates as they were")
    }
}

@Suite(.serialized, .enabled(if: ShapeCodeRime.worker != nil))
struct ShapeCodeRimeAcceptanceWorker {
    @Test func runScenario() throws {
        let scenario = try #require(ShapeCodeRime.worker)
        let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment[ShapeCodeRime.rootKey]))
        try ShapeCodeRime.scenario(scenario, root: root)
        print("SHAPE_CODE_WORKER_FINISHED:\(scenario)")
    }
}

@Suite(.serialized, .enabled(if: ShapeCodeRime.worker == nil),
       .enabled(if: ShapeCodeRime.dataAvailable || RimeFixture.dataRequired,
                "needs rime-ice's data and the shape-code Lua and tables (make deps)"))
struct ShapeCodeRimeAcceptanceTests {
    /// Each table shipped has its codes here, and none is left untested.
    @Test func everyTableShippedHasACase() {
        #expect(Set(ShapeCodeAdapter.shipped).isSubset(of: Set(tableCases.map(\.table))), "\(ShapeCodeAdapter.shipped)")
        #expect(!ShapeCodeAdapter.shipped.isEmpty)
    }

    /// Per table, in 微软双拼 and full pinyin: "`" + its letters lists 鱼 and the rare 蝓 first, words by any character
    /// (the first character's matches first), the unmatched left out; "`" alone changes nothing; Backspace takes the
    /// letters, then "`", then the pinyin; Space, a digit and a part picked put in only Chinese characters; "`" with
    /// nothing composed is what it is with shape codes off.
    @Test(arguments: ShapeCodeAdapter.shipped)
    func eachTableFiltersInMicrosoftShuangpinAndFullPinyin(_ table: String) throws {
        try ShapeCodeRime.run("table:" + table)
    }

    /// Off is today's rime-ice, its own "`" filter included; turned on, to another table, off again: each takes effect
    /// without a restart, and writing the same setting again leaves nothing to deploy.
    @Test func offIsTodaysAndEachChangeTakesEffect() throws {
        try ShapeCodeRime.run("on-and-off")
    }

    /// Shape codes on, Zhuyin typed: its schema has no shape-code filter and its candidates are as they were.
    @Test(.enabled(if: ShapeCodeRime.zhuyinAvailable || RimeFixture.dataRequired, "needs the Zhuyin and OpenCC data (make deps)"))
    func zhuyinIsUnaffected() throws {
        try ShapeCodeRime.run("zhuyin")
    }
}
