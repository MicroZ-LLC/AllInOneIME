import Foundation

/// A platform a settings window runs on: a field or a choice only some have says which (`SettingsDocument.Field
/// .platforms`), and a document made for one leaves the others' out.
public enum SettingsPlatform: String, Codable, CaseIterable, Sendable {
    case mac
    case windows
}

/// The settings as a document a settings window draws without knowing them: sections of fields, each with its kind,
/// value, choices and text in the interface language, only those that apply now on the platform it is made for
/// (`SettingsService.document`). Windows' Settings app reads it over the wire (protocol v1's settings messages) and stays
/// thin: the core decides the labels, which fields show, and whether a change is valid (`SettingsService.set`).
///
/// In JSON (keys sorted, as the wire writes it), a field leaves out what it doesn't have: `help`, `choices`, the bounds….
public struct SettingsDocument: Codable, Equatable, Sendable {
    /// The interface language the text is in (`UIText.language`): "zh-Hans", "en", "fr"…
    public var language: String
    public var platform: SettingsPlatform
    /// Why the config file can't be read: nothing can be changed until it is fixed (every field is read-only), and the
    /// file is left as it is.
    public var loadError: String?
    /// Why the last save failed.
    public var saveError: String?
    public var sections: [Section]

    public init(language: String, platform: SettingsPlatform, loadError: String? = nil, saveError: String? = nil,
                sections: [Section]) {
        self.language = language
        self.platform = platform
        self.loadError = loadError
        self.saveError = saveError
        self.sections = sections
    }

    /// The field `id`, wherever it is.
    public func field(_ id: String) -> Field? {
        for section in sections {
            if let field = section.fields.first(where: { $0.id == id }) { return field }
        }
        return nil
    }

    /// A page of settings, as the Mac's window has them: General, Input, AI Provider….
    public struct Section: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        /// A note under the section.
        public var footer: String?
        public var fields: [Field]

        public init(id: String, title: String, footer: String? = nil, fields: [Field]) {
            self.id = id
            self.title = title
            self.footer = footer
            self.fields = fields
        }
    }

    /// What a field is, and so what its value is and what it takes (`SettingsService.set`).
    public enum Kind: String, Codable, Sendable {
        /// On or off: a Bool.
        case toggle
        /// A whole number between `min` and `max`, in steps of `step`.
        case integer
        /// A number between `min` and `max` (`step`: what a slider moves by); null when `optional` and off.
        case number
        /// A string; null (`optional`) leaves it unset, so that the default (`placeholder`) applies. `choices`, if
        /// any, are suggestions: any text is taken.
        case text
        /// One of `choices`' values (null when one of them is: "follow the system").
        case choice
        /// Some of `choices`' values, each once, between `minCount` and `maxCount` of them; `ordered`: in the order
        /// given, which matters (the first is the default).
        case choices
        /// A list of strings of one's own; `ordered`: their order is their meaning (a command's arguments).
        case words
        /// A key, token or password: no value ever, only `status` ("✓ Saved · ends in a1b2") and `isSet`; changed
        /// with its `actions` (`setKey`, which sends it once, and `removeKey`).
        case secret
        /// A list of things (`items`), each with its own `actions` (a plugin's `remove`, a command's `delete`).
        case items
        /// Text to read (`value`), nothing to change.
        case info
        /// A button: its `actions` (one), and what the last run said (`status`).
        case button
    }

    public struct Field: Codable, Equatable, Sendable {
        /// What `set` and `settingsAction` name it by: "typeOut", "anthropic.model", "redaction.emails"….
        public var id: String
        public var kind: Kind
        public var label: String
        /// A line of explanation under the label.
        public var help: String?
        /// Left out when it is null (a text or number not set, "follow the system").
        public var value: AIConfig.JSONValue?
        /// What an empty text field stands for (the default).
        public var placeholder: String?
        public var choices: [Choice]?
        public var ordered: Bool?
        public var minCount: Int?
        public var maxCount: Int?
        public var min: Double?
        public var max: Double?
        public var step: Double?
        /// Null is a value too (`number`, `text`).
        public var optional: Bool?
        /// Shown, not changed here (the file can't be read, or it is changed another way).
        public var readOnly: Bool?
        /// Only on these platforms (nil: everywhere). A document made for one of them has it; one made for another
        /// doesn't.
        public var platforms: [SettingsPlatform]?
        /// A secret's state, a button's last outcome, a value as words ("16 a second").
        public var status: String?
        /// A secret: whether it is set (saved, or in the environment).
        public var isSet: Bool?
        /// What `settingsAction` takes for it.
        public var actions: [String]?
        public var items: [Item]?
        /// One of its actions that takes a while (`test`, `browse`) runs now: `cancel` (then among `actions`) stops it.
        public var running: Bool?
        /// A text of several lines (an AI instruction, a snippet).
        public var multiline: Bool?
        /// A path, picked with the system's open panel: a file's (`jargonFile`) or a folder's (`notes.folder`).
        public var picker: Picker?
        /// Its actions that take a text the user types (`value`, a string: the Notion link for `test`): a text box goes
        /// with them, `placeholder` its hint.
        public var textActions: [String]?
        /// What its items' `value` is, as an editor shows it (a custom command's): a field for each key of it, by `id`.
        /// One with `when` only applies while the other fields named there have one of those values (`type`: `run`).
        public var schema: [Field]?
        /// In a `schema`: the values other fields of it must have for this one to apply.
        public var when: [String: [AIConfig.JSONValue]]?

        public init(id: String, kind: Kind, label: String, help: String? = nil, value: AIConfig.JSONValue? = nil) {
            self.id = id
            self.kind = kind
            self.label = label
            self.help = help
            self.value = value
        }
    }

    /// What a path field picks (`Field.picker`).
    public enum Picker: String, Codable, Sendable {
        case file
        case folder
    }

    /// A choice: the value set, and how it reads.
    public struct Choice: Codable, Equatable, Sendable {
        public var value: AIConfig.JSONValue
        public var label: String
        public var note: String?
        /// Shown (it is the value now) but not to be picked: not on this platform, or not available.
        public var disabled: Bool?

        public init(value: AIConfig.JSONValue, label: String, note: String? = nil, disabled: Bool? = nil) {
            self.value = value
            self.label = label
            self.note = note
            self.disabled = disabled
        }

        public init(_ value: String?, _ label: String, note: String? = nil) {
            self.init(value: value.map(AIConfig.JSONValue.string) ?? .null, label: label, note: note)
        }
    }

    /// One thing of an `items` field: a plugin, a custom command.
    public struct Item: Codable, Equatable, Sendable {
        /// What `settingsAction` names it by (`item`).
        public var id: String
        public var title: String
        public var detail: String?
        /// Its definition, for an editor (a custom command's fields).
        public var value: AIConfig.JSONValue?
        public var actions: [String]?
        /// One of its actions that takes a while (`install`) runs now: `cancel` (then among `actions`) stops it.
        public var running: Bool?

        public init(id: String, title: String, detail: String? = nil, value: AIConfig.JSONValue? = nil, actions: [String]? = nil) {
            self.id = id
            self.title = title
            self.detail = detail
            self.value = value
            self.actions = actions
        }
    }
}

