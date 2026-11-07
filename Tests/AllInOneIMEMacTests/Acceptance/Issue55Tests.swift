import AppKit
import Foundation
import Testing

// Issue #55: a terminal paste in progress goes to another app after ⌘-Tab. Text with line breaks goes into a terminal as
// a paste (`TerminalPaste.paste`): what is on the clipboard is kept, the text written to it, and ⌘V posted once no
// modifier is held (`modifiersUp`). During a multi-line type-out (Type results out), or right after ⏎ on a multi-line
// row (clipboard history) or result, the user presses ⌘-Tab: the paste waits for ⌘ to be let go, and letting it go
// completes the switch. The ⌘V is posted all the same, into the app that is frontmost now (a chat box, a mail, another
// terminal, which may run its line); the input method hears that the terminal's field was left (`deactivateServer`)
// only later. And where the text couldn't be pasted (what is on the clipboard couldn't be kept in time), it goes into
// the terminal's field on one line, also once that field was left. Expected: nothing is pasted once the terminal is no
// longer frontmost or its field was left, and what the user copied is on the clipboard again after.
//
// As Issue54Tests does it: all of Sources/AllInOneIME is compiled into a child process, with the Mac library, the core
// and librime, as the input method is built, and only main.swift's dispatch replaced. The child makes the input
// controller and a terminal's field (Terminal's bundle id; it tells no caret), and puts a two-line text into it as the
// user's action does (the session's `typeOut` output for Type results out, its `commit` output for ⏎ on a row). The
// general pasteboard is a named one of the test's (the Mac's own clipboard is never touched), Paste from Other Apps is
// Allow, Accessibility is granted, and the keys TerminalPaste posts never leave the child. Which app is frontmost is the
// child's to say: `NSWorkspace`'s frontmost (and menu bar owning) app, `NSRunningApplication`'s lookup by process id and
// `isActive`, and the workspace's activation notifications, as macOS tells them on ⌘-Tab: Terminal first, Messages
// once switched to. A ⌘V is read 50 ms later by the app frontmost when it was posted. What the user copied is put on
// the pasteboard by a second process, the app it was copied in (a password manager), which hands its text over when
// read. The child's home is a folder of the test's and its keychain an in-memory one.

@Suite(.serialized)
struct Issue55Tests {
    /// A two-line text being pasted into a terminal (`trigger`), the user switching to another app while the paste
    /// waits (`window`), the input method told the terminal's field was left only after: no ⌘V reaches the app switched
    /// to, and what the user copied is on the clipboard again after.
    @Test(arguments: Issue55Child.Trigger.allCases, [Issue55Child.Window.modifierHeld, .slowCopy])
    func aTerminalPasteUnderWayIsNeverPostedIntoTheAppSwitchedTo(_ trigger: Issue55Child.Trigger, _ window: Issue55Child.Window) throws {
        let report = try Issue55Child.run(trigger, window)
        let when = "\(trigger.title), then \(window.title)"
        #expect(report.switchedBeforePasteKey, "the switch didn't come before the paste's ⌘V (the test missed its moment): \(report)")
        #expect(report.pasteKeysAfterSwitch == 0,
                "\(when): ⌘V was posted once \(Issue55Child.otherApp) was frontmost, which pasted \(report.otherAppGot.map(Issue55Child.Report.shown)): \(report)")
        #expect(!report.otherAppGot.contains(Issue55Child.copied),
                "\(when): \(Issue55Child.otherApp) pasted what the user had copied (\"\(Issue55Child.copied)\"): \(report)")
        #expect(report.clipboardAfter == Issue55Child.copied, "\(when): what the user copied is no longer on the clipboard: \(report)")
    }

    /// ⏎ on a two-line row in a terminal, the user switching to another app while what is on the clipboard is being kept
    /// and its app too slow to hand it over (`TerminalPaste.keepTimeout`): the text can't be pasted, and isn't put on one
    /// line into the terminal's field either, which was left meanwhile.
    @Test func aTextNotPastedIsNeverPutOnOneLineIntoATerminalFieldLeftMeanwhile() throws {
        let report = try Issue55Child.run(.insert, .tooSlowCopy)
        let when = "\(Issue55Child.Trigger.insert.title), then \(Issue55Child.Window.tooSlowCopy.title)"
        #expect(report.switchedBeforePasteKey, "the switch didn't come before the paste's ⌘V (the test missed its moment): \(report)")
        #expect(report.pasteKeys == 0, "\(when): ⌘V was posted: \(report)")
        #expect(report.typedAfterLeft.isEmpty,
                "\(when): the text went into the terminal's field after it was left (\(Issue55Child.Report.shown(report.typedAfterLeft))): \(report)")
        #expect(report.clipboardAfter == Issue55Child.copied, "\(when): what the user copied is no longer on the clipboard: \(report)")
    }

    /// The same paste waiting for ⌘ to be let go, the terminal staying frontmost: it is pasted into the terminal as
    /// before, and what the user copied is on the clipboard again after. (And the harness pastes as the input method
    /// does, so the cases above stop a real paste.)
    @Test(arguments: Issue55Child.Trigger.allCases)
    func aTerminalPasteWaitingForCommandIsPostedWhileTheTerminalStaysFrontmost(_ trigger: Issue55Child.Trigger) throws {
        let report = try Issue55Child.run(trigger, .stay)
        switch trigger {
        case .typeOut:
            #expect(report.typed == Issue55Child.answer.replacingOccurrences(of: "\n", with: ""), "the lines typed: \(report)")
            #expect(report.terminalGot == ["\n"], "the line break pasted: \(report)")
        case .insert:
            #expect(report.typed.isEmpty, "nothing typed: \(report)")
            #expect(report.terminalGot == [Issue55Child.answer], "the text pasted: \(report)")
        }
        #expect(report.otherAppGot.isEmpty, "no other app pasted: \(report)")
        #expect(report.clipboardAfter == Issue55Child.copied, "the clipboard put back: \(report)")
    }
}

