# Settings v2: the Core API the acceptance tests use

The Core acceptance tests for Settings v2 (0.6.7) were written before the implementation:
`SettingsV2LearningAcceptanceTests.swift` (§3, learning: the starting input, the local store, the Learned list) and
`SettingsV2PerAppAcceptanceTests.swift` (§2 and §4: Insert's choices, `appProfiles` left as they are, "Previous per-app
settings"). They use existing API wherever the spec allows: the sessions (`FakeHost` through the Suggestions rig), the input
a field starts in (`Composer.input`), the settings (`Config`, `SettingsStore`, `SettingsService`'s document), what syncs
(`ICloudSync.values`). This is the API they need that doesn't exist yet, all in the Core module (AllInOneIMECore). The
tests don't compile until it is there.

## The local store of what is learned (§3)

A new file, `Learned.swift`:

```swift
/// What is learned on this device (Settings v2 §3.2), in one local store: the starting input each app learned and the
/// streaks toward one, the apps where typos couldn't be fixed and the suggestion rows picked (both kept here now), and
/// what `AutocompleteStore` and `TemperatureSupport` learned, reached through it. App identifiers, inputs, counts and
/// times only, never text; never in the config file, never synced. Safe from any thread.
public final class LearnedStore: @unchecked Sendable {
    /// Where a shell keeps it: a file in the app's data folder (`CorePaths.dataDir`, Application Support).
    public static var defaultURL: URL { get }
    /// The store kept in `file` (nil: in memory only), reaching what `autocomplete` and `temperature` learned.
    public init(file: URL?, autocomplete: AutocompleteStore, temperature: TemperatureSupport)
    /// Writes to its file now what waits to be written.
    public func flush()

    /// Remembers `app` as one where typos couldn't be fixed (the Mac's `TypoMemory` until now): true if it wasn't yet.
    @discardableResult public func turnTyposOff(in app: String) -> Bool
    /// Whether `app` is one where typos couldn't be fixed (it gets none).
    public func typosOff(in app: String) -> Bool
    /// The suggestion rows picked, oldest first (what `SuggestionsServices.loadPicks` gives), and keeping one.
    public var picks: [SuggestionPick] { get }
    public func recordPick(_ pick: SuggestionPick)

    /// Privacy → Learned…: a row for each thing learned, its text in the interface language, apps named by `appName`.
    public func items(appName: (String) -> String?) -> [LearnedItem]
    /// Forget: `item` forgotten where it is kept (a learned starting input with its app's streak).
    public func forget(_ item: LearnedItem)
    /// Forget All: every item, and every streak.
    public func forgetAll()
}

/// One row of Privacy → Learned….
public struct LearnedItem: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// "Slack: starts in English": `app` as the field told it.
        case startingInput(app: String, input: Input)
        /// "Autocomplete stopped in Mail" (`Autocomplete.Learning`): `app` as it keeps it.
        case autocompleteStopped(app: String)
        /// "Typos off in Terminal".
        case typosOff(app: String)
        /// "Suggestion rows you picked: 42".
        case pickedRows(count: Int)
        /// "Model x doesn't take temperature" (`TemperatureSupport.models`).
        case noTemperature(provider: Provider, model: String)
    }
    public var kind: Kind
    /// The row as the list shows it, in the interface language.
    public var text: String
}
```

`SessionServices` (Session/SessionServices.swift), a stored property beside `autocomplete`:

```swift
/// What is learned on this device: a field starts in what its app learned, and its switches teach it (Settings v2
/// §3.1). The shell gives one for every field; the default is these services' own, in memory.
public var learned: LearnedStore
```

What the tests expect of the session with it: a new field of an app starts in the effective starting input (the learned
one if it can be typed now, else the app's `startingInput`, else the default input); two fields of the app in a row
corrected with Shift to the same input before any key that types teach it, and say so once, naming the app
(`SessionServices.appName`) and the input.

The tests also call internal API they reach through `@testable import`: `TemperatureSupport.init(file:)`,
`TemperatureSupport.remember(_:model:)`, `AutocompleteStore.learn(_:)` with `Autocomplete.Learning.record(_:in:)`.

## Insert's choices (§4)

`SuggestionsInsert` (Suggestions/SuggestionsInsert.swift):

```swift
extension SuggestionsInsert {
    /// What Settings offers to choose, everywhere and per app, in this order (Settings v2 §4): With title, With title and
    /// link. Unset is the source's own; ID only and "source" set explicitly can't be chosen anew, one a config has is
    /// still honored.
    public static var offered: [SuggestionsInsert] { get }
}
```

What the tests expect of Core's settings document (`SettingsService`, the Windows shell's) with it, everywhere
(`suggestionsInsert`) and per app (`apps.<app>.suggestionsInsert`): the choices that can be picked, null aside, are
`offered`; an old value a config has ("id", or "source" set explicitly) is the field's value, shown as a `disabled`
choice under its name ("ID only", "Source's default"); null (Restore Default) unsets it; "id" and "source" are refused
anew (`badValue`).

## "Previous per-app settings" (§2)

`AppProfile` and `Config` (AppProfile.swift):

```swift
extension AppProfile {
    /// The fields no Settings UI sets any more (Settings v2 §2), still honored while set, in the order a row lists them.
    public enum PreviousField: String, CaseIterable, Sendable {
        case startingInput, translateAlways, autocomplete, typeOut, rewriteStyles
    }
}

/// One row of General → "Previous per-app settings".
public struct PreviousAppSettings: Equatable, Sendable {
    /// The app's key in `Config.appProfiles` (what Remove takes).
    public var app: String
    /// What its profile sets of them, in `PreviousField`'s order.
    public var fields: [AppProfile.PreviousField]
    /// The row, in the interface language: "Slack: starts in English, Translate as You Type always on".
    public var text: String
}

extension Config {
    /// General → "Previous per-app settings": a row for each app whose profile sets any `PreviousField` (none: the
    /// section isn't shown), apps named by `appName` (else by their id).
    public func previousAppSettings(appName: (String) -> String?) -> [PreviousAppSettings]
    /// Remove: `app`'s `PreviousField`s cleared, its id in any case; its `noAI`, `suggestions` and `suggestionsInsert` as
    /// they are. A profile left setting nothing goes.
    public mutating func removePreviousAppSettings(for app: String)
}
```

## Notes for the implementer

- This file sits in the test target's folder: SwiftPM warns of it as an unhandled file until it is excluded in
  Core/Package.swift, as `Acceptance/ICloudSyncAppLevelCases.md` is.
- An existing test asks for the old choices: `SuggestionsInsertChoiceTests.theSettingsDocumentHasBothFields`
  (Core/Tests/AllInOneIMECoreTests/SuggestionsInsertChoiceTests.swift) expects "ID only" offered everywhere and per app,
  and sets "id" for an app. It contradicts decision 2 and `SettingsV2PerAppAcceptanceTests`; it isn't this feature's test
  to edit, so it is reported, not changed.
