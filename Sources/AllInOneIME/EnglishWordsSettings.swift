import AllInOneIMECore
import SwiftUI

/// Settings → Input → Chinese → English Words (「英文词」, `EnglishWords`): the English words of the user's that pinyin offers
/// among its candidates (`Config.englishWords`), the newest first, each removed with its ✕; more added in the field (several
/// separated by commas), saved on the list as the file has it then (`SettingsModel.addEnglishWords`; a key, a card or phone
/// number, an address refused, and said); and the switch that learns them from letters put in as typed, and from words
/// typed in English mode. The jargon list's English terms and the built-in list come up too, and aren't listed here.
struct EnglishWordsSection: View {
    @ObservedObject var model: SettingsModel
    @State private var adding = ""
    /// The last Add added nothing: the word is there already, or isn't one.
    @State private var notAdded = false
    /// The last Add left out what looks like a key, a card or phone number, an address (`EnglishWords.isSensitive`).
    @State private var refused = false

    var body: some View {
        Section {
            Toggle(isOn: $model.config.learnsEnglishWords) {
                titled(tr("学习打出的英文词", "Learn the English words you type"),
                       tr("打拼音时把同样的字母原样上屏两次（比如打 bedrock 按 ⏎，再来一次），或者在英文模式下把同一个词打两次，这个词以后就出现在拼音的候选里（英文模式下照常打字，什么都不显示）。密码框、终端、远程桌面和虚拟机、关了 AI 的 App 里不学，像密钥、号码的不学，英文模式下大写字母开头的词也不学。",
                          "Put the same letters in as typed twice while typing pinyin (bedrock and ⏎, then again), or type the same word twice in English mode, and it comes up among pinyin's candidates from then on (English mode itself shows nothing). Never in password fields, terminals, remote desktops and virtual machines, or apps with AI off, nor anything that looks like a key or a number, nor a word typed in English mode with a capital first."))
            }
            LabeledContent {
                HStack(spacing: 8) {
                    TextField("", text: Binding(get: { adding }, set: { adding = $0; notAdded = false; refused = false }),
                              prompt: Text(tr("比如 Bedrock", "Bedrock, say")))
                        .onSubmit(add)
                        .frame(minWidth: 180)
                    Button(tr("添加", "Add"), action: add)
                        .disabled(adding.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } label: {
                titled(tr("添加英文词", "Add English words"), tr("几个词用逗号分开", "Several separated by commas"))
            }
            if refused {
                Label(tr("没有添加像密钥、卡号、电话号码或 IP 地址的内容：你的英文词会通过 iCloud 同步，也会出现在候选里。",
                         "Left out what looks like a key, a card or phone number, or an IP address: your English words sync through iCloud and come up among the candidates."),
                      systemImage: "lock.trianglebadge.exclamationmark")
                    .font(.caption).foregroundStyle(.orange)
            } else if notAdded {
                Label(tr("没有添加：已经有了，或者不是英文词（英文字母开头，可以带数字和 - . + & ' _ /）。",
                         "Not added: it's there already, or isn't an English word (a Latin letter first, then letters, digits or - . + & ' _ /)."),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            let words = Array(model.config.englishWords.reversed())
            LabeledContent {
                if words.isEmpty {
                    Text(tr("还没有", "None yet")).foregroundStyle(.secondary)
                }
            } label: {
                titled(tr("你的英文词", "Your English words"),
                       tr("\(words.count) 个，新的在前", "\(words.count), the newest first"))
            }
            if !words.isEmpty {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 6) {
                        ForEach(Array(words.enumerated()), id: \.offset) { _, word in chip(word) }
                    }
                }
                .frame(maxHeight: 180)
            }
        } header: {
            SectionTitle(tr("英文词", "English Words"), icon: CandidateView.Icon(symbol: "textformat.abc", color: .systemTeal))
        } footer: {
            Text(tr("打几个字母，以它们开头的英文词就出现在拼音的候选里，比如 bedr → Bedrock。除了你的，黑话库里的英文词和 \(EnglishWords.curated.count) 个常用的产品和技术词（Bedrock、SageMaker…）也会出现；rime-ice 自带的英文词照旧。",
                    "Type a few letters and the English words they start come up among pinyin's candidates: bedr → Bedrock. Besides yours, the English terms of your jargon list and \(EnglishWords.curated.count) common product and technical words (Bedrock, SageMaker…) come up too; rime-ice's own English words are as before."))
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)  // under the card, from its left
        }
        .disabled(!model.canSave)
        .onChange(of: model.config.learnsEnglishWords) { model.save() }
    }

    private func chip(_ word: String) -> some View {
        HStack(spacing: 2) {
            Text(word).lineLimit(1).truncationMode(.middle)
            Button { model.removeEnglishWord(word) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .help(tr("移除\(word)", "Remove \(word)"))
                .accessibilityLabel(tr("移除\(word)", "Remove \(word)"))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.secondary.opacity(0.1), in: Capsule())
    }

    private func add() {
        guard !adding.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let result = model.addEnglishWords(adding)
        refused = !result.refused.isEmpty
        notAdded = result.words.isEmpty && !refused
        // What was refused goes from the screen too.
        if !result.words.isEmpty || refused { adding = "" }
    }

    private func titled(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
