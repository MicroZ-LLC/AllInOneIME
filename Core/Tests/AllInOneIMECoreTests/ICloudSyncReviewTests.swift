import Foundation
import Testing
@testable import AllInOneIMECore

// The sign-off review's probes (scratchpad/icloud-probe, S1–S17) as regression tests: two or three Macs, each with its own
// files and clock, sharing a temporary "iCloud Drive"; some see a private copy of it first (iCloud lag, offline) and then
// a merged one where two Macs' files of one name met (iCloud keeps the server's under the name, the other as "name 2").
// Nothing here touches the user's config, iCloud Drive or Rime folder.

/// One test's temporary world.
final class ProbeWorld {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("aio-icloud-review-\(UUID().uuidString)")
    deinit { try? FileManager.default.removeItem(at: root) }

    func drive(_ name: String) -> URL {
        let url = root.appendingPathComponent("drives/" + name)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func path(_ name: String) -> URL { root.appendingPathComponent("drives/" + name) }
}

final class ProbeMac {
    let name: String
    let dir: URL
    var engine: ICloudSyncEngine
    init(_ name: String, in world: ProbeWorld, drive: URL, _ change: (inout Config) -> Void = { _ in }) {
        self.name = name
        dir = world.root.appendingPathComponent("macs/" + name)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var config = Config.default
        config.iCloudSync.enabled = true
        config.jargonFile = dir.appendingPathComponent("jargon.txt").path
        change(&config)
        engine = ICloudSyncEngine(folder: ICloudSyncFolder(url: drive.appendingPathComponent("AllInOneIME")),
                                  configURL: dir.appendingPathComponent("config.json"),
                                  stateURL: dir.appendingPathComponent("state.json"),
                                  questionsURL: dir.appendingPathComponent("questions.json"))
        engine.machineID = { "probe-machine-" + name }
        try! config.write(to: engine.configURL)
        probeTouch(engine.configURL, pt(-60))
    }
    func use(drive: URL) { engine.folder = ICloudSyncFolder(url: drive.appendingPathComponent("AllInOneIME")) }
    var config: Config { try! Config.load(from: engine.configURL) }
    func edit(at: Date, _ change: (inout Config) -> Void) {
        var c = config
        let before = c
        change(&c)
        try! AIConfig.writing(c, from: before, keys: AIConfig.changedKeys(before, c), at: engine.configURL)
        probeTouch(engine.configURL, at)
    }
    func jargon(_ text: String, at: Date) {
        try! Data(text.utf8).write(to: dir.appendingPathComponent("jargon.txt"))
        probeTouch(dir.appendingPathComponent("jargon.txt"), at)
    }
    var jargonText: String { (try? String(contentsOf: dir.appendingPathComponent("jargon.txt"), encoding: .utf8)) ?? "<none>" }
    @discardableResult
    func sync(at: Date) -> ICloudSyncEngine.Report {
        var e = engine
        e.now = { at }
        return e.run()
    }
    var commands: [String] { config.customCommands.map(\.name).sorted() }
    var hidden: [String] { config.redaction.customWords.sorted() }
    var state: ICloudSync.State { ICloudSync.State.load(from: engine.stateURL) }
    func ask(_ q: String, at: Date) {
        var h = QuestionHistory.load(from: engine.questionsURL)
        h.record(.init(question: q, answer: "answer to " + q, date: at))
        try! h.write(to: engine.questionsURL)
        probeTouch(engine.questionsURL, at)
    }
    var questions: [String] { QuestionHistory.load(from: engine.questionsURL).entries.map(\.question) }
}

let probeT0 = Date(timeIntervalSince1970: 1_800_000_000)
func pt(_ m: Double) -> Date { probeT0.addingTimeInterval(m * 60) }
func probeTouch(_ url: URL, _ at: Date) { try? FileManager.default.setAttributes([.modificationDate: at], ofItemAtPath: url.path) }
func probeCommand(_ n: String) -> CustomCommand { CustomCommand(name: n, type: .prompt, prompt: "do " + n) }
func probeFiles(_ d: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: d.appendingPathComponent("AllInOneIME").path)) ?? []).sorted() }
func probeCopyDrive(_ from: URL, _ to: URL) {
    try? FileManager.default.removeItem(at: to)
    try! FileManager.default.copyItem(at: from, to: to)
}
/// iCloud Drive meeting two Macs' independently created files of the same name: the server's keeps the name, the other
/// becomes "name 2.ext".
func probeCollide(server: URL, other: URL, into out: URL) {
    let fm = FileManager.default
    probeCopyDrive(server, out)
    let o = other.appendingPathComponent("AllInOneIME"), d = out.appendingPathComponent("AllInOneIME")
    for f in (try? fm.contentsOfDirectory(atPath: o.path)) ?? [] {
        let src = o.appendingPathComponent(f), dst = d.appendingPathComponent(f)
        if fm.fileExists(atPath: dst.path) {
            if (try? Data(contentsOf: src)) == (try? Data(contentsOf: dst)) { continue }
            let ext = (f as NSString).pathExtension, stem = (f as NSString).deletingPathExtension
            try? fm.copyItem(at: src, to: d.appendingPathComponent("\(stem) 2" + (ext.isEmpty ? "" : "." + ext)))
        } else {
            try? fm.copyItem(at: src, to: dst)
        }
    }
}
func expectProbe(_ ok: Bool, _ what: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(ok, Comment(rawValue: what), sourceLocation: sourceLocation)
}

@Suite(.serialized)
struct ICloudSyncReviewTests {
    // S1: a Mac turned off, settings.json lost (Remove from iCloud elsewhere), a fresh Mac joins (its defaults go up
    // with joining stamps), then the first Mac turns sync back on: a rejoin.
    @Test func s1RejoinAgainstFreshMacFillers() {
        let w = ProbeWorld()
        let g = w.drive("s1")
        let a = ProbeMac("s1-A", in: w, drive: g) { $0.customCommands = [probeCommand("alpha")]; $0.maxTokens = 2000 }
        a.sync(at: pt(1))
        let b = ProbeMac("s1-B", in: w, drive: g)
        b.sync(at: pt(2))
        expectProbe(b.commands == ["alpha"] && b.config.maxTokens == 2000, "B joined and took A's (\(b.commands), \(b.config.maxTokens))")
        a.edit(at: pt(3)) { $0.iCloudSync.enabled = false }
        a.sync(at: pt(3))
        // Remove from iCloud on B: folder gone, B off and forgotten.
        try? FileManager.default.removeItem(at: g.appendingPathComponent("AllInOneIME"))
        b.edit(at: pt(4)) { $0.iCloudSync.enabled = false }
        b.engine.forget()
        // A fresh Mac C turns sync on: iCloud empty, its defaults go up as joining.
        let c = ProbeMac("s1-C", in: w, drive: g)
        c.sync(at: pt(5))
        // A turns sync back on.
        a.edit(at: pt(6)) { $0.iCloudSync.enabled = true }
        a.sync(at: pt(6))
        expectProbe(a.commands == ["alpha"], "A keeps its custom commands after rejoining (has \(a.commands))")
        expectProbe(a.config.maxTokens == 2000, "A keeps maxTokens 2000 after rejoining (has \(a.config.maxTokens))")
    }

