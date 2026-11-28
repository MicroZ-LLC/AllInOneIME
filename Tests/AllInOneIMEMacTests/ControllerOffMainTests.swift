import AllInOneIMETestSupport
import Foundation
import Testing

// The input controller's work moved off the main thread in 0.7.6, as the review of it found it (each test one finding):
// a type-out stopped in a field that tells its text late (Chromium) settles later, from a task, and must still take its
// typo out when the field is left, and type every key pressed meanwhile; what Accessibility tells (a password field
// after a pause, the field's frame for autocomplete's gray text, the panel's window and caret) is read off the main
// thread, and an answer for a placement, a field or a suggestion that is gone by then is not gone by; clipboard
// history's writes are done before the input method ends on SIGTERM.
//
// The input method's code isn't a library: Sources/AllInOneIME is compiled into a child process with main.swift's
// dispatch replaced, as AnchorReentrancyTests does it, once for all of them. Its fields are the child's own; what
// Accessibility answers is the child's (`AllInOneIMEInputController.anchorReaders`, `focusedFieldReaders`). Nothing
// is typed into another app; the panel and the gray text are drawn invisible.

@Suite(.serialized)
struct ControllerOffMainTests {
    /// A type-out with a typo in a field that tells its text 60 ms late, the field left (another field focused) while
    /// the typo is in it and the field doesn't tell it yet: the typo is still taken out, in that field, once it tells it;
    /// the rest isn't typed.
    @Test func leavingTheFieldWhileTheStopSettlesStillTakesTheTypoOut() throws {
        let report = try ControllerOffMainChild.run("blur")
        let typed = report["typed"] ?? ""
        #expect(report["caught"] == "true", "the test missed its moment (no typo the field didn't tell yet): \(report)")
        #expect(ControllerOffMainChild.intended.hasPrefix(typed) && typed.count >= 2,
                "the field holds \"\(typed)\": a typo left in it, or more than was typed before leaving")
        #expect(typed != ControllerOffMainChild.intended, "the rest was typed after the field was left")
        #expect(report["typingOut"] == "false", "still typing out: \(report)")
    }

    /// The same typo, the field telling it late, and three letters typed 15 ms apart while the stop settles: every key is
    /// typed once it settles, after the rest, in order, as the same keys typed after a type-out would be.
    @Test func keysTypedWhileTheStopSettlesAreTypedOnceItDoes() throws {
        let control = try ControllerOffMainChild.run("control")
        let report = try ControllerOffMainChild.run("keys")
        #expect(report["caught"] == "true", "the test missed its moment (no typo the field didn't tell yet): \(report)")
        let after = control["typed"] ?? ""
        #expect(report["typed"] == ControllerOffMainChild.intended + after,
                "the field holds \"\(report["typed"] ?? "")\", not the whole text and then \"\(after)\"")
        #expect(report["input"] == control["input"], "what is being typed is \"\(report["input"] ?? "")\", not \"\(control["input"] ?? "")\"")
        #expect(report["typingOut"] == "false" && report["fixKept"] == "true", "\(report)")
    }

    /// A letter and then ⏎ while the stop settles: ⏎ can't wait (the app may have to have it: a chat's send), so the stop
    /// settles at once with the field as it looks, the letter goes in first, then ⏎, as the same keys after a type-out.
    @Test func returnWhileTheStopSettlesSettlesItAndNoKeyIsLost() throws {
        let control = try ControllerOffMainChild.run("control-return")
        let report = try ControllerOffMainChild.run("keys-return")
        #expect(report["caught"] == "true", "the test missed its moment (no typo the field didn't tell yet): \(report)")
        let after = control["typed"] ?? ""
        let typed = report["typed"] ?? ""
        #expect(!after.isEmpty && typed.hasSuffix(after), "the field holds \"\(typed)\", not ending in \"\(after)\"")
        // Settled at once, a typo the field didn't tell yet may stay: one character off at most, nothing lost.
        let text = String(typed.dropLast(after.count))
        #expect(ControllerOffMainChild.oneEditApart(text, ControllerOffMainChild.intended), "the text typed out is \"\(text)\"")
        #expect(report["typingOut"] == "false" && report["fixKept"] == "true", "\(report)")
    }

    /// The field read once typing pauses (autocomplete's, Code's words): whether it is a password field is asked of
    /// Accessibility off the main thread (it may wait half a second on an app slow to answer), and the read still comes.
    @Test func thePauseReadAsksAccessibilityOffTheMainThread() throws {
        let report = try ControllerOffMainChild.run("pause")
        #expect(report["onMain"] == "0", "Accessibility asked on the main thread \(report["onMain"] ?? "?") times: \(report)")
        #expect(Int(report["offMain"] ?? "") ?? 0 >= 1, "never asked: \(report)")
        #expect(report["read"] == "true", "the field's read after the pause never came: \(report)")
        // Asked of the app being typed in (the field's), not of whichever app's element is focused system-wide.
        #expect(Int(report["ofTheFieldsApp"] ?? "") ?? 0 >= 1 && report["ofAnother"] == "0", "\(report)")
    }

    /// Whether the field is a password field, asked as it takes the focus (`SessionOutput.readPasswordField`): asked of
    /// the app being typed in, off the main thread; where no app is told, or none runs by its id, the answer is
    /// "can't tell", never "none" (the review of 0.7.6's privacy fixes, 4A: the system-wide focused element was asked,
    /// which as the focus goes from one app to another may still be the app's before). And never while secure input is
    /// on (4B).
    @Test func thePasswordFieldIsAskedOfTheAppBeingTypedIn() throws {
        let report = try ControllerOffMainChild.run("password-field")
        #expect(report["onMain"] == "0" && report["ofTheFieldsApp"] == "1" && report["ofAnother"] == "0", "\(report)")
        #expect(report["noApp"] == "unknown" && report["notRunning"] == "unknown", "\(report)")
        #expect(report["askedInSecureInput"] == "0", "Accessibility asked while secure input is on: \(report)")
    }

    /// Clear History just before SIGTERM (an update, `make install`, logging out), its deletion still queued behind a
    /// slow read: done before the input method ends, which is within the termination's two seconds.
    @Test func clearHistoryJustBeforeSIGTERMIsDone() throws {
        let folder = TestScratch.temporary("offmain-terminate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("clipboard-history.json")
        let start = Date()
        let result = try ControllerOffMainChild.launch(["terminate", file.path])
        let took = Date().timeIntervalSince(start)
        #expect(result.output.contains("TERMINATING"), "the child never sent the signal:\n\(result.output)")
        #expect(result.status == 0, "exit \(result.status):\n\(result.output)")
        let kept = FileManager.default.fileExists(atPath: file.path)
        #expect(!kept, "the history cleared before SIGTERM is back (\(took) s):\n\(result.output)")
        #expect(took < 10, "\(took) s")
    }

    /// Autocomplete's gray text asks Accessibility for the field's frame off the main thread. A suggestion taken down and
    /// another shown (another field) before the first's answer comes: the first's answer isn't the second's frame, and
    /// the first field isn't asked again for the second's place; the second's answer is kept.
    @Test func aStaleFieldFrameIsNotTakenForTheNewerSuggestion() throws {
        let report = try ControllerOffMainChild.run("ghost")
        #expect(report["shown"] == "true", "the gray text never showed (no screen?): \(report)")
        #expect(report["frame"] == "second", "the field frame kept is \(report["frame"] ?? "?"), not the second's: \(report)")
        #expect(report["firstAskedAgain"] == "false", "the first field was asked for the second's place: \(report)")
    }

    /// The window's frame read off the main thread for the panel's first placement in a field, its answer in while that
    /// placement still asks the field (an app slow over XPC runs the run loop): it is still learned.
    @Test func theWindowFrameToldDuringTheFirstPlacementIsLearned() throws {
        let report = try ControllerOffMainChild.run("window")
        #expect(report["asked"] == "1", "\(report)")
        #expect(report["during"] == "true", "the answer didn't come while the field was asked (the test missed its moment): \(report)")
        #expect(report["window"] == "learned", "the window's frame was dropped: \(report)")
    }

    /// Without Accessibility allowed, the panel's placement never reads it (nothing would come) and isn't redone for
    /// the nothing that came: one placement, the field asked once.
    @Test func withoutAccessibilityThePanelIsPlacedOnce() throws {
        let report = try ControllerOffMainChild.run("untrusted")
        #expect(report["shown"] == "true", "\(report)")
        #expect(report["caretReads"] == "0", "Accessibility's caret was read without Accessibility allowed: \(report)")
        #expect(report["placements"] == "1", "the panel was placed again for nothing: \(report)")
    }
}

