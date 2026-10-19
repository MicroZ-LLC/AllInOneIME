import Foundation
import PackagePlugin

/// `swift package --allow-writing-to-package-directory strings [--check] [--merge OUT]`: runs Scripts/strings/main.swift
/// (strings-tool) in the folder of the package it is run in. Run in a shell (any package that depends on the core), it
/// adds the core's sources and passes the core's catalog as the base: a shell's catalog holds only the shell's own text,
/// whether the core is a local folder or a checkout of its repository (for a local folder, `--move-to-base` too).
@main
struct Strings: CommandPlugin {
    struct Failed: Error, CustomStringConvertible {
        var description: String
    }

    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var arguments = arguments
        if let core = Self.core(of: context.package), core.id != context.package.id {
            arguments += ["--sources", "Sources", "--sources", core.directoryURL.appendingPathComponent("Sources").path,
                          "--base", core.directoryURL.appendingPathComponent("Resources/Localizable.xcstrings").path]
            // A core in a folder of the shell's (`.package(path:)`) is edited with it: text that moved from the shell's
            // code to the core's moves catalogs too. A checkout of the core's repository isn't written to.
            if case .local = core.origin { arguments.append("--move-to-base") }
        }
        let process = Process()
        process.executableURL = try context.tool(named: "strings-tool").url
        process.arguments = arguments
        process.currentDirectoryURL = context.package.directoryURL
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failed(description: "strings failed (exit \(process.terminationStatus))") }
    }

    /// The core's package: this one, or the dependency (direct or not) that has the AllInOneIMECore target.
    static func core(of package: Package) -> Package? {
        if package.targets.contains(where: { $0.name == "AllInOneIMECore" }) { return package }
        for dependency in package.dependencies {
            if let found = core(of: dependency.package) { return found }
        }
        return nil
    }
}
