import AllInOneIMECore
import SwiftUI

/// Settings → AI Provider → Privacy: sensitive values hidden from the AI before a request is sent (`Redaction`),
/// each kind on its own switch, and the user's own words.
struct PrivacySection: View {
    @ObservedObject var model: SettingsModel
    /// The words field as typed; saved on Return and when the page goes (`RedactionSettings.words`).
    @State private var words = ""

    var body: some View {
        Section {
            Toggle(isOn: $model.config.redaction.enabled) {
                titled(tr("发送前隐藏敏感信息", "Hide sensitive information before sending"),
                       tr("邮箱、电话、卡号、密钥这些先换成 [EMAIL_1] 这样的占位符再发给 AI，结果里再换回真实内容。",
                          "Emails, numbers and keys are replaced with placeholders such as [EMAIL_1] before the AI sees the text, and put back in the results."))
            }
            if model.config.redaction.enabled {
                Toggle(tr("邮箱地址", "Email addresses"), isOn: $model.config.redaction.emails)
                Toggle(tr("电话号码", "Phone numbers"), isOn: $model.config.redaction.phones)
                Toggle(tr("银行卡号", "Payment card numbers"), isOn: $model.config.redaction.cards)
                Toggle(tr("API 密钥和令牌", "API keys and tokens"), isOn: $model.config.redaction.keys)
                Toggle(tr("IP 地址", "IP addresses"), isOn: $model.config.redaction.ips)
                LabeledContent {
                    TextField("", text: $words, prompt: Text(tr("项目代号、名字…，用逗号分开", "A codename, a name…, separated by commas")))
                        .onSubmit(saveWords)
                        .frame(minWidth: 240)
                } label: {
                    titled(tr("也隐藏这些词", "Also hide these words"), tr("不分大小写", "In any case"))
                }
            }
        } header: {
            SectionTitle(tr("隐私", "Privacy"), icon: CommandIcons.provider)
        } footer: {
            Text(tr("能认出有固定格式的内容，比如邮箱、号码和密钥；认不出人名和地址，要隐藏的名字请加到上面的词里。",
                    "Recognizes formatted values like emails, numbers and keys; it can't recognize names or addresses, so add the names to hide as your own words."))
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)  // under the card, from its left
        }
        .disabled(!model.canSave)
        .onAppear { words = model.config.redaction.customWords.joined(separator: ", ") }
        .onDisappear(perform: saveWords)
        .onChange(of: model.config.redaction) { model.save() }
    }

    private func saveWords() {
        let list = RedactionSettings.words(from: words)
        words = list.joined(separator: ", ")
        if list != model.config.redaction.customWords { model.config.redaction.customWords = list }
    }

    private func titled(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// What the candidate panel says when values were hidden from the AI: one quiet line beside the time, and a row
/// whose placeholder the model changed past telling (`Redaction.isAltered`) marked, its text as the model wrote it.
enum RedactionPanel {
    static func hiddenLine(_ count: Int) -> String {
        tr("已对 AI 隐藏 \(count) 项", count == 1 ? "1 item hidden from the AI" : "\(count) items hidden from the AI")
    }

    static let changed = tr("⚠ 占位符被改动", "⚠ placeholder changed")

    static func annotate(_ model: inout CandidateView.Model, choices: [Composer.Choice], hidden: Int, phase: Composer.Phase) {
        guard hidden > 0 else { return }
        switch phase {
        case .translating, .choosing: break
        default: return
        }
        for (index, choice) in choices.enumerated() where model.rows.indices.contains(index) && choice.kind != .original
            && choice.isComplete && Redaction.isAltered(choice.text) {
            model.rows[index].comment = model.rows[index].comment.isEmpty ? changed : model.rows[index].comment + " · " + changed
        }
        model.detail = [hiddenLine(hidden), model.detail].compactMap { $0 }.joined(separator: " · ")
    }
}