enum Issue55Child {
    /// What the user copied (in a password manager).
    static let copied = "SECRET"
    /// A two-line text, as `@question` puts code in, or a row of clipboard history.
    static let answer = "echo one\necho two"
    /// The app ⌘-Tab switches to.
    static let otherApp = "Messages"

    /// How the text goes into the terminal, as the user's action has it.
    enum Trigger: String, CaseIterable, CustomTestStringConvertible, Sendable {
        /// A result typed out (Type results out): its line break pasted (the session's `typeOut` output).
        case typeOut = "type-out"
        /// ⏎ on a two-line row (clipboard history) or result: the text pasted (the session's `commit` output).
        case insert
        var testDescription: String { rawValue }

        var title: String {
            switch self {
            case .typeOut: "a two-line result typed out into a terminal"
            case .insert: "⏎ on a two-line row in a terminal"
            }
        }
    }

    /// Where the paste is when the user switches, and how the switch goes.
    enum Window: String, CaseIterable, CustomTestStringConvertible, Sendable {
        /// ⌘ is held (⌘-Tab): the paste is written and its ⌘V waits for ⌘ to be let go (`modifiersUp`). The switch is
        /// done, ⌘ let go 0.05 seconds later, and the terminal's field told it was left 0.3 seconds after the switch.
        case modifierHeld = "modifier-held"
        /// ⌘-Tab right after: what the user copied is being kept, its app handing it over 0.15 seconds after being
        /// asked. The switch is done then (⌘ already let go), the terminal's field told it was left 0.3 seconds after.
        case slowCopy = "slow-copy"
        /// ⌘-Tab right after, what the user copied being kept, its app handing it over only after 0.6 seconds (longer
        /// than `TerminalPaste.keepTimeout`): the switch done and the terminal's field told it was left at once.
        case tooSlowCopy = "too-slow-copy"
        /// ⌘ is held as in `modifierHeld`, then let go with no switch: the terminal stays frontmost.
        case stay
        var testDescription: String { rawValue }

        var title: String {
            switch self {
            case .modifierHeld: "⌘-Tab to \(Issue55Child.otherApp) while the paste waits for ⌘ to be let go"
            case .slowCopy: "⌘-Tab to \(Issue55Child.otherApp) while what was copied is kept (its app hands it over in 0.15 s)"
            case .tooSlowCopy: "⌘-Tab to \(Issue55Child.otherApp) while what was copied is kept (its app hands it over in 0.6 s)"
            case .stay: "⌘ let go in the terminal"
            }
        }