    // S2: two fresh Macs turn sync on before either's files reached the other (iCloud lag): both join an empty folder.
    @Test func s2SimultaneousFirstJoin() {
        let w = ProbeWorld()
        let on = ICloudSyncSettings(enabled: true, hiddenWords: true)
        let fa = w.drive("s2-a"), fb = w.drive("s2-b"), g = w.path("s2-g")
        let a = ProbeMac("s2-A", in: w, drive: fa) { $0.iCloudSync = on; $0.customCommands = [probeCommand("alpha")]; $0.redaction.customWords = ["Acme"] }
        let b = ProbeMac("s2-B", in: w, drive: fb) { $0.iCloudSync = on; $0.customCommands = [probeCommand("beta")]; $0.redaction.customWords = ["Bolt"] }
        a.jargon("alpha line\n", at: pt(0))
        b.jargon("beta line\n", at: pt(0))
        a.sync(at: pt(1))
        b.sync(at: pt(1.5))
        probeCollide(server: fa, other: fb, into: g)
        a.use(drive: g); b.use(drive: g)
        for i in 0..<4 { b.sync(at: pt(2 + Double(i))); a.sync(at: pt(2.5 + Double(i))) }
        expectProbe(Set(a.commands).isSuperset(of: ["alpha"]) && Set(b.commands).isSuperset(of: ["beta"]), "each Mac keeps its own custom commands")
        expectProbe(Set(a.hidden).isSuperset(of: ["Acme"]) && Set(b.hidden).isSuperset(of: ["Bolt"]), "each Mac keeps its own hidden words")
        expectProbe(a.jargonText.contains("alpha line") && b.jargonText.contains("beta line"), "each Mac keeps its own jargon lines")
        expectProbe(a.commands == b.commands, "the Macs converge on commands")
    }

    // S2b: as S2, but iCloud keeps A's settings.json and B's jargon.txt.
    @Test func s2bSplitWinners() {
        let w = ProbeWorld()
        let fa = w.drive("s2b-a"), fb = w.drive("s2b-b"), g = w.path("s2b-g")
        let a = ProbeMac("s2b-A", in: w, drive: fa), b = ProbeMac("s2b-B", in: w, drive: fb)
        a.jargon("alpha line\n", at: pt(0))
        b.jargon("beta line\n", at: pt(0))
        a.sync(at: pt(1)); b.sync(at: pt(1.5))
        probeCollide(server: fa, other: fb, into: g)
        // jargon.txt: B's won the name.
        let d = g.appendingPathComponent("AllInOneIME")
        try? FileManager.default.removeItem(at: d.appendingPathComponent("jargon 2.txt"))
        try! FileManager.default.removeItem(at: d.appendingPathComponent("jargon.txt"))
        try! FileManager.default.copyItem(at: fb.appendingPathComponent("AllInOneIME/jargon.txt"), to: d.appendingPathComponent("jargon.txt"))
        try! FileManager.default.copyItem(at: fa.appendingPathComponent("AllInOneIME/jargon.txt"), to: d.appendingPathComponent("jargon 2.txt"))
        a.use(drive: g); b.use(drive: g)
        var outcomes: [String] = []
        for i in 0..<4 {
            outcomes.append("B:\(b.sync(at: pt(2 + Double(i))).outcome)")
            outcomes.append("A:\(a.sync(at: pt(2.5 + Double(i))).outcome)")
        }
        expectProbe(a.jargonText.contains("alpha line") && b.jargonText.contains("beta line"), "each keeps its lines")
        expectProbe(a.jargonText == b.jargonText, "the jargon lists converge")
        expectProbe(!outcomes.suffix(2).contains { $0.contains("waiting") }, "nobody is left waiting forever")
    }

    // S3: A and C synced long ago (real data). B, offline (iCloud hasn't listed the folder yet), turns sync on.
    @Test func s3OfflineJoiner() {
        let w = ProbeWorld()
        let g = w.drive("s3-g"), fb = w.drive("s3-b"), g2 = w.path("s3-g2")
        let a = ProbeMac("s3-A", in: w, drive: g) { $0.customCommands = [probeCommand("alpha")] }
        a.sync(at: pt(1))
        a.edit(at: pt(2)) { $0.customCommands = [probeCommand("alpha"), probeCommand("gamma")] }
        a.sync(at: pt(2))
        let b = ProbeMac("s3-B", in: w, drive: fb) { $0.customCommands = [probeCommand("beta")]; $0.maxTokens = 3000 }
        b.jargon("beta line\n", at: pt(0))
        b.sync(at: pt(3))
        probeCollide(server: g, other: fb, into: g2)
        a.use(drive: g2); b.use(drive: g2)
        for i in 0..<3 { b.sync(at: pt(4 + Double(i))); a.sync(at: pt(4.5 + Double(i))) }
        expectProbe(b.commands.contains("beta"), "B (offline joiner) keeps its own custom command (has \(b.commands))")
        expectProbe(b.jargonText.contains("beta line"), "B keeps its jargon line")
        expectProbe(a.commands.contains("gamma"), "A keeps its own commands (has \(a.commands))")
    }

    // S4: both Macs synced, then offline; each edits; each writes its own settings.json; iCloud keeps B's.
    @Test func s4OfflineEditsConflict() {
        let w = ProbeWorld()
        let g = w.drive("s4-g")
        let a = ProbeMac("s4-A", in: w, drive: g), b = ProbeMac("s4-B", in: w, drive: g)
        a.sync(at: pt(1)); b.sync(at: pt(2)); a.sync(at: pt(3))
        let fa = w.path("s4-a"), fb = w.path("s4-b")
        probeCopyDrive(g, fa); probeCopyDrive(g, fb)
        a.use(drive: fa); b.use(drive: fb)
        a.edit(at: pt(10)) { $0.maxTokens = 3000; $0.customCommands = [probeCommand("alpha")] }
        a.sync(at: pt(10))
        b.edit(at: pt(11)) { $0.timeoutSeconds = 40 }
        b.sync(at: pt(11))
        probeCopyDrive(fb, g)  // B's version wins the file
        a.use(drive: g); b.use(drive: g)
        for i in 0..<3 { a.sync(at: pt(20 + Double(i))); b.sync(at: pt(20.5 + Double(i))) }
        expectProbe(a.config.maxTokens == 3000 && b.config.maxTokens == 3000, "A's offline change survives (A \(a.config.maxTokens), B \(b.config.maxTokens))")
        expectProbe(a.config.timeoutSeconds == 40 && b.config.timeoutSeconds == 40, "B's offline change survives")
        expectProbe(b.commands == ["alpha"], "A's offline commands reach B (\(b.commands))")
    }

