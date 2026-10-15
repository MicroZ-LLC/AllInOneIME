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
    /// when the next step comes before it has caught up). An empty replacement never arrives (`dropsEmpty`), as
    /// through the input method connection: the real-app test's NSTextView got none.
    final class SimField: TypeOut.Field {
        var text: [UInt16]
        var caretAt: Int
        var ignoresRanges = false
        var replaceMovesCaret = true
        var lag = 0.0
        var random = Seeded(state: 1)
        var dropsEmpty = true
        /// Replacements sent with empty text (the Typist never should).
        var emptyReplacements = 0
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

        /// A copy in the same state (to stop typing in it at every step).
        func copy() -> SimField {
            let field = SimField("")
            (field.text, field.caretAt, field.ignoresRanges, field.replaceMovesCaret) = (text, caretAt, ignoresRanges, replaceMovesCaret)
            (field.lag, field.random, field.dropsEmpty, field.replacements) = (lag, random, dropsEmpty, replacements)
            (field.stale, field.staleLooks, field.emptyReplacements) = (stale, staleLooks, emptyReplacements)
            return field
        }

        func replace(_ range: NSRange, with string: String) {
            if string.isEmpty { emptyReplacements += 1 }
            if string.isEmpty, dropsEmpty { return }
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
                #expect(!typist.fieldFailed && field.emptyReplacements == 0)
            }
        }
        #expect(waited > 0)  // the lagging fields were waited for
    }

    /// A field that reads back but ignores replacement ranges: nothing sent can take a typo out. The first typo is a
    /// probe (a wrong character corrected in one go), so the correction goes in after the typo: one character off,
    /// nothing else added, nothing more sent its way, and the app is to be remembered. Slips with no wrong character
    /// (a letter typed twice, a word typed again) aren't made before a fix was seen taken.
    @Test func aFieldThatIgnoresRangesKeepsAtMostOneTypoAndIsRemembered() {
        var tried = 0
        for text in Self.texts {
            for seed in UInt64(0)..<100 {
                var random = Seeded(state: seed)
                let plan = Self.plan(text, &random)
                let field = SimField("Re: ")
                field.ignoresRanges = true
                let typist = Self.typeOut(plan, into: field)
                #expect(Self.oneEditApart(field.string, "Re: " + text), "seed \(seed): \(field.string)")
                #expect(field.replacements <= 1)  // the probe's correction only
                #expect(typist.fieldFailed == (field.replacements == 1))
                #expect(typist.fieldFailed || field.string == "Re: " + text)
                if field.replacements == 1 { tried += 1 }
            }
        }
        #expect(tried > 500)
        // Typed again without typos (the app remembered): exact.
        let field = SimField("Re: ")
        field.ignoresRanges = true
        Self.typeOut(TypeOut.plan(for: Self.texts[0], rate: 16, mistakes: false), into: field)
        #expect(field.string == "Re: " + Self.texts[0])
    }

    /// 5000 runs; in each the caret is moved once, to a random place (a click, the app), at a random step, in half
    /// of them while a typo is in the field. Every character must be there once, none lost or extra, no typo left.
    @Test func theCaretMovedMidTypo5000Runs() async {
        let text = Self.texts.last!
        var garbled = 0, movedInTypo = 0, moved = 0
        var random = Seeded(state: 42)
        for run in 0..<5000 {
            if run % 50 == 0 { await Task.yield() }  // other tests run meanwhile (some time a process)
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
    /// and no more typos in that run; the app isn't remembered for it.
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
                    // Not the field's failing: its app isn't remembered.
                    #expect(!typist.fieldFailed && !typist.mistakes)
                }
            }
        }
        #expect(repaired > 100)
    }

    /// Stopped at any step (Esc, another key, the field lost): a typo in the field is taken out first.
    @Test func stoppingAnywhereInAFieldLeavesItRight() async {
        for text in Self.texts {
            await Task.yield()
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

    /// The sign-off's fuzz: its 8 texts, 40 seeds each, stopped at every step (the rest typed, or not), in a field
    /// that ignores replacement ranges and in one that honors them but tells its text late (Chromium). Ignoring:
    /// one character off at most, and whenever one is, the app is to be remembered. Honoring: exact, never remembered.
    @Test func stoppedAtEveryStep() async {
        let texts = [
            "Thanks for the quick reply, I will look into it tomorrow morning and get back to you.",
            "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs!",
            "我们明天下午三点在会议室开会，请大家准时参加。谢谢！",
            "See https://example.com/docs/getting-started?lang=en#install for the steps, then email ops@example.com today.",
            "def quick_sort(items):\n    if len(items) <= 1:\n        return items\n    pivot = items[0]\n    return quick_sort([x for x in items[1:] if x < pivot])",
            "First line of the note\nSecond line, with a bit more text\n\nA last paragraph after an empty line.",
            "The total is 1,299.50 dollars for 3 items, order #A-1042, due 2026-10-31 at 5pm.",
            Self.texts.last!,
        ]
        var stops = [0, 0], worst = [0, 0], unremembered = 0, lagOff = 0, falselyRemembered = 0, empty = 0
        for text in texts {
            for seed in UInt64(0)..<40 {
                await Task.yield()
                var random = Seeded(state: seed)
                let plan = Self.plan(text, &random)
                guard plan.contains(where: \.isSlip) else { continue }
                for (mode, ignores) in [true, false].enumerated() {
                    let field = SimField("> ")
                    field.ignoresRanges = ignores
                    if !ignores { (field.lag, field.random) = (0.5, Seeded(state: seed &* 31 &+ 7)) }
                    var typist = TypeOut.Typist(plan, start: 2, length: field.text.count)
                    for _ in 0..<100_000 {
                        for insertingRest in [true, false] {
                            let stopped = field.copy()
                            var copy = typist
                            stopped.type(copy.stop(insertingRest: insertingRest, in: stopped))
                            let typed = Array(stopped.string.dropFirst(2))
                            let off = Self.distance(typed, Array(text), toAStart: !insertingRest)
                            stops[mode] += 1
                            worst[mode] = max(worst[mode], off)
                            empty += stopped.emptyReplacements
                            if ignores {
                                if off > 0, !copy.fieldFailed { unremembered += 1 }
                            } else {
                                if off > 0 { lagOff += 1 }
                                if copy.fieldFailed { falselyRemembered += 1 }
                            }
                        }
                        if typist.step(in: field) == .done { break }
                    }
                }
            }
        }
        #expect(worst[0] <= 1 && unremembered == 0, "ignoring ranges: \(worst[0]) off at worst, \(unremembered) left unremembered")
        #expect(lagOff == 0 && falselyRemembered == 0, "lagging: \(lagOff) off, \(falselyRemembered) falsely remembered")
        #expect(empty == 0)
        print("stopped at every step: \(stops[0]) stops ignoring ranges (\(worst[0]) off at worst, \(unremembered) unremembered), "
              + "\(stops[1]) lagging (\(lagOff) off, \(falselyRemembered) falsely remembered)")
    }

    /// Edit distance from `a` to `b`, or (`toAStart`) to the nearest start of `b`; the common start and end trimmed first.
    static func distance(_ a: [Character], _ b: [Character], toAStart: Bool) -> Int {
        let same = zip(a, b).prefix { $0 == $1 }.count
        var x = Array(a.dropFirst(same)), y = Array(b.dropFirst(same))
        if toAStart {
            y = Array(y.prefix(2 * x.count + 2))
        } else {
            let end = zip(x.reversed(), y.reversed()).prefix { $0 == $1 }.count
            (x, y) = (Array(x.dropLast(end)), Array(y.dropLast(end)))
        }
        var row = Array(0...y.count)
        for i in 1...max(x.count, 1) where !x.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in 1...max(y.count, 1) where !y.isEmpty {
                let above = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (x[i - 1] == y[j - 1] ? 0 : 1))
                previous = above
            }
        }
        return toAStart ? row.min() ?? 0 : row[y.count]
    }

    static func oneEditApart(_ a: String, _ b: String) -> Bool {
        let (x, y) = (Array(a), Array(b))
        if x == y { return true }
        let prefix = zip(x, y).prefix { $0 == $1 }.count
        let suffix = zip(x.reversed(), y.reversed()).prefix { $0 == $1 }.count
        return max(x.count, y.count) - min(prefix + suffix, min(x.count, y.count)) <= 1
    }
}
