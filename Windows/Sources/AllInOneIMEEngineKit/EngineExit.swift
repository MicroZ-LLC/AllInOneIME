/// The engine's exit codes that what starts it acts on (the end-to-end driver, which ends another engine of the user's
/// only when that is why its own exited).
public enum EngineExit {
    /// Another engine runs for this user in this session, or on the pipe given (`--pipe`): it holds the single-instance
    /// mutex.
    public static let anotherEngineRuns: Int32 = 4
}
