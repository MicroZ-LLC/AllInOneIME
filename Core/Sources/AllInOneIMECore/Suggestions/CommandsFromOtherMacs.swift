import Foundation

// Custom `suggestions` commands from another Mac (spec Suggestions v1, decision 26): one that came through iCloud
// (`ICloudSync`) runs nothing on this Mac until the user confirms it here once. Sync marks it with the program it came
// with as it comes (`Config.unconfirmedCommands`); Settings → Custom Commands says where it is from and what it would run,
// with Allow (which confirms that program) and Remove; an edit made on this Mac confirms what it saves, and a program
// changed on another Mac is marked again as it comes. Only sync marks: a command made on this Mac, in Settings or in
// config.json, never asks. The marks are this Mac's own, never synced. `run` commands are as they were: they only run
// when the user runs them.

extension CustomCommand {
    /// A `suggestions` command that came from another Mac and isn't confirmed on this one: its name and the program
    /// (`argv`) it came with. The command with another program (edited here since) isn't it.
    public struct Unconfirmed: Codable, Hashable, Sendable {
        public var name: String
        public var argv: [String]

        public init(name: String, argv: [String]) {
            self.name = name
            self.argv = argv
        }

        /// Whether it is `command` as it came: a `suggestions` command of its name (in any case) and its program.
        func marks(_ command: CustomCommand) -> Bool {
            command.type == .suggestions && command.name.lowercased() == name.lowercased() && command.argv == argv
        }
    }
}

extension Config {
    /// Whether `command` came from another Mac with the program it has and isn't confirmed here: nothing of it runs on
    /// this Mac until it is (it's no suggestion source, `suggestionsSettings`).
    public func awaitsConfirmation(_ command: CustomCommand) -> Bool {
        unconfirmedCommands.contains { $0.marks(command) }
    }

    /// The marks once sync has put this config's `customCommands` in place of `before`'s (`ICloudSync.applying`): each
    /// `suggestions` command with a program is marked with it, unless this Mac runs that program already (the program of
    /// one of `before`'s `suggestions` commands not awaiting confirmation: a confirmation is of the program, whatever the
    /// command's name). So one sync left as it was keeps its mark, or its confirmation, and one whose program another Mac
    /// changed asks again.
    func unconfirmed(after before: Config) -> [CustomCommand.Unconfirmed] {
        let confirmed = Set(before.customCommands.filter { $0.type == .suggestions && !before.awaitsConfirmation($0) }.compactMap(\.argv))
        return customCommands.compactMap { command in
            guard command.type == .suggestions, let argv = command.argv, !(argv.first ?? "").isEmpty, !confirmed.contains(argv) else {
                return nil
            }
            return CustomCommand.Unconfirmed(name: command.name, argv: argv)
        }
    }

    /// `command` confirmed on this Mac, as Settings → Custom Commands' Allow does: with the program it showed (a program
    /// sync put in since stays marked). Whether a mark went.
    @discardableResult
    public mutating func confirm(_ command: CustomCommand) -> Bool {
        let count = unconfirmedCommands.count
        unconfirmedCommands.removeAll { $0.marks(command) }
        return unconfirmedCommands.count != count
    }

    /// The marks of the commands named `names` (in any case) gone: those commands were edited or deleted on this Mac.
    mutating func forgetUnconfirmed(named names: [String]) {
        let names = Set(names.map { $0.lowercased() })
        unconfirmedCommands.removeAll { names.contains($0.name.lowercased()) }
    }
}

extension UIText {
    /// Where a command awaiting confirmation is from and what it would run, as Settings → Custom Commands says it:
    /// "From another Mac: runs ~/bin/jira-list --all".
    public static func fromAnotherMac(_ command: CustomCommand, in t: InterfaceWords = InterfaceWords(language: UIText.language)) -> String {
        let program = CustomCommand.commandLine(command.argv ?? [])
        return t.tr("来自另一台 Mac：运行 \(program)", "From another Mac: runs \(program)")
    }

    /// What awaiting confirmation means, after `fromAnotherMac`.
    public static func runsNothingUntilAllowed(in t: InterfaceWords = InterfaceWords(language: UIText.language)) -> String {
        t.tr("在这台 Mac 上允许之前，它什么都不运行。", "It runs nothing on this Mac until you allow it.")
    }
}
