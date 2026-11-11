import AllInOneIMECore
import AppKit

/// This week's card, drawn: Settings → This Week shows it (`style` `.page`), and the picture `WeekStatsShareImage` copies
/// or saves is it (`.share`, 640 × 540 points), so the two are the same card. As the owner's design lays it out (Main,
/// ShareCard, FirstWeek): the days and the version on top; the headline, the week's number and how it compares, the days
/// and apps, the bars Monday to Sunday on the left; the commands run most, each with its own icon as the command list
/// draws it, on the right; where they came from and how many used AI; the clipboard history pastes at the bottom. In the
/// system's fonts and colors (the label colors, the accent color) of the appearance it's drawn in.
///
/// Drawn with AppKit's text and Core Graphics into the current graphics context, flipped, on any thread: the picture is
/// made off the main thread too.
public struct WeekStatsCard: @unchecked Sendable {
    public enum Style: Sendable {
        /// On the settings page: today named and bold, the card's own background and border.
        case page
        /// The picture: every day named, the footer at the bottom of 540 points.
        case share
    }

    public let text: WeekStatsText
    public let style: Style
    /// The user's own command names hidden (`.share` only: the page always shows them).
    public let hideOwnCommandNames: Bool
    /// A command's icon, by its id and where it comes from (the command list's: `IconToken.command`).
    public let icon: (WeekStats.Snapshot.CommandCount) -> IconToken

    public static let shareSize = CGSize(width: 640, height: 540)

    public init(week: WeekStats.Snapshot, language: String, style: Style, hideOwnCommandNames: Bool = false,
                icon: @escaping (WeekStats.Snapshot.CommandCount) -> IconToken = WeekStatsCard.builtInIcon) {
        text = WeekStatsText(week, language: language)
        self.style = style
        self.hideOwnCommandNames = style == .share && hideOwnCommandNames
        self.icon = icon
    }

    /// A command's icon without the catalog: a built-in one's own, else one for where it comes from.
    public static func builtInIcon(_ command: WeekStats.Snapshot.CommandCount) -> IconToken {
        if let builtIn = Command.builtins.first(where: { $0.name == command.id }), command.source == .builtIn {
            return IconToken.command(builtIn)
        }
        switch command.source {
        case .plugin: return IconToken(.plugin, color: .pink)
        case .own, .builtIn: return IconToken(.command, color: .indigo)
        }
    }

    // MARK: - Size

    private var padding: CGFloat { style == .share ? 32 : 22 }
    private static let gap: CGFloat = 16
    private static let columnGap: CGFloat = 28
    private static let barHeight: CGFloat = 64

    /// How tall the card is `width` points wide: the picture's 540; the page's as its content needs.
    public func height(forWidth width: CGFloat) -> CGFloat {
        if style == .share { return Self.shareSize.height }
        let inner = width - 2 * padding
        return padding + 16 + Self.gap + columnsHeight(inner) + Self.gap + 1 + Self.gap + 58 + Self.gap + 1 + Self.gap + 18 + padding
    }

    // MARK: - Drawing

