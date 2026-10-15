import Foundation
import Testing
@testable import AllInOneIMECore

/// `TypeOut.Typist` in simulated text fields: one that honors replacement ranges (as NSTextView, WebKit and Chromium
/// do), one that ignores them, one that tells its caret late, one whose caret is moved mid-typo, an editor that adds
/// text. The field must end up with exactly the text, or as close as the field allows.
struct TypistTests {
    typealias Seeded = TypeOutMistakesTests.Seeded

    /// A text field. Typing goes in at the caret; a replacement puts the caret after it (`replaceMovesCaret`, as
    /// NSTextView does) or keeps it where it was. `ignoresRanges`: a replacement goes in at the caret. `lag`: the
    /// chance that after an edit the caret and reads tell the field as it was before it, for 1–5 looks (Chromium,
    /// when the next step comes before it has caught up).
    final class SimField: TypeOut.Field {
        var text: [UInt16]
        var caretAt: Int
        var ignoresRanges = false
        var replaceMovesCaret = true
        var lag = 0.0
        var random = Seeded(state: 1)
        /// Replacements sent after `fieldFailed`.
        var replacements = 0
        private var stale: (text: [UInt16], caret: Int)?
        private var staleLooks = 0

        init(_ before: String, after: String = "") {
            text = Array((before + after).utf16)
            caretAt = before.utf16.count
        }

        var string: String { String(decoding: text, as: UTF16.self) }

        private var seen: (text: [UInt16], caret: Int) { staleLooks > 0 ? stale ?? (text, caretAt) : (text, caretAt) }

        var length: Int? { seen.text.count }

        var caret: Int? {
            let caret = seen.caret
            if staleLooks > 0 { staleLooks -= 1 }
            return caret
        }

        func read(_ range: NSRange) -> String? {
            let text = seen.text
            guard range.location >= 0, NSMaxRange(range) <= text.count else { return nil }
            return String(decoding: text[range.location..<NSMaxRange(range)], as: UTF16.self)
        }

        private func edited() {
            guard staleLooks == 0 else { return }  // still telling an older state
            (stale, staleLooks) = ((text, caretAt), random.next() < lag ? 1 + Int(random.next() * 5) : 0)
        }

        func type(_ string: String) {
            edited()
            let units = Array(string.utf16)
            text.insert(contentsOf: units, at: caretAt)
            caretAt += units.count
        }

        func replace(_ range: NSRange, with string: String) {
            replacements += 1
            if ignoresRanges { return type(string) }
            edited()
            let units = Array(string.utf16)
            guard NSMaxRange(range) <= text.count else { return }
            text.replaceSubrange(range.location..<NSMaxRange(range), with: units)
            if replaceMovesCaret {
                caretAt = range.location + units.count
            } else if caretAt >= NSMaxRange(range) {
                caretAt += units.count - range.length
            } else if caretAt > range.location {
                caretAt = range.location + units.count
            }
        }
    }

    static let texts = TypeOutMistakesTests.texts.filter { !$0.isEmpty } + [
        "Thanks again for taking the time to walk me through the new release plan yesterday afternoon. I think the overall "
            + "direction makes sense, and the team agrees that shipping the smaller pieces first will help us learn faster.",
    ]

    /// Types `runs` into `field` to the end; `between` acts on the field before each step.
    @discardableResult
    static func typeOut(_ runs: [TypeOut.Run], into field: SimField, waits: UnsafeMutablePointer<Int>? = nil,
                        between: (Int, TypeOut.Typist) -> Void = { _, _ in }) -> TypeOut.Typist {
        var typist = TypeOut.Typist(runs, start: field.caretAt, length: field.text.count)
        for n in 0..<100_000 {
            between(n, typist)
            let progress = typist.step(in: field)
            if progress == .done { break }
            if progress == .waiting { waits?.pointee += 1 }
        }
        return typist
    }

    static func plan(_ text: String, _ random: inout Seeded) -> [TypeOut.Run] {
        TypeOut.plan(for: text, rate: 16, varies: true, mistakes: true, random: { random.next() })
    }

    @Test func aFieldThatHonorsRangesEndsExact() {
        var waited = 0
        for text in Self.texts {
            for seed in UInt64(0)..<120 {
                var random = Seeded(state: seed)
                let field = SimField("Before ", after: " after")
                field.replaceMovesCaret = seed % 2 == 0
                field.lag = Double(seed % 3) / 4  // Chromium: the caret and text told a little late
                field.random = Seeded(state: seed + 1000)
                let typist = Self.typeOut(Self.plan(text, &random), into: field, waits: &waited)
                #expect(field.string == "Before " + text + " after", "seed \(seed): \(field.string)")
                #expect(!typist.fieldFailed)
            }
        }
        #expect(waited > 0)  // the lagging fields were waited for
    }