    // S5: settings.json from A (A's jargon hash) but jargon.txt from B: does anyone fix it?
    @Test func s5JargonStuck() {
        let w = ProbeWorld()
        let g = w.drive("s5-g")
        let a = ProbeMac("s5-A", in: w, drive: g), b = ProbeMac("s5-B", in: w, drive: g)
        a.jargon("one\n", at: pt(0))
        a.sync(at: pt(1)); b.sync(at: pt(2)); a.sync(at: pt(3))
        let fa = w.path("s5-a"), fb = w.path("s5-b")
        probeCopyDrive(g, fa); probeCopyDrive(g, fb)
        a.use(drive: fa); b.use(drive: fb)
        b.jargon("one\ntwo-from-B\n", at: pt(10)); b.sync(at: pt(10))
        a.jargon("one\nthree-from-A\n", at: pt(11)); a.sync(at: pt(11))
        // iCloud: settings.json from A (newer), jargon.txt from B.
        probeCopyDrive(fa, g)
        try! FileManager.default.removeItem(at: g.appendingPathComponent("AllInOneIME/jargon.txt"))
        try! FileManager.default.copyItem(at: fb.appendingPathComponent("AllInOneIME/jargon.txt"), to: g.appendingPathComponent("AllInOneIME/jargon.txt"))
        a.use(drive: g); b.use(drive: g)
        var outcomes: [String] = []
        for i in 0..<4 {
            outcomes.append("A:\(a.sync(at: pt(20 + Double(i))).outcome)")
            outcomes.append("B:\(b.sync(at: pt(20.5 + Double(i))).outcome)")
        }
        expectProbe(a.jargonText == b.jargonText, "the jargon lists converge")
        expectProbe(!outcomes.suffix(2).contains { $0.contains("waiting") }, "nobody waits forever")
    }

    // S6: the recent-questions file on one Mac becomes unreadable (it's "only a convenience": loads as empty).
    @Test func s6CorruptLocalQuestions() {
        let w = ProbeWorld()
        let on = ICloudSyncSettings(enabled: true, recentQuestions: true)
        let g = w.drive("s6")
        let a = ProbeMac("s6-A", in: w, drive: g) { $0.iCloudSync = on }, b = ProbeMac("s6-B", in: w, drive: g) { $0.iCloudSync = on }
        b.ask("Quokka one", at: pt(1)); b.ask("Quokka two", at: pt(2))
        b.sync(at: pt(3)); a.sync(at: pt(4)); b.sync(at: pt(5))
        expectProbe(a.questions.count == 2, "A has B's questions (\(a.questions))")
        try! Data("{ garbage".utf8).write(to: a.engine.questionsURL)
        a.sync(at: pt(6)); b.sync(at: pt(7))
        expectProbe(b.questions.count == 2, "a corrupt file on A doesn't clear B's questions")
    }

    // S7: "Remember recent questions" turned off in Settings (deletes them on this Mac), on again later.
    @Test func s7RememberOffOn() {
        let w = ProbeWorld()
        let on = ICloudSyncSettings(enabled: true, recentQuestions: true)
        let g = w.drive("s7")
        let a = ProbeMac("s7-A", in: w, drive: g) { $0.iCloudSync = on }, b = ProbeMac("s7-B", in: w, drive: g) { $0.iCloudSync = on }
        b.ask("Quokka one", at: pt(1)); b.sync(at: pt(2)); a.sync(at: pt(3)); b.sync(at: pt(4))
        a.edit(at: pt(5)) { $0.rememberQuestions = false }
        try? FileManager.default.removeItem(at: a.engine.questionsURL)  // as Settings' switch does
        a.sync(at: pt(5))
        b.ask("Quokka two", at: pt(6)); b.sync(at: pt(6))
        a.edit(at: pt(10)) { $0.rememberQuestions = true }
        let ra = a.sync(at: pt(10))
        let rb = b.sync(at: pt(11))
        b.sync(at: pt(12))
        expectProbe(b.questions.contains("Quokka one"), "turning Remember off/on on A doesn't clear B's (B: \(b.questions))")
    }

    // S8: a newer version's field inside an object key ("redaction"); the old Mac then edits that object.
    @Test func s8NewerFieldInObject() {
        let w = ProbeWorld()
        let g = w.drive("s8")
        let a = ProbeMac("s8-A", in: w, drive: g)
        a.sync(at: pt(1))
        let url = g.appendingPathComponent("AllInOneIME/settings.json")
        var text = try! String(contentsOf: url, encoding: .utf8)
        var remote = try! ICloudSync.RemoteSettings.parse(Data(text.utf8))
        let newer = ICloudSync.Entry(value: .object(["enabled": .bool(true), "emails": .bool(true), "phones": .bool(true), "cards": .bool(true),
                                                     "keys": .bool(true), "ips": .bool(true), "addresses": .bool(true)]),
                                     stamp: .init(modified: pt(2), by: "NEWER-MAC"))
        try! remote.patched(with: ["redaction": newer]).write(to: url)
        a.sync(at: pt(3))
        a.edit(at: pt(4)) { $0.redaction.emails = false }
        a.sync(at: pt(4))
        text = try! String(contentsOf: url, encoding: .utf8)
        remote = try! ICloudSync.RemoteSettings.parse(Data(text.utf8))
        expectProbe(remote.entries["redaction"]?.value.flatMap { if case let .object(f) = $0 { return f["addresses"] } else { return nil } } != nil,
              "the newer version's field in redaction survives an edit on the old Mac")
    }

    // S9: a newer Mac's custom commands that this version can't read (a new type); a fresh old Mac joins with its own.
    @Test func s9RefusedMergeOverwrites() {
        let w = ProbeWorld()
        let g = w.drive("s9")
        let a = ProbeMac("s9-A", in: w, drive: g) { $0.customCommands = [probeCommand("alpha")] }
        a.sync(at: pt(1))
        let url = g.appendingPathComponent("AllInOneIME/settings.json")
        let remote = try! ICloudSync.RemoteSettings.parse(Data(contentsOf: url))
        let list: AIConfig.JSONValue = .array([.object(["name": .string("alpha"), "type": .string("prompt"), "prompt": .string("do alpha")]),
                                               .object(["name": .string("shortcut"), "type": .string("shortcut"), "shortcut": .string("Foo")])])
        try! remote.patched(with: ["customCommands": .init(value: list, stamp: .init(modified: pt(2), by: "NEWER-MAC"))]).write(to: url)
        // B (this version) joins later; its config was saved just now (turning sync on in Settings).
        let b = ProbeMac("s9-B", in: w, drive: g) { $0.customCommands = [probeCommand("beta")] }
        probeTouch(b.engine.configURL, pt(10))
        let r1 = b.sync(at: pt(10))
        let r2 = b.sync(at: pt(11))
        let after = try! ICloudSync.RemoteSettings.parse(Data(contentsOf: url))
        let names = String(describing: after.entries["customCommands"]?.value)
        expectProbe(names.contains("shortcut"), "the newer Mac's command stays in iCloud (now \(names.prefix(160)))")
    }

