import AllInOneIMECore
import AppKit
import UserNotifications

/// The script extensions running (`CommandRunner.run`), in the panel of a text field or in the background.
/// One run per command at a time: a newer one of the same command stops the one before (in the background,
/// one isn't started twice). A run in the background (`background: true`, or a `show` whose field was left:
/// `detach`) keeps going; the menu bar panel lists it, and when it's done a notification says how it went:
/// clicking it (or its row) opens what it printed. Main thread only.
@MainActor
final class ScriptTasks {
    static let shared = ScriptTasks()

    struct Run: Identifiable, Equatable {
        enum Outcome: Equatable {
            case running
            case done
            case failed(String)
        }

        let id: Int
        let command: ScriptCommand
        let started: Date
        var finished: Date?
        var outcome: Outcome = .running
        var output: ScriptOutput?
        /// Kept by the menu bar panel, with a notification when it's done.
        var detached: Bool
    }

    /// What reaches the panel of the text field a run belongs to.
    enum Event {
        case update(CommandRunner.ScriptUpdate)
        case failed(Error)
    }

    private(set) var runs: [Run] = []
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var handlers: [Int: (Event) -> Void] = [:]
    private var counter = 0
    /// Finished background runs kept for the panel.
    static let keptFinished = 8

    /// Asks macOS whether notifications may be shown, the first time a run goes to the background (the self-test
    /// asks nothing).
    var askToNotify: () -> Void = {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    /// Shows a notification (the self-test records them instead).
    var notify: (_ id: Int, _ title: String, _ body: String) -> Void = { id, title, body in
        let content = UNMutableNotificationContent()
        content.title = String(title.prefix(120))
        content.body = String(body.prefix(240))
        content.sound = .default
        content.userInfo = ["scriptRun": id]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "script-\(id)-\(Date().timeIntervalSince1970)",
                                                                     content: content, trigger: nil))
    }

    /// The runs the menu bar panel lists: those in the background, newest first.
    var background: [Run] { runs.filter(\.detached).reversed() }

    /// Starts `command` with `arguments` and `environment`; `handler` gets what it prints while it belongs to a
    /// text field. Nil when it isn't started: already running in the background, or too many are.
    func start(_ command: ScriptCommand, arguments: [String], environment: [String: String], detached: Bool,
               handler: ((Event) -> Void)?) -> Int? {
        if detached {
            guard BackgroundRuns.admits(command.id, running: runningInBackground) else { return nil }
            askToNotify()
        } else {
            // A newer query stops the older one.
            for run in runs where !run.detached && run.command.id == command.id && run.outcome == .running { cancel(run.id) }
        }
        counter += 1
        let id = counter
        runs.append(Run(id: id, command: command, started: Date(), detached: detached))
        if let handler { handlers[id] = handler }
        let stream = CommandRunner.run(command, arguments: arguments, environment: environment)
        tasks[id] = Task { @MainActor [weak self] in
            do {
                for try await update in stream {
                    guard let self, !Task.isCancelled else { return }
                    self.update(id) { $0.output = update.output }
                    self.handlers[id]?(.update(update))
                    if update.isFinal { self.finish(id, .done) }
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.handlers[id]?(.failed(error))
                self.finish(id, .failed(UIText.describe(error)))
            }
        }
        log.notice("extension \(detached ? "started in the background" : "started", privacy: .public) (run \(id))")
        changed()
        return id
    }

    /// Background commands whose environment is being made (`startInBackground`).
    private var preparing: [UUID: Task<Void, Never>] = [:]

    /// Starts a background command once its environment is ready (`prepare`, off the main thread). Held here, not
    /// by the text field it came from: it starts even if that field is gone by then. `say` tells why it didn't.
    func startInBackground(_ command: ScriptCommand, arguments: [String],
                           prepare: @escaping @Sendable () async -> Result<[String: String], DescribedError>,
                           say: @escaping (String) -> Void) {
        let token = UUID()
        preparing[token] = Task { @MainActor [weak self] in
            let prepared = await prepare()
            guard let self else { return }
            self.preparing[token] = nil
            switch prepared {
            case let .failure(error): say(error.message)
            case let .success(environment):
                if self.start(command, arguments: arguments, environment: environment, detached: true, handler: nil) == nil {
                    say(tr("\(command.title) 已经在后台运行了（或后台命令太多）",
                           "\(command.title) is already running in the background (or too many are)"))
                }
            }
        }
    }

    /// Stops a run (Esc, a newer query, removed from the panel).
    func cancel(_ id: Int) {
        tasks[id]?.cancel()
        tasks[id] = nil
        handlers[id] = nil
        if let index = runs.firstIndex(where: { $0.id == id }), runs[index].outcome == .running {
            if runs[index].detached { runs[index].outcome = .failed(tr("已停止", "Stopped")) } else { runs.remove(at: index) }
        }
        changed()
    }

    /// The ids of the commands running in the background.
    private var runningInBackground: [String] {
        runs.filter { $0.detached && $0.outcome == .running }.map(\.command.id)
    }

    /// The field a run belonged to was left: it goes on in the background, as one started there would
    /// (`BackgroundRuns`): with four running already, or the same command, it's stopped instead.
    func detach(_ id: Int) {
        guard let index = runs.firstIndex(where: { $0.id == id }), runs[index].outcome == .running else { return }
        guard BackgroundRuns.admits(runs[index].command.id, running: runningInBackground) else {
            log.notice("extension run \(id) stopped: no room in the background")
            cancel(id)
            return
        }
        handlers[id] = nil
        runs[index].detached = true
        askToNotify()
        log.notice("extension run \(id) goes on in the background")
        changed()
    }

    /// Removed from the panel (stopped first if it runs).
    func remove(_ id: Int) {
        cancel(id)
        runs.removeAll { $0.id == id }
        changed()
    }

    private func update(_ id: Int, _ change: (inout Run) -> Void) {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        change(&runs[index])
    }

    private func finish(_ id: Int, _ outcome: Run.Outcome) {
        tasks[id] = nil
        handlers[id] = nil
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        runs[index].outcome = outcome
        runs[index].finished = Date()
        let run = runs[index]
        guard run.detached else {
            runs.remove(at: index)  // a text field's: its panel has it
            return
        }
        let title = run.command.title
        switch outcome {
        case .done:
            notify(id, tr("完成了：", "Done: ", key: "task.done") + title,
                   run.output?.notificationBody ?? tr("点这里查看输出", "Click to see what it printed"))
        case let .failed(message):
            notify(id, tr("出错了：", "Failed: ") + title, message)
        case .running: break
        }
        log.notice("extension run \(id) finished in the background")
        // Only the newest finished ones are kept.
        let finished = runs.filter { $0.detached && $0.outcome != .running }
        if finished.count > Self.keptFinished, let oldest = finished.first { runs.removeAll { $0.id == oldest.id } }
        changed()
    }

    private func changed() {
        NotificationCenter.default.post(name: .allInOneIMEScriptRunsChanged, object: self)
    }

    /// Opens what a run printed (so far) in the default text editor: a file in the caches folder.
    func openResult(_ id: Int) {
        guard let run = runs.first(where: { $0.id == id }) else { return }
        var text = run.output?.copyText ?? ""
        if case let .failed(message) = run.outcome { text += (text.isEmpty ? "" : "\n\n") + message }
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "AllInOneIME").appendingPathComponent("ScriptResults")
        let name = run.command.name + "-" + String(id) + ".txt"
        let file = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file, options: .atomic)
            NSWorkspace.shared.open(file)
        } catch {
            log.error("could not write an extension's result: \(String(describing: error), privacy: .public)")
        }
    }
}

extension Notification.Name {
    /// A script extension's run started, finished, went to the background or was removed (`ScriptTasks`).
    /// Posted on the main thread.
    static let allInOneIMEScriptRunsChanged = Notification.Name("AllInOneIMEScriptRunsChanged")
}