enum ControllerOffMainChild {
    struct Failure: Error, CustomStringConvertible { var description: String }

    /// What the type-outs type (as the child's harness has it).
    static let intended = "Thanks for the quick reply, I will look into it tomorrow morning and get back to you."

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    /// Whether `a` and `b` are the same, or one character substituted, added or left out (the self-test's `oneEditApart`).
    static func oneEditApart(_ a: String, _ b: String) -> Bool {
        let (x, y) = (Array(a), Array(b))
        if x == y { return true }
        let prefix = zip(x, y).prefix { $0 == $1 }.count
        let suffix = zip(x.reversed(), y.reversed()).prefix { $0 == $1 }.count
        return max(x.count, y.count) - min(prefix + suffix, min(x.count, y.count)) <= 1
    }

    /// The child run in `way`: its "REPORT key=value" lines.
    static func run(_ way: String) throws -> [String: String] {
        let result = try launch([way])
        guard result.status == 0 else { throw Failure(description: "the child (\(way)) failed (\(result.status)):\n\(result.output)") }
        var report: [String: String] = [:]
        for line in result.output.split(separator: "\n") where line.hasPrefix("REPORT ") {
            let pair = line.dropFirst("REPORT ".count)
            guard let equals = pair.firstIndex(of: "=") else { continue }
            report[String(pair[..<equals])] = String(pair[pair.index(after: equals)...])
        }
        guard !report.isEmpty else { throw Failure(description: "the child (\(way)) reported nothing:\n\(result.output)") }
        return report
    }

