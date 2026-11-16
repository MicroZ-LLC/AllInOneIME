import AllInOneIMECore
import SwiftUI

/// The start's three steps (#122), 560 × 440: the app's icon and name, the step's dots and "1 / 3", then the step.
struct StartView: View {
    @ObservedObject var model: StartModel
    /// Step 2's sign-in, through Settings → AI's own calls (`SettingsModel.signIn`).
    @ObservedObject var settings: SettingsModel
    /// Step 3's field.
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    private var trigger: String { settings.config.commandTrigger }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            switch model.step {
            case 1: switchStep
            case 2: connectStep
            default: tryStep
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32).padding(.top, 36).padding(.bottom, 24)
        .frame(width: 560, height: 440, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 32, height: 32).accessibilityHidden(true)
            Text("AllInOneIME").font(.system(size: 15, weight: .semibold))
            Spacer()
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { index in
                    Circle().fill(index == model.step ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)
            Text("\(model.step) / 3").font(.callout).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func title(_ text: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.system(size: 22, weight: .semibold))
            Text(body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 1. Switch to AllInOneIME

    private var switchStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            title(tr("先切到 AllInOneIME", "Switch to AllInOneIME"),
                  tr("按 Control + 空格，或在菜单栏的输入法菜单里选 AllInOneIME。切过去以后，这里自己往下走。",
                     "Press Control + Space, or choose AllInOneIME in the Input menu in the menu bar. Once you have, this goes on by itself."))
            HStack(spacing: 8) {
                Image(systemName: "keyboard").foregroundStyle(.secondary).accessibilityHidden(true)
                Text(tr("现在的输入法：", "Input source now: ")).foregroundStyle(.secondary)
                Text(model.sourceName.isEmpty ? "—" : model.sourceName).fontWeight(.medium)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
            Spacer(minLength: 0)
            HStack {
                Button(tr("跳过上手", "Skip")) { StartWindow.close() }.buttonStyle(.link)
                Spacer()
            }
        }
    }

    // MARK: 2. Connect an AI

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            title(tr("接上 AI", "Connect an AI"),
                  tr("登录后每天免费 200 次，不用自己的 AWS 或 API Key。", "Sign in for 200 free requests a day, with no AWS or API key of your own."))
            HStack(spacing: 10) {
                Button(tr("用 Google 登录", "Sign in with Google")) { settings.signIn(.google) }
                    .controlSize(.large).keyboardShortcut(.defaultAction)
                Button(tr("用邮箱登录 / 注册", "Sign in / Sign up with Email")) { settings.signIn(.email) }
                    .controlSize(.large)
                if settings.accountBusy { ProgressView().controlSize(.small) }
            }
            .disabled(settings.accountBusy)
            if let error = settings.accountError {
                Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Text(tr("已经有自己的 AI？", "Already have your own AI?")).font(.callout).foregroundStyle(.secondary).padding(.top, 6)
            HStack(spacing: 8) {
                ownAI(tr("你的订阅（Claude Code 等）", "Your subscription (Claude Code…)"))
                ownAI(tr("API Key", "API Key"))
                ownAI(tr("这台 Mac 上的 Apple", "Apple on this Mac"))
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(tr("稍后再说", "Later")) { model.later() }
            }
        }
    }

    /// One of "already have your own AI?": Settings → AI, where each is chosen.
    private func ownAI(_ name: String) -> some View {
        Button(name) { SettingsWindow.shared.show(page: .ai, spot: .provider) }
    }

    // MARK: 3. Try one @

    private var tryStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            title(tr("\(trigger) 后面，想说什么就打什么", "After \(trigger), type what you want"),
                  tr("不用记命令。打完它会列出能帮你做的事，↑↓ 选一个，回车执行。在下面试一次。",
                     "No commands to remember. Once you've typed, it lists what it can do; ↑↓ choose one, Return does it. Try it below."))
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder).controlSize(.large)
                .focused($fieldFocused)
                .accessibilityLabel(tr("试一试", "Try it"))
            HStack(spacing: 8) {
                ForEach(StartModel.examples, id: \.self) { example in
                    Button(trigger + example) {
                        text = StartModel.fieldText(trigger: trigger, example: example)
                        fieldFocused = true
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(tr("完成", "Done")) { StartWindow.close() }.keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            text = StartModel.fieldText(trigger: trigger, example: nil)
            DispatchQueue.main.async { fieldFocused = true }
        }
    }
}
