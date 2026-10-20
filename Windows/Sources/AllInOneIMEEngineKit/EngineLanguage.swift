import AllInOneIMECore
import Foundation

/// The engine's interface language, as the Mac's input method has it: the text of the settings document, the notices
/// and the panel in the language the settings pick (`Config.uiLanguage`, `UIText.choice`), else the system's, among the
/// nine the core's String Catalog has. Windows has no `.lproj` bundles: the catalog itself ships beside the engine
/// (`Localizable.xcstrings`), read into tables (`StringCatalog`, `UIText.useCatalog`).
public enum EngineLanguage {
    public static let catalogName = "Localizable.xcstrings"

    /// The catalog: beside the program (installed), else the core's own in the checkout a build is in
    /// (`Core/Resources`, a few folders up from `Windows/.build/<configuration>`).
    public static func catalog(executable: URL) -> URL? {
        let fm = FileManager.default
        let folder = executable.deletingLastPathComponent()
        var candidates = [folder.appendingPathComponent(catalogName)]
        var up = folder
        for _ in 0..<6 {
            up = up.deletingLastPathComponent()
            candidates.append(up.appendingPathComponent("Core/Resources/" + catalogName))
        }
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }

    /// Gives the core the catalog's translations and the system's languages (what "follow the system" picks from).
    public static func use(catalog url: URL) throws {
        let tables = try StringCatalog.tables(from: Data(contentsOf: url))
        UIText.useCatalog(tables, preferred: EngineSettings.preferredLanguages)
    }

    /// The settings' interface language, at the start and after each change of the settings (wherever it was made).
    public static func apply(_ config: Config) {
        if UIText.choice != config.uiLanguage { UIText.choice = config.uiLanguage }
    }
}
