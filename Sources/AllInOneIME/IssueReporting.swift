import AllInOneIMECore
import AppKit

/// What a report of a problem says about this Mac and the settings (`IssueReport.Diagnostics`), for `@reportissue`,
/// the input menu's "Report an Issue…" and Settings → About. Only versions, kinds and counts: the plugins and the
/// extensions are counted, never named.
@MainActor
enum IssueReporting {
    static func diagnostics(config: Config, plugins: Int, extensions: Int) -> IssueReport.Diagnostics {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let macOS = "\(version.majorVersion).\(version.minorVersion)" + (version.patchVersion > 0 ? ".\(version.patchVersion)" : "")
        let packs = LanguagePack.catalog.compactMap { pack -> String? in
            guard case let .installed(record) = LanguagePackManager.shared.state(pack) else { return nil }
            return "\(record.id) \(record.version)"
        }
        // The interface language picked, or the system's (which it follows) with "system".
        return IssueReport.Diagnostics(config: config, macOS: macOS, architecture: architecture,
                                       interfaceLanguage: config.uiLanguage ?? "system (\(UIText.language))",
                                       languagePacks: packs, plugins: plugins, extensions: extensions)
    }

    /// The installed plugins and extensions, as the input method has them now (no scan).
    static func current(config: Config) -> IssueReport.Diagnostics {
        diagnostics(config: config, plugins: LivePlugins.current().count, extensions: LiveExtensions.current(config).commands.count)
    }

    /// The new-issue page without a title (written there), for the menu and the settings.
    static func open(config: Config) {
        NSWorkspace.shared.open(IssueReport(title: "", diagnostics: current(config: config)).url)
    }

    /// This build's architecture, and Rosetta when an Intel build runs on Apple silicon.
    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let rosetta = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
        return rosetta ? "x86_64 (Rosetta)" : "x86_64"
        #endif
    }
}
