import Foundation
import Testing

// Issue #35: putting the clipboard back after our own paste records a copy that clipboard history skipped. A terminal
// paste (a multi-line result going into a terminal, a kept image from ⌃V's history) puts the text or the image on the
// clipboard (marked transient: never recorded), posts ⌘V (⌃V), then puts back what was there before, with nothing to
// mark it as ours: at its next look the history sees a change and records it as a new copy. A token copied in a terminal
// with Secure Keyboard Entry on, rightly skipped then, ends up in clipboard-history.json and ⌃V's panel; what Clear
// History (or the history turned off and on) has just removed comes back. Expected: our own put-back is never recorded,
// and a copy made after it still is.
//
// The input method's own code can't be imported here (it is an executable target): its TerminalPaste.swift and its
// ClipboardHistory.swift (`ClipboardHistoryShared`: the recorder over the general pasteboard and the user's file, its
// look each second, Clear History, the history turned off and on) are compiled into a child process, with the Mac
// library and the core, as the input method runs them (`ClipboardHistoryShared.start()`, as at launch). There the
// general pasteboard is a private one of the child's (the Mac's own clipboard is never touched), Paste from Other Apps is
// Allow, Accessibility is granted, the keys TerminalPaste posts never leave the child (a ⌘V or ⌃V has the terminal read
// the clipboard, as another app), the child's home is a folder of the test's (the history's file is never the user's),
// and the stand-ins are those of the input method's own files not compiled in: whether secure input is on (SecureInput),
// the config as the file has it (LiveConfig, the history on), the log.

struct Issue35Tests {
    /// A token, copied in a terminal with Secure Keyboard Entry on.
    static let token = "ghp_issue35SecretTokenCopiedDuringSecureInput"
    /// What the user had copied before Clear History.
    static let copied = "what the user copied"
    /// A multi-line result, as `@improve` or `@question` puts one in.
    static let answer = "first line\nsecond line"
    /// Copied after it all.
    static let later = "a later copy"

    /// A token copied during secure input, rightly not recorded; then, secure input off (another terminal), a multi-line
    /// result (a kept image) pasted there: the token is put back on the clipboard, and stays out of the history, its
    /// panel's list and its file. A copy made after is recorded as before.
    @Test(arguments: [Issue35Child.Scenario.secureText, .secureImage])
    func aTokenSkippedDuringSecureInputIsNeverRecordedByThePutBack(_ scenario: Issue35Child.Scenario) throws {
        let report = try Issue35Child.run(scenario)
        #expect(report.clipboardText == Self.token, "the clipboard put back as the user had it: \(report)")
        #expect(report.pasted, "the terminal got the paste: \(report)")
        #expect(!report.afterPutBack.contains(Self.token), "the token is in ⌃V's history after the put back: \(report)")
        #expect(!report.fileAfterPutBack.contains(Self.token) && !report.fileMentionsIt,
                "the token is in clipboard-history.json after the put back: \(report)")
        #expect(report.final == [Self.later], "a copy after: only it recorded: \(report)")
    }

    /// Clear History pressed while a paste is still to be put back: the history stays empty when it is, its file too; a
    /// copy made after is recorded as before.
    @Test func clearHistoryDuringAPasteKeepsItCleared() throws {
        let report = try Issue35Child.run(.clear)
        #expect(report.clipboardText == Self.copied, "the clipboard put back as the user had it: \(report)")
        #expect(report.pasted, "the terminal got the paste: \(report)")
        #expect(report.afterPutBack.isEmpty, "what Clear History removed is back in ⌃V's history: \(report)")
        #expect(report.fileAfterPutBack.isEmpty && !report.fileMentionsIt, "and in clipboard-history.json: \(report)")
        #expect(report.final == [Self.later], "a copy after: only it recorded: \(report)")
    }

    /// The history turned off and on again while a paste is still to be put back (Settings): it stays empty when it is;
    /// a copy made after is recorded as before.
    @Test func historyTurnedOffAndOnDuringAPasteStaysEmpty() throws {
        let report = try Issue35Child.run(.offOn)
        #expect(report.clipboardText == Self.copied, "the clipboard put back as the user had it: \(report)")
        #expect(report.pasted, "the terminal got the paste: \(report)")
        #expect(report.afterPutBack.isEmpty, "what turning the history off deleted is back in ⌃V's history: \(report)")
        #expect(report.fileAfterPutBack.isEmpty && !report.fileMentionsIt, "and in clipboard-history.json: \(report)")
        #expect(report.final == [Self.later], "a copy after: only it recorded: \(report)")
    }
}

