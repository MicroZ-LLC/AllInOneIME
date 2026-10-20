import AllInOneIMECore
import AppKit

/// The icons of the command list, like the colored squares of iOS Settings, as the Mac draws them: the core's tokens
/// (`IconToken`: one for each built-in command, one for each kind of custom command, a plugin's own or a puzzle piece,
/// a script extension's own emoji, image or symbol, each with the built-in one it falls back to), and the settings
/// window's sections.
enum CommandIcons {
    static func icon(for command: Command) -> CandidateView.Icon { CandidateView.Icon(IconToken.command(command)) }

    /// A plugin's own icon, or a puzzle piece (a chain link for a link plugin).
    static func icon(for plugin: InstalledPlugin) -> CandidateView.Icon { CandidateView.Icon(IconToken.plugin(plugin)) }

    /// A script extension's icon: its emoji, its image file, or its SF Symbol; else one for what it does, in
    /// teal (Raycast's red for a Raycast script).
    static func icon(for script: ScriptCommand) -> CandidateView.Icon { CandidateView.Icon(IconToken.script(script)) }

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
    static func icon(for custom: CustomCommand) -> CandidateView.Icon { CandidateView.Icon(IconToken.custom(custom)) }

    /// The settings window's sections, like System Settings: a colored square with a symbol.
    static let input = CandidateView.Icon(symbol: "keyboard.fill", color: .systemGray)
    static let translate = CandidateView.Icon(symbol: "translate", color: .systemBlue)
    static let improve = CandidateView.Icon(symbol: "wand.and.stars", color: .systemPurple)
    static let jargon = CandidateView.Icon(symbol: "text.book.closed.fill", color: .systemOrange)
    static let commands = CandidateView.Icon(symbol: "at", color: .systemIndigo)
    static let plugins = CandidateView.Icon(symbol: "puzzlepiece.extension.fill", color: .systemPink)
    static let voice = CandidateView.Icon(symbol: "mic.fill", color: .systemRed)
    static let provider = CandidateView.Icon(symbol: "cpu.fill", color: .systemTeal)
    /// Settings → Agent: `@agent`'s own.
    static var agent: CandidateView.Icon { icon(for: .agent) }
    static let advanced = CandidateView.Icon(symbol: "gearshape.2.fill", color: .systemGray)
    static let panel = CandidateView.Icon(symbol: "rectangle.on.rectangle", color: .systemTeal)
    static let webSearch = CandidateView.Icon(symbol: "globe", color: .systemCyan)

    /// A background task's state in `@tasks`.
    static func icon(for progress: AgentSession.Progress) -> CandidateView.Icon { CandidateView.Icon(IconToken.progress(progress)) }

    /// "blue", "systemBlue" or "#34C759"; nil for anything else (`IconToken.Color.named`).
    static func color(_ name: String?) -> NSColor? { IconToken.Color.named(name).map(NSColor.icon) }
}

extension CandidateView.Icon {
    /// `token` as the Mac draws it: a built-in icon as its SF Symbol; a symbol the Mac doesn't have (one a custom command,
    /// a plugin or a script extension named) as the token's fallback; an emoji instead of the square; an image file, or
    /// the fallback when it can't be read.
    init(_ token: IconToken) {
        let color = NSColor.icon(token.color), fallback = token.fallback.appleSymbol
        switch token.glyph {
        case let .builtin(builtin):
            self.init(symbol: builtin.appleSymbol, color: color)
        case let .symbol(name, _):
            self.init(symbol: NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil ? fallback : name, color: color)
        case let .emoji(emoji, _):
            self.init(symbol: fallback, color: color, emoji: emoji)
        case let .image(path, _):
            self.init(symbol: fallback, color: color, image: CommandIcons.image(path) != nil ? path : nil)
        }
    }
}

extension NSColor {
    /// An icon's color: the system's colors (they follow the appearance), a gray, or an exact sRGB one.
    static func icon(_ color: IconToken.Color) -> NSColor {
        switch color {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .mint: return .systemMint
        case .teal: return .systemTeal
        case .cyan: return .systemCyan
        case .blue: return .systemBlue
        case .indigo: return .systemIndigo
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .brown: return .systemBrown
        case .gray: return .systemGray
        case let .grayscale(white): return NSColor(white: CGFloat(white), alpha: 1)
        case let .rgb(red, green, blue):
            return NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
        }
    }
}
