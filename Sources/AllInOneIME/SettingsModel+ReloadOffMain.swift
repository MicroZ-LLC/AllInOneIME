import AllInOneIMECore
import Foundation

extension SettingsModel {
    /// `reloadIfChanged`, the file read off the main thread (AGENTS.md, rule 6: the input method's main thread is the
    /// one every app's typing waits for): the config file read again if something else changed it, then `done`, on the
    /// main thread, with the settings as the file has them: the start come back to, a card pointed at, the window opened
    /// (again, or on settings the start built) or become key.
    func reloadIfChangedOffMain(then done: @escaping @MainActor () -> Void) {
        guard persists else { return done() }
        let (url, date) = (store.configURL, store.fileDate)
        Task { [weak self] in
            let read = await Task.detached(priority: .userInitiated) { SettingsStore.FileRead(url, since: date) }.value
            if let read { self?.store.reloadIfChanged(read) }
            done()
        }
    }

    /// `reloadIfChangedOffMain` for the window become key: then, with the provider as the file has it, the AWS profile's
    /// line read again (back from Terminal after `aws sso login`, say).
    func reloadIfChangedOffMainForKeyWindow() {
        reloadIfChangedOffMain { [weak self] in
            guard let self, config.provider == .bedrock else { return }
            aws.refresh(profile: config.awsProfile)
        }
    }

    /// `reloadIfChangedOffMain` for the key field Settings is asked to show (`note`: `allInOneIMEFocusAPIKey`): then
    /// `done` with the provider it names (none: not called) and whether that is the one in use, as the file has it.
    func reloadIfChangedOffMain(showingKeyOf note: Notification, then done: @escaping @MainActor (Provider, _ inUse: Bool) -> Void) {
        let provider = (note.userInfo?["provider"] as? String).flatMap(Provider.init(rawValue:))
        reloadIfChangedOffMain { [weak self] in
            guard let self, let provider else { return }
            done(provider, provider == config.provider)
        }
    }
}

extension SettingsWindow {
    /// The window opens on `model`'s settings, kept from before (closed and opened again, or the start's): shown at once
    /// as they are, in their interface language, and the config file read again off the main thread if something else
    /// changed it (`reloadIfChangedOffMain`: opening Settings never reads it while keys wait); the interface language
    /// and the window's title follow what it has.
    func readAgain(_ model: SettingsModel) {
        UIText.choice = model.config.uiLanguage
        model.reloadIfChangedOffMain { [weak self] in
            guard UIText.choice != model.config.uiLanguage else { return }
            UIText.choice = model.config.uiLanguage
            self?.window?.title = Self.title
        }
    }
}