    static func launch(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let executable = try compiled.get()
        let home = TestScratch.temporary("offmain-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["CFFIXED_USER_HOME": home.path, "HOME": home.path]) { $1 }
        let log = TestScratch.temporary("offmain-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: log)
        }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(90)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.5)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw Failure(description: "the child (\(arguments.first ?? "")) didn't finish in 90 s:\n\((try? String(contentsOf: log, encoding: .utf8)) ?? "")")
        }
        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        return (process.terminationReason == .uncaughtSignal ? 128 + process.terminationStatus : process.terminationStatus, output)
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = TestScratch.temporary("offmain-child-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        let mainFile = scratch.appendingPathComponent("main.swift")
        // KeptDraftControllerTests' ways run in the same child (one compile for both suites).
        try (String(main[..<cut.upperBound]) + KeptDraftControllerTests.harness + harness).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        let executable = scratch.appendingPathComponent("offmain")
        let swift = try SourceCompiler.compile(repository: repository, sources: [mainFile.path] + others,
                                               executable: executable, timeout: 900)
        guard swift.status == 0 else { throw Failure(description: "compiling Sources/AllInOneIME with the harness:\n\(swift.output)") }
        return executable
    }

    /// After main.swift's `let arguments = …`: the child's fields and its ways.
    static let harness = #"""

    /// A text field that tells its text and caret `lag` seconds late (Chromium's), each change in the order made: what it
    /// holds (`document`) at once, what it tells (`told`) later. Answering for its caret's line runs the run loop for
    /// `spins` seconds (an app slow to answer over XPC). Counts what it is asked.
    final class OffMainField: NSObject, IMKTextInput {
        var document = ""
        private(set) var told = ""
        var lag: TimeInterval = 0
        var spins: TimeInterval = 0
        var onSpin: (() -> Void)?
        var rect = NSRect(x: 420, y: 560, width: 1, height: 18)
        var app = "com.example.offmain"
        var asked = 0

