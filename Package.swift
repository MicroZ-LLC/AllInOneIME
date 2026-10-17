// swift-tools-version: 6.0
import PackageDescription

/// Official librime release build, unpacked by `make deps` (see Makefile).
let rimeLib = Context.packageDirectory + "/ThirdParty/librime/dist/lib"

let package = Package(
    name: "AllInOneIME",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AllInOneIME", targets: ["AllInOneIME"]),
        .executable(name: "allinoneime-cli", targets: ["allinoneime-cli"]),
        // The platform-neutral core, for the other platforms' shells (and its own scheme: `make check-ios`).
        .library(name: "AllInOneIMECore", targets: ["AllInOneIMECore"]),
    ],
    // CryptoKit's API everywhere: on Apple platforms swift-crypto is CryptoKit itself (re-exported), elsewhere its own.
    dependencies: [.package(url: "https://github.com/apple/swift-crypto.git", from: "5.0.0")],
    targets: [
        // The interface text and its language (UIString, InterfaceText, InterfaceLanguage) and the config's uiLanguage
        // (ConfigFile): all AllInOneIME Settings needs, so it doesn't link AllInOneIMECore. AllInOneIMECore re-exports it.
        .target(name: "AllInOneIMEText"),

        // Pure logic: AWS auth, Bedrock streaming client, prompt/parser, two-level composer, key maps. Platform-neutral:
        // what it needs of the system goes through `Platform` (Sources/AllInOneIMECore/Platform/), with Apple's
        // frameworks in Platform/Apple/ (each file under `#if canImport`); Scripts/check-core-portable.sh keeps it so.
        // FoundationModels (Apple's on-device model, macOS 26) is weak-linked: the app still runs on macOS 14.
        .target(
            name: "AllInOneIMECore",
            dependencies: ["AllInOneIMEText", .product(name: "Crypto", package: "swift-crypto")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"], .when(platforms: [.macOS]))]
        ),

        // The macOS shell's library: what only the Mac has (Carbon key layouts, code signing, Spotlight, AppleScript,
        // the login shell, git through posix_spawn, the updater's install) and `Platform.mac`, which the input method, its
        // command line and the installer install at launch.
        .target(name: "AllInOneIMEMac", dependencies: ["AllInOneIMECore"]),

        // librime's C API; header and dylib come from ThirdParty/librime.
        .systemLibrary(name: "CRime", path: "Sources/CRime"),

        // Swift wrapper around librime: level one (local pinyin).
        .target(
            name: "AllInOneIMERime",
            dependencies: ["CRime", "AllInOneIMECore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.unsafeFlags(["-L\(rimeLib)"], .when(platforms: [.macOS]))]
        ),

        // The input method process (bundled into AllInOneIME.app by the Makefile).
        // AppKit/InputMethodKit glue is written in Swift 5 mode: IMK predates Swift concurrency
        // annotations and every callback arrives on the main thread anyway.
        .executableTarget(
            name: "AllInOneIME",
            dependencies: ["AllInOneIMECore", "AllInOneIMEMac", "AllInOneIMERime"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("InputMethodKit"),
                .linkedFramework("Carbon"),
                // Voice input: microphone capture and on-device speech recognition.
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                // @reminder: Apple Reminders.
                .linkedFramework("EventKit"),
                // librime.1.dylib is copied into Contents/Frameworks by the Makefile.
                .unsafeFlags(["-L\(rimeLib)", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"], .when(platforms: [.macOS])),
            ]
        ),

        // Developer tool: run level two (translate/polish) from the terminal.
        .executableTarget(name: "allinoneime-cli", dependencies: [
            "AllInOneIMECore", .target(name: "AllInOneIMEMac", condition: .when(platforms: [.macOS])),
        ]),

        // AllInOneIME Settings (「AllInOneIME 设置」): a launcher in ~/Applications that opens the settings window.
        .executableTarget(name: "AllInOneIMESettings", dependencies: ["AllInOneIMEText"], swiftSettings: [.swiftLanguageMode(.v5)]),

        // 「安装 AllInOneIME」: the installer on the release disk image (`make dmg`). It carries both
        // apps and installs them like `make install`; it uninstalls them too.
        .executableTarget(
            name: "AllInOneIMEInstaller",
            dependencies: ["AllInOneIMECore", "AllInOneIMEMac"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // The core alone: what tests the macOS shell's library is in AllInOneIMEMacTests.
        .testTarget(name: "AllInOneIMECoreTests", dependencies: ["AllInOneIMECore"], resources: [.copy("Fixtures")]),
        // Timing, PackData, ComposerTestSupport and ScriptFolder are AllInOneIMECoreTests' (linked here).
        .testTarget(name: "AllInOneIMEMacTests", dependencies: ["AllInOneIMEMac"]),
        .testTarget(
            name: "AllInOneIMERimeTests",
            dependencies: ["AllInOneIMERime"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.unsafeFlags(["-L\(rimeLib)", "-Xlinker", "-rpath", "-Xlinker", rimeLib], .when(platforms: [.macOS]))]
        ),
    ]
)

// The core builds for iOS too (`make check-ios`).
package.platforms?.append(.iOS(.v17))

// Elsewhere (Linux, Windows, Android) the package is the core, its tests and the CLI: the input method, its two
// apps, the macOS shell's library and librime (an official macOS build in ThirdParty) are macOS's.
#if !os(macOS)
let macOnly: Set = ["CRime", "AllInOneIMERime", "AllInOneIMEMac", "AllInOneIMEMacTests", "AllInOneIME", "AllInOneIMESettings",
                    "AllInOneIMEInstaller", "AllInOneIMERimeTests"]
package.targets.removeAll { macOnly.contains($0.name) }
package.products.removeAll { $0.name == "AllInOneIME" }
package.targets.first { $0.name == "allinoneime-cli" }?.dependencies = ["AllInOneIMECore"]
// The core's tests as they are: what they import of Apple's (os's lock, CryptoKit, CoreGraphics) is shimmed
// (Tests/LinuxShims), and the one that needs Darwin's posix_spawn is left out.
package.targets += [
    .target(name: "os", path: "Tests/LinuxShims/os"),
    .target(name: "CryptoKit", dependencies: [.product(name: "Crypto", package: "swift-crypto")], path: "Tests/LinuxShims/CryptoKit"),
    .target(name: "CoreGraphics", path: "Tests/LinuxShims/CoreGraphics"),
]
if let tests = package.targets.first(where: { $0.name == "AllInOneIMECoreTests" }) {
    tests.dependencies = ["AllInOneIMECore", "os", "CryptoKit", "CoreGraphics"]
    tests.exclude += ["Acceptance/PluginLanguageAcceptanceTests.swift"]
}
#endif
