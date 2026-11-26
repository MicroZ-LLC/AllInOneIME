import Foundation

/// The core's resources (Package.swift: AllInOneIMECore's `resources`), in the bundle SwiftPM makes of them,
/// "AllInOneIME-Core_AllInOneIMECore": a .bundle on Apple's systems, a .resources folder elsewhere. Looked for where
/// `Bundle.module` looks (an app's resources: the macOS app's Contents/Resources, where the Makefile's `app` puts it; a
/// test bundle's; beside a command-line tool or, off Apple's systems, any executable) and beside a test bundle, but
/// never stopping the process as `Bundle.module` does when the bundle isn't there: a program built from the core's
/// objects by hand (some tests compile their children so) finds nothing instead.
enum CoreResources {
    static let bundleName = "AllInOneIME-Core_AllInOneIMECore"

    /// A class of this module, for the bundle its code was loaded from (a test bundle, a framework).
    private final class Marker {}

    /// The resource's file, or nil when there is no such resource or no bundle of them.
    static func url(forResource name: String, withExtension ext: String) -> URL? {
        let loaded = Bundle(for: Marker.self)
        let places = [Bundle.main.resourceURL, loaded.resourceURL, Bundle.main.bundleURL,
                      loaded.bundleURL.deletingLastPathComponent()]
        for place in places.compactMap({ $0 }) {
            for kind in ["bundle", "resources"] {
                let bundle = Bundle(url: place.appendingPathComponent("\(bundleName).\(kind)", isDirectory: true))
                if let url = bundle?.url(forResource: name, withExtension: ext) { return url }
            }
        }
        return nil
    }
}
