import Foundation

extension TypeOut {
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
        private var stopStage = StopStage.start
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
            while true {
                if let rest = stopping(insertingRest: insertingRest, in: field) { return rest }
                wait()
            }
        }

        /// `stop` one look at the field at a time, for a caller that waits elsewhere, never on its own thread (the Mac's
        /// main thread): what to type at the caret once it is done; nil while the field isn't as typed yet, to be asked
        /// again a little later (`patience` times at most for each check). `waiting` false: done now, with the field as it
        /// looks now (as once `patience` is over).
        public mutating func stopping(insertingRest: Bool, in field: Field, waiting: Bool = true) -> String? {
            if stopStage == .start { (stopStage, waits) = (pending ? .checking : .dropping, 0) }
            if stopStage == .checking {
                let look = look(field)
                if look != .asTyped, waiting, waits < Self.patience { return waited() }
                if look != .asTyped { settle(look, in: field) } else if lastFix != nil { proven = true }
                (lastFix, stopStage, waits) = (nil, .dropping, 0)
            }
            if stopStage == .dropping { stopStage = dropTypo(in: field) ? .checkingDrop : .done }
            if stopStage == .checkingDrop {
                let look = look(field)
                if look != .asTyped, waiting, waits < Self.patience { return waited() }
                if look == .notFixed || look == .inserted { settle(look, in: field) }
                (lastFix, stopStage) = (nil, .done)
            }
            return insertingRest ? typing.rest : ""
        }

        /// Where `stopping` is: checking the field before a typo is taken out, then the typo's fix.
        enum StopStage { case start, checking, dropping, checkingDrop, done }

        /// One more look to wait for (`stopping`).
        private mutating func waited() -> String? {
            waits += 1
            return nil
        }

        /// When typing stops: a typo still in the field taken out where it was typed, if the text there is still exactly
        /// that (`stopping`). Whether it was: its fix to be checked.
        private mutating func dropTypo(in field: Field) -> Bool {
            guard typing.inSlip else { return false }
            let before = typing
            var dropped = typing
            guard case let .replace(location, length, with, replacing)? = dropped.dropTypo() else {
                typing = dropped
                return false
            }
            let range = NSRange(location: start + location, length: length)
            guard read(field, range) == replacing else {
                typing.keepTyped()
                return false
            }
            field.replace(range, with: with)
            (typing, lastFix) = (dropped, (before, with))
            return true
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
