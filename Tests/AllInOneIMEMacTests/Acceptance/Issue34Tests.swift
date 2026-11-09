import Foundation
import Testing

// Issue #34: a terminal paste empties the clipboard when Paste from Other Apps is not Allow. With Accessibility granted,
// a multi-line result going into a terminal (and a kept image from ⌃V's history) goes in as a paste: the clipboard is
// saved, the text put on it, ⌘V (⌃V) posted, the clipboard put back. The save reads every type without asking whether
// it may: with Deny each read comes back empty and the put back clears the clipboard, so what the user had copied is
// gone; with Ask (or never asked yet, macOS 15.4+) each read asks, once per line break while typing out. Expected: the
// clipboard is untouched and nothing asks; without read access a result goes in the way it does without Accessibility
// (on one line).
//
// The input method's own code can't be imported here (it is an executable target): its TerminalPaste.swift and its
// "can paste in terminal" (InputController's `canPasteInTerminal` default) are compiled into a child process, with the
// Mac library and the core, as the input method runs them. There the general pasteboard is a private one of the
// child's (the Mac's own clipboard is never touched), Paste from Other Apps answers as the test says (Allow, Deny, Ask,
// not asked yet: `NSPasteboard.accessBehavior`), the input method's reads of the clipboard's data are counted (with
// Deny they come back empty, as macOS returns them; with Ask each one is a prompt), Accessibility is granted without
// asking, and the keys TerminalPaste posts never leave the child: a ⌘V or ⌃V has the terminal read the clipboard, as
// another app (which macOS doesn't ask about).

@Suite(.enabled(if: Issue34Child.macOSAsksBeforeReads, "Paste from Other Apps is macOS 15.4's"))
struct Issue34Tests {
    /// What the user had copied before the result went in.
    static let copied = "what the user copied"
    /// A multi-line result, as `@improve` or `@question` puts one in.
    static let answer = "first line\nsecond line"

    static let withoutReadAccess = [Issue34Child.Access.deny, .ask, .notAsked]

    /// Accessibility granted, but the clipboard can't be read without asking: no paste into a terminal (the result goes in
    /// on one line, as without Accessibility), and asking so reads nothing and prompts for nothing.
    @Test(arguments: withoutReadAccess)
    func noTerminalPasteWithoutReadAccess(_ access: Issue34Child.Access) throws {
        let report = try Issue34Child.run(.canPaste, access)
        #expect(report.canPaste == false, "Accessibility granted, Paste from Other Apps \(access): can paste in terminal")
        #expect(report.reads == 0, "reads of the clipboard's data: \(report)")
        #expect(report.accessibilityPrompts == 0, "\(report)")
    }

    /// A multi-line result pasted into the terminal all the same: what the user copied is still on the clipboard after,
    /// nothing of it was read (with Ask, a prompt each), and the terminal never got it pasted in.
    @Test(arguments: withoutReadAccess)
    func aPasteLeavesTheClipboardAsItWas(_ access: Issue34Child.Access) throws {
        let report = try Issue34Child.run(.paste, access)
        #expect(report.clipboardText == Self.copied, "Paste from Other Apps \(access): the clipboard after the paste: \(report)")
        #expect(report.reads == 0, "reads of the clipboard's data (each a prompt with Ask): \(report)")
        #expect(!report.terminalGot.contains("text:" + Self.copied), "the user's clipboard pasted into the terminal: \(report)")
    }

    /// Typing a result out into a terminal pastes each line break: two line breaks never ask twice (nor once), and leave
    /// the clipboard as it was.
    @Test(arguments: withoutReadAccess)
    func typingOutLineBreaksNeverAsks(_ access: Issue34Child.Access) throws {
        let report = try Issue34Child.run(.typeOut, access)
        #expect(report.reads == 0, "Paste from Other Apps \(access): reads of the clipboard's data for two line breaks: \(report)")
        #expect(report.clipboardText == Self.copied, "the clipboard after typing out: \(report)")
        #expect(!report.terminalGot.contains("text:" + Self.copied), "the user's clipboard pasted into the terminal: \(report)")
    }

