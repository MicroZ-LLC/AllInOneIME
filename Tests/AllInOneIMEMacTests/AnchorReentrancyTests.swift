import AllInOneIMETestSupport
import Foundation
import Testing

// The panel's rect asked of a field while a key comes in (0.7.5 crash, 2026-11-22): asking the field for its caret
// (`markedRange`, `firstRect`) waits on the app over XPC and runs the run loop meanwhile, so the next key can be handled
// inside that call; the key shows the panel, which places it (`anchor`), writing `panelAnchor`. The asking call held
// `&panelAnchor` (and `&lastAnchorByApp`) open across the field's answer, and Swift stopped the input method for the
// overlapping access (SIGABRT). Both ways in are tried: the panel placed for a key (`anchor`) and the field asked again
// a moment later (`reasked`).
//
// The input method's code isn't a library: Sources/AllInOneIME is compiled into a child process with main.swift's
// dispatch replaced, as Issue49Tests does it. The child's field answers the caret question by placing the panel again
// for the same field, once, as the key arriving meanwhile would. A crash shows as the child dying of a signal.

@Suite(.serialized)
struct AnchorReentrancyTests {
    @Test(arguments: ["anchor", "reask"])
    func aKeyPlacingThePanelWhileTheFieldIsAskedDoesntCrash(_ way: String) throws {
        let result = try AnchorReentrancyChild.run(way)
        #expect(result.status == 0 && result.output.contains("PLACED \(way)"),
                "the input method stopped while the field was asked for the panel's rect (\(way)), exit \(result.status):\n\(result.output)")
        #expect(result.output.contains("REENTERED"), "the field wasn't asked while the panel was placed (\(way)):\n\(result.output)")
    }
}

enum AnchorReentrancyChild {
    struct Failure: Error, CustomStringConvertible { var description: String }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    static func run(_ way: String) throws -> (status: Int32, output: String) {
        let executable = try compiled.get()
        let home = TestScratch.temporary("anchor-reentrancy-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = executable
        process.arguments = [way]
        process.environment = ProcessInfo.processInfo.environment.merging(["CFFIXED_USER_HOME": home.path, "HOME": home.path]) { $1 }
        let log = TestScratch.temporary("anchor-reentrancy-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(60)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            throw Failure(description: "the child didn't finish in 60 s")
        }
        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        return (process.terminationReason == .uncaughtSignal ? 128 + process.terminationStatus : process.terminationStatus, output)
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = TestScratch.temporary("anchor-reentrancy-child-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try (String(main[..<cut.upperBound]) + harness).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        let executable = scratch.appendingPathComponent("anchor-reentrancy")
        let swift = try SourceCompiler.compile(repository: repository, sources: [mainFile.path] + others,
                                               executable: executable, timeout: 900)
        guard swift.status == 0 else { throw Failure(description: "compiling Sources/AllInOneIME with the harness:\n\(swift.output)") }
        return executable
    }

    /// After main.swift's `let arguments = …`: a controller whose field, asked for its caret, places the panel again once.
    static let harness = #"""

    final class ReenteringField: NSObject, IMKTextInput {
        weak var controller: AllInOneIMEInputController?
        var reentered = false

        private func reenter() {
            guard !reentered, let controller else { return }
            reentered = true
            print("REENTERED")
            fflush(stdout)
            _ = MainActor.assumeIsolated { controller.anchor(self) }  // the key that came in meanwhile shows the panel
        }

        func insertText(_ string: Any!, replacementRange: NSRange) {}
        func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {}
        func selectedRange() -> NSRange { NSRange(location: 3, length: 0) }
        func markedRange() -> NSRange {
            reenter()
            return NSRange(location: NSNotFound, length: 0)
        }
        func attributedSubstring(from range: NSRange) -> NSAttributedString! { nil }
        func length() -> Int { 3 }
        func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode,
                            inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { NSNotFound }
        func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! {
            lineRect?.pointee = .zero  // a rect not to trust, as Chromium tells: the panel is asked again later
            return [:]
        }
        func validAttributesForMarkedText() -> [Any]! { [] }
        func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
        func selectMode(_ modeIdentifier: String!) {}
        func supportsUnicode() -> Bool { true }
        func bundleIdentifier() -> String! { "com.example.host.reentering" }
        func windowLevel() -> CGWindowLevel { CGWindowLevelForKey(.normalWindow) }
        func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
        func uniqueClientIdentifierString() -> String! { "anchor-reentrancy" }
        func string(from range: NSRange, actualRange: NSRangePointer!) -> String! { nil }
        func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect { NSRect(x: 420, y: 560, width: 1, height: 18) }
    }

    MainActor.assumeIsolated {
        guard let controller = AllInOneIMEInputController(server: nil, delegate: nil, client: nil) else {
            print("FAIL no input controller")
            exit(3)
        }
        let field = ReenteringField()
        field.controller = controller
        controller.clientOverride = field
        switch arguments.first {
        case "anchor":
            _ = controller.anchor(field)
        case "reask":
            field.reentered = true
            _ = controller.anchor(field)  // placed once, not trusted: asked again later
            field.reentered = false
            _ = controller.reasked(field, token: controller.anchorToken)
        default:
            print("FAIL way \(arguments.first ?? "")")
            exit(3)
        }
        print("PLACED \(arguments.first ?? "")")
        fflush(stdout)
        exit(0)
    }
    """#
}
