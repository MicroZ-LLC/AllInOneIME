import Foundation

/// The apps whose text fields didn't take a typo's fix as asked (`Config.typeOutMistakes`, `TypeOut.Typist`):
/// they get no typos again, across restarts, until forgotten (Settings → General, or
/// `defaults delete com.aipinyin.inputmethod.AIPinyin typeOutNoTyposApps`).
@MainActor
enum TypoMemory {
    /// Where they're kept (the self-test uses its own).
    static var defaults = UserDefaults.standard
    static let key = "typeOutNoTyposApps"

    static var apps: [String] { defaults.stringArray(forKey: key) ?? [] }

    static func contains(_ app: String) -> Bool { apps.contains(app) }

    /// Remembers `app` (never an app without a bundle identifier); false if it was already, or can't be.
    @discardableResult
    static func remember(_ app: String) -> Bool {
        guard !app.isEmpty, !contains(app) else { return false }
        defaults.set(apps + [app], forKey: key)
        return true
    }

    static func forget() { defaults.removeObject(forKey: key) }
}
