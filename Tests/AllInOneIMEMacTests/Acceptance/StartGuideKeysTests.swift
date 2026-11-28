import AllInOneIMECore
import Foundation
import Testing

// The start guide's step 3 types the magic key (on entering the step) and "@" + an example (its buttons) into its field
// as key events posted to the session, so that the input method sees them (#198). Two defects:
//
//   1. An example clicked while the @ list is open with a draft stacks the example onto that draft: the view empties
//      the field editor, but the input method's draft is left as it was. Required: an example click first cancels any
//      open @ draft and panel with exactly TWO leading Escape key strokes (key code 0x35, no characters) before the
//      trigger, so the field ends as "@" + that example only. The plain trigger typed on entering the step posts no
//      Escape.
//   2. The keys are posted with US-layout key codes, and only the characters with no key (明) carry a unicode string,
//      so a non-US layout types other characters. Required: every character stroke carries its own character as the
//      event's unicode string (CGEventKeyboardSetUnicodeString), keeping its key code (the input method tells keys by
//      their key code and usage, and reads the text from the characters) and its Shift flag.
//
// What Esc does in the @ list (read in Core/Sources/AllInOneIMECore/Composer+OneAt.swift, `handleOneAtKey`): with
// text typed after the trigger it does NOT discard the draft: it puts it in as typed (`finishOneAsTyped`, "Esc leaves
// the text as typed"); the trigger alone is given up (the draft emptied); with a selection nothing goes in. But in a
// command's result list (`Composer.swift`, `phase == .choosing`) one Esc only goes back to the draft (`backToDraft`),
// so ONE Escape cannot cancel there: it leaves the draft open, and the example would stack onto it. Hence two (decided
// by the owner's coordinator): the first drops a result list back to the draft; the second gives the draft up, or puts
// it in as typed, which leaves the old "@…" in the field: the view (not these tests) has to clear the field once the
// Escapes are handled, before the trigger arrives. No other key cancels a draft without putting it in: the only path
// that drops it outright is the app's `cancelComposition` (`SessionEvent.cancel`), which is no key, and the view's
// `discardMarkedText()` leaves the draft as it is today (defect 1). Escape, the panels' cancel key, is used as asked.
//
// The code has no seam for this, so this file pins a CONTRACT the implementer must provide on `StartModel`
// (Sources/AllInOneIME/StartWindow.swift), with the US-layout key tables moved out of StartView so the model has them:
//
//     struct Stroke: Equatable { var keyCode: UInt16; var shift: Bool; var characters: String }
//     static func strokes(for typed: String, cancelFirst: Bool) -> [Stroke]
//         // one Stroke per character of `typed` (the view makes key down and up from each): its key code as today's
//         // US-layout table gives it (`KeyEvent.noKeyCode`, 0xFFFF, for a character with no key such as 明), Shift
//         // where the character takes it, and `characters` that character, always; with `cancelFirst`, exactly two
//         // Strokes more, first: Stroke(keyCode: 0x35, shift: false, characters: "") (Escape), twice (see above).
//     static func shouldCancelFirst(example: String?) -> Bool
//         // true when an example is clicked, false for the plain trigger typed on entering the step.
//
// StartView must post `strokes(for: tryField(...).typed, cancelFirst: shouldCancelFirst(example:))`, setting each
// event's unicode string to the stroke's characters.
//
// Until the contract exists the child fails to compile (the first failure); the source test of how StartView posts its
// keys fails on its own today, for defect 2's reason. Offline, free, deterministic: nothing is posted, no window shown.

@Suite(.serialized)
struct StartGuideKeysTests {
    static let repository = StartWindowChild.repository

    struct Stroke: Equatable, CustomStringConvertible {
        var keyCode: UInt16
        var shift: Bool
        var characters: String
        var description: String {
            "(0x\(String(keyCode, radix: 16)), \(shift ? "shift" : "-"), \(characters.debugDescription))"
        }
    }

    static let escape = Stroke(keyCode: VirtualKey.escape, shift: false, characters: "")
    /// What `cancelFirst` puts first: one Escape drops a result list back to the draft, the next gives the draft up.
    static let cancel = [escape, escape]