    /// A field that reads back but ignores replacement ranges: nothing sent can take a typo out. It stays (one
    /// character off, or one extra), nothing else is added, and the app is to be remembered.
    @Test func aFieldThatIgnoresRangesKeepsAtMostOneTypoAndIsRemembered() {
        var failed = 0, exact = 0, runs = 0
        for text in Self.texts {
            for seed in UInt64(0)..<100 {
                var random = Seeded(state: seed)
                let plan = Self.plan(text, &random)
                guard plan.contains(where: \.isSlip) else { continue }
                runs += 1
                let field = SimField("Re: ")
                field.ignoresRanges = true
                let typist = Self.typeOut(plan, into: field)
                #expect(Self.oneEditApart(field.string, "Re: " + text), "seed \(seed): \(field.string)")
                #expect(typist.fieldFailed && !typist.mistakes)
                #expect(field.replacements == 1)  // the first fix only: nothing more is sent its way
                if typist.fieldFailed { failed += 1 }
                if field.string == "Re: " + text { exact += 1 }
            }
        }
        #expect(failed == runs && runs > 0)
        // Typed again without typos (the app remembered): exact.
        let field = SimField("Re: ")
        field.ignoresRanges = true
        Self.typeOut(TypeOut.plan(for: Self.texts[0], rate: 16, mistakes: false), into: field)
        #expect(field.string == "Re: " + Self.texts[0])
    }

    /// 5000 runs; in each the caret is moved once, to a random place (a click, the app), at a random step, in half
    /// of them while a typo is in the field. Every character must be there once, none lost or extra, no typo left.
    @Test func theCaretMovedMidTypo5000Runs() {
        let text = Self.texts.last!
        var garbled = 0, movedInTypo = 0, moved = 0
        var random = Seeded(state: 42)
        for run in 0..<5000 {
            let plan = Self.plan(text, &random)
            let field = SimField("Before: ", after: " :after")
            field.replaceMovesCaret = run % 2 == 0
            field.lag = run % 3 == 0 ? 0.3 : 0
            let duringTypo = random.next() < 0.5
            let from = Int(random.next() * Double(plan.reduce(0) { $0 + $1.steps.count }))
            var done = false
            Self.typeOut(plan, into: field) { n, typist in
                guard !done, n >= from, !duringTypo || typist.typing.inSlip else { return }
                done = true
                if typist.typing.inSlip { movedInTypo += 1 }
                field.caretAt = Int(random.next() * Double(field.text.count + 1))
            }
            if done { moved += 1 }
            if field.string.sorted() != ("Before: " + text + " :after").sorted() { garbled += 1 }
        }
        #expect(garbled == 0, "\(garbled) of 5000 runs garbled (\(moved) moved, \(movedInTypo) while a typo was in the field)")
        #expect(movedInTypo > 1000)
        print("caret moved: 5000 runs, \(moved) moved, \(movedInTypo) while a typo was in the field, \(garbled) garbled")
    }

    /// An editor adds text while a typo is in it (an autocomplete, a closing bracket): the typed span is put right,
    /// and the app is to be remembered.
    @Test func anEditorAddingTextMidTypoIsPutRight() {
        var random = Seeded(state: 9)
        var repaired = 0
        for text in [Self.texts[5], Self.texts.last!, "let total = items.map { $0.price }.reduce(0, +) // the sum of 42 prices"] {
            for _ in 0..<200 {
                let plan = Self.plan(text, &random)
                guard plan.contains(where: \.isSlip) else { continue }
                let field = SimField("x")
                var added = false
                let typist = Self.typeOut(plan, into: field) { _, typist in
                    guard !added, typist.typing.inSlip else { return }
                    added = true
                    field.type("Completion")
                }
                if added {
                    repaired += 1
                    #expect(field.string == "x" + text, "\(field.string)")
                    #expect(typist.fieldFailed && !typist.mistakes)
                }
            }
        }
        #expect(repaired > 100)
    }

    /// Stopped at any step (Esc, another key, the field lost): a typo in the field is taken out first.
    @Test func stoppingAnywhereInAFieldLeavesItRight() {
        for text in Self.texts {
            for seed in UInt64(0)..<15 {
                var random = Seeded(state: seed)
                let plan = Self.plan(text, &random)
                let count = plan.reduce(0) { $0 + $1.steps.count }
                for stop in stride(from: 0, through: count, by: 3) {
                    for insertingRest in [true, false] {
                        let field = SimField("> ")
                        var typist = TypeOut.Typist(plan, start: field.caretAt, length: field.text.count)
                        for _ in 0..<stop where typist.step(in: field) != .done {}
                        field.type(typist.stop(insertingRest: insertingRest, in: field))
                        let typed = String(field.string.dropFirst(2))
                        if insertingRest {
                            #expect(typed == text, "seed \(seed), stopped after \(stop): \(typed)")
                        } else {
                            #expect(text.hasPrefix(typed), "seed \(seed), stopped after \(stop): \(typed)")
                        }
                    }
                }
            }
        }
    }

    static func oneEditApart(_ a: String, _ b: String) -> Bool {
        let (x, y) = (Array(a), Array(b))
        if x == y { return true }
        let prefix = zip(x, y).prefix { $0 == $1 }.count
        let suffix = zip(x.reversed(), y.reversed()).prefix { $0 == $1 }.count
        return max(x.count, y.count) - min(prefix + suffix, min(x.count, y.count)) <= 1
    }
}
