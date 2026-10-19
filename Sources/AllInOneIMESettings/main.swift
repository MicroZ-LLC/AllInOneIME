// AllInOneIME Settings (「AllInOneIME 设置」): a small app in ~/Applications so the settings are easy
// to find (Spotlight, Launchpad, Finder). macOS only shows options for its own input methods in
// System Settings, so third-party input methods ship their own entry point like this one.
//
// It opens the input method with --settings: a running input method gets a reopen event and
// shows its settings window; one that isn't running yet starts and shows it.
import AllInOneIMEText
import AppKit

let inputMethodID = "com.aipinyin.inputmethod.AIPinyin"
let home = FileManager.default.homeDirectoryForCurrentUser
let installed = home.appendingPathComponent("Library/Input Methods/AllInOneIME.app")

/// The interface language, as in the input method: the one picked in the settings (`uiLanguage`), else the
/// system's among the languages this app ships (`InterfaceLanguage`).
let language = InterfaceLanguage.current(setting: ConfigFile.uiLanguage())

/// As the input method's `tr`: the Chinese, the English, or the String Catalog's translation of the English.
func tr(_ zh: UIString, _ en: UIString) -> String { InterfaceText.text(zh, en, language: language, app: .main) }

func fail(_ message: String) -> Never {
    let alert = NSAlert()
    alert.messageText = tr("打不开 AllInOneIME 设置", "Can't open AllInOneIME Settings")
    alert.informativeText = message
    alert.runModal()
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let url = FileManager.default.fileExists(atPath: installed.path)
    ? installed
    : NSWorkspace.shared.urlForApplication(withBundleIdentifier: inputMethodID)
guard let url else {
    fail(tr("没有找到 AllInOneIME 输入法（~/Library/Input Methods/AllInOneIME.app），请先安装。",
            "The AllInOneIME input method isn't installed (~/Library/Input Methods/AllInOneIME.app)."))
}

let configuration = NSWorkspace.OpenConfiguration()
configuration.arguments = ["--settings"]
configuration.activates = true
// macOS 14+ cooperative activation: hand our activation to the input method so its window can
// come to the front.
NSApp.yieldActivation(toApplicationWithBundleIdentifier: inputMethodID)
NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
    DispatchQueue.main.async {
        if let error { fail(error.localizedDescription) }
        exit(0)
    }
}
app.run()
