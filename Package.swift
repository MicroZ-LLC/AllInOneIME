// swift-tools-version: 6.0
import PackageDescription

// The macOS shell: the input method, its command line, AllInOneIME Settings and the installer. What every platform
// shares is the core, Core/ (a package of its own).

/// The core's package: every product of it goes through `core`, so that when the core comes from its own repository
/// (`.package(url:)`, whose identity is "allinoneime-core") only this changes.
let corePackage = "core"
func core(_ product: String) -> Target.Dependency { .product(name: product, package: corePackage) }

/// Official librime release build, unpacked by `make deps` into ThirdParty: $ALLINONEIME_THIRDPARTY if it is set (an
/// absolute path), else ThirdParty here. The one rule, as the Makefile (which documents it), the Rime tests and
/// Scripts/make-dmg.sh have it.
let thirdParty = Context.environment["ALLINONEIME_THIRDPARTY"].flatMap { $0.isEmpty ? nil : $0 }
    ?? Context.packageDirectory + "/ThirdParty"
let rimeLib = thirdParty + "/librime/dist/lib"

/// FoundationModels (Apple's on-device model, macOS 26) is weak-linked: the app still runs on macOS 14. On everything
/// here that links the core (Scripts/check-weak-links.sh checks the built binaries).
let weakFoundationModels = LinkerSetting.unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"],
                                                     .when(platforms: [.macOS]))

let package = Package(
    name: "AllInOneIME",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AllInOneIME", targets: ["AllInOneIME"]),
        .executable(name: "allinoneime-cli", targets: ["allinoneime-cli"]),
    ],
    dependencies: [.package(path: "Core")],
    targets: [
        // The macOS shell's library: what only the Mac has (Carbon key layouts, code signing, Spotlight, AppleScript,
        // the login shell, git through posix_spawn, the updater's install) and `Platform.mac`, which the input method, its
        // command line and the installer install at launch.
        .target(name: "AllInOneIMEMac", dependencies: [core("AllInOneIMECore")]),

        // The input method process (bundled into AllInOneIME.app by the Makefile).
        // AppKit/InputMethodKit glue is written in Swift 5 mode: IMK predates Swift concurrency
        // annotations and every callback arrives on the main thread anyway.
        .executableTarget(
            name: "AllInOneIME",
            dependencies: [core("AllInOneIMECore"), "AllInOneIMEMac", core("AllInOneIMERime")],
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
                weakFoundationModels,
                // librime.1.dylib is copied into Contents/Frameworks by the Makefile.
                .unsafeFlags(["-L\(rimeLib)", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"], .when(platforms: [.macOS])),
                // The debug build (the tests run it as a child process) finds librime where it is. The end-to-end
                // tests that run it (the core's PluginLanguageAcceptanceTests, this package's
                // ExtensionSourcesAcceptanceTests) set DYLD_LIBRARY_PATH to <their package>/ThirdParty/librime/dist/lib,
                // which for the core's (Core/) is a folder that doesn't exist, and with ALLINONEIME_THIRDPARTY set isn't
                // where librime is: this rpath, to the folder the build linked, is what lets the binary start there.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", rimeLib], .when(platforms: [.macOS], configuration: .debug)),
            ]
        ),

        // Developer tool: run level two (translate/polish) from the terminal (the core's AllInOneIMECLI, on the Mac's platform).
        .executableTarget(
            name: "allinoneime-cli",
            dependencies: [core("AllInOneIMECLI"), core("AllInOneIMECore"), "AllInOneIMEMac"],
            linkerSettings: [weakFoundationModels]
        ),

        // AllInOneIME Settings (「AllInOneIME 设置」): a launcher in ~/Applications that opens the settings window.
        .executableTarget(name: "AllInOneIMESettings", dependencies: [core("AllInOneIMEText")], swiftSettings: [.swiftLanguageMode(.v5)]),

        // 「安装 AllInOneIME」: the installer on the release disk image (`make dmg`). It carries both
        // apps and installs them like `make install`; it uninstalls them too.
        .executableTarget(
            name: "AllInOneIMEInstaller",
            dependencies: [core("AllInOneIMECore"), "AllInOneIMEMac"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [weakFoundationModels]
        ),

        // The macOS shell's tests: its library's, and those that read the app's own files (the Info.plists, the input
        // method's sources). The core's tests are Core's.
        .testTarget(
            name: "AllInOneIMEMacTests",
            dependencies: ["AllInOneIMEMac", core("AllInOneIMECore"), core("AllInOneIMETestSupport")],
            linkerSettings: [weakFoundationModels]
        ),
        .testTarget(
            name: "AllInOneIMERimeTests",
            dependencies: [core("AllInOneIMERime"), core("AllInOneIMECore")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                weakFoundationModels,
                .unsafeFlags(["-L\(rimeLib)", "-Xlinker", "-rpath", "-Xlinker", rimeLib], .when(platforms: [.macOS])),
            ]
        ),
    ]
)