    // S10: privacy: what lands in the iCloud folder and the state file.
    @Test func s10Privacy() {
        let w = ProbeWorld()
        let g = w.drive("s10")
        let a = ProbeMac("s10-A", in: w, drive: g) {
            $0.redaction.customWords = ["SecretCodename"]
            $0.customCommands = [probeCommand("alpha")]
            $0.extensionFolders = ["/Users/someone/secret-ext"]
        }
        a.ask("PrivateQuestionText", at: pt(0))
        a.sync(at: pt(1))
        let all = (try? FileManager.default.subpathsOfDirectory(atPath: g.path)) ?? []
        var blob = ""
        for p in all { blob += (try? String(contentsOf: g.appendingPathComponent(p), encoding: .utf8)) ?? "" }
        expectProbe(!blob.contains("SecretCodename"), "hidden words not in iCloud with the opt-in off (default)")
        expectProbe(!blob.contains("PrivateQuestionText"), "questions not in iCloud with the opt-in off (default)")
        expectProbe(!blob.contains("secret-ext"), "extension folders not in iCloud")
        let on = ICloudSyncSettings(enabled: true, hiddenWords: true, recentQuestions: true)
        a.edit(at: pt(2)) { $0.iCloudSync = on }
        a.sync(at: pt(3))
        let state = (try? String(contentsOf: a.engine.stateURL, encoding: .utf8)) ?? ""
        expectProbe(!state.contains("PrivateQuestionText") && !state.lowercased().contains("privatequestiontext"), "the state file never holds question text")
        let q = (try? String(contentsOf: g.appendingPathComponent("AllInOneIME/questions.json"), encoding: .utf8)) ?? ""
        expectProbe(q.contains("PrivateQuestionText"), "opted in: questions.json holds them")
        let mode = (try? FileManager.default.attributesOfItem(atPath: g.appendingPathComponent("AllInOneIME/questions.json").path))?[.posixPermissions] as? Int
        expectProbe(mode == 0o600, "questions.json in iCloud is the user's only (\(String(mode ?? 0, radix: 8)))")
    }

    // S11: how long a run takes (temp folder, warm).
    @Test func s11Timing() {
        let w = ProbeWorld()
        let g = w.drive("s11")
        let a = ProbeMac("s11-A", in: w, drive: g) { c in c.customCommands = (0..<40).map { probeCommand("c" + String(UnicodeScalar(97 + $0 % 26)!) + String(UnicodeScalar(97 + $0 / 26)!)) } }
        a.jargon(String(repeating: "jargon line\n", count: 2000), at: pt(0))
        a.sync(at: pt(1))
        let start = Date()
        for i in 0..<20 { a.sync(at: pt(2 + Double(i))) }
        let perRun = Date().timeIntervalSince(start) / 20
        expectProbe(perRun < 0.25, "a run with nothing to do is quick (\(Int(perRun * 1000)) ms)")
    }

    // S12: runs settle: no uploads on repeated runs.
    @Test func s12PingPong() {
        let w = ProbeWorld()
        let g = w.drive("s12")
        let a = ProbeMac("s12-A", in: w, drive: g) { $0.appProfiles["com.Apple.Mail"] = AppProfile(typeOut: true) }
        let b = ProbeMac("s12-B", in: w, drive: g) { $0.appProfiles["com.apple.mail"] = AppProfile(typeOut: false) }
        a.sync(at: pt(1)); b.sync(at: pt(2))
        a.edit(at: pt(3)) { $0.maxTokens = 1000 }
        var ups: [Int] = []
        for i in 0..<5 { ups.append(a.sync(at: pt(4 + Double(i))).uploaded.count); ups.append(b.sync(at: pt(4.5 + Double(i))).uploaded.count) }
        expectProbe(ups.suffix(4).allSatisfy { $0 == 0 }, "runs settle")
    }

    // S13: Remove from iCloud on B; A never turned off (normal mode); fresh C joins first. A keeps its commands?
    @Test func s13RemoveThenFreshJoinNormal() {
        let w = ProbeWorld()
        let g = w.drive("s13")
        let a = ProbeMac("s13-A", in: w, drive: g) { $0.customCommands = [probeCommand("alpha")] }
        a.sync(at: pt(1))
        try? FileManager.default.removeItem(at: g.appendingPathComponent("AllInOneIME"))
        let c = ProbeMac("s13-C", in: w, drive: g) { $0.customCommands = [probeCommand("gamma")] }
        c.sync(at: pt(2))
        for i in 0..<3 { a.sync(at: pt(3 + Double(i))); c.sync(at: pt(3.5 + Double(i))) }
        expectProbe(a.commands.contains("alpha"), "A keeps its commands")
        expectProbe(c.commands.contains("gamma"), "C keeps its own commands (it joined an empty iCloud)")
    }

    // S14: iCloud's questions.json unreadable: waiting forever? set aside?
    @Test func s14QuestionsCorruptICloud() {
        let w = ProbeWorld()
        let on = ICloudSyncSettings(enabled: true, recentQuestions: true)
        let g = w.drive("s14")
        let a = ProbeMac("s14-A", in: w, drive: g) { $0.iCloudSync = on }
        a.ask("one", at: pt(0)); a.sync(at: pt(1))
        let url = g.appendingPathComponent("AllInOneIME/questions.json")
        try! Data("{ broken".utf8).write(to: url)
        var outs: [String] = []
        for i in 0..<3 { outs.append("\(a.sync(at: pt(2 + Double(i))).outcome)") }
        expectProbe(!outs.last!.contains("waiting"), "an unreadable questions.json doesn't leave sync waiting forever")
    }

    // S15: hidden words turned on then off: are they still in iCloud?
    @Test func s15HiddenOffAfterOn() {
        let w = ProbeWorld()
        let g = w.drive("s15")
        let a = ProbeMac("s15-A", in: w, drive: g) { $0.iCloudSync = ICloudSyncSettings(enabled: true, hiddenWords: true); $0.redaction.customWords = ["Codename"] }
        a.sync(at: pt(1))
        a.edit(at: pt(2)) { $0.iCloudSync.hiddenWords = false }
        a.sync(at: pt(2))
        let s = (try? String(contentsOf: g.appendingPathComponent("AllInOneIME/settings.json"), encoding: .utf8)) ?? ""
        // Turning the switch off leaves them in iCloud (Settings says so); "Remove from iCloud…" for hidden words takes them out.
        expectProbe(s.contains("Codename"), "turning Hidden words off leaves them in iCloud, as Settings says")
        try? a.engine.removeFromICloud(.hiddenWords)
        let after = (try? String(contentsOf: g.appendingPathComponent("AllInOneIME/settings.json"), encoding: .utf8)) ?? ""
        expectProbe(!after.contains("Codename") && after.contains("maxTokens"), "Remove from iCloud takes only the hidden words out")
        expectProbe(a.hidden == ["Codename"], "this Mac keeps its own")
        a.sync(at: pt(3))
        let still = (try? String(contentsOf: g.appendingPathComponent("AllInOneIME/settings.json"), encoding: .utf8)) ?? ""
        expectProbe(!still.contains("Codename"), "with the switch off, they don't go back up")
    }

