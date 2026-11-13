import AllInOneIMECore
import Foundation

/// Where a CLI that only came with a desktop app is (`ClaudeSessionMac.desktopBundled`: the Claude app's Claude Code, the
/// ChatGPT app's codex, agy where its installer puts it): the apps' own layout, or a lookup a test puts in its place
/// (`inject`), so that on a Mac with those apps a test's own CLIs, or none, are what is found. Nothing in the environment
/// switches it, and the input method never injects one: there, the layout is looked at.
public enum DesktopCLILookup {
    private static let injected = Locked<(@Sendable (SessionAgent) -> URL?)?>(initialState: nil)

    /// `lookup` in place of the apps' layout from now on; nil: the layout again.
    public static func inject(_ lookup: (@Sendable (SessionAgent) -> URL?)?) {
        injected.withLock { $0 = lookup }
    }

    /// `agent`'s program in a desktop app: what the injected lookup says when there is one, else `layout` (the apps').
    public static func bundled(_ agent: SessionAgent, layout: (SessionAgent) -> URL?) -> URL? {
        if let lookup = injected.withLock({ $0 }) { return lookup(agent) }
        return layout(agent)
    }
}
