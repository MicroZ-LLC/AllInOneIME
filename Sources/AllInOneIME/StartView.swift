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

    /// System Settings → Keyboard, where step 1 sends the user to add the input source.
    static let keyboardSettings = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")

    private var switchStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.sourceAdded {
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
            } else {
                addStep
            }
            Spacer(minLength: 0)
            HStack {
                Button(tr("跳过上手", "Skip")) { StartWindow.close() }.buttonStyle(.link)
                Spacer()
            }
        }
    }

    /// Step 1 while the input source isn't added (a fresh install where macOS left that to the user): where to add it,
    /// and the button to Keyboard settings; once it is added, step 1 says to switch to it.
    private var addStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            title(tr("先添加 AllInOneIME", "Add AllInOneIME first"),
                  tr("在「键盘」设置的「输入法」里点「编辑…」，再点左下角的 +，选「英语」下的 AllInOneIME，点「添加」。加好以后，这里自己往下走。",
                     "In Keyboard settings, under Input Sources, click Edit…, then + at the bottom left, choose AllInOneIME under English and click Add. Once you have, this goes on by itself."))
            Button(InputSourceStatus.button) {
                if let url = Self.keyboardSettings { NSWorkspace.shared.open(url) }
            }
            .controlSize(.large).keyboardShortcut(.defaultAction)
            Text(InputSourceStatus.steps).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 2. Connect an AI

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            title(tr("接上 AI", "Connect an AI"),
                  tr("登录后每天免费 200 次，不用自己的 AWS 或 API Key。", "Sign in for 200 free requests a day, with no AWS or API key of your own."))
            HStack(spacing: 10) {
                // Google's sign-in only where the service offers it, as Settings → AI shows it; Email works everywhere, so
                // it is the default button.
                if HostedService.googleEnabled {
                    Button(tr("用 Google 登录", "Sign in with Google")) { settings.signIn(.google) }
                        .controlSize(.large)
                }
                Button(tr("用邮箱登录 / 注册", "Sign in / Sign up with Email")) { settings.signIn(.email) }
                    .controlSize(.large).keyboardShortcut(.defaultAction)
                if settings.accountBusy { ProgressView().controlSize(.small) }
            }
            .disabled(settings.accountBusy)
            if let error = settings.accountError {
                Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            // A CLI with a subscription, an API key, a cloud service or Apple's model: each is chosen in Settings → AI,
            // and this goes on by itself once the one chosen is ready (`StartModel.aiReady`).
            Text(tr("已经有自己的 AI？", "Already have your own AI?")).font(.callout).foregroundStyle(.secondary).padding(.top, 6)
            ownAI(tr("使用我自己的 AI…", "Use My Own AI…"))
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(tr("稍后再说", "Later")) { model.later() }
            }
        }
    }

    /// "Already have your own AI?": Settings → AI, where each is chosen.
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
