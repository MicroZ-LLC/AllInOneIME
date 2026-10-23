import AllInOneIMECore
import SwiftUI

/// Settings → General → Suggestions (spec suggestions v1, 3): their switch, the input menu's, for plugins' completions
/// (each turned on in Plugins) and Code's rows (Code is in Input) alike, an app's own choice in Apps; and forgetting the
/// rows picked.
struct SuggestionsSection: View {
    @ObservedObject var model: SettingsModel
    /// How many rows picked are kept (rows picked before come first).
    @State private var picked = 0

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { model.config.suggestions != false }, set: { model.setSuggestions($0) })) {
                titled(tr("建议", "Suggestions"),
                       tr("插件的补全（比如打 #12 列出 GitHub issue；每个插件的补全在「插件」里打开）和代码输入的关键字、代码片段（在「输入」里）：光标下面列出几行，按 Tab 插入。和输入法菜单里的「建议」是同一个开关；某个 App 里不要可以在「按 App 设置」里关掉。",
                          "Plugins' completions (#12 lists GitHub issues, say; turn each plugin's on in Plugins) and Code's keywords and snippets (see Input): a few rows under the caret, Tab inserts. The same switch as Suggestions in the input menu; an app can turn them off in Apps."))
            }
            HStack {
                Text(tr("选过的行下次排在前面，只存在这台 Mac 上。", "Rows you pick come first next time; they're kept on this Mac only."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(tr("忘掉选过的行（\(picked)）", "Forget Picked Rows (\(picked))")) {
                    guard model.store.persists else { return }
                    SuggestionsShared.picks.clear()
                    picked = 0
                }
                .disabled(picked == 0)
            }
        } header: {
            SectionTitle(tr("建议", "Suggestions"), icon: SettingsPage.general.icon)
        }
        .disabled(!model.canSave)
        .onAppear { picked = SuggestionsShared.picks.all.count }
    }

    /// A row's title with a short explanation under it, as the other pages show them.
    private func titled(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
