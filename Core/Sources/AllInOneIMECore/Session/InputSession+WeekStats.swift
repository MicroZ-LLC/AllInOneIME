import Foundation

/// The runs of a field's session counted for this week's stats (`WeekStats`, `SessionServices.weekStats`): each command
/// the composer counts for the command list (`Composer.Effect.commandUsed`), with where it comes from, the app it ran in
/// and whether it sent a request to an AI provider. One that starts a request is counted when the request first answers
/// (a cached answer sent nothing: no AI then), and not when it fails or is given up before; one that is done at once
/// (a snippet, a link, an app opened) at once. `@stats` itself isn't counted: looking at the week doesn't change it.
/// Nothing is counted in a field nothing may leave (`nothingLeavesDevice`: secure input, a known password field), and a
/// run whose request answers after everything was forgotten (Forget All) isn't counted then (`WeekStats.era`).
/// The characters the user types through the input method are counted as they go in (`InputSession.countTyped`).
struct WeekStatsRuns {
    struct Run {
        var id: String
        var source: WeekStats.CommandSource
        var app: String?
        var ai: Bool
        /// The stats' `era` when it ran.
        var era: Int
    }

    /// By the request each waits for.
    var pending: [Int: [Run]] = [:]
    /// The most requests waiting at once: older ones (refused, given up) go.
    static let limit = 16
}

extension Composer.Effect {
    /// The request this effect starts, which answers through the session's tasks (nil: none).
    var startedRequest: Int? {
        switch self {
        case let .startConversion(_, id), let .startCommand(_, _, id), let .search(_, id), let .startRun(_, _, id),
             let .startScript(_, _, _, id, _), let .startPlan(_, _, id), let .reask(_, _, id), let .listAgents(id):
            return id
        default:
            return nil
        }
    }
}

extension InputSession {
    /// `name` ran (`commandUsed`) in the batch `effects`: counted once its request answers, or now.
    func countRun(_ name: String, in effects: [Composer.Effect]) {
        guard name != Command.stats.name, !nothingLeavesDevice() else { return }
        let command = composer.commands.first { $0.name == name } ?? ([Command.edit] + Command.builtins).first { $0.name == name }
        let run = WeekStatsRuns.Run(id: name, source: command.map(WeekStats.CommandSource.init) ?? .own, app: app,
                                    ai: command.map { $0.kind == .convert || $0.kind == .generate } ?? false,
                                    era: services.weekStats.era)
        guard let request = effects.lazy.compactMap(\.startedRequest).first else {
            record(run, fromCache: false)
            return
        }
        weekStatsRuns.pending[request, default: []].append(run)
        if weekStatsRuns.pending.count > WeekStatsRuns.limit, let oldest = weekStatsRuns.pending.keys.min() {
            weekStatsRuns.pending[oldest] = nil
        }
    }

    /// `request` answered (its first output, a list, a script's line; a script left running in the background): its runs
    /// counted, unless the field is one nothing may leave by now.
    func runAnswered(_ request: Int, fromCache: Bool) {
        guard let runs = weekStatsRuns.pending.removeValue(forKey: request), !nothingLeavesDevice() else { return }
        for run in runs { record(run, fromCache: fromCache) }
    }

    /// `request` failed: its runs aren't counted.
    func runFailed(_ request: Int) {
        weekStatsRuns.pending[request] = nil
    }

    private func record(_ run: WeekStatsRuns.Run, fromCache: Bool) {
        services.weekStats.recordCommand(id: run.id, source: run.source, bundleID: run.app, usedAI: run.ai && !fromCache,
                                         era: run.era)
    }

    /// Something from clipboard history was pasted: counted (never what), but not in a field nothing may leave.
    func countClipboardPaste() {
        guard !nothingLeavesDevice() else { return }
        services.weekStats.recordClipboardPaste()
    }

    /// `@stats`'s ⌘C done by the shell (`PlatformAction.copyWeekStatsImage`): `copied`, whether the picture is on the
    /// clipboard now. Its notice says so then, and only then; else that it couldn't be copied.
    public func weekStatsImageCopied(_ copied: Bool) -> [SessionOutput] {
        let words = WeekStatsWords(language: composer.messages.language)
        return showNotice(copied ? words.imageCopied : words.imageNotCopied)
    }

    // MARK: Characters typed

    /// `text` the user typed went into the field through the input method: told by the composer
    /// (`Composer.typedIntoField`: a candidate picked, a draft put in as typed …), or a key it let through to the app as
    /// typed (`key`, with a language's engine in level one). Its characters, but for spaces and line breaks, are added to
    /// this week's stats as a number, in memory (the shell writes it later); never during secure input or in a field
    /// known as a password field (`nothingLeavesDevice`). What a command, an answer, a snippet, autocomplete, a suggestion
    /// row or clipboard history puts in is never told here.
    func countTyped(_ text: String) {
        guard !nothingLeavesDevice() else { return }
        services.weekStats.recordTypedCharacters(Self.typedCharacters(in: text))
    }

    /// The characters of `text` this week's stats count: each one (a Chinese character, a letter, a digit, a mark, an
    /// emoji) but spaces and line breaks.
    static func typedCharacters(in text: String) -> Int {
        text.reduce(0) { $1.isWhitespace || $1.isNewline ? $0 : $0 + 1 }
    }
}
