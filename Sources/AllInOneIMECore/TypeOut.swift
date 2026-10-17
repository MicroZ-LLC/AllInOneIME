import Foundation

/// Typing a result out character by character, like a person typing (`Config.typeOut`): how long to
/// wait before each character. The pace varies a little, and stops after punctuation and spaces last longer.
public enum TypeOut {
    /// Characters a second, from very slow (6 s a character) to fast; the default.
    public static let slowestRate = 1.0 / 6
    public static let fastestRate = 40.0
    public static let defaultRate = 16.0

    /// The pause before each character of `text` (the first one too, so it reads as typed), in seconds,
    /// at `rate` characters a second on average. `varies`: short bursts of 3–8 characters, each at its
    /// own pace from half to twice `rate`, like a person speeding up and slowing down. `random` gives
    /// numbers in 0..<1 (the tests pass their own).
    public static func delays(for text: String, rate: Double, varies: Bool = false,
                              random: () -> Double = { Double.random(in: 0..<1) }) -> [Double] {
        let rate = min(max(rate, slowestRate), fastestRate)
        var base = 1 / rate
        var burstLeft = 0
        var previous: Character?
        return text.map { character in
            defer { previous = character }
            if varies {
                if burstLeft == 0 {
                    burstLeft = 3 + Int(random() * 6)
                    base = 1 / (rate * pow(2, 2 * random() - 1))  // ½× to 2× the rate, the middle as likely as the ends
                }
                burstLeft -= 1
            }
            var delay = base * (0.6 + 0.8 * random())  // 60–140 % of the pace
            if let previous {
                if ".,;:!?。，、；：！？…".contains(previous) { delay *= 3 }  // a breath after punctuation
                else if previous == " " || previous == "\n" { delay *= 1.5 }
            }
            return delay
        }
    }

    /// The slider's position (0…1, a log scale so the slow end isn't squeezed) for `rate`, and back.
    public static func position(of rate: Double) -> Double {
        log(min(max(rate, slowestRate), fastestRate) / slowestRate) / log(fastestRate / slowestRate)
    }

    public static func rate(at position: Double) -> Double {
        slowestRate * pow(fastestRate / slowestRate, min(max(position, 0), 1))
    }
}

// MARK: - Typos, fixed on the way

extension TypeOut {
    /// What a key does: types one character (a `Character`, as a string), ⌫ deletes the last one typed, or
    /// `correct`: the last one typed is replaced with the right one in one go (⌫ and the key at once).
    public enum Stroke: Equatable, Sendable {
        case type(String)
        case delete
        case correct(String)
    }

    /// A key and the pause before it, in seconds.
    public struct Step: Equatable, Sendable {
        public var stroke: Stroke
        public var delay: Double

        public init(_ stroke: Stroke, after delay: Double) {
            self.stroke = stroke
            self.delay = delay
        }
    }

    /// A stretch of the text as it's typed: one character, or the few a slip spans (a typo and its fix).
    /// Its `steps` replayed leave exactly `text`; `plain` types the same text without the slip.
    public struct Run: Equatable, Sendable {
        public var text: String
        public var steps: [Step]
        public var plain: [Step]
        public var isSlip: Bool { steps != plain }
    }

    /// The slips a person makes and fixes (`plan`): a neighboring key, noticed 0–3 letters later (in code, an
    /// address or a number at once); a letter typed twice; a space typed twice; a short word typed, taken back
    /// and typed again (a hesitation).
    public enum Slip: CaseIterable, Sendable {
        case neighbor, doubled, space, hesitation
    }

    /// The chance of a slip at each character where one can happen (Latin letters and digits, the spaces
    /// between words; Chinese, Japanese or Korean characters), and how many characters at least after one.
    static let slipChance = 0.035
    static let cjkSlipChance = 0.02
    static let slipGap = 12

