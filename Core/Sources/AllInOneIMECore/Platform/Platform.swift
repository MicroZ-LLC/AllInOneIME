import Foundation

/// What the core needs from the system it runs on, in one place. A shell (the macOS app, later the Windows, iOS and
/// Android ones) installs its own at launch (`Platform.current = …`); tests may give stand-ins to the code they test, or
/// scope one to what they run (`Platform.$override.withValue(fake) { … }`).
/// By default the core uses what it is built with: Apple's frameworks on Apple platforms (`Platform/Apple/`), and
/// elsewhere neutral stand-ins: a heuristic language guess, the date rules alone, and no JavaScript, on-device model,
/// PDF text or secret store ("not supported on this platform").
public struct Platform: Sendable {
    /// API keys and the like (`APIKeys`).
    public var secrets: SecretStore
    /// JavaScript, for plugins (`PluginScript`) and `@js` (`InlineCode`).
    public var scripts: any ScriptEngine
    /// The on-device model (`Provider.apple`); one that can be held to a schema is an `AppleGuidedBackend` too.
    public var onDeviceModel: any OnDeviceModel
    /// The language a text is written in (`Language.of`, `AppleModel.unsupportedLanguage`).
    public var languages: any LanguageIdentifier
    /// Dates and times written in a text (`ReminderParser.detect`).
    public var dates: any DateDetector
    /// A PDF's text (`WebReader`).
    public var pdf: any PDFTextExtractor
    /// Programs: commands, scripts, plugins, `@py`, `@js`, AWS `credential_process`, a language pack's archive.
    public var processes: any ProcessLauncher
    /// Atomic swaps, private writes, modification dates, the Trash.
    public var files: any FileOps

    public init(secrets: SecretStore = Platform.systemSecrets, scripts: any ScriptEngine = Platform.systemScripts,
                onDeviceModel: any OnDeviceModel = Platform.systemOnDeviceModel,
                languages: any LanguageIdentifier = Platform.systemLanguages, dates: any DateDetector = Platform.systemDates,
                pdf: any PDFTextExtractor = Platform.systemPDF, processes: any ProcessLauncher = Platform.systemProcesses,
                files: any FileOps = SystemFileOps()) {
        self.secrets = secrets
        self.scripts = scripts
        self.onDeviceModel = onDeviceModel
        self.languages = languages
        self.dates = dates
        self.pdf = pdf
        self.processes = processes
        self.files = files
    }

    /// The platform in use: the task's `override` if it has one, else the installed one. Set (installed) at launch,
    /// before anything else reads it.
    public static var current: Platform {
        get { override ?? installed.withLock { $0 } }
        set { installed.withLock { $0 = newValue } }
    }

    /// A stand-in for what one task (and the tasks it starts) does, leaving the installed platform, and the tests running
    /// beside it, alone: `Platform.$override.withValue(fake) { … }`. Work handed to another thread (a dispatch queue)
    /// doesn't see it; the core reads `Platform.current` before it hands work off.
    @TaskLocal public static var override: Platform?

    /// The installed platform (`current`'s setter).
    static let installed = Locked(initialState: Platform())
}

/// The secret store is the keychain seam `APIKeys` always had.
public typealias SecretStore = APIKeys.Keychain
/// The on-device model is the model seam `AppleModel` always had.
public typealias OnDeviceModel = AppleModelBackend

// MARK: - What the core is built with

extension Platform {
    /// The login keychain where there is one. (A shell entitled to the data protection keychain installs the store routed
    /// over it instead: `KeySync.system`.)
    public static var systemSecrets: SecretStore {
        #if canImport(Security)
        return .login
        #else
        return .unavailable
        #endif
    }

    /// JavaScriptCore where there is one.
    public static var systemScripts: any ScriptEngine {
        #if canImport(JavaScriptCore)
        return JavaScriptCoreEngine()
        #else
        return UnsupportedScriptEngine()
        #endif
    }

    /// Foundation Models on a system that has them (macOS 26), else a model that is never available.
    public static var systemOnDeviceModel: any OnDeviceModel {
        #if canImport(FoundationModels)
        if #available(macOS 26, iOS 26, *) { return FoundationModelsBackend() }
        #endif
        return UnsupportedBackend()
    }

    /// NaturalLanguage where there is one, else letters, stop words and accents.
    public static var systemLanguages: any LanguageIdentifier {
        #if canImport(NaturalLanguage)
        return NaturalLanguageIdentifier()
        #else
        return HeuristicLanguageIdentifier()
        #endif
    }

    /// NSDataDetector where there is one, else none (the reminder parser's own rules still read dates).
    public static var systemDates: any DateDetector {
        #if canImport(Darwin)
        return DataDetectorDates()
        #else
        return RulesOnlyDateDetector()
        #endif
    }

    /// PDFKit where there is one.
    public static var systemPDF: any PDFTextExtractor {
        #if canImport(PDFKit)
        return PDFKitTextExtractor()
        #else
        return UnsupportedPDFTextExtractor()
        #endif
    }

    /// Foundation's `Process` on the desktop systems; none on iOS and Android, which have no child processes for apps.
    public static var systemProcesses: any ProcessLauncher {
        #if os(macOS) || os(Linux) || os(Windows)
        return FoundationProcessLauncher()
        #else
        return NoProcessLauncher()
        #endif
    }
}
