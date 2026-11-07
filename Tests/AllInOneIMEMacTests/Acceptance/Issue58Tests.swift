import AppKit
import Foundation
import Testing

// Issue #58: tabs and control characters in a clipboard row or a snippet reach the shell. Into a terminal, only text
// with a line break goes in as a paste (`insert`: where Accessibility lets the paste key be posted) or on one line
// (where it can't: the session's `intoField`). One-line text with a tab, ESC, ^C or ^D is inserted as it is
// (`insertText`): the terminal hands a tab to the shell as completion (the command line garbled) and ^D as the end of
// input (an empty shell closes). Copy a Makefile line ("\tmake test") or a TSV pair, ⌃V in Terminal, ⏎ on its row; or
// a snippet with a tab. Expected: the text arrives as copied, through the paste as multi-line text does, or with its
// tabs made spaces and its other control characters dropped, as command output already is (`CommandRunner.oneLine`).
// Either way nothing typed into the terminal has a control character, and the text's words arrive as they were.
//
// Here where the paste key can be posted (the core's Issue58Tests has the terminal where it can't). As Issue54Tests
// does it: all of Sources/AllInOneIME is compiled into a child process, with the Mac library, the core and librime, as
// the input method is built, and only main.swift's dispatch replaced. The child makes the input controller and a
// terminal's field (Terminal's bundle id, `FakeTextClient`), its session focused there, and presses the keys as the
// user does: ⌃V and ⏎ on the row (the clipboard history and what ⌃V reads of the clipboard the child's own), or
// "@tsv" and ⏎ for a snippet. Pasting is allowed and recorded (`canPasteInTerminal`, `pasteInTerminal`), never posted;
// what is inserted is the field's. Secure input is off for the child (it may be on on the Mac running the tests: a login
// window). No key tap is made and no key is posted; the child's home is a folder of the test's and its keychain an
// in-memory one: nothing reads the user's config, keychain, clipboard or history.

@Suite(.serialized)
struct Issue58Tests {
    /// ⌃V ⏎ on a row (or `@tsv` ⏎ for a snippet) of one-line text with a tab or a control character, in a terminal
    /// that can be pasted into: nothing typed into it has a control character, and the text's words arrive (pasted or
    /// typed) as they were.
    @Test(arguments: Issue58Child.Case.all)
    func aTabOrControlCharacterIsNeverTypedIntoATerminal(_ item: Issue58Child.Case) throws {
        let report = try Issue58Child.run(item)
        let what = "\(item.testDescription) in Terminal"
        if item.how == .row {
            #expect(report.shown, "\(what): the clipboard history didn't show its row (the test missed its setup): \(report)")
        }
        #expect(!report.inserted.isEmpty || !report.pasted.isEmpty, "\(what): nothing went into the terminal: \(report)")
        let typed = report.inserted.joined()
        #expect(Issue58Child.controls(typed).isEmpty,
                "\(what): typed into the terminal as \(Issue58Child.shown(typed)), its control characters to the shell: \(report)")
        #expect(Issue58Child.words(report.pasted.joined(separator: " ") + " " + typed) == item.words,
                "\(what): the terminal got other words than the text's: \(report)")
    }
}

enum Issue58Child {
    /// A text and how it is put in.
    struct Case: CustomTestStringConvertible, Sendable {
        enum How: String, Sendable { case row, snippet }
        var how: How
        var text: String
        /// The words it holds.
        var words: [String]

        var testDescription: String {
            how == .row ? "⌃V ⏎ on \(Issue58Child.shown(text))" : "the snippet \(Issue58Child.shown(text))"
        }

        static let all: [Case] = [
            Case(how: .row, text: "\tmake test", words: ["make", "test"]),  // a Makefile line
            Case(how: .row, text: "name\tvalue", words: ["name", "value"]),  // a TSV pair
            Case(how: .row, text: "echo hi\u{1B}", words: ["echo", "hi"]),
            Case(how: .row, text: "\u{03}sleep 1", words: ["sleep", "1"]),
            Case(how: .row, text: "exit\u{04}", words: ["exit"]),
            Case(how: .snippet, text: "name\tvalue", words: ["name", "value"]),
            Case(how: .snippet, text: "\tmake test", words: ["make", "test"]),
        ]
    }

    /// What the child saw.
    struct Report: Decodable, CustomStringConvertible {
        /// Whether the clipboard history's panel showed, with its rows.
        var shown: Bool
        var rows: [String]
        /// What went into the terminal's field (`insertText`), in order.
        var inserted: [String]
        /// What was pasted into it (`pasteInTerminal`), in order.
        var pasted: [String]
        /// What is marked in it once it's all over.
        var marked: String
        var output: String?

