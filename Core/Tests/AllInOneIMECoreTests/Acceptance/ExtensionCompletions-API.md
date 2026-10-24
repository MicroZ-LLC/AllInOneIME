# Script extensions as completion sources; replacing inserts (0.6.7.1): the API the acceptance tests use

The spec (owner, 2026-10-24) is in the 0.6.7.1 hand-off; its section 4 lists what the tests cover. The tests are
`ExtensionCompletionsAcceptanceTests.swift` and `SuggestionsReplaceAcceptanceTests.swift` in this folder, written from
the spec before the implementation, by another author. They use what exists wherever they can: a text field's
`InputSession` driven as a shell drives it (`FakeHost`, the Suggestions rig of `SuggestionsAcceptanceTests.swift`), what
goes into the field (`commit`, `replace`), the rows shown, script extensions written to disk and read as the app reads
them (`ScriptFolder`, `ExtensionStore.load`), their programs real bash scripts. This is the little they need that
doesn't exist yet. Names and shapes are a proposal: an implementation that names them otherwise changes the tests'
calls, not what they check.

## The Markdown link choice (spec 1)

```swift
public enum SuggestionsInsert {
    // ...the cases there are...
    /// "Markdown link": `[{title}]({url})`, else `{arg}` (`templates`). Written in the config as "markdownLink"; Settings
    /// names it "Markdown link" (`label`) and offers it after With title and link (`offered`, and so
    /// `AppInsertChoice.offered`).
    case markdownLink
}
```

What a row puts in where its filled template doesn't start with the token (a replacement) needs no new API: the session
emits `SessionOutput.replace(text, range:)` with the token's range in the field (UTF-16), the one change.

## A command's completion source (spec 2)

```swift
extension ScriptCommand {
    /// The completion source the command declares: its script's `@allinoneime.completion {…}` line, or its bundle entry's
    /// `"completion": {…}` (the entry's over the line, as for every key), read by the rules of a plugin's `completions`
    /// entry (docs/plugins.md), its name the command's name and its title the command's title. `.failure`: refused, and
    /// why (Settings → Commands shows the reason under the command, which still loads); nil: none declared.
    public var completion: Result<CompletionSource, CompletionRefusal>? { get }
}

extension CompletionSourceKey {
    /// What `command`'s source is kept under: its list, its status (`CompletionSourceStatus.plugin` and `.source`), its
    /// picks, "Refresh now", its approval's `plugin` and `source`. A `plugin` no plugin can have.
    public init(extension command: ScriptCommand)
}

extension CompletionSourceApproval {
    /// What turning `command`'s source on in Settings → Commands approves now: its key (`CompletionSourceKey(extension:)`),
    /// the SHA-256 of its script file, whether it queries, its terms (prefix, compare); no hosts. Kept with the plugins'
    /// approvals (`Config.completionSources`, `SuggestionsSettings.enabled`). Nil: the command declares no source (or one
    /// refused), or its script can't be read.
    public init?(enabling command: ScriptCommand)
}
```

## How the tests hand them to a session (no new API)

- The commands: the session takes those of `SessionServices.loadExtensions` (not turned off) whose source is approved in
  `SuggestionsSettings.enabled`; the values a bundle's commands get from `SessionServices.extensionPreferences`.
- Their programs are run by the core itself by default, as custom commands' are (`SuggestionsServices.commandRuntime`,
  `CommandCompletionRunner`): the tests give no runner of their own and nothing of the shell's (`startScript`), and see
  what the programs did in files they write.
- An approval that no longer holds is reported through `SuggestionsServices.approvalsLapsed`, as a plugin's is; statuses
  through `SuggestionsServices.reportStatus`, under the command's key.
