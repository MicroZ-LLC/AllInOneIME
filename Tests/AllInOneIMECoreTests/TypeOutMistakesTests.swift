import Foundation
import Testing
@testable import AllInOneIMECore

/// Typos fixed on the way (`Config.typeOutMistakes`): whatever the slips, and wherever typing stops, the
/// document ends up with exactly the text.
struct TypeOutMistakesTests {
    /// Numbers in 0..<1 from a seed (SplitMix64), so a failure can be replayed.
    struct Seeded {
        var state: UInt64
        mutating func next() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return Double((z ^ (z >> 31)) >> 11) / Double(UInt64(1) << 53)
        }
    }

    /// A text field: the edits applied as an app applies them (UTF-16 ranges), after what was in it before.
    struct Field {
        let before: String
        var text: NSMutableString
        init(_ before: String) { self.before = before; text = NSMutableString(string: before) }
        var typed: String { String(text.substring(from: (before as NSString).length)) }

        mutating func apply(_ edit: TypeOut.Typing.Edit) {
            switch edit {
            case let .type(string): text.append(string)
            case let .replace(location, length, string):
                let start = (before as NSString).length
                #expect(location >= 0 && location + length == text.length - start, "a replacement ends at the caret")
                text.replaceCharacters(in: NSRange(location: start + location, length: length), with: string)
            }
        }
    }

    static let texts = [
        "Thanks for the quick reply, I will look into it tomorrow morning and get back to you.",
        "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs!",
        "我们明天下午三点在会议室开会，请大家准时参加。谢谢！",
        "我用 Python 写了一个 quick sort，速度还不错，大家可以看看。",
        "See https://example.com/docs/getting-started?lang=en#install for the steps, then email ops@example.com today.",
        "def quick_sort(items):\n    if len(items) <= 1:\n        return items\n    pivot = items[0]\n    return quick_sort([x for x in items[1:] if x < pivot])",
        "Great work everyone 👍🏽 the release went out on time 🎉 and nobody had to stay late.",
        "First line of the note\nSecond line, with a bit more text\n\nA last paragraph after an empty line.",
        "Café déjà vu, naïve résumé: these words keep their accents, while plain ones may slip.",
        "The total is 1,299.50 dollars for 3 items, order #A-1042, due 2026-10-31 at 5pm.",
        "x",
        "",
        "ok",
        "안녕하세요 반갑습니다 오늘 날씨가 좋네요",
        "今日はいい天気ですね、散歩に行きましょう。",
    ]

    static func plan(_ text: String, seed: UInt64, rate: Double = 16, varies: Bool = false) -> [TypeOut.Run] {
        var random = Seeded(state: seed)
        return TypeOut.plan(for: text, rate: rate, varies: varies, mistakes: true, random: { random.next() })
    }

    /// The characters each run starts at.
    static func offsets(_ runs: [TypeOut.Run]) -> [Int] {
        var at = 0
        return runs.map { run in defer { at += run.text.count }; return at }
    }

    @Test func withoutMistakesEachCharacterIsJustTyped() {
        var a = Seeded(state: 7), b = Seeded(state: 7)
        let text = "Hello, world. 你好！"
        let runs = TypeOut.plan(for: text, rate: 16, varies: true, random: { a.next() })
        let delays = TypeOut.delays(for: text, rate: 16, varies: true, random: { b.next() })
        #expect(runs.count == text.count && runs.allSatisfy { !$0.isSlip && $0.steps.count == 1 })
        #expect(runs.map(\.text).joined() == text && runs.map { $0.steps[0].delay } == delays)
    }

    @Test func everyPlanLeavesExactlyTheText() {
        for text in Self.texts {
            for seed in UInt64(0)..<300 {
                let runs = Self.plan(text, seed: seed, varies: seed % 2 == 0)
                #expect(runs.map(\.text).joined() == text)
                // Each run's keys replayed leave its text; its plain keys too.
                for run in runs {
                    for steps in [run.steps, run.plain] {
                        var typed: [String] = []
                        for step in steps {
                            #expect(step.delay > 0)
                            switch step.stroke {
                            case let .type(character): typed.append(character)
                            case .delete: typed.removeLast()
                            }
                        }
                        #expect(typed.joined() == run.text, "seed \(seed): \(run)")
                    }
                }
                // Typed into a field after some text, step by step.
                var field = Field("Re: ")
                var typing = TypeOut.Typing(runs)
                while let (edit, _) = typing.next() { field.apply(edit) }
                #expect(field.text as String == "Re: " + text, "seed \(seed)")
                #expect(typing.typed.joined() == text && typing.length == text.utf16.count)
            }
        }
    }

    @Test func stoppingAnywhereLeavesTheTextRight() {
        for text in Self.texts where !text.isEmpty {
            for seed in UInt64(0)..<40 {
                let runs = Self.plan(text, seed: seed)
                let count = runs.reduce(0) { $0 + $1.steps.count }
                for stop in 0...count {
                    for insertingRest in [true, false] {
                        var field = Field("> ")
                        var typing = TypeOut.Typing(runs)
                        for _ in 0..<stop { if let (edit, _) = typing.next() { field.apply(edit) } }
                        if let edit = typing.stop(insertingRest: insertingRest) { field.apply(edit) }
                        // The rest typed: all of it. Stopped (Esc, the field lost): its start, never a typo.
                        if insertingRest {
                            #expect(field.typed == text, "seed \(seed), stopped after \(stop): \(field.typed)")
                        } else {
                            #expect(text.hasPrefix(field.typed), "seed \(seed), stopped after \(stop): \(field.typed)")
                        }
                    }
                }
            }
        }
    }

    @Test func aSlipTheFieldCantFixIsTypedPlainly() {
        for seed in UInt64(0)..<50 {
            let text = Self.texts[seed % 2 == 0 ? 0 : 3]
            let runs = Self.plan(text, seed: seed)
            var field = Field("")
            var typing = TypeOut.Typing(runs)
            var deleted = false
            while true {
                if typing.startsSlip { typing.skipSlip() }
                guard let (edit, _) = typing.next() else { break }
                if case .replace = edit { deleted = true }
                field.apply(edit)
            }
            #expect(field.typed == text && !deleted)
        }
    }

    @Test func aFewSlipsIn100CharactersOfProseNeverTwoInARow() {
        let prose = String(repeating: Self.texts[0] + " " + Self.texts[1] + " ", count: 6)
        var slips = 0, kinds = Set<String>()
        for seed in UInt64(0)..<200 {
            let runs = Self.plan(prose, seed: seed)
            let starts = Self.offsets(runs)
            var lastEnd: Int?
            for (run, start) in zip(runs, starts) where run.isSlip {
                slips += 1
                if let lastEnd { #expect(start - lastEnd >= TypeOut.slipGap, "seed \(seed): slips \(start - lastEnd) apart") }
                lastEnd = start + run.text.count
                #expect(start > 0)
                let deletes = run.steps.filter { $0.stroke == .delete }.count
                let typed = run.steps.compactMap { if case let .type(c) = $0.stroke { return c } else { return nil } }
                if run.text == " " { kinds.insert("space") }
                else if run.text.count == 1, deletes == 1, typed == [run.text, run.text] { kinds.insert("doubled") }
                else if typed.first != String(run.text.first!) {
                    kinds.insert("neighbor")
                    // A neighboring key on QWERTY, the right letter typed again.
                    let wrong = Character(typed[0]), right = run.text.first!
                    #expect(TypeOut.Keyboard.qwerty.neighbors(of: right).contains(wrong))
                    #expect((1...4).contains(deletes) && deletes == run.text.count)
                    // Noticed within the word: fixed before a space, where an app's spelling correction may act.
                    #expect(run.text.allSatisfy { $0.isLetter })
                } else { kinds.insert("hesitation"); #expect((2...6).contains(run.text.count)) }
            }
        }
        let perHundred = Double(slips) / Double(200 * prose.count) * 100
        #expect(perHundred > 1.5 && perHundred < 4.5, "\(perHundred) slips in 100 characters")
        #expect(kinds == ["space", "doubled", "neighbor", "hesitation"])
    }

    /// Always "random" 0: a slip wherever one may happen.
    static func eager(_ text: String) -> [TypeOut.Run] {
        TypeOut.plan(for: text, rate: 16, mistakes: true, random: { 0.001 })
    }

    @Test func noneInAddressesNumbersOrCode() {
        for text in ["https://example.com/a/b?c=d", "www.example.org", "bob.smith@example.com", "3.14159 2026 1,299.50 #42",
                     "foo.bar snake_case camelCase iPhone e.g. a/b x=y", "for (i = 0; i < n; i++) { total += i }",
                     "  indented code line\n  another indented line", "```\nlet some code here\n```"] {
            #expect(!Self.eager(text).contains { $0.isSlip }, "\(text)")
            for seed in UInt64(0)..<100 { #expect(!Self.plan(text, seed: seed).contains { $0.isSlip }) }
        }
        // Around them, in the words.
        let text = "Read the guide at https://example.com/getting-started before tomorrow, or write to help@example.com today"
        let url = (text as NSString).range(of: "https://example.com/getting-started")
        let mail = (text as NSString).range(of: "help@example.com")
        let protected = [url.location..<(url.location + url.length), mail.location..<(mail.location + mail.length)]
        for seed in UInt64(0)..<300 {
            let runs = Self.plan(text, seed: seed)
            for (run, start) in zip(runs, Self.offsets(runs)) where run.isSlip {
                // Whatever a slip types, wrong or not, stays clear of the address (and the space before it).
                let span = start..<(start + max(run.text.count, run.steps.count))
                #expect(!protected.contains { $0.overlaps(span.lowerBound..<min(span.upperBound, start + run.text.count + 1)) })
                #expect(!protected.contains { $0.contains(start) })
            }
        }
        #expect(Self.eager(text).contains { $0.isSlip })
        // A text mostly of code has none, even in its prose lines.
        #expect(!Self.eager(Self.texts[5]).contains { $0.isSlip })
    }

    @Test func chineseOnlyHesitates() {
        for text in [Self.texts[2], Self.texts[13], Self.texts[14]] {
            var slips = 0
            for seed in UInt64(0)..<200 {
                for run in Self.plan(text, seed: seed) where run.isSlip {
                    slips += 1
                    // Two characters typed, deleted and typed again: never a character that isn't there.
                    let typed = run.steps.compactMap { if case let .type(c) = $0.stroke { return c } else { return nil } }
                    #expect(run.text.count == 2 && typed == run.text.map(String.init) + run.text.map(String.init))
                }
            }
            #expect(slips > 0)
        }
        // Mixed: the English words slip as English does, the Chinese only hesitates.
        #expect(Self.eager(Self.texts[3]).contains { $0.isSlip && $0.text.allSatisfy(\.isASCII) })
    }

    @Test func neighborsByKeyPlace() {
        let qwerty = TypeOut.Keyboard.qwerty
        #expect(Set(qwerty.neighbors(of: "d")) == Set("ersfxc"))
        #expect(Set(qwerty.neighbors(of: "q")) == Set("wa"))
        #expect(Set(qwerty.neighbors(of: "m")) == Set("njk"))
        #expect(Set(qwerty.neighbors(of: "D")) == Set("ERSFXC"))
        #expect(qwerty.neighbors(of: "é").isEmpty && qwerty.neighbors(of: "1").isEmpty)
        // AZERTY: the same keys type other letters (A where Q is, M right of L).
        let azertyKeys: [UInt16: String] = [0x0C: "a", 0x0D: "z", 0x0E: "e", 0x00: "q", 0x01: "s", 0x25: "l", 0x29: "m",
                                             0x06: "w", 0x07: "x", 0x2E: ",", 0x28: "k", 0x23: "p", 0x21: "^", 0x27: "ù"]
        let azerty = TypeOut.Keyboard { azertyKeys[$0] ?? "" }
        #expect(Set(azerty.neighbors(of: "a")) == Set("zq"))
        #expect(Set(azerty.neighbors(of: "m")).isSuperset(of: Set("lù")) && !azerty.neighbors(of: "m").contains(","))
        #expect(Set(azerty.neighbors(of: "q")) == Set("azsw"))
        // The plan takes the keyboard it's given.
        let runs = TypeOut.plan(for: "Bonjour mon ami, quelle surprise", rate: 16, mistakes: true, keyboard: azerty, random: { 0.001 })
        for run in runs where run.isSlip {
            if case let .type(wrong) = run.steps[0].stroke, wrong != String(run.text.first!) {
                #expect(azerty.neighbors(of: run.text.first!).contains(Character(wrong)))
            }
        }
    }

    @Test func offByDefaultInTheConfig() throws {
        #expect(!Config.default.typeOutMistakes)
        #expect(try !JSONDecoder().decode(Config.self, from: Data("{}".utf8)).typeOutMistakes)
        let set = try JSONDecoder().decode(Config.self, from: Data(#"{"typeOut": true, "typeOutMistakes": true}"#.utf8))
        #expect(set.typeOutMistakes)
        #expect(try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(set)).typeOutMistakes)
    }
}