    /// How `text` is typed: one run per character, paced as `delays` does, and with `mistakes` an occasional
    /// slip fixed on the way, about 3 in 100 characters and never two within 12 characters, nor at the start
    /// of the text or of a line. In prose any slip; in a web or email address, a number, a word that looks like
    /// code (`foo.bar`, `snake_case`, `camelCase`) or a line that does (indented, braces, `;`, `=`), only a
    /// wrong letter or digit, taken back at once (⌫ and the right one next): never a wrong bracket, quote,
    /// operator or space, which editors pair or indent on. Chinese, Japanese and Korean only hesitate (two
    /// characters typed, deleted, typed again): their wrong characters come from picking a candidate, not a
    /// neighboring key, and a made-up one would read as a glitch. The wrong letters are `keyboard`'s
    /// neighbors of the right one, a wrong digit one next to it. Replayed, the runs leave exactly `text`.
    public static func plan(for text: String, rate: Double, varies: Bool = false, mistakes: Bool = false,
                            keyboard: Keyboard = .qwerty,
                            random: () -> Double = { Double.random(in: 0..<1) }) -> [Run] {
        let characters = Array(text)
        let plain = zip(characters, delays(for: text, rate: rate, varies: varies, random: random))
            .map { Step(.type(String($0)), after: $1) }
        func single(_ i: Int) -> Run { Run(text: String(characters[i]), steps: [plain[i]], plain: [plain[i]]) }
        guard mistakes else { return characters.indices.map(single) }

        let places = SlipPlaces(characters)
        let base = 1 / min(max(rate, slowestRate), fastestRate)
        func pick<T>(_ items: [T]) -> T { items[min(Int(random() * Double(items.count)), items.count - 1)] }
        // Noticing takes a moment; ⌫ is quick; typing again starts at the usual pace.
        func notice() -> Double { base * (2 + 2 * random()) }
        func erase() -> Double { base * (0.35 + 0.3 * random()) }
        func again() -> Double { base * (0.8 + 0.4 * random()) }
        func typed(_ range: Range<Int>) -> [Step] { Array(plain[range]) }
        func retyped(_ range: Range<Int>) -> [Step] {
            range.map { Step(.type(String(characters[$0])), after: $0 == range.lowerBound ? again() : plain[$0].delay) }
        }
        func deletes(_ count: Int) -> [Step] { (0..<count).map { Step(.delete, after: $0 == 0 ? notice() : erase()) } }
        func run(_ range: Range<Int>, _ steps: [Step]) -> Run {
            Run(text: String(characters[range]), steps: steps, plain: Array(plain[range]))
        }

        func slip(at i: Int) -> (run: Run, length: Int)? {
            let kinds = Slip.allCases.filter { places.allows($0, at: i, keyboard: keyboard) }
            // Not right after a line break: an editor may indent there.
            guard !characters[i - 1].isNewline else { return nil }
            guard !kinds.isEmpty,
                  random() < (places.kinds[i] == .cjk ? cjkSlipChance : slipChance) else { return nil }
            // A neighboring key most often; a word taken back the least.
            let weighted = kinds.flatMap { kind -> [Slip] in
                switch kind {
                case .neighbor: return Array(repeating: kind, count: 5)
                case .doubled, .space: return Array(repeating: kind, count: 2)
                case .hesitation: return [kind]
                }
            }
            let character = characters[i]
            switch pick(weighted) {
            case .neighbor where places.kinds[i] == .code:
                // In code: the wrong one, then corrected at once (⌫ and the right one in one go).
                let wrong = pick(places.wrong(for: character, keyboard: keyboard))
                return (run(i..<(i + 1), [Step(.type(String(wrong)), after: plain[i].delay),
                                          Step(.correct(String(character)), after: notice())]), 1)
            case .neighbor:
                let wrong = pick(keyboard.neighbors(of: character))
                // 0–3 more letters of the word before it's noticed: fixed before the word ends, as an app's
                // spelling correction may change a word at the space after it.
                var more = 0
                let wanted = Int(random() * 4)
                while more < wanted, i + 1 + more < characters.count, places.kinds[i + 1 + more] == .letter { more += 1 }
                let range = i..<(i + 1 + more)
                return (run(range, [Step(.type(String(wrong)), after: plain[i].delay)] + typed((i + 1)..<range.upperBound)
                            + deletes(range.count) + retyped(range)), range.count)
            case .doubled, .space:
                let twice = Step(.type(String(character)), after: base * (0.4 + 0.3 * random()))
                return (run(i..<(i + 1), [plain[i], twice] + deletes(1)), 1)
            case .hesitation:
                let range = i..<places.wordEnd(at: i)
                return (run(range, typed(range) + deletes(range.count) + retyped(range)), range.count)
            }
        }

        var runs: [Run] = []
        var i = 0
        var quietUntil = 1  // the first character is just typed
        while i < characters.count {
            if i >= quietUntil, let (run, length) = slip(at: i) {
                runs.append(run)
                i += length
                quietUntil = i + slipGap
            } else {
                runs.append(single(i))
                i += 1
            }
        }
        return runs
    }