    // S16: Mac A's config was hand-edited with a command Settings wouldn't save (a digit in its name); B joins.
    @Test func s16HandEditedInvalidCommand() {
        let w = ProbeWorld()
        let g = w.drive("s16")
        let a = ProbeMac("s16-A", in: w, drive: g) { $0.customCommands = [probeCommand("alpha"), probeCommand("gpt4")] }
        a.sync(at: pt(1))
        let b = ProbeMac("s16-B", in: w, drive: g) { $0.customCommands = [probeCommand("beta")] }
        probeTouch(b.engine.configURL, pt(10))  // Settings saved it when sync was turned on
        let r1 = b.sync(at: pt(10)), r2 = b.sync(at: pt(11))
        a.sync(at: pt(12))
        expectProbe(a.commands.contains("alpha"), "A keeps its valid commands after B joins (A: \(a.commands))")
    }

    // S17: rejoin: B changed its commands while off; iCloud's (changed too) can't be read here.
    @Test func s17RejoinRefusedMerge() {
        let w = ProbeWorld()
        let g = w.drive("s17")
        let a = ProbeMac("s17-A", in: w, drive: g) { $0.customCommands = [probeCommand("alpha")] }
        a.sync(at: pt(1))
        let b = ProbeMac("s17-B", in: w, drive: g)
        b.sync(at: pt(2))
        b.edit(at: pt(3)) { $0.iCloudSync.enabled = false }
        b.sync(at: pt(3))
        a.edit(at: pt(4)) { $0.customCommands = [probeCommand("alpha"), probeCommand("gpt4")] }  // hand edit
        a.sync(at: pt(4))
        b.edit(at: pt(5)) { $0.customCommands = [probeCommand("alpha"), probeCommand("beta")] }
        b.edit(at: pt(6)) { $0.iCloudSync.enabled = true }
        let r1 = b.sync(at: pt(6)), r2 = b.sync(at: pt(7))
        a.sync(at: pt(8))
        expectProbe(a.commands.contains("gpt4"), "a refused merge never puts B's list over iCloud's (A: \(a.commands))")
    }
}

/// The review's other fixes: Migration Assistant copies, Clears made in Settings, newer fields in objects, Rime's
/// sync folder, a category waiting while the others sync.
@Suite(.serialized)
struct ICloudSyncReviewFixTests {
    @Test func aRecordCopiedFromAnotherMacGetsAMacIDOfItsOwn() throws {
        let w = ProbeWorld()
        let g = w.drive("mig")
        let a = ProbeMac("mig-A", in: w, drive: g)
        a.sync(at: pt(1))
        let id = a.state.macID
        #expect(a.state.machine == "probe-machine-mig-A")
        #expect(!a.sync(at: pt(2)).newMachine && a.state.macID == id)
        // Migration Assistant: the same files on new hardware.
        a.engine.machineID = { "another-machine" }
        let report = a.sync(at: pt(3))
        #expect(report.newMachine && a.state.macID != id && a.state.machine == "another-machine")
        a.edit(at: pt(4)) { $0.typeOut = true }
        a.sync(at: pt(5))
        let entry = try ICloudSync.RemoteSettings.parse(Data(contentsOf: g.appendingPathComponent("AllInOneIME/settings.json"))).entries["typeOut"]
        #expect(entry?.stamp.by == a.state.macID)
    }

    @Test func aClearInSettingsIsRecordedAndRememberOffIsNoClear() {
        let w = ProbeWorld()
        let on = ICloudSyncSettings(enabled: true, recentQuestions: true)
        let g = w.drive("clear")
        let a = ProbeMac("clear-A", in: w, drive: g) { $0.iCloudSync = on }, b = ProbeMac("clear-B", in: w, drive: g) { $0.iCloudSync = on }
        b.ask("Quokka one", at: pt(1))
        b.ask("Quokka two", at: pt(2))
        b.sync(at: pt(3)); a.sync(at: pt(4))
        // "Remember recent questions" off on A (deleted here, the switch's hook), and on again: B keeps them, A gets them back.
        try? FileManager.default.removeItem(at: a.engine.questionsURL)
        a.engine.forgetQuestionsSeen()
        a.sync(at: pt(5)); b.sync(at: pt(6))
        #expect(b.questions.count == 2 && a.questions.count == 2, "A: \(a.questions), B: \(b.questions)")
        // "Clear" on A at minute 8 (recorded); B asked one at 7, unseen by A: asked before the Clear, it goes too.
        b.ask("Quokka three", at: pt(7))
        try? FileManager.default.removeItem(at: a.engine.questionsURL)
        a.engine.recordQuestionsClear(at: pt(8))
        b.ask("Quokka four", at: pt(9))
        a.sync(at: pt(10)); b.sync(at: pt(11)); a.sync(at: pt(12))
        #expect(a.questions == ["Quokka four"] && b.questions == ["Quokka four"], "A: \(a.questions), B: \(b.questions)")
    }

    @Test func newerFieldsInAppAndProviderSettingsSurviveAnOlderMacsEdit() throws {
        let w = ProbeWorld()
        let g = w.drive("fields")
        let a = ProbeMac("fields-A", in: w, drive: g) { $0.appProfiles["com.apple.mail"] = AppProfile(typeOut: true) }
        a.sync(at: pt(1))
        let url = g.appendingPathComponent("AllInOneIME/settings.json")
        let remote = try ICloudSync.RemoteSettings.parse(Data(contentsOf: url))
        let stamp = ICloudSync.Stamp(modified: pt(2), by: "NEWER")
        try remote.patched(with: [
            "appProfiles.com.apple.mail": .init(value: .object(["typeOut": .bool(true), "tone": .string("warm")]), stamp: stamp),
            "anthropic": .init(value: .object(["model": .string("claude-haiku-5-5"), "cacheHint": .bool(true)]), stamp: stamp),
        ]).write(to: url)
        a.sync(at: pt(3))
        a.edit(at: pt(4)) { $0.appProfiles["com.apple.mail"]?.noAI = true; $0.anthropic.model = "claude-opus-5-5" }
        let report = a.sync(at: pt(5))
        #expect(Set(report.uploaded) == ["appProfiles.com.apple.mail", "anthropic"])
        let after = try ICloudSync.RemoteSettings.parse(Data(contentsOf: url)).entries
        #expect(after["appProfiles.com.apple.mail"]?.value == .object(["typeOut": .bool(true), "noAI": .bool(true), "tone": .string("warm")]))
        #expect(after["anthropic"]?.value == .object(["model": .string("claude-opus-5-5"), "cacheHint": .bool(true)]))
        // Settled: the same stamp isn't sent again.
        #expect(a.sync(at: pt(6)).uploaded.isEmpty)
    }

