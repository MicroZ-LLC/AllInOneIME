import AllInOneIMECore
import Foundation
import Testing

// #122: a three-step start instead of "type @improve". The acceptance tests, written from the issue and the
// integrator's contract by an author other than the implementation's (whose changes don't edit them).
//
// "The installer's last dialog says 「…然后在任意输入框里打 @improve」. That teaches a command name, while the point of one @
// (0.7.0) is that after the magic key you type anything and pick from what the list offers. This replaces it with a
// short start that ends with the user trying one @ on a sentence of their own."
//
// The issue's acceptance list, as seen here:
//   1. "Step 1 moves on only when the selected input source becomes AllInOneIME's source ID": `StartModel` starts at
//      step 1 and stays there for any other source ID and for none; ours moves it to step 2 ("Moves to step 2 by itself
//      when the input source becomes AllInOneIME"); shown with ours selected already, it starts at 2; past step 1 a
//      change of input source does nothing.
//   2. "Signing in or Later moves from step 2 to step 3", and neither does anything at step 1 or 3.
//   3. "Each example's text gives the same first one-@ row as the same text typed anywhere": the three examples, in
//      order, and the field's text for each ("Three example buttons each fill in a text after the magic key"; "The field
//      is prefilled with the magic key"), with "@" and with another magic key. Their first rows are the core's
//      (StartExamplesAcceptanceTests, the same three texts).
//   4. "The window shows once per Mac": "Done, Skip or closing the window marks it as seen, in the settings app's own
//      defaults": `StartWindow.shouldShow` is true on fresh defaults, stays true while the steps go by, and is false
//      after `close()` at any step, in the defaults the model was given and no others.
//   5. "An update still opens Settings": the installer's `settingsAppArguments(fresh:)`, `["--start"]` for a fresh
//      install and none for an update.
//   6. "The installer text no longer names `@improve`": `installedDetails(trigger:)` "says that after @ you type
//      anything and pick what to do, in both languages, with the configured trigger": in English and Chinese, with "@"
//      and "~", it has the trigger in it and neither "improve" nor any other command's name after the trigger.
// Not seen here: the window as drawn (its size, the dots, 「1 / 3」, the buttons and their wording), that the sign-in
// buttons make the calls Settings → AI makes, the current input source as shown, the field's focus, that `--start` and
// the notification open the window (and Settings once it was seen), and that AllInOneIME Settings passes `--start` on.
//
// Neither the input method's code nor the installer's can be imported here (executable targets). As Settings120MacTests
// does it, all of Sources/AllInOneIME is compiled into a child process with main.swift's dispatch (what follows
// `let arguments = …`) replaced, and Sources/AllInOneIMEInstaller into another with what follows main.swift's
// `// MARK: Start` replaced: each child prints what the contract's names give. The children's home is a folder of the
// test's, and the defaults a model is given are files in it: nothing reads the user's config or the app's defaults.

@Suite(.serialized)
struct StartWindowMacTests {
    typealias Child = StartWindowChild

    /// AllInOneIME's source ID (rule 3; `InputSourceRegistrar.sourceID` in the app).
    static let ours = "com.allinoneime.inputmethod.AllInOneIME"
    /// Other input sources: Apple's layouts and input methods, and IDs that only look like ours.
    static let others = ["com.apple.keylayout.ABC", "com.apple.keylayout.US", "com.apple.inputmethod.SCIM.ITABC",
                         "com.allinoneime.inputmethod", "com.allinoneime.inputmethod.AllInOneIME.Pinyin",
                         "com.allinoneime.inputmethod.AllInOneIME_Connection", "com.example.inputmethod.AllInOneIME"]

    /// The issue's examples, in the order of step 3's buttons: "a sum (`200*15%`), a time (「明天下午三点开会」), and an app
    /// every Mac has (`safari`, instead of the mockup's `weixin`)".
    static let examples = ["200*15%", "明天下午三点开会", "safari"]

    // MARK: - Step 1 → 2

    /// A model starts at step 1, and shown with another input source selected (or none told) it is at step 1.
    @Test func theStartBeginsAtStepOne() throws {
        let scripts = [Child.Script(Self.ours, [])] + ([nil] + Self.others).map { Child.Script(Self.ours, [.start($0)]) }
        let report = try Child.run(scripts)
        for script in scripts {
            let steps = try #require(report.steps(script), "\(script): \(report)")
            #expect(steps.allSatisfy { $0 == 1 }, "\(script): steps \(steps)")
        }
    }

