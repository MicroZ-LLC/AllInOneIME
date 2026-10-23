import AllInOneIMECore
import SwiftUI

/// Settings → Coding Languages (spec suggestions v1, 2 and 3): Suggestions' switch (the input menu's) and the rows picked;
/// coding mode, how it is turned on and whether it is on now; the coding packs installed, each removable; and those the
/// language library offers, fetched only when asked (no network before). Apart from the input languages' packs
/// (Settings → Input): coding languages are never shown with human languages.
struct CodingLanguagesPage: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var packs = CodingPackManager.shared
    /// Coding mode as it is now (the chooser a long press of Shift opens turns it on and off), read again as it changes.
    @State private var codingMode = SuggestionsShared.codingMode
    /// How many rows picked are kept (rows picked before come first).
    @State private var picked = 0
    /// The pack about to be deleted (asked first).
    @State private var packToDelete: CodingLanguagePack?

    var body: some View {
        suggestionsSection
            .onAppear {
                packs.reload()
                codingMode = SuggestionsShared.codingMode
                picked = SuggestionsShared.picks.all.count
            }
            .onReceive(NotificationCenter.default.publisher(for: .allInOneIMESuggestionsChanged)) { _ in
                codingMode = SuggestionsShared.codingMode
                packs.reload()
            }
        codingModeSection
        installedSection
        librarySection
    }

    /// Suggestions on or off everywhere (an app's own choice is in Apps), and forgetting the rows picked.
    @ViewBuilder private var suggestionsSection: some View {
        Section {
            Toggle(isOn: Binding(get: { model.config.suggestions != false }, set: { model.setSuggestions($0) })) {
                titled(tr("建议", "Suggestions"),
                       tr("插件的补全（比如打 #12 列出 GitHub issue）和编码模式的关键字、代码片段：光标下面列出几行，按 Tab 插入。和输入法菜单里的「建议」是同一个开关；每个插件的补全在「插件」里打开，某个 App 里不要可以在「按 App 设置」里关掉。",
                          "Plugins' completions (#12 lists GitHub issues, say) and coding mode's keywords and snippets: a few rows under the caret, Tab inserts. The same switch as Suggestions in the input menu; each plugin's completions are turned on in Plugins, and an app can turn them off in Apps."))
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
            SectionTitle(tr("建议", "Suggestions"), icon: SettingsPage.codingLanguages.icon)
        }
        .disabled(!model.canSave)
    }

    /// What coding mode does, how it is turned on and off, and whether it is on now.
    @ViewBuilder private var codingModeSection: some View {
        Section {
            Text(tr("在输入框里按住 Shift 一秒，光标处会弹出一个小菜单：按 2 选「编码模式」（或用 ↑↓ 选中按 ⏎）。打开后菜单栏图标会显示它，在所有 App 里一直开着，直到再选一次关掉。开着时每个输入框从英文开始（按 Shift 照样切换），光标下面列出下面这些语言包的关键字、代码片段和输入框里已有的词，按 Tab 补全。它和边打边译不能同时开。",
                    "Hold Shift for a second in a text field and a small chooser opens at the caret: press 2 for Coding mode (or pick it with ↑↓ and ⏎). The menu bar icon shows it while it's on, in every app, until you choose it again. Each text field then starts in English (Shift still switches), and the rows under the caret offer the keywords and snippets of the packs below and words already in the field: Tab completes. It and Translate as You Type are never on together."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Label(codingMode ? tr("编码模式现在开着：按住 Shift 一秒，再选一次「编码模式」就关掉。",
                                  "Coding mode is on now: hold Shift for a second and choose Coding mode again to turn it off.")
                             : tr("编码模式现在关着。", "Coding mode is off now."),
                  systemImage: codingMode ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(codingMode ? .primary : .secondary)
            if model.config.suggestions == false {
                Label(tr("建议关着，编码模式也不会列出什么：在上面打开。", "Suggestions are off, so coding mode shows no rows: turn them on above."),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        } header: {
            SectionTitle(tr("编码模式", "Coding Mode"), icon: SettingsPage.codingLanguages.icon)
        }
    }

    /// The packs installed: each with its version and what it holds, and Delete….
    @ViewBuilder private var installedSection: some View {
        Section {
            Text(tr("开着编码模式时，所有装好的语言包都会用上（输入框分不出是哪种语言）。",
                    "While coding mode is on, every pack installed is used (a text field can't tell which language it's in)."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                // On a row that is always there (a Form section's own dialog is not shown).
                .confirmationDialog(packToDelete.map { tr("删除 \($0.title) 编程语言包？", "Delete the \($0.title) coding pack?") } ?? "",
                                    isPresented: Binding(get: { packToDelete != nil }, set: { if !$0 { packToDelete = nil } })) {
                    Button(tr("删除", "Delete"), role: .destructive) {
                        if let pack = packToDelete { packs.remove(pack.language) }
                        packToDelete = nil
                    }
                    Button(tr("取消", "Cancel"), role: .cancel) { packToDelete = nil }
                } message: {
                    Text(tr("它的关键字和代码片段不再出现；以后可以从下面的语言库再下载。",
                            "Its keywords and snippets no longer show; you can download it again from the library below."))
                }
            ForEach(packs.installed, id: \.language) { pack in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: "curlybraces").foregroundStyle(.secondary).frame(width: 20)
                        Text(pack.title).fontWeight(.medium)
                        Text(tr("\(pack.version) · \(pack.keywords.count) 个关键字 · \(pack.snippets.count) 个代码片段",
                                "\(pack.version) · \(pack.keywords.count) keywords · \(pack.snippets.count) snippets"))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(tr("删除…", "Delete…")) { packToDelete = pack }
                    }
                    if case let .failed(message) = packs.states[pack.language] {
                        Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                            .padding(.leading, 28)
                    }
                }
            }
            if packs.installed.isEmpty {
                Text(tr("还没有编程语言包：开着编码模式时只列出输入框里已有的词。在下面的语言库里下载。",
                        "No coding packs yet: coding mode offers only words already in the field. Download one from the library below."))
                    .foregroundStyle(.secondary)
            }
        } header: {
            SectionTitle(tr("已安装的编程语言", "Installed Coding Languages"), icon: SettingsPage.codingLanguages.icon)
        }
    }

    /// The language library's coding packs: a button until asked (no network before), then each with Download, its
    /// progress and Cancel, Update, or Installed.
    @ViewBuilder private var librarySection: some View {
        let host = LanguagePackLibrary.defaultBaseURL.host ?? "languages.allinoneime.com"
        Section {
            if let offered = packs.offered {
                HStack {
                    Text(tr("可下载", "Available")).font(.headline)
                    Spacer()
                    if packs.fetching { ProgressView().controlSize(.small) }
                    Button(tr("刷新", "Refresh")) { packs.fetch() }.disabled(packs.fetching)
                }
                ForEach(offered, id: \.language) { entry in libraryRow(entry) }
                if offered.isEmpty {
                    Text(tr("语言库里暂时没有这个版本能用的编程语言包。", "The library has no coding packs for this version yet."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Button(tr("显示可下载的语言包…", "Show Available Packs…")) { packs.fetch() }.disabled(packs.fetching)
                    if packs.fetching { ProgressView().controlSize(.small) }
                }
            }
            if let error = packs.offerError {
                Label(tr("没能取得语言库的列表：", "Couldn't get the library's list: ") + error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text(tr("语言包来自语言库，下载后逐个核对签名的索引；只有你点了才会联网（\(host)）。",
                    "Packs come from the language library, each checked against its signed index; it's fetched only when you ask (\(host))."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionTitle(tr("编程语言库", "Coding Language Library"), icon: SettingsPage.codingLanguages.icon)
        }
    }

    /// A pack on offer: its title, version and size, and what can be done with it now; a failed download says why.
    private func libraryRow(_ entry: CodingPackIndex.Entry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "curlybraces").foregroundStyle(.secondary).frame(width: 20)
                Text(entry.title).fontWeight(.medium)
                Text("\(entry.version) · \(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                libraryButton(entry)
            }
            if case let .failed(message) = packs.states[entry.language] {
                Label(tr("没有下载成功：", "Didn't download: ") + message, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).padding(.leading, 28)
            }
        }
    }

    @ViewBuilder private func libraryButton(_ entry: CodingPackIndex.Entry) -> some View {
        switch packs.states[entry.language] ?? .idle {
        case let .downloading(share):
            HStack(spacing: 8) {
                ProgressView(value: share).frame(width: 100)
                Text("\(Int(share * 100))%").monospacedDigit().foregroundStyle(.secondary)
                Button(tr("取消", "Cancel")) { packs.cancel(entry.language) }
            }
        case .failed:
            Button(tr("重试", "Retry")) { packs.download(entry) }
        case .idle:
            if let installed = packs.installed.first(where: { $0.language == entry.language }) {
                if SemVer.compare(entry.version, installed.version) > 0 {
                    Button(tr("更新（当前 \(installed.version)）", "Update (from \(installed.version))")) { packs.download(entry) }
                } else {
                    Text(tr("已安装", "Installed")).foregroundStyle(.secondary)
                }
            } else {
                Button(tr("下载", "Download")) { packs.download(entry) }
            }
        }
    }

    /// A row's title with a short explanation under it, as the other pages show them.
    private func titled(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