    /// Where in a text a slip may happen: which characters are letters of a plain word, spaces between
    /// such words, Chinese, Japanese or Korean characters, or letters and digits of code, an address or a
    /// number (`code`: only a wrong one, taken back at once). Everything else is left alone.
    struct SlipPlaces {
        enum Kind: Equatable { case none, letter, space, cjk, code }
        let characters: [Character]
        private(set) var kinds: [Kind]

        /// Characters that make a word (or, `codeLine`, a line) look like code.
        static let codeCharacters = Set("/\\_=<>{}[]$#%&|~^*+`")
        static let codeLine = Set("{};=`")

        init(_ characters: [Character]) {
            self.characters = characters
            kinds = Array(repeating: .none, count: characters.count)
            // Lines: the code ones (and those in a ``` block) are code; in a text mostly of code, all of them.
            var lines: [Range<Int>] = []
            var start = 0
            for (i, character) in characters.enumerated() where character.isNewline {
                lines.append(start..<i)
                start = i + 1
            }
            lines.append(start..<characters.count)
            var inBlock = false
            var prose: [Range<Int>] = []
            var code: [Range<Int>] = []
            for line in lines where !line.isEmpty {
                let text = String(characters[line])
                if text.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    inBlock.toggle()
                } else if inBlock || text.hasPrefix("  ") || text.hasPrefix("\t") || text.contains(where: Self.codeLine.contains)
                            || text.contains("()") {
                    code.append(line)
                } else {
                    prose.append(line)
                }
            }
            if code.count * 3 >= prose.count + code.count {
                code += prose
                prose = []
            }
            for line in code { markCode(line) }
            for line in prose { mark(line) }
            // A space between two plain words (after a comma or a full stop too), alone.
            for i in characters.indices where characters[i] == " " && i > 0 && i + 1 < characters.count {
                let before = kinds[i - 1] == .letter
                    || (i > 1 && ",.;:!?".contains(characters[i - 1]) && kinds[i - 2] == .letter)
                if before && kinds[i + 1] == .letter { kinds[i] = .space }
            }
        }

        /// Marks the plain words of a line, word by word (split at spaces, and where CJK meets other letters).
        private mutating func mark(_ line: Range<Int>) {
            var i = line.lowerBound
            while i < line.upperBound {
                guard !characters[i].isWhitespace else { i += 1; continue }
                var end = i
                while end < line.upperBound, !characters[end].isWhitespace { end += 1 }
                let token = String(characters[i..<end])
                // A web or email address, or anything with code's characters, is code.
                let address = token.contains("://") || token.lowercased().contains("www.") || token.contains("@")
                if address || token.contains(where: Self.codeCharacters.contains) {
                    markCode(i..<end)
                } else {
                    var j = i
                    while j < end {
                        var k = j + 1
                        let cjk = Self.isCJK(characters[j])
                        while k < end, Self.isCJK(characters[k]) == cjk { k += 1 }
                        if cjk {
                            for n in j..<k { kinds[n] = .cjk }
                        } else if Self.isPlainWord(characters[j..<k]) {
                            for n in j..<k where characters[n].isASCII && characters[n].isLetter { kinds[n] = .letter }
                        } else {
                            markCode(j..<k)  // a number, `foo.bar`, `camelCase`
                        }
                        j = k
                    }
                }
                i = end
            }
        }

        /// The ASCII letters and digits of `range` as code.
        private mutating func markCode(_ range: Range<Int>) {
            for n in range where characters[n].isASCII && (characters[n].isLetter || characters[n].isNumber) { kinds[n] = .code }
        }

        /// The wrong characters for `character` in code: a neighboring letter on `keyboard`, or a digit next to it.
        func wrong(for character: Character, keyboard: Keyboard) -> [Character] {
            guard let digit = character.wholeNumberValue, character.isASCII else { return keyboard.neighbors(of: character) }
            return [digit - 1, digit + 1].filter { (0...9).contains($0) }.map { Character(String($0)) }
        }