    /// "Moves to step 2 by itself when the input source becomes AllInOneIME": at step 1, our source ID moves to step 2.
    @Test func ourInputSourceMovesStepOneToStepTwo() throws {
        let script = Child.Script(Self.ours, [.start("com.apple.keylayout.ABC"), .source(Self.ours)])
        let report = try Child.run([script])
        #expect(report.steps(script) == [1, 1, 2], "\(script): \(report)")
    }

    /// "Step 1 moves on only when the selected input source becomes AllInOneIME's source ID": any other ID, one that
    /// looks like ours, or none, leaves it at step 1, each alone and all in a row; ours after them still moves on.
    @Test func noOtherInputSourceMovesStepOne() throws {
        let alone = ([nil] + Self.others).map { Child.Script(Self.ours, [.start(nil), .source($0)]) }
        let inARow = Child.Script(Self.ours, [.start(nil)] + ([nil] + Self.others).map { .source($0) } + [.source(Self.ours)])
        let report = try Child.run(alone + [inARow])
        for script in alone {
            #expect(report.steps(script) == [1, 1, 1], "\(script): \(report.steps(script) ?? [])")
        }
        let steps = try #require(report.steps(inARow), "\(inARow): \(report)")
        #expect(steps.dropLast().allSatisfy { $0 == 1 } && steps.last == 2, "\(inARow): steps \(steps)")
    }

    /// The source ID is the one the model was made with (`ourSourceID`): a model made with another ID moves on for that
    /// one, and not for the app's.
    @Test func theSourceIDIsTheOneTheModelWasGiven() throws {
        let given = "com.example.inputmethod.Given"
        let script = Child.Script(given, [.start(nil), .source(Self.ours), .source(given)])
        let already = Child.Script(given, [.start(Self.ours)])
        let report = try Child.run([script, already])
        #expect(report.steps(script) == [1, 1, 1, 2], "\(script): \(report)")
        #expect(report.steps(already) == [1, 1], "\(already): \(report)")
    }

    /// "starts at 1 (at 2 if the selected input source is ours already)".
    @Test func theStartBeginsAtStepTwoWhenOurInputSourceIsSelectedAlready() throws {
        let script = Child.Script(Self.ours, [.start(Self.ours)])
        let report = try Child.run([script])
        #expect(report.steps(script) == [1, 2], "\(script): \(report)")
    }

    /// Past step 1 a change of input source does nothing: at step 2 another source doesn't go back to step 1 and ours
    /// doesn't move on; at step 3 neither does anything.
    @Test func aChangeOfInputSourceDoesNothingPastStepOne() throws {
        let changes: [Child.Step] = [.source("com.apple.keylayout.ABC"), .source(nil), .source(Self.ours)]
        let atTwo = Child.Script(Self.ours, [.start(Self.ours)] + changes)
        let atThree = Child.Script(Self.ours, [.start(Self.ours), .later] + changes)
        let report = try Child.run([atTwo, atThree])
        #expect(report.steps(atTwo) == [1, 2, 2, 2, 2], "\(atTwo): \(report)")
        #expect(report.steps(atThree) == [1, 2, 3, 3, 3, 3], "\(atThree): \(report)")
    }

    // MARK: - Step 2 → 3

    /// "Signing in moves on. 「稍后再说」 / "Later" moves on too, since typing works without signing in": each moves step 2
    /// to step 3, whether step 2 was reached by switching or was where the start began.
    @Test func signingInOrLaterMovesStepTwoToStepThree() throws {
        var scripts: [Child.Script] = []
        for move in [Child.Step.signedIn, .later] {
            scripts.append(Child.Script(Self.ours, [.start(Self.ours), move]))
            scripts.append(Child.Script(Self.ours, [.start(nil), .source(Self.ours), move]))
        }
        let report = try Child.run(scripts)
        for script in scripts {
            let steps = try #require(report.steps(script), "\(script): \(report)")
            #expect(steps.dropLast().last == 2 && steps.last == 3, "\(script): steps \(steps)")
        }
    }

