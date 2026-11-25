import AllInOneIMECore
import AllInOneIMETestSupport

/// Models the existing pinyin behavior for an Option chord while composing: commit, then pass the key to the app.
final class OptionCommittingPinyinEngine: PinyinEngine {
    private let base = FakeEngine()
    private var pendingCommit: String?
    private(set) var selectedCandidates: [Int] = []

    func processKey(_ keycode: Int32, mask: Int32) -> Bool {
        if mask & RimeKey.altMask != 0, base.snapshot().isComposing {
            pendingCommit = base.commitComposition()
            return false
        }
        return base.processKey(keycode, mask: mask)
    }

    func takeCommit() -> String? {
        if let pendingCommit {
            self.pendingCommit = nil
            return pendingCommit
        }
        return base.takeCommit()
    }

    func snapshot() -> EngineSnapshot { base.snapshot() }
    func selectCandidate(onPage index: Int) -> Bool {
        selectedCandidates.append(index)
        return base.selectCandidate(onPage: index)
    }
    func commitComposition() -> String? { base.commitComposition() }
    var rawInput: String { base.rawInput }
    func clearComposition() { base.clearComposition() }
    func setAsciiMode(_ on: Bool) { base.setAsciiMode(on) }
}
