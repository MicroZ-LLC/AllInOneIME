import Foundation

extension SettingsStore {
    /// Where each provider's key comes from, the last 4 characters kept with a saved one (`APIKeys.keyEnding`) and the
    /// host a saved one is tied to (`APIKeys.savedHost`: a key row shows it as set only for a base URL of that host,
    /// `APIKeys.Source.sent(by:to:savedFor:)`); the key itself isn't read. The first look may ask the user's shell for
    /// its variables: not on a thread that draws.
    public static func keyStates(_ providers: [Provider] = Provider.allCases.filter { $0 != .bedrock },
                                 lookup: (Provider) -> APIKeys.Source = { APIKeys.source($0) })
        -> (sources: [Provider: APIKeys.Source], endings: [Provider: String], hosts: [Provider: String]) {
        let sources = Dictionary(uniqueKeysWithValues: providers.map { ($0, lookup($0)) })
        let endings = Dictionary(uniqueKeysWithValues: providers.compactMap { provider in
            APIKeys.keyEnding(account: provider.rawValue).map { (provider, $0) }
        })
        let hosts = Dictionary(uniqueKeysWithValues: providers.compactMap { provider in
            APIKeys.savedHost(provider).map { (provider, $0) }
        })
        return (sources, endings, hosts)
    }
}