    /// Draws the card in `rect` of the current graphics context (flipped), in its drawing appearance.
    public func draw(in rect: CGRect) {
        let palette = Palette()
        let inner = rect.insetBy(dx: padding, dy: padding)
        if style == .page {
            let card = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
            palette.background.setFill()
            card.fill()
            palette.separator.setStroke()
            card.lineWidth = 1
            card.stroke()
        } else {
            palette.background.setFill()
            rect.fill()
        }
        var y = inner.minY
        // The days, and the version.
        let version = attributed(text.versionLabel, Fonts.small, palette.secondary)
        let versionWidth = ceil(version.size().width)
        draw(version, x: inner.maxX - versionWidth, y: y, width: versionWidth, line: 16)
        draw(attributed(text.dateSubtitle, Fonts.small, palette.secondary), x: inner.minX, y: y,
             width: inner.width - versionWidth - 12, line: 16)
        y += 16 + Self.gap

        let column = (inner.width - Self.columnGap) / 2
        let height = columnsHeight(inner.width)
        drawLeft(CGRect(x: inner.minX, y: y, width: column, height: height), palette)
        drawRight(CGRect(x: inner.minX + column + Self.columnGap, y: y, width: column, height: height), palette)
        y += height + Self.gap
        palette.separator.setFill()
        CGRect(x: inner.minX, y: y, width: inner.width, height: 1).fill()
        y += 1 + Self.gap
        drawSources(CGRect(x: inner.minX, y: y, width: inner.width, height: 58), palette)
        y += 58
        if style == .share {
            // At the bottom, a line over it.
            let top = inner.maxY - 18 - 14 - 1
            palette.separator.setFill()
            CGRect(x: inner.minX, y: top, width: inner.width, height: 1).fill()
            drawFooter(CGRect(x: inner.minX, y: top + 15, width: inner.width, height: 18), palette)
        } else {
            y += Self.gap
            palette.separator.setFill()
            CGRect(x: inner.minX, y: y, width: inner.width, height: 1).fill()
            y += 1 + Self.gap
            drawFooter(CGRect(x: inner.minX, y: y, width: inner.width, height: 18), palette)
        }
    }

    // MARK: The left column

    /// The headline's block and the bars: as tall as either column needs.
    private func columnsHeight(_ width: CGFloat) -> CGFloat {
        max(leftHeight, rightHeight((width - Self.columnGap) / 2))
    }

    private var hasComparisonLine: Bool { text.comparison != nil }

    private var leftHeight: CGFloat {
        20 + 8 + 64 + 8 + (hasComparisonLine ? 22 + 8 : 0) + 16 + 18 + 16 + 4 + Self.barHeight + 4 + 16
    }

    private func drawLeft(_ rect: CGRect, _ palette: Palette) {
        var y = rect.minY
        draw(attributed(style == .share ? text.shareHeadline : text.headline, Fonts.headline, palette.primary),
             x: rect.minX, y: y, width: rect.width, line: 20)
        y += 20 + 8
        // The number, and what it counts on its baseline.
        let number = attributed(text.count, Fonts.number, palette.primary, kern: -1)
        let numberSize = number.size()
        let numberTop = y + (64 - (Fonts.number.ascender - Fonts.number.descender)) / 2
        number.draw(at: CGPoint(x: rect.minX, y: numberTop))
        let baseline = numberTop + Fonts.number.ascender
        let unit = attributed(text.countUnit, Fonts.unit, palette.primary)
        unit.draw(at: CGPoint(x: rect.minX + ceil(numberSize.width) + 8, y: baseline - Fonts.unit.ascender))
        y += 64 + 8
        if let comparison = text.comparison {
            if let percent = text.comparisonPercent, let label = text.comparisonLabel {
                let width = drawBadge(percent, trend: text.trend ?? .same, x: rect.minX, y: y, palette)
                draw(attributed(label, Fonts.small, palette.secondary), x: rect.minX + width + 8, y: y,
                     width: rect.width - width - 8, line: 22)
            } else {
                draw(attributed(comparison, Fonts.small, palette.secondary), x: rect.minX, y: y, width: rect.width, line: 22)
            }
            y += 22 + 8
        }
        draw(attributed(text.activity, Fonts.small, palette.secondary), x: rect.minX, y: y, width: rect.width, line: 16)
        y += 16 + 18
        drawBars(CGRect(x: rect.minX, y: y, width: rect.width, height: 16 + 4 + Self.barHeight + 4 + 16), palette)
    }

