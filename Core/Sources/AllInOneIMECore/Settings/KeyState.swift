import Foundation

/// Whether a key is set, as a key row shows it: saved in the secret store (with its last 4 characters when they were
/// kept, `APIKeys.ending(of:)`), set in the user's shell, or not set. The key itself is never read for this.
public enum KeyState: Equatable, Sendable {
    /// Not looked up yet.
    case loading
    case saved(ending: String?)
    /// In the user's shell, under this variable.
    case shell(String)
    case missing

    public init(_ source: APIKeys.Source?, ending: String?) {
        switch source {
        case .keychain?: self = .saved(ending: ending)
        case let .environment(name)?: self = .shell(name)
        case .none?: self = .missing
        case nil: self = .loading
        }
    }

    public var isSet: Bool {
        switch self {
        case .saved, .shell: return true
        case .loading, .missing: return false
        }
    }

    /// "✓ Saved · ends in a1b2", "✓ From $OPENAI_API_KEY", or `missing` ("No API key yet").
    public func text(missing: String) -> String {
        switch self {
        case .loading: return ""
        case let .saved(ending): return "✓ " + tr("已保存", "Saved") + (ending.map { tr(" · 结尾 \($0)", " · ends in \($0)") } ?? "")
        case let .shell(name): return "✓ " + tr("来自 $\(name)", "From $\(name)")
        case .missing: return missing
        }
    }
}
