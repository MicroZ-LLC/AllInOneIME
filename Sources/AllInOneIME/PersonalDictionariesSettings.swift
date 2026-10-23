import AllInOneIMECore
import AllInOneIMERime
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The local vocabulary files, separate from settings and iCloud. File reading and parsing run on
/// a worker task; only the Rime lifecycle calls and the state shown in Settings use the main actor.
@MainActor
final class PersonalDictionariesModel: ObservableObject {
    @Published private(set) var dictionaries: [PersonalDictionary] = []
    @Published private(set) var isWorking = false
    @Published private(set) var status: String?
    @Published private(set) var error: String?

    private let userDirectory: URL
    private let schemaURL: @MainActor () -> URL?
    private var revision = 0

    init(userDirectory: URL = RimeDirectories.user,
         schema: @escaping @MainActor () -> URL? = { RimeDirectories.shared?.appendingPathComponent("rime_ice.schema.yaml") }) {
        self.userDirectory = userDirectory
        schemaURL = schema
    }

    var hasChinesePack: Bool { schemaURL() != nil }

    func refresh() async {
        guard !isWorking else { return }
        let store = dictionaryStore()
        let revision = self.revision
        do {
            let saved = try await Task.detached(priority: .utility) { try store.list() }.value
            guard revision == self.revision, !isWorking else { return }
            dictionaries = saved
            error = nil
        } catch {
            if revision == self.revision, !isWorking { self.error = error.localizedDescription }
        }
    }

    func chooseDictionary(fuzzyPinyin: [String]) {
        guard !isWorking, hasChinesePack else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "yaml") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = tr("选择一个直接包含词条和拼音编码的 UTF-8 Rime .dict.yaml 文件；再次导入相同 name 会更新已存的副本。",
                           "Choose a UTF-8 Rime .dict.yaml containing its own entries and pinyin codes. Import the same name again to update its saved copy.")
        guard panel.runModal() == .OK, let source = panel.url else { return }
        Task { await importDictionary(from: source, fuzzyPinyin: fuzzyPinyin) }
    }

    func importDictionary(from source: URL, fuzzyPinyin: [String]) async {
        guard !isWorking, hasChinesePack else { return }
        let store = dictionaryStore()
        await change(store: store) {
            _ = try store.importDictionary(from: source, fuzzyPinyin: fuzzyPinyin)
            return try store.list()
        }
    }

    func removeDictionary(named name: String, fuzzyPinyin: [String]) async {
        guard !isWorking, hasChinesePack else { return }
        let store = dictionaryStore()
        await change(store: store) {
            try store.removeDictionary(named: name, fuzzyPinyin: fuzzyPinyin)
            return try store.list()
        }
    }

    private func dictionaryStore() -> PersonalDictionaryStore {
        PersonalDictionaryStore(userDirectory: userDirectory,
                                schema: schemaURL() ?? userDirectory.appendingPathComponent("rime_ice.schema.yaml"))
    }

    private func change(store: PersonalDictionaryStore, _ operation: @escaping @Sendable () throws -> [PersonalDictionary]) async {
        revision += 1
        isWorking = true
        error = nil
        status = tr("正在保存词库…", "Saving dictionaries…")
        defer { isWorking = false }
        do {
            dictionaries = try await Task.detached(priority: .utility, operation: operation).value
        } catch {
            self.error = error.localizedDescription
            status = nil
            return
        }

        // A settings or iCloud change during parsing may have changed fuzzy pinyin. Reconcile the
        // latest saved choice before deployment, using the same writer that preserves these imports.
        let currentFuzzy = LiveConfig.current.fuzzyPinyin
        do {
            let outcome = try await Task.detached(priority: .utility) { try store.applyFuzzyPinyin(currentFuzzy) }.value
            if outcome == .userFile { throw PersonalDictionaryError.managedFile(FuzzyPinyin.fileName) }
        } catch {
            self.error = error.localizedDescription
            status = nil
            return
        }
        status = tr("正在重新部署词库…", "Redeploying dictionaries…")
        if RimeService.shared.isStarted { RimeService.shared.redeploy(invalidateGeneratedSchema: true) }
        else { RimeStartup.start() }
        let deadline = Date().addingTimeInterval(120)
        while !RimeService.shared.isReady, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        if !RimeService.shared.isReady {
            error = tr("词库副本已保存在这台 Mac 上，部署仍在等待或进行。稍后可从输入法菜单选择「重新部署词库」。",
                       "The dictionary copy is saved on this Mac; deployment is still pending or running. You can choose Redeploy Dictionaries from the input menu later.")
            status = nil
        } else if RimeService.shared.deploymentStatus == .failed {
            error = tr("词库副本已保存在这台 Mac 上，但 Rime 部署失败。请查看 Rime 日志，处理后从输入法菜单选择「重新部署词库」。",
                       "The dictionary copy is saved on this Mac, but Rime deployment failed. Check the Rime logs, then choose Redeploy Dictionaries from the input menu.")
            if let detail = RimeService.shared.deploymentError { error! += "\n" + detail }
            status = nil
        } else {
            status = RimeService.shared.deploymentStatus == .succeeded
                ? tr("词库已重新部署，可以使用了。", "Dictionaries redeployed and ready to use.")
                : tr("词库副本已保存在这台 Mac 上。", "Dictionary copies saved on this Mac.")
        }
    }
}

