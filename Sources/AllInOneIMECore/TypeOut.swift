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
    /// What a key does: types one character (a `Character`, as a string), or ⌫ deletes the last one typed.
    public enum Stroke: Equatable, Sendable {
        case type(String)
        case delete
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

    /// The slips a person makes and fixes (`plan`): a neighboring key, noticed 0–3 letters later; a letter
    /// typed twice; a space typed twice; a short word typed, taken back and typed again (a hesitation).
    public enum Slip: CaseIterable, Sendable {
        case neighbor, doubled, space, hesitation
    }

    /// The chance of a slip at each character where one can happen (Latin letters and the spaces between
    /// words; Chinese, Japanese or Korean characters), and how many characters at least after one.
    static let slipChance = 0.035
    static let cjkSlipChance = 0.02
    static let slipGap = 12

    /// How `text` is typed: one run per character, paced as `delays` does, and with `mistakes` an occasional
    /// slip fixed at once, about 3 in 100 characters of prose and never two within 12 characters. None
    /// in a web address, an email address, a number, a word that looks like code (`foo.bar`, `snake_case`,
    /// `camelCase`) or a line that does (indented, braces, `;`, `=`), nor at the very first character.
    /// Chinese, Japanese and Korean only hesitate (two characters typed, deleted, typed again): their
    /// wrong characters come from picking a candidate, not a neighboring key, and a made-up one would read
    /// as a glitch. The wrong letters are `keyboard`'s neighbors of the right one. Replayed, the runs
    /// leave exactly `text`.
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
        var quietUntil = 1  // the first character is just typed: a fix always has one before it
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
    /// such words, or Chinese, Japanese or Korean characters. Everything else is left alone.
    struct SlipPlaces {
        enum Kind: Equatable { case none, letter, space, cjk }
        let characters: [Character]
        private(set) var kinds: [Kind]

        /// Characters that make a word (or, `codeLine`, a line) look like code.
        static let codeCharacters = Set("/\\_=<>{}[]$#%&|~^*+`")
        static let codeLine = Set("{};=`")

        init(_ characters: [Character]) {
            self.characters = characters
            kinds = Array(repeating: .none, count: characters.count)
            // Lines, the code ones (and those in a ``` block) left out; a text mostly of code has none.
            var lines: [Range<Int>] = []
            var start = 0
            for (i, character) in characters.enumerated() where character.isNewline {
                lines.append(start..<i)
                start = i + 1
            }
            lines.append(start..<characters.count)
            var inBlock = false
            var prose: [Range<Int>] = []
            var code = 0
            for line in lines where !line.isEmpty {
                let text = String(characters[line])
                if text.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    inBlock.toggle()
                    code += 1
                } else if inBlock || text.hasPrefix("  ") || text.hasPrefix("\t") || text.contains(where: Self.codeLine.contains)
                            || text.contains("()") {
                    code += 1
                } else {
                    prose.append(line)
                }
            }
            guard code * 3 < prose.count + code else { return }
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
                // A web or email address, or anything with code's characters, is left whole.
                let address = token.contains("://") || token.lowercased().contains("www.") || token.contains("@")
                if !address && !token.contains(where: Self.codeCharacters.contains) {
                    var j = i
                    while j < end {
                        var k = j + 1
                        let cjk = Self.isCJK(characters[j])
                        while k < end, Self.isCJK(characters[k]) == cjk { k += 1 }
                        if cjk {
                            for n in j..<k { kinds[n] = .cjk }
                        } else if Self.isPlainWord(characters[j..<k]) {
                            for n in j..<k where characters[n].isASCII && characters[n].isLetter { kinds[n] = .letter }
                        }
                        j = k
                    }
                }
                i = end
            }
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
            case .neighbor: return kinds[i] == .letter && !keyboard.neighbors(of: characters[i]).isEmpty
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
        public init(layout: KeyboardLayout) {
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
        /// What a step does to the document: types at the end, or replaces a range with a string.
        public enum Edit: Equatable, Sendable {
            case type(String)
            case replace(location: Int, length: Int, with: String)
        }

        public let runs: [Run]
        private var run = 0
        private var step = 0
        private var plainly = false
        /// The characters typed, as they are in the document now (a typo in it until it's fixed).
        public private(set) var typed: [String] = []
        /// Its length in UTF-16, and where the current run's characters start in `typed`.
        public private(set) var length = 0
        private var runStart = 0
        /// The length after the last typo was taken back.
        private var lastFix: Int?

        public init(_ runs: [Run]) { self.runs = runs }

        public var isDone: Bool { run >= runs.count }
        /// Whether the next step starts a slip: before it the app checks it can fix one here, else `skipSlip`.
        public var startsSlip: Bool { !isDone && step == 0 && !plainly && runs[run].isSlip }
        /// The coming slip's text typed without it.
        public mutating func skipSlip() { if startsSlip { plainly = true } }

        /// The pause before the next step (nil: done).
        public var nextDelay: Double? {
            isDone ? nil : (plainly ? runs[run].plain : runs[run].steps)[step].delay
        }

        /// The text typed from UTF-16 offset `offset` on, as it is in the document now.
        public func text(from offset: Int) -> String {
            var at = length
            var tail: [String] = []
            for character in typed.reversed() where at > offset {
                tail.append(character)
                at -= character.utf16.count
            }
            return tail.reversed().joined()
        }

        /// Whether a typo was taken back after `offset`.
        public func fixedTypo(after offset: Int) -> Bool { lastFix.map { $0 >= offset } ?? false }

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
                lastFix = length
            }
            step += 1
            if step == steps.count { (run, step, plainly, runStart) = (run + 1, 0, false, typed.count) }
            return (edit, current.delay)
        }

        /// When typing stops: what leaves the document right. A typo not fixed yet is taken out; then with
        /// `insertingRest` the rest of the text goes in at once, else the document holds the start of the text.
        /// nil: nothing to do.
        public func stop(insertingRest: Bool) -> Edit? {
            guard !isDone else { return nil }
            let wrong = typed.count - runStart - rightSoFar
            let rest = insertingRest ? rest : ""
            if wrong == 0 { return rest.isEmpty ? nil : .type(rest) }
            var copy = self
            return copy.erase(wrong, putting: rest)
        }

        /// Takes the last `count` characters out and puts `text` in their place. The character before them is
        /// replaced too, by itself: some apps take an empty insert as nothing to do. (A slip never starts at
        /// the first character, so there is one.)
        private mutating func erase(_ count: Int, putting text: String) -> Edit {
            let gone = typed.suffix(count).joined().utf16.count
            typed.removeLast(count)
            length -= gone
            let before = typed.last ?? ""
            return .replace(location: length - before.utf16.count, length: before.utf16.count + gone, with: before + text)
        }
    }
}