    /// A kept image from ⌃V's history pasted into a terminal (⌃V): nothing of the clipboard read, and it isn't left empty
    /// (what the user copied is still there, or the image is, for their own paste, as without Accessibility).
    @Test(arguments: withoutReadAccess)
    func aKeptImageNeverEmptiesTheClipboard(_ access: Issue34Child.Access) throws {
        let report = try Issue34Child.run(.image, access)
        #expect(report.reads == 0, "Paste from Other Apps \(access): reads of the clipboard's data: \(report)")
        #expect(report.clipboardText == Self.copied || report.clipboardHasImage, "the clipboard left empty: \(report)")
        #expect(!report.terminalGot.contains("text:" + Self.copied), "the user's clipboard pasted into the terminal: \(report)")
    }

    /// With Allow it pastes as before: the terminal gets the result (the image), and the clipboard is put back. (And the
    /// child sees the input method's reads, so the counts above are real.)
    @Test func withAllowItPastesAndPutsTheClipboardBack() throws {
        let check = try Issue34Child.run(.canPaste, .allow)
        #expect(check.canPaste == true && check.reads == 0, "\(check)")
        let paste = try Issue34Child.run(.paste, .allow)
        #expect(paste.terminalGot.contains("text:" + Self.answer), "\(paste)")
        #expect(paste.clipboardText == Self.copied && paste.reads > 0, "\(paste)")
        let lines = try Issue34Child.run(.typeOut, .allow)
        #expect(lines.terminalGot.filter { $0 == "text:\n" }.count == 2 && lines.clipboardText == Self.copied, "\(lines)")
        let image = try Issue34Child.run(.image, .allow)
        #expect(image.terminalGot.contains { $0.hasPrefix("png:") }, "\(image)")
        #expect(image.clipboardText == Self.copied && image.reads > 0, "\(image)")
    }
}

enum Issue34Child {
    /// Paste from Other Apps' setting for AllInOneIME (`NSPasteboard.AccessBehavior`).
    enum Access: String, CaseIterable, CustomTestStringConvertible, Sendable {
        case allow, deny, ask, notAsked
        var testDescription: String { rawValue }
    }

    enum Scenario: String {
        /// Whether the input method pastes a multi-line result into a terminal (`canPasteInTerminal`).
        case canPaste = "can-paste"
        /// `TerminalPaste.paste` of a multi-line result (a result inserted).
        case paste
        /// `TerminalPaste.paste` of a line break, twice (a result typed out).
        case typeOut = "type-out"
        /// `TerminalPaste.pasteImage` of a kept image, with ⌃V (a terminal's paste key).
        case image
    }

    /// What the child saw.
    struct Report: Decodable, CustomStringConvertible {
        var canPaste: Bool?
        /// The input method's reads of the clipboard's data (its types aren't counted: reading them never asks).
        var reads: Int
        var accessibilityPrompts: Int
        /// The keys posted ("cmd-9-down": ⌘V).
        var keys: [String]
        /// What the terminal read off the clipboard at each paste key: "text:…", "png:<bytes>".
        var terminalGot: [String]
        /// The clipboard after, as another app reads it.
        var clipboardText: String?
        var clipboardHasImage: Bool

