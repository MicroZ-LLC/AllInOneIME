import AllInOneIMECore
import SwiftUI

/// The settings window's pages as #120 lays them out (owner, 0.7.5): Common first, with the ten rows most people need
/// and a field to say what to change; More Settings, an index of five groups, each opening as a short page of its own
/// with a back button. Only where a row is shown changed: every row keeps its config key and behaviour.
extension SettingsView {
    /// The page shown's sections (`page`).
    @ViewBuilder var pageContent: some View {
        switch page {
        case .week: EmptyView()  // `WeekStatsPage`, drawn instead of the form
        case .common:
            CommonRequestSection(assistant: assistant)
            // The input languages and how they're typed, then the commands and the features most people use.
            inputSection
            Section {
                magicKeyRow
                outputLanguagesRow
            } header: {
                SectionTitle(tr("命令与功能", "Commands and features"), icon: CommandIcons.commands)
            }
            .disabled(!model.canSave)
            ClipboardHistorySection(model: model, titled: false)
            autocompleteSection
            Section {} footer: {
                Text(Self.moreFooter(SettingsPage.more.shownCount(model.config)))
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
        case .ai:
            // Who answers, then what the AI commands do, then the model's parameters (owner, 0.7.5).
            providerSection
            aiCommandsSection
            requestSection
        case .commands:
            commandsSection
            AgentSettingsPage(model: model)
            notesSection
            pluginsSection
            extensionsSection
            // The plugins' folder, the extensions' folders and the extension sources, folded (owner, 0.7.4).
            ExtensionSourcesSection(model: model, disclosure: $foldersAndSources, folders: AnyView(extensionFolderRows))
        case .more:
            MoreSettingsIndex(config: model.config, issues: assistant.issues.map(\.element)) { page = $0 }
        case .about: aboutSection
        case .inputAndKeys, .suggestions, .privacy, .interface, .advanced:
            GroupTitle(group: page) { page = .more }
            groupContent
        }
    }

    /// A group of More Settings: its rows, in the sections they had on the pages they came from.
    @ViewBuilder private var groupContent: some View {
        switch page {
        case .inputAndKeys:
            // Each input's options under its name (Chinese's fuzzy pinyin, dictionaries and removed candidates, the
            // English words, Code's language), then the action key.
            ForEach(model.config.inputs, id: \.self) { input in inputOptions(input) }
            Section { actionKeyRow }.disabled(!model.canSave)
        case .suggestions:
            SuggestionsSection(model: model)
        case .privacy:
            PrivacySection(model: model)
        case .interface:
            appearanceSection
            ICloudSyncSection(model: model)
        case .advanced:
            typeOutSection
            typingSection
            // Only while an app has one; migration from before Settings v2 (owner, 0.7.4: from General).
            PreviousAppSettingsSection(model: model)
            filesSection
        default: EmptyView()
        }
    }

    /// Common's last line: how many rows More Settings has, and that saying what to change works too.
    static func moreFooter(_ count: Int) -> String {
        tr("不常改的 \(count) 项在更多设置里，分成 \(SettingsPage.groups.count) 组；不想找，就在上面直接说。",
           "\(count) settings you rarely change are in More Settings, in \(SettingsPage.groups.count) groups; or just say what to change above.")
    }
}

/// Common's first row: what to change, said in a sentence. Return asks the AI as the search's last row ("Change: …")
/// does, through the same code (`AssistantModel.sendRequest`): the preview comes at the top of the page, with Apply and
/// Undo. Nothing is sent before Return.
struct CommonRequestSection: View {
    @ObservedObject var assistant: AssistantModel
    @State private var text = ""

    var body: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("", text: $text,
                          prompt: Text(tr("想改什么，直接说，例如：翻译成英文和日文，候选竖排",
                                          "Say what to change, e.g. translate into English and Japanese, candidates in a column")))
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onSubmit(send)
                    .accessibilityLabel(tr("想改什么，直接说", "Say what to change"))
            }
            .padding(.vertical, 2)
        }
    }

    private func send() {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        assistant.request = typed
        assistant.sendRequest()
        text = ""
    }
}

/// A group's title, with the back button to More Settings on its left.
struct GroupTitle: View {
    let group: SettingsPage
    let back: () -> Void

    var body: some View {
        Section {} header: {
            HStack(spacing: 8) {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help(SettingsPage.more.title)
                .accessibilityLabel(tr("返回更多设置", "Back to More Settings"))
                IconTile(icon: group.icon, size: 22)
                Text(group.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary)
                Spacer()
            }
            .padding(.top, 4)
        }
    }
}

/// More Settings: a row per group, with its icon, its name, the rows inside, how many are shown and ›; a click opens
/// the group. A dot as the sidebar has, for what the checks found wrong in a group.
struct MoreSettingsIndex: View {
    let config: Config
    let issues: [Doctor.Finding]
    let open: (SettingsPage) -> Void

    var body: some View {
        Section {
            ForEach(SettingsPage.groups) { group in
                let shown = group.spots.filter { $0.isShown(config) }
                let worst = issues.filter { SettingsPage.of($0.area) == group }.map(\.status).min()
                Button { open(group) } label: {
                    HStack(spacing: 10) {
                        IconTile(icon: group.icon, size: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title).foregroundStyle(.primary)
                            Text(shown.map(\.title).joined(separator: tr("、", ", ")))
                                .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                        }
                        Spacer(minLength: 8)
                        if let worst {
                            Circle().fill(TroubleshootSheet.color(worst)).frame(width: 8, height: 8).accessibilityHidden(true)
                        }
                        Text("\(shown.count)").foregroundStyle(.secondary).monospacedDigit()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(group.title + tr("：", ": ") + tr("\(shown.count) 项", "\(shown.count) settings"))
            }
        } header: {
            SectionTitle(SettingsPage.more.title, icon: SettingsPage.more.icon)
        }
    }
}
