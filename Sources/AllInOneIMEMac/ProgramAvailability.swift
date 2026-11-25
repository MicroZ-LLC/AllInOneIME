import Foundation

/// Whether programs are on this Mac, for the main thread (the input method's `AgentAvailability`: `@agent`'s settings,
/// the `@question` hand-off), each looked up on the login shell's PATH (`ShellEnvironment.path`) and kept until
/// `forget`. The main thread never waits for the shell: until it has answered (`ShellReadiness`), a program is looked up
/// each time it's asked about (on the fallback PATH) and nothing is kept; once it has, `changed` is told on the main
/// thread, so what showed such an answer asks again.
@MainActor
public final class ProgramAvailability {
    private let readiness: ShellReadiness
    private var found: [String: Bool] = [:]
    /// Whether `changed` waits for the shell to answer.
    private var waiting = false
    /// What showed an answer given before the shell answered asks again.
    private let changed: @MainActor () -> Void

    public init(readiness: ShellReadiness = ShellEnvironment.readiness, changed: @escaping @MainActor () -> Void = {}) {
        self.readiness = readiness
        self.changed = changed
    }

    /// Looked up again from now on.
    public func forget() { found = [:] }

    /// `program` taken as installed or not, until `forget` (the self-test's).
    public func pretend(_ program: String, installed: Bool) { found[program] = installed }

    /// Whether `program` is installed: as found before, else as `lookUp` finds it now (on `ShellEnvironment.path`), kept
    /// once the shell has answered.
    public func installed(_ program: String, lookUp: () -> Bool) -> Bool {
        if let known = found[program] { return known }
        // Asked before the lookup: one made on the fallback PATH is never kept.
        let ready = readiness.isReady
        let installed = lookUp()
        if ready {
            found[program] = installed
        } else if !waiting {
            waiting = true
            readiness.whenReady { [weak self] in
                guard let self else { return }
                waiting = false
                changed()
            }
        }
        return installed
    }
}
