import AllInOneIMECore
import SwiftUI

/// Code in Settings → Input (decision 22): an input after the languages, a kind of its own, never among them. Its row in
/// the list (`CodeInputRow`): the coding language, picked from the library's (one whose pack isn't installed downloads it
/// first, as adding an input language downloads its pack), and Remove; the coding packs installed, each removable, and
/// those the library offers, fetched only when asked (`CodingPacksSections`).
@MainActor
enum CodeInputSettings {
    /// Code's mark, as the menu bar icon has it.
    static let icon = CandidateView.Icon(symbol: "curlybraces", color: .systemGreen)

    /// `language` picked as Code's (the + menu, Code's menu): Code's at once where its pack is installed, else once the
    /// pack has downloaded (`CodingPackManager.pick`).
    static func pick(_ language: String, model: SettingsModel) {
        CodingPackManager.shared.pick(language) { language in
            model.config.codingLanguage = language
            model.save()  // the window may be closed by now
        }
    }

    /// The coding languages Code's menu offers: the library's, and one an installed pack or the settings name besides.
    static func languages(_ config: Config, installed: [CodingLanguagePack]) -> [(language: String, title: String)] {
        var all = CodingLanguagePack.offered
        for language in installed.map(\.language) + [config.codingLanguage].compactMap({ $0 }) where !all.contains(where: { $0.language == language }) {
            all.append((language, CodingLanguagePack.title(of: language, installed: installed)))
        }
        return all
    }

    /// What Code does, under its name: short, so its menu stays on its line.
    static var summary: String {
        tr("在输入语言后面，单按 Shift 切到它：列出这种编程语言的关键字和代码片段",
           "After the languages, a tap of Shift away: rows of this language's keywords and snippets")
    }
}

/// Settings → Input's Code row, after the input languages: its coding language and Remove (once Code is added, with + or
/// from the input menu); the pack of a language picked for it while it downloads (with Cancel), or why it didn't (with
/// Retry).
struct CodeInputRow: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var packs = CodingPackManager.shared

    var body: some View {
        if let language = model.config.codingLanguage {
            LabeledContent {
                HStack(spacing: 8) {
                    Picker("", selection: Binding(get: { language }, set: { CodeInputSettings.pick($0, model: model) })) {
                        ForEach(CodeInputSettings.languages(model.config, installed: packs.installed), id: \.language) { offered in
                            Text(offered.title + (packs.installed.contains { $0.language == offered.language }
                                                  ? "" : tr("（下载语言包）", " (downloads a language pack)")))
                                .tag(offered.language)
                        }
                    }
                    .pickerStyle(.menu).labelsHidden().fixedSize()
                    Button(tr("移除", "Remove"), role: .destructive) { model.config.codingLanguage = nil }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label(tr("代码", "Code"), systemImage: "curlybraces")
                    Text(CodeInputSettings.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !packs.installed.contains(where: { $0.language == language }), !packs.isDownloading(language) {
                        Label(tr("\(CodingLanguagePack.title(of: language)) 的语言包还没安装：装好以后才能切到代码。",
                                 "The \(CodingLanguagePack.title(of: language)) pack isn't installed: Code can be typed once it is."),
                              systemImage: "arrow.down.circle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if model.config.suggestions == false {
                        Label(tr("建议关着，代码输入不会列出什么：在「通用」里打开。", "Suggestions are off, so Code shows no rows: turn them on in General."),
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
        if let picked = packs.picked { pickedPack(picked) }
    }

    /// The pack of the language picked for Code: its download going on (with Cancel), or its failure (with Retry); nothing
    /// otherwise.
    @ViewBuilder private func pickedPack(_ language: String) -> some View {
        let title = CodingLanguagePack.title(of: language)
        switch packs.states[language] ?? .idle {
        case let .downloading(share):
            LabeledContent {
                HStack(spacing: 8) {
                    ProgressView(value: share).frame(width: 140)
                    Text("\(Int(share * 100))%").monospacedDigit().foregroundStyle(.secondary)
                    Button(tr("取消", "Cancel")) { packs.cancel(language) }
                }
            } label: {
                titled(tr("正在下载 \(title) 编程语言包", "Downloading the \(title) coding pack"),
                       tr("下载完就切到代码（\(title)），不用重启", "Code is in \(title) once it's done, no restart"))
            }
        case let .failed(message):
            LabeledContent {
                Button(tr("重试", "Retry")) { CodeInputSettings.pick(language, model: model) }
            } label: {
                titled(tr("\(title) 编程语言包没有下载成功", "The \(title) coding pack didn't download"), message)
            }
        case .idle:
            EmptyView()
        }
    }

    private func titled(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Settings → Input's coding packs (spec suggestions v1, 3; decision 22): those installed, each with its version and
/// what it holds, and Delete… (the pack of Code's language takes Code with it); and those the language library offers,
/// fetched only when asked (no network before), each with Download, its progress and Cancel, Update, or Installed.
struct CodingPacksSections: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var packs = CodingPackManager.shared
    /// The pack about to be deleted (asked first).
    @State private var packToDelete: CodingLanguagePack?

    var body: some View {
        installedSection
            .onAppear { packs.reload() }
            .onReceive(NotificationCenter.default.publisher(for: .allInOneIMESuggestionsChanged)) { _ in packs.reload() }
        librarySection
    }

    /// The packs installed: each with its version and what it holds, and Delete….
    @ViewBuilder private var installedSection: some View {
        Section {
            Text(tr("代码输入只用上面选的那种编程语言的包；其他的留着，换成它们时就能用。",
                    "Code uses the pack of the language picked for it above; the others stay installed for when you pick theirs."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                // On a row that is always there (a Form section's own dialog is not shown).
                .confirmationDialog(packToDelete.map { tr("删除 \($0.title) 编程语言包？", "Delete the \($0.title) coding pack?") } ?? "",
                                    isPresented: Binding(get: { packToDelete != nil }, set: { if !$0 { packToDelete = nil } })) {
                    Button(tr("删除", "Delete"), role: .destructive) {
                        if let pack = packToDelete { delete(pack) }
                        packToDelete = nil
                    }
                    Button(tr("取消", "Cancel"), role: .cancel) { packToDelete = nil }
                } message: {
                    if packToDelete?.language == model.config.codingLanguage {
                        Text(tr("代码输入也会移除。以后可以从下面的语言库再下载。", "Code is removed from your inputs too. You can download it again from the library below."))
                    } else {
                        Text(tr("它的关键字和代码片段不再出现；以后可以从下面的语言库再下载。",
                                "Its keywords and snippets no longer show; you can download it again from the library below."))
                    }
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
                Text(tr("还没有编程语言包：给代码输入选一种语言就会下载，也可以从下面的语言库里下载。",
                        "No coding packs yet: picking a language for Code downloads its pack, or download one from the library below."))
                    .foregroundStyle(.secondary)
            }
        } header: {
            SectionTitle(tr("已安装的编程语言", "Installed Coding Languages"), icon: CodeInputSettings.icon)
        }
        .disabled(!model.canSave)
    }

    /// Deletes `pack`; Code goes with the pack of its language (as an input language goes with its pack).
    private func delete(_ pack: CodingLanguagePack) {
        if model.config.codingLanguage == pack.language { model.config.codingLanguage = nil }
        packs.remove(pack.language)
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
            SectionTitle(tr("编程语言库", "Coding Language Library"), icon: CodeInputSettings.icon)
        }
        .disabled(!model.canSave)
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
}