    @Test func aCategoryWaitingDoesntStopTheOthersFromSyncing() throws {
        let w = ProbeWorld()
        let g = w.drive("wait")
        let a = ProbeMac("wait-A", in: w, drive: g), b = ProbeMac("wait-B", in: w, drive: g)
        a.jargon("one\n", at: pt(0))
        a.sync(at: pt(1)); b.sync(at: pt(2))
        a.jargon("two\n", at: pt(3))
        a.edit(at: pt(3)) { $0.typeOut = true }
        a.sync(at: pt(4))
        let file = g.appendingPathComponent("AllInOneIME/jargon.txt")
        let data = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        try data.write(to: g.appendingPathComponent("AllInOneIME/.jargon.txt.icloud"))
        let report = b.sync(at: pt(5))
        #expect(report.outcome == .waiting && report.waitingFor == [.jargon])
        #expect(b.config.typeOut && b.state.lastSync == pt(5), "the settings synced, and say so")
    }

    @Test func questionsGoToICloudForTheUserOnlyAndAnUnreadableOneIsSetAside() throws {
        let w = ProbeWorld()
        let on = ICloudSyncSettings(enabled: true, recentQuestions: true)
        let g = w.drive("qfile")
        let a = ProbeMac("qfile-A", in: w, drive: g) { $0.iCloudSync = on }
        a.ask("Quokka", at: pt(0))
        a.sync(at: pt(1))
        let url = g.appendingPathComponent("AllInOneIME/questions.json")
        #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) == 0o600)
        try Data("{ broken".utf8).write(to: url)
        let report = a.sync(at: pt(2))
        #expect(report.outcome == .synced && report.setAside?.hasPrefix("questions (unreadable ") == true)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("Quokka"))
        // This Mac's own file unreadable: set aside, never taken as no questions.
        try Data("{ broken".utf8).write(to: a.engine.questionsURL)
        let local = a.sync(at: pt(3))
        #expect(local.questionsSetAside?.hasPrefix("questions (unreadable ") == true)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("Quokka"), "iCloud's kept")
        a.sync(at: pt(4))
        #expect(a.questions == ["Quokka"], "back from iCloud")
    }

    @Test func removingTheRecentQuestionsFromICloud() throws {
        let w = ProbeWorld()
        let on = ICloudSyncSettings(enabled: true, recentQuestions: true)
        let g = w.drive("qremove")
        let a = ProbeMac("qremove-A", in: w, drive: g) { $0.iCloudSync = on }
        a.ask("Quokka", at: pt(0))
        a.sync(at: pt(1))
        a.edit(at: pt(2)) { $0.iCloudSync.recentQuestions = false }
        try a.engine.removeFromICloud(.recentQuestions)
        #expect(!FileManager.default.fileExists(atPath: g.appendingPathComponent("AllInOneIME/questions.json").path))
        let text = try String(contentsOf: g.appendingPathComponent("AllInOneIME/settings.json"), encoding: .utf8)
        #expect(!text.contains(ICloudSync.questionsKey) && text.contains("maxTokens"))
        #expect(a.questions == ["Quokka"], "this Mac keeps its own")
    }

    @Test func rimesSyncFolderIsTakenOutOnlyWhenItIsOurs() throws {
        let w = ProbeWorld()
        let user = w.root.appendingPathComponent("Rime")
        let ours = w.root.appendingPathComponent("CloudDocs/AllInOneIME/rime")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        let yaml = user.appendingPathComponent("installation.yaml")
        try Data("installation_id: \"copied-id\"\nsync_dir: \"/Users/me/Dropbox/RimeSync\"\n".utf8).write(to: yaml)
        #expect(try !RimeSync.removeSyncDir(ifItIs: ours, userDataDir: user), "the user's own sync_dir stays")
        #expect(RimeSync.syncDir(in: try String(contentsOf: yaml, encoding: .utf8)) == "/Users/me/Dropbox/RimeSync")
        try RimeSync.setSyncDir(ours, userDataDir: user)
        #expect(try RimeSync.removeSyncDir(ifItIs: ours, userDataDir: user))
        #expect(RimeSync.syncDir(in: try String(contentsOf: yaml, encoding: .utf8)) == nil)
        // A Rime folder copied from another Mac: a new installation id is made.
        #expect(try RimeSync.resetInstallationID(userDataDir: user))
        #expect(try !String(contentsOf: yaml, encoding: .utf8).contains("installation_id"))
        #expect(try !RimeSync.resetInstallationID(userDataDir: user))
    }
}

/// The second review's probes (scratchpad/icloud-probe2, S18–S25) as regression tests.
@Suite(.serialized)
struct ICloudSyncReview2Tests {
    @Test func s18ThreeMacsJoinAtOnce() {
        let w = ProbeWorld()
        let fa = w.drive("s18-a"), fb = w.drive("s18-b"), fc = w.drive("s18-c")
        let a = ProbeMac("s18-A", in: w, drive: fa) { $0.customCommands = [probeCommand("alpha")] }
        let b = ProbeMac("s18-B", in: w, drive: fb) { $0.customCommands = [probeCommand("beta")] }
        let c = ProbeMac("s18-C", in: w, drive: fc) { $0.customCommands = [probeCommand("gamma")] }
        a.sync(at: pt(1)); b.sync(at: pt(1.1)); c.sync(at: pt(1.2))
        // iCloud keeps A's files; B and C both see A's (not each other's yet) and merge.
        probeCopyDrive(fa, fb); probeCopyDrive(fa, fc)
        b.sync(at: pt(2)); c.sync(at: pt(2.1))
        // B's and C's settings.json meet: C's keeps the name.
        let g = w.path("s18-g")
        probeCollide(server: fc, other: fb, into: g)
        a.use(drive: g); b.use(drive: g); c.use(drive: g)
        for i in 0..<4 { a.sync(at: pt(3 + Double(i))); b.sync(at: pt(3.3 + Double(i))); c.sync(at: pt(3.6 + Double(i))) }
        expectProbe(Set(a.commands) == ["alpha", "beta", "gamma"] && a.commands == b.commands && b.commands == c.commands,
              "three Macs joining at once all end with every Mac's commands")
    }

