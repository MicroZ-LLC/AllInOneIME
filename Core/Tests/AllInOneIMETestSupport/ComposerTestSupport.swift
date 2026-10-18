import Foundation
@testable import AllInOneIMECore

/// Keys as the input controller hands them to the composer: a typed character, and the keys the tests press.
public func k(_ s: String, mods: KeyModifiers = []) -> KeyEvent { KeyEvent(keyCode: 0, characters: s, modifiers: mods) }
public let spaceKey = KeyEvent(keyCode: VirtualKey.space, characters: " ")
public let enterKey = KeyEvent(keyCode: VirtualKey.returnKey, characters: "\r")
public let escKey = KeyEvent(keyCode: VirtualKey.escape, characters: "\u{1B}")
public let backspaceKey = KeyEvent(keyCode: VirtualKey.delete, characters: "\u{7F}")
public let upKey = KeyEvent(keyCode: VirtualKey.up, characters: "\u{F700}")
public let downKey = KeyEvent(keyCode: VirtualKey.down, characters: "\u{F701}")
public let shiftSpace = KeyEvent(keyCode: VirtualKey.space, characters: " ", modifiers: .shift)
/// ⌥Space as AppKit delivers it on a US layout (it types a no-break space).
public let optionSpace = KeyEvent(keyCode: VirtualKey.space, characters: "\u{A0}", charactersIgnoringModifiers: " ", modifiers: .option)

/// Minimal stand-in for Rime: whole-input candidates from a tiny dictionary.
public final class FakeEngine: PinyinEngine {
    public var dictionary = [
        "nihao": ["你好", "拟好"],
        "wo": ["我", "窝"],
        "jintian": ["今天", "金天"],
    ]
    public var input = ""
    public var highlighted = 0
    public var ascii = false
    /// Every key librime would have been given, in order.
    public var keys: [(keycode: Int32, mask: Int32)] = []
    private var pendingCommit: String?

    public init() {}

    public func candidates() -> [String] { menu().words }

    /// The candidates for the input and how many letters picking one uses up: a whole-input entry,
    /// else (like Rime's partial candidates) the longest known prefix, else the letters as typed.
    public func menu() -> (words: [String], length: Int) {
        guard !input.isEmpty else { return ([], 0) }
        if let words = dictionary[input] { return (words, input.count) }
        for n in stride(from: input.count - 1, to: 0, by: -1) {
            if let words = dictionary[String(input.prefix(n))] { return (words, n) }
        }
        return ([input], input.count)
    }

    public func processKey(_ keycode: Int32, mask: Int32) -> Bool {
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

    public func takeCommit() -> String? {
        defer { pendingCommit = nil }
        return pendingCommit
    }

    public func snapshot() -> EngineSnapshot {
        EngineSnapshot(
            isComposing: !input.isEmpty, preedit: input, cursor: input.count,
            candidates: candidates().enumerated().map { EngineCandidate(label: String($0.offset + 1), text: $0.element) },
            highlighted: highlighted, isAsciiMode: ascii)
    }

    public func selectCandidate(onPage index: Int) -> Bool {
        guard !input.isEmpty, candidates().indices.contains(index) else { return false }
        return select(index)
    }

    /// Like librime: the highlighted candidate, then any letters it doesn't cover, as typed.
    public func commitComposition() -> String? {
        guard !input.isEmpty else { return nil }
        let (all, length) = menu()
        emit(all[min(highlighted, all.count - 1)])
        emit(String(input.dropFirst(length)))
        input = ""
        highlighted = 0
        return takeCommit()
    }

    public var rawInput: String { input }
    public func clearComposition() { input = "" }
    public func setAsciiMode(_ on: Bool) { ascii = on }
}

/// What the composer typed (its commits), in order.
public func commits(_ r: Composer.Response) -> [String] { commits(r.effects) }
public func commits(_ effects: [Composer.Effect]) -> [String] {
    effects.compactMap { if case let .commit(s) = $0 { return s } else { return nil } }
}
