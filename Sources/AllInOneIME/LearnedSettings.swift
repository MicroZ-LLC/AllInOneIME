import AllInOneIMECore
import Foundation
import SwiftUI

/// Privacy → Learned…, the row: what this Mac learned (Settings v2, 3.2), how many things, and the list in a sheet.
struct LearnedRow: View {
    @ObservedObject var model: SettingsModel
    @State private var shown = false

    var body: some View {
        LabeledContent {
            Button(tr("学到的内容…", "Learned…")) { shown = true }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(SettingsSpot.learned.title)
                Text(SettingsSpot.learned.note ?? "").font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.count(model.learned.count)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .settingsRow(.learned, shown: model.spot)
        .onAppear { model.refreshLearned() }
        .sheet(isPresented: $shown) {
            LearnedSheet(model: model) { shown = false }
        }
    }

    /// "Nothing learned yet", "3 things learned".
    static func count(_ count: Int) -> String {
        switch count {
        case 0: return LearnedSheet.nothing
        case 1: return tr("学到了 1 项", "1 thing learned")
        default: return tr("学到了 \(count) 项", "\(count) things learned")
        }
    }
}

/// Privacy → Learned…, the list (`LearnedStore.items`): a row for each thing learned on this Mac (an app's starting
/// input, where autocomplete stopped, where typos couldn't be fixed, the suggestion rows picked, the models that don't
/// take a temperature), each with Forget, and Forget All. Nothing of it is in the config file or synced.
struct LearnedSheet: View {
    @ObservedObject var model: SettingsModel
    let done: () -> Void

    static var nothing: String { tr("还没有学到什么", "Nothing learned yet") }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if model.learned.isEmpty {
                        Text(Self.nothing).foregroundStyle(.secondary)
                    }
                    ForEach(Array(model.learned.enumerated()), id: \.offset) { _, item in
                        LabeledContent {
                            Button(tr("忘掉", "Forget")) { model.forget(item) }
                        } label: {
                            Text(item.text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } header: {
                    SectionTitle(SettingsSpot.learned.title, icon: SettingsPage.privacy.icon)
                } footer: {
                    Text(tr("只存在这台 Mac 上，不同步，也不存你打的字：只有 App、输入、次数和模型。忘掉的以后还会再学。",
                            "Kept on this Mac only, never synced, and never what you type: only apps, inputs, counts and models. What you forget can be learned again."))
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            HStack {
                Button(tr("全部忘掉", "Forget All")) { model.forgetAllLearned() }
                    .disabled(model.learned.isEmpty)
                Spacer()
                Button(tr("完成", "Done"), action: done).keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 16)
        }
        .frame(width: 560, height: 420)
        .onAppear { model.refreshLearned() }
    }
}

/// What the settings images show learned (`--settings-image`): a sample of each kind, in memory, never the user's (the
/// images go into docs and release notes). Mail starts in English, autocomplete stopped in Xcode, Terminal has no typos,
/// 42 suggestion rows picked, and one model of an OpenAI-compatible service that doesn't take a temperature.
@MainActor
enum LearnedSamples {
    /// The samples' store; its temperature models kept in `folder` (removed with it).
    static func store(in folder: URL) -> LearnedStore {
        let models = folder.appendingPathComponent("unsupported-temperature.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(["openai:o3-mini"]).write(to: models)
        let autocomplete = AutocompleteStore()
        autocomplete.learn { learning in
            var stopped = Autocomplete.Learning.App()
            stopped.stopped = true
            learning.apps["com.apple.dt.xcode"] = stopped
        }
        let store = LearnedStore(file: nil, autocomplete: autocomplete, temperature: TemperatureSupport(file: models))
        for _ in 0..<2 { store.corrected("com.apple.mail", to: .language(.english)) }
        store.turnTyposOff(in: "com.apple.Terminal")
        let picks = (0..<42).map { SuggestionPick(plugin: "github", source: "issues", match: "#\(1200 + $0)") }
        _ = store.moveIn(typosOff: [], picks: picks)
        return store
    }
}
