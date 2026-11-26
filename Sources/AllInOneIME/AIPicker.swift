import AllInOneIMECore
import AppKit
import SwiftUI

/// The logos of Settings → AI's choices (`AIChoice`), all of one tone: monochrome PDFs in the app's Resources/AILogos
/// (made from the SVGs beside them in the repository by Scripts/make-ai-logos.swift), drawn as template images, so that
/// they take the text's color in light and dark mode. AllInOneIME Cloud's is the app's own mark (the menu bar's,
/// panel-icon.tiff).
/// Missing (a build run outside the app), a choice shows its initials instead.
@MainActor
enum AILogos {
    private static var images: [String: NSImage] = [:]

    /// The logo's file, without its extension.
    static func file(_ choice: AIChoice) -> String {
        switch choice {
        case .cli(.claude): return "claude"
        case .cli(.codex), .provider(.openai): return "openai"
        case .cli(.antigravity): return "antigravity"
        case .provider(.gemini): return "googlegemini"
        case .cli(.kiro): return "kiro"
        case .provider(.anthropic): return "anthropic"
        case .provider(.bedrock): return "amazonwebservices"
        case .provider(.apple): return "apple"
        case .provider(.hosted): return "panel-icon"
        }
    }

    static func image(_ choice: AIChoice) -> NSImage? {
        let name = file(choice)
        if let image = images[name] { return image }
        let url = choice == .provider(.hosted) ? Bundle.main.url(forResource: name, withExtension: "tiff")
            : Bundle.main.url(forResource: name, withExtension: "pdf", subdirectory: "AILogos")
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        images[name] = image
        return image
    }

    /// What stands for a choice without its logo: "A1" for AllInOneIME Cloud, else its name's first letters.
    static func initials(_ choice: AIChoice) -> String {
        if choice == .provider(.hosted) { return "A1" }
        return String(choice.name.split(separator: " ").prefix(2).compactMap(\.first))
    }
}

