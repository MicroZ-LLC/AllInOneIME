import AppKit
import Foundation
import Testing

// Stopping a terminal type-out of three lines or more (#54, after its acceptance tests' two): a key or a click puts the
// rest of the answer in at once, and the rest has line breaks of its own, so it is pasted (`insert`), in a task of its
// own, while the stopped line break's paste may still be keeping what is on the clipboard. Should the stopped one then
// write the clipboard, it takes the rest's paste over and puts the user's copy back at once, before the terminal reads
// the rest's ⌘V: the terminal pastes what the user copied. A stopped paste never touches the clipboard
// (`TerminalPaste.write`).
//
// As Issue54Tests (Acceptance) does it: all of Sources/AllInOneIME compiled into a child process with main.swift's
// dispatch replaced, a named pasteboard of the test's as the general one, Paste from Other Apps Allow, Accessibility
// granted, the keys posted kept in the child, and the terminal reading the clipboard 50 ms after each ⌘V. What the user
// copied is put on that pasteboard by a second process, which hands it over 0.15 seconds after being asked, and copies
// it anew for each round. Which of the two pastes is done keeping it first varies, so each stop is tried a few rounds.

@Suite(.serialized)
struct TerminalPasteStopTests {
    /// A three-line answer typed out into a terminal, stopped by a key or a click while its first line break's paste is
    /// keeping what the user copied: the terminal never reads that, it reads the rest of the answer, line breaks and all,
    /// and what the user copied is on the clipboard again after.
    @Test(arguments: TerminalPasteStopChild.Stop.allCases)
    func stoppingALongerTypeOutWhileTheClipboardIsKeptNeverPastesWhatTheUserCopied(_ stop: TerminalPasteStopChild.Stop) throws {
        let rounds = try TerminalPasteStopChild.run(stop)
        #expect(rounds.count == TerminalPasteStopChild.rounds, "the rounds: \(rounds)")
        for (index, round) in rounds.enumerated() {
            let which = "\(stop.rawValue), round \(index + 1)"
            #expect(round.stoppedBeforePasteKey, "\(which): typing wasn't stopped before the first ⌘V (the test missed its moment): \(round)")
            #expect(!round.terminalGot.contains(TerminalPasteStopChild.copied), "\(which): the terminal pasted what the user had copied: \(round)")
            #expect(round.terminalGot.allSatisfy { $0 == TerminalPasteStopChild.rest }, "\(which): the terminal read something else than the rest: \(round)")
            #expect(round.clipboardAfter == TerminalPasteStopChild.copied, "\(which): what the user copied is no longer on the clipboard: \(round)")
        }
    }
}

enum TerminalPasteStopChild {
    static let copied = "SECRET"
    /// The rest of `answer` once its first line is typed (the line break being pasted then is left out).
    static let rest = "echo two\necho three"
    static let rounds = 8

    /// A stop that puts the rest in at once.
    enum Stop: String, CaseIterable, CustomTestStringConvertible, Sendable {
        /// A letter key, handed over by the terminal.
        case key
        /// A click elsewhere in the terminal (`commitComposition`).
        case click
        var testDescription: String { rawValue }
    }

    /// What the child saw in a round.
    struct Round: Decodable, CustomStringConvertible {
        var stoppedBeforePasteKey: Bool
        var pasteKeys: Int
        var terminalGot: [String]
        var typed: String
        var clipboardAfter: String?

        var description: String {
            "stopped before ⌘V \(stoppedBeforePasteKey), \(pasteKeys) ⌘V, terminal read \(terminalGot.map(Self.shown)), typed "
                + "\(Self.shown(typed)), clipboard after: \(clipboardAfter.map(Self.shown) ?? "no text")"
        }

        static func shown(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\n", with: "\\n") + "\"" }
    }

    struct Failure: Error, CustomStringConvertible { var description: String }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    static var thirdParty: URL {
        ProcessInfo.processInfo.environment["ALLINONEIME_THIRDPARTY"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("ThirdParty")
    }

