import Foundation
import Testing

// #198: Start guide step 3 never reaches the @ list. The field was prefilled with "@" (selected), so typing "200*15%"
// replaced it and the input method never saw a trigger; an example button set the field's text programmatically (no
// trigger seen either); Return with no panel fired Done's default action (closed the guide, marked it seen).
//
// Spec (from the issue):
//   1. The trigger the user sees in the field must reach the input method as a real typed key, never as a text
//      replacement a selection-replace would remove: the prefilled state sets no text in the field itself.
//   2. Clicking an example leaves typing going on in the @ list (same rule): no programmatic text either.
//   3. Return in the field with no panel open must not close the guide / mark it seen: step 3's Done is only a click
//      (no default-action key equivalent); step 1/2's buttons keep theirs.
//
// The code has no seam for 1/2, so this file pins a CONTRACT the implementer must provide on `StartModel`
// (Sources/AllInOneIME/StartWindow.swift), replacing `fieldText(trigger:example:)`:
//
//     struct TryField { var preset: String; var typed: String }
//     static func tryField(trigger: String, example: String?) -> TryField
//         // preset: text put in the field programmatically (must be empty);
//         // typed: the keys the view feeds the input method as real key events (trigger + example).
//     static func hasDefaultAction(step: Int) -> Bool
//         // whether that step's button carries Return as its key equivalent (true for 1 and 2, false for 3);
//         // StartView must use it, and step 3's Done must not carry `.keyboardShortcut(.defaultAction)`.
//
// Until the contract exists the child fails to compile (the first failure); the source test of Done's key equivalent
// fails on its own today, for the issue's reason. Offline, free, deterministic.

@Suite(.serialized)
struct Issue198Tests {
    static let repository = StartWindowChild.repository

    @Test func prefilledTriggerIsTypedNotPreset() throws {
        let report = try Self.ask(["tf\t@\t<none>", "tf\t~\t<none>"])
        for trigger in ["@", "~"] {
            #expect(report.values["TF\t\(trigger)\t<none>\tpreset"] == "", "preset for \(trigger): \(report)")
            #expect(report.values["TF\t\(trigger)\t<none>\ttyped"] == trigger, "typed for \(trigger): \(report)")
        }
    }

    @Test func exampleClickIsTypedNotPreset() throws {
        let examples = ["200*15%", "明天下午三点开会", "safari"]
        let report = try Self.ask(examples.map { "tf\t@\t" + $0 })
        for example in examples {
            #expect(report.values["TF\t@\t\(example)\tpreset"] == "", "preset for \(example): \(report)")
            #expect(report.values["TF\t@\t\(example)\ttyped"] == "@" + example, "typed for \(example): \(report)")
        }
    }

    @Test func onlyStepThreeLosesItsDefaultAction() throws {
        let report = try Self.ask(["da"])
        #expect(report.values["DA\t1"] == "1", "\(report)")
        #expect(report.values["DA\t2"] == "1", "\(report)")
        #expect(report.values["DA\t3"] == "0", "\(report)")
    }

    /// Observable today: step 3's Done button in the view has no Return key equivalent.
    @Test func doneInTryStepHasNoDefaultActionKey() throws {
        let view = try String(contentsOf: Self.repository.appendingPathComponent("Sources/AllInOneIME/StartView.swift"),
                              encoding: .utf8)
        let start = try #require(view.range(of: "private var tryStep"), "StartView has no tryStep")
        let body = String(view[start.lowerBound...])
        let done = try #require(body.range(of: "\"Done\""), "tryStep has no Done button")
        let line = body[done.lowerBound...].prefix { $0 != "\n" }
        #expect(!line.contains("defaultAction"), "step 3's Done still has the default action: \(line)")
    }

    // MARK: - Child

    static let compiled: Result<URL, Error> = Result { try compile() }

    static func ask(_ arguments: [String]) throws -> (values: [String: String], description: String) {
        let executable = try compiled.get()
        let result = try StartChildProcess.run(executable, arguments, timeout: 60)
        let text = "(exit \(result.status)):\n\(result.output)"
        if result.status != 0 { throw StartWindowChild.Failure(description: "the child failed " + text) }
        return (StartChildProcess.values(result.output), text)
    }

    static func compile() throws -> URL {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("issue198-\(UUID().uuidString)")
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
        let executable = scratch.appendingPathComponent("issue198")
        let swift = try SourceCompiler.compile(repository: repository, sources: [mainFile.path] + others,
                                               executable: executable, timeout: 900)
        guard swift.status == 0 else {
            throw StartWindowChild.Failure(description: "compiling Sources/AllInOneIME with the #198 contract:\n\(swift.output)")
        }
        return executable
    }

    static let harness = #"""

MainActor.assumeIsolated {
    for argument in arguments {
        let parts = argument.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        if parts.first == "tf", parts.count == 3 {
            let field = StartModel.tryField(trigger: parts[1], example: parts[2] == "<none>" ? nil : parts[2])
            print("TF\t\(parts[1])\t\(parts[2])\tpreset\t\(field.preset)")
            print("TF\t\(parts[1])\t\(parts[2])\ttyped\t\(field.typed)")
        } else if parts.first == "da" {
            for step in 1...3 { print("DA\t\(step)\t\(StartModel.hasDefaultAction(step: step) ? 1 : 0)") }
        }
    }
    fflush(stdout)
}
exit(0)
"""#
}