        func insertText(_ string: Any!, replacementRange: NSRange) {
            let text = (string as? NSAttributedString)?.string ?? string as? String ?? ""
            let whole = document as NSString
            if replacementRange.location != NSNotFound, NSMaxRange(replacementRange) <= whole.length {
                document = whole.replacingCharacters(in: replacementRange, with: text)
            } else {
                document += text
            }
            let now = document
            if lag == 0 { told = now } else { DispatchQueue.main.asyncAfter(deadline: .now() + lag) { self.told = now } }
        }
        func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {}
        func selectedRange() -> NSRange {
            asked += 1
            return NSRange(location: (told as NSString).length, length: 0)
        }
        func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
        func attributedSubstring(from range: NSRange) -> NSAttributedString! {
            let whole = told as NSString
            guard range.location != NSNotFound, NSMaxRange(range) <= whole.length else { return nil }
            return NSAttributedString(string: whole.substring(with: range))
        }
        func length() -> Int { (told as NSString).length }
        func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode,
                            inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { NSNotFound }
        func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable: Any]! {
            asked += 1
            if spins > 0 {
                onSpin?()
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(spins))
            }
            lineRect?.pointee = rect
            return [:]
        }
        func validAttributesForMarkedText() -> [Any]! { [] }
        func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
        func selectMode(_ modeIdentifier: String!) {}
        func supportsUnicode() -> Bool { true }
        func bundleIdentifier() -> String! { app }
        func windowLevel() -> CGWindowLevel { CGWindowLevelForKey(.normalWindow) }
        func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
        func uniqueClientIdentifierString() -> String! { "offmain-\(app)" }
        func string(from range: NSRange, actualRange: NSRangePointer!) -> String! { nil }
        func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect {
            asked += 1
            return rect
        }
    }

    /// Counted from any thread.
    final class OffMainCount: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        func add(_ key: String) { lock.withLock { counts[key, default: 0] += 1 } }
        func get(_ key: String) -> Int { lock.withLock { counts[key] ?? 0 } }
    }

    @MainActor
    enum OffMain {
        static let intended = "Thanks for the quick reply, I will look into it tomorrow morning and get back to you."
        static var controller: AllInOneIMEInputController!

        static func say(_ key: String, _ value: Any) {
            print("REPORT \(key)=\(value)")
            fflush(stdout)
        }

        /// The run loop run for `seconds` at most, until `done`.
        @discardableResult
        static func pump(_ seconds: TimeInterval, until done: () -> Bool = { false }) -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if done() { return true }
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.002))
            }
            return done()
        }

        /// A controller of English only (no pinyin engine), typing out with typos (one wherever one may be), 30 ms apart.
        static func make() {
            guard let made = AllInOneIMEInputController(server: nil, delegate: nil, client: nil) else {
                print("FAIL no input controller")
                exit(3)
            }
            controller = made
            var config = Config.default
            config.setOrder([Language.english])
            config.typeOutMistakes = true
            config.autocomplete = false
            // No Raycast scripts of the Mac's: Spotlight isn't asked (it finds Core/Examples/extensions' `@wordcount` in
            // every copy of this repository there), nor are the folders an earlier child found read back (UserDefaults
            // are every child's, CFFIXED_USER_HOME doesn't move them): a rebuild took them in, in time for an "@" or not.
            config.findRaycastScripts = false
            LiveExtensions.shownFound = []
            controller.services.loadSettings = { config }
            controller.services.secureInputActive = { false }
            controller.applySettings()
            LearnedShared.store = LearnedStore(file: nil, autocomplete: AutocompleteStore(), temperature: TemperatureSupport(file: nil))
            (GhostOverlay.invisible, CandidatePanel.invisible) = (true, true)
            KeyGuard.shared.disabled = true  // no key tap, no pointer monitor: the child's keys are its own
            _ = NSApplication.shared
        }

        /// A key down as the app hands it over; one the input method doesn't take, the app types (`characters`).
        static func press(_ characters: String, code: UInt16, into field: OffMainField) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                         isARepeat: false, keyCode: code)!
            if !controller.handle(event, client: field) { field.insertText(characters, replacementRange: NSRange(location: NSNotFound, length: 0)) }
        }

        /// `intended` typed out into `field`, until a typo is in it that the field doesn't tell yet: whether one came. A
        /// step every 100 ms, the field 60 ms late: caught up at each step, so a typo may start (`TypeOut.Typist.step`).
        static func typeOutToATypo(_ field: OffMainField) -> Bool {
            controller.typeOutRandom = { 0.001 }
            controller.typeOutSleep = { _ in try? await Task.sleep(nanoseconds: 100_000_000) }
            field.lag = 0.06
            controller.apply([.typeOut(intended)], client: field)
            return pump(10) { !intended.hasPrefix(field.document) && field.told != field.document }
        }

        static func blur() {
            make()
            let field = OffMainField()
            let caught = typeOutToATypo(field)
            controller.deactivateServer(field)
            pump(3) { !controller.isTypingOut }
            pump(0.3)
            say("caught", caught)
            say("typed", field.document)
            say("typingOut", controller.isTypingOut)
        }

        static let keys: [(String, UInt16)] = [("a", 0), ("b", 11), ("c", 8)]
        static let keysThenReturn: [(String, UInt16)] = [("a", 0), ("\r", 36)]

        static func control(_ keys: [(String, UInt16)]) {
            make()
            let field = OffMainField()
            for (key, code) in keys {
                press(key, code: code, into: field)
                pump(0.015)
            }
            pump(0.5)
            say("typed", field.document)
            say("input", controller.preedit)
        }

        static func keysWhileSettling(_ keys: [(String, UInt16)]) {
            make()
            let field = OffMainField()
            let caught = typeOutToATypo(field)
            for (key, code) in keys {
                press(key, code: code, into: field)
                pump(0.015)
            }
            pump(3) { !controller.isTypingOut }
            pump(0.5)
            say("caught", caught)
            say("typed", field.document)
            say("input", controller.preedit)
            say("typingOut", controller.isTypingOut)
            say("fixKept", !LearnedShared.store.typosOff(in: field.app))
        }

        static func pause() {
            make()
            let count = OffMainCount()
            let field = OffMainField()
            let app = field.app
            AllInOneIMEInputController.focusedFieldReaders.isSecure = { asked in
                count.add(Thread.isMainThread ? "main" : "off")
                count.add(asked == app ? "app" : "another")
                return false
            }
            field.insertText("hello there", replacementRange: NSRange(location: NSNotFound, length: 0))
            controller.passwordField = nil
            let before = field.asked
            controller.readFieldAfterPause(id: 1, in: field)
            pump(2) { field.asked > before }
            let read = field.asked > before
            pump(0.2)
            say("onMain", count.get("main"))
            say("offMain", count.get("off"))
            say("ofTheFieldsApp", count.get("app"))
            say("ofAnother", count.get("another"))
            say("read", read)
        }

        static func passwordField() {
            make()
            let count = OffMainCount()
            let field = OffMainField()
            let app = field.app
            AllInOneIMEInputController.focusedFieldReaders.isSecure = { asked in
                count.add(Thread.isMainThread ? "main" : "off")
                count.add(asked == app ? "app" : "another")
                return false
            }
            controller.passwordField = nil
            controller.readPasswordField(focus: 1, in: field)
            pump(2) { count.get("off") + count.get("main") > 0 }
            pump(0.2)
            say("onMain", count.get("main"))
            say("ofTheFieldsApp", count.get("app"))
            say("ofAnother", count.get("another"))
            // Accessibility's own answer where the app can't be told: unknown, never "none".
            say("noApp", FocusedField.isSecure(in: nil).map { "\($0)" } ?? "unknown")
            say("notRunning", FocusedField.isSecure(in: "com.example.not-running").map { "\($0)" } ?? "unknown")
            // Secure input on: nothing is asked of Accessibility.
            let asked = count.get("off") + count.get("main")
            let services = controller.services
            controller.services.secureInputActive = { true }
            controller.readPasswordField(focus: 2, in: field)
            pump(0.3)
            controller.services = services
            say("askedInSecureInput", count.get("off") + count.get("main") - asked)
        }

        static func ghost() {
            make()
            let gates = [DispatchSemaphore(value: 0), DispatchSemaphore(value: 0)]
            let count = OffMainCount()
            let screen = NSScreen.screens.first?.frame ?? .zero
            let frames = [NSRect(x: screen.midX - 300, y: screen.midY - 100, width: 600, height: 200),
                          NSRect(x: screen.midX - 250, y: screen.midY - 150, width: 500, height: 300)]
            AllInOneIMEInputController.focusedFieldReaders.frame = { _ in
                let asked = count.get("frame")
                count.add("frame")
                gates[min(asked, 1)].wait()
                return frames[min(asked, 1)]
            }
            let (first, second) = (OffMainField(), OffMainField())
            (first.app, second.app) = ("com.example.first", "com.example.second")
            first.rect = NSRect(x: screen.midX - 200, y: screen.midY, width: 1, height: 18)
            second.rect = NSRect(x: screen.midX - 150, y: screen.midY - 40, width: 1, height: 18)
            controller.placeGhost("first suggestion", in: first)
            let shown = GhostOverlay.shared.isVisible
            controller.hideGhost()
            controller.placeGhost("second suggestion", in: second)
            let firstAsked = first.asked
            gates[0].signal()
            pump(0.3)
            gates[1].signal()
            pump(0.3)
            say("shown", shown && GhostOverlay.shared.isVisible)
            let kept = controller.ghostField ?? nil
            say("frame", kept == frames[1] ? "second" : kept == frames[0] ? "first" : "\(String(describing: kept))")
            say("firstAskedAgain", first.asked != firstAsked)
            say("reads", count.get("frame"))
        }

        static func window() {
            make()
            let count = OffMainCount()
            let frame = CGRect(x: 100, y: 100, width: 900, height: 700)
            var readers = AnchorReaders()
            readers.trusted = { true }
            readers.process = { _ in 4242 }
            readers.listedWindow = { _ in nil }
            readers.windowFrame = { _, _ in
                count.add("window")
                return (frame, false)
            }
            readers.caret = { _, _, _ in nil }
            AllInOneIMEInputController.anchorReaders = readers
            let field = OffMainField()
            field.rect = NSRect(x: 420, y: 560, width: 1, height: 18)
            // The field answers for its line slowly the first time, running the run loop: the window's answer comes then.
            var during = false
            field.spins = 0.1
            field.onSpin = {
                field.spins = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { during = count.get("window") > 0 }
            }
            _ = controller.anchor(field)
            pump(0.3)
            say("asked", count.get("window"))
            say("during", during)
            say("window", controller.panelAnchor.window == frame ? "learned" : "\(String(describing: controller.panelAnchor.window))")
        }

        static func untrusted() {
            make()
            let count = OffMainCount()
            var readers = AnchorReaders()
            readers.trusted = { false }
            readers.process = { _ in 4242 }
            readers.listedWindow = { _ in CGRect(x: 0, y: 0, width: 1200, height: 800) }
            readers.windowFrame = { _, _ in nil }
            readers.caret = { _, _, _ in
                count.add("caret")
                return nil  // as FocusedField.caret answers without Accessibility allowed
            }
            AllInOneIMEInputController.anchorReaders = readers
            let field = OffMainField()
            field.rect = .zero  // a rect not to trust, as Chromium tells: Accessibility would be asked
            CandidatePanel.shared.take(by: controller, .session({ _ in }))
            let before = controller.placements
            controller.show(.notice("a notice"), anchoredIn: field)
            let shown = CandidatePanel.shared.isShowing
            pump(0.4)
            say("shown", shown)
            say("caretReads", count.get("caret"))
            say("placements", controller.placements - before)
        }

        /// Clear History queued behind a slow read of the history's file, SIGTERM 50 ms later.
        static func terminate(_ path: String) {
            let url = URL(fileURLWithPath: path)
            let first = ClipboardHistoryStore(url: url)
            first.record("a copy", at: Date(), limit: 20)
            first.waitForWrites()
            guard FileManager.default.fileExists(atPath: path) else {
                print("FAIL the history's file wasn't written")
                exit(3)
            }
            let held = Date().addingTimeInterval(0.35)
            let store = ClipboardHistoryStore(url: url, readFile: { url in
                while Date() < held { usleep(5_000) }
                return try? Data(contentsOf: url)
            })
            store.clear()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                print("TERMINATING")
                fflush(stdout)
                terminationSignal.resume()
                kill(getpid(), SIGTERM)
            }
            withExtendedLifetime(store) { RunLoop.main.run(until: Date().addingTimeInterval(5)) }
            print("FAIL still running 5 s after SIGTERM")
            exit(4)
        }
    }

    MainActor.assumeIsolated {
        switch arguments.first {
        case "blur": OffMain.blur()
        case "control": OffMain.control(OffMain.keys)
        case "keys": OffMain.keysWhileSettling(OffMain.keys)
        case "control-return": OffMain.control(OffMain.keysThenReturn)
        case "keys-return": OffMain.keysWhileSettling(OffMain.keysThenReturn)
        case "pause": OffMain.pause()
        case "password-field": OffMain.passwordField()
        case "ghost": OffMain.ghost()
        case "window": OffMain.window()
        case "untrusted": OffMain.untrusted()
        case "terminate": OffMain.terminate(arguments.count > 1 ? arguments[1] : "")
        default:
            guard KeptDrafts.run(arguments.first ?? "") else {
                print("FAIL way \(arguments.first ?? "")")
                exit(3)
            }
        }
        fflush(stdout)
        exit(0)
    }
    """#
}
