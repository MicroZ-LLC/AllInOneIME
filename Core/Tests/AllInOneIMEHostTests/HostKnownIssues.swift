import Foundation

/// What the stress runs (`HostStressTests`) found that differs from profile to profile and isn't fixed: each a minimal
/// scenario, replayed here as a known issue (it fails where it says, and this test says so once it no longer does), and
/// recognised in a stress run's failures so that a run finds what is new. Each waits for the owner: the fix is a choice
/// of what the user sees (AGENTS.md rule 1), not a small fix.
enum HostKnownIssues {
    // None now. The "@" list's text put in on `blur` and lost where the field had let go first (`atListLostOnBlur`) is
    // fixed: a draft is kept for its field when the focus is lost without a click (#180: BlurDraftAcceptanceTests).

    /// Which known issue a stress failure is, from its minimal steps, its kind and its profile; nil: none.
    static func matching(_ steps: [String], kind: String, on profile: HostProfile) -> String? {
        nil
    }
}
