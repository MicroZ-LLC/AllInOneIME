// swift-tools-version: 6.0
import PackageDescription

// AllInOneIME's core: what every platform's shell shares (the macOS input method in the repository's root, Windows/
// beside it, later iOS and Android). Platform-neutral: what it needs of the system goes through `Platform`
// (Sources/AllInOneIMECore/Platform/), with Apple's frameworks in Platform/Apple/ (each file under `#if canImport`);
// Scripts/check-core-portable.sh keeps it so. No unsafe flags, so that a shell can depend on it by URL: the shell links
// what its system needs (librime's folder; on macOS, FoundationModels weak), and Scripts/check-core-standalone.sh keeps
// it from reaching outside this folder.
let package = Package(
    name: "AllInOneIME-Core",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AllInOneIMEText", targets: ["AllInOneIMEText"]),
        .library(name: "AllInOneIMECore", targets: ["AllInOneIMECore"]),
        .library(name: "AllInOneIMERime", targets: ["AllInOneIMERime"]),
        .library(name: "AllInOneIMECLI", targets: ["AllInOneIMECLI"]),
        // What a shell's tests share with the core's (`FakeEngine`, the keys, `ScriptFolder`, `Timing`, `PackData`).
        .library(name: "AllInOneIMETestSupport", targets: ["AllInOneIMETestSupport"]),
        // `swift package strings [--check]`: the String Catalog in step with the code, in the core or in a shell.
        .plugin(name: "Strings", targets: ["Strings"]),
    ],
    // CryptoKit's API everywhere: on Apple platforms swift-crypto is CryptoKit itself (re-exported), elsewhere its own.
    dependencies: [.package(url: "https://github.com/apple/swift-crypto.git", from: "5.0.0")],
    targets: [
        // The interface text and its language (UIString, InterfaceText, InterfaceLanguage) and the config's uiLanguage
        // (ConfigFile): all AllInOneIME Settings needs, so it doesn't link AllInOneIMECore. AllInOneIMECore re-exports it.
        .target(name: "AllInOneIMEText"),

        // Pure logic: AWS auth, Bedrock streaming client, prompt/parser, two-level composer, key maps.
        // FoundationModels (Apple's on-device model, macOS 26) is imported `@_weakLinked`; the macOS shell weak-links
        // the whole framework too (its Package.swift), so the app still runs on macOS 14.
        .target(
            name: "AllInOneIMECore",
            dependencies: ["AllInOneIMEText", .product(name: "Crypto", package: "swift-crypto")]
        ),

        // librime's C API (its headers, from the official release, in include/); the library is the shell's to link
        // (`-L`): on macOS, ThirdParty/librime from `make deps`.
        .systemLibrary(name: "CRime"),

        // Swift wrapper around librime: level one (local pinyin).
        .target(name: "AllInOneIMERime", dependencies: ["CRime", "AllInOneIMECore"], swiftSettings: [.swiftLanguageMode(.v5)]),

        // The command line (`CLI.run`): level two from a terminal. Each shell runs it from its own main, with its platform.
        .target(name: "AllInOneIMECLI", dependencies: ["AllInOneIMECore"]),

        // The tests' helpers, for the core's tests and a shell's; the tests' only, never a shell's app. Its own helpers use
        // the core's public API. The acceptance helpers in it (Acceptance/, the acceptance tests' author's) still import
        // the core @testable, which only a build with testing on allows (debug, or `swift test -c release`), though all
        // they use is public or `package` (Prompt.liveDataRule): until that import is a plain one, a release build of the
        // core is of its products, as a shell's is (`swift build -c release --product …`, each of them:
        // Scripts/check-core-standalone.sh --release), and `swift build -c release` alone, which builds every target,
        // fails on it.
        // (Crypto: Acceptance/AcceptanceShared.swift imports it, for the goldens' SHA-256.)
        .target(name: "AllInOneIMETestSupport", dependencies: ["AllInOneIMECore", .product(name: "Crypto", package: "swift-crypto")],
                path: "Tests/AllInOneIMETestSupport"),

        // The String Catalog's tool (Scripts/strings/main.swift) and the command that runs it in a package's folder.
        // (Swift 5 mode: it was a script, whose top-level variables Swift 6 takes for the main actor's.)
        .executableTarget(name: "strings-tool", path: "Scripts/strings", swiftSettings: [.swiftLanguageMode(.v5)]),
        .plugin(
            name: "Strings",
            capability: .command(
                intent: .custom(verb: "strings", description: "Keep Resources/Localizable.xcstrings in step with the code"),
                permissions: [.writeToPackageDirectory(reason: "Adds the code's new interface texts to the String Catalog")]
            ),
            dependencies: ["strings-tool"],
            path: "Scripts/StringsPlugin"
        ),

        .testTarget(name: "AllInOneIMECoreTests", dependencies: ["AllInOneIMECore", "AllInOneIMETestSupport"],
                    resources: [.copy("Fixtures")]),
    ]
)

// The core builds for iOS too (`make check-ios` in the repository's root).
package.platforms?.append(.iOS(.v17))

// Elsewhere (Linux, Windows, Android) the package is the core and its tests: librime (an official macOS build, which
// the macOS shell links) is macOS's for now.
#if !os(macOS)
let macOnly: Set = ["CRime", "AllInOneIMERime"]
package.targets.removeAll { macOnly.contains($0.name) }
package.products.removeAll { $0.name == "AllInOneIMERime" }
// The core's tests as they are: what they import of Apple's (os's lock, CryptoKit, CoreGraphics) is shimmed
// (Tests/LinuxShims), and the one that needs Darwin's posix_spawn is left out.
package.targets += [
    .target(name: "os", path: "Tests/LinuxShims/os"),
    .target(name: "CryptoKit", dependencies: [.product(name: "Crypto", package: "swift-crypto")], path: "Tests/LinuxShims/CryptoKit"),
    .target(name: "CoreGraphics", path: "Tests/LinuxShims/CoreGraphics"),
]
if let tests = package.targets.first(where: { $0.name == "AllInOneIMECoreTests" }) {
    tests.dependencies = ["AllInOneIMECore", "AllInOneIMETestSupport", "os", "CryptoKit", "CoreGraphics"]
    tests.exclude += ["Acceptance/PluginLanguageAcceptanceTests.swift"]
    #if os(Windows)
    // Windows has no POSIX calls for the tests to check processes and files with (pid_t, kill, process groups, realpath,
    // lstat, opendir): those that use them are left out, and with them the ones that write their scripts with ScriptFolder
    // (bash scripts anyway) or ExtensionComposerTests' helpers.
    tests.exclude += ["ExtensionTests.swift", "ExtensionRobustnessTests.swift", "ExtensionComposerTests.swift",
                      "ClickPickTests.swift", "ExtensionExamplesTests.swift", "Acceptance/QuestionHistoryAcceptanceTests.swift"]
    package.targets.first { $0.name == "AllInOneIMETestSupport" }?.exclude += ["ScriptFolder.swift"]
    #endif
}
#endif
