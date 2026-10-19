// swift-tools-version: 6.0
import PackageDescription

// The Windows shell: the engine (the per-user process the TSF text service talks to over a named pipe, wire protocol
// v1: pinyin through librime, the candidate window, the AI requests and the rest of what the Composer asks for), the
// command line (the core's, AllInOneIMECLI, on the core's own platform, plus wire-replay and the settings commands),
// and the tests of the core's librime binding (AllInOneIMERime) on librime's Windows build. The text service itself is
// a C++ DLL (Windows/tip), its installer an MSI (Windows/installer, with its helper AllInOneIMESetup); its settings
// window comes next, as the macOS shell has them.

/// The core's package: every product of it goes through `core`, so that when the core comes from its own repository
/// (`.package(url:)`, whose identity is "allinoneime-core") only this changes.
let corePackage = "core"
func core(_ product: String) -> Target.Dependency { .product(name: product, package: corePackage) }

/// Official librime release build (MSVC x64), unpacked by Scripts/fetch-librime.sh into ThirdParty:
/// $ALLINONEIME_THIRDPARTY if it is set (an absolute path), else ThirdParty here. The one rule, as the scripts and the
/// Rime tests have it.
let thirdParty = Context.environment["ALLINONEIME_THIRDPARTY"].flatMap { $0.isEmpty ? nil : $0 }
    ?? Context.packageDirectory + "/ThirdParty"
let rimeLib = thirdParty + "/librime/dist/lib"

/// What links librime (the core's CRime names it, `link "rime"`): rime.lib from its folder, and rime.dll delay-loaded,
/// so that the program loads it from where it is (`LoadLibraryExW` with its full path) before its first call into
/// librime, instead of Windows looking for it beside the program and on PATH at launch.
let linksRime: [LinkerSetting] = [
    .unsafeFlags(["-L\(rimeLib)", "-Xlinker", "/DELAYLOAD:rime.dll"], .when(platforms: [.windows])),
    .linkedLibrary("delayimp", .when(platforms: [.windows])),
]

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
        // The candidate window (M6): a layered, no-activate, topmost Win32 window drawn with Direct2D and DirectWrite, on
        // a thread of its own, behind a C interface (include/AllInOneIMEPanel.h). Empty off Windows.
        .target(name: "CAllInOneIMEPanel",
                linkerSettings: ["user32", "gdi32", "d2d1", "dwrite", "windowscodecs", "shcore", "ole32"].map {
                    .linkedLibrary($0, .when(platforms: [.windows]))
                }),
        // What the engine does, as a library its tests use too: the WireHost (pinyin through librime, the panel's model
        // and window, level two through the core's Converter, the clipboard, opening, terminals), the settings.
        .target(name: "AllInOneIMEEngineKit",
                dependencies: ["AllInOneIMEWindows", "CAllInOneIMEPanel", core("AllInOneIMEWire"), core("AllInOneIMECore"),
                               core("AllInOneIMERime")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        // The per-user engine: the wire server on the pipe.
        .executableTarget(name: "AllInOneIMEEngine",
                          dependencies: ["AllInOneIMEEngineKit", "AllInOneIMEWindows", core("AllInOneIMEWire"),
                                         core("AllInOneIMECore")],
                          linkerSettings: linksRime),
        .executableTarget(name: "allinoneime-cli",
                          dependencies: [core("AllInOneIMECLI"), core("AllInOneIMEWire"), "AllInOneIMEWindows"]),
        // The pipe's security, as the DLL's server check sees it. Windows only (empty elsewhere).
        .testTarget(name: "AllInOneIMEWindowsTests",
                    dependencies: ["AllInOneIMEWindows", core("AllInOneIMEWire"), core("AllInOneIMECore")]),
    ],
    // The candidate window's C++ (Direct2D, DirectWrite).
    cxxLanguageStandard: .cxx17
)

#if os(Windows)
// librime on Windows with rime-ice's data (Scripts/build-rime-data.sh): typing, paging, picking, learning, fuzzy pinyin,
// the learned words' sync, and the core's Composer on it. The macOS shell's own Rime tests are the root's.
package.targets.append(
    .testTarget(
        name: "AllInOneIMERimeTests",
        dependencies: [core("AllInOneIMERime"), core("AllInOneIMECore")],
        swiftSettings: [.swiftLanguageMode(.v5)],
        linkerSettings: linksRime
    )
)
// The engine's host through the wire: pinyin with the real librime, the panel's model and window, level two against a
// stub provider on localhost (never a paid API), the other effects, the settings commands.
package.targets.append(
    .testTarget(
        name: "AllInOneIMEEngineTests",
        dependencies: ["AllInOneIMEEngineKit", "AllInOneIMEWindows", core("AllInOneIMEWire"), core("AllInOneIMECore"),
                       core("AllInOneIMERime")],
        swiftSettings: [.swiftLanguageMode(.v5)],
        linkerSettings: linksRime
    )
)
#endif
