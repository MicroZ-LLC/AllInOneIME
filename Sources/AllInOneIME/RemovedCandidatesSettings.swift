import AllInOneIMECore
import SwiftUI

/// Settings → Input → the Chinese chip → Removed Candidates (「删掉的候选词」, `RemovedCandidates`): the candidates the user
/// removed with a right-click (or ⌃⌦ on the highlighted one) while typing pinyin, which never come up again
/// (`Config.removedCandidates`), the newest first, each brought back with its ✕ (`SettingsModel.restoreCandidate`, on the
/// list as the file has it then). Nothing is added here: a candidate is removed where it shows.
struct RemovedCandidatesSection: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Section {
            let removed = Array(model.config.removedCandidates.reversed())
            LabeledContent {
                if removed.isEmpty {
                    Text(tr("还没有", "None yet")).foregroundStyle(.secondary)
                }
            } label: {
                titled(tr("删掉的候选词", "Removed candidates"), tr("\(removed.count) 个，新的在前", "\(removed.count), the newest first"))
            }
            if !removed.isEmpty {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 6) {
                        ForEach(Array(removed.enumerated()), id: \.offset) { _, text in chip(text) }
                    }
                }
                .frame(maxHeight: 180)
            }
        } header: {
            SectionTitle(tr("删掉的候选词", "Removed candidates"), icon: CandidateView.Icon(symbol: "eye.slash", color: .systemTeal))
        } footer: {
            Text(tr("在候选词上点右键（或按 ⌃⌦ 删除高亮的那个），它就不会再出现，学到的也一并忘掉。点 ✕ 恢复。",
                    "Right-click a candidate (or press ⌃⌦ for the highlighted one) and it no longer comes up; what was learned of it is forgotten too. ✕ brings it back."))
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)  // under the card, from its left
        }
        .disabled(!model.canSave)
    }

    private func chip(_ text: String) -> some View {
        HStack(spacing: 2) {
            Text(text).lineLimit(1).truncationMode(.middle)
            Button { model.restoreCandidate(text) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .help(tr("恢复\(text)", "Restore \(text)"))
                .accessibilityLabel(tr("恢复\(text)", "Restore \(text)"))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.secondary.opacity(0.1), in: Capsule())
    }

    private func titled(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