        /// Letters only (an apostrophe or hyphen between them), around them at most punctuation; no capital
        /// inside (`camelCase`, `iPhone`), no digit, no dot between letters (`foo.bar`, `e.g.`).
        static func isPlainWord(_ word: ArraySlice<Character>) -> Bool {
            let trim = Set(".,;:!?\"'“”‘’()…")
            var core = word[...]
            while let first = core.first, trim.contains(first) { core = core.dropFirst() }
            while let last = core.last, trim.contains(last) { core = core.dropLast() }
            guard !core.isEmpty else { return false }
            var previous: Character?
            for character in core {
                if character.isASCII && character.isLetter {
                    if character.isUppercase, let previous, previous.isLetter { return false }
                } else if "'’-".contains(character) {
                    guard let previous, previous.isLetter else { return false }
                } else {
                    return false
                }
                previous = character
            }
            return previous?.isLetter == true
        }

        /// Chinese, Japanese or Korean: an ideograph, kana or a Hangul syllable.
        static func isCJK(_ character: Character) -> Bool {
            character.unicodeScalars.contains { scalar in
                scalar.properties.isIdeographic || (0x3040...0x30FF).contains(scalar.value)
                    || (0xAC00...0xD7A3).contains(scalar.value)
            }
        }

        /// The end of the word of plain letters starting at `i` (letters only: none with an apostrophe).
        func wordEnd(at i: Int) -> Int {
            var end = i
            while end < kinds.count, kinds[end] == .letter || (kinds[i] == .cjk && kinds[end] == .cjk && end < i + 2) {
                end += 1
            }
            return end
        }

        func allows(_ slip: Slip, at i: Int, keyboard: Keyboard) -> Bool {
            switch slip {
            case .neighbor:
                if kinds[i] == .code { return !wrong(for: characters[i], keyboard: keyboard).isEmpty }
                return kinds[i] == .letter && !keyboard.neighbors(of: characters[i]).isEmpty
            case .doubled: return kinds[i] == .letter
            case .space: return kinds[i] == .space
            case .hesitation:
                if kinds[i] == .cjk { return i + 1 < kinds.count && kinds[i + 1] == .cjk }
                // A word of 2–6 letters, from its start to its end (not part of "don't" or "well-known").
                guard kinds[i] == .letter, i == 0 || !Self.joins(characters[i - 1]) else { return false }
                let end = wordEnd(at: i)
                return (2...6).contains(end - i) && (end == characters.count || !Self.joins(characters[end]))
            }
        }

