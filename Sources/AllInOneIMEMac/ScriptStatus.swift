import AllInOneIMECore
import Foundation

/// The status lines of the commands that have one (`ScriptCommand.status`), shown beside their names in the
/// command list: run in the background when the list shows them and they're due (`StatusSchedule`), a few at a
/// time and stopped after `ScriptCommand.Status.timeout`. A slow one never holds the list up; one that ends,
/// failed or not, lets the next due one start. Their last values are kept across launches (`StatusFile`): read off the
/// main thread at launch (`prepare`), shown once in, until they're refreshed. Main thread only.
@MainActor
public final class ScriptStatus {
    public static let shared = ScriptStatus()

    private var schedule = StatusSchedule()
    /// Whether the values kept are in (`prepare`): until then nothing is written over them.
    private var prepared = false
    /// How the values kept across launches are read (off the main thread).
    private let read: @Sendable () -> [String: StatusSchedule.Kept]
    /// Where the values are written, off the main thread, one write after another; the read at launch goes first.
    private static let writes = DispatchQueue(label: "com.aipinyin.inputmethod.script-statuses", qos: .utility)

    /// Made without reading anything: the values kept come in with `prepare`.
    init(read: @escaping @Sendable () -> [String: StatusSchedule.Kept] = { StatusFile.shared.read() }) {
        self.read = read
    }

    /// Reads the values kept across launches off the main thread (at launch: the first "@" list doesn't read the file),
    /// then shows them, where this launch has none newer; `done` once they're in.
    public func prepare(done: (@MainActor () -> Void)? = nil) {
        let read = self.read
        Self.writes.async {
            let kept = read()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.schedule.adopt(kept)
                    self.prepared = true
                    done?()
                }
            }
        }
    }

    /// The last status line of `command`, if it has one.
    public func text(for command: ScriptCommand) -> String? { schedule.text(for: command.id) }

    /// The last status line of the command with `id`.
    func text(forID id: String) -> String? { schedule.text(for: id) }

    /// Runs the status of those of `commands` that are due (`environment` gives each its environment, nil: not
    /// now); `ended` is called when one ends, to draw it and start the next due one.
    public func refresh(_ commands: [ScriptCommand], environment: @escaping (ScriptCommand) async -> [String: String]?,
                        ended: @escaping () -> Void) {
        for command in schedule.due(commands) {
            Task { @MainActor [weak self] in
                var line: String?
                if let env = await environment(command) {
                    do {
                        for try await update in CommandRunner.run(command, arguments: [], environment: env, status: true) where update.isFinal {
                            line = update.output.lines.first.map { String($0.prefix(40)) }
                        }
                    } catch {
                        line = nil  // the value before stays until its next refresh time
                    }
                }
                if self?.schedule.finished(command.id, line: line) == true, self?.prepared == true, let kept = self?.schedule.kept {
                    Self.writes.async { StatusFile.shared.write(kept) }
                }
                ended()
            }
        }
    }
}
