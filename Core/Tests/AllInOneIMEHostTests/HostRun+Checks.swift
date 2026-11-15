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
        // `APP clears` (v1.2): on a native field (IMK calls cancelComposition) the input method holds no draft from then
        // on. Chromium-based hosts tell it nothing, so there the scenario checks the next key instead (no old pinyin).
        if appCleared {
            appCleared = false
            if profile == .nstextview, host.composer.isComposing {
                fail("the app emptied the field and the input method still holds the draft \(Self.quote(host.composer.markedText))\(state)")
            }
        }
    }

    /// The field and the session as they are now, for a failure's message.
    var state: String {
        let panel = host.panel == nil ? "hidden" : "shown"
        return " [\(profile.rawValue): field \(Self.quote(host.document)), caret \(host.caret), marked \(Self.quote(host.marked)), "
            + "panel \(panel), \(Self.name(host.composer.inputLanguage))\(focused ? "" : ", not focused")]"
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
