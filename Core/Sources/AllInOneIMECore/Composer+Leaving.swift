import Foundation

// MARK: - Leaving the field while typing

extension Composer {
    /// The user left the field while typing: a click elsewhere or in it, another field, another app, the window closed
    /// (the shell's blur and commit). What is being composed and not yet confirmed (pinyin) is dropped and nothing of it
    /// goes in, the same in every app (the owner, 2026-11-15; #116). The rest goes as `commitAll` has it.
    public func leaveField() -> [Effect] { commitAll(convertingComposition: false) }
}
