import AppKit
import Foundation
import Testing

// Issue #54: stopping a terminal type-out can paste the user's previous clipboard. With Type results out on, a
// multi-line result typed into a terminal has each line break pasted (`TerminalPaste.paste`), awaited inside the typing
// task. When typing stops (Esc or another key, the field left, a click elsewhere in the terminal, another result typed
// out) the task is cancelled, and every `try? await Task.sleep` of the paste under way returns at once: the wait for
// the modifier keys to be let go, and the wait for the terminal to read the clipboard. The ⌘V is posted all the same,
// and what the user had copied (a password, a token) is put back on the clipboard right after it, before the terminal
// reads: the terminal pastes that. Expected: the put-back waits for the terminal to read, whether or not typing was
// stopped; or a stopped paste posts no ⌘V at all. Either way the terminal never gets what the user copied, and the
// user's copy is on the clipboard again after.
//
// The input method's own code can't be imported here (it is an executable target): as Issue40Tests does it, all of
// Sources/AllInOneIME is compiled into a child process, with the Mac library, the core and librime, as the input method
// is built. Only main.swift's dispatch (what follows `let arguments = …`) is replaced: the child makes the input
// controller and a terminal's field (Terminal's bundle id; it tells no caret, as a terminal), has a two-line result
// typed out into it (the session's `typeOut` output, as Type results out answers a result), and stops it as the user
// does, while the first line break's paste is under way: between what is on the clipboard being kept and the ⌘V. As in
// Issue45Tests, the general pasteboard is a named one of the test's (the Mac's own clipboard is never touched), Paste
// from Other Apps is Allow, Accessibility is granted, and the keys TerminalPaste posts never leave the child; no key tap
// is made. A ⌘V has the terminal read the clipboard 50 ms later (it takes the key, then reads; later still when busy
// with output). What the user copied is put on that pasteboard by a second process, the app it was copied in (a
// password manager), which hands its text over when it is read. The child's home is a folder of the test's and its
// keychain an in-memory one: nothing reads the user's config or keychain.

@Suite(.serialized)
struct Issue54Tests {
    /// A two-line result being typed out into a terminal, stopped (`stop`) while its line break's paste waits (`window`):
    /// the terminal never reads what the user copied (it reads the line break, or no ⌘V comes), and what the user copied
    /// is on the clipboard again after.
    @Test(arguments: Issue54Child.Window.allCases, Issue54Child.Stop.allCases)
    func stoppingATypeOutMidPasteNeverPastesWhatTheUserCopied(_ window: Issue54Child.Window, _ stop: Issue54Child.Stop) throws {
        let report = try Issue54Child.run(stop, window)
        let when = "\(stop.title) while \(window.title)"
        #expect(report.stoppedBeforePasteKey, "the typing wasn't stopped before the line break's ⌘V (the test missed its moment): \(report)")
        #expect(!report.terminalGot.contains(Issue54Child.copied),
                "\(when): the terminal pasted what the user had copied (\"\(Issue54Child.copied)\"), put back before it read: \(report)")
        #expect(report.terminalGot.allSatisfy { $0 == "\n" },
                "\(when): the terminal read something other than the line break being pasted: \(report)")
        #expect(report.clipboardAfter == Issue54Child.copied, "\(when): what the user copied is no longer on the clipboard: \(report)")
    }

    /// The same result left to finish: its line break is pasted, the terminal reads it, and what the user copied is on
    /// the clipboard again after. (And the harness pastes as the input method does, so the cases above stop a real paste.)
    @Test func aTypeOutLeftToFinishPastesItsLineBreakAndPutsTheClipboardBack() throws {
        let report = try Issue54Child.run(nil, nil)
        #expect(report.typed == Issue54Child.answer.replacingOccurrences(of: "\n", with: ""), "the lines typed: \(report)")
        #expect(report.terminalGot == ["\n"], "the line break pasted: \(report)")
        #expect(report.clipboardAfter == Issue54Child.copied, "the clipboard put back: \(report)")
    }
}

enum Issue54Child {
    /// What the user copied (in a password manager).
    static let copied = "SECRET"
    /// A two-line result, as `@question` puts code in.
    static let answer = "echo one\necho two"

    /// How typing is stopped, as the user stops it.
    enum Stop: String, CaseIterable, CustomTestStringConvertible, Sendable {
        /// Another field takes the focus (⌘Tab to another app, a click in another window): `deactivateServer`.
        case focusLeft = "focus-left"
        /// A click elsewhere in the terminal: the app wants everything in now (`commitComposition`).
        case click
        /// Another result typed out (the session's `typeOut` output again).
        case newResult = "new-result"
        /// Esc, handed over by the terminal as a key.
        case escape
        var testDescription: String { rawValue }

