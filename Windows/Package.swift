// swift-tools-version: 6.0
import PackageDescription

// The Windows shell. For now its command line: the core's (AllInOneIMECLI) on the core's own platform, and the tests
// of the core's librime binding (AllInOneIMERime) on librime's Windows build. The input method (a Text Services
// Framework text service), its settings and its installer come next, as the macOS shell has them.

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
    ],
    dependencies: [.package(path: "../Core")],
    targets: [
        .executableTarget(name: "allinoneime-cli", dependencies: [core("AllInOneIMECLI")]),
    ]
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
#endif
