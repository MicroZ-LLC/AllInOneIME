import AllInOneIMECore
import AppKit

/// The icons of the command list, like the colored squares of iOS Settings: one for each built-in
/// command, one for each kind of custom command, a plugin's own (or a puzzle piece), a script extension's
/// own (an emoji, an image or a symbol). A custom command or a plugin may name its own SF Symbol and color.
enum CommandIcons {
    static func icon(for command: Command) -> CandidateView.Icon {
        if let plugin = command.plugin { return icon(for: plugin) }
        if let custom = command.custom { return icon(for: custom) }
        if let script = command.script { return icon(for: script) }
        switch command {
        case .improve: return CandidateView.Icon(symbol: "wand.and.stars", color: .systemPurple)
        case .translate: return CandidateView.Icon(symbol: "translate", color: .systemBlue)
        case .question: return CandidateView.Icon(symbol: "questionmark.bubble.fill", color: .systemBlue)
        case .claude: return CandidateView.Icon(symbol: "sparkles", color: .systemOrange)
        case .open: return CandidateView.Icon(symbol: "magnifyingglass", color: .systemGray)
        case .read: return CandidateView.Icon(symbol: "doc.richtext.fill", color: .systemTeal)
        case .note: return CandidateView.Icon(symbol: "note.text", color: .systemYellow)
        case .reminder: return CandidateView.Icon(symbol: "bell.fill", color: .systemRed)
        case .calc: return CandidateView.Icon(symbol: "plus.forwardslash.minus", color: .systemOrange)
        case .py: return CandidateView.Icon(symbol: "chevron.left.forwardslash.chevron.right", color: .systemBlue)
        case .js: return CandidateView.Icon(symbol: "curlybraces", color: .systemYellow)
        case .webSearch: return CandidateView.Icon(symbol: "globe", color: .systemCyan)
        case .tasks: return CandidateView.Icon(symbol: "checklist", color: .systemGreen)
        case .settings: return CandidateView.Icon(symbol: "gearshape.fill", color: .systemGray)
        case .config: return CandidateView.Icon(symbol: "slider.horizontal.3", color: .systemIndigo)
        case .imessage: return CandidateView.Icon(symbol: "message.fill", color: .systemGreen)
        case .reportIssue: return CandidateView.Icon(symbol: "exclamationmark.bubble.fill", color: .systemOrange)
        default: return CandidateView.Icon(symbol: "command", color: .systemGray)
        }
    }

    /// A plugin's own icon, or a puzzle piece (a chain link for a link plugin).
    static func icon(for plugin: InstalledPlugin) -> CandidateView.Icon {
        CandidateView.Icon(symbol: plugin.manifest.icon ?? (plugin.manifest.type == .link ? "link" : "puzzlepiece.extension.fill"),
                           color: color(plugin.manifest.color) ?? .systemPink)
    }

    /// A script extension's icon: its emoji, its image file, or its SF Symbol; else one for what it does, in
    /// teal (Raycast's red for a Raycast script).
    static func icon(for script: ScriptCommand) -> CandidateView.Icon {
        let color: NSColor = script.source == .raycast ? .systemRed : .systemTeal
        let symbol = script.background ? "clock.arrow.circlepath" : script.status != nil ? "gauge.with.dots.needle.33percent" : {
            switch script.output {
            case .insert: return "text.cursor"
            case .show: return "text.alignleft"
            case .list: return "list.bullet"
            case .silent: return "bolt.fill"
            }
        }()
        switch script.icon {
        case let .emoji(emoji)?: return CandidateView.Icon(symbol: symbol, color: color, emoji: emoji)
        case let .image(url)? where image(url.path) != nil:
            return CandidateView.Icon(symbol: symbol, color: color, image: url.path)
        case let .symbol(name)? where NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil:
            return CandidateView.Icon(symbol: name, color: color)
        default: return CandidateView.Icon(symbol: symbol, color: color)
        }
    }

    static let scripts = CandidateView.Icon(symbol: "terminal.fill", color: .systemTeal)

    /// An extension's image file, read again only when its modification date changes (the list is drawn on each
    /// key: a stat then, not a read).
    private static var images: [String: (date: Date?, image: NSImage?)] = [:]

    static func image(_ path: String) -> NSImage? {
        let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        if let known = images[path], known.date == date { return known.image }
        let image = date == nil ? nil : NSImage(contentsOfFile: path)
        images[path] = (date, image)
        return image
    }

    /// A custom command's own icon, or one for its type.
    static func icon(for custom: CustomCommand) -> CandidateView.Icon {
        let (symbol, fallback): (String, NSColor)
        switch custom.type {
        case .prompt: (symbol, fallback) = ("text.bubble.fill", .systemIndigo)
        case .run: (symbol, fallback) = ("chevron.left.forwardslash.chevron.right", .systemBrown)
        case .terminal: (symbol, fallback) = ("apple.terminal.fill", NSColor(white: 0.25, alpha: 1))
        case .link: (symbol, fallback) = ("link", .systemBlue)
        }
        return CandidateView.Icon(symbol: custom.icon ?? symbol, color: color(custom.color) ?? fallback)
    }

    /// The settings window's sections, like System Settings: a colored square with a symbol.
    static let input = CandidateView.Icon(symbol: "keyboard.fill", color: .systemGray)
    static let translate = CandidateView.Icon(symbol: "translate", color: .systemBlue)
    static let improve = CandidateView.Icon(symbol: "wand.and.stars", color: .systemPurple)
    static let jargon = CandidateView.Icon(symbol: "text.book.closed.fill", color: .systemOrange)
    static let commands = CandidateView.Icon(symbol: "at", color: .systemIndigo)
    static let plugins = CandidateView.Icon(symbol: "puzzlepiece.extension.fill", color: .systemPink)
    static let voice = CandidateView.Icon(symbol: "mic.fill", color: .systemRed)
    static let provider = CandidateView.Icon(symbol: "cpu.fill", color: .systemTeal)
    static let advanced = CandidateView.Icon(symbol: "gearshape.2.fill", color: .systemGray)
    static let panel = CandidateView.Icon(symbol: "rectangle.on.rectangle", color: .systemTeal)
    static let webSearch = CandidateView.Icon(symbol: "globe", color: .systemCyan)

    /// A background task's state in `@tasks`.
    static func icon(for progress: AgentSession.Progress) -> CandidateView.Icon {
        switch progress {
        case .done: return CandidateView.Icon(symbol: "checkmark", color: .systemGreen)
        case .working: return CandidateView.Icon(symbol: "hourglass", color: .systemOrange)
        case .needsYou: return CandidateView.Icon(symbol: "exclamationmark", color: .systemYellow)
        }
    }

    /// "blue", "systemBlue" or "#34C759"; nil for anything else.
    static func color(_ name: String?) -> NSColor? {
        guard let name = name?.trimmingCharacters(in: .whitespaces).lowercased(), !name.isEmpty else { return nil }
        if name.hasPrefix("#"), name.count == 7, let value = Int(name.dropFirst(), radix: 16) {
            return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                           blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
        let named: [String: NSColor] = [
            "red": .systemRed, "orange": .systemOrange, "yellow": .systemYellow, "green": .systemGreen,
            "mint": .systemMint, "teal": .systemTeal, "cyan": .systemCyan, "blue": .systemBlue,
            "indigo": .systemIndigo, "purple": .systemPurple, "pink": .systemPink, "brown": .systemBrown,
            "gray": .systemGray, "grey": .systemGray, "black": NSColor(white: 0.15, alpha: 1),
        ]
        return named[name.hasPrefix("system") ? String(name.dropFirst(6)) : name]
    }
}