enum Issue35Child {
    enum Scenario: String, CaseIterable, CustomTestStringConvertible, Sendable {
        /// The token copied during secure input, then a multi-line result pasted (`TerminalPaste.paste`).
        case secureText = "secure-text"
        /// The token copied during secure input, then a kept image pasted with ⌃V (`TerminalPaste.pasteImage`).
        case secureImage = "secure-image"
        /// A copy recorded, a result pasted, Clear History before it is put back (`ClipboardHistoryShared.clear`).
        case clear
        /// A copy recorded, a result pasted, the history turned off and on before it is put back
        /// (`ClipboardHistoryShared.apply`, as Settings does).
        case offOn = "off-on"
        var testDescription: String { rawValue }
    }

    /// What the child saw.
    struct Report: Decodable, CustomStringConvertible {
        /// What the terminal read off the clipboard at each paste key: "text:…", "png:<bytes>".
        var terminalGot: [String]
        /// The clipboard after the put back, as another app reads it.
        var clipboardText: String?
        /// The history's items once the paste was put back and the history had looked (an image "<image>").
        var afterPutBack: [String]
        /// clipboard-history.json's then, read anew.
        var fileAfterPutBack: [String]
        /// Whether the file's bytes have the token (or what was cleared) in them at all.
        var fileMentionsIt: Bool
        /// The history's items after a later copy.
        var final: [String]
        /// The history's items after each step.
        var steps: [String]

        var pasted: Bool { terminalGot.contains("text:" + Issue35Tests.answer) || terminalGot.contains { $0.hasPrefix("png:") } }

