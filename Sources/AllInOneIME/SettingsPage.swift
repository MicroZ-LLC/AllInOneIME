import AllInOneIMECore
import SwiftUI

/// The settings window's pages (owner, 0.7.5, #120): the sidebar's six (`sidebar`), Common first, and More Settings'
/// five groups, each a short page of its own with a back button to More Settings (`groups`, `parent`). Every row
/// (`SettingsSpot`) lives in one of them; only where a row is shown changed, never its config key.
enum SettingsPage: String, CaseIterable, Identifiable {
    case common, ai
    /// This week's stats (`WeekStatsPage`): how much AllInOneIME was used, as a picture to share.
    case week
    case commands, more, about
    /// More Settings' groups.
    case inputAndKeys, suggestions, privacy, interface, advanced

    var id: String { rawValue }

    /// The sidebar's pages, in order; a thin line before More Settings.
    static let sidebar: [SettingsPage] = [.common, .ai, .week, .commands, .more, .about]

    /// More Settings' groups, in order.
    static let groups: [SettingsPage] = [.inputAndKeys, .suggestions, .privacy, .interface, .advanced]

    /// More Settings for a group, nothing for a sidebar page.
    var parent: SettingsPage? { Self.groups.contains(self) ? .more : nil }

    /// The sidebar's page it is under: its own, or More Settings for a group.
    var sidebarPage: SettingsPage { parent ?? self }

    var title: String {
        switch self {
        case .common: return tr("常用", "Common")
        case .ai: return tr("AI", "AI")
        case .week: return WeekStatsText.sidebarTitle(language: UIText.language)
        case .commands: return tr("命令库", "Commands")
        case .more: return tr("更多设置", "More Settings")
        case .about: return tr("关于", "About")
        case .inputAndKeys: return tr("输入与按键", "Input and keys")
        case .suggestions: return tr("建议", "Suggestions")
        case .privacy: return tr("隐私", "Privacy")
        case .interface: return tr("界面与同步", "Interface and sync")
        case .advanced: return tr("高级", "Advanced")
        }
    }

    /// Where it is, as the search's results say it: "More Settings › Privacy" for a group.
    var place: String { parent.map { $0.title + " › " + title } ?? title }

    var icon: CandidateView.Icon {
        switch self {
        case .common: return CandidateView.Icon(symbol: "star.fill", color: .systemBlue)
        case .ai: return CommandIcons.provider
        case .week: return CommandIcons.icon(for: .stats)
        case .commands: return CommandIcons.commands
        case .more: return CandidateView.Icon(symbol: "ellipsis", color: .systemGray)
        case .about: return CandidateView.Icon(symbol: "info", color: .systemBlue)
        case .inputAndKeys: return CandidateView.Icon(symbol: "keyboard.fill", color: .systemBlue)
        case .suggestions: return CandidateView.Icon(symbol: "list.bullet.rectangle.fill", color: .systemTeal)
        case .privacy: return CandidateView.Icon(symbol: "hand.raised.fill", color: .systemBlue)
        case .interface: return CandidateView.Icon(symbol: "macwindow", color: .systemIndigo)
        case .advanced: return CommandIcons.advanced
        }
    }

    /// Its rows (`SettingsSpot`), in order; More Settings' are its groups'.
    var spots: [SettingsSpot] {
        self == .more ? Self.groups.flatMap(\.spots) : SettingsSpot.allCases.filter { $0.page == self }
    }

    /// How many of its rows `config` shows (More Settings: its groups' together).
    func shownCount(_ config: Config) -> Int { spots.filter { $0.isShown(config) }.count }

    /// Whether the page has a row `query` finds (its title counts too), with commands named with the command trigger
    /// (`trigger`: "~agent") as its rows name them ("@agent").
    func matches(_ query: String, trigger: String = "@") -> Bool {
        let words = query.lowercased().replacingOccurrences(of: trigger, with: "@").split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        return words.allSatisfy { title.lowercased().contains($0) } || spots.contains { $0.matches(query, trigger: trigger) }
    }

    /// The page a Doctor finding of `area` shows on, as a banner at its top (and a dot on its sidebar row, More Settings'
    /// for a group); what has no page of its own (secure input, the logs' errors) is About's, with Troubleshoot.
    static func of(_ area: Doctor.Area) -> SettingsPage {
        switch area {
        case .inputMethod, .languagePacks: return .common
        case .iCloudSync: return .interface
        case .provider, .connection, .appleIntelligence: return .ai
        case .permissions: return .privacy
        case .extensions: return .commands
        case .config: return .advanced
        case .updates, .secureInput, .recentErrors: return .about
        }
    }
}