    /// "at 1 or 3 they do nothing": neither skips step 1 (the input source still has to become ours), and at step 3
    /// neither moves anywhere.
    @Test func signingInAndLaterDoNothingAtStepOneOrThree() throws {
        let atOne = Child.Script(Self.ours, [.start(nil), .signedIn, .later, .signedIn, .source(Self.ours)])
        let atThree = Child.Script(Self.ours, [.start(Self.ours), .signedIn, .signedIn, .later, .signedIn])
        let report = try Child.run([atOne, atThree])
        #expect(report.steps(atOne) == [1, 1, 1, 1, 1, 2], "\(atOne): \(report)")
        #expect(report.steps(atThree) == [1, 2, 3, 3, 3, 3], "\(atThree): \(report)")
    }

    // MARK: - Shown once

    /// "The window shows once per Mac": `shouldShow` is true on fresh defaults and false once marked seen
    /// (`StartWindow.markSeen`), under the contract's key.
    @Test func theStartShowsUntilItIsMarkedSeen() throws {
        let script = Child.Script(Self.ours, [.markSeen])
        let report = try Child.run([script], facts: true)
        #expect(report.value("SEENKEY") == "startSeen", "\(report)")
        #expect(report.shows(script) == [true, false], "\(script): \(report)")
        #expect(report.value("KEPT", script.argument) == "1", "nothing kept under the key: \(report)")
    }

    /// "Done, Skip or closing the window marks it as seen": `close()` at step 1 (Skip), step 2 (the window closed) and
    /// step 3 (Done); until then it would still show, whatever steps went by; after it, it doesn't, again or ever.
    @Test func closingAtAnyStepMarksTheStartSeen() throws {
        let scripts = [Child.Script(Self.ours, [.start(nil), .close]),
                       Child.Script(Self.ours, [.start(nil), .source(Self.ours), .close]),
                       Child.Script(Self.ours, [.start(Self.ours), .signedIn, .close]),
                       Child.Script(Self.ours, [.start(nil), .source(Self.ours), .later, .close, .close])]
        let report = try Child.run(scripts)
        for script in scripts {
            let shows = try #require(report.shows(script), "\(script): \(report)")
            let closed = try #require(script.steps.firstIndex(of: .close))
            // One more than the steps: the first is before any of them.
            #expect(shows.prefix(closed + 1).allSatisfy { $0 }, "\(script): seen before it was closed: \(shows)")
            #expect(shows.dropFirst(closed + 1).allSatisfy { !$0 }, "\(script): still shown after close(): \(shows)")
            #expect(report.value("KEPT", script.argument) == "1", "\(script): nothing kept under the key: \(report)")
        }
    }

    /// "in the settings app's own defaults": the defaults the model was given, a suite of the test's here; another
    /// suite, and the process's own, still say to show it.
    @Test func closingMarksOnlyTheDefaultsTheModelWasGiven() throws {
        let script = Child.Script(Self.ours, [.start(Self.ours), .later, .close])
        let report = try Child.run([script])
        #expect(report.shows(script)?.last == false, "\(script): \(report)")
        #expect(report.value("ELSEWHERE", script.argument) == "1", "another suite was marked seen: \(report)")
        #expect(report.value("STANDARD", script.argument) == "1", "the process's own defaults were marked seen: \(report)")
    }

    // MARK: - Step 3's field and examples

    /// "Three example buttons each fill in a text after the magic key: a sum (`200*15%`), a time (「明天下午三点开会」), and
    /// an app every Mac has (`safari`…)", in that order.
    @Test func theExamplesAreASumATimeAndAnApp() throws {
        let report = try Child.run([], facts: true)
        #expect(report.value("EXAMPLES") == String(Self.examples.count), "\(report)")
        for (index, example) in Self.examples.enumerated() {
            #expect(report.value("EXAMPLE", String(index)) == example, "example \(index + 1): \(report)")
        }
    }

    /// "The field is prefilled with the magic key (`commandTrigger`)": with no example the field's text is the trigger
    /// alone, whichever it is.
    @Test func theFieldIsPrefilledWithTheMagicKey() throws {
        let report = try Child.run([], fields: ["@", "~"].map { Child.Field($0, nil) })
        #expect(report.field("@", nil) == "@", "\(report)")
        #expect(report.field("~", nil) == "~", "\(report)")
    }