        private static func joins(_ character: Character) -> Bool { character.isLetter || "'’-".contains(character) }
    }

    /// Which letters are next to which on the keyboard, by the keys' places on a Mac keyboard: a typo's wrong letter.
    public struct Keyboard: Sendable {
        /// The letter keys' codes row by row (the Q, A and Z rows of a US keyboard), each row shifted to the
        /// right of the one above as on the keyboard.
        static let rows: [(shift: Double, keys: [UInt16])] = [
            (0, [0x0C, 0x0D, 0x0E, 0x0F, 0x11, 0x10, 0x20, 0x22, 0x1F, 0x23, 0x21, 0x1E]),
            (0.25, [0x00, 0x01, 0x02, 0x03, 0x05, 0x04, 0x26, 0x28, 0x25, 0x29, 0x27]),
            (0.75, [0x06, 0x07, 0x08, 0x09, 0x0B, 0x2D, 0x2E, 0x2B, 0x2F, 0x2C]),
        ]
        /// What those keys type on a US keyboard.
        static let usKeys: [UInt16: String] = Dictionary(uniqueKeysWithValues: zip(
            rows.flatMap(\.keys), ["qwertyuiop[]", "asdfghjkl;'", "zxcvbnm,./"].flatMap { $0.map(String.init) }))

        private let neighbors: [Character: [Character]]

        /// The neighbors on a layout where key `code` types `typing(code)` (without modifiers): keys side by
        /// side in a row, or touching in the row above or below.
        public init(typing: (UInt16) -> String) {
            var places: [(letter: Character, row: Int, x: Double)] = []
            for (row, line) in Self.rows.enumerated() {
                for (column, key) in line.keys.enumerated() {
                    let typed = typing(key).lowercased()
                    if typed.count == 1, let letter = typed.first, letter.isLetter {
                        places.append((letter, row, Double(column) + line.shift))
                    }
                }
            }
            var neighbors: [Character: [Character]] = [:]
            for a in places {
                neighbors[a.letter] = places.filter { b in
                    b.letter != a.letter
                        && ((b.row == a.row && abs(b.x - a.x) == 1) || (abs(b.row - a.row) == 1 && abs(b.x - a.x) < 1))
                }.map(\.letter)
            }
            self.neighbors = neighbors
        }

        /// A US keyboard (QWERTY).
        public static let qwerty = Keyboard { usKeys[$0] ?? "" }

        /// The keyboard `layout` types with (AZERTY, QWERTZ, Dvorak …).
        public init(layout: any KeyTranslator) {
            self.init { code in
                var state: UInt32 = 0
                return layout.translate(code, [], state: &state, deadKeys: false)
            }
        }

        /// The letters next to `letter`'s key, a capital's as capitals; none for a letter the keyboard hasn't.
        public func neighbors(of letter: Character) -> [Character] {
            guard let lower = String(letter).lowercased().first, let near = neighbors[lower] else { return [] }
            guard letter.isUppercase else { return near }
            return near.compactMap { String($0).uppercased().count == 1 ? String($0).uppercased().first : nil }
        }
    }
    /// Typing out a plan step by step, and what's in the document meanwhile: `stop` leaves it right
    /// whenever typing stops. Places are UTF-16 offsets (as text fields count) from where typing started.
    public struct Typing: Sendable {
        /// What a step does to the document: types at the end, or replaces the `length` UTF-16 units at
        /// `location`, which hold `replacing`, with `with` (never empty: see `erase`).
        public enum Edit: Equatable, Sendable {
            case type(String)
            case replace(location: Int, length: Int, with: String, replacing: String)
        }

        /// The plan; a slip the field couldn't take back becomes plain text as it was typed (`keepTyped`).
        public private(set) var runs: [Run]
        private var run = 0
        private var step = 0
        private var plainly = false
        /// The characters typed, as they are in the document now (a typo in it until it's fixed).
        public private(set) var typed: [String] = []
        /// Its length in UTF-16, and where the current run's characters start in `typed`.
        public private(set) var length = 0
        private var runStart = 0

        public init(_ runs: [Run]) { self.runs = runs }

        public var isDone: Bool { run >= runs.count }
        /// Whether the next step starts a slip: before it the app checks it can fix one here, else `skipSlip`.
        public var startsSlip: Bool { !isDone && step == 0 && !plainly && runs[run].isSlip }
        /// Whether a slip is under way: its typo may be in the document.
        public var inSlip: Bool { !isDone && step > 0 && !plainly && runs[run].isSlip }
        /// The coming slip's text typed without it.
        public mutating func skipSlip() { if startsSlip { plainly = true } }

        /// Makes the coming slip the plainest one, to see whether the field takes a typo back: its wrong character,
        /// then corrected in one go, the rest of its text plainly. False when it has no wrong character (a letter
        /// or space typed twice, a word typed again): then it's typed plainly.
        public mutating func probe() -> Bool {
            guard startsSlip, case let .type(wrong)? = runs[run].steps.first?.stroke,
                  let right = runs[run].text.first.map(String.init), wrong != right else {
                skipSlip()
                return false
            }
            let current = runs[run]
            let notice = current.steps.count > 1 ? current.steps[1].delay : current.plain[0].delay
            runs[run].steps = [current.steps[0], Step(.correct(right), after: notice)] + current.plain.dropFirst()
            return true
        }

        /// The pause before the next step (nil: done).
        public var nextDelay: Double? {
            isDone ? nil : (plainly ? runs[run].plain : runs[run].steps)[step].delay
        }

        /// The text typed from UTF-16 offset `offset` on, as it is in the document now.
        public func text(from offset: Int) -> String {
            var at = length
            var first = typed.endIndex
            while at > offset, first > typed.startIndex {
                first -= 1
                at -= typed[first].utf16.count
            }
            return typed[first...].joined()
        }

        /// The text not typed yet: what's left of the current run, after what of it is right, and the runs after it.
        public var rest: String {
            guard !isDone else { return "" }
            let intended = runs[run].text.map(String.init)
            return (intended[rightSoFar...] + runs[(run + 1)...].map(\.text)).joined()
        }

        /// How many characters of the current run are in the document as they should be.
        private var rightSoFar: Int {
            guard !isDone else { return 0 }
            return zip(typed[runStart...], runs[run].text.map(String.init)).prefix { $0 == $1 }.count
        }

        /// The next step: its edit, and the pause before it.
        public mutating func next() -> (edit: Edit, delay: Double)? {
            guard !isDone else { return nil }
            let steps = plainly ? runs[run].plain : runs[run].steps
            let current = steps[step]
            let edit: Edit
            switch current.stroke {
            case let .type(character):
                typed.append(character)
                length += character.utf16.count
                edit = .type(character)
            case .delete:
                edit = erase(1, putting: "")
            case let .correct(character):
                edit = erase(1, putting: character)
                typed.append(character)
                length += character.utf16.count
            }
            step += 1
            if step == steps.count { (run, step, plainly, runStart) = (run + 1, 0, false, typed.count) }
            return (edit, current.delay)
        }

        /// When typing stops: what leaves the document right. A typo not fixed yet is taken out (`dropTypo`); then
        /// with `insertingRest` the rest of the text goes in, else the document holds the start of the text. nil:
        /// nothing to do.
        public func stop(insertingRest: Bool) -> Edit? {
            var copy = self
            let edit = copy.dropTypo()
            let rest = insertingRest ? copy.rest : ""
            guard case let .replace(location, length, with, replacing)? = edit else { return rest.isEmpty ? nil : .type(rest) }
            return .replace(location: location, length: length, with: with + rest, replacing: replacing)
        }

        /// Gives up the slip under way: the edit that takes its typo out (nil: none in the document), and the
        /// rest of its text is typed plainly. A single wrong character is replaced with the rest of the run's text
        /// in one go: were the field to put that at the caret instead, the typo would be the one thing off.
        public mutating func dropTypo() -> Edit? {
            guard inSlip else { return nil }
            let right = rightSoFar
            let wrong = typed.count - runStart - right
            let remainder = Array(runs[run].text.map(String.init)[right...])
            runs[run].steps = runs[run].plain
            guard wrong > 0 else {
                goOn(at: right)
                return nil
            }
            if wrong == 1, !remainder.isEmpty {
                let edit = erase(1, putting: remainder.joined())
                typed += remainder
                length += remainder.joined().utf16.count
                goOn(at: runs[run].plain.count)
                return edit
            }
            let edit = erase(wrong, putting: "")
            goOn(at: right)
            return edit
        }

        /// Keeps what the slip under way typed, its typo too (the field didn't take it back), and `adding`, what a
        /// fix put at the caret instead: the run's text becomes that, and the rest of its characters are typed
        /// plainly after it.
        public mutating func keepTyped(adding extra: String = "") {
            guard !isDone, typed.count > runStart || !extra.isEmpty else { return }
            let current = runs[run]
            let right = rightSoFar
            let added = extra.map(String.init)
            // What was added carries on the run's text (a correction, its rest): the characters after it follow.
            let carriesOn = !added.isEmpty && Array(current.text.map(String.init).dropFirst(right).prefix(added.count)) == added
            typed += added
            length += extra.utf16.count
            let kept = Array(typed[runStart...])
            let rest = Array(current.plain.dropFirst(min(carriesOn ? right + added.count : kept.count, current.plain.count)))
            let steps = kept.map { Step(.type($0), after: 0) } + rest
            let text = kept.joined() + rest.compactMap { if case let .type(c) = $0.stroke { c } else { nil } }.joined()
            runs[run] = Run(text: text, steps: steps, plain: steps)
            goOn(at: kept.count)
        }

        /// Goes on with the current run's plain steps from `step`.
        private mutating func goOn(at step: Int) {
            (self.step, plainly) = (step, false)
            if step >= runs[run].steps.count { (run, self.step, runStart) = (run + 1, 0, typed.count) }
        }

        /// Takes the last `count` characters out, putting `text` in their place. Never with an empty string: an
        /// input method's empty insert never reaches the app (NSTextView gets nothing), so with nothing to put
        /// there the character before them is taken too and put back; it's never a line break (no slip starts a line).
        private mutating func erase(_ count: Int, putting text: String) -> Edit {
            let gone = typed.suffix(count).joined()
            typed.removeLast(count)
            length -= gone.utf16.count
            if text.isEmpty, let before = typed.last, !before.contains(where: \.isNewline) {
                let width = before.utf16.count
                return .replace(location: length - width, length: width + gone.utf16.count, with: before, replacing: before + gone)
            }
            return .replace(location: length, length: gone.utf16.count, with: text, replacing: gone)
        }
    }

    /// A text field typed into (`Typist`). Places in UTF-16, as text fields count.
    public protocol Field: AnyObject {
        /// The caret; nil when the field doesn't say, or text is selected.
        var caret: Int? { get }
        /// The length of all its text; nil when the field doesn't say.
        var length: Int? { get }
        /// The text in `range`; nil when the field doesn't say.
        func read(_ range: NSRange) -> String?
        /// Types `text` at the caret.
        func type(_ text: String)
        /// Replaces `range` with `text` (the text input protocol's `replacementRange`).
        func replace(_ range: NSRange, with text: String)
    }

    /// Types a plan into a field, and keeps the field right while a typo is in it.
    ///
    /// Until a fix is seen taken in this field (`proven`), a typo is only a probe: a wrong character corrected in
    /// one go (`Typing.probe`), so a field that ignores replacement ranges ends up one character off at most. Before
    /// every step of a slip, after each fix, and when typing stops, the field must hold exactly what was typed, be
    /// as long as that, and have its caret right after it; a field that lags (Chromium tells the caret late) is
    /// given `patience` checks (`step` says `waiting`; `stop` waits in between). Then, when it still doesn't:
    /// - it shows what was there before the last fix, or that with the fix's text at the caret: the field didn't
    ///   take it (it ignores replacement ranges). What's there is kept, the rest goes on after it, and `fieldFailed`
    ///   (the app gets no more typos);
    /// - it holds what was typed, no more and no less, but the caret is elsewhere (a click, the app moved it):
    ///   the typo is taken out where it was typed, if the text there is still exactly that, and the rest typed plainly;
    /// - anything else (an editor changed or added text): the typed span, up to the caret, is replaced with what
    ///   it should be, if it's about that long, else left alone. Not the field's failing: it isn't remembered.
    /// After any of these, no more typos in this run.
    public struct Typist {
        public enum Progress: Equatable, Sendable { case typed, waiting, done }
        enum Look: Equatable { case asTyped, notFixed, inserted, moved, changed }

        public private(set) var typing: Typing
        /// Where typing started in the field, and the field's length then (nil: it doesn't say).
        public let start: Int
        let lengthBefore: Int?
        /// Whether typos are still made in this run.
        public private(set) var mistakes: Bool
        /// Whether a fix was seen taken in this field: until then a typo is a probe.
        public private(set) var proven: Bool
        /// The field didn't take a typo's fix: its app should get no more typos.
        public private(set) var fieldFailed = false
        /// What happened when it didn't (for the log).
        public private(set) var failure: String?
        /// The field read back as typed up to here.
        private var checked = 0
        /// The last fix until it's seen taken: what was typed before it, and what it put in.
        private var lastFix: (before: Typing, with: String)?
        private var waits = 0
        /// Checks before a field that doesn't hold what was typed is taken as changed (50 ms apart in the app).
        public static let patience = 6

        public init(_ runs: [Run], start: Int, length: Int? = nil, proven: Bool = false) {
            typing = Typing(runs)
            self.start = start
            lengthBefore = length
            mistakes = runs.contains { $0.isSlip }
            self.proven = proven
        }

        public var nextDelay: Double? { typing.nextDelay }
        public var isDone: Bool { typing.isDone && lastFix == nil }
        public var rest: String { typing.rest }
        private var pending: Bool { lastFix != nil || typing.inSlip }

        /// The next step into `field`; `waiting`: check again a little later, without the step's pause.
        public mutating func step(in field: Field) -> Progress {
            if pending {
                let look = look(field)
                if look != .asTyped {
                    if waits < Self.patience {
                        waits += 1
                        return .waiting
                    }
                    settle(look, in: field)
                } else if lastFix != nil {
                    proven = true
                }
                (waits, lastFix) = (0, nil)
            }
            guard !typing.isDone else { return .done }
            if typing.startsSlip {
                // A typo only where the field holds what was typed, the caret after it; a probe until one was taken.
                if mistakes, look(field) == .asTyped, proven || typing.probe() { checked = typing.length } else { typing.skipSlip() }
            }
            let before = typing
            guard let (edit, _) = typing.next() else { return .done }
            switch edit {
            case let .type(character):
                field.type(character)
            case let .replace(location, length, with, _):
                field.replace(NSRange(location: start + location, length: length), with: with)
                lastFix = (before, with)
            }
            return .typed
        }

        /// Stops: a typo still in the field is taken out where it was typed, if the text there is still exactly
        /// that, and checked like any fix (`wait` between checks). Returns what to type then at the caret: the rest
        /// with `insertingRest`, else nothing.
        public mutating func stop(insertingRest: Bool, in field: Field, wait: () -> Void = {}) -> String {
            if pending {
                let look = settled(field, wait: wait)
                if look != .asTyped { settle(look, in: field) } else if lastFix != nil { proven = true }
                lastFix = nil
            }
            if typing.inSlip {
                let before = typing
                var dropped = typing
                if case let .replace(location, length, with, replacing)? = dropped.dropTypo() {
                    let range = NSRange(location: start + location, length: length)
                    if read(field, range) == replacing {
                        field.replace(range, with: with)
                        (typing, lastFix) = (dropped, (before, with))
                        let look = settled(field, wait: wait)
                        if look == .notFixed || look == .inserted { settle(look, in: field) }
                        lastFix = nil
                    } else {
                        typing.keepTyped()
                    }
                } else {
                    typing = dropped
                }
            }
            return insertingRest ? typing.rest : ""
        }

        /// The field's look, checked up to `patience` more times (`wait` in between) while it isn't as typed.
        private func settled(_ field: Field, wait: () -> Void) -> Look {
            var look = look(field)
            for _ in 0..<Self.patience where look != .asTyped {
                wait()
                look = self.look(field)
            }
            return look
        }

        /// How the field compares with what was typed since the last check.
        func look(_ field: Field) -> Look {
            let from = min(checked, typing.length)
            let caret = field.caret
            let length = field.length
            /// Whether the field is as long as with `typed` and `extra` more (unknown: yes).
            func long(_ typed: Typing, _ extra: Int = 0) -> Bool {
                lengthBefore.map { length == nil || length == $0 + typed.length + extra } ?? true
            }
            let asTyped = read(field, NSRange(location: start + from, length: typing.length - from)) == typing.text(from: from)
                && long(typing)
            if asTyped && caret == start + typing.length { return .asTyped }
            if let (before, with) = lastFix, before.length >= from {
                let shown = before.text(from: from)
                let span = before.length - from
                if caret == start + before.length, long(before),
                   read(field, NSRange(location: start + from, length: span)) == shown {
                    return .notFixed
                }
                let width = with.utf16.count
                if width > 0, caret == start + before.length + width, long(before, width),
                   read(field, NSRange(location: start + from, length: span + width)) == shown + with {
                    return .inserted
                }
            }
            return asTyped ? .moved : .changed
        }

        private func read(_ field: Field, _ range: NSRange) -> String? {
            range.length == 0 ? "" : field.read(range)
        }

        /// The field didn't hold what was typed, after waiting: no more typos in this run, and the field made right
        /// as far as it can be.
        private mutating func settle(_ look: Look, in field: Field) {
            mistakes = false
            switch look {
            case .asTyped:
                break
            case .notFixed, .inserted:
                guard let (before, with) = lastFix else { break }
                typing = before
                typing.keepTyped(adding: look == .inserted ? with : "")
                fieldFailed = true
                failure = look == .inserted ? "a typo's fix went in at the caret: replacement range ignored"
                    : "a typo's fix wasn't taken"
            case .moved:
                var dropped = typing
                if case let .replace(location, length, with, replacing)? = dropped.dropTypo() {
                    let range = NSRange(location: start + location, length: length)
                    guard read(field, range) == replacing else {
                        typing.keepTyped()
                        break
                    }
                    field.replace(range, with: with)
                }
                typing = dropped
            case .changed:
                // The typed span, up to the caret, replaced with what it should be, if it's about that long.
                let from = min(checked, typing.length)
                var dropped = typing
                _ = dropped.dropTypo()
                let should = dropped.text(from: from)
                guard let caret = field.caret, caret >= start + from, caret - (start + from) <= should.utf16.count + 16,
                      !should.isEmpty || caret > start + from,
                      read(field, NSRange(location: start + from, length: caret - start - from)) != nil else {
                    typing.keepTyped()
                    break
                }
                if should.isEmpty {
                    // Nothing to put there: the character before goes too, and back (never an empty insert).
                    let before = dropped.text(from: 0).suffix(1).description
                    let width = before.utf16.count
                    guard width > 0, !before.contains(where: \.isNewline) else { typing.keepTyped(); break }
                    field.replace(NSRange(location: start + from - width, length: caret - start - from + width), with: before)
                } else {
                    field.replace(NSRange(location: start + from, length: caret - start - from), with: should)
                }
                typing = dropped
            }
        }
    }
}