        var description: String {
            "terminal got \(terminalGot), clipboard after: \(clipboardText.map { "\"\($0)\"" } ?? "no text"), "
                + "history after the put back \(afterPutBack), its file \(fileAfterPutBack)\(fileMentionsIt ? " (mentions it)" : ""), "
                + "after a later copy \(final); steps: \(steps.joined(separator: "; "))"
        }
    }

    struct Failure: Error, CustomStringConvertible { var description: String }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    static func run(_ scenario: Scenario) throws -> Report {
        let executable = try compiled.get()
        // The child's home: the history's file there, never the user's.
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("issue35-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let result = try command(executable, [scenario.rawValue], environment: ["CFFIXED_USER_HOME": home.path, "HOME": home.path],
                                 timeout: 60)
        guard result.status == 0, let line = result.output.split(separator: "\n").last(where: { $0.hasPrefix("REPORT ") }) else {
            throw Failure(description: "the child (\(scenario.rawValue)) failed (\(result.status)):\n\(result.output)")
        }
        return try JSONDecoder().decode(Report.self, from: Data(line.dropFirst("REPORT ".count).utf8))
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("issue35-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let harness = scratch.appendingPathComponent("Harness.swift")
        try Issue35Harness.swift.write(to: harness, atomically: true, encoding: .utf8)
        let stubs = scratch.appendingPathComponent("Stubs.c"), stubsObject = scratch.appendingPathComponent("Stubs.o")
        try Issue35Harness.stubs.write(to: stubs, atomically: true, encoding: .utf8)
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
        let executable = scratch.appendingPathComponent("issue35")
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
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("issue35-\(UUID().uuidString).log")
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
/// them rewritten), and C stand-ins for Accessibility and posting keys, linked in ahead of the system's.
private enum Issue35Harness {
    static let stubs = #"""
#include <stdint.h>
// Accessibility granted, never asked for; the keys posted handed to the harness, never posted to the Mac.
unsigned char AXIsProcessTrusted(void) { return 1; }
unsigned char AXIsProcessTrustedWithOptions(const void *options) { return 1; }
static void (*posted)(void *event);
void issue35_on_post(void (*callback)(void *event)) { posted = callback; }
void CGEventPost(uint32_t tap, void *event) { if (posted) posted(event); }
"""#

    static let swift = #"""
import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import Foundation
import ObjectiveC
import os

@_silgen_name("issue35_on_post") func issue35OnPost(_ callback: @convention(c) (UnsafeMutableRawPointer?) -> Void)

// The input method's own, not compiled in: its log, whether secure input is on (Secure Keyboard Entry in a terminal),
// the config as its file has it (clipboard history on, 20 kept).
let log = Logger(subsystem: "com.allinoneime.inputmethod.AllInOneIME", category: "ime")

enum SecureInput {
    static var isOn = false
}

enum LiveConfig {
    static var config = Config.default
    static var currentIfValid: Config? { config }
}

struct Issue35Report: Encodable {
    var terminalGot: [String] = []
    var clipboardText: String?
    var afterPutBack: [String] = []
    var fileAfterPutBack: [String] = []
    var fileMentionsIt = false
    var final: [String] = []
    var steps: [String] = []
}

/// The general pasteboard, a private one; Paste from Other Apps: Allow.
enum Issue35Clipboard {
    static let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.allinoneime.inputmethod.issue35.\(UUID().uuidString)"))
    static var terminalGot: [String] = []

    static func install() {
        let general = class_getClassMethod(NSPasteboard.self, NSSelectorFromString("generalPasteboard"))!
        let generalBlock: @convention(block) (AnyObject) -> NSPasteboard = { _ in Issue35Clipboard.pasteboard }
        method_setImplementation(general, imp_implementationWithBlock(generalBlock))
        // `NSPasteboard.AccessBehavior.alwaysAllow` (macOS 15.4; before it, nothing asks).
        if let access = class_getInstanceMethod(NSPasteboard.self, NSSelectorFromString("accessBehavior")) {
            let accessBlock: @convention(block) (AnyObject) -> Int = { _ in 2 }
            method_setImplementation(access, imp_implementationWithBlock(accessBlock))
        }
        issue35OnPost { pointer in
            guard let pointer else { return }
            let event = Unmanaged<CGEvent>.fromOpaque(pointer).takeUnretainedValue()
            guard event.type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 9 else { return }  // V
            // The terminal takes the paste.
            let pasteboard = Issue35Clipboard.pasteboard
            if let text = pasteboard.string(forType: .string) { Issue35Clipboard.terminalGot.append("text:" + text) }
            if let png = pasteboard.data(forType: .png) { Issue35Clipboard.terminalGot.append("png:\(png.count)") }
        }
    }

    /// `text` copied by another app (a terminal's ⌘C).
    static func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

@main
struct Issue35Main {
    @MainActor
    static func main() async {
        Platform.current = .mac  // as the input method's launch
        Issue35Clipboard.install()
        let arguments = CommandLine.arguments
        guard arguments.count == 2, ["secure-text", "secure-image", "clear", "off-on"].contains(arguments[1]) else {
            print("usage: issue35 secure-text|secure-image|clear|off-on")
            exit(2)
        }
        // Never the user's history: the child's home is the test's.
        let file = ClipboardHistoryStore.defaultURL
        guard let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"], !home.isEmpty,
              file.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path)
        else {
            print("the history's file isn't in the test's home: \(file.path)")
            exit(3)
        }
        let pasteboard = Issue35Clipboard.pasteboard
        defer { pasteboard.releaseGlobally() }
        let token = "ghp_issue35SecretTokenCopiedDuringSecureInput", copied = "what the user copied"
        let answer = "first line\nsecond line"
        var report = Issue35Report()
        func items() -> [String] { ClipboardHistoryShared.recorder.store.items.map { $0.image != nil ? "<image>" : $0.text } }
        func look(_ step: String) {
            ClipboardHistoryShared.tick()
            report.steps.append("\(step): \(items())")
        }
        ClipboardHistoryShared.start()  // as at launch: a look now, then each second
        let scenario = arguments[1]
        switch scenario {
        case "secure-text", "secure-image":
            // Copied in a terminal with Secure Keyboard Entry on: not recorded.
            SecureInput.isOn = true
            Issue35Clipboard.copy(token)
            look("the token copied during secure input")
            // Another terminal: secure input off.
            SecureInput.isOn = false
            look("secure input off")
            if scenario == "secure-text" {
                await TerminalPaste.paste(answer)
            } else {
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                              hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                await TerminalPaste.pasteImage(bitmap.representation(using: .png, properties: [:])!, controlV: true)
            }
            report.steps.append("pasted: \(items())")
        default:
            Issue35Clipboard.copy(copied)
            look("copied")
            await TerminalPaste.paste(answer)
            // Before the clipboard is put back (half a second after the terminal read it).
            if scenario == "clear" {
                ClipboardHistoryShared.clear()  // Clear History
                report.steps.append("cleared: \(items())")
            } else {
                // Settings: the history turned off, then on again.
                LiveConfig.config.clipboardHistory = false
                ClipboardHistoryShared.apply(LiveConfig.config)
                look("turned off")
                LiveConfig.config.clipboardHistory = true
                ClipboardHistoryShared.apply(LiveConfig.config)
                look("turned on")
            }
        }
        // The clipboard put back meanwhile; the history looking as it does.
        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            ClipboardHistoryShared.tick()
        }
        report.steps.append("put back: \(items())")
        report.terminalGot = Issue35Clipboard.terminalGot
        report.clipboardText = pasteboard.string(forType: .string)
        report.afterPutBack = items()
        report.fileAfterPutBack = ClipboardHistoryStore(url: file).items.map { $0.image != nil ? "<image>" : $0.text }
        let bytes = (try? Data(contentsOf: file)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        report.fileMentionsIt = bytes.contains(scenario.hasPrefix("secure") ? token : copied)
        Issue35Clipboard.copy("a later copy")
        look("a later copy")
        report.final = items()
        let json = try! JSONEncoder().encode(report)
        print("REPORT " + String(decoding: json, as: UTF8.self))
    }
}
"""#
}
