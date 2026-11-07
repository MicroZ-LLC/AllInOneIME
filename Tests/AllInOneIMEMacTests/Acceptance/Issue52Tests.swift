import Foundation
import Testing

// Issue #52: clipboard history reads Universal Clipboard text on the main thread. With the history on and Paste from
// Other Apps set to Allow, each copy is recorded at the history's next look (`ClipboardRecorder.poll`): its text read
// with `SystemClipboard.text()`, on the input method's main thread. A copy made on an iPhone or another Mac (Universal
// Clipboard: `com.apple.is-remote-clipboard` among its types) hands its text over only when it is read, fetched over
// the network, so typing waits on it: at the look each second, at ⌃V's panel (it looks before showing the history), and
// at a paste into a terminal (it looks before its write). `SystemClipboard.image()` already skips a remote item for
// exactly this reason; `text()` doesn't. Expected: no wait on the main thread for a copy made on an iPhone, and a copy
// made on this Mac still recorded.
//
// The input method's own code can't be imported here (it is an executable target): as Issue35Tests does it, its
// ClipboardHistory.swift (`ClipboardHistoryShared`: the recorder over the general pasteboard, its look each second, the
// panel's items) and TerminalPaste.swift (its look before a write) are compiled into a child process, with the Mac
// library and the core, and started as at launch (`ClipboardHistoryShared.start()`) on a run loop, as the input method's
// main thread. There the general pasteboard is a private one of the child's (the Mac's own clipboard is never touched),
// Paste from Other Apps is Allow, Accessibility is granted and the keys TerminalPaste posts never leave the child, the
// child's home is a folder of the test's (the history's file is never the user's), and the stand-ins are those of the
// input method's own files not compiled in: whether secure input is on (SecureInput), the config as the file has it
// (LiveConfig, the history on), the log. Once it runs, the user copies: a second process, the app the copy was made in
// (Universal Clipboard's, or an app on this Mac), puts it on that pasteboard and hands its text over only when it is
// read, two seconds after being asked where it came from an iPhone (the network). The child measures how long its main
// thread, where the input method answers keys, is kept from answering as the history looks at that copy.

@Suite(.serialized)
struct Issue52Tests {
    /// Longer than typing ever waits on the clipboard; well under the two seconds the iPhone's copy takes.
    static let limit: TimeInterval = 0.5

    /// Copied on an iPhone (Universal Clipboard), then typing on (`path`: the look each second, ⌃V's panel, a result pasted
    /// into a terminal): the history's look never holds the main thread up while the text is fetched from the iPhone.
    @Test(arguments: Issue52Child.Path.allCases)
    func aUniversalClipboardCopyNeverHoldsUpTyping(_ path: Issue52Child.Path) throws {
        let report = try Issue52Child.run(path, .remote)
        #expect(report.copied, "the iPhone's copy never reached the clipboard: \(report)")
        if let call = report.call {
            #expect(call < Self.limit, "\(path.title): it waited \(Self.seconds(call)) for the iPhone's copy (fetched over the network): \(report)")
        }
        #expect(report.longestStall < Self.limit,
                "\(path.title): keys typed meanwhile waited \(Self.seconds(report.longestStall)) (the main thread read the iPhone's copy): \(report)")
    }

    /// Copied in an app on this Mac, its text handed over at once: the history records it at its next look, as before,
    /// without holding typing up. (And the copy's text is read across processes here, so the wait above is real.)
    @Test func aCopyMadeOnThisMacIsStillRecorded() throws {
        let report = try Issue52Child.run(.tick, .local)
        #expect(report.copied, "the copy never reached the clipboard: \(report)")
        #expect(report.history.first == Issue52Child.Kind.local.text, "the copy isn't in ⌃V's history: \(report)")
        #expect(report.asked > 0, "the copy's app was never asked for its text: \(report)")
        #expect(report.longestStall < Self.limit, "keys typed meanwhile waited \(Self.seconds(report.longestStall)): \(report)")
    }

    static func seconds(_ interval: TimeInterval) -> String { String(format: "%.2f s", interval) }
}

enum Issue52Child {
    /// Where the history looks at the copy, as the user types on.
    enum Path: String, CaseIterable, CustomTestStringConvertible, Sendable {
        /// Its look each second (`ClipboardHistoryShared.start`'s timer on the main run loop).
        case tick
        /// ⌃V's panel, which looks before showing the history (`ClipboardHistoryShared.services.items`).
        case panel
        /// A multi-line result pasted into a terminal, which has the history look before its write
        /// (`TerminalPaste.paste`, `TerminalPaste.lookBeforeWrite`).
        case paste
        var testDescription: String { rawValue }

