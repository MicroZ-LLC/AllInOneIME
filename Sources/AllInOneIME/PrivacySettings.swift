import AllInOneIMECore
import SwiftUI

/// Settings → Privacy: sensitive values hidden from the AI before a request is sent (`Redaction`: one switch, and the
/// user's own words), the apps without AI, what `@agent` takes from Chrome, the recent questions kept, and the English
/// words learned.
struct PrivacySection: View {
    @ObservedObject var model: SettingsModel
    /// The words field as typed; saved on Return and when the page goes (`RedactionSettings.words`), only if it was edited
    /// here, and then on top of the list as it is by then: a word added meanwhile elsewhere (the search's Change, a hand
    /// edit) stays. Not being edited, it follows the list.
    @State private var words = ""
    @State private var edited = false
    /// The list the field last showed: what an edit took out of it, or put in, is measured against it.
    @State private var shown: [String] = []

    var body: some View {
        Section {
            Toggle(isOn: $model.config.redaction.enabled) {
                titled(SettingsSpot.hideSensitive.title, SettingsSpot.hideSensitive.note ?? "")
            }
            .settingsRow(.hideSensitive, shown: model.spot)
            // Each kind is hidden with the switch on; one set off in the config (by hand, an earlier version) shows here.
            if model.config.redaction.enabled {
                ForEach(Self.kinds, id: \.title) { kind in
                    if !model.config.redaction[keyPath: kind.path] {
                        RestoreDefaultRow(title: kind.title + tr("：不隐藏", ": not hidden"),
                                          note: tr("默认会隐藏。", "Hidden by default.")) {
                            model.config.redaction[keyPath: kind.path] = true
                        }
                    }
                }
            }
            LabeledContent {
                TextField("", text: Binding(get: { words }, set: { if $0 != words { words = $0; edited = true } }),
                          prompt: Text(tr("项目代号、名字…，用逗号分开", "A codename, a name…, separated by commas")))
                    .onSubmit(saveWords)
                    .frame(minWidth: 240)
            } label: {
                titled(SettingsSpot.wordsToHide.title, SettingsSpot.wordsToHide.note ?? "")
            }
            .disabled(!model.config.redaction.enabled)
            .settingsRow(.wordsToHide, shown: model.spot)
        } header: {
            SectionTitle(tr("发给 AI 的内容", "What Goes to the AI"), icon: SettingsPage.privacy.icon)
        } footer: {
            Text(model.triggered(tr("只用于发给你的 AI 服务的请求；@agent、从网站取数据或打开网站的插件（@stock、@x）和脚本扩展照原样发送文字。",
                                    "Applies to requests to your AI service; @agent, plugins that fetch from or open a website (@stock, @x) and script extensions send text as typed.")))
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)  // under the card, from its left
        }
        .disabled(!model.canSave)
        .onAppear { show(model.config.redaction.customWords) }
        .onDisappear(perform: saveWords)
        // The list read again (written by the search's Change, by hand): shown, unless the field is being edited.
        .onChange(of: model.config.redaction.customWords) { if !edited { show(model.config.redaction.customWords) } }
        .onChange(of: model.config.redaction) { model.save() }
        Section {
            AppsWithoutAISection(model: model)
        }
        .disabled(!model.canSave)
        Section {
            // `@agent` (and `@reply` with nothing selected or pasted) in Chrome takes the page along (`PageContext`), with
            // Accessibility allowed. The key stays `agentPageContext`.
            Toggle(isOn: $model.config.agentPageContext) {
                titled(SettingsSpot.pageContext.title, SettingsSpot.pageContextNote)
            }
            .settingsRow(.pageContext, shown: model.spot)
            // The recent @questions (`QuestionHistory`); off forgets them too.
            Toggle(isOn: Binding(get: { model.config.rememberQuestions }, set: { model.setRememberQuestions($0) })) {
                titled(SettingsSpot.rememberQuestions.title,
                       model.triggered(tr("@question 后面不打字就列出最近 \(QuestionHistory.limit) 个问题和答案；关掉会忘掉它们。",
                                          "@question with nothing after it lists your last \(QuestionHistory.limit) questions and their answers; turning it off forgets them.")))
            }
            .settingsRow(.rememberQuestions, shown: model.spot)
            HStack {
                Text(model.recentQuestions == 0 ? tr("没有保存的问题。", "No questions saved.")
                     : model.recentQuestions == 1 ? tr("保存了 1 个问题。", "1 saved question.")
                     : tr("保存了 \(model.recentQuestions) 个问题。", "\(model.recentQuestions) saved questions."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(tr("忘掉（\(model.recentQuestions)）", "Forget (\(model.recentQuestions))")) { model.clearRecentQuestions() }
                    .disabled(model.recentQuestions == 0)
            }
            // The words themselves are in the English chip (Chinese's without English), General → Input languages.
            Toggle(isOn: $model.config.learnsEnglishWords) {
                titled(SettingsSpot.learnEnglishWords.title, SettingsSpot.learnEnglishWordsNote)
            }
            .settingsRow(.learnEnglishWords, shown: model.spot)
            // ── "Learned…" (Settings v2, 3.2) goes here, after Learn English words: the learned state (apps' starting
            // inputs, where autocomplete stopped, where typos couldn't be fixed, the rows picked, the models that refuse a
            // temperature), a row each with Forget, and Forget All. Until then their Forget buttons stay where they are.
        } header: {
            SectionTitle(tr("记住和学习", "Remembered and Learned"), icon: SettingsPage.privacy.icon)
        }
        .disabled(!model.canSave)
        .onChange(of: model.config.learnsEnglishWords) { model.save() }
    }

    /// The kinds hidden with the switch on, each kept in the config as its own (`RedactionSettings`).
    static var kinds: [(title: String, path: WritableKeyPath<RedactionSettings, Bool>)] {
        [(tr("邮箱地址", "Email addresses"), \.emails), (tr("电话号码", "Phone numbers"), \.phones),
         (tr("银行卡号", "Payment card numbers"), \.cards), (tr("API 密钥和令牌", "API keys and tokens"), \.keys),
         (tr("IP 地址", "IP addresses"), \.ips)]
    }

    private func show(_ list: [String]) {
        words = list.joined(separator: ", ")
        shown = list
        edited = false
    }

    /// The field's edit, if there was one, applied to the list as the file has it now (`SettingsModel.saveWords`, which
    /// saves it here: leaving the page, this section's onChange is gone with it): the words taken out of the field go,
    /// the words put in are added; the others, a word added elsewhere since included, stay.
    private func saveWords() {
        guard edited else { return }
        show(model.saveWords(field: words, shown: shown))
    }

    private func titled(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// What the candidate panel says when values were hidden from the AI (`PanelRedaction`, the core's), in the interface
/// language as it is now.
enum RedactionPanel {
    static func hiddenLine(_ count: Int) -> String { PanelRedaction.hiddenLine(count, language: UIText.language) }

    static var changed: String { PanelRedaction.changed(language: UIText.language) }

    static func annotate(_ model: inout PanelModel, choices: [Composer.Choice], hidden: Int, phase: Composer.Phase) {
        PanelRedaction.annotate(&model, choices: choices, hidden: hidden, phase: phase, language: UIText.language)
    }
}
