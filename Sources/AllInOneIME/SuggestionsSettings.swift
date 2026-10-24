import AllInOneIMECore
import SwiftUI

/// Settings → General → Suggestions (spec suggestions v1, 3): their switch, the input menu's, for plugins' completions
/// and Code's rows alike; what a row inserts (decision 28; Settings v2, 4): everywhere, then in the apps with their own
/// choice. The rows picked (picked before, they come first) are in Privacy → Learned….
struct SuggestionsSection: View {
    @ObservedObject var model: SettingsModel

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
        } header: {
            SectionTitle(tr("建议", "Suggestions"), icon: SettingsPage.general.icon)
        }
        .disabled(!model.canSave)
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

/// "In these apps": each app with its own choice (`AppProfile.insertChoice`), what a suggestion row inserts there or Off
/// (no suggestions there), its picker and Remove (the app's other settings untouched), and Add App….
struct AppInsertsList: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let apps = model.appInsertApps
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(SettingsSpot.appInserts.title)
                    Text(SettingsSpot.appInserts.note ?? "").font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                AddAppMenu(model: model, has: { $0.insertChoice != nil }) { app in
                    model.setInsertChoice(.insert(AppInsertsList.added(everywhere: model.config.suggestionsInsert)), for: app)
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
        let own = model.config.profile(for: app)?.insertChoice
        return HStack {
            AppLabel(app: app)
            Spacer()
            if let own, !AppInsertChoice.offered.contains(own) {
                // "ID only", or the source's own written out: shown as it is, until Restore Default.
                Text(own.label).foregroundStyle(.secondary).help(SuggestionsInsert.notOffered)
                Button(tr("恢复默认", "Restore Default")) { model.setInsertChoice(nil, for: app) }
            } else {
                Picker("", selection: Binding(get: { own ?? .insert(.title) }, set: { model.setInsertChoice($0, for: app) })) {
                    ForEach(AppInsertChoice.offered, id: \.self) { choice in Text(choice.label).tag(choice) }
                }
                .labelsHidden().fixedSize()
                Button(tr("移除", "Remove")) { model.setInsertChoice(nil, for: app) }
            }
        }
        .padding(.leading, 4)
    }
}

extension SettingsModel {
    /// "In these apps": the apps with a choice of their own (`AppProfile.insertChoice`: an insert, or Off with none), by
    /// name.
    var appInsertApps: [String] { appsWith { $0.insertChoice != nil } }

    /// An app's choice in "In these apps", saved: an insert (its suggestions as everywhere), Off (what its rows insert
    /// kept), nil (Remove, Restore Default: both cleared). Its other settings untouched.
    func setInsertChoice(_ choice: AppInsertChoice?, for app: String) {
        changeProfile(app) { $0.insertChoice = choice }
    }
}