    /// "Three example buttons each fill in a text after the magic key": the trigger followed by the example
    /// (`"@200*15%"`), with "@" and with another magic key.
    @Test func anExampleFillsInItsTextAfterTheMagicKey() throws {
        let triggers = ["@", "~"]
        let report = try Child.run([], fields: triggers.flatMap { trigger in Self.examples.map { Child.Field(trigger, $0) } })
        #expect(report.field("@", "200*15%") == "@200*15%", "\(report)")
        for trigger in triggers {
            for example in Self.examples {
                #expect(report.field(trigger, example) == trigger + example, "\(trigger) \(example): \(report)")
            }
        }
    }

    // MARK: - The installer

    /// "The installer's last-dialog button … opens it on a fresh install. An update opens Settings as before":
    /// AllInOneIME Settings is opened with `--start` after a fresh install, and with no argument after an update.
    @Test func theInstallerOpensTheStartOnAFreshInstallAndSettingsOnAnUpdate() throws {
        let report = try StartInstallerChild.run(interface: "en", triggers: [])
        #expect(report.value("ARGS", "fresh") == "1:--start", "a fresh install: \(report)")
        #expect(report.value("ARGS", "update") == "0:", "an update: \(report)")
    }

    /// "The installer's dialog text says that after @ you type anything and pick what to do, in both languages, with the
    /// configured trigger, instead of naming `@improve`": in English and in Chinese, with "@" and with "~" the magic
    /// key, the text never has "improve" in it (nor any other command's name after the magic key), and has the trigger.
    @Test func theInstallersTextNamesTheMagicKeyAndNoCommand() throws {
        let triggers = ["@", "~"]
        for (interface, probe) in [("en", "Cancel"), ("zh", "取消")] {
            let report = try StartInstallerChild.run(interface: interface, triggers: triggers)
            // The child's interface language is the one asked for (its Cancel button's title).
            try #require(report.value("PROBE") == probe, "the installer isn't in \(interface): \(report)")
            for trigger in triggers {
                let text = try #require(report.details(trigger), "\(interface), \(trigger): no text: \(report)")
                #expect(!text.isEmpty, "\(interface), \(trigger): no text")
                #expect(text.range(of: "improve", options: .caseInsensitive) == nil, "\(interface), \(trigger): names improve: \(text)")
                #expect(text.contains(trigger), "\(interface), \(trigger): no magic key in: \(text)")
                // "with the configured trigger": another magic key than "@" leaves no "@" to type.
                if trigger != "@" { #expect(!text.contains("@"), "\(interface), \(trigger): says @: \(text)") }
                for command in Command.builtins {
                    #expect(text.range(of: trigger + command.name, options: .caseInsensitive) == nil,
                            "\(interface), \(trigger): names \(trigger)\(command.name): \(text)")
                }
                // In the interface language.
                let han = text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
                #expect(han == (interface == "zh"), "\(interface), \(trigger): not in the interface language: \(text)")
            }
        }
    }
}

// MARK: - The input method's child

enum StartWindowChild {
    /// What is done to a `StartModel`, in order: the window shown with an input source selected (`start`), the input
    /// source changed (`source`), signed in, Later, the window closed, or the start marked seen without a model
    /// (`StartWindow.markSeen`). An ID of nil: no input source told.
    enum Step: Hashable, CustomStringConvertible, Sendable {
        case start(String?), source(String?), signedIn, later, close, markSeen

        var description: String {
            switch self {
            case let .start(id): return "start=" + (id ?? "nil")
            case let .source(id): return "source=" + (id ?? "nil")
            case .signedIn: return "signedIn"
            case .later: return "later"
            case .close: return "close"
            case .markSeen: return "markSeen"
            }
        }
    }

    /// A model made with `ours` as its source ID and fresh defaults (a suite of its own), then `steps`.
    struct Script: Hashable, CustomStringConvertible, Sendable {
        var ours: String
        var steps: [Step]
        init(_ ours: String, _ steps: [Step]) { (self.ours, self.steps) = (ours, steps) }
        /// As the child is asked, and as it names the script in its answers.
        var argument: String { "script " + ours + " " + steps.map(\.description).joined(separator: " ") }
        var description: String { argument }
    }

