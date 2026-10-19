import Foundation

/// An icon of the command list and the panel's rows, like the colored squares of iOS Settings, as data: a glyph drawn
/// white on a color. Each shell draws it its own way (the Mac: an SF Symbol on a rounded square, `CandidateView.Icon`).
///
/// The glyph is one of four (`Glyph`): one of the core's own icons, named for what it stands for (`Builtin`, a list a
/// shell maps to its icon set); a symbol a custom command, a plugin or a script extension named, in SF Symbols'
/// vocabulary (`CustomCommand.icon`, `PluginManifest.icon`, `ScriptCommand.Icon.symbol`); a script extension's emoji or
/// image file. The last three carry the built-in icon for what they are (`fallback`), drawn where the platform has no
/// such symbol or can't read the image.
public struct IconToken: Equatable, Sendable {
    /// The core's own icons, by what they stand for. A shell maps each to its icon set; on Apple platforms they are SF
    /// Symbols (`appleSymbol`). The names (`rawValue`) are the list a shell's mapping goes by:
    ///
    /// - the built-in commands: `improve`, `translate`, `question`, `reply`, `agent`, `open`, `read`, `note`,
    ///   `reminder`, `python`, `javascript`, `webSearch`, `tasks`, `settings`, `message` (`@imessage`), `reportIssue`,
    ///   and `command` for one without an icon of its own;
    /// - plugins and custom commands, by what they are: `plugin`, `link`, `prompt`, `run`, `terminal`, `snippet`;
    /// - script extensions, by what they do: `scriptInsert`, `scriptShow`, `scriptList`, `scriptSilent`,
    ///   `scriptBackground`, `scriptStatus` (one with a status line);
    /// - a background task's state (`@tasks`): `done`, `working`, `needsYou`.
    public enum Builtin: String, CaseIterable, Sendable {
        case improve, translate, question, reply, agent, open, read, note, reminder, python, javascript, webSearch, tasks
        case settings, message, reportIssue, command
        case plugin, link, prompt, run, terminal, snippet
        case scriptInsert, scriptShow, scriptList, scriptSilent, scriptBackground, scriptStatus
        case done, working, needsYou

        /// Its SF Symbol, on Apple platforms.
        public var appleSymbol: String {
            switch self {
            case .improve: return "wand.and.stars"
            case .translate: return "translate"
            case .question: return "questionmark.bubble.fill"
            case .reply: return "arrowshape.turn.up.left.fill"
            case .agent: return "sparkles"
            case .open: return "magnifyingglass"
            case .read: return "doc.richtext.fill"
            case .note: return "note.text"
            case .reminder: return "bell.fill"
            case .python, .run: return "chevron.left.forwardslash.chevron.right"
            case .javascript: return "curlybraces"
            case .webSearch: return "globe"
            case .tasks: return "checklist"
            case .settings: return "gearshape.fill"
            case .message: return "message.fill"
            case .reportIssue: return "exclamationmark.bubble.fill"
            case .command: return "command"
            case .plugin: return "puzzlepiece.extension.fill"
            case .link: return "link"
            case .prompt: return "text.bubble.fill"
            case .terminal: return "apple.terminal.fill"
            case .snippet: return "text.insert"
            case .scriptInsert: return "text.cursor"
            case .scriptShow: return "text.alignleft"
            case .scriptList: return "list.bullet"
            case .scriptSilent: return "bolt.fill"
            case .scriptBackground: return "clock.arrow.circlepath"
            case .scriptStatus: return "gauge.with.dots.needle.33percent"
            case .done: return "checkmark"
            case .working: return "hourglass"
            case .needsYou: return "exclamationmark"
            }
        }
    }

    /// What is drawn on the square: exactly one of these.
    public enum Glyph: Equatable, Sendable {
        case builtin(Builtin)
        /// A symbol named in SF Symbols' vocabulary (a custom command's, a plugin's, a script extension's own): drawn
        /// where the platform has it, else `fallback`.
        case symbol(String, fallback: Builtin)
        /// A script extension's emoji, drawn as text instead of the square (`fallback` where the platform can't).
        case emoji(String, fallback: Builtin)
        /// A script extension's image file (a path), drawn instead of the square; where it can't be read, `fallback`.
        case image(path: String, fallback: Builtin)
    }

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