    // S19: the app writes the join's values on the main thread, then Settings (stale model, read before the join) saves
    // the whole file because the user toggled a switch before the window read the file again.
    @Test func s19StaleSettingsSaveAfterJoin() {
        let w = ProbeWorld()
        let g = w.drive("s19")
        let a = ProbeMac("s19-A", in: w, drive: g) { $0.customCommands = [probeCommand("alpha")]; $0.maxTokens = 2000 }
        a.sync(at: pt(1))
        let b = ProbeMac("s19-B", in: w, drive: g) { $0.customCommands = [probeCommand("beta")] }
        let stale = b.config  // Settings' model as the window had it when sync was turned on
        b.sync(at: pt(2))     // the join: B takes maxTokens 2000, merges commands, and puts the merge up
        expectProbe(b.config.maxTokens == 2000 && Set(b.commands) == ["alpha", "beta"], "B joined (\(b.config.maxTokens), \(b.commands))")
        // The user turns on "Hidden words" before Settings re-read the file: whole-file save of the stale model.
        // Settings now writes only the keys the window changed since it last read the file (SettingsModel.save).
        var saved = stale
        saved.iCloudSync.hiddenWords = true
        try! AIConfig.writing(saved, from: stale, keys: AIConfig.changedKeys(stale, saved), at: b.engine.configURL)
        probeTouch(b.engine.configURL, pt(2.01))
        expectProbe(b.config.maxTokens == 2000 && Set(b.commands) == ["alpha", "beta"] && b.config.iCloudSync.hiddenWords,
                    "Settings' save kept the join's values (\(b.config.maxTokens), \(b.commands))")
        b.sync(at: pt(2.02))
        a.sync(at: pt(3))
        expectProbe(a.config.maxTokens == 2000 && a.commands.contains("alpha"), "A's settings survive B's stale Settings save")
    }

    // S20: the record says another machine (Migration Assistant): a new Mac id; nothing lost, nothing storms.
    @Test func s20MachineChange() {
        let w = ProbeWorld()
        let g = w.drive("s20")
        let a = ProbeMac("s20-A", in: w, drive: g) { $0.customCommands = [probeCommand("alpha")] }
        a.engine.machineID = { "machine-one" }
        a.sync(at: pt(1))
        let b = ProbeMac("s20-B", in: w, drive: g)
        b.engine.machineID = { "machine-two" }
        b.sync(at: pt(2))
        // A's whole folder (config, record) copied to a new Mac A2.
        let a2 = ProbeMac("s20-A2", in: w, drive: g)
        try! FileManager.default.removeItem(at: a2.engine.configURL)
        try! FileManager.default.copyItem(at: a.engine.configURL, to: a2.engine.configURL)
        try! FileManager.default.copyItem(at: a.engine.stateURL, to: a2.engine.stateURL)
        a2.engine.machineID = { "machine-three" }
        let r = a2.sync(at: pt(3))
        var ups: [Int] = []
        for i in 0..<3 { ups.append(a.sync(at: pt(4 + Double(i))).uploaded.count); ups.append(b.sync(at: pt(4.3 + Double(i))).uploaded.count); ups.append(a2.sync(at: pt(4.6 + Double(i))).uploaded.count) }
        a2.edit(at: pt(10)) { $0.maxTokens = 3000 }
        a2.sync(at: pt(10)); a.sync(at: pt(11)); b.sync(at: pt(12))
        expectProbe(r.newMachine && a2.state.macID != a.state.macID, "the copy gets its own Mac id")
        expectProbe(ups.allSatisfy { $0 == 0 }, "no uploads storm after it")
        expectProbe(a.config.maxTokens == 3000 && b.config.maxTokens == 3000 && a.commands == ["alpha"], "a change on the copy reaches the others")
        // The same machine id again (no copy): never a new id.
        let before = a.state.macID
        a.sync(at: pt(20))
        expectProbe(a.state.macID == before, "the same Mac never gets a new id")
    }

    // S21: B changes the jargon; A gets B's jargon.txt before B's settings.json (still the old stamp); A runs.
    @Test func s21JargonRepairRace() {
        let w = ProbeWorld()
        let g = w.drive("s21")
        let a = ProbeMac("s21-A", in: w, drive: g), b = ProbeMac("s21-B", in: w, drive: g)
        a.jargon("one\n", at: pt(0))
        a.sync(at: pt(1)); b.sync(at: pt(2)); a.sync(at: pt(3))
        let oldSettings = try! Data(contentsOf: g.appendingPathComponent("AllInOneIME/settings.json"))
        b.jargon("one\ntwo-from-B\n", at: pt(10)); b.sync(at: pt(10))
        let newSettings = try! Data(contentsOf: g.appendingPathComponent("AllInOneIME/settings.json"))
        // A sees B's jargon.txt but still the old settings.json.
        try! oldSettings.write(to: g.appendingPathComponent("AllInOneIME/settings.json"))
        let r = a.sync(at: pt(11))
        let jt = (try? String(contentsOf: g.appendingPathComponent("AllInOneIME/jargon.txt"), encoding: .utf8)) ?? "-"
        // Then B's settings.json arrives (A's jargon.txt write may have gone over B's).
        try! newSettings.write(to: g.appendingPathComponent("AllInOneIME/settings.json"))
        var outs: [String] = []
        for i in 0..<3 { outs.append("A:\(a.sync(at: pt(12 + Double(i))).outcome)"); outs.append("B:\(b.sync(at: pt(12.5 + Double(i))).outcome)") }
        expectProbe(a.jargonText.contains("two-from-B") && b.jargonText.contains("two-from-B"), "B's new line reaches A and stays on B")
    }

    // S22: three Macs, varied settings, many runs: nothing re-uploads once settled.
    @Test func s22SettleThreeMacs() {
        let w = ProbeWorld()
        let g = w.drive("s22")
        let on = ICloudSyncSettings(enabled: true, hiddenWords: true, recentQuestions: true)
        let a = ProbeMac("s22-A", in: w, drive: g) { $0.iCloudSync = on; $0.customCommands = [probeCommand("alpha")]; $0.redaction.customWords = ["X"]; $0.appProfiles["com.Apple.Mail"] = AppProfile(typeOut: true) }
        let b = ProbeMac("s22-B", in: w, drive: g) { $0.iCloudSync = on; $0.customCommands = [probeCommand("beta")]; $0.appProfiles["com.apple.mail"] = AppProfile(noAI: true) }
        let c = ProbeMac("s22-C", in: w, drive: g) { $0.iCloudSync = on; $0.redaction.customWords = ["Y"] }
        a.jargon("a\n", at: pt(0)); c.jargon("c\n", at: pt(0))
        a.ask("qa", at: pt(0)); b.ask("qb", at: pt(0.5))
        var ups: [[String]] = []
        for i in 0..<6 {
            ups.append(a.sync(at: pt(1 + Double(i))).uploaded); ups.append(b.sync(at: pt(1.3 + Double(i))).uploaded); ups.append(c.sync(at: pt(1.6 + Double(i))).uploaded)
        }
        expectProbe(ups.suffix(6).allSatisfy(\.isEmpty), "settles (last two rounds upload nothing)")
        expectProbe(a.commands == c.commands && a.hidden == c.hidden && a.jargonText == c.jargonText, "converged")
    }

