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
        // The wire protocol's engine side (docs/wire-protocol-v1.md): messages, frames, the server and the Composer's
        // adapter, whatever carries them (the Windows shell's pipe, later Android's JNI and the C ABI).
        .library(name: "AllInOneIMEWire", targets: ["AllInOneIMEWire"]),
        // QuickJS-ng as a ScriptEngine: the core's JavaScript off Apple platforms, and an Apple shell's if it wants it.
        .library(name: "AllInOneIMEQuickJS", targets: ["AllInOneIMEQuickJS"]),
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
            dependencies: [
                "AllInOneIMEText", "AllInOneIMEScriptEngine",
                // The JavaScript where there is no JavaScriptCore (Platform.systemScripts).
                .target(name: "AllInOneIMEQuickJS", condition: .when(platforms: [.linux, .windows, .android])),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),

        // The JavaScript engine's interface (ScriptEngine), below the core so that AllInOneIMEQuickJS can implement it
        // and still be the core's default. AllInOneIMECore re-exports it.
        .target(name: "AllInOneIMEScriptEngine"),

        // QuickJS-ng (QuickJSEngine): plugins and @js where there is no JavaScriptCore. On Apple platforms only the
        // tests use it, to run the JavaScript tests on both engines; Swift Build still compiles CQuickJS there and links
        // its object into every debug product (the app's too, about 480 JS_* functions), and release builds dead-strip
        // it. This Swift module itself isn't linked into them.
        .target(name: "AllInOneIMEQuickJS", dependencies: ["AllInOneIMEScriptEngine", "CQuickJS"]),

        // QuickJS-ng's C sources as released (VENDORED.md), its header and quickjs-swift.h for Swift (module.modulemap).
        // Flat, as upstream has them, so their includes are each other's; the defines and libm are upstream's CMake ones.
        // Each .c is built through its swift-*.c, which includes it with -Wshorten-64-to-32 off, so it is excluded.
        .target(
            name: "CQuickJS",
            exclude: ["LICENSE", "VENDORED.md", "quickjs.c", "dtoa.c", "libregexp.c", "libunicode.c"],
            publicHeadersPath: ".",
            cSettings: [
                .define("_GNU_SOURCE"),
                .define("NDEBUG", .when(configuration: .release)),
                .define("WIN32_LEAN_AND_MEAN", .when(platforms: [.windows])),
                .define("_WIN32_WINNT", to: "0x0601", .when(platforms: [.windows])),
                .define("_CRT_SECURE_NO_WARNINGS", .when(platforms: [.windows])),
            ],
            linkerSettings: [.linkedLibrary("m", .when(platforms: [.linux, .android]))]
        ),

        // librime's C API (its headers, from the official release, in include/); the library is the shell's to link
        // (`-L`): on macOS, ThirdParty/librime from `make deps`; on Windows, rime.lib from Windows/Scripts/fetch-librime.sh.
        .systemLibrary(name: "CRime"),

        // Swift wrapper around librime: level one (local pinyin).
        .target(name: "AllInOneIMERime", dependencies: ["CRime", "AllInOneIMECore"], swiftSettings: [.swiftLanguageMode(.v5)]),

        // The command line (`CLI.run`): level two from a terminal. Each shell runs it from its own main, with its platform.
        .target(name: "AllInOneIMECLI", dependencies: ["AllInOneIMECore"]),

        // The wire protocol (docs/wire-protocol-v1.md), transport-independent: every platform's, as the core is.
        .target(name: "AllInOneIMEWire", dependencies: ["AllInOneIMECore"]),

        // The tests' helpers, for the core's tests and a shell's; the tests' only, never a shell's app. It uses the core's
        // public API (and `package`: Prompt.liveDataRule), so it builds in release too.
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

        // AllInOneIMEQuickJS first. Swift Build (SwiftPM's default build system in Swift 6.4) takes a target into a
        // product once, by the first edge it meets to it in the dependency graph, with that edge's platform condition.
        // Listed after AllInOneIMECore, the first edge would be the core's, which is off Apple platforms only, and the
        // tests' own (unconditional) one would be ignored: on the Mac the link fails, QuickJSEngine's protocol witness
        // table undefined. It fails loudly, never quietly. (No upstream issue found to link; observed with Swift 6.4,
        // 2026-10.) A shell on Apple platforms that depends on the AllInOneIMEQuickJS product needs it before the core
        // the same way.
        .testTarget(name: "AllInOneIMECoreTests", dependencies: ["AllInOneIMEQuickJS", "AllInOneIMECore", "AllInOneIMETestSupport"],
                    // Specs for the macOS shell's self-test, and the API Settings v2's acceptance tests were written against.
                    exclude: ["Acceptance/ICloudSyncAppLevelCases.md", "Acceptance/SettingsV2-API.md"],
                    resources: [.copy("Fixtures")]),
        // The wire protocol's goldens (WireGoldens/*.jsonl), replayed against the server with a scripted provider.
        .testTarget(name: "AllInOneIMEWireTests", dependencies: ["AllInOneIMEWire", "AllInOneIMECore"],
                    resources: [.copy("WireGoldens")]),
    ]
)

// The core builds for iOS too (`make check-ios` in the repository's root).
package.platforms?.append(.iOS(.v17))

// Elsewhere (Linux, Windows, Android) the package is the core and its tests. librime is there on macOS and Windows,
// whose shells link its official builds; elsewhere it isn't yet.
#if !os(macOS)
#if !os(Windows)
let rimeOnly: Set = ["CRime", "AllInOneIMERime"]
package.targets.removeAll { rimeOnly.contains($0.name) }
package.products.removeAll { $0.name == "AllInOneIMERime" }
#endif
// The core's tests as they are: what they import of Apple's (os's lock, CryptoKit, CoreGraphics) is shimmed
// (Tests/LinuxShims), and the one that needs Darwin's posix_spawn is left out.
package.targets += [
    .target(name: "os", path: "Tests/LinuxShims/os"),
    .target(name: "CryptoKit", dependencies: [.product(name: "Crypto", package: "swift-crypto")], path: "Tests/LinuxShims/CryptoKit"),
    .target(name: "CoreGraphics", path: "Tests/LinuxShims/CoreGraphics"),
]
if let tests = package.targets.first(where: { $0.name == "AllInOneIMECoreTests" }) {
    tests.dependencies = ["AllInOneIMECore", "AllInOneIMETestSupport", "AllInOneIMEQuickJS", "os", "CryptoKit", "CoreGraphics"]
    tests.exclude += ["Acceptance/PluginLanguageAcceptanceTests.swift"]
    #if os(Windows)
    // Windows has no POSIX calls for the tests to check processes and files with (pid_t, kill, process groups, realpath,
    // lstat, opendir): those that use them are left out, and with them the ones that run bash scripts or use
    // ExtensionComposerTests' helpers. (ScriptFolder itself builds there: the tests that only load what it writes run.)
    tests.exclude += ["ExtensionTests.swift", "ExtensionRobustnessTests.swift", "ExtensionComposerTests.swift",
                      "ClickPickTests.swift", "ExtensionExamplesTests.swift", "Acceptance/QuestionHistoryAcceptanceTests.swift"]
    #endif
}
#endif
