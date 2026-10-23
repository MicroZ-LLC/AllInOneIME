import Foundation

/// The code editors, one list for all that tells them apart: autocomplete is off there unless the app is set to always
/// (`Autocomplete.isCodeEditor`: Tab indents there and takes the editor's own completion, which a gray suggestion would
/// take instead, and what is written there is code), and suggestions' rows are the terminal and code editor class's there
/// (`SuggestionsAppClass.codeEditor`: Tab completes the rows' shared start only). Xcode, Visual Studio Code (and its
/// Insiders build), VSCodium, Cursor, Windsurf, Zed, Nova, Sublime Text, JetBrains' IDEs (IntelliJ IDEA, PyCharm,
/// WebStorm, GoLand, CLion, Rider, PhpStorm, RubyMine, DataGrip, Fleet), Android Studio, BBEdit, TextMate, MacVim, Emacs;
/// on Windows the same by program, with Visual Studio and Notepad++. Jupyter in a browser goes by the browser's id, and
/// can't be told. (Terminals are the field's: `FieldInfo.terminal`.)
public enum CodeEditors {
    /// By the beginning of their bundle ids, in small letters.
    static let apps = [
        "com.apple.dt.xcode", "com.microsoft.vscode", "com.vscodium", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf",
        "dev.zed.zed", "com.panic.nova", "com.sublimetext.", "com.jetbrains.", "com.google.android.studio", "com.barebones.bbedit",
        "com.macromates.textmate", "org.vim.macvim", "org.gnu.emacs",
    ]
    /// On Windows, by their program's file name (an app id "win:code.exe").
    static let programs: Set<String> = [
        "code.exe", "code - insiders.exe", "vscodium.exe", "cursor.exe", "windsurf.exe", "zed.exe", "sublime_text.exe", "devenv.exe",
        "idea64.exe", "pycharm64.exe", "webstorm64.exe", "goland64.exe", "clion64.exe", "rider64.exe", "phpstorm64.exe",
        "rubymine64.exe", "datagrip64.exe", "studio64.exe", "notepad++.exe",
    ]

    /// Whether `app` (a bundle id, or a Windows app id; in any case) is a code editor.
    public static func contains(_ app: String?) -> Bool {
        guard let app = app?.lowercased() else { return false }
        if app.hasPrefix("win:") { return programs.contains(String(app.dropFirst(4))) }
        return apps.contains { app.hasPrefix($0) }
    }
}
