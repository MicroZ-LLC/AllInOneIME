import AllInOneIMECore
import SwiftUI

/// Settings → Privacy: sensitive values hidden from the AI before a request is sent (`Redaction`: one switch, and the
/// user's own words), the apps without AI, what `@agent` takes from Chrome, the English words learned, what else this
/// Mac learned (Learned…), and the install ID the update check sends. The recent questions kept are `@question`'s, on
/// the AI page (owner, 0.7.5).
struct PrivacySection: View {
    @ObservedObject var model: SettingsModel
    /// The words field, as typed (`SettingsModel.wordsField`): saved on Return, when it or the window loses the focus,
    /// when the page goes and with any other save (`RedactionSettings.words`), only if it was edited, and then on top of
    /// the list as it is by then: a word added meanwhile elsewhere (the search's Change, a hand edit) stays.
    @FocusState private var wordsFocused: Bool

    var body: some View {
        Section {
            // Words to hide only with the switch on (owner, 0.7.4); off, the search's Words to hide points at the switch.
            let hiding = model.config.redaction.enabled
            Toggle(isOn: $model.config.redaction.enabled) {
                titled(.hideSensitive)
            }
            .settingsRow(.hideSensitive, standingIn: hiding ? [] : [.wordsToHide], shown: model.spot)
            // Each kind is hidden with the switch on; one set off in the config (by hand, an earlier version) shows here.
            if hiding {
                ForEach(Self.kinds, id: \.title) { kind in
                    if !model.config.redaction[keyPath: kind.path] {
                        RestoreDefaultRow(title: kind.title + tr("：不隐藏", ": not hidden"),
                                          note: tr("默认会隐藏。", "Hidden by default.")) {
                            model.config.redaction[keyPath: kind.path] = true
                        }
                    }
                }
                LabeledContent {
                    TextField("", text: Binding(get: { model.wordsField }, set: { model.editWords($0) }),
                              prompt: Text(tr("项目代号、名字…，用逗号分开", "A codename, a name…, separated by commas")))
                        .focused($wordsFocused)
                        .onSubmit(model.commitWords)
                        .onChange(of: wordsFocused) { if !wordsFocused { model.commitWords() } }
                        .frame(minWidth: 240)
                } label: {
                    titled(.wordsToHide)
                }
                .settingsRow(.wordsToHide, shown: model.spot)
            }
        } header: {
            SectionTitle(tr("发给 AI 的内容", "What Goes to the AI"), icon: SettingsPage.privacy.icon)
        } footer: {
            Text(model.triggered(tr("只用于发给你的 AI 服务的请求；@agent、从网站取数据或打开网站的插件（@stock、@x）和脚本扩展照原样发送文字。",
                                    "Applies to requests to your AI service; @agent, plugins that fetch from or open a website (@stock, @x) and script extensions send text as typed.")))
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)  // under the card, from its left
        }
        .disabled(!model.canSave)
        .onAppear { if !model.wordsEdited { model.showWords(model.config.redaction.customWords) } }
        .onDisappear(perform: model.commitWords)
        // Another app in front, Settings left open: the field keeps the window's focus, but what that app sends next
        // hides the words typed.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            model.commitWords()
        }
        // The list read again (written by the search's Change, by hand): shown, unless the field is being edited.
        .onChange(of: model.config.redaction.customWords) {
            if !model.wordsEdited { model.showWords(model.config.redaction.customWords) }
        }
        .onChange(of: model.config.redaction) { model.save() }
        Section {
            AppsWithoutAISection(model: model)
        }
        .disabled(!model.canSave)
        Section {
            // `@agent` (and `@reply` with nothing selected or pasted) in Chrome takes the page along (`PageContext`), with
            // Accessibility allowed. The key stays `agentPageContext`.
            Toggle(isOn: $model.config.agentPageContext) {
                titled(.pageContext)
            }
            .settingsRow(.pageContext, shown: model.spot)
            // The words themselves are in the English chip (Chinese's without English), General → Input languages.
            Toggle(isOn: $model.config.learnsEnglishWords) {
                titled(.learnEnglishWords)
            }
            .settingsRow(.learnEnglishWords, shown: model.spot)
            // What this Mac learned (Settings v2, 3.2: apps' starting inputs, where autocomplete stopped, where typos
            // couldn't be fixed, where a result didn't take the selection's place, the rows picked, the models that refuse
            // a temperature), in a sheet: a row each with Forget, and Forget All.
            LearnedRow(model: model)
        } header: {
            SectionTitle(tr("记住和学习", "Remembered and Learned"), icon: SettingsPage.privacy.icon)
        }
        .disabled(!model.canSave)
        .onChange(of: model.config.learnsEnglishWords) { model.save() }
        Section {
            // In the update check's request (`UpdateController.installID`); off forgets the ID kept.
            Toggle(isOn: $model.config.sendsInstallID) {
                titled(.installID)
            }
            .settingsRow(.installID, shown: model.spot)
        } header: {
            SectionTitle(tr("发给 allinoneime.com 的内容", "What Goes to allinoneime.com"), icon: SettingsPage.privacy.icon)
        }
        .disabled(!model.canSave)
        .onChange(of: model.config.sendsInstallID) {
            model.save()
            if !model.config.sendsInstallID { UpdateController.shared.forgetInstallID() }
        }
    }

    /// The kinds hidden with the switch on, each kept in the config as its own (`RedactionSettings`).
    static var kinds: [(title: String, path: WritableKeyPath<RedactionSettings, Bool>)] {
        [(tr("邮箱地址", "Email addresses"), \.emails), (tr("电话号码", "Phone numbers"), \.phones),
         (tr("银行卡号", "Payment card numbers"), \.cards), (tr("API 密钥和令牌", "API keys and tokens"), \.keys),
         (tr("IP 地址", "IP addresses"), \.ips)]
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
