import AllInOneIMECore
import Foundation
import Observation

/// A custom command's Test run in its editor (the app's `CommandEditor`): the sample it runs on, one run at a time
/// (`CommandTrial.run`), and what it gave. What it gave is the sample's and the command's it ran: a new sample stops the
/// run and what it gave is gone, as `stop` does when what it runs changes; a run stopped (or one started after it) never
/// shows what it gives after. Main thread only.
@MainActor @Observable
public final class CommandEditorTrial {
    /// A run under way, or what it gave: what it would put in, or why it gave nothing.
    public enum Outcome: Equatable, Sendable {
        case running
        case passed(String)
        case failed(String)
    }

    /// The text after the command, or the selection, as typed beside Test run: another stops the run.
    public var sample: String {
        get { typed }
        set {
            guard newValue != typed else { return }
            typed = newValue
            stop()
        }
    }

    public private(set) var outcome: Outcome?
    private var typed: String
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The runs started, counted: what one gives is shown only while it is the last.
    @ObservationIgnored private var runs = 0

    /// `outcome`: a run shown as done (the settings' images).
    public init(sample: String = "", outcome: Outcome? = nil) {
        typed = sample
        self.outcome = outcome
    }

    /// `command` run on the sample, the run before stopped; `ask` answers an AI instruction (once the user agreed).
    public func start(_ command: CustomCommand, ask: @escaping CommandTrial.Asker) {
        stop()
        runs += 1
        let (run, sample) = (runs, typed)
        outcome = .running
        task = Task {
            let outcome: Outcome
            do {
                outcome = .passed(try await CommandTrial.run(command, sample: sample, ask: ask))
            } catch {
                outcome = .failed(UIText.describe(error))
            }
            // Stopped (the sample or what it runs changed, another run, the editor closed): not the form's now.
            guard !Task.isCancelled, run == runs else { return }
            self.outcome = outcome
        }
    }

    /// The run stopped (a program as Esc stops it), what it gave gone.
    public func stop() {
        task?.cancel()
        task = nil
        outcome = nil
    }
}
