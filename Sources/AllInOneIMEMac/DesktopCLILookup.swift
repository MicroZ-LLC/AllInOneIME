import AllInOneIMECore
import Foundation

/// Resolve a CLI from the shell first, then from a desktop app. Tests inject both lookups.
public enum DesktopCLILookup {
    public static func resolve(_ agent: SessionAgent,
                               shell: (SessionAgent) -> URL?, bundled: (SessionAgent) -> URL?) -> URL? {
        shell(agent) ?? bundled(agent)
    }
}