        var title: String {
            switch self {
            case .focusLeft: "the field left"
            case .click: "a click elsewhere in the terminal"
            case .newResult: "another result typed out"
            case .escape: "Esc"
            }
        }
    }

    /// Where the line break's paste is when typing is stopped: after what is on the clipboard is being kept, before ⌘V.
    enum Window: String, CaseIterable, CustomTestStringConvertible, Sendable {
        /// ⌘ is held (⌘Tab on its way): the paste is written and its ⌘V waits for ⌘ to be let go (`modifiersUp`), which
        /// it is 0.3 seconds after the stop.
        case modifierHeld = "modifier-held"
        /// What the user copied is handed over by its app when read, 0.15 seconds after being asked: the paste waits
        /// for it to be kept (well within `TerminalPaste.keepTimeout`).
        case slowCopy = "slow-copy"
        var testDescription: String { rawValue }

        var title: String {
            switch self {
            case .modifierHeld: "⌘ is held (the ⌘V waits for it)"
            case .slowCopy: "what was copied is being kept (its app hands it over 0.15 s after being asked)"
            }
        }
    }

    /// What the child saw.
    struct Report: Decodable, CustomStringConvertible {
        /// Whether typing was stopped before any ⌘V was posted.
        var stoppedBeforePasteKey: Bool
        /// The ⌘V posted.
        var pasteKeys: Int
        /// What the terminal read off the clipboard at each ⌘V (50 ms after it).
        var terminalGot: [String]
        /// What was inserted into the terminal's field (typed).
        var typed: String
        /// The clipboard's text once it is all over.
        var clipboardAfter: String?
        var output: String?

        var description: String {
            "stopped before ⌘V \(stoppedBeforePasteKey), \(pasteKeys) ⌘V, terminal read \(terminalGot.map(Self.shown)), typed "
                + "\(Self.shown(typed)), clipboard after: \(clipboardAfter.map(Self.shown) ?? "no text")"
                + (output.map { "\n\($0)" } ?? "")
        }

        static func shown(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\n", with: "\\n") + "\"" }
    }

    struct Failure: Error, CustomStringConvertible { var description: String }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    static var thirdParty: URL {
        ProcessInfo.processInfo.environment["ALLINONEIME_THIRDPARTY"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("ThirdParty")
    }