/// A choice's logo on its tile: a rounded square a shade off the background, the logo in the text's color.
struct AILogoTile: View {
    let choice: AIChoice
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size / 4, style: .continuous).fill(Color.primary.opacity(0.06))
            if let image = AILogos.image(choice) {
                Image(nsImage: image).renderingMode(.template).resizable().interpolation(.high).scaledToFit()
                    .foregroundStyle(.primary).frame(width: size * 0.62, height: size * 0.62)
            } else {
                Text(AILogos.initials(choice)).font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Settings → AI, collapsed (0.7.4's design, #174): the AI chosen (its logo, its name, how it is now: orange when it
/// can't answer) and Change ▾, which opens the choices (`AIChoiceSettings`). Its own settings are the rows under it
/// (`SettingsView.providerSection`).
struct AIChosenRow: View {
    let choice: AIChoice
    let status: AIStatus
    let change: () -> Void

    var body: some View {
        Button(action: change) {
            HStack(spacing: 12) {
                AILogoTile(choice: choice, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                    Text(choice.detail(status)).font(.callout).foregroundStyle(status.isProblem ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(tr("更换 ▾", "Change ▾")).foregroundStyle(Color.accentColor).fontWeight(.medium)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("更换 AI", "Change the AI") + tr("：", ": ") + choice.name + tr("，", ", ", key: "ai.label.separator") + status.text)
    }
}

/// Settings → AI's two states (#174): collapsed, as the page shows each time (`AIChosenRow`, the chosen AI's settings
/// under it), or choosing (Change ▾): every choice offered as a card, by group. A card picked is chosen and the page
/// collapses; Cancel (Esc) collapses it, nothing chosen. The settings search landing on another AI, or the start or the
/// Doctor pointing at a card not in use, opens the choices, that card scrolled to. Kept by the window's model
/// (`SettingsModel.aiCards`), so that the window scrolls to the card it points at.
struct AIPickerState {
    typealias Groups = [(group: AIChoice.Group, choices: [AIChoice])]

    private(set) var chosen: AIChoice
    /// Every choice offered (`AIChoice.groups`), the one in use among them.
    private(set) var groups: Groups
    private(set) var choosing = false
    /// The card the search or a pointer asked for (offered, not in use), scrolled to as the choices open.
    private(set) var scrollTarget: AIChoice?

    init(chosen: AIChoice, groups: Groups) {
        self.chosen = chosen
        self.groups = groups
    }

    /// The cards shown: none while collapsed.
    var visibleGroups: Groups { choosing ? groups : [] }

    /// What the page offers now (the AI chosen elsewhere, Apple's model found), its state kept.
    mutating func update(chosen: AIChoice, groups: Groups) {
        self.chosen = chosen
        self.groups = groups
    }

    /// Change ▾: the choices open, nothing chosen.
    mutating func change() { choosing = true }

    /// Cancel, or Esc: collapsed, nothing chosen.
    mutating func cancel() {
        choosing = false
        scrollTarget = nil
    }

    /// A click on a card: chosen, the page collapsed.
    mutating func pick(_ choice: AIChoice) {
        chosen = choice
        cancel()
    }

    /// The page left (another page, the window closed) while choosing or pointed at a card: collapsed, so that it
    /// comes back as it starts, the card pointed at forgotten.
    mutating func pageLeft() { cancel() }

    /// The page shown (`search` and `target` nil: collapsed), or pointed at: by the settings search (`search`: what was
    /// typed, "Choose the AI", "kiro"), or by the start or the Doctor (`target`, a card). Pointed at, the choices open
    /// unless the card asked for (the target, else a choice the search names) is the one in use, whose row is at the
    /// top; that card is scrolled to, if it is offered.
    mutating func show(search: String?, target: AIChoice?) {
        let wanted = target ?? search.flatMap(Self.named)
        choosing = (target != nil || search != nil) && wanted != chosen
        scrollTarget = choosing ? wanted.flatMap { wanted in groups.contains { $0.choices.contains(wanted) } ? wanted : nil } : nil
    }

    /// The first choice (`AIChoice.all`'s order) that every word typed begins a word of, in its name or its config value
    /// ("kiro", "bedrock", "claude"); nil for none ("Choose the AI", "订阅").
    static func named(_ search: String) -> AIChoice? {
        let typed = search.lowercased().split(whereSeparator: \.isWhitespace)
        guard !typed.isEmpty else { return nil }
        return AIChoice.all.first { choice in
            let words = (choice.name + " " + choice.id).lowercased().split { !$0.isLetter && !$0.isNumber }
            return typed.allSatisfy { part in words.contains { $0.hasPrefix(part) } }
        }
    }
}

/// What is above the cards while choosing: what they are for, and Cancel at the right, which Esc presses too.
struct AIChoicesHeader: View {
    let cancel: () -> Void

    var body: some View {
        HStack {
            Text(SettingsSpot.provider.title).font(.system(size: 14, weight: .semibold))
            Spacer()
            // Esc is this button's own key, so that it takes the same path as a click (`AIPickerState.cancel`).
            Button(tr("取消", "Cancel"), action: cancel).keyboardShortcut(.cancelAction)
                .buttonStyle(.plain).foregroundStyle(Color.accentColor)
        }
    }
}

/// Settings → AI, choosing: Cancel at the top (`AIChoicesHeader`), then every choice as a card, by group
/// (`AIChoice.groups`): one click chooses one; the chosen one is outlined and says In use (#121's cards, shown by
/// `AIChoiceSettings`).
struct AIChoicesGrid: View {
    let chosen: AIChoice
    let groups: [(group: AIChoice.Group, choices: [AIChoice])]
    let status: (AIChoice) -> AIStatus
    let pick: (AIChoice) -> Void
    let cancel: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 10, alignment: .top), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AIChoicesHeader(cancel: cancel)
            ForEach(groups.indices, id: \.self) { index in
                let entry = groups[index]
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(entry.group.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        Text(entry.group.note).font(.callout).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(entry.choices, id: \.self) { choice in
                            AIChoiceCard(choice: choice, status: status(choice), chosen: choice == chosen) { pick(choice) }
                                .id(choice)  // scrolled to when pointed at (`AIPickerState.scrollTarget`)
                        }
                    }
                }
            }
        }
    }
}

/// One choice: its logo, its name and a caption: In use for the chosen one; the others' status in gray, never orange
/// (on a fresh install most aren't set up, and orange everywhere reads as an error; #121).
struct AIChoiceCard: View {
    enum Tone: Equatable { case secondary, inUse }

    let choice: AIChoice
    let status: AIStatus
    let chosen: Bool
    let pick: () -> Void

    /// What the card says under its name, and in which color.
    static func caption(_ status: AIStatus, chosen: Bool) -> (text: String, tone: Tone) {
        chosen ? (tr("正在使用", "In use"), .inUse) : (status.text, .secondary)
    }

    var body: some View {
        Button(action: pick) {
            // Every card as tall as one with a name on two lines ("AllInOneIME Cloud" in a narrow window), so that a row's
            // cards line up.
            HStack(spacing: 7) {
                AILogoTile(choice: choice, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    let caption = Self.caption(status, chosen: chosen)
                    Text(caption.text).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(caption.tone == .inUse ? Color.accentColor : Color.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(chosen ? Color.accentColor : Color.primary.opacity(0.14), lineWidth: chosen ? 2 : 1)
            }
            .background {
                if chosen {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.accentColor.opacity(0.18), lineWidth: 3).padding(-2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.name + tr("，", ", ", key: "ai.label.separator") + Self.caption(status, chosen: chosen).text)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// A CLI chosen as the AI: its session (the name it has in the CLI's own list, Start Over), how to go on in Terminal, or
/// what it lacks (installing it, signing in); then where what has to be fast goes (`AIChoice.fallbackNote`).
struct AISessionRows: View {
    @ObservedObject var model: SettingsModel
    let agent: SessionAgent
    let status: AIStatus
    @State private var startedOver = false

    var body: some View {
        switch status {
        case let .notInstalled(program):
            LabeledContent(tr("没装", "Not installed", key: "ai.status.notInstalled")) {
                Text(tr("装好 \(program) 后回到这里", "Install \(program), then come back here")).foregroundStyle(.secondary)
            }
        case .signedOut:
            LabeledContent(tr("怎么登录", "How to sign in")) {
                Text(tr("终端里运行 \(agent.signIn)", "Run \(agent.signIn) in Terminal")).textSelection(.enabled)
            }
        default:
            LabeledContent {
                Button(tr("重新开始", "Start Over")) {
                    startedOver = (try? ClaudeSessionMac.manager(agent).startOver()) != nil
                }
            } label: {
                let name = agent.displayName
                titled(tr("会话：\(sessionName)", "Session: \(sessionName)"),
                       startedOver ? tr("✓ 下一个问题开始一个新会话", "✓ The next question starts a new session")
                           : UIText.triggered(tr("每个 @question 对话在这里都是一个新对话，追问留在里面。「重新开始」现在就换一个新对话（旧的还在 \(name) 的历史里）。",
                                                 "Each @question conversation is a new one here, its follow-ups in it. Start Over begins a new one now (the old one stays in \(name)'s history).")))
            }
            LabeledContent(tr("终端里接着聊", "Continue in Terminal")) {
                Text("⌘⏎").foregroundStyle(.secondary)
            }
        }
        Text(AIChoice.fallbackNote(model.config.fastProvider(model.aiFacts)))
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    /// What the session is called where the user finds it: "AllInOneIME" in Claude Code's and Codex's lists, its folder
    /// ("kiro-session") for the others.
    private var sessionName: String {
        agent == .claude || agent == .codex ? SessionAgent.sessionName
            : ClaudeSessionMac.manager(agent).store.directory.lastPathComponent
    }
}