struct PersonalDictionariesSection: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var dictionaries: PersonalDictionariesModel

    var body: some View {
        Section {
            LabeledContent {
                Button(tr("导入或更新…", "Import or Update…")) {
                    dictionaries.chooseDictionary(fuzzyPinyin: model.config.fuzzyPinyin)
                }
                .disabled(dictionaries.isWorking || !dictionaries.hasChinesePack)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("添加你的拼音词库", "Add your pinyin vocabulary"))
                    Text(tr("UTF-8 Rime .dict.yaml，最多 32 MiB", "UTF-8 Rime .dict.yaml, up to 32 MiB"))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if !dictionaries.hasChinesePack {
                Text(tr("先添加中文（拼音）并下载语言包。", "Add Chinese (pinyin) and download its language pack first."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            if dictionaries.dictionaries.isEmpty {
                Text(tr("还没有个人词库", "No personal dictionaries yet")).foregroundStyle(.secondary)
            }
            ForEach(dictionaries.dictionaries) { dictionary in
                LabeledContent {
                    Button(tr("移除", "Remove"), role: .destructive) {
                        Task { await dictionaries.removeDictionary(named: dictionary.name, fuzzyPinyin: model.config.fuzzyPinyin) }
                    }
                    .disabled(dictionaries.isWorking || !dictionaries.hasChinesePack)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dictionary.name)
                        Text(tr("\(dictionary.fileName) · \(dictionary.entryCount) 条", "\(dictionary.fileName) · \(dictionary.entryCount) entries"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            if let status = dictionaries.status {
                HStack(spacing: 8) {
                    if dictionaries.isWorking { ProgressView().controlSize(.small) }
                    Text(status).font(.callout).foregroundStyle(.secondary)
                }
            }
            if let error = dictionaries.error {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                HStack {
                    Button(tr("打开 Rime 用户目录", "Open Rime User Folder")) { NSWorkspace.shared.open(RimeDirectories.user) }
                    Button(tr("打开 Rime 日志", "Open Rime Logs")) { NSWorkspace.shared.open(RimeDirectories.logs) }
                }
            }
        } header: {
            SectionTitle(tr("个人词库", "Personal Dictionaries"), icon: CandidateView.Icon(symbol: "character.book.closed", color: .systemTeal))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("补充自带词库；文件需直接包含文字、拼音编码和可选的数字权重，不支持依赖其他词库。再次导入相同 name 会更新副本；只修改原文件不会自动更新。副本只留在这台 Mac 上，不通过 iCloud 同步或发给 AI。移除后已学到的词会保留。",
                        "Supplements the built-in vocabulary. Files must contain their own text, pinyin codes and optional numeric weights, without other dictionary dependencies. Import the same name again to update its copy; editing the source alone doesn't update it. Copies stay on this Mac, outside iCloud sync and AI context. Learned words are kept when you remove a dictionary."))
                // What is picked is learned into rime_ice's user dictionary, which RimeSync syncs.
                Text(tr("从词库里选过的词和别的词一样会学进拼音学到的词；开了「通过 iCloud 同步」的「学到的词」时，会同步到你的其他 Mac。",
                        "A word you pick from one is learned like any other, into pinyin's learned words, which sync to your other Macs when Sync through iCloud has Learned words on."))
                // The wrapper takes in all of rime-ice's words: each change compiles them again.
                Text(tr("每次导入、更新或移除都会重新编译拼音词库（雾凇拼音的全部词条加上你的），可能要一分钟左右；这期间暂时打不了中文。",
                        "Each import, update or removal compiles pinyin's dictionary again (all of rime-ice's words with yours), which can take a minute or so; Chinese input pauses until it's done."))
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(!model.canSave || !model.store.persists)
        .task { if model.store.persists { await dictionaries.refresh() } }
    }
}
