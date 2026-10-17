import AllInOneIMECore
import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    /// Settings → AI Provider with the API key field focused (Settings → Assistant when a provider needs a key).
    static let allInOneIMEFocusAPIKey = Notification.Name("AllInOneIMEFocusAPIKey")
}

/// What Settings → Assistant's requests run with (`AssistantModel`, `AIConfig`): the request on the on-device model first
/// (`AIConfigService`), its answer checked against the settings as they are and shown to confirm, then applied through
/// the config file (as the input menu and Settings save), with undo for ten minutes. Test Connection runs after the
/// provider changed, and Settings opens at the key field when a provider needs a key: keys never go through the AI.
@MainActor
enum AIConfigSession {
    /// The config file the changes go to (the self-test's own).
    static var url = Config.defaultURL
    static var service = AIConfigService()
    /// What undoes the last changes, kept for this process (not past quitting).
    static var lastApplied: AIConfig.Applied?
    static var now: () -> Date = Date.init
    /// What the checks need, for what the user typed (the self-test gives its own). Built off the main thread where it
    /// reads the keychain items' attributes, the login shell's variables or the apps on disk.
    static var environment: (_ typed: String) async -> AIConfig.Environment = { await liveEnvironment(typed: $0) }
    /// Settings → AI Provider with `provider`'s key field focused (shown there even when another provider is in use; the
    /// self-test records it).
    static var openKeyField: (Provider) -> Void = { provider in
        SettingsWindow.shared.show(page: .provider)
        // Once the page is up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NotificationCenter.default.post(name: .allInOneIMEFocusAPIKey, object: nil, userInfo: ["provider": provider.rawValue])
        }
    }
    /// Where each provider's key is: the keychain item's attributes (the key isn't read, nothing is asked), else the
    /// login shell's variables (`APIKeys.source`). Settings' "Saved in the keychain" and the Assistant's checks
    /// all ask here, off the main thread; the self-test gives its own (the user's keychain is never asked).
    static var keySource: @Sendable (Provider) -> APIKeys.Source = { APIKeys.source($0) }

    /// The providers with a key, by `lookup` (`keySource`, taken on the main thread).
    nonisolated static func providersWithKey(_ lookup: @Sendable (Provider) -> APIKeys.Source) -> Set<Provider> {
        Set(Provider.allCases.filter { $0 != .bedrock && $0 != .apple && lookup($0) != .none })
    }

    private static var prewarmed: Date?

    /// As Settings → Assistant shows: the on-device model loaded and the checks' view of this Mac (the apps, the
    /// keychain's attributes) read ahead, at most once a minute, so the request that follows doesn't wait for them.
    /// Nothing is sent.
    static func prewarmIfDue() {
        guard prewarmed.map({ Date().timeIntervalSince($0) > 60 }) ?? true else { return }
        prewarmed = Date()
        service.prewarm()
        Task { @MainActor in _ = await environment("") }
    }

    /// Test Connection, as Settings runs it, on the config file as it is now: what it said, and whether it worked.
    static var testConnection: (URL) async -> (ok: Bool, line: String) = { url in await runSettingsTest(url) }

    /// The checks' view of this Mac: the language packs installed, the apps, the AWS profiles (names only, read when
    /// asked), the models Settings offers, the providers offered and which have a key (from the keychain item's
    /// attributes: no key is read, nothing asked), the hosts of the services Settings offers, and what the user typed.
    static func liveEnvironment(typed: String) async -> AIConfig.Environment {
        // What the app's own objects hold, here on the main thread.
        let installed = Set(Language.allCases.filter { LanguagePackManager.shared.isUsable($0) })
        let models = knownModels()
        let offered = Provider.offered
        let language = UIText.language
        let hosts = AIConfig.compatibleHosts.union(CompatibleService.all.compactMap { URL(string: $0.baseURL)?.host?.lowercased() })
        let others = RecentApps.apps + Array(((try? Config.load(from: url)) ?? .default).appProfiles.keys)
        let cached = cachedApps.flatMap { Date().timeIntervalSince($0.date) < 60 && $0.language == language ? $0.catalog : nil }
        // Off it: the keychain items' attributes and the login shell's variables (`keySource`), the apps on disk.
        let lookup = keySource
        let (keyed, apps) = await Task.detached(priority: .userInitiated) {
            (providersWithKey(lookup), cached ?? scanApps(adding: others, language: language))
        }.value
        if cached == nil { cachedApps = (Date(), language, apps) }
        let drive = ICloudSyncController.shared.engine.folder
        return AIConfig.Environment(
            packInstalled: { installed.contains($0) }, apps: apps, awsProfiles: { AIConfig.awsProfiles().map(\.name) },
            knownModels: { models[$0] ?? [] }, offeredProviders: offered, hasKey: { keyed.contains($0) }, language: language,
            typedText: typed, knownHosts: hosts, iCloudDriveAvailable: { drive.isAvailable })
    }

    /// The models Settings offers for each provider (and the OpenAI-compatible services' own, where it names one).
    static func knownModels() -> [Provider: [String]] {
        var models: [Provider: [String]] = [:]
        for provider in [Provider.bedrock, .anthropic, .gemini, .openai] {
            models[provider] = SuggestedModel.suggested(for: provider).map(\.id)
        }
        models[.openai, default: []] += CompatibleService.all.compactMap(\.model).filter { !(models[.openai] ?? []).contains($0) }
        return models
    }

    private static var cachedApps: (date: Date, language: String, catalog: AIConfig.AppCatalog)?

    /// The apps in /Applications (and its Utilities), /System/Applications and ~/Applications, and `others` (typed in
    /// lately, with settings of their own), each with its names (as Finder shows it, its bundle's, in Chinese where the
    /// app has one: 微信). Off the main thread; kept for a minute.
    nonisolated static func scanApps(adding others: [String], language: String) -> AIConfig.AppCatalog {
        var apps: [AIConfig.AppCatalog.App] = []
        var seen = Set<String>()
        let fm = FileManager.default
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                       fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        for folder in folders {
            for name in (try? fm.contentsOfDirectory(atPath: folder)) ?? [] where name.hasSuffix(".app") {
                let url = URL(fileURLWithPath: folder).appendingPathComponent(name)
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, seen.insert(id.lowercased()).inserted else { continue }
                apps.append(AIConfig.AppCatalog.App(bundleID: id, names: names(of: bundle, at: url, language: language)))
            }
        }
        for id in others where seen.insert(id.lowercased()).inserted {
            // Elsewhere on the Mac (or not installed): by its bundle's names where macOS knows it, else its id.
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            let names = url.flatMap { url in Bundle(url: url).map { names(of: $0, at: url, language: language) } } ?? [id]
            apps.append(AIConfig.AppCatalog.App(bundleID: id, names: names))
        }
        return AIConfig.AppCatalog(apps: apps)
    }

    /// An app's names: its name in the interface language `language` when the app has one there (the preview shows the
    /// first: "微信" in the Chinese interface), as Finder shows it, its bundle's display name and name, and its Chinese
    /// name if it has one.
    nonisolated static func names(of bundle: Bundle, at url: URL, language: String = "en") -> [String] {
        var names = [FileManager.default.displayName(atPath: url.path), url.deletingPathExtension().lastPathComponent]
        let info = bundle.infoDictionary ?? [:]
        names += [info["CFBundleDisplayName"], info["CFBundleName"]].compactMap { $0 as? String }
        let chinese = localizedNames(at: url, in: ["zh-Hans", "zh_CN", "zh-CN", "zh_Hans", "zh"])
        names += chinese
        // English: Finder's name, as before. Another language: the app's own name in it, where its bundle has one.
        let interface = InterfaceLanguage.isChinese(language) ? chinese
            : language == "en" ? [] : localizedNames(at: url, in: [language, language.replacingOccurrences(of: "-", with: "_")])
        if let shown = interface.first { names.insert(shown, at: 0) }
        var seen = Set<String>()
        return names.map { $0.hasSuffix(".app") ? String($0.dropLast(4)) : $0 }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The display names and names in the app's `InfoPlist.strings` of `lprojs` (spellings of one language), in that order.
    nonisolated static func localizedNames(at url: URL, in lprojs: [String]) -> [String] {
        lprojs.flatMap { lproj -> [String] in
            let strings = url.appendingPathComponent("Contents/Resources/\(lproj).lproj/InfoPlist.strings")
            guard let table = NSDictionary(contentsOf: strings) as? [String: Any] else { return [] }
            return [table["CFBundleDisplayName"], table["CFBundleName"]].compactMap { $0 as? String }
        }
    }

    /// The lookups the on-device model may call: apps by name, the AWS profiles and their regions (read when it asks:
    /// names and regions only, never a credential), the language packs.
    static func tools(_ env: AIConfig.Environment) -> AIConfigService.Tools {
        let apps = env.apps
        let packs = Language.allCases.map { language in
            "\(language.rawValue) (\(language.englishName)): " + (LanguagePack.for(language) == nil ? "built in"
                : env.packInstalled(language) ? "installed" : "not installed")
        }.joined(separator: "\n")
        return AIConfigService.Tools(
            findApps: { query in
                let found = apps.search(query)
                return found.isEmpty ? "No app found for \"\(query)\"." : found.map { "\($0.name): \($0.bundleID)" }.joined(separator: "\n")
            },
            awsProfiles: {
                let profiles = AIConfig.awsProfiles()
                return profiles.isEmpty ? "No AWS profiles in ~/.aws."
                    : profiles.map { "\($0.name) (region \($0.region ?? "-"))" }.joined(separator: "\n")
            },
            languagePacks: { packs })
    }

    /// Settings' own Test Connection on the config file at `url` (a model that saves nothing): its line once it's done.
    static func runSettingsTest(_ url: URL) async -> (ok: Bool, line: String) {
        let model = SettingsModel(configURL: url, persists: false)
        model.runTest()
        for await status in model.$testStatus.values {
            switch status {
            case let .passed(line): return (true, line.replacingOccurrences(of: "\n", with: " · "))
            case let .failed(line): return (false, line)
            case .idle, .running: continue
            }
        }
        return (false, "")
    }
}

extension Provider {
    /// One whose requests need an API key the user enters (or, for the hosted service, a sign-in).
    var needsKey: Bool { self == .anthropic || self == .gemini || self == .openai }
}

