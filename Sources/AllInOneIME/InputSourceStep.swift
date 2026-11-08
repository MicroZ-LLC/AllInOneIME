import AllInOneIMECore
import AllInOneIMEMac
import AppKit
import SwiftUI

// The one step the user has to take after an install or the move to this system identity: adding the input method in
// System Settings → Keyboard → Input Sources. macOS lets only the user add a new input method (asked to enable one,
// Text Input Sources says it did and changes nothing), so until the user has, the About page shows that step first, with
// a button to Keyboard settings (`InputSourceStepSection`); right after the move, the input method opens About on it at
// once, before any other page (`UpdateController.start`): nothing of AllInOneIME types until it is done. Looked at again
// when the input method's app becomes active (back from System Settings, say) and when a text field activates it; once
// the source is enabled the step goes, and what the move's record waits for (the input source before this one taken
// out) is done (`IdentityFinish`).

/// Whether the installed input method's own input source is enabled (`InputSourceCheck`). Main thread.
@MainActor
final class InputSourceStatus: ObservableObject {
    static let shared = InputSourceStatus()

    /// The installed input method's source isn't enabled: the About page shows the step.
    @Published var needsAdding = false
    /// Run once when the source is found enabled after it wasn't, the app active (the user back from System Settings).
    var whenAdded: (() -> Void)?
    /// Only the installed input method is the user's input source.
    var isInstalled = UpdateLocations.runningIsInstalled
    var check = InputSourceCheck.system(id: InputSourceRegistrar.sourceID, bundle: Bundle.main.bundleURL)
    /// Done when the source is found enabled: the move's record's step that waits for it, if there is one.
    var enabled: () -> Void = {
        IdentityFinish.queue.async {
            let finish = IdentityFinish.system(say: { line in log.notice("\(line, privacy: .public)") })
            if finish.waitsForInputSource { _ = finish.run() }
        }
    }
    /// What the last look found (nil: none yet).
    private var known: Bool?
    private var observer: NSObjectProtocol?

    /// System Settings → Keyboard.
    static let keyboardSettings = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!

    private init() {}

    /// At launch: looked at now, and again each time the app becomes active.
    func start() {
        refresh(appActive: false)
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                          queue: .main) { _ in
            MainActor.assumeIsolated { InputSourceStatus.shared.refresh(appActive: true) }
        }
    }

    /// A text field activated the input method: looked at again while the step is shown (it is enabled now).
    func textFieldActivated() {
        if needsAdding { refresh(appActive: false) }
    }

    func refresh(appActive: Bool) {
        guard isInstalled else {
            needsAdding = false
            return
        }
        let on = check.isEnabled()
        if needsAdding == on { needsAdding = !on }
        defer { known = on }
        guard on else {
            if known != false { log.notice("input source: not enabled; About shows the step to add it") }
            return
        }
        guard known != true else { return }
        if known == false { log.notice("input source: enabled") }
        enabled()
        if known == false, appActive, let whenAdded {
            self.whenAdded = nil
            whenAdded()
        }
    }

    /// The step, in plain words: where to add it.
    static var title: String {
        tr("还差一步：添加 AllInOneIME —— 系统设置 → 键盘 → 输入法 → + → 英语 → AllInOneIME",
           "One step left: add AllInOneIME — System Settings → Keyboard → Input Sources → + → English → AllInOneIME")
    }

    static var steps: String {
        tr("加好之前用不了 AllInOneIME 打字，而新的输入法只能由你自己添加。英语下面找不到它的话，先退出登录或重启 Mac 再加。加好以后用 Ctrl+空格 或 🌐 键切换到它。",
           "AllInOneIME can't type until it's added, and only you can add it. If it isn't listed under English, log out or restart your Mac first. Then switch to it with Ctrl+Space or the 🌐 key.")
    }

    static var button: String { tr("打开键盘设置", "Open Keyboard Settings") }
}

/// The About page's first section while the input source isn't enabled: the one step left, with the button that opens
/// Keyboard settings.
struct InputSourceStepSection: View {
    @ObservedObject var status: InputSourceStatus

    var body: some View {
        if status.needsAdding {
            Section {
                LabeledContent {
                    Button(InputSourceStatus.button) { NSWorkspace.shared.open(InputSourceStatus.keyboardSettings) }
                        .buttonStyle(.borderedProminent)
                } label: {
                    Label {
                        titled(InputSourceStatus.title, InputSourceStatus.steps)
                    } icon: {
                        Image(systemName: "keyboard").foregroundStyle(Color.orange)
                    }
                }
            }
        }
    }
}
