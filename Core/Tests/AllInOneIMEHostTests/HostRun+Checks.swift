import Foundation
@testable import AllInOneIMECore
import AllInOneIMETestSupport

/// What a scenario checks (`EXPECT`), and what must hold after every step whatever it checks (`checkInvariants`).
extension HostRun {
    func check(_ expectation: HostExpectation) {
        switch expectation {
        case let .doc(markup): checkDocument(markup)
        case let .marked(text):
            let shown = host.marked.isEmpty ? nil : host.marked
            if shown != text { fail("marked text \(Self.quote(shown)), expected \(Self.quote(text))\(state)") }
        case let .preedit(text, caret): checkPreedit(text, caret: caret)
        case let .panel(shown):
            if (host.panel != nil) != shown { fail("the panel \(host.panel == nil ? "hidden" : "shown"), expected \(shown ? "shown" : "hidden")\(state)") }
        case let .language(expected):
            let language = host.composer.inputLanguage
            if language != (expected == .chinese ? .chinese : .english) {
                fail("the input language \(Self.name(language)), expected \(expected.rawValue)\(state)")
            }
        case let .contextBefore(expected): checkContext(expected)
        case let .contextAfter(expected): checkContextAfter(expected)
        case .fallbackNone:
            if !typedFallback.isEmpty { fail("autocomplete's fallback is \(Self.quote(typedFallback)), expected none\(state)") }
        case let .switches(count):
            if switches != count { fail("\(switches) language switches, expected \(count)\(state)") }
            switches = 0
        case let .calls(call, budget): checkCalls(call, budget)
        case .nolost: checkNothingLost()
        }
    }

    /// The candidate panel's input line (v1.3): what is being typed shows there and only there. Its prompt and text as
    /// one line; none where the panel is hidden or has no input line, or nothing typed in it (a prompt alone, "question
    /// 2 › ", is no composition). A space between two Latin letters is a syllable split and isn't compared: librime
    /// shows "ni hao", the core's fake engine the letters as typed, and the scenario is replayed with both. A caret, where
    /// the scenario gives one, is compared the same way, by what is before it.
    private func checkPreedit(_ expected: String?, caret: Int?) {
        let input = host.panel?.input
        let shown = input.flatMap { $0.text.isEmpty ? nil : $0.prompt + $0.text }
        guard shown.map(Self.unsplit) == expected.map(Self.unsplit) else {
            return fail("the panel's input line \(Self.quote(shown)), expected \(Self.quote(expected))\(state)")
        }
        guard let caret, let expected, let shown, let input else { return }
        let before = input.caret.map { String(shown.prefix(input.prompt.count + $0)) }
        if before.map(Self.unsplit) != Self.unsplit(String(expected.prefix(caret))) {
            fail("the panel's input line's caret after \(Self.quote(before)), expected after "
                 + "\(Self.quote(String(expected.prefix(caret))))\(state)")
        }
    }

    /// `text` without its syllable splits: the spaces between two Latin letters.
    static func unsplit(_ text: String) -> String {
        let characters = Array(text)
        var kept = ""
        for (index, character) in characters.enumerated() {
            if character == " ", index > 0, index + 1 < characters.count,
               characters[index - 1].isASCII && characters[index - 1].isLetter,
               characters[index + 1].isASCII && characters[index + 1].isLetter { continue }
            kept.append(character)
        }
        return kept
    }

    private func checkDocument(_ markup: FieldMarkup) {
        guard host.document == markup.text else {
            return fail("the field holds \(Self.quote(host.document)), expected \(Self.quote(markup.text))\(state)")
        }
        if let caret = markup.caret, host.selection != nil || host.caret != caret {
            fail("the caret at \(host.caret)\(host.selection.map { ", \($0) selected" } ?? ""), expected at \(caret)\(state)")
        }
        if let selection = markup.selection, host.selection != selection {
            fail("\(host.selection.map { "\($0)" } ?? "nothing") selected, expected \(selection)\(state)")
        }
    }