/// Why a change or an action was refused, as the window shows it (in the interface language), and the field it is
/// about.
public struct SettingsProblem: Error, Codable, Equatable, Sendable {
    public enum Code: String, Codable, Sendable {
        /// No such field here (not on this platform, or not now: another provider's).
        case unknownField
        /// Not a value the field takes.
        case badValue
        /// The field isn't changed this way (read-only, or the action isn't one of its `actions`).
        case notChangeable
        /// The config file can't be read: nothing is changed until it is fixed.
        case configBroken
        /// It was taken, but couldn't be done (a save, the secret store).
        case failed
        /// An action that takes a while was stopped (`cancel`, or the same action again): nothing it found is shown.
        case cancelled
        /// The settings changed since the revision the change was made on (`set`'s `revision`), or the list it was
        /// made on (`shown`) can't be merged with the one now: nothing changed; the document is the settings now.
        case stale
    }

    public var code: Code
    public var field: String?
    public var message: String

    public init(_ code: Code, field: String?, message: String) {
        self.code = code
        self.field = field
        self.message = message
    }
}

/// What `settingsAction` asks of a field: one of its `actions`.
public struct SettingsAction: Equatable, Sendable {
    public var field: String
    /// "setKey", "removeKey", "test", "browse", "install", "remove", "save", "delete", "cancel".
    public var name: String
    /// The item it is about (a plugin's name, a command's).
    public var item: String?
    /// What it takes: a link to test, a command's definition.
    public var value: AIConfig.JSONValue?
    /// `setKey`'s key: sent once, never kept anywhere but the secret store, never sent back.
    public var key: String?

    public init(field: String, name: String, item: String? = nil, value: AIConfig.JSONValue? = nil, key: String? = nil) {
        self.field = field
        self.name = name
        self.item = item
        self.value = value
        self.key = key
    }

    public static let setKey = "setKey"
    public static let removeKey = "removeKey"
    public static let test = "test"
    public static let browse = "browse"
    public static let install = "install"
    public static let remove = "remove"
    public static let save = "save"
    public static let delete = "delete"
    /// Stops what a field (or, with `item`, one of its items) runs: an action that takes a while.
    public static let cancel = "cancel"
}

/// What an action did: done, with what it says (a test's outcome); or refused (`SettingsProblem`).
public struct SettingsActionOutcome: Equatable, Sendable {
    public var message: String?

    public init(message: String? = nil) { self.message = message }
}
