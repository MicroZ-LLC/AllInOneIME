import AllInOneIMECore
import SwiftUI

/// Settings → General → Suggestions (spec suggestions v1, 3): their switch, the input menu's, for plugins' completions
/// and Code's rows alike; what a row inserts (decision 28; Settings v2, 4): everywhere, then in the apps with their own
/// choice; and forgetting the rows picked.
struct SuggestionsSection: View {
    @ObservedObject var model: SettingsModel
    /// How many rows picked are kept (rows picked before come first).
    @State private var picked = 0

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { model.config.suggestions != false }, set: { model.setSuggestions($0) })) {
                titled(.suggestions)
            }
            .settingsRow(.suggestions, shown: model.spot)
            // What a suggestion row inserts, for every source: everywhere, then the apps with their own.
            SuggestionsInsertPicker(model: model)
                .settingsRow(.suggestionsInsert, shown: model.spot)
            AppInsertsList(model: model)
            HStack {
                Text(tr("选过的行下次排在前面，只存在这台 Mac 上。", "Rows you pick come first next time; they're kept on this Mac only."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(tr("忘掉选过的行（\(picked)）", "Forget Picked Rows (\(picked))")) {
                    guard model.store.persists else { return }
                    LearnedShared.store.forget(LearnedItem(kind: .pickedRows(count: picked)))
                    picked = 0
                }
                .disabled(picked == 0)
            }
        } header: {
            SectionTitle(tr("建议", "Suggestions"), icon: SettingsPage.general.icon)
        }
        .disabled(!model.canSave)
        .onAppear { picked = LearnedShared.store.picks.count }
    }

    /// A row's title with a short explanation under it, as the other pages show them.
    @ViewBuilder private func titled(_ spot: SettingsSpot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(spot.title)
            if let note = spot.note {
                Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// What a suggestion row inserts everywhere (decision 28), under the Suggestions switch: the source's own (a plugin's
/// `insert`, a custom command's Insert) until another is chosen, with title, or with title and link; for every source,
/// plugins' and custom commands', never Code's. "ID only" can't be chosen any more (Settings v2, 4): a config that has it,
/// or the source's own written out, shows it on its own row with Restore Default.
struct SuggestionsInsertPicker: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        if let kept = model.config.suggestionsInsert, !SuggestionsInsert.offered.contains(kept) {
            RestoreDefaultRow(title: SettingsSpot.suggestionsInsert.title + tr("：", ": ") + kept.label,
                              note: SuggestionsInsert.notOffered) { model.setSuggestionsInsert(nil) }
        } else {
            Picker(selection: Binding(get: { model.config.suggestionsInsert }, set: { model.setSuggestionsInsert($0) })) {
                Text(tr("默认", "Default")).tag(SuggestionsInsert?.none)
                ForEach(SuggestionsInsert.offered, id: \.self) { insert in Text(insert.label).tag(SuggestionsInsert?.some(insert)) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SettingsSpot.suggestionsInsert.title)
                    Text(SuggestionsInsert.help).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

extension SuggestionsInsert {
    /// What Settings and the input menu offer (Settings v2, 4): with title, with title and link. The source's own is the
    /// default (none chosen); "ID only" is still honored where a config has it.
    static let offered: [SuggestionsInsert] = [.title, .titleAndLink]

    /// Under a choice that isn't offered any more, kept in a config.
    static var notOffered: String {
        tr("现在不能再选它了；默认用插件或命令自己定的。", "It can't be chosen any more; by default each plugin or command says what goes in.")
    }
}

/// "In these apps": each app with its own choice of what a suggestion row inserts (`AppProfile.suggestionsInsert`), its
/// picker and Remove (the app's other settings untouched), and Add App….
struct AppInsertsList: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let apps = model.appsWith { $0.suggestionsInsert != nil }
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SettingsSpot.appInserts.title)
                    Text(SettingsSpot.appInserts.note ?? "").font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                AddAppMenu(model: model, has: { $0.suggestionsInsert != nil }) { app in
                    model.changeProfile(app) { $0.suggestionsInsert = AppInsertsList.added(everywhere: model.config.suggestionsInsert) }
                }
            }
            ForEach(apps, id: \.self) { app in row(app) }
        }
        .settingsRow(.appInserts, shown: model.spot)
    }

    /// What an app added here inserts: the other one of the two offered than everywhere's (what adding it is for).
    static func added(everywhere: SuggestionsInsert?) -> SuggestionsInsert {
        everywhere == .titleAndLink ? .title : .titleAndLink
    }

    private func row(_ app: String) -> some View {
        let own = model.config.profile(for: app)?.suggestionsInsert
        return HStack {
            AppLabel(app: app)
            Spacer()
            if let own, !SuggestionsInsert.offered.contains(own) {
                // "ID only", or the source's own written out: shown as it is, until Restore Default.
                Text(own.label).foregroundStyle(.secondary).help(SuggestionsInsert.notOffered)
                Button(tr("恢复默认", "Restore Default")) { model.changeProfile(app) { $0.suggestionsInsert = nil } }
            } else {
                Picker("", selection: Binding(get: { own ?? .title }, set: { insert in model.changeProfile(app) { $0.suggestionsInsert = insert } })) {
                    ForEach(SuggestionsInsert.offered, id: \.self) { insert in Text(insert.label).tag(insert) }
                }
                .labelsHidden().fixedSize()
                Button(tr("移除", "Remove")) { model.changeProfile(app) { $0.suggestionsInsert = nil } }
            }
        }
        .padding(.leading, 4)
    }
}