    /// Today's US-layout table (StartView's), which the contract keeps: letters, digits and marks, without Shift.
    static let keys: [Character: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09,
        "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
        "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18, "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E,
        "o": 0x1F, "u": 0x20, "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
        "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, " ": 0x31, "`": 0x32,
    ]

    // MARK: - Strokes: key codes and Shift

    @Test func lettersTakeTheirUSKeysWithoutShift() throws {
        let letters = "abcdefghijklmnopqrstuvwxyz"
        let report = try Self.ask([Self.strokesArgument(letters, cancelFirst: false)])
        let strokes = try #require(report.strokes(letters, cancelFirst: false), "\(report)")
        let expected = try letters.map { Stroke(keyCode: try #require(Self.keys[$0]), shift: false, characters: String($0)) }
        #expect(strokes == expected, "\(report)")
    }

    @Test func capitalLettersTakeTheSameKeysWithShiftAndKeepTheirCase() throws {
        let typed = "Safari"
        let report = try Self.ask([Self.strokesArgument(typed, cancelFirst: false)])
        let strokes = try #require(report.strokes(typed, cancelFirst: false), "\(report)")
        #expect(strokes == [
            Stroke(keyCode: 0x01, shift: true, characters: "S"), Stroke(keyCode: 0x00, shift: false, characters: "a"),
            Stroke(keyCode: 0x03, shift: false, characters: "f"), Stroke(keyCode: 0x00, shift: false, characters: "a"),
            Stroke(keyCode: 0x0F, shift: false, characters: "r"), Stroke(keyCode: 0x22, shift: false, characters: "i"),
        ], "\(report)")
    }

    @Test func digitsTakeTheirUSKeysWithoutShift() throws {
        let digits = "0123456789"
        let report = try Self.ask([Self.strokesArgument(digits, cancelFirst: false)])
        let strokes = try #require(report.strokes(digits, cancelFirst: false), "\(report)")
        let codes: [UInt16] = [0x1D, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19]
        #expect(strokes == zip(digits, codes).map { Stroke(keyCode: $1, shift: false, characters: String($0)) }, "\(report)")
    }

    /// The marks the examples and the magic key use, on their digit or "=" key with Shift; "=" itself without.
    @Test func shiftedMarksTakeShift() throws {
        let typed = "@*%+="
        let report = try Self.ask([Self.strokesArgument(typed, cancelFirst: false)])
        let strokes = try #require(report.strokes(typed, cancelFirst: false), "\(report)")
        #expect(strokes == [
            Stroke(keyCode: 0x13, shift: true, characters: "@"), Stroke(keyCode: 0x1C, shift: true, characters: "*"),
            Stroke(keyCode: 0x17, shift: true, characters: "%"), Stroke(keyCode: 0x18, shift: true, characters: "+"),
            Stroke(keyCode: 0x18, shift: false, characters: "="),
        ], "\(report)")
    }

    @Test func aCharacterWithNoKeyHasNoKeyCodeAndCarriesItself() throws {
        let typed = "明天下午三点开会"
        let report = try Self.ask([Self.strokesArgument("明", cancelFirst: false), Self.strokesArgument(typed, cancelFirst: false)])
        #expect(report.strokes("明", cancelFirst: false) == [Stroke(keyCode: KeyEvent.noKeyCode, shift: false, characters: "明")],
                "\(report)")
        #expect(report.strokes(typed, cancelFirst: false)
                == typed.map { Stroke(keyCode: KeyEvent.noKeyCode, shift: false, characters: String($0)) }, "\(report)")
    }

    // MARK: - Strokes: each carries its own character (defect 2)

    @Test func everyStrokeCarriesItsOwnCharacter() throws {
        let typed = ["@200*15%", "@明天下午三点开会", "@safari", "~Safari", "Hello, World! 1+1=2 (#3) ~`\\|\"'<>?_{}[]"]
        let report = try Self.ask(typed.flatMap { [Self.strokesArgument($0, cancelFirst: false),
                                                   Self.strokesArgument($0, cancelFirst: true)] })
        for text in typed {
            for cancelFirst in [false, true] {
                let strokes = try #require(report.strokes(text, cancelFirst: cancelFirst), "\(text): \(report)")
                let characters = cancelFirst ? Array(strokes.dropFirst(Self.cancel.count)) : strokes
                #expect(characters.count == text.count, "\(text), cancelFirst \(cancelFirst): \(strokes)")
                for (stroke, character) in zip(characters, text) {
                    #expect(stroke.characters == String(character), "\(text), \(character): \(stroke)")
                }
                #expect(characters.map(\.characters).joined() == text, "\(text), cancelFirst \(cancelFirst): \(strokes)")
            }
        }
    }

    // MARK: - Escape first (defect 1)

    @Test func cancelFirstAddsExactlyTwoEscapesFirst() throws {
        let typed = ["@", "@200*15%", "~明天下午三点开会"]
        let report = try Self.ask(typed.flatMap { [Self.strokesArgument($0, cancelFirst: false),
                                                   Self.strokesArgument($0, cancelFirst: true)] })
        for text in typed {
            let plain = try #require(report.strokes(text, cancelFirst: false), "\(text): \(report)")
            let cancelling = try #require(report.strokes(text, cancelFirst: true), "\(text): \(report)")
            #expect(cancelling == Self.cancel + plain, "\(text): \(cancelling) against \(plain)")
            #expect(cancelling.prefix { $0 == Self.escape }.count == 2, "\(text): not exactly two Escapes first: \(cancelling)")
            #expect(!plain.contains { $0.keyCode == VirtualKey.escape }, "\(text): an Escape without cancelFirst: \(plain)")
        }
        // The contract's own initializer and equality, as the child sees them: the leading Escapes it counts.
        #expect(report.values["ESC\t1\t" + Self.base64("@")] == "2", "\(report)")
        #expect(report.values["ESC\t0\t" + Self.base64("@")] == "0", "\(report)")
    }

    @Test func anExampleClickCancelsFirstAndStepEntryDoesNot() throws {
        let report = try Self.ask(Self.examples.map { "sc\t" + $0 } + ["sc\t" + StartWindowChild.none])
        for example in Self.examples {
            #expect(report.values["SC\t" + example] == "1", "\(example): \(report)")
        }
        #expect(report.values["SC\t" + StartWindowChild.none] == "0", "step entry: \(report)")
    }

    /// The view's whole path: the field's keys (`tryField`), cancelled first as `shouldCancelFirst` says: an example's
    /// button posts Escape twice, then exactly the trigger and the example; entering the step posts the trigger alone.
    @Test func anExampleClickSpellsTwoEscapesThenTriggerAndExampleOnly() throws {
        let triggers = ["@", "~"]
        let report = try Self.ask(triggers.flatMap { trigger in
            (Self.examples + [StartWindowChild.none]).map { "click\t\(trigger)\t\($0)" }
        })
        for trigger in triggers {
            for example in Self.examples {
                let strokes = try #require(report.click(trigger, example), "\(trigger)\(example): \(report)")
                #expect(Array(strokes.prefix(Self.cancel.count)) == Self.cancel,
                        "\(trigger)\(example): not two Escapes first: \(strokes)")
                let rest = strokes.dropFirst(Self.cancel.count)
                #expect(rest.map(\.characters).joined() == trigger + example, "\(trigger)\(example): \(strokes)")
                #expect(rest.count == (trigger + example).count, "\(trigger)\(example): \(strokes)")
                #expect(!rest.contains { $0.keyCode == VirtualKey.escape }, "\(trigger)\(example): \(strokes)")
            }
            let entry = try #require(report.click(trigger, nil), "\(trigger): \(report)")
            #expect(entry.map(\.characters) == [trigger], "\(trigger) on entering the step: \(entry)")
            #expect(!entry.contains { $0.keyCode == VirtualKey.escape }, "\(trigger) on entering the step: \(entry)")
        }
        #expect(report.click("@", nil) == [Stroke(keyCode: 0x13, shift: true, characters: "@")], "\(report)")
        #expect(report.click("~", nil) == [Stroke(keyCode: 0x32, shift: true, characters: "~")], "\(report)")
        #expect(report.click("@", "safari") == Self.cancel + [Stroke(keyCode: 0x13, shift: true, characters: "@")]
                + "safari".map { Stroke(keyCode: Self.keys[$0] ?? 0, shift: false, characters: String($0)) }, "\(report)")
    }

    // MARK: - The view

    /// Observable today: StartView posts the contract's strokes, each with its characters as the event's unicode
    /// string, whatever its key code (today only a character with no key carries one: `if code == KeyEvent.noKeyCode`).
    @Test func viewPostsEveryStrokeWithItsCharacters() throws {
        let view = try String(contentsOf: Self.repository.appendingPathComponent("Sources/AllInOneIME/StartView.swift"),
                              encoding: .utf8)
        #expect(view.contains("strokes(for:"), "StartView doesn't post StartModel.strokes(for:cancelFirst:)")
        #expect(view.contains("shouldCancelFirst(example:"), "StartView doesn't ask StartModel.shouldCancelFirst(example:)")
        let start = try #require(view.range(of: "func post("), "StartView has no post")
        let rest = view[start.lowerBound...]
        let body = rest.range(of: "\n    }\n").map { rest[..<$0.upperBound] } ?? rest
        #expect(body.contains("keyboardSetUnicodeString"), "post sets no unicode string: \(body)")
        #expect(!body.contains("noKeyCode"), "post still sets the unicode string only for a character with no key: \(body)")
    }

    // MARK: - Child

    /// `StartModel.examples` as the issue names them (the buttons step 3 shows).
    static let examples = ["200*15%", "明天下午三点开会", "safari"]

    static func base64(_ text: String) -> String { Data(text.utf8).base64EncodedString() }

    static func strokesArgument(_ typed: String, cancelFirst: Bool) -> String {
        "st\t\(cancelFirst ? 1 : 0)\t" + base64(typed)
    }

    struct Report: CustomStringConvertible {
        var values: [String: String]
        var description: String

        /// The strokes the child printed under `prefix`: a COUNT line, then a STROKE line each.
        func strokes(_ prefix: String) -> [Stroke]? {
            guard let count = values["COUNT\t" + prefix].flatMap(Int.init) else { return nil }
            var strokes: [Stroke] = []
            for index in 0..<count {
                let fields = values["STROKE\t\(prefix)\t\(index)"]?.split(separator: ",", omittingEmptySubsequences: false)
                guard let fields, fields.count == 3, let code = UInt16(fields[0]),
                      let data = Data(base64Encoded: String(fields[2])),
                      let characters = String(data: data, encoding: .utf8) else { return nil }
                strokes.append(Stroke(keyCode: code, shift: fields[1] == "1", characters: characters))
            }
            return strokes
        }

        func strokes(_ typed: String, cancelFirst: Bool) -> [Stroke]? {
            strokes("st\t\(cancelFirst ? 1 : 0)\t" + StartGuideKeysTests.base64(typed))
        }

        func click(_ trigger: String, _ example: String?) -> [Stroke]? {
            strokes("click\t\(trigger)\t\(example ?? StartWindowChild.none)")
        }
    }

    static let compiled: Result<URL, Error> = Result { try compile() }

    static func ask(_ arguments: [String]) throws -> Report {
        let executable = try compiled.get()
        let result = try StartChildProcess.run(executable, arguments, timeout: 60)
        let text = "(exit \(result.status)):\n\(result.output)"
        if result.status != 0 { throw StartWindowChild.Failure(description: "the child failed " + text) }
        return Report(values: StartChildProcess.values(result.output), description: text)
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("startkeys-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else {
            throw StartWindowChild.Failure(description: "main.swift: no dispatch line")
        }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try (String(main[..<cut.upperBound]) + harness).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        let executable = scratch.appendingPathComponent("startkeys")
        let swift = try SourceCompiler.compile(repository: repository, sources: [mainFile.path] + others,
                                               executable: executable, timeout: 900)
        guard swift.status == 0 else {
            throw StartWindowChild.Failure(description: "compiling Sources/AllInOneIME with the start guide's keys contract:\n\(swift.output)")
        }
        return executable
    }

    /// Asked with `st\t<0|1>\t<base64 typed>` (strokes(for:cancelFirst:)), `sc\t<example|<none>>`
    /// (shouldCancelFirst(example:)) and `click\t<trigger>\t<example|<none>>` (the view's path: tryField's keys, cancelled
    /// first as shouldCancelFirst says). Each stroke as "<key code>,<shift 0|1>,<base64 characters>".
    static let harness = #"""

