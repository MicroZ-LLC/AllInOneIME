import AppKit
import Foundation
import Testing

// Issue #45: a terminal paste stalls typing while it saves a Universal Clipboard item. With Paste from Other Apps set to
// Allow, a multi-line result going into a terminal (inserted, or typed out: each line break), and a kept image from
// ⌃V's history, go in as a paste: the clipboard is saved first (`ClipboardSnapshot.take`, reading every type of every
// item), on the main thread. When what is on the clipboard was copied on an iPhone (Universal Clipboard: its data is
// fetched over the network when read) or is an app's promised data that is slow to come, the input method waits on it,
// and the keys typed meanwhile wait too. Expected: the paste never waits on remote or promised data: it skips those
// types, or goes in on one line as without read access. Clipboard history already never reads Universal Clipboard's
// data, for the same reason (`SystemClipboard.remoteType`).
//
// The input method's own code can't be imported here (it is an executable target): its TerminalPaste.swift and its
// "can paste in terminal" (InputController's `canPasteInTerminal` default) are compiled into a child process, with the
// Mac library and the core, as the input method runs them (on a run loop, as the input method's main thread). There the
// general pasteboard is a named one of the test's (the Mac's own clipboard is never touched), Paste from Other Apps is
// Allow, Accessibility is granted, and the keys TerminalPaste posts never leave the child: a ⌘V or ⌃V has the terminal
// read the clipboard, as another app. What the user copied is put on that pasteboard by a second process, the app it
// was copied in (Universal Clipboard's, or another app's), which hands its text over only when it is read, two seconds
// after being asked (the network, a busy app). The child measures how long each paste waits before the terminal gets
// it, and how long its main thread, where the input method answers keys, is kept from answering.

@Suite(.serialized)
struct Issue45Tests {
    /// What the user copied (on the iPhone, in another app).
    static let copied = "copied on the iPhone"
    /// A multi-line result, as `@improve` or `@question` puts one in.
    static let answer = "first line\nsecond line"
    /// Longer than a paste or a key ever waits on the clipboard; well under the two seconds the copy's data takes.
    static let limit: TimeInterval = 0.5

    /// Copied on an iPhone (Universal Clipboard), then a result pasted into the terminal (inserted, typed out, a kept
    /// image): it goes in at once, the keys typed meanwhile aren't held up, the iPhone is never asked for the copy's data
    /// (fetched over the network), and what was copied there is still on the clipboard after.
    @Test(arguments: Issue45Child.Action.allCases)
    func aUniversalClipboardCopyNeverHoldsUpAPaste(_ action: Issue45Child.Action) throws {
        let (report, asked) = try Issue45Child.run(action, .remote)
        #expect(report.wentIn, "\(action.title): it never went in: \(report)")
        #expect(report.slowest < Self.limit,
                "\(action.title): it waited \(Self.seconds(report.slowest)) for the iPhone's copy before going in: \(report)")
        #expect(report.longestStall < Self.limit,
                "\(action.title): keys typed meanwhile waited \(Self.seconds(report.longestStall)) (the main thread was held): \(report)")
        #expect(asked == 0, "\(action.title): the iPhone was asked for the copy's data \(asked) times (over the network): \(report)")
        let text = report.clipboardTypes.contains(NSPasteboard.PasteboardType.string.rawValue)
        if action == .image {
            // Without saving the clipboard, the image is left on it for the user's own paste, as without read access.
            #expect(text || report.clipboardTypes.contains(NSPasteboard.PasteboardType.png.rawValue), "the clipboard left empty: \(report)")
        } else {
            #expect(text, "\(action.title): what was copied on the iPhone is no longer on the clipboard: \(report)")
        }
    }

    /// Copied in an app that hands its data over only when it is read and takes its time (a promised type): a result
    /// pasted into the terminal still goes in at once, and the keys typed meanwhile aren't held up.
    @Test(arguments: Issue45Child.Action.allCases)
    func aSlowPromisedCopyNeverHoldsUpAPaste(_ action: Issue45Child.Action) throws {
        let (report, _) = try Issue45Child.run(action, .promised)
        #expect(report.wentIn, "\(action.title): it never went in: \(report)")
        #expect(report.slowest < Self.limit,
                "\(action.title): it waited \(Self.seconds(report.slowest)) for the copied app's data before going in: \(report)")
        #expect(report.longestStall < Self.limit,
                "\(action.title): keys typed meanwhile waited \(Self.seconds(report.longestStall)) (the main thread was held): \(report)")
    }

    /// Copied in an app that hands its data over at once when read: a result is pasted and the clipboard put back as
    /// before. (And the copy's data is read across processes here, so the waits above are real.)
    @Test func aCopyWhoseDataComesAtOnceIsPastedAndPutBack() throws {
        let (report, asked) = try Issue45Child.run(.insert, .instant)
        #expect(report.path == "pasted" && report.terminalGot.contains("text:" + Self.answer), "\(report)")
        #expect(report.clipboardText == Self.copied, "the clipboard after the paste: \(report)")
        #expect(asked > 0, "\(report)")
    }

    static func seconds(_ interval: TimeInterval) -> String { String(format: "%.2f s", interval) }
}

