import Foundation

extension ICloudSync {
    /// What the checks need of this Mac: which providers have a key (asked without reading it), the AWS profiles, the
    /// providers offered. The tests give their own: the checks ask nothing of this Mac but through here (never the
    /// keychain themselves).
    public struct Environment: Sendable {
        /// Where each provider's key comes from (`APIKeys.source`: the keychain item's attributes, never the key): one
        /// set in the login shell counts only for a base URL it goes to (`APIKeys.Source.sent(by:to:)`), as in Settings.
        public var keySource: @Sendable (Provider) -> APIKeys.Source
        /// The host each provider's key in the keychain was saved for (`APIKeys.savedHost`: the item's attributes; nil:
        /// tied to none): it counts only for a base URL of that host (`APIKeys.Source.sent(by:to:savedFor:)`), as in
        /// Settings.
        public var savedHost: @Sendable (Provider) -> String?
        /// The AWS profiles in ~/.aws (nil: not checked).
        public var awsProfiles: (@Sendable () -> [String])?
        public var offeredProviders: [Provider]
        /// The interface languages this Mac's app ships (`InterfaceLanguage.shipped`): a `uiLanguage` naming another is
        /// refused.
        public var interfaceLanguages: [String]

        /// `hasKey`: whether each provider has a key, as if the keychain held it; `keySource`, where given, where it
        /// comes from instead (this Mac's: `APIKeys.source`); `savedHost`, the host a key in the keychain was saved for
        /// (this Mac's: `APIKeys.savedHost`; not given: tied to none, it counts for any base URL).
        public init(hasKey: @escaping @Sendable (Provider) -> Bool = { _ in true },
                    keySource: (@Sendable (Provider) -> APIKeys.Source)? = nil,
                    savedHost: @escaping @Sendable (Provider) -> String? = { _ in nil },
                    awsProfiles: (@Sendable () -> [String])? = nil,
                    offeredProviders: [Provider] = Provider.allCases, interfaceLanguages: [String] = InterfaceLanguage.builtIn) {
            self.keySource = keySource ?? { hasKey($0) ? .keychain : .none }
            self.savedHost = savedHost
            self.awsProfiles = awsProfiles
            self.offeredProviders = offeredProviders
            self.interfaceLanguages = interfaceLanguages
        }

        /// `provider`'s key as it counts for its requests with `config`'s base URL (`APIKeys.Source.sent(by:in:)`, asked
        /// of this environment alone): none where it isn't sent there.
        func keySent(by provider: Provider, in config: Config) -> APIKeys.Source {
            keySource(provider).sent(by: provider, to: HTTPProviders.host(of: config.settings(for: provider)), savedFor: savedHost(provider))
        }
    }
}