    /// The field's text asked for: a trigger and an example (nil: none).
    struct Field: Hashable, Sendable {
        var trigger: String
        var example: String?
        init(_ trigger: String, _ example: String?) { (self.trigger, self.example) = (trigger, example) }
        var argument: String { "field\t" + trigger + "\t" + (example ?? StartWindowChild.none) }
    }

    /// No example, as the child is asked.
    static let none = "<none>"

    /// What the child printed: each line a tag, its keys and a value, tab-separated.
    struct Report: CustomStringConvertible {
        var values: [String: String]
        var status: Int32
        var output: String
        /// The value of the line `tag` with these keys.
        func value(_ tag: String, _ keys: String...) -> String? { values[([tag] + keys).joined(separator: "\t")] }
        /// The model's step when made, then after each of the script's steps.
        func steps(_ script: Script) -> [Int]? {
            value("STEPS", script.argument).map { $0.split(separator: ",").compactMap { Int($0) } }
        }
        /// `StartWindow.shouldShow` of the script's defaults when fresh, then after each of the script's steps.
        func shows(_ script: Script) -> [Bool]? {
            value("SHOWS", script.argument).map { $0.split(separator: ",").map { $0 == "1" } }
        }
        func field(_ trigger: String, _ example: String?) -> String? { value("FIELD", trigger, example ?? StartWindowChild.none) }
        var description: String { "(the child exited \(status)):\n\(output)" }
    }

    struct Failure: Error, CustomStringConvertible { var description: String }

    static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let compiled: Result<URL, Error> = Result { try compile() }

    /// The child run with `scripts`, the fields asked for and (with `facts`) the examples and the key, what it printed
    /// read back.
    static func run(_ scripts: [Script], fields: [Field] = [], facts: Bool = false) throws -> Report {
        let executable = try compiled.get()
        let arguments = (facts ? ["facts"] : []) + scripts.map(\.argument) + fields.map(\.argument)
        let result = try StartChildProcess.run(executable, arguments, timeout: 60)
        let report = Report(values: StartChildProcess.values(result.output), status: result.status, output: result.output)
        if result.status != 0 { throw Failure(description: "the child failed \(report)") }
        return report
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("start122-child-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIME")
        // main.swift as written up to its dispatch, then the harness.
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        let dispatch = "\nlet arguments = Array(CommandLine.arguments.dropFirst())\n"
        guard let cut = main.range(of: dispatch) else { throw Failure(description: "main.swift: no `\(dispatch.dropFirst().dropLast())`") }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try (String(main[..<cut.upperBound]) + StartWindowHarness.swift).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        // The Mac library, the core and librime's wrapper, as `swift test` built them.
        let executable = scratch.appendingPathComponent("start122")
        let swift = try SourceCompiler.compile(repository: repository, sources: [mainFile.path] + others,
                                               executable: executable, timeout: 900)
        guard swift.status == 0 else { throw Failure(description: "compiling Sources/AllInOneIME with the harness:\n\(swift.output)") }
        return executable
    }
}