enum Issue45Child {
    /// How the result goes into the terminal.
    enum Action: String, CaseIterable, CustomTestStringConvertible, Sendable {
        /// A multi-line result inserted (`insert`: a paste where it can be, else one line).
        case insert
        /// A multi-line result typed out (`typeOut`): each line break pasted, the next line typed between them.
        case typeOut = "type-out"
        /// A kept image from ⌃V's history (`TerminalPaste.pasteImage`, with ⌃V: a terminal's paste key).
        case image
        var testDescription: String { rawValue }

        var title: String {
            switch self {
            case .insert: "a multi-line result inserted"
            case .typeOut: "a multi-line result typed out"
            case .image: "a kept image pasted"
            }
        }
    }

    /// What the user copied, and how its app hands it over when read.
    enum Kind: String, Sendable {
        /// On an iPhone (Universal Clipboard: `com.apple.is-remote-clipboard` among its types), its text two seconds to
        /// come (the network).
        case remote
        /// In an app that promises its text, two seconds to come.
        case promised
        /// In an app that promises its text and hands it over at once.
        case instant
    }

    /// What the child saw.
    struct Report: Decodable, CustomStringConvertible {
        /// "pasted", or "one line" (inserted, as without read access), "typed" (the line breaks typed out).
        var path: String
        /// Whether the result went in (the terminal got the paste, or it was inserted on one line).
        var wentIn: Bool
        /// The longest a paste took before the terminal got it, in seconds.
        var slowest: Double
        /// The longest the input method's main thread was kept from answering, in seconds.
        var longestStall: Double
        /// What the terminal read off the clipboard at each paste key: "text:…", "png:<bytes>".
        var terminalGot: [String]
        /// The clipboard's types after, as another app sees them (reading them never asks for data).
        var clipboardTypes: [String]
        /// The clipboard's text after (only where it comes at once).
        var clipboardText: String?

        var description: String {
            "\(path), went in \(wentIn), slowest paste \(Issue45Tests.seconds(slowest)), main thread held "
                + "\(Issue45Tests.seconds(longestStall)), terminal got \(terminalGot), clipboard after: \(clipboardTypes)"
                + (clipboardText.map { " \"\($0)\"" } ?? "")
        }
    }

