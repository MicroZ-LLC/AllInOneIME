import Foundation

/// The core's resources (Package.swift: AllInOneIMECore's `resources`), in the bundle SwiftPM makes of them,
/// "AllInOneIME-Core_AllInOneIMECore": a .bundle on Apple's systems, a .resources folder elsewhere. Looked for where
/// `Bundle.module` looks (an app's resources: the macOS app's Contents/Resources, where the Makefile's `app` puts it; a
/// test bundle's; beside a command-line tool or, off Apple's systems, any executable), beside a test bundle, and beside
/// the library the core was loaded from (a DLL or .so in another program: its bundle is the folder it's in), but never
/// stopping the process as `Bundle.module` does when the bundle isn't there: a program built from the core's objects by
/// hand (some tests compile their children so) finds nothing instead. A shell ships the bundle (README: Products).
enum CoreResources {
    static let bundleName = "AllInOneIME-Core_AllInOneIMECore"

    /// A class of this module, for the bundle its code was loaded from (a test bundle, a framework, a library).
    private final class Marker {}

    /// The resource's file, or nil when there is no such resource or no bundle of them.
    static func url(forResource name: String, withExtension ext: String) -> URL? {
        url(forResource: name, withExtension: ext, in: places(main: .main, loaded: Bundle(for: Marker.self)))
    }

    /// The folders the bundle may be in, in the order they're looked in: `main`'s resources, then `loaded`'s (the
    /// bundle the core's code came from), `main` itself, `loaded` itself (a library's folder), and the folder `loaded`
    /// is in (a test bundle's).
    static func places(main: Bundle, loaded: Bundle) -> [URL] {
        [main.resourceURL, loaded.resourceURL, main.bundleURL, loaded.bundleURL,
         loaded.bundleURL.deletingLastPathComponent()].compactMap { $0 }
    }

    /// The resource in the first of `places` that holds the bundle (.bundle or .resources) with it.
    static func url(forResource name: String, withExtension ext: String, in places: [URL]) -> URL? {
        for place in places {
            for kind in ["bundle", "resources"] {
                let bundle = Bundle(url: place.appendingPathComponent("\(bundleName).\(kind)", isDirectory: true))
                if let url = bundle?.url(forResource: name, withExtension: ext) { return url }
            }
        }
        return nil
    }
}