/// What follows main.swift's `let arguments = …` in the child. Each argument is "facts" (EXAMPLES, EXAMPLE, SEENKEY),
/// "field<tab>TRIGGER<tab>EXAMPLE" (FIELD: `StartModel.fieldText`), or a script, "script OURS STEP STEP …": a
/// `StartModel` made with OURS and the fresh defaults of a suite of its own (a file in the test's home), then each step
/// done to it (STEPS: the model's step when made and after each; SHOWS: `StartWindow.shouldShow` of its defaults then;
/// KEPT: whether the defaults hold something under `StartWindow.seenKey` at the end; ELSEWHERE and STANDARD: whether
/// another fresh suite and the process's own defaults still say to show it). Only the contract's names are used.
private enum StartWindowHarness {
    static let swift = #"""

// MARK: - StartWindowMacTests' child (in place of main.swift's dispatch)

MainActor.assumeIsolated {
    // Never the user's defaults: the test's home.
    let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] ?? ""
    guard !home.isEmpty, URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        .hasPrefix(URL(fileURLWithPath: home).standardizedFileURL.path) else {
        print("FAIL the home isn't the test's: \(NSHomeDirectory())")
        exit(3)
    }
    func id(_ text: Substring) -> String? { text == "nil" ? nil : String(text) }
    // A suite named by a path is kept in that file: in the test's home, not in the user's Preferences.
    func freshDefaults() -> UserDefaults? {
        UserDefaults(suiteName: URL(fileURLWithPath: home).appendingPathComponent("start122-" + UUID().uuidString).path)
    }
    for argument in arguments {
        if argument == "facts" {
            print("EXAMPLES\t\(StartModel.examples.count)")
            for (index, example) in StartModel.examples.enumerated() { print("EXAMPLE\t\(index)\t\(example)") }
            print("SEENKEY\t\(StartWindow.seenKey)")
        } else if argument.hasPrefix("field\t") {
            let parts = argument.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else {
                print("FAIL usage: field<tab>TRIGGER<tab>EXAMPLE, not \(argument)")
                exit(2)
            }
            let text = StartModel.fieldText(trigger: parts[1], example: parts[2] == "<none>" ? nil : parts[2])
            print("FIELD\t\(parts[1])\t\(parts[2])\t\(text)")
        } else if argument.hasPrefix("script ") {
            let words = argument.split(separator: " ")
            guard words.count >= 2, let defaults = freshDefaults(), let elsewhere = freshDefaults() else {
                print("FAIL usage: script OURS STEP…, not \(argument)")
                exit(2)
            }
            let model = StartModel(defaults: defaults, ourSourceID: String(words[1]))
            var steps = [model.step]
            var shows = [StartWindow.shouldShow(defaults)]
            for word in words.dropFirst(2) {
                switch word {
                case "signedIn": model.signedIn()
                case "later": model.later()
                case "close": model.close()
                case "markSeen": StartWindow.markSeen(defaults)
                case _ where word.hasPrefix("start="): model.start(currentSourceID: id(word.dropFirst("start=".count)))
                case _ where word.hasPrefix("source="): model.inputSourceChanged(to: id(word.dropFirst("source=".count)))
                default:
                    print("FAIL no step \(word)")
                    exit(2)
                }
                steps.append(model.step)
                shows.append(StartWindow.shouldShow(defaults))
            }
            print("STEPS\t\(argument)\t\(steps.map(String.init).joined(separator: ","))")
            print("SHOWS\t\(argument)\t\(shows.map { $0 ? "1" : "0" }.joined(separator: ","))")
            print("KEPT\t\(argument)\t\(defaults.object(forKey: StartWindow.seenKey) == nil ? 0 : 1)")
            print("ELSEWHERE\t\(argument)\t\(StartWindow.shouldShow(elsewhere) ? 1 : 0)")
            print("STANDARD\t\(argument)\t\(StartWindow.shouldShow(UserDefaults.standard) ? 1 : 0)")
            // Told above if it was marked; not left in the child's own defaults then.
            if UserDefaults.standard.object(forKey: StartWindow.seenKey) != nil {
                UserDefaults.standard.removeObject(forKey: StartWindow.seenKey)
            }
        } else {
            print("FAIL no such question: \(argument)")
            exit(2)
        }
    }
    fflush(stdout)
}
exit(0)
"""#
}

// MARK: - The installer's child

enum StartInstallerChild {
    struct Report: CustomStringConvertible {
        var values: [String: String]
        var status: Int32
        var output: String
        func value(_ tag: String, _ keys: String...) -> String? { values[([tag] + keys).joined(separator: "\t")] }
        /// `Installer.installedDetails(trigger:)`, as the child said it (base64, the text may have lines).
        func details(_ trigger: String) -> String? {
            value("DETAILS", trigger).flatMap { Data(base64Encoded: $0) }.map { String(decoding: $0, as: UTF8.self) }
        }
        var description: String {
            let told = values.keys.filter { $0.hasPrefix("DETAILS\t") }.sorted().map { key in
                key + "\t" + (details(String(key.dropFirst("DETAILS\t".count))) ?? "?")
            }
            return "(the child exited \(status)):\n\(output)\n\(told.joined(separator: "\n"))"
        }
    }

    static let repository = StartWindowChild.repository
    static let compiled: Result<URL, Error> = Result { try compile() }

    /// The installer's child with `interface` its interface language (the config's `uiLanguage`, in a home of the
    /// test's): what `settingsAppArguments` gives, and `installedDetails` for each of `triggers`.
    static func run(interface: String, triggers: [String]) throws -> Report {
        let executable = try compiled.get()
        let result = try StartChildProcess.run(executable, triggers, timeout: 60) { home in
            let folder = home.appendingPathComponent(".config/allinoneime", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("{\"uiLanguage\": \"\(interface)\"}".utf8).write(to: folder.appendingPathComponent("config.json"))
        }
        let report = Report(values: StartChildProcess.values(result.output), status: result.status, output: result.output)
        if result.status != 0 { throw StartWindowChild.Failure(description: "the installer's child failed \(report)") }
        return report
    }

    /// Sources/AllInOneIMEInstaller, its main.swift as written up to where it starts (`// MARK: Start`: `language`,
    /// `tr` and what else Installer.swift may use of it stay), then the harness.
    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("start122-installer-\(UUID().uuidString)")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let sources = repository.appendingPathComponent("Sources/AllInOneIMEInstaller")
        let main = try String(contentsOf: sources.appendingPathComponent("main.swift"), encoding: .utf8)
        // Where the installer starts: the mark, else the switch on its arguments.
        guard let cut = main.range(of: "\n// MARK: Start\n", options: .backwards)
                ?? main.range(of: "\nswitch CommandLine.arguments", options: .backwards) else {
            throw StartWindowChild.Failure(description: "the installer's main.swift: no `// MARK: Start` nor `switch CommandLine.arguments`")
        }
        let mainFile = scratch.appendingPathComponent("main.swift")
        try (String(main[..<cut.lowerBound]) + "\n" + harness).write(to: mainFile, atomically: true, encoding: .utf8)
        let others = try fm.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "main.swift" }.map(\.path).sorted()
        let executable = scratch.appendingPathComponent("start122-installer")
        let swift = try SourceCompiler.compile(repository: repository, sources: [mainFile.path] + others,
                                               executable: executable, timeout: 900)
        guard swift.status == 0 else {
            throw StartWindowChild.Failure(description: "compiling Sources/AllInOneIMEInstaller with the harness:\n\(swift.output)")
        }
        return executable
    }

    /// In place of the installer's start: nothing is installed, asked or opened. PROBE: the Cancel button's title, in
    /// the interface language. ARGS: what AllInOneIME Settings is opened with, their count and the arguments. DETAILS:
    /// the last dialog's text for each trigger given, base64.
    static let harness = #"""