    struct Failure: Error, CustomStringConvertible { var description: String }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    /// `action` with `kind` on the clipboard: what the child saw, and how many times the copy's app was asked for its data.
    static func run(_ action: Action, _ kind: Kind) throws -> (report: Report, asked: Int) {
        let executable = try compiled.get()
        let name = "com.aipinyin.inputmethod.issue45.\(UUID().uuidString)"
        defer { NSPasteboard(name: NSPasteboard.Name(name)).releaseGlobally() }
        // The app the copy was made in, on the clipboard until the end.
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("issue45-source-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        let source = Process()
        source.executableURL = executable
        source.arguments = ["source", kind.rawValue, name]
        source.standardOutput = handle
        source.standardError = handle
        try source.run()
        defer {
            if source.isRunning { source.terminate() }
            source.waitUntilExit()
            try? handle.close()
            try? FileManager.default.removeItem(at: log)
        }
        let sourceLog = { (try? String(contentsOf: log, encoding: .utf8)) ?? "" }
        let ready = Date().addingTimeInterval(20)
        while !sourceLog().contains("READY") && source.isRunning && Date() < ready { Thread.sleep(forTimeInterval: 0.02) }
        guard sourceLog().contains("READY") else { throw Failure(description: "the copy's app never put it on the clipboard:\n\(sourceLog())") }

        let result = try command(executable, [action.rawValue, kind.rawValue, name], timeout: 60)
        guard result.status == 0, let line = result.output.split(separator: "\n").last(where: { $0.hasPrefix("REPORT ") }) else {
            throw Failure(description: "the child (\(action.rawValue), \(kind.rawValue)) failed (\(result.status)):\n\(result.output)")
        }
        let report = try JSONDecoder().decode(Report.self, from: Data(line.dropFirst("REPORT ".count).utf8))
        return (report, sourceLog().split(separator: "\n").filter { $0.hasPrefix("ASKED ") }.count)
    }

    /// InputController's `canPasteInTerminal` default, as written there (`TerminalPaste.isAllowed()` where it can't be
    /// found).
    static func canPasteInTerminal() throws -> String {
        let source = try String(contentsOf: repository.appendingPathComponent("Sources/AllInOneIME/InputController.swift"), encoding: .utf8)
        guard let declaration = source.range(of: #"var canPasteInTerminal\s*:[^=\n]*=\s*"#, options: .regularExpression),
              source[declaration.upperBound...].first == "{"
        else { return "{ TerminalPaste.isAllowed() }" }
        var depth = 0
        var index = declaration.upperBound
        while index < source.endIndex {
            if source[index] == "{" { depth += 1 }
            if source[index] == "}" {
                depth -= 1
                if depth == 0 { return String(source[declaration.upperBound...index]) }
            }
            index = source.index(after: index)
        }
        return "{ TerminalPaste.isAllowed() }"
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("issue45-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let harness = scratch.appendingPathComponent("Harness.swift")
        try Issue45Harness.swift.replacingOccurrences(of: "CAN_PASTE_IN_TERMINAL", with: try canPasteInTerminal())
            .write(to: harness, atomically: true, encoding: .utf8)
        let stubs = scratch.appendingPathComponent("Stubs.c"), stubsObject = scratch.appendingPathComponent("Stubs.o")
        try Issue45Harness.stubs.write(to: stubs, atomically: true, encoding: .utf8)
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
        let executable = scratch.appendingPathComponent("issue45")
        let arguments = ["swiftc", "-swift-version", "5", "-parse-as-library", "-I", modules.path,
                         "-I", repository.appendingPathComponent("Core/Sources/CRime").path,
                         "-framework", "AppKit", "-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels",
                         repository.appendingPathComponent("Sources/AllInOneIME/TerminalPaste.swift").path, harness.path,
                         stubsObject.path] + objects + ["-o", executable.path]
        let swift = try command(URL(fileURLWithPath: "/usr/bin/xcrun"), arguments, timeout: 240)
        guard swift.status == 0 else { throw Failure(description: "compiling TerminalPaste.swift with the harness:\n\(swift.output)") }
        return executable
    }

    private static func command(_ executable: URL, _ arguments: [String], timeout: TimeInterval) throws -> (status: Int32, output: String) {
        // A file, not a pipe: a long compiler output never blocks the child.
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("issue45-\(UUID().uuidString).log")
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

/// The child's sources: a harness around the input method's TerminalPaste.swift (nothing of it rewritten), and C stand-ins
/// for Accessibility and posting keys, linked in ahead of the system's. The same executable is the copy's app
/// (`source`) and the input method (the action).
private enum Issue45Harness {
    static let stubs = #"""
#include <stdint.h>
// Accessibility granted, as the issue's trigger has it; the keys posted handed to the harness, never posted to the Mac.
unsigned char AXIsProcessTrusted(void) { return 1; }
unsigned char AXIsProcessTrustedWithOptions(const void *options) { return 1; }
static void (*posted)(void *event);
void issue45_on_post(void (*callback)(void *event)) { posted = callback; }
void CGEventPost(uint32_t tap, void *event) { if (posted) posted(event); }
"""#

    static let swift = #"""
import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import Foundation
import ObjectiveC

@_silgen_name("issue45_on_post") func issue45OnPost(_ callback: @convention(c) (UnsafeMutableRawPointer?) -> Void)

let copied = "copied on the iPhone"
let answer = "first line\nsecond line"

struct Issue45Report: Encodable {
    var path = ""
    var wentIn = false
    var slowest = 0.0
    var longestStall = 0.0
    var terminalGot: [String] = []
    var clipboardTypes: [String] = []
    var clipboardText: String?
}

/// The app the copy was made in: it hands its text over only when it is read, `delay` after being asked, and says so.
final class Issue45Source: NSObject, NSPasteboardItemDataProvider {
    let delay: TimeInterval
    init(delay: TimeInterval) { self.delay = delay }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        print("ASKED \(type.rawValue)")
        fflush(stdout)
        Thread.sleep(forTimeInterval: delay)
        item.setString(copied, forType: type)
    }
}

/// The general pasteboard, the test's named one; Paste from Other Apps: Allow; the terminal reading it at each paste key.
enum Issue45Clipboard {
    static var pasteboard: NSPasteboard!
    static var terminalGot: [(got: String, at: Date)] = []

    static func install(_ name: String) {
        pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
        let general = class_getClassMethod(NSPasteboard.self, NSSelectorFromString("generalPasteboard"))!
        let generalBlock: @convention(block) (AnyObject) -> NSPasteboard = { _ in Issue45Clipboard.pasteboard }
        method_setImplementation(general, imp_implementationWithBlock(generalBlock))
        // `NSPasteboard.AccessBehavior.alwaysAllow` (macOS 15.4; before it, reading never asks).
        if let access = class_getInstanceMethod(NSPasteboard.self, NSSelectorFromString("accessBehavior")) {
            let accessBlock: @convention(block) (AnyObject) -> Int = { _ in 2 }
            method_setImplementation(access, imp_implementationWithBlock(accessBlock))
        }
        issue45OnPost { pointer in
            guard let pointer else { return }
            let event = Unmanaged<CGEvent>.fromOpaque(pointer).takeUnretainedValue()
            guard event.type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 9 else { return }  // V
            // The terminal takes the paste.
            let pasteboard = Issue45Clipboard.pasteboard!
            if let text = pasteboard.string(forType: .string) { Issue45Clipboard.terminalGot.append(("text:" + text, Date())) }
            if let png = pasteboard.data(forType: .png) { Issue45Clipboard.terminalGot.append(("png:\(png.count)", Date())) }
        }
    }

    /// When the terminal first got something `matching`, after the first `skipping` it got.
    static func got(after skipping: Int, _ matching: (String) -> Bool) -> Date? {
        terminalGot.dropFirst(skipping).first { matching($0.got) }?.at
    }
}

/// How long the main thread (where the input method answers keys) is kept from answering: the longest a block handed to
/// it waits to run, handed one every 5 ms from another thread.
final class Issue45Heartbeat: @unchecked Sendable {
    private let lock = NSLock()
    private var longestValue = 0.0
    private var running = true

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
                guard goOn else { return }
                let start = Date()
                DispatchQueue.main.sync {}
                let waited = Date().timeIntervalSince(start)
                lock.lock()
                longestValue = max(longestValue, waited)
                lock.unlock()
                Thread.sleep(forTimeInterval: 0.005)
            }
        }
    }

    func stop() {
        lock.lock()
        running = false
        lock.unlock()
    }
}

@main
struct Issue45Main {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 4, ["remote", "promised", "instant"].contains(arguments[2]) else {
            print("usage: issue45 source|insert|type-out|image remote|promised|instant <pasteboard>")
            exit(2)
        }
        let (kind, name) = (arguments[2], arguments[3])
        if arguments[1] == "source" {
            // What the user copied, its text handed over when read.
            let source = Issue45Source(delay: kind == "instant" ? 0 : 2)
            let pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
            pasteboard.clearContents()
            let item = NSPasteboardItem()
            if kind == "remote" { item.setData(Data(), forType: NSPasteboard.PasteboardType("com.apple.is-remote-clipboard")) }
            item.setDataProvider(source, forTypes: [.string])
            pasteboard.writeObjects([item])
            print("READY")
            fflush(stdout)
            withExtendedLifetime(source) { RunLoop.main.run() }
            return
        }
        Issue45Clipboard.install(name)
        let action = arguments[1]
        Task { @MainActor in
            let report = await inputMethod(action, kind)
            let json = try! JSONEncoder().encode(report)
            print("REPORT " + String(decoding: json, as: UTF8.self))
            fflush(stdout)
            exit(0)
        }
        // The input method's main thread: a run loop, as NSApplication's.
        RunLoop.main.run()
    }

    @MainActor
    static func inputMethod(_ action: String, _ kind: String) async -> Issue45Report {
        // InputController's own.
        let canPasteInTerminal: @MainActor () -> Bool = CAN_PASTE_IN_TERMINAL
        let heartbeat = Issue45Heartbeat()
        heartbeat.start()
        try? await Task.sleep(nanoseconds: 50_000_000)
        var report = Issue45Report()
        switch action {
        case "insert":
            // InputController's `insert`: a paste where it can be, else one line.
            let start = Date()
            if canPasteInTerminal() {
                report.path = "pasted"
                (report.wentIn, report.slowest) = await paste(answer)
            } else {
                report.path = "one line"
                report.wentIn = true
                report.slowest = Date().timeIntervalSince(start)
            }
        case "type-out":
            // InputController's `typeOut`: each line break pasted, the next line typed between them (longer than the
            // clipboard takes to be put back).
            let pastes = canPasteInTerminal()
            report.path = pastes ? "pasted" : "typed"
            var wentIn = 0
            for _ in 0..<2 {
                if pastes {
                    let (went, after) = await paste("\n")
                    if went { wentIn += 1 }
                    report.slowest = max(report.slowest, after)
                } else {
                    wentIn += 1
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
            report.wentIn = wentIn == 2
        case "image":
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                          hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let png = bitmap.representation(using: .png, properties: [:])!
            let start = Date()
            report.path = "pasted"
            await TerminalPaste.pasteImage(png, controlV: true)
            let at = Issue45Clipboard.got(after: 0) { $0.hasPrefix("png:") }
            report.wentIn = at != nil
            report.slowest = (at ?? Date()).timeIntervalSince(start)
        default:
            print("unknown action \(action)")
            exit(2)
        }
        // The clipboard put back (half a second after the terminal read a text paste).
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        heartbeat.stop()
        report.longestStall = heartbeat.longest
        report.terminalGot = Issue45Clipboard.terminalGot.map(\.got)
        let pasteboard = Issue45Clipboard.pasteboard!
        report.clipboardTypes = pasteboard.types?.map(\.rawValue) ?? []
        if kind == "instant" { report.clipboardText = pasteboard.string(forType: .string) }
        return report
    }

    /// `TerminalPaste.paste(text)`: whether it went in, and how long after: once the terminal got it; or at once where
    /// the paste says it didn't paste (`false`), for its caller to insert it on one line, as without read access.
    @MainActor
    static func paste(_ text: String) async -> (wentIn: Bool, after: TimeInterval) {
        let start = Date(), before = Issue45Clipboard.terminalGot.count
        let pasted: Any = await TerminalPaste.paste(text)
        if let at = Issue45Clipboard.got(after: before, { $0 == "text:" + text }) { return (true, at.timeIntervalSince(start)) }
        return (pasted as? Bool == false, Date().timeIntervalSince(start))
    }
}
"""#
}