        var title: String {
            switch self {
            case .tick: "the history's look each second"
            case .panel: "⌃V's panel"
            case .paste: "a multi-line result pasted into a terminal"
            }
        }
    }

    /// Where the user copied, and how its app hands the text over when read.
    enum Kind: String, Sendable {
        /// On an iPhone (Universal Clipboard: `com.apple.is-remote-clipboard` among its types), its text two seconds to
        /// come (the network).
        case remote
        /// In an app on this Mac that hands its text over at once.
        case local

        var text: String { self == .remote ? "copied on the iPhone" : "copied on this Mac" }
    }

    /// What the child saw.
    struct Report: Decodable, CustomStringConvertible {
        /// Whether the copy reached the clipboard.
        var copied: Bool
        /// How long the panel's items (the paste) took on the main thread, in seconds; nil for the look each second.
        var call: Double?
        /// The longest the input method's main thread was kept from answering, from the copy on, in seconds.
        var longestStall: Double
        /// The history's items after three seconds of typing on.
        var history: [String]
        /// How many times the copy's app was asked for its text.
        var asked: Int

        var description: String {
            "copied \(copied), " + (call.map { "call took \(Issue52Tests.seconds($0)), " } ?? "")
                + "main thread held \(Issue52Tests.seconds(longestStall)), history \(history), the copy's app asked \(asked) times"
        }
    }

    struct Failure: Error, CustomStringConvertible { var description: String }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    /// The history started, then `kind`'s copy made and the history looking at it through `path`: what the child saw.
    static func run(_ path: Path, _ kind: Kind) throws -> Report {
        let executable = try compiled.get()
        // The child's home: the history's file there, never the user's.
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("issue52-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let name = "com.aipinyin.inputmethod.issue52.\(UUID().uuidString)"
        let result = try command(executable, [path.rawValue, kind.rawValue, name],
                                 environment: ["CFFIXED_USER_HOME": home.path, "HOME": home.path], timeout: 60)
        guard result.status == 0, let line = result.output.split(separator: "\n").last(where: { $0.hasPrefix("REPORT ") }) else {
            throw Failure(description: "the child (\(path.rawValue), \(kind.rawValue)) failed (\(result.status)):\n\(result.output)")
        }
        return try JSONDecoder().decode(Report.self, from: Data(line.dropFirst("REPORT ".count).utf8))
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("issue52-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let harness = scratch.appendingPathComponent("Harness.swift")
        try Issue52Harness.swift.write(to: harness, atomically: true, encoding: .utf8)
        let stubs = scratch.appendingPathComponent("Stubs.c"), stubsObject = scratch.appendingPathComponent("Stubs.o")
        try Issue52Harness.stubs.write(to: stubs, atomically: true, encoding: .utf8)
        let clang = try command(URL(fileURLWithPath: "/usr/bin/xcrun"), ["clang", "-c", stubs.path, "-o", stubsObject.path], timeout: 60)
        guard clang.status == 0 else { throw Failure(description: clang.output) }
        // The Mac library and the core, as `swift test` built them for this target.
        let products = repository.appendingPathComponent(".build/debug")
        let modules = fm.fileExists(atPath: products.appendingPathComponent("Modules").path)
            ? products.appendingPathComponent("Modules") : products
        var objects: [String] = []
        for module in ["AllInOneIMEMac", "AllInOneIMECore", "AllInOneIMEText", "AllInOneIMEScriptEngine", "CQuickJS", "Crypto"] {
            let aggregate = products.appendingPathComponent(module + ".o")
            if fm.fileExists(atPath: aggregate.path) {
                objects.append(aggregate.path)
            } else if let files = try? fm.contentsOfDirectory(at: products.appendingPathComponent(module + ".build"), includingPropertiesForKeys: nil) {
                objects += files.filter { $0.pathExtension == "o" }.map(\.path)
            }
        }
        let sources = ["TerminalPaste.swift", "ClipboardHistory.swift"].map { repository.appendingPathComponent("Sources/AllInOneIME/" + $0).path }
        let executable = scratch.appendingPathComponent("issue52")
        let arguments = ["swiftc", "-swift-version", "5", "-parse-as-library", "-I", modules.path,
                         "-I", repository.appendingPathComponent("Core/Sources/CRime").path,
                         "-framework", "AppKit", "-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"]
            + sources + [harness.path, stubsObject.path] + objects + ["-o", executable.path]
        let swift = try command(URL(fileURLWithPath: "/usr/bin/xcrun"), arguments, timeout: 240)
        guard swift.status == 0 else {
            throw Failure(description: "compiling TerminalPaste.swift and ClipboardHistory.swift with the harness:\n\(swift.output)")
        }
        return executable
    }

    private static func command(_ executable: URL, _ arguments: [String], environment: [String: String] = [:],
                                timeout: TimeInterval) throws -> (status: Int32, output: String) {
        // A file, not a pipe: a long compiler output never blocks the child.
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("issue52-\(UUID().uuidString).log")
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
        if !environment.isEmpty { process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 } }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            throw Failure(description: "timed out: \(executable.lastPathComponent) \(arguments.first ?? "")")
        }
        return (process.terminationStatus, (try? String(contentsOf: log, encoding: .utf8)) ?? "")
    }
}

