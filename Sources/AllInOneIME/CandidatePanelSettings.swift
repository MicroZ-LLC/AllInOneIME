import AllInOneIMECore
import AppKit
import SwiftUI

/// How the candidate panel looks: how a word's candidates are laid out (Common → Typing), and whether the keys are
/// explained at the panel's bottom (`Config.keyHints`, More Settings → Interface and sync). Each saved as it changes.
struct CandidatePanelRows: View {
    enum Rows { case layout, keyHints }

    @ObservedObject var model: SettingsModel
    /// The row shown.
    var rows: Rows

    var body: some View {
        switch rows {
        case .layout:
            layoutRow
                .onChange(of: model.config.candidateLayout) { model.save() }
        case .keyHints:
            keyHintsRow
                .onChange(of: model.config.keyHints) { model.save() }
        }
    }

    /// Common → how the candidates of a word being typed (pinyin, Hindi) are laid out: in a column, or in a row like
    /// macOS's own panel (owner, 0.7.4: with the input languages, no longer in Advanced).
    private var layoutRow: some View {
        LabeledContent {
            Picker("", selection: $model.config.candidateLayout) {
                Text(tr("竖排", "Vertical")).tag(CandidateArrangement.vertical)
                Text(tr("横排", "Horizontal")).tag(CandidateArrangement.horizontal)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        } label: {
            titled(SettingsSpot.candidateLayout.title, Self.layoutNote(model.config.candidateLayout))
        }
        .settingsRow(.candidateLayout, shown: model.spot)
    }

    /// Interface and sync → the keys explained at the bottom of the candidate box (⏎ inserts, Esc cancels…): on by default; off for a
    /// smaller box once they're known (forum, 0.7.5).
    private var keyHintsRow: some View {
        Toggle(isOn: $model.config.keyHints) {
            titled(.keyHints)
        }
        .settingsRow(.keyHints, shown: model.spot)
    }

    /// What the candidate layout's row says for `layout`, as the core's settings document says it too.
    static func layoutNote(_ layout: CandidateArrangement) -> String {
        layout == .horizontal
            ? tr("选词（拼音、印地语）的候选并排，像系统自带的输入法：← → 选词，↑↓ 或 - = 翻页。",
                 "Word candidates (pinyin, Hindi) side by side, like the system's own input methods: ← → choose, ↑↓ or - = turn the page.")
            : tr("选词（拼音、印地语）的候选一个一个往下排：↑↓ 选词，← → 或 - = 翻页。",
                 "Word candidates (pinyin, Hindi) one under the other: ↑↓ choose, ← → or - = turn the page.")
    }
}
