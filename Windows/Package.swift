// swift-tools-version: 6.0
import PackageDescription

// The Windows shell: the engine (the per-user process the TSF text service talks to over a named pipe, wire protocol
// v1) and the command line. The text service itself (a C++ DLL, Windows/tip), its settings and its installer come
// next, as the macOS shell has them.

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
        .executable(name: "AllInOneIMEEngine", targets: ["AllInOneIMEEngine"]),
    ],
    dependencies: [.package(path: "../Core")],
    targets: [
        // Windows' own: the pipe's two ends (PipeListener for the engine, PipeClient for the replay CLI) and the
        // Win32 they need (tokens, SIDs, the security descriptor). Empty off Windows.
        .target(name: "AllInOneIMEWindows", dependencies: [core("AllInOneIMEWire")]),
        // The per-user engine: the wire server on the pipe.
        .executableTarget(name: "AllInOneIMEEngine",
                          dependencies: ["AllInOneIMEWindows", core("AllInOneIMEWire"), core("AllInOneIMECore")]),
        .executableTarget(name: "allinoneime-cli",
                          dependencies: [core("AllInOneIMECLI"), core("AllInOneIMEWire"), "AllInOneIMEWindows"]),
        // The pipe's security, as the DLL's server check sees it. Windows only (empty elsewhere).
        .testTarget(name: "AllInOneIMEWindowsTests",
                    dependencies: ["AllInOneIMEWindows", core("AllInOneIMEWire"), core("AllInOneIMECore")]),
    ]
)
