import Foundation
@testable import AllInOneIMECore

/// Minimal stand-in for Rime: whole-input candidates from a tiny dictionary.
final class FakeEngine: PinyinEngine {
    var dictionary = [
        "nihao": ["你好", "拟好"],
        "wo": ["我", "窝"],
        "jintian": ["今天", "金天"],
    ]
    var input = ""
    var highlighted = 0
    var ascii = false
    /// Every key librime would have been given, in order.
    var keys: [(keycode: Int32, mask: Int32)] = []
    private var pendingCommit: String?

    func candidates() -> [String] { menu().words }

    /// The candidates for the input and how many letters picking one uses up: a whole-input entry,
    /// else (like Rime's partial candidates) the longest known prefix, else the letters as typed.
    func menu() -> (words: [String], length: Int) {
        guard !input.isEmpty else { return ([], 0) }
        if let words = dictionary[input] { return (words, input.count) }
        for n in stride(from: input.count - 1, to: 0, by: -1) {
            if let words = dictionary[String(input.prefix(n))] { return (words, n) }
        }
        return ([input], input.count)
    }

    func processKey(_ keycode: Int32, mask: Int32) -> Bool {
        keys.append((keycode, mask))
        if ascii { return false }
        let composing = !input.isEmpty
        switch keycode {
        case 0x61...0x7A:
            input.append(Character(Unicode.Scalar(UInt8(keycode))))
            highlighted = 0
            return true
        case RimeKey.space where composing: return select(highlighted)
        case 0x31...0x35 where composing: return select(Int(keycode - 0x31))
        case RimeKey.returnKey where composing:
            emit(input)
            input = ""
            return true
        case RimeKey.backSpace where composing:
            input.removeLast()
            return true
        case RimeKey.escape where composing:
            input = ""
            return true
        case RimeKey.down where composing:
            highlighted = min(highlighted + 1, candidates().count - 1)
            return true
        case 0x2C:  // ','
            if composing { emit(candidates()[highlighted]); input = "" }
            emit("，")
            return true
        default:
            return composing
        }
    }

    private func select(_ index: Int) -> Bool {
        let (all, length) = menu()
        guard all.indices.contains(index) else { return true }
        emit(all[index])
        input.removeFirst(length)
        highlighted = 0
        return true
    }

    private func emit(_ s: String) { pendingCommit = (pendingCommit ?? "") + s }

    func takeCommit() -> String? {
        defer { pendingCommit = nil }
        return pendingCommit
    }

    func snapshot() -> EngineSnapshot {
        EngineSnapshot(
            isComposing: !input.isEmpty, preedit: input, cursor: input.count,
            candidates: candidates().enumerated().map { EngineCandidate(label: String($0.offset + 1), text: $0.element) },
            highlighted: highlighted, isAsciiMode: ascii)
    }

    func selectCandidate(onPage index: Int) -> Bool {
        guard !input.isEmpty, candidates().indices.contains(index) else { return false }
        return select(index)
    }

    /// Like librime: the highlighted candidate, then any letters it doesn't cover, as typed.
    func commitComposition() -> String? {
        guard !input.isEmpty else { return nil }
        let (all, length) = menu()
        emit(all[min(highlighted, all.count - 1)])
        emit(String(input.dropFirst(length)))
        input = ""
        highlighted = 0
        return takeCommit()
    }

    var rawInput: String { input }
    func clearComposition() { input = "" }
    func setAsciiMode(_ on: Bool) { ascii = on }
}

/// What the composer typed (its commits), in order.
func commits(_ r: Composer.Response) -> [String] { commits(r.effects) }
func commits(_ effects: [Composer.Effect]) -> [String] {
    effects.compactMap { if case let .commit(s) = $0 { return s } else { return nil } }
}