// MARK: - StartWindowMacTests' child (in place of the installer's start)

print("PROBE\t" + tr("取消", "Cancel"))
for (name, fresh) in [("fresh", true), ("update", false)] {
    let arguments = Installer.settingsAppArguments(fresh: fresh)
    print("ARGS\t\(name)\t\(arguments.count):\(arguments.joined(separator: ","))")
}
for trigger in CommandLine.arguments.dropFirst() {
    print("DETAILS\t\(trigger)\t" + Data(Installer.installedDetails(trigger: trigger).utf8).base64EncodedString())
}
fflush(stdout)
exit(0)
"""#
}

// MARK: - A child process

enum StartChildProcess {
    /// What a child printed: each line a tag, its keys and a value, tab-separated; the keys are what tells a value.
    static func values(_ output: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 2, let tag = fields.first, tag == tag.uppercased(), tag != "FAIL" else { continue }
            values[fields.dropLast().joined(separator: "\t")] = fields.last
        }
        return values
    }

    /// `executable` run to its end in a home of its own (never the user's config), which `prepare` fills
    /// first: its exit status and what it printed.
    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval,
                    prepare: (URL) throws -> Void = { _ in }) throws -> (status: Int32, output: String) {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("start122-home-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        try prepare(home)
        // A file, not a pipe: a long output never blocks the child.
        let log = fm.temporaryDirectory.appendingPathComponent("start122-\(UUID().uuidString).log")
        fm.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer {
            try? handle.close()
            try? fm.removeItem(at: log)
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = StartWindowChild.repository
        process.environment = ProcessInfo.processInfo.environment.merging(["CFFIXED_USER_HOME": home.path, "HOME": home.path]) { $1 }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.5)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw StartWindowChild.Failure(description: "timed out: \(executable.lastPathComponent) \(arguments.first ?? "")\n"
                                           + ((try? String(contentsOf: log, encoding: .utf8)) ?? ""))
        }
        return (process.terminationStatus, (try? String(contentsOf: log, encoding: .utf8)) ?? "")
    }
}
