import Foundation

/// An icon of the command list and the panel's rows, like the colored squares of iOS Settings, as data: a symbol (or
/// an emoji, or an image file) drawn white on a color. Each shell draws it its own way (the Mac: an SF Symbol on a
/// rounded square, `CandidateView.Icon`).
///
/// `symbol` is a name in SF Symbols' vocabulary, which built-in commands use and custom commands, plugins and script
/// extensions name theirs in (`CustomCommand.icon`, `PluginManifest.icon`, `ScriptCommand.Icon.symbol`); a shell
/// without SF Symbols maps the names it knows to its own icon set and draws a generic one for the others.
public struct IconToken: Equatable, Sendable {
    /// The square's color: the system's named colors (each shell's own shade of them), a gray by its brightness, or an
    /// exact sRGB one ("#34C759").
    public enum Color: Equatable, Sendable {
        case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray
        /// A neutral gray, 0 black … 1 white.
        case grayscale(Double)
        case rgb(red: UInt8, green: UInt8, blue: UInt8)

        /// "blue", "systemBlue" or "#34C759" (what a custom command, a bundle's snippet or a plugin names); nil for
        /// anything else.
        public static func named(_ name: String?) -> Color? {
            guard let name = name?.trimmingCharacters(in: .whitespaces).lowercased(), !name.isEmpty else { return nil }
            if name.hasPrefix("#"), name.count == 7, let value = Int(name.dropFirst(), radix: 16) {
                return .rgb(red: UInt8((value >> 16) & 0xFF), green: UInt8((value >> 8) & 0xFF), blue: UInt8(value & 0xFF))
            }
            let named: [String: Color] = [
                "red": .red, "orange": .orange, "yellow": .yellow, "green": .green,
                "mint": .mint, "teal": .teal, "cyan": .cyan, "blue": .blue,
                "indigo": .indigo, "purple": .purple, "pink": .pink, "brown": .brown,
                "gray": .gray, "grey": .gray, "black": .grayscale(0.15),
            ]
            return named[name.hasPrefix("system") ? String(name.dropFirst(6)) : name]
        }
    }

    /// The symbol drawn on the square.
    public var symbol: String
    public var color: Color
    /// Drawn instead of the symbol on its square: a script extension's own emoji, or image file (a path; when it can't
    /// be read, the symbol).
    public var emoji: String?
    public var image: String?
    /// For a symbol a script extension named itself: the one drawn when the platform has no `symbol`.
    public var fallbackSymbol: String?

    public init(symbol: String, color: Color, emoji: String? = nil, image: String? = nil, fallbackSymbol: String? = nil) {
        self.symbol = symbol
        self.color = color
        self.emoji = emoji
        self.image = image
        self.fallbackSymbol = fallbackSymbol
    }
}

// MARK: - The commands' icons

extension IconToken {
    /// A command's icon: one for each built-in command, one for each kind of custom command, a plugin's own (or a
    /// puzzle piece), a script extension's own (an emoji, an image or a symbol).
    public static func command(_ command: Command) -> IconToken {
        if let plugin = command.plugin { return Self.plugin(plugin) }
        if let custom = command.custom { return Self.custom(custom) }
        if let script = command.script { return Self.script(script) }
        switch command {
        case .improve: return IconToken(symbol: "wand.and.stars", color: .purple)
        case .translate: return IconToken(symbol: "translate", color: .blue)
        case .question: return IconToken(symbol: "questionmark.bubble.fill", color: .blue)
        case .reply: return IconToken(symbol: "arrowshape.turn.up.left.fill", color: .green)
        case .agent: return IconToken(symbol: "sparkles", color: .orange)
        case .open: return IconToken(symbol: "magnifyingglass", color: .gray)
        case .read: return IconToken(symbol: "doc.richtext.fill", color: .teal)
        case .note: return IconToken(symbol: "note.text", color: .yellow)
        case .reminder: return IconToken(symbol: "bell.fill", color: .red)
        case .py: return IconToken(symbol: "chevron.left.forwardslash.chevron.right", color: .blue)
        case .js: return IconToken(symbol: "curlybraces", color: .yellow)
        case .webSearch: return IconToken(symbol: "globe", color: .cyan)
        case .tasks: return IconToken(symbol: "checklist", color: .green)
        case .settings: return IconToken(symbol: "gearshape.fill", color: .gray)
        case .imessage: return IconToken(symbol: "message.fill", color: .green)
        case .reportIssue: return IconToken(symbol: "exclamationmark.bubble.fill", color: .orange)
        default: return IconToken(symbol: "command", color: .gray)
        }
    }

    /// A plugin's own icon, or a puzzle piece (a chain link for a link plugin).
    public static func plugin(_ plugin: InstalledPlugin) -> IconToken {
        IconToken(symbol: plugin.manifest.icon ?? (plugin.manifest.type == .link ? "link" : "puzzlepiece.extension.fill"),
                  color: Color.named(plugin.manifest.color) ?? .pink)
    }

    /// A script extension's icon: its emoji, its image file, or its symbol; else one for what it does, in teal
    /// (Raycast's red for a Raycast script).
    public static func script(_ script: ScriptCommand) -> IconToken {
        let color: Color = script.source == .raycast ? .red : .teal
        let symbol = script.background ? "clock.arrow.circlepath" : script.status != nil ? "gauge.with.dots.needle.33percent" : {
            switch script.output {
            case .insert: return "text.cursor"
            case .show: return "text.alignleft"
            case .list: return "list.bullet"
            case .silent: return "bolt.fill"
            }
        }()
        switch script.icon {
        case let .emoji(emoji)?: return IconToken(symbol: symbol, color: color, emoji: emoji)
        case let .image(url)?: return IconToken(symbol: symbol, color: color, image: url.path)
        case let .symbol(name)?: return IconToken(symbol: name, color: color, fallbackSymbol: symbol)
        case nil: return IconToken(symbol: symbol, color: color)
        }
    }

    /// A custom command's own icon, or one for its type.
    public static func custom(_ custom: CustomCommand) -> IconToken {
        let (symbol, fallback): (String, Color)
        switch custom.type {
        case .prompt: (symbol, fallback) = ("text.bubble.fill", .indigo)
        case .run: (symbol, fallback) = ("chevron.left.forwardslash.chevron.right", .brown)
        case .terminal: (symbol, fallback) = ("apple.terminal.fill", .grayscale(0.25))
        case .link: (symbol, fallback) = ("link", .blue)
        case .snippet: (symbol, fallback) = ("text.insert", .mint)
        }
        return IconToken(symbol: custom.icon ?? symbol, color: Color.named(custom.color) ?? fallback)
    }

    /// A background task's state in `@tasks`.
    public static func progress(_ progress: AgentSession.Progress) -> IconToken {
        switch progress {
        case .done: return IconToken(symbol: "checkmark", color: .green)
        case .working: return IconToken(symbol: "hourglass", color: .orange)
        case .needsYou: return IconToken(symbol: "exclamationmark", color: .yellow)
        }
    }
}
