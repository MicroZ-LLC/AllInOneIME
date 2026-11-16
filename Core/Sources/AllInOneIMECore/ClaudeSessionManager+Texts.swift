import Foundation

extension ClaudeSessionManager {
    /// The answer's text from `replies`, each time it changes.
    static func texts(_ replies: AsyncThrowingStream<SessionReply, Error>) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var last: String?
                    for try await reply in replies where reply.text != last {
                        last = reply.text
                        continuation.yield(reply.text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// What Terminal runs for a hand-off: `arguments` (the CLI's) under `lockf`, which holds `lock` (the conversation's,
    /// `handOffOnceEnded`) while the CLI runs, waiting up to 10 seconds for it to be let go; as they are where there is no
    /// `/usr/bin/lockf`. A shell's `exec` keeps the window's process the CLI's (or lockf's, which waits for it).
    public static func terminalCommand(_ arguments: [String], lock: URL) -> [String] {
        let script = #"lock="$1"; shift; if [ -x /usr/bin/lockf ]; then exec /usr/bin/lockf -k -t 10 "$lock" "$@"; fi; exec "$@""#
        return ["/bin/sh", "-c", script, "sh", lock.path] + arguments
    }
}
