// swift-tools-version: 6.0
import PackageDescription

// The Windows shell. For now its command line: the core's (AllInOneIMECLI) on the core's own platform. The input method
// (a Text Services Framework text service), its settings and its installer come next, as the macOS shell has them.

/// The core's package: every product of it goes through `core`, so that when the core comes from its own repository
/// (`.package(url:)`, whose identity is "allinoneime-core") only this changes.
let corePackage = "core"
func core(_ product: String) -> Target.Dependency { .product(name: product, package: corePackage) }

let package = Package(
    name: "AllInOneIME-Windows",
    // Off Windows only for trying it out (the core's floor on the Mac).
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "allinoneime-cli", targets: ["allinoneime-cli"]),
    ],
    dependencies: [.package(path: "../Core")],
    targets: [
        .executableTarget(name: "allinoneime-cli", dependencies: [core("AllInOneIMECLI")]),
    ]
)
