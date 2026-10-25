import Foundation

/// Script extensions in the settings document: the folders they are read from (`Config.extensionFolders`: one added by
/// its path, one removed; a folder found by the Mac's Spotlight hidden or shown again), and what is in them, each bundle
/// and script an item with its own fields: its switch (`Config.disabledExtensions`), a bundle's preferences
/// (`Config.extensionPreferences`; a password in the secret store, as a key is), its commands' switches, and under a
/// command that declares a completion source its switch (0.6.7.1 §2), or why it is refused.
extension SettingsSchema {
    mutating func scriptExtensions() -> [Field] {
        var fields: [Field] = []
        let store = store
        var folders = Field(id: "extensions.folders", kind: .items, label: tr("文件夹", "Folders"),
                            help: tr("选择放脚本或扩展包的文件夹", "Choose a folder of scripts or extension bundles"))
        folders.actions = [SettingsAction.add]
        (folders.textActions, folders.picker) = ([SettingsAction.add], .folder)
        // On Windows written as Windows writes a path (`%USERPROFILE%\…`); one typed so is taken (`typedOnWindows`).
        let windows = platform == .windows
        folders.placeholder = windows ? ExtensionStore.windowsShown(ExtensionStore.defaultFolder) : ExtensionStore.defaultFolder
        let listed = ExtensionStore.folders(config, found: [])
        folders.items = listed.map { folder in
            let detail = folder.found ? (folder.hidden ? tr("自动找到 · 已隐藏", "found · hidden") : tr("自动找到", "found")) : tr("添加的", "added")
            let action = folder.found ? (folder.hidden ? SettingsAction.show : SettingsAction.hide) : SettingsAction.remove
            return SettingsDocument.Item(id: folder.path, title: windows ? ExtensionStore.windowsShown(folder.path) : folder.path,
                                         detail: detail, actions: [action])
        }
        add(folders, to: &fields)
        handlers[folders.id] = { action in
            switch action.name {
            case SettingsAction.add:
                let path = action.value?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !path.isEmpty else {
                    return .failure(SettingsProblem(.badValue, field: action.field, message: SettingsService.badValue))
                }
                store.addExtensionFolder(windows ? ExtensionStore.typedOnWindows(path, home: NSHomeDirectory(),
                                                                                 environment: ProcessInfo.processInfo.environment)
                                                 : ExtensionStore.abbreviated(path))
            case SettingsAction.remove, SettingsAction.hide, SettingsAction.show:
                // By its id (its path as the config keeps it), or the folder however it was written when it was added
                // (on Windows a path in the home folder is kept from "~").
                let listed = ExtensionStore.folders(store.config, found: [])
                let item = windows ? action.item.map {
                    ExtensionStore.typedOnWindows($0, home: NSHomeDirectory(), environment: ProcessInfo.processInfo.environment)
                } : action.item
                guard let folder = listed.first(where: { $0.path == action.item })
                    ?? listed.first(where: { item != nil && ExtensionStore.isSameFolder($0.path, item!) }) else {
                    return .failure(SettingsProblem(.badValue, field: action.field, message: SettingsService.badValue))
                }
                store.removeExtensionFolder(folder)
            default:
                return .failure(SettingsProblem(.notChangeable, field: action.field, message: SettingsService.notChangeable))
            }
            return store.saveError.map { .failure(SettingsProblem(.failed, field: action.field, message: $0)) }
                ?? .success(SettingsActionOutcome())
        }

        var list = Field(id: "extensions.installed", kind: .items, label: tr("脚本扩展", "Script Extensions"))
        let index = extensions
        if index.bundles.isEmpty && index.commands.isEmpty {
            list.help = tr("还没有扩展。把脚本、扩展包或 Raycast 的脚本命令放进上面的文件夹就行。",
                           "No extensions yet. Put scripts, extension bundles or Raycast Script Commands in a folder above.")
        }
        var items: [SettingsDocument.Item] = []
        for bundle in index.bundles {
            let detail = [bundle.version, bundle.author, bundle.description].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            items.append(SettingsDocument.Item(id: "bundle:" + bundle.name, title: bundle.title, detail: detail.isEmpty ? nil : detail,
                                               fields: bundleFields(bundle, commands: index.commands.filter { $0.source.bundleName == bundle.name })))
        }
        for command in index.commands where command.source.bundleName == nil {
            var fields: [Field] = []
            add(toggle(Self.switchID(command.id), config.commandTrigger + command.name, UIText.summary(command), store.isEnabled(command.id)),
                to: &fields) { store.setEnabled(command.id, Self.bool($0)) }
            fields += extensionCompletionFields(command)
            items.append(SettingsDocument.Item(id: command.id, title: config.commandTrigger + command.name,
                                               detail: command.source == .raycast ? command.title + " · Raycast" : command.title,
                                               fields: fields))
        }
        list.items = items
        add(list, to: &fields)
        return fields
    }