        var description: String {
            "canPaste \(canPaste.map(String.init) ?? "-"), reads \(reads), accessibility prompts \(accessibilityPrompts), keys \(keys), "
                + "terminal got \(terminalGot), clipboard after: \(clipboardText.map { "\"\($0)\"" } ?? "no text")"
                + (clipboardHasImage ? " and an image" : "")
        }
    }

    struct Failure: Error, CustomStringConvertible { var description: String }

    static var macOSAsksBeforeReads: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 4, patchVersion: 0))
    }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    static func run(_ scenario: Scenario, _ access: Access) throws -> Report {
        let result = try command(try compiled.get(), [scenario.rawValue, access.rawValue], timeout: 60)
        guard result.status == 0, let line = result.output.split(separator: "\n").last(where: { $0.hasPrefix("REPORT ") }) else {
            throw Failure(description: "the child (\(scenario.rawValue), \(access.rawValue)) failed (\(result.status)):\n\(result.output)")
        }
        return try JSONDecoder().decode(Report.self, from: Data(line.dropFirst("REPORT ".count).utf8))
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
        let scratch = fm.temporaryDirectory.appendingPathComponent("issue34-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let harness = scratch.appendingPathComponent("Harness.swift")
        try Issue34Harness.swift.replacingOccurrences(of: "CAN_PASTE_IN_TERMINAL", with: try canPasteInTerminal())
            .write(to: harness, atomically: true, encoding: .utf8)
        let stubs = scratch.appendingPathComponent("Stubs.c"), stubsObject = scratch.appendingPathComponent("Stubs.o")
        try Issue34Harness.stubs.write(to: stubs, atomically: true, encoding: .utf8)
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
        let executable = scratch.appendingPathComponent("issue34")
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
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("issue34-\(UUID().uuidString).log")
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
/// for Accessibility and posting keys, linked in ahead of the system's.
private enum Issue34Harness {
    static let stubs = #"""
#include <stdint.h>
// Accessibility granted, as the issue's trigger has it, never asked for; the keys posted handed to the harness, never
// posted to the Mac.
static int32_t prompts;
unsigned char AXIsProcessTrusted(void) { return 1; }
unsigned char AXIsProcessTrustedWithOptions(const void *options) { prompts++; return 1; }
int32_t issue34_accessibility_prompts(void) { return prompts; }
static void (*posted)(void *event);
void issue34_on_post(void (*callback)(void *event)) { posted = callback; }
void CGEventPost(uint32_t tap, void *event) { if (posted) posted(event); }
"""#

    static let swift = #"""
import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import Foundation
import ObjectiveC

@_silgen_name("issue34_accessibility_prompts") func issue34AccessibilityPrompts() -> Int32
@_silgen_name("issue34_on_post") func issue34OnPost(_ callback: @convention(c) (UnsafeMutableRawPointer?) -> Void)

struct Issue34Report: Encodable {
    var canPaste: Bool?
    var reads = 0
    var accessibilityPrompts = 0
    var keys: [String] = []
    var terminalGot: [String] = []
    var clipboardText: String?
    var clipboardHasImage = false
}

/// The general pasteboard, a private one; Paste from Other Apps as the test says; the input method's reads counted.
enum Issue34Clipboard {
    static let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.allinoneime.inputmethod.issue34.\(UUID().uuidString)"))
    /// `NSPasteboard.AccessBehavior`'s raw value: default 0 (never asked), ask 1, alwaysAllow 2, alwaysDeny 3.
    static var behavior = 2
    static var reads = 0
    static var keys: [String] = []
    static var terminalGot: [String] = []
    /// Another app reading (the terminal, the test): not the input method's read, never asked about.
    static var otherApp = false

    static func asOtherApp<T>(_ body: () -> T) -> T {
        otherApp = true
        defer { otherApp = false }
        return body()
    }

    static func install() {
        let general = class_getClassMethod(NSPasteboard.self, NSSelectorFromString("generalPasteboard"))!
        let generalBlock: @convention(block) (AnyObject) -> NSPasteboard = { _ in Issue34Clipboard.pasteboard }
        method_setImplementation(general, imp_implementationWithBlock(generalBlock))
        guard let access = class_getInstanceMethod(NSPasteboard.self, NSSelectorFromString("accessBehavior")) else {
            print("no NSPasteboard.accessBehavior")
            exit(2)
        }
        let accessBlock: @convention(block) (AnyObject) -> Int = { _ in Issue34Clipboard.behavior }
        method_setImplementation(access, imp_implementationWithBlock(accessBlock))
        for type in [NSPasteboard.self, NSPasteboardItem.self] as [AnyClass] {
            for name in ["dataForType:", "stringForType:", "propertyListForType:"] { countReads(type, name) }
        }
        countObjectReads()
        issue34OnPost { pointer in
            guard let pointer else { return }
            let event = Unmanaged<CGEvent>.fromOpaque(pointer).takeUnretainedValue()
            let modifier = event.flags.contains(.maskCommand) ? "cmd" : event.flags.contains(.maskControl) ? "ctrl" : "none"
            let down = event.type == .keyDown
            Issue34Clipboard.keys.append("\(modifier)-\(event.getIntegerValueField(.keyboardEventKeycode))-\(down ? "down" : "up")")
            guard down, event.getIntegerValueField(.keyboardEventKeycode) == 9 else { return }  // V
            // The terminal takes the paste.
            Issue34Clipboard.asOtherApp {
                let pasteboard = Issue34Clipboard.pasteboard
                if let text = pasteboard.string(forType: .string) { Issue34Clipboard.terminalGot.append("text:" + text) }
                if let png = pasteboard.data(forType: .png) { Issue34Clipboard.terminalGot.append("png:\(png.count)") }
            }
        }
    }

    /// `name` (a read of one type's data) counted when the input method reads; with Deny, nothing comes back.
    static func countReads(_ type: AnyClass, _ name: String) {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(type, selector) else {
            print("no \(type) \(name)")
            exit(2)
        }
        typealias Read = @convention(c) (AnyObject, Selector, AnyObject?) -> AnyObject?
        let original = unsafeBitCast(method_getImplementation(method), to: Read.self)
        let block: @convention(block) (AnyObject, AnyObject?) -> AnyObject? = { object, pasteboardType in
            if !Issue34Clipboard.otherApp {
                Issue34Clipboard.reads += 1
                if Issue34Clipboard.behavior == 3 { return nil }
            }
            return original(object, selector, pasteboardType)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    static func countObjectReads() {
        let selector = NSSelectorFromString("readObjectsForClasses:options:")
        guard let method = class_getInstanceMethod(NSPasteboard.self, selector) else { return }
        typealias Read = @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?) -> AnyObject?
        let original = unsafeBitCast(method_getImplementation(method), to: Read.self)
        let block: @convention(block) (AnyObject, AnyObject?, AnyObject?) -> AnyObject? = { object, classes, options in
            if !Issue34Clipboard.otherApp {
                Issue34Clipboard.reads += 1
                if Issue34Clipboard.behavior == 3 { return nil }
            }
            return original(object, selector, classes, options)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}

@main
struct Issue34Main {
    @MainActor
    static func main() async {
        // InputController's own.
        let canPasteInTerminal: @MainActor () -> Bool = CAN_PASTE_IN_TERMINAL
        Issue34Clipboard.install()
        let arguments = CommandLine.arguments
        let behaviors = ["notAsked": 0, "ask": 1, "allow": 2, "deny": 3]
        guard arguments.count == 3, let behavior = behaviors[arguments[2]] else {
            print("usage: issue34 can-paste|paste|type-out|image allow|deny|ask|notAsked")
            exit(2)
        }
        let pasteboard = Issue34Clipboard.pasteboard
        defer { pasteboard.releaseGlobally() }
        // What the user copied, as Allow had it read.
        pasteboard.clearContents()
        pasteboard.setString("what the user copied", forType: .string)
        Issue34Clipboard.behavior = behavior
        var report = Issue34Report()
        switch arguments[1] {
        case "can-paste":
            report.canPaste = canPasteInTerminal()
        case "paste":
            await TerminalPaste.paste("first line\nsecond line")
        case "type-out":
            for _ in 0..<2 { await TerminalPaste.paste("\n") }
        case "image":
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                          hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            await TerminalPaste.pasteImage(bitmap.representation(using: .png, properties: [:])!, controlV: true)
        default:
            print("unknown scenario \(arguments[1])")
            exit(2)
        }
        // The clipboard put back (half a second after the terminal read a text paste).
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        report.reads = Issue34Clipboard.reads
        report.accessibilityPrompts = Int(issue34AccessibilityPrompts())
        report.keys = Issue34Clipboard.keys
        report.terminalGot = Issue34Clipboard.terminalGot
        report.clipboardText = Issue34Clipboard.asOtherApp { pasteboard.string(forType: .string) }
        report.clipboardHasImage = Issue34Clipboard.asOtherApp { pasteboard.data(forType: .png) != nil }
        let json = try! JSONEncoder().encode(report)
        print("REPORT " + String(decoding: json, as: UTF8.self))
    }
}
"""#
}