    // S23: Remove hidden words from iCloud (switch off first, as Settings does); another Mac with it on puts its own back.
    @Test func s23RemoveHiddenWords() {
        let w = ProbeWorld()
        let g = w.drive("s23")
        let on = ICloudSyncSettings(enabled: true, hiddenWords: true)
        let a = ProbeMac("s23-A", in: w, drive: g) { $0.iCloudSync = on; $0.redaction.customWords = ["Codename"] }
        a.sync(at: pt(1))
        a.edit(at: pt(2)) { $0.iCloudSync.hiddenWords = false }
        try! a.engine.removeFromICloud(.hiddenWords)
        a.sync(at: pt(3))
        let s = (try? String(contentsOf: g.appendingPathComponent("AllInOneIME/settings.json"), encoding: .utf8)) ?? ""
        expectProbe(!s.contains("Codename"), "removed from iCloud and not put back by this Mac")
        expectProbe(a.hidden == ["Codename"], "kept on this Mac")
        // While settings.json isn't downloaded: does it say so?
        let url = g.appendingPathComponent("AllInOneIME/settings.json")
        let data = try! Data(contentsOf: url)
        try! FileManager.default.removeItem(at: url)
        try! Data().write(to: g.appendingPathComponent("AllInOneIME/.settings.json.icloud"))
        // Put back (another Mac's sync) while it's a placeholder: Remove says it waits, and a later run finishes it.
        let back = try! ICloudSync.RemoteSettings.parse(data).patched(with: [ICloudSync.hiddenWordsKey: .init(value: .array([.string("Codename")]), stamp: .init(modified: pt(2.5), by: "OTHER"))])
        let result = try? a.engine.removeFromICloud(.hiddenWords)
        expectProbe(result == .waiting, "a placeholder: Remove says it is waiting, not that it removed them (\(String(describing: result)))")
        expectProbe(a.state.pendingRemovals == [.hiddenWords], "noted for the next run")
        try! FileManager.default.removeItem(at: g.appendingPathComponent("AllInOneIME/.settings.json.icloud"))
        try! back.write(to: url)
        // A copy set aside earlier holds them too.
        try! back.write(to: g.appendingPathComponent("AllInOneIME/settings (unreadable 2026-10-16 180000).json"))
        a.sync(at: pt(4))
        let after = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        expectProbe(!after.contains("Codename") && a.state.pendingRemovals.isEmpty, "the next run that can read settings.json removed them")
        expectProbe(!FileManager.default.fileExists(atPath: g.appendingPathComponent("AllInOneIME/settings (unreadable 2026-10-16 180000).json").path),
                    "the set-aside copy holding them went too")
    }

    // S24: Remember off (Settings: deletes here, no Clear), the setting syncs to B, then on again.
    @Test func s24RememberOffOnResurrects() {
        let w = ProbeWorld()
        let on = ICloudSyncSettings(enabled: true, recentQuestions: true)
        let g = w.drive("s24")
        let a = ProbeMac("s24-A", in: w, drive: g) { $0.iCloudSync = on }, b = ProbeMac("s24-B", in: w, drive: g) { $0.iCloudSync = on }
        a.ask("Secret one", at: pt(1)); a.sync(at: pt(2)); b.sync(at: pt(3)); a.sync(at: pt(3.5))
        a.edit(at: pt(4)) { $0.rememberQuestions = false }
        try? FileManager.default.removeItem(at: a.engine.questionsURL)
        a.engine.forgetQuestionsSeen()
        a.sync(at: pt(4)); b.sync(at: pt(5))
        expectProbe(b.questions == ["Secret one"], "turning Remember off on A clears nothing on B")
        a.edit(at: pt(6)) { $0.rememberQuestions = true }
        a.sync(at: pt(6)); b.sync(at: pt(7)); a.sync(at: pt(8))
        // As the README says: on again, the other Macs' questions come back.
        expectProbe(a.questions == ["Secret one"] && b.questions == ["Secret one"], "A: \(a.questions), B: \(b.questions)")
    }

    // S25: Clear in Settings while the questions switch is off on this Mac, then the switch on.
    @Test func s25ClearWhileQuestionsOff() {
        let w = ProbeWorld()
        let on = ICloudSyncSettings(enabled: true, recentQuestions: true)
        let g = w.drive("s25")
        let a = ProbeMac("s25-A", in: w, drive: g) { $0.iCloudSync = on }, b = ProbeMac("s25-B", in: w, drive: g) { $0.iCloudSync = on }
        b.ask("B one", at: pt(1)); b.sync(at: pt(2)); a.sync(at: pt(3))
        a.edit(at: pt(4)) { $0.iCloudSync.recentQuestions = false }
        a.sync(at: pt(4))
        try? FileManager.default.removeItem(at: a.engine.questionsURL)
        a.engine.recordQuestionsClear(at: pt(5))
        b.ask("B two", at: pt(6)); b.sync(at: pt(6))
        a.edit(at: pt(10)) { $0.iCloudSync.recentQuestions = true }
        a.sync(at: pt(10)); b.sync(at: pt(11))
        // A Clear made while this Mac didn't sync the questions is its own: the other Macs keep theirs (documented).
        expectProbe(Set(b.questions) == ["B one", "B two"], "B: \(b.questions)")
        expectProbe(Set(a.questions) == ["B one", "B two"], "A gets them back once it syncs them: \(a.questions)")
    }

    /// A Settings save landing while a run writes: the key Settings changed since the run read the file stays as Settings
    /// wrote it, and goes up next run as this Mac's change.
    @Test func aSettingsSaveDuringARunIsNeverOverwritten() throws {
        let w = ProbeWorld()
        let g = w.drive("race")
        let a = ProbeMac("race-A", in: w, drive: g), b = ProbeMac("race-B", in: w, drive: g)
        a.sync(at: pt(1)); b.sync(at: pt(2))
        a.edit(at: pt(3)) { $0.maxTokens = 2500; $0.typeOut = true }
        a.sync(at: pt(4))
        // B's run reads its file, then Settings saves maxTokens before the run writes.
        var engine = b.engine
        engine.now = { pt(5) }
        engine.writeConfig = { config, old, keys, url in
            let before = try Config.load(from: url)
            var user = before
            user.maxTokens = 3000
            try AIConfig.writing(user, from: before, keys: ["maxTokens"], at: url)
            probeTouch(url, pt(5))
            return try ICloudSync.writeConfig(config, readAs: old, keys: keys, at: url)
        }
        let report = engine.run()
        expectProbe(report.configKeys == ["typeOut"] && b.config.maxTokens == 3000 && b.config.typeOut, "\(report.configKeys)")
        expectProbe(b.sync(at: pt(6)).uploaded == ["maxTokens"], "Settings' change goes up next")
        a.sync(at: pt(7))
        expectProbe(a.config.maxTokens == 3000, "and wins: it is the newer")
    }
}
