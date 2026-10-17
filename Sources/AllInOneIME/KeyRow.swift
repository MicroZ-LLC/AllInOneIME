import AllInOneIMECore
import AppKit
import SwiftUI

/// Whether a key is set, as a key row shows it: saved in the keychain (with its last 4 characters when they were kept,
/// `APIKeys.ending(of:)`), set in the user's shell, or not set. The key itself is never read for this.
enum KeyState: Equatable {
    /// Not looked up yet.
    case loading
    case saved(ending: String?)
    /// In the user's shell, under this variable.
    case shell(String)
    case missing

    init(_ source: APIKeys.Source?, ending: String?) {
        switch source {
        case .keychain?: self = .saved(ending: ending)
        case let .environment(name)?: self = .shell(name)
        case .none?: self = .missing
        case nil: self = .loading
        }
    }

    var isSet: Bool {
        switch self {
        case .saved, .shell: return true
        case .loading, .missing: return false
        }
    }

    /// "✓ Saved · ends in a1b2", "✓ From $OPENAI_API_KEY", or `missing` ("No API key yet").
    func text(missing: String) -> String {
        switch self {
        case .loading: return ""
        case let .saved(ending): return "✓ " + tr("已保存", "Saved") + (ending.map { tr(" · 结尾 \($0)", " · ends in \($0)") } ?? "")
        case let .shell(name): return "✓ " + tr("来自 $\(name)", "From $\(name)")
        case .missing: return missing
        }
    }

    /// The status as the row draws it: the checkmark in green, a missing key in orange.
    func label(missing: String) -> Text {
        switch self {
        case .saved, .shell:
            return Text("✓").foregroundColor(.green) + Text(text(missing: missing).dropFirst()).foregroundColor(.primary)
        case .missing:
            return Text(missing).foregroundColor(.orange)
        case .loading:
            return Text("")
        }
    }
}

/// The content of a key row (the label is the caller's): with a key, its status and Replace… and Remove…, the paste
/// field shown only once Replace… is clicked, so that an empty field never stands for a key that is saved; without one,
/// "No API key yet" and the paste field with Save. An empty or blank field saves nothing and removes nothing; removing is
/// Remove…, confirmed.
struct KeyRowContent: View {
    let state: KeyState
    /// What a missing key is called: "No API key yet".
    let missing: String
    /// The paste field's placeholder.
    let prompt: String
    /// Remove…'s question, and what removing means (nil: nothing to add).
    let removeTitle: String
    var removeMessage: String? = nil
    let save: (String) -> Void
    /// Nil: no Remove… (a key in the shell isn't ours to remove).
    let remove: (() -> Void)?
    /// The paste field shown and focused (Replace…, or asked from outside: Settings → Assistant opening the key).
    @Binding var editing: Bool
    @State private var text = ""
    @State private var removing = false
    @FocusState private var focused: Bool

    private var blank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        Group {
            if state == .missing || editing {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        SecureField("", text: $text, prompt: Text(prompt))
                            .labelsHidden()
                            .focused($focused)
                            .onSubmit(commit)
                            .onExitCommand(perform: cancel)
                        Button(tr("保存", "Save"), action: commit).disabled(blank)
                        if state != .missing { Button(tr("取消", "Cancel"), action: cancel) }
                    }
                    if state == .missing { state.label(missing: missing).font(.callout) }
                }
            } else {
                HStack(spacing: 8) {
                    state.label(missing: missing)
                    Spacer(minLength: 8)
                    if state.isSet {
                        Button(tr("替换…", "Replace…")) { editing = true }
                        if let remove {
                            Button(tr("删除…", "Remove…")) { removing = true }
                                .alert(removeTitle, isPresented: $removing) {
                                    // ⏎ is Cancel: removing is a choice of its own.
                                    Button(tr("取消", "Cancel"), role: .cancel) {}.keyboardShortcut(.defaultAction)
                                    Button(tr("删除", "Remove"), role: .destructive, action: remove)
                                } message: {
                                    if let removeMessage { Text(removeMessage) }
                                }
                        }
                    }
                }
            }
        }
        .onAppear { if editing { focused = true } }
        .onChange(of: editing) { if editing { focused = true } else { text = "" } }
    }

    private func commit() {
        guard !blank else { return }
        save(text)
        text = ""
        editing = false
    }

    private func cancel() {
        text = ""
        editing = false
    }
}

/// Settings' sheet for the key of a provider other than the one in use (Settings → Assistant asked for it): nothing
/// about that provider is drawn on the current one's page. Save keeps the key; Save and Use also switches to the
/// provider and runs Test Connection; Cancel and Esc change nothing.
struct KeySheet: View {
    @ObservedObject var model: SettingsModel
    let provider: Provider
    let close: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private var blank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var name: String { UIText.name(provider) }

    /// "Gemini", "Claude": the name on "Save and Use …".
    static func shortName(_ provider: Provider) -> String {
        switch provider {
        case .anthropic: return "Claude"
        case .gemini: return "Gemini"
        default: return UIText.name(provider)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("\(name) 的 key", "\(name) key")).font(.headline)
            model.keyState(provider).label(missing: tr("还没有 API key", "No API key yet")).font(.callout)
            SecureField("", text: $text, prompt: Text(tr("粘贴 API key", "Paste the API key")))
                .labelsHidden()
                .focused($focused)
                .onSubmit(save)
            Text(tr("key 存在钥匙串里，不会发给 AI。", "Keys are kept in your keychain and never sent to the AI."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(tr("保存并使用 \(Self.shortName(provider))", "Save and Use \(Self.shortName(provider))"), action: saveAndUse)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(blank)
                Spacer()
                Button(tr("取消", "Cancel"), role: .cancel, action: close).keyboardShortcut(.cancelAction)
                Button(tr("保存", "Save"), action: save).keyboardShortcut(.defaultAction).disabled(blank)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { focused = true }
    }

    private func save() {
        guard !blank else { return }
        model.saveKey(text, for: provider)
        text = ""
        close()
    }

    private func saveAndUse() {
        guard !blank else { return }
        model.saveKeyAndUse(text, for: provider)
        text = ""
        close()
    }
}

/// The provider whose key the sheet asks for.
struct KeySheetRequest: Identifiable, Equatable {
    let provider: Provider
    var id: String { provider.rawValue }
}