/// The child's sources: a harness around the input method's TerminalPaste.swift and ClipboardHistory.swift (nothing of
/// them rewritten), and C stand-ins for Accessibility and posting keys, linked in ahead of the system's. The same
/// executable is the copy's app (`source`) and the input method (the path).
private enum Issue52Harness {
    static let stubs = #"""
#include <stdint.h>
// Accessibility granted, never asked for; the keys posted handed to the harness, never posted to the Mac.
unsigned char AXIsProcessTrusted(void) { return 1; }
unsigned char AXIsProcessTrustedWithOptions(const void *options) { return 1; }
static void (*posted)(void *event);
void issue52_on_post(void (*callback)(void *event)) { posted = callback; }
void CGEventPost(uint32_t tap, void *event) { if (posted) posted(event); }
"""#

    static let swift = #"""
import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import Foundation
import ObjectiveC
import os

@_silgen_name("issue52_on_post") func issue52OnPost(_ callback: @convention(c) (UnsafeMutableRawPointer?) -> Void)

// The input method's own, not compiled in: its log, whether secure input is on (it isn't), the config as its file has
// it (clipboard history on, 20 kept).
let log = Logger(subsystem: "com.aipinyin.inputmethod.issue52", category: "ime")

enum SecureInput {
    static var isOn = false
}

enum LiveConfig {
    static var config = Config.default
    static var currentIfValid: Config? { config }
}

struct Issue52Report: Encodable {
    var copied = false
    var call: Double?
    var longestStall = 0.0
    var history: [String] = []
    var asked = 0
}

/// The app the copy was made in: it hands its text over only when it is read, `delay` after being asked, and says so.
final class Issue52Source: NSObject, NSPasteboardItemDataProvider {
    let text: String
    let delay: TimeInterval
    init(text: String, delay: TimeInterval) { (self.text, self.delay) = (text, delay) }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        print("ASKED \(type.rawValue)")
        fflush(stdout)
        Thread.sleep(forTimeInterval: delay)
        item.setString(text, forType: type)
    }
}

/// The general pasteboard, the test's named one; Paste from Other Apps: Allow; a terminal reading it at each paste key.
enum Issue52Clipboard {
    static var pasteboard: NSPasteboard!

    static func install(_ name: String) {
        pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
        let general = class_getClassMethod(NSPasteboard.self, NSSelectorFromString("generalPasteboard"))!
        let generalBlock: @convention(block) (AnyObject) -> NSPasteboard = { _ in Issue52Clipboard.pasteboard }
        method_setImplementation(general, imp_implementationWithBlock(generalBlock))
        // `NSPasteboard.AccessBehavior.alwaysAllow` (macOS 15.4; before it, nothing asks).
        if let access = class_getInstanceMethod(NSPasteboard.self, NSSelectorFromString("accessBehavior")) {
            let accessBlock: @convention(block) (AnyObject) -> Int = { _ in 2 }
            method_setImplementation(access, imp_implementationWithBlock(accessBlock))
        }
        issue52OnPost { pointer in
            guard let pointer else { return }
            let event = Unmanaged<CGEvent>.fromOpaque(pointer).takeUnretainedValue()
            guard event.type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 9 else { return }  // V
            // The terminal takes the paste.
            _ = Issue52Clipboard.pasteboard.string(forType: .string)
        }
    }
}

/// How long the main thread (where the input method answers keys) is kept from answering: the longest a block handed to
/// it waits to run, handed one every 5 ms from another thread.
final class Issue52Heartbeat: @unchecked Sendable {
    private let lock = NSLock()
    private var longestValue = 0.0
    private var running = true
    private var finished = false

    var longest: Double {
        lock.lock()
        defer { lock.unlock() }
        return longestValue
    }

    func start() {
        Thread.detachNewThread { [self] in
            while true {
                lock.lock()
                let goOn = running
                lock.unlock()
                guard goOn else { break }
                let start = Date()
                DispatchQueue.main.sync {}
                let waited = Date().timeIntervalSince(start)
                lock.lock()
                longestValue = max(longestValue, waited)
                lock.unlock()
                Thread.sleep(forTimeInterval: 0.005)
            }
            lock.lock()
            finished = true
            lock.unlock()
        }
    }