    public var glyph: Glyph
    public var color: Color

    public init(_ glyph: Glyph, color: Color) {
        self.glyph = glyph
        self.color = color
    }

    public init(_ builtin: Builtin, color: Color) { self.init(.builtin(builtin), color: color) }

    /// What is drawn where the glyph can't be (a symbol the platform hasn't, an image it can't read): a built-in's own,
    /// else the one for what it is.
    public var fallback: Builtin {
        switch glyph {
        case let .builtin(builtin): return builtin
        case let .symbol(_, fallback), let .emoji(_, fallback), let .image(_, fallback): return fallback
        }
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
        case .improve: return IconToken(.improve, color: .purple)
        case .translate: return IconToken(.translate, color: .blue)
        case .question: return IconToken(.question, color: .blue)
        case .reply: return IconToken(.reply, color: .green)
        case .agent: return IconToken(.agent, color: .orange)
        case .open: return IconToken(.open, color: .gray)
        case .read: return IconToken(.read, color: .teal)
        case .note: return IconToken(.note, color: .yellow)
        case .reminder: return IconToken(.reminder, color: .red)
        case .py: return IconToken(.python, color: .blue)
        case .js: return IconToken(.javascript, color: .yellow)
        case .webSearch: return IconToken(.webSearch, color: .cyan)
        case .tasks: return IconToken(.tasks, color: .green)
        case .settings: return IconToken(.settings, color: .gray)
        case .imessage: return IconToken(.message, color: .green)
        case .reportIssue: return IconToken(.reportIssue, color: .orange)
        default: return IconToken(.command, color: .gray)
        }
    }

    /// A plugin's own icon, or a puzzle piece (a chain link for a link plugin), which its own falls back to.
    public static func plugin(_ plugin: InstalledPlugin) -> IconToken {
        let kind: Builtin = plugin.manifest.type == .link ? .link : .plugin
        return IconToken(plugin.manifest.icon.map { .symbol($0, fallback: kind) } ?? .builtin(kind),
                         color: Color.named(plugin.manifest.color) ?? .pink)
    }

    /// A script extension's icon: its emoji, its image file, or its symbol; else, and where those can't be drawn, one
    /// for what it does, in teal (Raycast's red for a Raycast script).
    public static func script(_ script: ScriptCommand) -> IconToken {
        let color: Color = script.source == .raycast ? .red : .teal
        let kind: Builtin = script.background ? .scriptBackground : script.status != nil ? .scriptStatus : {
            switch script.output {
            case .insert: return .scriptInsert
            case .show: return .scriptShow
            case .list: return .scriptList
            case .silent: return .scriptSilent
            }
        }()
        switch script.icon {
        case let .emoji(emoji)?: return IconToken(.emoji(emoji, fallback: kind), color: color)
        case let .image(url)?: return IconToken(.image(path: url.path, fallback: kind), color: color)
        case let .symbol(name)?: return IconToken(.symbol(name, fallback: kind), color: color)
        case nil: return IconToken(kind, color: color)
        }
    }

    /// A custom command's own icon, or one for its type, which its own falls back to.
    public static func custom(_ custom: CustomCommand) -> IconToken {
        let (kind, fallback): (Builtin, Color)
        switch custom.type {
        case .prompt: (kind, fallback) = (.prompt, .indigo)
        case .run: (kind, fallback) = (.run, .brown)
        case .terminal: (kind, fallback) = (.terminal, .grayscale(0.25))
        case .link: (kind, fallback) = (.link, .blue)
        case .snippet: (kind, fallback) = (.snippet, .mint)
        }
        return IconToken(custom.icon.map { .symbol($0, fallback: kind) } ?? .builtin(kind), color: Color.named(custom.color) ?? fallback)
    }

    /// A background task's state in `@tasks`.
    public static func progress(_ progress: AgentSession.Progress) -> IconToken {
        switch progress {
        case .done: return IconToken(.done, color: .green)
        case .working: return IconToken(.working, color: .orange)
        case .needsYou: return IconToken(.needsYou, color: .yellow)
        }
    }
}