    /// `rounds` of the answer typed out and stopped by `stop`, in one child.
    static func run(_ stop: Stop) throws -> [Round] {
        let executable = try compiled.get()
        let fm = FileManager.default
        let name = "com.aipinyin.inputmethod.pastestop.\(UUID().uuidString)"
        defer { NSPasteboard(name: NSPasteboard.Name(name)).releaseGlobally() }
        let home = fm.temporaryDirectory.appendingPathComponent("pastestop-home-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home.appendingPathComponent(".config/allinoneime"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let environment = ["CFFIXED_USER_HOME": home.path, "HOME": home.path]

        // The app the copy was made in: copies it anew at each SIGUSR1.
        let log = fm.temporaryDirectory.appendingPathComponent("pastestop-source-\(UUID().uuidString).log")
        fm.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        let source = Process()
        source.executableURL = executable
        source.arguments = ["source", "0.15", name]
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

        let result = try command(executable, [stop.rawValue, name, log.path, "\(source.processIdentifier)", "\(rounds)"],
                                 environment: environment, timeout: 120)
        guard result.status == 0, let line = result.output.split(separator: "\n").last(where: { $0.hasPrefix("REPORT ") }) else {
            throw Failure(description: "the child (\(stop.rawValue)) failed (\(result.status)):\n\(result.output)")
        }
        return try JSONDecoder().decode([Round].self, from: Data(line.dropFirst("REPORT ".count).utf8))
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("pastestop-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try (String(main[..<cut.upperBound]) + TerminalPasteStopHarness.swift).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        let stubs = scratch.appendingPathComponent("Stubs.c"), stubsObject = scratch.appendingPathComponent("Stubs.o")
        try TerminalPasteStopHarness.stubs.write(to: stubs, atomically: true, encoding: .utf8)
        let clang = try command(URL(fileURLWithPath: "/usr/bin/xcrun"), ["clang", "-c", stubs.path, "-o", stubsObject.path], timeout: 60)
        guard clang.status == 0 else { throw Failure(description: clang.output) }
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
        let executable = scratch.appendingPathComponent("pastestop")
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
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("pastestop-\(UUID().uuidString).log")
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

/// The child's sources: what follows main.swift's `let arguments = …`, and C stand-ins for Accessibility, the modifier
/// keys' state, the key tap and posting keys, linked in ahead of the system's. The same executable is the copy's app.
private enum TerminalPasteStopHarness {
    static let stubs = #"""
#include <stdint.h>
unsigned char AXIsProcessTrusted(void) { return 1; }
unsigned char AXIsProcessTrustedWithOptions(const void *options) { return 1; }
static void (*posted)(void *event);
void pastestop_on_post(void (*callback)(void *event)) { posted = callback; }
void CGEventPost(uint32_t tap, void *event) { if (posted) posted(event); }
uint64_t CGEventSourceFlagsState(int32_t state) { return 0; }
void *CGEventTapCreate(uint32_t tap, uint32_t place, uint32_t options, uint64_t mask, void *callback, void *info) { return 0; }
"""#

    static let swift = #"""

// MARK: - The child of TerminalPasteStopTests (in place of main.swift's dispatch)

@_silgen_name("pastestop_on_post") func pasteStopOnPost(_ callback: @convention(c) (UnsafeMutableRawPointer?) -> Void)

let pasteStopCopied = "SECRET"

signal(SIGTERM, SIG_DFL)

if arguments.first == "source" {
    // The app the user copied in: its text handed over when read, `delay` seconds after being asked; copied anew at
    // each SIGUSR1.
    final class PasteStopSource: NSObject, NSPasteboardItemDataProvider {
        let delay: TimeInterval
        init(delay: TimeInterval) { self.delay = delay }

        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
            print("ASKED \(type.rawValue)")
            fflush(stdout)
            Thread.sleep(forTimeInterval: delay)
            item.setString(pasteStopCopied, forType: type)
        }
    }
    guard arguments.count == 3 else { exit(2) }
    let source = PasteStopSource(delay: Double(arguments[1]) ?? 0)
    let pasteboard = NSPasteboard(name: NSPasteboard.Name(arguments[2]))
    func copy() {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setDataProvider(source, forTypes: [.string])
        pasteboard.writeObjects([item])
        print("READY")
        fflush(stdout)
    }
    copy()
    signal(SIGUSR1, SIG_IGN)
    let again = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
    again.setEventHandler { copy() }
    again.resume()
    DispatchQueue.main.asyncAfter(deadline: .now() + 180) { exit(0) }
    withExtendedLifetime((source, again)) { RunLoop.main.run() }
    exit(0)
}

Platform.current.secrets = .inMemory()

/// A terminal's text field (Terminal): it takes what is inserted, and tells no caret.
final class PasteStopTerminal: NSObject, IMKTextInput {
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
    func uniqueClientIdentifierString() -> String! { "pastestop-terminal" }
    func string(from range: NSRange, actualRange: NSRangePointer!) -> String! { nil }
    func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect { NSRect(x: 420, y: 560, width: 1, height: 18) }
}

/// The general pasteboard, the test's named one; Paste from Other Apps: Allow; the terminal reading it 50 ms after each
/// ⌘V.
@MainActor
enum PasteStopClipboard {
    static var pasteboard: NSPasteboard!
    static var pasteKeys = 0
    static var terminalGot: [String] = []

    static func install(_ name: String) {
        pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
        let general = class_getClassMethod(NSPasteboard.self, NSSelectorFromString("generalPasteboard"))!
        let generalBlock: @convention(block) (AnyObject) -> NSPasteboard = { _ in MainActor.assumeIsolated { PasteStopClipboard.pasteboard } }
        method_setImplementation(general, imp_implementationWithBlock(generalBlock))
        if let access = class_getInstanceMethod(NSPasteboard.self, NSSelectorFromString("accessBehavior")) {
            let accessBlock: @convention(block) (AnyObject) -> Int = { _ in 2 }
            method_setImplementation(access, imp_implementationWithBlock(accessBlock))
        }
        pasteStopOnPost { pointer in
            guard let pointer else { return }
            let event = Unmanaged<CGEvent>.fromOpaque(pointer).takeUnretainedValue()
            guard event.type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 9 else { return }  // V
            MainActor.assumeIsolated {
                PasteStopClipboard.pasteKeys += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    MainActor.assumeIsolated {
                        PasteStopClipboard.terminalGot.append(PasteStopClipboard.pasteboard.string(forType: .string) ?? "")
                    }
                }
            }
        }
    }
}

struct PasteStopRound: Encodable {
    var stoppedBeforePasteKey = false
    var pasteKeys = 0
    var terminalGot: [String] = []
    var typed = ""
    var clipboardAfter: String?
}

@MainActor
enum PasteStopChild {
    static let stop = arguments.count > 0 ? arguments[0] : ""
    static let name = arguments.count > 1 ? arguments[1] : ""
    static let sourceLog = arguments.count > 2 ? arguments[2] : ""
    static let sourcePID = arguments.count > 3 ? pid_t(arguments[3]) ?? 0 : 0
    static let rounds = arguments.count > 4 ? Int(arguments[4]) ?? 1 : 1
    static let answer = "echo one\necho two\necho three"
    static let firstLine = "echo one"

    static var controller: AllInOneIMEInputController!
    static let terminal = PasteStopTerminal()
    static var done: [PasteStopRound] = []
    static var round = PasteStopRound()
    static var askedBefore = 0

    static func say(_ line: String) {
        print(line)
        fflush(stdout)
    }

    static func sourceSaid(_ word: String) -> Int {
        ((try? String(contentsOfFile: sourceLog, encoding: .utf8)) ?? "").components(separatedBy: word).count - 1
    }

    static func start() {
        let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
        guard !home.isEmpty, Config.defaultURL.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path) else {
            say("FAIL the config file isn't in the test's home: \(Config.defaultURL.path)")
            exit(3)
        }
        PasteStopClipboard.install(name)
        guard let made = AllInOneIMEInputController(server: nil, delegate: nil, client: nil) else {
            say("FAIL no input controller")
            exit(3)
        }
        controller = made
        controller.clientOverride = terminal
        startRound()
    }

    /// The answer typed out, with what the user copied just put on the clipboard (not kept by an earlier round).
    static func startRound() {
        (round, terminal.typed) = (PasteStopRound(), "")
        (PasteStopClipboard.pasteKeys, PasteStopClipboard.terminalGot) = (0, [])
        askedBefore = sourceSaid("ASKED ")
        controller.apply([.typeOut(answer)], client: terminal)
        waitForPaste(until: Date().addingTimeInterval(20))
    }

    /// Until the first line is typed and its line break's paste is keeping what was copied (its app asked for it).
    static func waitForPaste(until deadline: Date) {
        if terminal.typed == firstLine && sourceSaid("ASKED ") > askedBefore {
            stopTyping()
            return
        }
        guard Date() < deadline else {
            say("FAIL the line break was never pasted: typed \"\(terminal.typed)\", \(PasteStopClipboard.pasteKeys) ⌘V")
            exit(3)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.002) { MainActor.assumeIsolated { waitForPaste(until: deadline) } }
    }

    static func stopTyping() {
        round.stoppedBeforePasteKey = PasteStopClipboard.pasteKeys == 0
        switch stop {
        case "key":
            let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a",
                                       isARepeat: false, keyCode: 0)!
            _ = controller.handle(key, client: terminal)
        case "click":
            controller.commitComposition(terminal)
        default:
            say("FAIL unknown stop \(stop)")
            exit(2)
        }
        // The rest's paste kept, read and put back (0.5 s after the read).
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            MainActor.assumeIsolated {
                round.pasteKeys = PasteStopClipboard.pasteKeys
                round.terminalGot = PasteStopClipboard.terminalGot
                round.typed = terminal.typed
                round.clipboardAfter = PasteStopClipboard.pasteboard.string(forType: .string)
                done.append(round)
                guard done.count < rounds else {
                    say("REPORT " + String(decoding: try! JSONEncoder().encode(done), as: UTF8.self))
                    exit(0)
                }
                // Copied anew, so the next round's paste waits on its app again.
                let copies = sourceSaid("READY")
                kill(sourcePID, SIGUSR1)
                waitForCopy(after: copies, until: Date().addingTimeInterval(10))
            }
        }
    }

    static func waitForCopy(after copies: Int, until deadline: Date) {
        if sourceSaid("READY") > copies {
            startRound()
            return
        }
        guard Date() < deadline else {
            say("FAIL the copy's app never copied again")
            exit(3)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { MainActor.assumeIsolated { waitForCopy(after: copies, until: deadline) } }
    }
}

let pasteStopApp = NSApplication.shared
pasteStopApp.setActivationPolicy(.accessory)
DispatchQueue.main.async { MainActor.assumeIsolated { PasteStopChild.start() } }
pasteStopApp.run()
exit(0)
"""#
}
