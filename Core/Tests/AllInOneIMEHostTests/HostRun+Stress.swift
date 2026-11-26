import Foundation
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// What must hold after every step of a random scenario (`HostStress`), whatever the scenario checks: the user-visible
/// state the same rules every profile has, checked as the step left it (nothing settled first, so the copies and timers
/// on their way still come in between the steps as they would).
extension HostRun {
    func checkStrictInvariants() {
        // Nothing typed lost or doubled: what was committed is in the field as many times as it went in (`EXPECT nolost`).
        let wrong = ledger.mismatches(in: host.document)
        if !wrong.isEmpty {
            let listed = wrong.map { "\"\($0.character)\" \($0.has) times, put in \($0.should)" }.joined(separator: "; ")
            fail("characters lost or doubled: \(listed)\(state)")
        }
        // Contract v1.3: what is being typed is in the panel only; the session marks nothing in the field.
        if !host.marked.isEmpty { fail("marked text \(Self.quote(host.marked)) in the field after a step\(state)") }
        let input = host.panel?.input.map { $0.prompt + $0.text } ?? ""
        let typing = !(host.panel?.input?.text.isEmpty ?? true)
        if focused, !inABC, host.composer.isComposing, host.panel == nil {
            fail("composing \(Self.quote(host.composer.markedText)) with no panel\(state)")
        }
        if typing, !host.composer.isComposing {
            fail("the panel's input line \(Self.quote(input)) with nothing composed\(state)")
        }
        if started, !focused || inABC, host.panel != nil {
            fail("the panel shown in a field that lost the focus\(state)")
        }
    }

    /// The first failure of `steps` (scenario lines after `header`) on `profile`, checked strictly; nil: none.
    static func firstStrictFailure(_ header: [String], _ steps: [String], on profile: HostProfile) -> HostFailure? {
        guard let scenario = try? HostCaseParser.parse(HostStress.text(header, steps), fallbackName: "stress") else {
            return HostFailure(line: 0, message: "the scenario can't be read")
        }
        return UIText.$scopedInterface.withValue(UIText.ScopedInterface(choice: "en", commandTrigger: "@")) {
            let run = HostRun(scenario, profile: profile)
            run.strict = true
            return run.run().first
        }
    }

    /// What kind of failure `message` is: its words up to the first quote, bracket or number (the same check failing).
    static func kind(of message: String) -> String {
        String(message.prefix { !"\"[(0123456789".contains($0) }).trimmingCharacters(in: .whitespaces)
    }
}