    /// A two-line result typed out into a terminal and stopped by `stop` in `window` (nil: left to finish).
    static func run(_ stop: Stop?, _ window: Window?) throws -> Report {
        let executable = try compiled.get()
        let fm = FileManager.default
        let name = "com.allinoneime.inputmethod.issue54.\(UUID().uuidString)"
        defer { NSPasteboard(name: NSPasteboard.Name(name)).releaseGlobally() }
        // The child's home: never the user's config.
        let home = fm.temporaryDirectory.appendingPathComponent("issue54-home-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home.appendingPathComponent(".config/allinoneime"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let environment = ["CFFIXED_USER_HOME": home.path, "HOME": home.path]

        // The app the copy was made in, on the clipboard until the end.
        let log = fm.temporaryDirectory.appendingPathComponent("issue54-source-\(UUID().uuidString).log")
        fm.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        let source = Process()
        source.executableURL = executable
        source.arguments = ["source", window == .slowCopy ? "0.15" : "0", name]
        source.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        source.standardOutput = handle
        source.standardError = handle
        try source.run()
        defer {
            if source.isRunning { source.terminate() }
            let stopped = Date().addingTimeInterval(2)
            while source.isRunning && Date() < stopped { Thread.sleep(forTimeInterval: 0.02) }
            if source.isRunning { kill(source.processIdentifier, SIGKILL) }
            source.waitUntilExit()
            try? handle.close()
            try? fm.removeItem(at: log)
        }
        let sourceLog = { (try? String(contentsOf: log, encoding: .utf8)) ?? "" }
        let ready = Date().addingTimeInterval(20)
        while !sourceLog().contains("READY") && source.isRunning && Date() < ready { Thread.sleep(forTimeInterval: 0.02) }
        guard sourceLog().contains("READY") else { throw Failure(description: "the copy's app never put it on the clipboard:\n\(sourceLog())") }

        let result = try command(executable, [stop?.rawValue ?? "none", window?.rawValue ?? "none", name, log.path],
                                 environment: environment, timeout: 60)
        guard result.status == 0, let line = result.output.split(separator: "\n").last(where: { $0.hasPrefix("REPORT ") }) else {
            throw Failure(description: "the child (\(stop?.rawValue ?? "none"), \(window?.rawValue ?? "none")) failed (\(result.status)):\n\(result.output)")
        }
        var report = try JSONDecoder().decode(Report.self, from: Data(line.dropFirst("REPORT ".count).utf8))
        report.output = result.output.split(separator: "\n").filter { $0.hasPrefix("FAIL") }.joined(separator: "\n")
        if report.output?.isEmpty == true { report.output = nil }
        return report
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("issue54-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        // main.swift as written up to its dispatch, then the harness.
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try (String(main[..<cut.upperBound]) + Issue54Harness.swift).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        let stubs = scratch.appendingPathComponent("Stubs.c"), stubsObject = scratch.appendingPathComponent("Stubs.o")
        try Issue54Harness.stubs.write(to: stubs, atomically: true, encoding: .utf8)
        let clang = try command(URL(fileURLWithPath: "/usr/bin/xcrun"), ["clang", "-c", stubs.path, "-o", stubsObject.path], timeout: 60)
        guard clang.status == 0 else { throw Failure(description: clang.output) }
        // The Mac library, the core and librime's wrapper, as `swift test` built them.
        let products = repository.appendingPathComponent(".build/debug")
        let modules = fm.fileExists(atPath: products.appendingPathComponent("Modules").path)
            ? products.appendingPathComponent("Modules") : products
        var objects: [String] = []
        for module in ["AllInOneIMEMac", "AllInOneIMECore", "AllInOneIMERime", "AllInOneIMEText", "AllInOneIMEScriptEngine",
                       "CQuickJS", "Crypto"] {
            let aggregate = products.appendingPathComponent(module + ".o")
            if fm.fileExists(atPath: aggregate.path) {
                objects.append(aggregate.path)
            } else if let files = try? fm.contentsOfDirectory(at: products.appendingPathComponent(module + ".build"), includingPropertiesForKeys: nil) {
                objects += files.filter { $0.pathExtension == "o" }.map(\.path)
            }
        }
        let rimeLib = thirdParty.appendingPathComponent("librime/dist/lib")
        let executable = scratch.appendingPathComponent("issue54")
        let arguments = ["swiftc", "-swift-version", "5", "-j", "\(max(2, ProcessInfo.processInfo.activeProcessorCount))",
                         "-I", modules.path, "-I", repository.appendingPathComponent("Core/Sources/CRime").path,
                         "-L", rimeLib.path, "-lrime", "-Xlinker", "-rpath", "-Xlinker", rimeLib.path,
                         "-framework", "AppKit", "-framework", "InputMethodKit", "-framework", "Carbon", "-framework", "AVFoundation",
                         "-framework", "Speech", "-framework", "EventKit", "-framework", "SwiftUI",
                         "-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels",
                         mainFile.path] + others + [stubsObject.path] + objects + ["-o", executable.path]
        let swift = try command(URL(fileURLWithPath: "/usr/bin/xcrun"), arguments, timeout: 900)
        guard swift.status == 0 else { throw Failure(description: "compiling Sources/AllInOneIME with the harness:\n\(swift.output)") }
        return executable
    }

    private static func command(_ executable: URL, _ arguments: [String], environment: [String: String] = [:],
                                timeout: TimeInterval) throws -> (status: Int32, output: String) {
        // A file, not a pipe: a long compiler output never blocks the child.
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("issue54-\(UUID().uuidString).log")
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

/// The child's sources: what follows main.swift's `let arguments = …` (the input controller typing a result out into a
/// terminal's field, stopped as the scenario says), and C stand-ins for Accessibility, the modifier keys' state, the key
/// tap and posting keys, linked in ahead of the system's. The same executable is the copy's app (`source`).
private enum Issue54Harness {
    static let stubs = #"""
#include <stdint.h>
// Accessibility granted, as the issue's trigger has it; the keys posted handed to the harness, never posted to the Mac;
// the modifier keys held as the harness says; no key tap made.
unsigned char AXIsProcessTrusted(void) { return 1; }
unsigned char AXIsProcessTrustedWithOptions(const void *options) { return 1; }
static void (*posted)(void *event);
void issue54_on_post(void (*callback)(void *event)) { posted = callback; }
void CGEventPost(uint32_t tap, void *event) { if (posted) posted(event); }
static volatile uint64_t held;
static volatile int64_t reads;
void issue54_hold(uint64_t flags) { held = flags; }
int64_t issue54_flag_reads(void) { return reads; }
uint64_t CGEventSourceFlagsState(int32_t state) { reads += 1; return held; }
void *CGEventTapCreate(uint32_t tap, uint32_t place, uint32_t options, uint64_t mask, void *callback, void *info) { return 0; }
"""#

    static let swift = #"""

// MARK: - Issue #54's child (in place of main.swift's dispatch)

@_silgen_name("issue54_on_post") func issue54OnPost(_ callback: @convention(c) (UnsafeMutableRawPointer?) -> Void)
@_silgen_name("issue54_hold") func issue54Hold(_ flags: UInt64)
@_silgen_name("issue54_flag_reads") func issue54FlagReads() -> Int64

let issue54Copied = "SECRET"

// Ended by SIGTERM as any program is (main.swift ignores it, for the source `runServer` resumes): the test stops the
// copy's app so, and the child once it times out.
signal(SIGTERM, SIG_DFL)

if arguments.first == "source" {
    // The app the user copied in (a password manager): its text handed over when read, `delay` seconds after being asked.
    final class Issue54Source: NSObject, NSPasteboardItemDataProvider {
        let delay: TimeInterval
        init(delay: TimeInterval) { self.delay = delay }

        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
            print("ASKED \(type.rawValue)")
            fflush(stdout)
            Thread.sleep(forTimeInterval: delay)
            item.setString(issue54Copied, forType: type)
        }
    }
    guard arguments.count == 3 else { exit(2) }
    let source = Issue54Source(delay: Double(arguments[1]) ?? 0)
    let pasteboard = NSPasteboard(name: NSPasteboard.Name(arguments[2]))
    pasteboard.clearContents()
    let item = NSPasteboardItem()
    item.setDataProvider(source, forTypes: [.string])
    pasteboard.writeObjects([item])
    print("READY")
    fflush(stdout)
    // Never outlives the test for long, should it end without stopping this.
    DispatchQueue.main.asyncAfter(deadline: .now() + 120) { exit(0) }
    withExtendedLifetime(source) { RunLoop.main.run() }
    exit(0)
}

// Never the user's keychain.
Platform.current.secrets = .inMemory()

/// A terminal's text field (Terminal), as the input method sees it: it takes what is inserted, and tells no caret.
final class Issue54Terminal: NSObject, IMKTextInput {
    var typed = ""

    func insertText(_ string: Any!, replacementRange: NSRange) {
        typed += (string as? NSAttributedString)?.string ?? string as? String ?? ""
    }
    func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {}
    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: NSNotFound) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func attributedSubstring(from range: NSRange) -> NSAttributedString! { nil }
    func length() -> Int { 0 }
    func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode,
                        inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { NSNotFound }
    func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! {
        lineRect?.pointee = NSRect(x: 420, y: 560, width: 1, height: 18)
        return [:]
    }
    func validAttributesForMarkedText() -> [Any]! { [] }
    func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
    func selectMode(_ modeIdentifier: String!) {}
    func supportsUnicode() -> Bool { true }
    func bundleIdentifier() -> String! { "com.apple.Terminal" }
    func windowLevel() -> CGWindowLevel { CGWindowLevelForKey(.normalWindow) }
    func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String! { "issue54-terminal" }
    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! { nil }
    func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect { NSRect(x: 420, y: 560, width: 1, height: 18) }
}

/// The general pasteboard, the test's named one; Paste from Other Apps: Allow; the terminal reading it 50 ms after each
/// ⌘V reaches it (it takes the key, then reads).
@MainActor
enum Issue54Clipboard {
    static var pasteboard: NSPasteboard!
    static var pasteKeys = 0
    static var terminalGot: [String] = []

    static func install(_ name: String) {
        pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
        let general = class_getClassMethod(NSPasteboard.self, NSSelectorFromString("generalPasteboard"))!
        let generalBlock: @convention(block) (AnyObject) -> NSPasteboard = { _ in MainActor.assumeIsolated { Issue54Clipboard.pasteboard } }
        method_setImplementation(general, imp_implementationWithBlock(generalBlock))
        // `NSPasteboard.AccessBehavior.alwaysAllow` (macOS 15.4; before it, reading never asks).
        if let access = class_getInstanceMethod(NSPasteboard.self, NSSelectorFromString("accessBehavior")) {
            let accessBlock: @convention(block) (AnyObject) -> Int = { _ in 2 }
            method_setImplementation(access, imp_implementationWithBlock(accessBlock))
        }
        issue54OnPost { pointer in
            guard let pointer else { return }
            let event = Unmanaged<CGEvent>.fromOpaque(pointer).takeUnretainedValue()
            guard event.type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 9 else { return }  // V
            MainActor.assumeIsolated {
                Issue54Clipboard.pasteKeys += 1
                // The terminal takes the paste.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    MainActor.assumeIsolated {
                        Issue54Clipboard.terminalGot.append(Issue54Clipboard.pasteboard.string(forType: .string) ?? "")
                    }
                }
            }
        }
    }
}

struct Issue54Report: Encodable {
    var stoppedBeforePasteKey = false
    var pasteKeys = 0
    var terminalGot: [String] = []
    var typed = ""
    var clipboardAfter: String?
}

@MainActor
enum Issue54Child {
    static let stop = arguments.count > 0 ? arguments[0] : ""
    static let window = arguments.count > 1 ? arguments[1] : ""
    static let name = arguments.count > 2 ? arguments[2] : ""
    static let sourceLog = arguments.count > 3 ? arguments[3] : ""
    static let answer = "echo one\necho two"
    static let firstLine = "echo one"
    static let command: UInt64 = 0x100000  // ⌘ (kCGEventFlagMaskCommand)