func printStrokes(_ prefix: String, _ strokes: [StartModel.Stroke]) {
    print("COUNT\t\(prefix)\t\(strokes.count)")
    for (index, stroke) in strokes.enumerated() {
        let code: UInt16 = stroke.keyCode
        let shift: Bool = stroke.shift
        let characters: String = stroke.characters
        print("STROKE\t\(prefix)\t\(index)\t\(code),\(shift ? 1 : 0),\(Data(characters.utf8).base64EncodedString())")
    }
}

MainActor.assumeIsolated {
    for argument in arguments {
        let parts = argument.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        if parts.first == "st", parts.count == 3, let data = Data(base64Encoded: parts[2]),
           let typed = String(data: data, encoding: .utf8) {
            let strokes: [StartModel.Stroke] = StartModel.strokes(for: typed, cancelFirst: parts[1] == "1")
            printStrokes(argument, strokes)
            let escape = StartModel.Stroke(keyCode: 0x35, shift: false, characters: "")
            print("ESC\t\(parts[1])\t\(parts[2])\t\(strokes.prefix { $0 == escape }.count)")
        } else if parts.first == "sc", parts.count == 2 {
            let cancels: Bool = StartModel.shouldCancelFirst(example: parts[1] == "<none>" ? nil : parts[1])
            print("SC\t\(parts[1])\t\(cancels ? 1 : 0)")
        } else if parts.first == "click", parts.count == 3 {
            let example = parts[2] == "<none>" ? nil : parts[2]
            let typed = StartModel.tryField(trigger: parts[1], example: example).typed
            printStrokes(argument, StartModel.strokes(for: typed, cancelFirst: StartModel.shouldCancelFirst(example: example)))
        }
    }
    fflush(stdout)
}
exit(0)
"""#
}
