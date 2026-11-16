import Foundation

/// What the command trigger (`Config.commandTrigger`) can be.
extension Config {
    /// Why `value` can't be the command trigger; nil when it can. It opens the command list where a sentence starts, after
    /// a space and after Chinese, and goes in as itself when no command follows: one ASCII symbol, and not one typing
    /// needs there (`typingSymbols`).
    public static func commandTriggerProblem(_ value: String) -> CommandTriggerProblem? {
        guard value.unicodeScalars.count == 1, let scalar = value.unicodeScalars.first, (33...126).contains(scalar.value),
              !CharacterSet.alphanumerics.contains(scalar) else { return .notASymbol }
        return typingSymbols.contains(Character(value)) ? .typingSymbol(value) : nil
    }

    /// The ASCII symbols typing needs, which the command trigger would take from it: pinyin's (rime-ice's): ' between
    /// syllables, ` its lookup key (`speller/alphabet`, `key_binder/search`), - and = turning the candidates' pages,
    /// [ and ] picking a word's first or last character (`key_binder`), , . : held after a digit
    /// (`punctuator/digit_separators`); and every symbol its punctuation types as Chinese (`punctuator/half_shape`:
    /// ，。；：？！“”‘’、（）《》【】「」…… —— · ¥), and /. What is left types as itself in every mode (`commandTriggers`).
    /// The macOS shell's Rime tests (CommandTriggerSymbolsTests) check them against rime-ice as it is deployed.
    public static let typingSymbols: Set<Character> = [
        "'", "`", "-", "=", "[", "]", ",", ".", ":", ";", "/", "\\", "?", "!", "\"", "(", ")", "<", ">", "{", "}", "^", "_", "$",
    ]

    /// Every symbol the command trigger can be, in ASCII order: # % & * + @ | ~.
    public static var commandTriggers: [String] {
        (33...126).compactMap(UnicodeScalar.init).map(String.init).filter(validCommandTrigger)
    }

    /// Why a command trigger is refused (`commandTriggerProblem`), as Settings says it.
    public enum CommandTriggerProblem: Error, Equatable, LocalizedError {
        /// Not one ASCII symbol: a letter, a digit, a space, nothing, several characters, or another script's.
        case notASymbol
        /// A symbol typing needs (`typingSymbols`).
        case typingSymbol(String)

        public var errorDescription: String? { message(language: UIText.language) }

        /// What Settings says, in `language`, with the symbols that work.
        public func message(language: String) -> String {
            let t = InterfaceWords(language: language), these = Config.commandTriggers.joined(separator: " ")
            switch self {
            case .notASymbol:
                return t.tr("魔法键只能是一个符号，不能是字母、数字或空格。可以用：\(these)",
                            "The magic key must be one symbol, not a letter, digit or space. These work: \(these)")
            case let .typingSymbol(symbol):
                return t.tr("\(symbol) 打字时要用（拼音或中文标点），不能用来打开命令。可以用：\(these)",
                            "\(symbol) is needed for typing (pinyin or Chinese punctuation), so it can't open commands. These work: \(these)")
            }
        }
    }
}
