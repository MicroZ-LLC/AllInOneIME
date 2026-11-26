import AllInOneIMECore
import Foundation

extension SettingsModel {
    /// `reloadIfChanged`, the file read off the main thread (AGENTS.md, rule 6: the input method's main thread is the
    /// one every app's typing waits for): the config file read again if something else changed it, then `done`, on the
    /// main thread, with the settings as the file has them. For what isn't the window's own first showing: the start
    /// come back to, a card pointed at.
    func reloadIfChangedOffMain(then done: @escaping @MainActor () -> Void) {
        guard persists else { return done() }
        let (url, date) = (store.configURL, store.fileDate)
        Task { [weak self] in
            let read = await Task.detached(priority: .userInitiated) { SettingsStore.FileRead(url, since: date) }.value
            if let read { self?.store.reloadIfChanged(read) }
            done()
        }
    }
}