    /// The comparison's pill: an arrow and the percent, in the accent color on a wash of it. Its width.
    private func drawBadge(_ percent: String, trend: WeekStatsText.Trend, x: CGFloat, y: CGFloat, _ palette: Palette) -> CGFloat {
        let label = attributed(percent, Fonts.badge, palette.accent)
        let arrow: NSImage? = trend == .same ? nil
            : symbol(trend == .up ? "arrow.up" : "arrow.down", size: 9, weight: .bold, color: palette.accent)
        let arrowWidth = arrow.map { ceil($0.size.width) + 3 } ?? 0
        let width = 8 + arrowWidth + ceil(label.size().width) + 8
        palette.badge.setFill()
        NSBezierPath(roundedRect: CGRect(x: x, y: y, width: width, height: 22), xRadius: 11, yRadius: 11).fill()
        if let arrow {
            arrow.draw(in: CGRect(x: x + 8, y: y + (22 - arrow.size.height) / 2, width: arrow.size.width, height: arrow.size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        draw(label, x: x + 8 + arrowWidth, y: y, width: width, line: 22)
        return width
    }

    /// Monday to Sunday: each day's count over its bar (the tallest the full height), its weekday under it; a day without
    /// any (or still to come) a short gray bar and a dash.
    private func drawBars(_ rect: CGRect, _ palette: Palette) {
        let days = text.week.days
        let gap: CGFloat = 6
        let width = (rect.width - 6 * gap) / 7
        let most = max(days.filter { !$0.isFuture }.map(\.commandCount).max() ?? 0, 1)
        let counts = text.barLabels, names = text.weekdayLabels(forShare: style == .share)
        for (index, day) in days.enumerated() {
            let x = rect.minX + CGFloat(index) * (width + gap)
            let today = style == .page && day.isToday
            let empty = day.commandCount == 0 || day.isFuture
            let count = attributed(counts[index], today ? Fonts.digitsBold : Fonts.digits, empty ? palette.secondary : palette.primary)
            draw(count, x: x, y: rect.minY, width: width, line: 16, centered: true)
            let bottom = rect.minY + 16 + 4 + Self.barHeight
            if empty {
                palette.empty.setFill()
                NSBezierPath(roundedRect: CGRect(x: x, y: bottom - 4, width: width, height: 4), xRadius: 2, yRadius: 2).fill()
            } else {
                let height = max((CGFloat(day.commandCount) / CGFloat(most) * Self.barHeight).rounded(), 6)
                palette.accent.setFill()
                NSBezierPath(roundedRect: CGRect(x: x, y: bottom - height, width: width, height: height), xRadius: 5, yRadius: 5).fill()
            }
            let name = attributed(names[index], today ? Fonts.smallBold : Fonts.small, today ? palette.accent : palette.secondary)
            draw(name, x: x - gap / 2, y: bottom + 4, width: width + gap, line: 16, centered: true)
        }
    }

    // MARK: The right column

    private func rightHeight(_ width: CGFloat) -> CGFloat {
        let rows = CGFloat(text.week.topCommands.count)
        let list = rows > 0 ? rows * 26 + (rows - 1) * 8 + 10 : 0
        return 16 + 10 + list + footnoteHeight(width)
    }

    private var footnote: String { text.otherCommands ?? text.commandHint ?? "" }

    private func footnoteHeight(_ width: CGFloat) -> CGFloat {
        let size = attributed(footnote, Fonts.small, .black).boundingRect(
            with: CGSize(width: width, height: 200), options: [.usesLineFragmentOrigin]).size
        return max(16, ceil(size.height))
    }

    private func drawRight(_ rect: CGRect, _ palette: Palette) {
        var y = rect.minY
        draw(attributed(text.topCommandsTitle, Fonts.smallBold, palette.secondary), x: rect.minX, y: y, width: rect.width, line: 16)
        y += 16 + 10
        let commands = text.week.topCommands
        let shown = text.week.shareCommands(hideOwnCommandNames: hideOwnCommandNames, language: text.language)
        let most = max(commands.first?.count ?? 1, 1)
        for (index, command) in commands.enumerated() {
            let row = CGRect(x: rect.minX, y: y, width: rect.width, height: 26)
            drawIcon(icon(command), in: CGRect(x: row.minX, y: row.midY - 11, width: 22, height: 22), palette)
            let name = shown[index]
            draw(attributed(name.displayName, name.isHidden ? Fonts.small : Fonts.mono, palette.primary),
                 x: row.minX + 30, y: row.minY, width: 84, line: 26)
            let count = attributed("\(command.count)", Fonts.count, palette.primary)
            let countWidth = max(24, ceil(count.size().width))
            draw(count, x: row.maxX - countWidth, y: row.minY, width: countWidth, line: 26, alignment: .right)
            let track = CGRect(x: row.minX + 30 + 84 + 8, y: row.midY - 3, width: max(row.width - 30 - 84 - 8 - 8 - countWidth, 0), height: 6)
            palette.track.setFill()
            NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
            var filled = track
            filled.size.width = max(track.width * CGFloat(command.count) / CGFloat(most), 6)
            palette.accent.setFill()
            NSBezierPath(roundedRect: filled, xRadius: 3, yRadius: 3).fill()
            y += 26 + 8
        }
        if !commands.isEmpty { y += 10 - 8 }
        attributed(footnote, Fonts.small, palette.secondary)
            .draw(with: CGRect(x: rect.minX, y: y, width: rect.width, height: footnoteHeight(rect.width)), options: [.usesLineFragmentOrigin])
    }

    /// A command's icon as the command list draws it: its symbol in its color on a light wash of it, a rounded square;
    /// an emoji as it is.
    private func drawIcon(_ token: IconToken, in frame: CGRect, _ palette: Palette) {
        let color = Self.color(token.color)
        let fallback = token.fallback.appleSymbol
        var name = fallback
        switch token.glyph {
        case let .builtin(builtin):
            name = builtin.appleSymbol
        case let .symbol(symbol, _):
            if NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil { name = symbol }
        case let .emoji(emoji, _):
            let glyph = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: frame.height * 0.8)])
            let size = glyph.size()
            glyph.draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
            return
        case .image, .item:
            break
        }
        color.withAlphaComponent(palette.dark ? 0.26 : 0.15).setFill()
        NSBezierPath(roundedRect: frame, xRadius: frame.width * 0.28, yRadius: frame.height * 0.28).fill()
        var ink = color
        if let rgb = color.usingColorSpace(.sRGB) {
            ink = (palette.dark ? rgb.blended(withFraction: 0.15, of: .white) : rgb.blended(withFraction: 0.22, of: .black)) ?? rgb
        }
        guard let image = symbol(name, size: frame.height * 0.52, weight: .semibold, color: ink)
                ?? symbol("command", size: frame.height * 0.52, weight: .semibold, color: ink) else { return }
        let size = image.size
        image.draw(in: CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// An icon's color: the system's (they follow the appearance), a gray, or an exact one (the command list's).
    public static func color(_ color: IconToken.Color) -> NSColor {
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

    // MARK: Where from, and the pastes

    private func drawSources(_ rect: CGRect, _ palette: Palette) {
        var y = rect.minY
        let ai = attributed(text.aiSummary, Fonts.small, palette.secondary)
        let aiWidth = ceil(ai.size().width)
        draw(ai, x: rect.maxX - aiWidth, y: y, width: aiWidth, line: 16)
        draw(attributed(text.sourcesTitle, Fonts.smallBold, palette.secondary), x: rect.minX, y: y,
             width: rect.width - aiWidth - 12, line: 16)
        y += 16 + 8
        // The split: the user's own, built in, plugins, as many as each ran; gray when none ran.
        let counts = text.week.sourceCounts
        let parts = WeekStats.CommandSource.allCases.map { ($0, counts[$0]) }.filter { $0.1 > 0 }
        let colors: [WeekStats.CommandSource: NSColor] = [.own: palette.accent, .builtIn: palette.accentMid, .plugin: palette.accentLight]
        if parts.isEmpty {
            palette.empty.setFill()
            NSBezierPath(roundedRect: CGRect(x: rect.minX, y: y, width: rect.width, height: 10), xRadius: 5, yRadius: 5).fill()
        } else {
            let available = rect.width - CGFloat(parts.count - 1) * 2
            let total = CGFloat(parts.reduce(0) { $0 + $1.1 })
            var x = rect.minX
            for (index, (source, count)) in parts.enumerated() {
                let width = index == parts.count - 1 ? rect.maxX - x : (available * CGFloat(count) / total).rounded()
                let segment = CGRect(x: x, y: y, width: max(width, 2), height: 10)
                colors[source]?.setFill()
                Self.segment(segment, first: index == 0, last: index == parts.count - 1).fill()
                x += width + 2
            }
        }
        y += 10 + 8
        // The legend.
        var x = rect.minX
        for source in WeekStats.CommandSource.allCases {
            colors[source]?.setFill()
            NSBezierPath(roundedRect: CGRect(x: x, y: y + 4, width: 8, height: 8), xRadius: 2, yRadius: 2).fill()
            x += 8 + 6
            let name = attributed(text.sourceName(source), Fonts.small, palette.primary)
            draw(name, x: x, y: y, width: ceil(name.size().width), line: 16)
            x += ceil(name.size().width) + 6
            let count = attributed("\(counts[source])", Fonts.smallDigitsBold, palette.primary)
            draw(count, x: x, y: y, width: ceil(count.size().width), line: 16)
            x += ceil(count.size().width) + 18
        }
    }

    /// A segment of the split bar: rounded more at the bar's ends.
    private static func segment(_ rect: CGRect, first: Bool, last: Bool) -> NSBezierPath {
        let outer: CGFloat = 5, inner: CGFloat = 2
        let left = first ? outer : inner, right = last ? outer : inner
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.minX + left, y: rect.minY))
        path.line(to: CGPoint(x: rect.maxX - right, y: rect.minY))
        path.appendArc(withCenter: CGPoint(x: rect.maxX - right, y: rect.minY + right), radius: right, startAngle: 270, endAngle: 0)
        path.line(to: CGPoint(x: rect.maxX, y: rect.maxY - right))
        path.appendArc(withCenter: CGPoint(x: rect.maxX - right, y: rect.maxY - right), radius: right, startAngle: 0, endAngle: 90)
        path.line(to: CGPoint(x: rect.minX + left, y: rect.maxY))
        path.appendArc(withCenter: CGPoint(x: rect.minX + left, y: rect.maxY - left), radius: left, startAngle: 90, endAngle: 180)
        path.line(to: CGPoint(x: rect.minX, y: rect.minY + left))
        path.appendArc(withCenter: CGPoint(x: rect.minX + left, y: rect.minY + left), radius: left, startAngle: 180, endAngle: 270)
        path.close()
        return path
    }

    /// "另外，从剪贴板历史粘贴了 47 次" (the number bold) with the clipboard's icon, and what is kept of them on the right.
    private func drawFooter(_ rect: CGRect, _ palette: Palette) {
        let note = attributed(text.clipboardNote, Fonts.small, palette.secondary)
        let noteWidth = ceil(note.size().width)
        draw(note, x: rect.maxX - noteWidth, y: rect.minY, width: noteWidth, line: 18)
        if let icon = symbol("clipboard", size: 11, weight: .regular, color: palette.secondary) {
            icon.draw(in: CGRect(x: rect.minX + (13 - icon.size.width) / 2, y: rect.midY - icon.size.height / 2,
                                 width: icon.size.width, height: icon.size.height),
                      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let pastes = NSMutableAttributedString(attributedString: attributed(text.clipboardPastes, Fonts.small, palette.secondary))
        let number = "\(text.week.clipboardPasteCount)"
        let range = (pastes.string as NSString).range(of: number)
        if range.location != NSNotFound {
            pastes.addAttributes([.font: Fonts.smallDigitsBold, .foregroundColor: palette.primary], range: range)
        }
        draw(pastes, x: rect.minX + 19, y: rect.minY, width: rect.width - 19 - noteWidth - 12, line: 18)
    }

    // MARK: - Text

    private func attributed(_ string: String, _ font: NSFont, _ color: NSColor, kern: CGFloat = 0) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if kern != 0 { attributes[.kern] = kern }
        return NSAttributedString(string: string, attributes: attributes)
    }

    /// One line of `text` in a line `line` points tall at `y`, cut short with "…" past `width`.
    private func draw(_ text: NSAttributedString, x: CGFloat, y: CGFloat, width: CGFloat, line: CGFloat, centered: Bool = false,
                      alignment: NSTextAlignment = .left) {
        guard width > 0 else { return }
        let font = text.length > 0 ? (text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) : nil
        let height = font.map { ceil($0.ascender - $0.descender + $0.leading) } ?? line
        let shown = NSMutableAttributedString(attributedString: text)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = centered ? .center : alignment
        shown.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: shown.length))
        shown.draw(with: CGRect(x: x, y: y + (line - height) / 2, width: width, height: height),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }

    /// Fonts are immutable: shared by every thread that draws.
    private enum Fonts {
        nonisolated(unsafe) static let small = NSFont.systemFont(ofSize: 12)
        nonisolated(unsafe) static let smallBold = NSFont.systemFont(ofSize: 12, weight: .semibold)
        nonisolated(unsafe) static let digits = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        nonisolated(unsafe) static let digitsBold = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        nonisolated(unsafe) static let smallDigitsBold = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        nonisolated(unsafe) static let headline = NSFont.systemFont(ofSize: 14)
        nonisolated(unsafe) static let unit = NSFont.systemFont(ofSize: 18, weight: .semibold)
        nonisolated(unsafe) static let badge = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        nonisolated(unsafe) static let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        nonisolated(unsafe) static let count = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        /// The week's number: the system's rounded design, bold, digits of one width.
        nonisolated(unsafe) static let number: NSFont = {
            let bold = NSFont.systemFont(ofSize: 64, weight: .bold)
            let rounded = bold.fontDescriptor.withDesign(.rounded) ?? bold.fontDescriptor
            let digits = rounded.addingAttributes([.featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                                                                      .selectorIdentifier: kMonospacedNumbersSelector]]])
            return NSFont(descriptor: digits, size: 64) ?? bold
        }()
    }

    /// The card's colors in the drawing appearance (light or dark): the system's labels and separators, the accent color
    /// and two lighter steps of it (toward the background) for the split.
    private struct Palette {
        let dark: Bool
        let background: NSColor
        let primary: NSColor
        let secondary: NSColor
        let separator: NSColor
        let accent: NSColor
        let accentMid: NSColor
        let accentLight: NSColor
        let badge: NSColor
        let empty: NSColor
        let track: NSColor

        init() {
            let appearance = NSAppearance.currentDrawing()
            dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            func resolved(_ color: NSColor) -> NSColor { color.usingColorSpace(.sRGB) ?? color }
            background = dark ? NSColor(srgbRed: 0.137, green: 0.137, blue: 0.141, alpha: 1)
                : NSColor(srgbRed: 0.984, green: 0.984, blue: 0.984, alpha: 1)
            primary = resolved(.labelColor)
            secondary = resolved(.secondaryLabelColor)
            separator = resolved(.separatorColor)
            let accent = resolved(.controlAccentColor)
            self.accent = accent
            accentMid = accent.blended(withFraction: 0.35, of: background) ?? accent
            accentLight = accent.blended(withFraction: 0.7, of: background) ?? accent
            badge = accent.withAlphaComponent(dark ? 0.24 : 0.12)
            empty = resolved(dark ? NSColor(white: 1, alpha: 0.16) : NSColor(white: 0, alpha: 0.15))
            track = resolved(dark ? NSColor(white: 1, alpha: 0.1) : NSColor(white: 0, alpha: 0.07))
        }
    }
}
