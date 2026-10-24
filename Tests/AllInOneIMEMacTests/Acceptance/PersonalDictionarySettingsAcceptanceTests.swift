import Foundation
import Testing

/// Independent acceptance of the production Settings model, with real local dictionary persistence.
/// No file dialog, installed IME, live configuration, or implementation-author tests are used.
@Suite(.serialized)
struct PersonalDictionarySettingsAcceptanceTests {
    @Test func mutationsRunInBackgroundRefreshAndAutomaticallyRedeploy() throws {
        try DictionarySettingsChild.run("mutations")
    }

    @Test func missingPackAndFailedDeploymentsNeverClaimSuccess() throws {
        try DictionarySettingsChild.run("states")
    }
}

private enum DictionarySettingsChild {
    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }
    struct Failure: Error, CustomStringConvertible { var description: String }

    static func run(_ scenario: String) throws {
        let executable = try compiled.get()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dictionary-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try command(executable, [scenario, root.path, thirdParty.path], injectObserver: true)
        #expect(result.status == 0, "\(result.output)")
        #expect(result.output.contains("PASS dictionary-settings \(scenario)"), "\(result.output)")
    }

    static var thirdParty: URL {
        ProcessInfo.processInfo.environment["ALLINONEIME_THIRDPARTY"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("ThirdParty")
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("dictionary-settings-harness-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let source = try String(contentsOf: repository.appendingPathComponent("Sources/AllInOneIME/PersonalDictionariesSettings.swift"), encoding: .utf8)
        guard let end = source.range(of: "\nstruct PersonalDictionariesSection:") else {
            throw Failure(description: "Cannot isolate production PersonalDictionariesModel declaration")
        }
        let model = scratch.appendingPathComponent("ProductionDictionaryModel.swift")
        try String(source[..<end.lowerBound]).write(to: model, atomically: true, encoding: .utf8)
        let harness = scratch.appendingPathComponent("Harness.swift")
        try harnessSource.write(to: harness, atomically: true, encoding: .utf8)
        let observer = scratch.appendingPathComponent("ReadGate.c")
        try readGateSource.write(to: observer, atomically: true, encoding: .utf8)
        let library = scratch.appendingPathComponent("ReadGate.dylib")
        let c = try command(URL(fileURLWithPath: "/usr/bin/xcrun"), ["clang", "-dynamiclib", observer.path, "-o", library.path])
        guard c.status == 0 else { throw Failure(description: c.output) }
        let products = repository.appendingPathComponent(".build/debug")
        let modules = fm.fileExists(atPath: products.appendingPathComponent("Modules").path)
            ? products.appendingPathComponent("Modules") : products
        var objects: [String] = []
        for name in ["AllInOneIMECore", "AllInOneIMEText", "AllInOneIMEScriptEngine", "Crypto"] {
            let aggregate = products.appendingPathComponent(name + ".o")
            if fm.fileExists(atPath: aggregate.path) { objects.append(aggregate.path) }
            else {
                objects += try fm.contentsOfDirectory(at: products.appendingPathComponent(name + ".build"), includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "o" }.map(\.path)
            }
        }
        let rimeLib = thirdParty.appendingPathComponent("librime/dist/lib")
        let executable = scratch.appendingPathComponent("acceptance")
        let args = ["swiftc", "-swift-version", "5", "-parse-as-library", "-I", modules.path,
                    "-I", repository.appendingPathComponent("Core/Sources/CRime").path,
                    "-L", rimeLib.path, "-lrime", "-Xlinker", "-rpath", "-Xlinker", rimeLib.path,
                    "-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels",
                    "-framework", "AppKit", "-framework", "SwiftUI", model.path, harness.path, library.path]
            + objects + ["-o", executable.path]
        let swift = try command(URL(fileURLWithPath: "/usr/bin/xcrun"), args)
        guard swift.status == 0 else { throw Failure(description: swift.output) }
        return executable
    }

    static func command(_ executable: URL, _ args: [String], injectObserver: Bool = false) throws -> (status: Int32, output: String) {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("dictionary-settings-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: log) }
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.currentDirectoryURL = repository
        process.standardOutput = handle
        process.standardError = handle
        if injectObserver {
            var environment = ProcessInfo.processInfo.environment
            environment["DYLD_INSERT_LIBRARIES"] = executable.deletingLastPathComponent().appendingPathComponent("ReadGate.dylib").path
            process.environment = environment
        }
        try process.run()
        let deadline = Date().addingTimeInterval(60)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { process.terminate(); throw Failure(description: "Isolated dictionary Settings child timed out") }
        return (process.terminationStatus, (try? String(contentsOf: log, encoding: .utf8)) ?? "")
    }

    static let harnessSource = #"""
import AllInOneIMECore
import AppKit
import Foundation

func tr(_ chinese: String, _ english: String) -> String { english }
// All otherwise-live process globals are local stand-ins. The production model and persistence
// implementation are unchanged; only engine completion is controlled by this test.
enum RimeDirectories {
    static var user = URL(fileURLWithPath: "/private/tmp/unconfigured-dictionary-test")
    static var shared: URL?
}
@MainActor enum LiveConfig {
    static var current: Config { try! Config.load() } // selfTestURL is set before any model is created
}
@MainActor final class RimeService {
    enum DeploymentStatus { case idle, deploying, succeeded, failed }
    static let shared = RimeService()
    var isStarted = true
    var isReady = true
    var deploymentStatus = DeploymentStatus.failed
    var deploymentError: String? = nil
    var redeploys = 0, starts = 0
    var requests: Int { redeploys + starts }
    var onRequest: (() -> Void)?
    func redeploy(invalidateGeneratedSchema: Bool = false) { redeploys += 1; isReady = false; onRequest?() }
    func finish(_ outcome: DeploymentStatus) { deploymentStatus = outcome; isReady = true }
}
@MainActor enum RimeStartup {
    static func start() {
        let engine = RimeService.shared
        engine.starts += 1
        engine.isStarted = true
        engine.isReady = false
        engine.onRequest?()
    }
}
@_silgen_name("dictionary_gate_arm") func armReadGate(_ path: UnsafePointer<CChar>)
@_silgen_name("dictionary_gate_seen") func readGateSeen() -> Int32
@_silgen_name("dictionary_gate_on_main") func readGateOnMain() -> Int32
@_silgen_name("dictionary_gate_release") func releaseReadGate()

@MainActor enum Check {
    static var total = 0, failures = 0
    static func that(_ condition: Bool, _ message: String) {
        total += 1
        if !condition { failures += 1; print("FAIL: " + message) }
    }
    struct Timeout: Error, CustomStringConvertible { var description: String }
    static func until(context: () -> String = { "" }, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(4)
        while !condition() {
            if Date() > deadline { throw Timeout(description: "Timed out: " + context()) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
struct Fixture {
    let root: URL, user: URL, schema: URL
    var store: PersonalDictionaryStore { PersonalDictionaryStore(userDirectory: user, schema: schema) }
    @MainActor init(_ root: URL, thirdParty: URL) throws {
        self.root = root
        user = root.appendingPathComponent("user")
        schema = root.appendingPathComponent("shared/rime_ice.schema.yaml")
        let fm = FileManager.default
        try fm.createDirectory(at: user.appendingPathComponent("rime_ice.userdb"), withIntermediateDirectories: true)
        try fm.createDirectory(at: schema.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: thirdParty.appendingPathComponent("rime-data/rime_ice.schema.yaml"), to: schema)
        // This model test needs a complete tiny pack fixture, not the production vocabulary graph.
        try "---\nname: rime_ice\nversion: \"fixture\"\nsort: by_weight\n...\n原词\tyuan ci\t100\n"
            .write(to: schema.deletingLastPathComponent().appendingPathComponent("rime_ice.dict.yaml"), atomically: true, encoding: .utf8)
        try Data("existing learned words".utf8).write(to: user.appendingPathComponent("rime_ice.userdb/KEEP"))
        try Data("existing installation".utf8).write(to: user.appendingPathComponent("installation.yaml"))
        Config.selfTestURL = root.appendingPathComponent("config.json")
        var config = Config.default
        config.uiLanguage = "en"
        config.fuzzyPinyin = ["z-zh"]
        try config.write()
        UIText.choice = "en"
        RimeDirectories.user = user
        RimeDirectories.shared = schema.deletingLastPathComponent()
    }
    func source(_ file: String, name: String = "settings_acceptance", count: Int = 1, valid: Bool = true) throws -> URL {
        let url = root.appendingPathComponent(file + ".dict.yaml")
        let rows = (0..<count).map { "验收\($0)\t\(valid ? "yan shou" : "invalid-123")\t100\n" }.joined()
        try ("---\nname: \(name)\nversion: \"1\"\nsort: by_weight\n...\n" + rows).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    func snapshot() throws -> [String: Data] {
        let files = FileManager.default.enumerator(at: user, includingPropertiesForKeys: [.isRegularFileKey])!
        var result: [String: Data] = [:]
        for case let url as URL in files where (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
            result[String(url.path.dropFirst(user.path.count))] = try Data(contentsOf: url)
        }
        return result
    }
}

@MainActor func mutations(_ fixture: Fixture) async throws {
    let model = PersonalDictionariesModel(userDirectory: fixture.user, schema: { fixture.schema })
    let source = try fixture.source("chosen")
    let other = try fixture.source("overlap", name: "must_not_import")
    let original = try Data(contentsOf: source)
    let engine = RimeService.shared
    let preserved = try fixture.snapshot()
    source.path.withCString(armReadGate)
    defer { releaseReadGate() }
    let importing = Task { await model.importDictionary(from: source, fuzzyPinyin: ["z-zh"]) }
    try await Check.until { readGateSeen() != 0 }
    Check.that(readGateOnMain() == 0, "real source I/O and parsing start on a worker, leaving the main actor responsive")
    Check.that(model.isWorking && model.status == "Saving dictionaries…" && model.error == nil, "saving state is visible during background work")
    Check.that(engine.requests == 0, "deployment is not requested before the file is saved")
    // Change the actual isolated saved config while parsing is paused. The caller's original
    // argument is deliberately stale by the time the mutation finishes.
    var current = try Config.load()
    current.fuzzyPinyin = ["n-l"]
    try current.write()
    let configBytes = try Data(contentsOf: Config.defaultURL)
    let overlap = Task { await model.importDictionary(from: other, fuzzyPinyin: []) }
    let removal = Task { await model.removeDictionary(named: "settings_acceptance", fuzzyPinyin: []) }
    let refresh = Task { await model.refresh() }
    try await Task.sleep(for: .milliseconds(50))
    Check.that(model.dictionaries.isEmpty && engine.requests == 0, "working state rejects overlapping imports, removal and refresh")
    engine.onRequest = {
        Check.that((try? fixture.store.list().map(\.name)) == ["settings_acceptance"], "saved dictionary is present before automatic deployment")
        Check.that((try? fixture.store.applyFuzzyPinyin(["n-l"])) == .unchanged, "latest saved fuzzy choice is already reconciled before deployment")
    }
    releaseReadGate()
    try await Check.until(context: { "import: working=\(model.isWorking), status=\(model.status ?? "nil"), error=\(model.error ?? "nil")" }) { engine.requests > 0 }
    Check.that(engine.requests == 1 && model.dictionaries.count == 1, "successful import refreshes the displayed list and requests one deploy")
    Check.that(model.isWorking && model.status == "Redeploying dictionaries…" && model.error == nil,
               "a previous failed deployment is not treated as the completion of this pending request")
    engine.finish(.succeeded)
    await importing.value; await overlap.value; await removal.value; await refresh.value
    engine.onRequest = nil
    Check.that(!model.isWorking && model.error == nil && model.status == "Dictionaries redeployed and ready to use.", "new successful deployment ends the working state honestly")
    Check.that(try engine.requests == 1 && fixture.store.list().count == 1, "overlapping actions did not introduce a second mutation or deploy")
    let reopened = PersonalDictionariesModel(userDirectory: fixture.user, schema: { fixture.schema })
    await reopened.refresh()
    Check.that(reopened.dictionaries == model.dictionaries, "opening the settings list reads the saved dictionary")
    let updated = try fixture.source("chosen-again", count: 2)
    let updating = Task { await model.importDictionary(from: updated, fuzzyPinyin: ["n-l"]) }
    try await Check.until(context: { "update: \(model.error ?? model.status ?? "nil")" }) { engine.requests == 2 }
    Check.that(model.dictionaries.count == 1 && model.dictionaries.first?.entryCount == 2 && model.dictionaries.first?.fileName == updated.lastPathComponent,
               "reimporting the same identity updates list metadata without adding a duplicate")
    engine.finish(.succeeded); await updating.value
    let beforeInvalid = try fixture.snapshot()
    let invalid = try fixture.source("invalid-update", count: 3, valid: false)
    await model.importDictionary(from: invalid, fuzzyPinyin: ["n-l"])
    Check.that(try fixture.snapshot() == beforeInvalid, "invalid update leaves every working-copy byte unchanged")
    Check.that(engine.requests == 2 && !model.isWorking && model.error != nil && model.status == nil,
               "invalid update reports an error, clears old success, and does not redeploy")
    Check.that(model.dictionaries.first?.entryCount == 2, "invalid update preserves the displayed working dictionary")
    let deleting = Task { await model.removeDictionary(named: "settings_acceptance", fuzzyPinyin: ["n-l"]) }
    try await Check.until(context: { "remove: \(model.error ?? model.status ?? "nil")" }) { engine.requests == 3 }
    Check.that(try model.dictionaries.isEmpty && fixture.store.list().isEmpty, "removal refreshes persisted and displayed lists before automatic redeploy")
    engine.finish(.succeeded); await deleting.value
    await reopened.refresh()
    Check.that(reopened.dictionaries.isEmpty && !model.isWorking && model.error == nil, "later refresh observes removal and successful deployment")
    Check.that(try Data(contentsOf: source) == original, "import, reimport and removal leave the chosen source untouched")
    Check.that(try Data(contentsOf: Config.defaultURL) == configBytes, "model mutations do not overwrite the saved configuration")
    let after = try fixture.snapshot()
    Check.that(preserved.allSatisfy { after[$0.key] == $0.value }, "existing installation and learned-word files are untouched")
}

@MainActor func states(_ fixture: Fixture) async throws {
    let source = try fixture.source("chosen")
    let blocked = PersonalDictionariesModel(userDirectory: fixture.user, schema: { nil })
    let before = try fixture.snapshot()
    await blocked.importDictionary(from: source, fuzzyPinyin: [])
    await blocked.removeDictionary(named: "anything", fuzzyPinyin: [])
    Check.that(!blocked.hasChinesePack && !blocked.isWorking && blocked.dictionaries.isEmpty, "no Chinese pack blocks direct import/remove")
    Check.that(try fixture.snapshot() == before && RimeService.shared.requests == 0, "no-pack actions neither write files nor request deployment")
    let engine = RimeService.shared
    engine.isStarted = false
    let model = PersonalDictionariesModel(userDirectory: fixture.user, schema: { fixture.schema })
    let importing = Task { await model.importDictionary(from: source, fuzzyPinyin: []) }
    try await Check.until(context: { "startup: working=\(model.isWorking), status=\(model.status ?? "nil"), error=\(model.error ?? "nil")" }) { engine.starts == 1 }
    Check.that(engine.redeploys == 0 && engine.isStarted, "a saved import starts Rime automatically when it is not running")
    Check.that(model.isWorking && model.error == nil && model.status == "Redeploying dictionaries…", "pending startup does not reuse a prior failure as success")
    engine.finish(.failed); await importing.value
    Check.that(!model.isWorking && model.status == nil && model.error?.contains("deployment failed") == true,
               "deployment failure is presented as failure rather than ready-to-use")
    Check.that(try model.dictionaries.count == 1 && fixture.store.list().count == 1, "failed deployment retains the successfully saved copy and visible list")
    let updated = try fixture.source("chosen-again", count: 2)
    let updating = Task { await model.importDictionary(from: updated, fuzzyPinyin: []) }
    try await Check.until(context: { "second deploy: \(model.error ?? model.status ?? "nil")" }) { engine.redeploys == 1 }
    // A service can retain the previous notification while a newly queued deploy is not ready.
    engine.deploymentStatus = .succeeded
    try await Task.sleep(for: .milliseconds(50))
    Check.that(model.isWorking && model.error == nil && model.status == "Redeploying dictionaries…", "stale success notification cannot finish an in-flight deployment")
    engine.finish(.failed); await updating.value
    Check.that(model.error?.contains("deployment failed") == true && model.status == nil, "the new failed result takes precedence over stale success")
}

@main struct DictionarySettingsMain {
    @MainActor static func main() async {
        let args = CommandLine.arguments
        guard args.count == 4 else { exit(2) }
        do {
            let fixture = try Fixture(URL(fileURLWithPath: args[2]), thirdParty: URL(fileURLWithPath: args[3]))
            if args[1] == "mutations" { try await mutations(fixture) }
            else if args[1] == "states" { try await states(fixture) }
            else { exit(2) }
        } catch { Check.that(false, "unexpected error: \(error)") }
        print("\(Check.failures == 0 ? "PASS" : "FAIL") dictionary-settings \(args[1]): \(Check.total) checks, \(Check.failures) failures")
        exit(Check.failures == 0 ? 0 : 1)
    }
}
"""#

    // Deterministically pause the real source-file open in a detached import. If the model ever
    // performs it on the main thread, record the failure without deadlocking the test process.
    static let readGateSource = #"""
#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <limits.h>
static char watched[PATH_MAX];
static atomic_int active, seen, on_main;
void dictionary_gate_arm(const char *path) { strlcpy(watched,path,sizeof(watched)); atomic_store(&seen,0); atomic_store(&on_main,0); atomic_store(&active,1); }
int32_t dictionary_gate_seen(void) { return atomic_load(&seen); }
int32_t dictionary_gate_on_main(void) { return atomic_load(&on_main); }
void dictionary_gate_release(void) { atomic_store(&active,0); }
static void note(const char *path, int flags) {
    if (!atomic_load(&active) || !path || strcmp(path,watched) || (flags & (O_WRONLY|O_RDWR))) return;
    if (atomic_exchange(&seen,1)) return;
    atomic_store(&on_main,pthread_main_np());
    if (pthread_main_np()) return;
    for (int i=0; atomic_load(&active) && i<6000; ++i) usleep(1000);
}
static int observed_open(const char *path,int flags,...) {
    mode_t mode=0; if(flags&O_CREAT){va_list a;va_start(a,flags);mode=va_arg(a,int);va_end(a);} note(path,flags); return open(path,flags,mode);
}
static int observed_openat(int fd,const char *path,int flags,...) {
    mode_t mode=0; if(flags&O_CREAT){va_list a;va_start(a,flags);mode=va_arg(a,int);va_end(a);} note(path,flags); return openat(fd,path,flags,mode);
}
extern int original_open_nocancel(const char *,int,...) __asm("_open$NOCANCEL");
static int observed_open_nocancel(const char *path,int flags,...) {
    mode_t mode=0; if(flags&O_CREAT){va_list a;va_start(a,flags);mode=va_arg(a,int);va_end(a);} note(path,flags); return original_open_nocancel(path,flags,mode);
}
extern int original_openat_nocancel(int,const char *,int,...) __asm("_openat$NOCANCEL");
static int observed_openat_nocancel(int fd,const char *path,int flags,...) {
    mode_t mode=0; if(flags&O_CREAT){va_list a;va_start(a,flags);mode=va_arg(a,int);va_end(a);} note(path,flags); return original_openat_nocancel(fd,path,flags,mode);
}
#define INTERPOSE(new,old) __attribute__((used)) static struct {const void *a;const void *b;} pair_##new __attribute__((section("__DATA,__interpose")))={(const void *)(uintptr_t)&new,(const void *)(uintptr_t)&old};
INTERPOSE(observed_open,open)
INTERPOSE(observed_openat,openat)
INTERPOSE(observed_open_nocancel,original_open_nocancel)
INTERPOSE(observed_openat_nocancel,original_openat_nocancel)
"""#
}