        var description: String {
            "panel \(shown ? "shown" : "not shown") \(Self.list(rows)), inserted \(Self.list(inserted)), pasted \(Self.list(pasted)), "
                + "marked \(Issue58Child.shown(marked))" + (output.map { "\n\($0)" } ?? "")
        }

        static func list(_ texts: [String]) -> String {
            "[" + texts.map(Issue58Child.shown).joined(separator: ", ") + "]"
        }
    }

    struct Failure: Error, CustomStringConvertible { var description: String }

    /// `text` with its control characters shown (`\t`, `\u{1B}`).
    static func shown(_ text: String) -> String {
        "\"" + text.unicodeScalars.map { $0.escaped(asASCII: true) }.joined() + "\""
    }

    static func controls(_ text: String) -> [Unicode.Scalar] {
        text.unicodeScalars.filter { $0.properties.generalCategory == .control }
    }

    /// The words of `text`, between blank space and control characters.
    static func words(_ text: String) -> [String] {
        let spaced = String(String.UnicodeScalarView(text.unicodeScalars.map { $0.properties.generalCategory == .control ? " " : $0 }))
        return spaced.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    static var thirdParty: URL {
        ProcessInfo.processInfo.environment["ALLINONEIME_THIRDPARTY"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("ThirdParty")
    }

    /// `item` put into a terminal's field by the child.
    static func run(_ item: Case) throws -> Report {
        let executable = try compiled.get()
        let fm = FileManager.default
        // The child's home: never the user's config.
        let home = fm.temporaryDirectory.appendingPathComponent("issue58-home-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home.appendingPathComponent(".config/allinoneime"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let environment = ["CFFIXED_USER_HOME": home.path, "HOME": home.path]
        // The text as JSON: its control characters kept as they are.
        let text = String(decoding: try JSONEncoder().encode([item.text]), as: UTF8.self)
        let result = try command(executable, [item.how.rawValue, text], environment: environment, timeout: 60)
        guard result.status == 0, let line = result.output.split(separator: "\n").last(where: { $0.hasPrefix("REPORT ") }) else {
            throw Failure(description: "the child (\(item.testDescription)) failed (\(result.status)):\n\(result.output)")
        }
        var report = try JSONDecoder().decode(Report.self, from: Data(line.dropFirst("REPORT ".count).utf8))
        report.output = result.output.split(separator: "\n").filter { $0.hasPrefix("FAIL") }.joined(separator: "\n")
        if report.output?.isEmpty == true { report.output = nil }
        return report
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("issue58-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        // main.swift as written up to its dispatch, then the harness.
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try (String(main[..<cut.upperBound]) + Issue58Harness.swift).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        let stubs = scratch.appendingPathComponent("Stubs.c"), stubsObject = scratch.appendingPathComponent("Stubs.o")
        try Issue58Harness.stubs.write(to: stubs, atomically: true, encoding: .utf8)
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
        let executable = scratch.appendingPathComponent("issue58")
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
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("issue58-\(UUID().uuidString).log")
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

/// The child's sources: what follows main.swift's `let arguments = …` (the input controller in a terminal's field, the
/// keys pressed as the scenario says), and C stand-ins for Accessibility and secure input, and that keep it from posting
/// keys or making a key tap, linked in ahead of the system's.
private enum Issue58Harness {
    static let stubs = #"""
#include <stdint.h>
// Accessibility granted (the paste key could be posted); secure input off (a login window or a password field elsewhere
// on the Mac would keep the terminal from composing); no key ever posted to the Mac; no key tap made.
unsigned char AXIsProcessTrusted(void) { return 1; }
unsigned char IsSecureEventInputEnabled(void) { return 0; }
unsigned char AXIsProcessTrustedWithOptions(const void *options) { return 1; }
void CGEventPost(uint32_t tap, void *event) {}
void *CGEventTapCreate(uint32_t tap, uint32_t place, uint32_t options, uint64_t mask, void *callback, void *info) { return 0; }
"""#

    static let swift = #"""

// MARK: - Issue #58's child (in place of main.swift's dispatch)

// Ended by SIGTERM as any program is (main.swift ignores it): the test stops the child once it times out.
signal(SIGTERM, SIG_DFL)

// Never the user's keychain.
Platform.current.secrets = .inMemory()

struct Issue58Report: Encodable {
    var shown = false
    var rows: [String] = []
    var inserted: [String] = []
    var pasted: [String] = []
    var marked = ""
}

@MainActor
enum Issue58Child {
    static var report = Issue58Report()

    static func say(_ line: String) {
        print(line)
        fflush(stdout)
    }

    static func key(_ characters: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                         windowNumber: 0, context: nil, characters: characters,
                         charactersIgnoringModifiers: flags == .control ? "v" : characters, isARepeat: false, keyCode: code)!
    }

    static func main() {
        // The app, as `runServer` has it; no key tap, no clipboard history but the child's own, no microphone.
        NSApplication.shared.setActivationPolicy(.accessory)
        KeyGuard.shared.disabled = true
        ClipboardHistoryShared.isolated = true
        AllInOneIMEInputController.microphoneAllowed = false
        // Never the user's config: the test's home.
        let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
        guard !home.isEmpty, Config.defaultURL.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path) else {
            say("FAIL the config file isn't in the test's home: \(Config.defaultURL.path)")
            exit(3)
        }
        guard arguments.count == 2, let texts = try? JSONDecoder().decode([String].self, from: Data(arguments[1].utf8)),
              let text = texts.first else {
            say("FAIL arguments: \(arguments)")
            exit(2)
        }
        let how = arguments[0]
        var config = Config.default
        config.uiLanguage = "en"
        config.checkForUpdates = false
        if how == "snippet" { config.customCommands = [CustomCommand(name: "tsv", type: .snippet, text: text)] }
        let settings = config

        CandidatePanel.shared.alphaValue = 0
        CandidatePanel.shared.ignoresMouseEvents = true
        guard let controller = AllInOneIMEInputController(server: nil, delegate: nil, client: nil) else {
            say("FAIL no input controller")
            exit(3)
        }
        // A terminal's field (Terminal).
        let terminal = FakeTextClient()
        terminal.bundleIDOverride = "com.apple.Terminal"
        controller.clientOverride = terminal
        controller.services.loadSettings = { settings }
        controller.services.loadCommandUsage = { CommandUsage() }
        controller.services.saveCommandUsage = { _ in }
        controller.services.secureInputActive = { false }
        // The history and the clipboard: the text just copied, an older copy.
        let now = Date()
        let history = [ClipboardHistoryItem(text: text, copiedAt: now - 60), ClipboardHistoryItem(text: "an older copy", copiedAt: now - 3600)]
        controller.services.clipboardHistory = ClipboardHistoryServices(state: { .recording }, items: { history }, canPassPasteKey: { false },
                                                                       firstShowing: { false }, now: { now })
        controller.peekClipboard = { .text(text) }
        controller.readClipboard = { .text(text) }
        // The paste key could be posted: what is pasted recorded, never posted.
        controller.canPasteInTerminal = { true }
        controller.pasteInTerminal = { Issue58Child.report.pasted.append($0); return true }
        controller.applySettings()
        controller.apply(controller.session.handle(.focus(FieldInfo(app: "com.apple.Terminal", terminal: true))).outputs, client: terminal)
        controller.composer.setInputMode(.english)

        switch how {
        case "row":
            _ = controller.handle(key("\u{16}", 0x09, .control), client: terminal)
            let panel = CandidatePanel.shared
            report.shown = SelfTest.pump(timeout: 3) { panel.isShowing && !panel.view.model.rows.isEmpty }
            report.rows = panel.view.model.rows.map(\.text)
        case "snippet":
            guard SelfTest.pump(timeout: 10, until: { controller.composer.commands.contains { $0.name == "tsv" } }) else {
                say("FAIL the snippet isn't offered")
                exit(3)
            }
            _ = controller.handle(key("@", 0x13, .shift), client: terminal)
            for (ch, code) in [("t", 0x11), ("s", 0x01), ("v", 0x09)] as [(String, UInt16)] {
                _ = controller.handle(key(ch, code), client: terminal)
            }
        default:
            say("FAIL unknown case \(how)")
            exit(2)
        }
        _ = controller.handle(key("\r", 0x24), client: terminal)
        // What goes in once the key is done (a paste), and anything after it.
        _ = SelfTest.pump(timeout: 1) { !report.pasted.isEmpty || !terminal.inserted.isEmpty }
        _ = SelfTest.pump(timeout: 0.5) { false }
        report.inserted = terminal.inserted.filter { !$0.isEmpty }
        report.marked = terminal.marked
        say("REPORT " + String(decoding: try! JSONEncoder().encode(report), as: UTF8.self))
        exit(0)
    }
}

MainActor.assumeIsolated { Issue58Child.main() }
exit(0)
"""#
}