    /// What autocomplete (or a command) would read before the caret: the field's text as the shell reads it, else what
    /// the session kept of what was typed (only where the field tells nothing, and not past a click). An expected
    /// empty text is met by nothing to read too.
    private func checkContext(_ expected: String?) {
        let read = reader.text(before: Autocomplete.beforeLimit, after: Autocomplete.afterLimit)
        _ = field.takeCalls()
        let typed = typedFallback
        let before = read?.before ?? (typed.isEmpty ? nil : typed)
        let met = expected == "" ? (before ?? "") == "" : before == expected
        if !met {
            fail("context before the caret \(before.map { Self.quote($0) } ?? "unreadable"), expected "
                 + "\(expected.map { Self.quote($0) } ?? "unreadable")\(state)")
        }
    }

    /// What autocomplete would read after the caret: the field's text as the shell reads it (nothing where it tells none;
    /// an expected empty text is met by that too).
    private func checkContextAfter(_ expected: String) {
        let after = reader.text(before: Autocomplete.beforeLimit, after: Autocomplete.afterLimit)?.after
        _ = field.takeCalls()
        if expected == "" ? (after ?? "") != "" : after != expected {
            fail("context after the caret \(after.map { Self.quote($0) } ?? "unreadable"), expected \(Self.quote(expected))\(state)")
        }
    }

    /// What autocomplete uses where the field tells nothing: what was typed since the focus, unless the caret may have
    /// moved since (a click), as the session decides it (`InputSession+Autocomplete`).
    var typedFallback: String {
        let session: InputSession = host.session
        return session.caretMayHaveMoved(within: now - session.autocomplete.typedAt) ? "" : session.autocomplete.typed.text
    }

    private func checkCalls(_ call: HostCall, _ budget: HostCallBudget) {
        let over = keyCalls.filter { !budget.allows($0.calls[call]) }
        for key in over {
            fail("\(key.key) (line \(key.line)) made \(key.calls[call]) \(call.rawValue) calls, expected \(budget) (\(key.calls))")
        }
        keyCalls = []
    }

    private func checkNothingLost() {
        let wrong = ledger.mismatches(in: host.document)
        guard !wrong.isEmpty else { return }
        let listed = wrong.map { "\"\($0.character)\" \($0.has) times, put in \($0.should)" }.joined(separator: "; ")
        let dropped = ledger.dropped.isEmpty ? "" : " (dropped by the field: \(Self.quote(ledger.dropped)))"
        fail("characters lost or doubled: \(listed)\(dropped)\(state)")
    }

    /// After every step: the caret and the selection inside the text; nothing composed where the field has lost the
    /// focus (`blur` puts what's pending in); no marked text of the session's left in the field with nothing composed.
    /// (Copies of events that reach the session fail as they come: `deliver`.)
    func checkInvariants() {
        let length = (host.document as NSString).length
        if host.caret > length || host.selection.map({ $0.upperBound > length }) == true {
            fail("the caret or the selection past the text's end\(state)")
        }
        if started, !focused || inABC, host.composer.isComposing {
            fail("the field lost the focus with \(Self.quote(host.composer.markedText)) still composed\(state)")
        }
        if markedBySession, !host.marked.isEmpty, !host.composer.isComposing {
            fail("marked text \(Self.quote(host.marked)) left in the field with nothing composed\(state)")
        }
        // `APP clears` (v1.3): with nothing marked in the field, the app emptying it doesn't touch the composition, and
        // the input method may keep it; the scenario checks the user's next step instead.
    }

    /// The field and the session as they are now, for a failure's message.
    var state: String {
        let panel = host.panel == nil ? "hidden" : "shown"
        return " [\(profile.rawValue): field \(Self.quote(host.document)), caret \(host.caret), marked \(Self.quote(host.marked)), "
            + "panel \(panel), preedit \(Self.quote(host.panel?.input.map { $0.prompt + $0.text })), \(Self.name(host.composer.inputLanguage))\(focused ? "" : ", not focused")]"
    }

    static func name(_ language: Language) -> String {
        switch language {
        case .chinese: HostLanguage.chinese.rawValue
        case .english: HostLanguage.english.rawValue
        default: language.rawValue
        }
    }

    static func quote(_ text: String?) -> String {
        guard let text else { return "none" }
        return "\"" + text.replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t") + "\""
    }
}