        /// How long the app the user copied in takes to hand it over.
        var copyDelay: String {
            switch self {
            case .slowCopy: "0.15"
            case .tooSlowCopy: "0.6"
            case .modifierHeld, .stay: "0"
            }
        }
    }

    /// What the child saw.
    struct Report: Decodable, CustomStringConvertible {
        /// Whether the switch (or, staying, ⌘ let go) came before any ⌘V was posted.
        var switchedBeforePasteKey: Bool
        /// The ⌘V posted, and those posted once the other app was frontmost.
        var pasteKeys: Int
        var pasteKeysAfterSwitch: Int
        /// What the terminal, and the other app, read off the clipboard at each ⌘V posted while frontmost (50 ms after).
        var terminalGot: [String]
        var otherAppGot: [String]
        /// What was inserted into the terminal's field (typed), and what of it once the field was left.
        var typed: String
        var typedAfterLeft: String
        /// The clipboard's text once it is all over.
        var clipboardAfter: String?
        var output: String?

        var description: String {
            "switched before ⌘V \(switchedBeforePasteKey), \(pasteKeys) ⌘V (\(pasteKeysAfterSwitch) after the switch), terminal read "
                + "\(terminalGot.map(Self.shown)), \(Issue55Child.otherApp) read \(otherAppGot.map(Self.shown)), typed \(Self.shown(typed)) "
                + "(after the field was left: \(Self.shown(typedAfterLeft))), clipboard after: \(clipboardAfter.map(Self.shown) ?? "no text")"
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

    /// A two-line text put into a terminal by `trigger`, the user switching apps in `window`.
    static func run(_ trigger: Trigger, _ window: Window) throws -> Report {
        let executable = try compiled.get()
        let fm = FileManager.default
        let name = "com.aipinyin.inputmethod.issue55.\(UUID().uuidString)"
        defer { NSPasteboard(name: NSPasteboard.Name(name)).releaseGlobally() }
        // The child's home: never the user's config.
        let home = fm.temporaryDirectory.appendingPathComponent("issue55-home-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home.appendingPathComponent(".config/allinoneime"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let environment = ["CFFIXED_USER_HOME": home.path, "HOME": home.path]

        // The app the copy was made in, on the clipboard until the end.
        let log = fm.temporaryDirectory.appendingPathComponent("issue55-source-\(UUID().uuidString).log")
        fm.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        let source = Process()
        source.executableURL = executable
        source.arguments = ["source", window.copyDelay, name]
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

        let result = try command(executable, [trigger.rawValue, window.rawValue, name, log.path], environment: environment, timeout: 60)
        guard result.status == 0, let line = result.output.split(separator: "\n").last(where: { $0.hasPrefix("REPORT ") }) else {
            throw Failure(description: "the child (\(trigger.rawValue), \(window.rawValue)) failed (\(result.status)):\n\(result.output)")
        }
        var report = try JSONDecoder().decode(Report.self, from: Data(line.dropFirst("REPORT ".count).utf8))
        report.output = result.output.split(separator: "\n").filter { $0.hasPrefix("FAIL") }.joined(separator: "\n")
        if report.output?.isEmpty == true { report.output = nil }
        return report
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("issue55-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        // main.swift as written up to its dispatch, then the harness.
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try (String(main[..<cut.upperBound]) + Issue55Harness.swift).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        let stubs = scratch.appendingPathComponent("Stubs.c"), stubsObject = scratch.appendingPathComponent("Stubs.o")
        try Issue55Harness.stubs.write(to: stubs, atomically: true, encoding: .utf8)
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
        let executable = scratch.appendingPathComponent("issue55")
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
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("issue55-\(UUID().uuidString).log")
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

/// The child's sources: what follows main.swift's `let arguments = …` (the input controller putting a two-line text into
/// a terminal's field, the user switching apps as the scenario says), and C stand-ins for Accessibility, the modifier
/// keys' state, the key tap and posting keys, linked in ahead of the system's. The same executable is the copy's app
/// (`source`).
private enum Issue55Harness {
    static let stubs = #"""
#include <stdint.h>
// Accessibility granted; the keys posted handed to the harness, never posted to the Mac; the modifier keys held as the
// harness says; no key tap made.
unsigned char AXIsProcessTrusted(void) { return 1; }
unsigned char AXIsProcessTrustedWithOptions(const void *options) { return 1; }
static void (*posted)(void *event);
void issue55_on_post(void (*callback)(void *event)) { posted = callback; }
void CGEventPost(uint32_t tap, void *event) { if (posted) posted(event); }
static volatile uint64_t held;
static volatile int64_t reads;
void issue55_hold(uint64_t flags) { held = flags; }
int64_t issue55_flag_reads(void) { return reads; }
uint64_t CGEventSourceFlagsState(int32_t state) { reads += 1; return held; }
void *CGEventTapCreate(uint32_t tap, uint32_t place, uint32_t options, uint64_t mask, void *callback, void *info) { return 0; }
"""#

    static let swift = #"""

// MARK: - Issue #55's child (in place of main.swift's dispatch)

@_silgen_name("issue55_on_post") func issue55OnPost(_ callback: @convention(c) (UnsafeMutableRawPointer?) -> Void)
@_silgen_name("issue55_hold") func issue55Hold(_ flags: UInt64)
@_silgen_name("issue55_flag_reads") func issue55FlagReads() -> Int64

let issue55Copied = "SECRET"

// Ended by SIGTERM as any program is (main.swift ignores it, for the source `runServer` resumes): the test stops the
// copy's app so, and the child once it times out.
signal(SIGTERM, SIG_DFL)

if arguments.first == "source" {
    // The app the user copied in (a password manager): its text handed over when read, `delay` seconds after being asked.
    final class Issue55Source: NSObject, NSPasteboardItemDataProvider {
        let delay: TimeInterval
        init(delay: TimeInterval) { self.delay = delay }

        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
            print("ASKED \(type.rawValue)")
            fflush(stdout)
            Thread.sleep(forTimeInterval: delay)
            item.setString(issue55Copied, forType: type)
        }
    }
    guard arguments.count == 3 else { exit(2) }
    let source = Issue55Source(delay: Double(arguments[1]) ?? 0)
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
final class Issue55Terminal: NSObject, IMKTextInput {
    var typed = ""
    /// Whether the input method was told the field was left (`deactivateServer`), and what went in after.
    var left = false
    var typedAfterLeft = ""

    func insertText(_ string: Any!, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? string as? String ?? ""
        typed += text
        if left { typedAfterLeft += text }
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
    func uniqueClientIdentifierString() -> String! { "issue55-terminal" }
    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! { nil }
    func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect { NSRect(x: 420, y: 560, width: 1, height: 18) }
}

/// An app as macOS tells it to the input method: Terminal, the one being typed into, and Messages, the one ⌘-Tab
/// switches to. Active while frontmost (`Issue55Apps.front`).
final class Issue55App: NSRunningApplication {
    let pid: pid_t
    let id: String
    let name: String

    init(pid: pid_t, id: String, name: String) {
        self.pid = pid
        self.id = id
        self.name = name
        super.init()
    }

    override var processIdentifier: pid_t { pid }
    override var bundleIdentifier: String? { id }
    override var localizedName: String? { name }
    override var isActive: Bool { Issue55Apps.front === self }
    override var ownsMenuBar: Bool { isActive }
    override var isTerminated: Bool { false }
    override var isFinishedLaunching: Bool { true }
    override var isHidden: Bool { false }
    override var activationPolicy: NSApplication.ActivationPolicy { .regular }
}

/// Which app is frontmost, as `NSWorkspace` and `NSRunningApplication` tell it here, and the switch ⌘-Tab makes.
enum Issue55Apps {
    static let terminal = Issue55App(pid: 99_955, id: "com.apple.Terminal", name: "Terminal")
    static let messages = Issue55App(pid: 99_956, id: "com.apple.MobileSMS", name: "Messages")
    nonisolated(unsafe) static var front: Issue55App = terminal

    static func install() {
        let frontmost: @convention(block) (AnyObject) -> NSRunningApplication? = { _ in Issue55Apps.front }
        for name in ["frontmostApplication", "menuBarOwningApplication"] {
            if let method = class_getInstanceMethod(NSWorkspace.self, NSSelectorFromString(name)) {
                method_setImplementation(method, imp_implementationWithBlock(frontmost))
            }
        }
        // Looked up by process id: ours; any other as macOS has it.
        let lookupName = NSSelectorFromString("runningApplicationWithProcessIdentifier:")
        if let lookup = class_getClassMethod(NSRunningApplication.self, lookupName) {
            typealias Lookup = @convention(c) (AnyObject, Selector, pid_t) -> NSRunningApplication?
            let original = unsafeBitCast(method_getImplementation(lookup), to: Lookup.self)
            let block: @convention(block) (AnyObject, pid_t) -> NSRunningApplication? = { type, pid in
                [Issue55Apps.terminal, Issue55Apps.messages].first { $0.pid == pid } ?? original(type, lookupName, pid)
            }
            method_setImplementation(lookup, imp_implementationWithBlock(block))
        }
    }

    /// ⌘-Tab done: Messages frontmost, Terminal deactivated, as the workspace tells it.
    static func switchToMessages() {
        let old = front
        front = messages
        let center = NSWorkspace.shared.notificationCenter
        center.post(name: NSWorkspace.didDeactivateApplicationNotification, object: NSWorkspace.shared,
                    userInfo: [NSWorkspace.applicationUserInfoKey: old])
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: NSWorkspace.shared,
                    userInfo: [NSWorkspace.applicationUserInfoKey: messages])
    }
}

/// The general pasteboard, the test's named one; Paste from Other Apps: Allow; the app frontmost when a ⌘V is posted
/// reading it 50 ms later (it takes the key, then reads).
@MainActor
enum Issue55Clipboard {
    static var pasteboard: NSPasteboard!
    static var pasteKeys = 0
    static var pasteKeysAfterSwitch = 0
    static var terminalGot: [String] = []
    static var otherAppGot: [String] = []

    static func install(_ name: String) {
        pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
        let general = class_getClassMethod(NSPasteboard.self, NSSelectorFromString("generalPasteboard"))!
        let generalBlock: @convention(block) (AnyObject) -> NSPasteboard = { _ in MainActor.assumeIsolated { Issue55Clipboard.pasteboard } }
        method_setImplementation(general, imp_implementationWithBlock(generalBlock))
        // `NSPasteboard.AccessBehavior.alwaysAllow` (macOS 15.4; before it, reading never asks).
        if let access = class_getInstanceMethod(NSPasteboard.self, NSSelectorFromString("accessBehavior")) {
            let accessBlock: @convention(block) (AnyObject) -> Int = { _ in 2 }
            method_setImplementation(access, imp_implementationWithBlock(accessBlock))
        }
        issue55OnPost { pointer in
            guard let pointer else { return }
            let event = Unmanaged<CGEvent>.fromOpaque(pointer).takeUnretainedValue()
            guard event.type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 9 else { return }  // V
            MainActor.assumeIsolated {
                let into = Issue55Apps.front
                Issue55Clipboard.pasteKeys += 1
                if into !== Issue55Apps.terminal { Issue55Clipboard.pasteKeysAfterSwitch += 1 }
                // The app frontmost takes the paste.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    MainActor.assumeIsolated {
                        let read = Issue55Clipboard.pasteboard.string(forType: .string) ?? ""
                        if into === Issue55Apps.terminal {
                            Issue55Clipboard.terminalGot.append(read)
                        } else {
                            Issue55Clipboard.otherAppGot.append(read)
                        }
                    }
                }
            }
        }
    }

    /// Whether a paste of ours is on the clipboard (`TerminalPaste.write` marks it transient).
    static var written: Bool {
        pasteboard.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) == true
    }
}

struct Issue55Report: Encodable {
    var switchedBeforePasteKey = false
    var pasteKeys = 0
    var pasteKeysAfterSwitch = 0
    var terminalGot: [String] = []
    var otherAppGot: [String] = []
    var typed = ""
    var typedAfterLeft = ""
    var clipboardAfter: String?
}

@MainActor
enum Issue55Child {
    static let trigger = arguments.count > 0 ? arguments[0] : ""
    static let window = arguments.count > 1 ? arguments[1] : ""
    static let name = arguments.count > 2 ? arguments[2] : ""
    static let sourceLog = arguments.count > 3 ? arguments[3] : ""
    static let answer = "echo one\necho two"
    static let firstLine = "echo one"
    static let command: UInt64 = 0x100000  // ⌘ (kCGEventFlagMaskCommand)

    static var controller: AllInOneIMEInputController!
    static let terminal = Issue55Terminal()
    static var report = Issue55Report()
    static var askedBefore = 0
    static var readsBefore: Int64 = 0

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
        Issue55Apps.install()
        Issue55Clipboard.install(name)
        guard let made = AllInOneIMEInputController(server: nil, delegate: nil, client: nil) else {
            say("FAIL no input controller")
            exit(3)
        }
        controller = made
        controller.clientOverride = terminal
        if window == "modifier-held" || window == "stay" { issue55Hold(command) }  // ⌘ down: ⌘-Tab on its way
        askedBefore = asked()
        readsBefore = issue55FlagReads()
        switch trigger {
        case "type-out":
            // A result answered with Type results out on: typed into the terminal, its line break pasted.
            controller.apply([.typeOut(answer)], client: terminal)
        case "insert":
            // ⏎ on a two-line row: the text goes in, pasted.
            controller.apply([.commit(answer)], client: terminal)
        default:
            say("FAIL unknown trigger \(trigger)")
            exit(2)
        }
        waitForPaste(until: Date().addingTimeInterval(20))
    }

    /// Until the paste waits: for ⌘ to be let go (written, the modifier keys asked), or for what was copied to be kept
    /// (its app asked for it); typing out, once the first line is typed.
    static func waitForPaste(until deadline: Date) {
        let lineTyped = trigger == "insert" || terminal.typed == firstLine
        let waiting: Bool
        switch window {
        case "modifier-held", "stay": waiting = lineTyped && Issue55Clipboard.written && issue55FlagReads() > readsBefore
        case "slow-copy", "too-slow-copy": waiting = lineTyped && asked() > askedBefore
        default:
            say("FAIL unknown window \(window)")
            exit(2)
        }
        if waiting {
            switchApps()
            return
        }
        guard Date() < deadline else {
            say("FAIL the paste never waited: typed \"\(terminal.typed)\", \(Issue55Clipboard.pasteKeys) ⌘V")
            exit(3)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.002) { MainActor.assumeIsolated { waitForPaste(until: deadline) } }
    }

    /// The input method told the terminal's field was left, as macOS tells it once another app has the focus.
    static func leaveField() {
        terminal.left = true
        controller.deactivateServer(terminal)
    }

    /// ⌘-Tab to Messages as the window has it (or ⌘ let go in the terminal); what happened told once it's all over.
    static func switchApps() {
        report.switchedBeforePasteKey = Issue55Clipboard.pasteKeys == 0
        switch window {
        case "modifier-held":
            Issue55Apps.switchToMessages()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { issue55Hold(0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { leaveField() } }
        case "slow-copy":
            Issue55Apps.switchToMessages()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { leaveField() } }
        case "too-slow-copy":
            Issue55Apps.switchToMessages()
            leaveField()
        case "stay":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { issue55Hold(0) }
        default:
            break
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            MainActor.assumeIsolated {
                report.pasteKeys = Issue55Clipboard.pasteKeys
                report.pasteKeysAfterSwitch = Issue55Clipboard.pasteKeysAfterSwitch
                report.terminalGot = Issue55Clipboard.terminalGot
                report.otherAppGot = Issue55Clipboard.otherAppGot
                report.typed = terminal.typed
                report.typedAfterLeft = terminal.typedAfterLeft
                report.clipboardAfter = Issue55Clipboard.pasteboard.string(forType: .string)
                say("REPORT " + String(decoding: try! JSONEncoder().encode(report), as: UTF8.self))
                exit(0)
            }
        }
    }
}

// The input method's main thread: the app, as `runServer` has it (no IMKServer, nothing else started).
let issue55App = NSApplication.shared
issue55App.setActivationPolicy(.accessory)
DispatchQueue.main.async { MainActor.assumeIsolated { Issue55Child.start() } }
issue55App.run()
exit(0)
"""#
}