    /// Stopped once the block handed last has run and its wait is counted (the main thread let go meanwhile: a wait that
    /// ends as the measuring does is counted too).
    @MainActor
    func stop() async {
        lock.lock()
        running = false
        lock.unlock()
        while true {
            lock.lock()
            let done = finished
            lock.unlock()
            if done { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

@main
struct Issue52Main {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 4, ["source", "tick", "panel", "paste"].contains(arguments[1]), ["remote", "local"].contains(arguments[2])
        else {
            print("usage: issue52 source|tick|panel|paste remote|local <pasteboard>")
            exit(2)
        }
        let (kind, name) = (arguments[2], arguments[3])
        if arguments[1] == "source" {
            // What the user copied, its text handed over when read: two seconds after being asked from an iPhone.
            let source = kind == "remote" ? Issue52Source(text: "copied on the iPhone", delay: 2)
                : Issue52Source(text: "copied on this Mac", delay: 0)
            let pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
            pasteboard.clearContents()
            let item = NSPasteboardItem()
            if kind == "remote" { item.setData(Data(), forType: NSPasteboard.PasteboardType(SystemClipboard.remoteType)) }
            item.setDataProvider(source, forTypes: [.string])
            pasteboard.writeObjects([item])
            print("READY")
            fflush(stdout)
            withExtendedLifetime(source) { RunLoop.main.run() }
            return
        }
        Platform.current = .mac  // as the input method's launch
        // Never the user's history: the child's home is the test's.
        let file = ClipboardHistoryStore.defaultURL
        guard let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"], !home.isEmpty,
              file.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path)
        else {
            print("the history's file isn't in the test's home: \(file.path)")
            exit(3)
        }
        Issue52Clipboard.install(name)
        let path = arguments[1]
        Task { @MainActor in
            let report = await inputMethod(path, kind, name)
            let json = try! JSONEncoder().encode(report)
            print("REPORT " + String(decoding: json, as: UTF8.self))
            fflush(stdout)
            exit(0)
        }
        // The input method's main thread: a run loop, as NSApplication's (the history's timer runs on it).
        RunLoop.main.run()
    }

    @MainActor
    static func inputMethod(_ path: String, _ kind: String, _ name: String) async -> Issue52Report {
        var report = Issue52Report()
        let pasteboard = Issue52Clipboard.pasteboard!
        defer { pasteboard.releaseGlobally() }
        ClipboardHistoryShared.start()  // as at launch: a look now (nothing copied yet), then each second

        // The user copies (on the iPhone, in an app on this Mac): the copy's app puts it on the clipboard. The main thread
        // is held meanwhile, so no look is made before the one through `path`.
        let sourceLog = FileManager.default.temporaryDirectory.appendingPathComponent("issue52-source-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: sourceLog.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: sourceLog) }
        let handle = try! FileHandle(forWritingTo: sourceLog)
        let source = Process()
        source.executableURL = Bundle.main.executableURL
        source.arguments = ["source", kind, name]
        source.standardOutput = handle
        source.standardError = handle
        do { try source.run() } catch {
            print("the copy's app couldn't start: \(error)")
            exit(4)
        }
        defer {
            if source.isRunning { source.terminate() }
            source.waitUntilExit()
            try? handle.close()
        }
        let sourceOutput = { (try? String(contentsOf: sourceLog, encoding: .utf8)) ?? "" }
        let ready = Date().addingTimeInterval(20)
        while !sourceOutput().contains("READY") && source.isRunning && Date() < ready { Thread.sleep(forTimeInterval: 0.01) }
        report.copied = sourceOutput().contains("READY") && !(pasteboard.types ?? []).isEmpty

        // Typing on from here: how long the main thread is kept from answering keys.
        let heartbeat = Issue52Heartbeat()
        heartbeat.start()
        let start = Date()
        switch path {
        case "panel":
            // ⌃V: the panel asks for the history's items.
            _ = ClipboardHistoryShared.services.items()
            report.call = Date().timeIntervalSince(start)
        case "paste":
            // A multi-line result going into a terminal (`@improve`, `@question`).
            _ = await TerminalPaste.paste("first line\nsecond line")
            report.call = Date().timeIntervalSince(start)
        default:
            break  // the history's next look each second
        }
        // Three seconds of typing on, the history looking each second.
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        await heartbeat.stop()
        report.longestStall = heartbeat.longest
        report.history = ClipboardHistoryShared.recorder.store.items.map { $0.image != nil ? "<image>" : $0.text }
        report.asked = sourceOutput().split(separator: "\n").filter { $0.hasPrefix("ASKED ") }.count
        return report
    }
}
"""#
}