    /// A bundle's switch, its preferences, and its commands' switches while it is on.
    mutating func bundleFields(_ bundle: ExtensionBundle, commands: [ScriptCommand]) -> [Field] {
        var fields: [Field] = []
        let store = store
        let on = store.isEnabled(bundle.name)
        add(toggle(Self.switchID(bundle.name), bundle.title, bundle.description, on), to: &fields) {
            store.setEnabled(bundle.name, Self.bool($0))
        }
        for preference in bundle.preferences {
            let id = "extensions.preference." + bundle.name + "." + preference.name
            let label = preference.title + (preference.required ? " *" : "")
            let value = store.preference(bundle, preference)
            switch preference.kind {
            case .textfield:
                var text = text(id, label, preference.description, value: value.isEmpty ? nil : value, placeholder: preference.defaultValue)
                text.optional = nil
                add(text, to: &fields) { store.config.extensionPreferences[bundle.name, default: [:]][preference.name] = $0.string ?? "" }
            case .checkbox:
                add(toggle(id, label, preference.description, value == "true"), to: &fields) {
                    store.config.extensionPreferences[bundle.name, default: [:]][preference.name] = Self.bool($0) ? "true" : "false"
                }
            case .dropdown:
                add(choice(id, label, preference.description, value: .string(value),
                           choices: preference.choices.map { (Choice($0.value, $0.title), nil) }), to: &fields) { new in
                    store.config.extensionPreferences[bundle.name, default: [:]][preference.name] = new.string ?? ""
                }
            case .password:
                let account = ExtensionBundle.Preference.keychainAccount(bundle: bundle.name, name: preference.name)
                let saved = APIKeys.hasKeychainKey(account: account)
                add(secret(id, label, preference.description,
                           state: saved ? .saved(ending: APIKeys.keyEnding(account: account)) : .missing,
                           missing: tr("还没有设置", "Not set yet"), removable: saved), to: &fields)
                handlers[id] = { action in
                    if action.name == SettingsAction.setKey, (action.key ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return .failure(SettingsProblem(.badValue, field: action.field, message: SettingsService.noKey))
                    }
                    let error = action.name == SettingsAction.setKey
                        ? store.setPreference(bundle, preference, action.key ?? "") : store.removePassword(bundle, preference)
                    return error.map { .failure(SettingsProblem(.failed, field: action.field, message: $0)) }
                        ?? .success(SettingsActionOutcome())
                }
            }
        }
        if on {
            for command in commands {
                add(toggle(Self.switchID(command.id), config.commandTrigger + command.name, UIText.summary(command), store.isEnabled(command.id)),
                    to: &fields) { store.setEnabled(command.id, Self.bool($0)) }
                fields += extensionCompletionFields(command)
            }
        }
        return fields
    }

    /// The completion source `command` declares (0.6.7.1 §2), under its switch: its own switch, off until turned on here,
    /// saying what it does (it runs the script in the background; one that queries gets what you type after its prefix),
    /// then why it can't show (the magic key), that it changed since it was turned on (an update of an extension source
    /// whose updates aren't trusted: off until turned on again), that Suggestions are off, or how it is doing (its items,
    /// last refresh, last error); or why its declaration is refused. None for a command that declares none.
    mutating func extensionCompletionFields(_ command: ScriptCommand) -> [Field] {
        var fields: [Field] = []
        switch command.completion {
        case nil:
            break
        case let .failure(refused)?:
            var field = Field(id: "extensions.completion.refused." + command.id, kind: .info, label: tr("没有用上的补全", "Completions not used"))
            field.help = refused.reason
            add(field, to: &fields)
        case let .success(source)?:
            let store = store
            let key = CompletionSourceKey(extension: command)
            let approval = config.approval(of: source, in: command)
            let holds = approval?.holds(for: source, of: command, follows: config.followsChanges(of: command)) ?? false
            var field = toggle("extensions.completion." + command.id, tr("建议", "Suggestions"), source.scriptSummary(), holds)
            if let reason = source.inactiveReason(config) {
                field.status = reason
            } else if approval != nil, !holds {
                field.status = CompletionSource.scriptChanged
            } else if holds, config.suggestions == false {
                field.status = tr("建议关着，这些补全不会出现：在「通用」里打开。", "Suggestions are off, so these completions don't show: turn them on in General.")
            } else if holds, let status = suggestionStatuses.first(where: { $0.plugin == key.plugin && $0.source == key.source }) {
                field.status = status.summary()
            }
            add(field, to: &fields) { store.config.setCompletionSource(source, of: command, enabled: Self.bool($0)) }
        }
        return fields
    }

    /// A bundle's or a command's switch: "extensions.on." and its id in `Config.disabledExtensions`.
    static func switchID(_ id: String) -> String { "extensions.on." + id }
}
