import Foundation

/// Level one without a language pack: English letters only. Every key goes to the application (or to
/// the draft of an @ command), as librime does in Latin mode, so typing and commands work before any
/// pack is installed; asking it for Chinese leaves it in Latin mode.
public final class LatinEngine: PinyinEngine {
    public init() {}

    public func processKey(_ keycode: Int32, mask: Int32) -> Bool { false }
    public func takeCommit() -> String? { nil }
    public func snapshot() -> EngineSnapshot { EngineSnapshot(isAsciiMode: true) }
    public func selectCandidate(onPage index: Int) -> Bool { false }
    public func commitComposition() -> String? { nil }
    public var rawInput: String { "" }
    public func clearComposition() {}
    public func setAsciiMode(_ on: Bool) {}
}