    static var controller: AllInOneIMEInputController!
    static let terminal = Issue54Terminal()
    static var report = Issue54Report()
    static var askedBefore = 0

    static func say(_ line: String) {
        print(line)
        fflush(stdout)
    }

    static func asked() -> Int {
        ((try? String(contentsOfFile: sourceLog, encoding: .utf8)) ?? "").components(separatedBy: "ASKED ").count - 1
    }

    static func start() {
        // Never the user's config: the test's home.
        let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
        guard !home.isEmpty, Config.defaultURL.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path) else {
            say("FAIL the config file isn't in the test's home: \(Config.defaultURL.path)")
            exit(3)
        }
        Issue54Clipboard.install(name)
        guard let made = AllInOneIMEInputController(server: nil, delegate: nil, client: nil) else {
            say("FAIL no input controller")
            exit(3)
        }
        controller = made
        controller.clientOverride = terminal
        if window == "modifier-held" { issue54Hold(command) }
        askedBefore = asked()
        // A result answered with Type results out on: typed into the terminal, its line break pasted.
        controller.apply([.typeOut(answer)], client: terminal)
        waitForPaste(until: Date().addingTimeInterval(20))
    }

    /// Until the first line is typed and its line break's paste waits: for ⌘ to be let go (the modifier keys asked), or
    /// for what was copied to be kept (its app asked for it); left to finish, until it's all typed.
    static func waitForPaste(until deadline: Date) {
        let waiting: Bool
        switch window {
        case "modifier-held": waiting = terminal.typed == firstLine && issue54FlagReads() > 0
        case "slow-copy": waiting = terminal.typed == firstLine && asked() > askedBefore
        case "none": waiting = terminal.typed == answer.replacingOccurrences(of: "\n", with: "")
        default:
            say("FAIL unknown window \(window)")
            exit(2)
        }
        if waiting {
            stopTyping()
            return
        }
        guard Date() < deadline else {
            say("FAIL the line break was never pasted: typed \"\(terminal.typed)\", \(Issue54Clipboard.pasteKeys) ⌘V")
            exit(3)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.002) { MainActor.assumeIsolated { waitForPaste(until: deadline) } }
    }

