import Foundation

/// Password managers, by app: what is typed in one is a password, a name to sign in with or a note kept secret, whatever
/// its field says of itself (a password shown in a plain field, one typed before secure input comes on). Nothing typed
/// there is learned as an English word (`EnglishWords.learns`), and autocomplete never runs there (`Autocomplete.blocker`).
public enum PasswordManagers {
    /// By the beginning of their bundle ids (in small letters): 1Password (7 and 8), Apple's Passwords and Keychain
    /// Access, Bitwarden, KeePassXC, Strongbox, Enpass, Secrets, NordPass, Keeper, Proton Pass, RoboForm, Dashlane,
    /// LastPass, MacPass.
    static let bundleIDs = [
        "com.1password.", "com.agilebits.", "com.apple.passwords", "com.apple.keychainaccess", "com.bitwarden.",
        "org.keepassxc.", "com.markmcguill.strongbox", "in.sinew.enpass", "com.outercorner.secrets", "com.nordsec.nordpass",
        "com.keepersecurity.", "me.proton.pass", "com.siber.roboform", "com.dashlane.", "com.lastpass.", "com.hicknhacksoftware.macpass",
    ]
    /// The same on Windows, by their program's file name (an app id "win:1password.exe").
    static let programs: Set<String> = [
        "1password.exe", "bitwarden.exe", "keepassxc.exe", "keepass.exe", "enpass.exe", "nordpass.exe",
        "keeperpasswordmanager.exe", "proton pass.exe", "roboform.exe", "dashlane.exe",
    ]

    /// Whether `app` (a bundle id, or a Windows app id; in any case) is a password manager.
    public static func contains(_ app: String?) -> Bool {
        guard let app = app?.lowercased() else { return false }
        if app.hasPrefix("win:") { return programs.contains(String(app.dropFirst(4))) }
        return bundleIDs.contains { app.hasPrefix($0) }
    }
}