    /// Typing stopped as the user stops it, ⌘ let go 0.3 seconds later; what happened told once it's all over.
    static func stopTyping() {
        report.stoppedBeforePasteKey = Issue54Clipboard.pasteKeys == 0
        switch stop {
        case "focus-left":
            controller.deactivateServer(terminal)
        case "click":
            controller.commitComposition(terminal)
        case "new-result":
            controller.apply([.typeOut("pwd")], client: terminal)
        case "escape":
            let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                          isARepeat: false, keyCode: 53)!
            _ = controller.handle(escape, client: terminal)
        case "none":
            break
        default:
            say("FAIL unknown stop \(stop)")
            exit(2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { issue54Hold(0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            MainActor.assumeIsolated {
                report.pasteKeys = Issue54Clipboard.pasteKeys
                report.terminalGot = Issue54Clipboard.terminalGot
                report.typed = terminal.typed
                report.clipboardAfter = Issue54Clipboard.pasteboard.string(forType: .string)
                say("REPORT " + String(decoding: try! JSONEncoder().encode(report), as: UTF8.self))
                exit(0)
            }
        }
    }
}

// The input method's main thread: the app, as `runServer` has it (no IMKServer, nothing else started).
let issue54App = NSApplication.shared
issue54App.setActivationPolicy(.accessory)
DispatchQueue.main.async { MainActor.assumeIsolated { Issue54Child.start() } }
issue54App.run()
exit(0)
"""#
}
