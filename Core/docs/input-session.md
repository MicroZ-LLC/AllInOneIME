# A text field's session

Every shell drives one `InputSession` (`Sources/AllInOneIMECore/Session/`) per text field: it adapts its platform's
events to `SessionEvent`s and applies the `SessionOutput`s that come back. The input logic is the session's: the
`Composer`, and what goes on around it (secure input, the app taking the marked text, the settings and the commands read
again, dead keys, a selection moved under a command, level two refused during secure input, notices, the candidate
panel, saves and their outcomes, the web page `@agent` takes along).

```swift
let session = InputSession(services: services, deliver: { event in
    queue.async { apply(session.handle(event).outputs) }       // the session's own thread: the Mac's main queue
})
let response = session.handle(.key(key, context))              // response.handled: false, the app gets the key too
apply(response.outputs)
```

## Threads

The session is used from one thread only; it is no actor, and the core has no `@MainActor`. What it starts that answers
later (`SessionTasks`: level two's streams, script extensions, `list` commands, `@open`'s searches, recipients, the web
page, notes, reminders, messages, screenshots, the programs' check) runs off that thread and answers through `deliver`,
from any thread, as `SessionEvent.task`; the shell hands each back on the session's thread. Work in a slot (a request,
a list, a search as typed, recipients, the script's run) is one at a time: a newer one stops the one before, and what
the older one still sends is dropped. Timers are outputs too (`startTimer`): the shell calls back with
`SessionEvent.timer` when they're due; a newer one of a kind makes the older one's firing do nothing.

Still the process's, not a session's: the interface language the session sets from the settings (`UIText.choice`),
which it hands its panel (`UIText.language`) and its messages; a change of it is told on the main queue
(`.allInOneIMEInterfaceLanguageChanged`: at once when it was made there, else posted there), where a panel on screen all
along draws. On Apple platforms that is the main thread; elsewhere the main queue's work may run on another thread (on
Linux, after `dispatchMain()`), so the core asks the queue, not `Thread.isMainThread`. Where `@note` saves and the
agent `@agent` hands to, by name (`UIText.noteDestinationName`, `UIText.agentName`), too.

## What the field says

The core never asks the field in the middle of a key: each key carries a `FieldContext` the shell read before handing
it on. A shell where reading is cheap (or that has to send it all across a pipe) reads everything (`Parts.all`). One
where it isn't asks `fieldWants(for:given:)` and reads what it says, asking again until it says nothing more (three
times at most): first whether secure input is on (nothing else is read in a password field), then the marked text's
length when something is composed, where the selection is while a command is written on it, the selection and the
character before the caret when "@" may start a command, the text around the caret when `@reply` may run. The Mac reads
so: the selection with Accessibility, where the field doesn't tell it, only when "@" may use it.

`FieldInfo` comes with the focus: the app (its own settings: `AppProfile`), whether it's a terminal (it runs every line
it is given and pastes on ⌘V itself), whether it's a password field. Once the shell has said what it says of the focus
itself (the Mac: Translate as You Type on, in an app that translates always), it calls `tellBuiltinRenames()`: a custom
command renamed because a built-in has its name now is said once, last, so no notice of the focus takes its place. A
field that takes the focus again after `.close` starts over: its engine is made again, its work starts again.

## Outputs

| Output | The Mac |
|---|---|
| `commit`, `commitAfterKey`, `replace` | `insertText` (a terminal gets text with line breaks as a paste); after the key; by range |
| `marked` | `setMarkedText`, and its watch for apps that take it on their own |
| `typeOut`, `moveCaret` | typed out like a person (`TypeOut.Typist`), the caret back into a snippet |
| `panel`, `notice`, `noticeElsewhere` | the candidate panel at the caret (`PanelModel`, below); a notice on its own; in the field typed in now, else at the pointer |
| `open`, `openAgent`, `openSettings`, `copy` | NSWorkspace, Terminal, the settings window, the pasteboard |
| `readClipboard` | read once the key is answered, never during secure input: `SessionEvent.clipboard` |
| `keyboardLayout` | the input language's layout told to the field |
| `startTimer` | `DispatchQueue.main.asyncAfter`, then `SessionEvent.timer` |
| `platform(.startVoice …)` | dictation (macOS 26's speech recognition), `SessionEvent.voice` as it hears |

## The candidate panel

The `panel` output (and `InputSession.panelModel()`) is a `PanelModel` (`Session/PanelModel.swift`), which
`PanelPresenter` makes of the composer in the interface language and with the key names it is given:
`PanelPresenter(config:language:terms:…)`, the session handing it `UIText.language` (set from the settings) and
`Platform.current.terms`. Neither it nor `SessionText` reads the process's language: two sessions can show theirs in
two. What is structure is data, for each shell to lay out and draw its own way:

| Field | What it is | The Mac draws it |
|---|---|---|
| `chip` | Translate as You Type's chip: the language typed and the one it goes into, each a part to click | a pill on top |
| `handoff` | where an `@question` conversation can go on: a `title`, and `choices`, each a `shortcut` ("⌘1", "Ctrl+1") and a `name` | lines of text, four choices a line (three when there are more) |
| `input` | the line of input: a `prompt` ("refine › "), the `text`, the `caret` in characters into it (nil: none, the command sent) | one line, "▏" at the caret |
| `header` | lines above the rows, each its own: the selection, what the draft has attached (two for a screenshot), the refinements | one under the other, small |
| `rows` | `label`, `text`, `comment`, `kind` (candidate, original, translation), `isComplete`, `icon`, `pickable`, `choice` | a column, or side by side (`horizontal`) |
| `highlighted`, `transcript` | the row picked; the rows are a conversation (no taller than half the screen, scrolled to the last) | |
| `status` | `none`, `loading`, `hint`, `list` (a hint and its items), `error` | under the rows; a list's items after "· " |
| `footer`, `detail` | what the keys do; on its right the page, the time a result took, a notice | |

A click on a row: the shell sends `.pick` with the row's index, and the session picks its `choice` (what
`Composer.choose(index:)` takes: the row's own index, a conversation's answer by its round, none for its question).

An icon (`IconToken`) is a `color` and one `glyph`: `.builtin`, one of the core's own icons named for what it stands
for (`IconToken.Builtin`: its names are the list a shell maps to its icon set; `appleSymbol` is each one's SF Symbol),
or a symbol in SF Symbols' vocabulary (a custom command's, a plugin's, a script extension's own), an emoji or an image
file (a script extension's), each with the built-in it falls back to (`fallback`) where the platform has no such symbol
or can't read the image.

The keys and places the text names are the platform's (`Platform.terms`, `PlatformTerms`): `.mac` writes ⌘C, ⌃V, ⌘R,
⌘1–⌘3, right ⌥, "Tap ⌥", ⌥Space, ⏎, ⇧⏎, ⌫, "this Mac", Terminal and calls `.app` bundles apps; `.windows` Ctrl+C,
Ctrl+V, Ctrl+R, Ctrl+1–3, right Ctrl, "Tap Ctrl", Ctrl+Space, Enter, Shift+Enter, Backspace, "this PC", a terminal and
the Start menu's `.lnk` and `.exe` files (a row that Return picks, a message to send or an issue to open, has the key as
its label too). Esc, Tab, the arrows and the digits are written the same everywhere. A recorded action key reads on
Windows as it is pressed there, whichever system recorded it (`PlatformTerms.name(_:space:)`: the Mac's ⌘J is Ctrl+J,
its ⌃⏎ Win+Enter); on the Mac as it was recorded. Which key does what is the composer's (`Composer.modifierRoles`,
which the shell sets): the presenter and the session's messages name the keys by its roles, whatever roles the terms
came with, so the text names the keys the composer acts on. The settings document names the keys and places of the
platform it is made for (`SettingsSchema.terms`: on Windows Enter, a terminal window, this PC, `cmd /c`, the Credential
Manager, `%USERPROFILE%`), and its paths as that platform writes them, whatever the system it is made on (on Windows
`%APPDATA%\AllInOneIME\jargon.txt` for the jargon list's default, backslashes: `SettingsSchema.shown(path:)`). Other
text outside the panel and the composer's messages still names the Mac: `@settings`' "⏎ opens Settings", `@doctor`'s
and some errors' ("no key for it on this Mac", "Run `aws sso login` in Terminal").

## Services

`SessionServices` is what the session asks of the system or has it do: the settings, what is kept between fields and
launches, level one's engine, the language packs, programs, plugins and extensions, script runs, Terminal, notes,
reminders, contacts and messages, the web page, the secret store's keys. Its defaults do nothing and keep nothing; the
Mac fills it in (`SessionServices.mac`), a test with stand-ins (`FakeHost` in `AllInOneIMETestSupport` drives a session
as a shell does; `InputSessionTests` run on every platform).

Still the Mac shell's: Translate as You Type's state shared by every field and its chip (`TranslateModeShared`), the
recording itself, typing out, drawing the panel, the input menu.

## The Windows engine

The engine (merged in 0.6.6/integration) drives a `Composer` through `AllInOneIMEWire`'s `ComposerSession` and
`EngineHost`, which repeat what the Mac's controller did before the session. To drive an `InputSession` instead:

1. **The names it shared with the session are settled** (done): its panel is the core's `PanelModel`, made by the
   core's `PanelPresenter` (`EngineHost.model(for:)`, in the interface language `EngineSettings.interfaceLanguage`
   picks and with `PlatformTerms.windows`; the composer's `modifierRoles` are `.windows`); the engine's own
   `PanelModel` and `PanelBuilder` are gone, and its drawing protocol is `PanelWindow` (`CandidateWindow`, `NoPanel`,
   the tests' `RecordingPanel`). A click on a row picks the row's `choice` (the last model's, kept with the session).
   The wire's `FieldInfo` and `FieldContext` are `WireField` and `WireContext` (§4 and §5.1 keep their names; the
   DLL's C++ `wire::FieldInfo` too).
2. **`ComposerSession` wraps an `InputSession`** and loses its own policy (the secure check, `MarkedTextWatch`, the
   selection-moved check, `applyIdentity`):
   - `keyDown` → `.key(event, context)`, the context from the frame's `ctx` with `read: .all`: `secure` = the field's,
     `markedTextTaken` = the composition no longer in the document (`ctx.comp` 0 where it was set: the watch the
     session no longer has), `selectedRange` = `ctx.selection`, `selection` = `ctx.selText` with it, `beforeCaret` =
     the last character of `ctx.before`, `text` = `FieldText(before: ctx.before, after: "")`; a modifier's key-down or
     key-up → `.modifiers(ModifierChange(key:modifiers:timestamp: t / 1000), context)`.
   - `focus` → `.focus(FieldInfo(app: field.app, terminal: isTerminal(field.process), secure: field.secure))`, then
     `tellBuiltinRenames()` (in place of `sessionFocused` and `applyIdentity`); `blur` → `.blur`; `endComposition`
     "terminated" → `.commit`, "timeout" → `apply(composer.appTookMarkedText())`; `close` → `.close`; a row clicked →
     `.pick`, scrolled → `.scroll`.
   - Outputs → the wire's: `commit` and `replace` → `commit(text:)` (a range once the wire carries one),
     `commitAfterKey` → `commit(text:afterKey: true)`, `marked` → `composition` (the caret, a `draft` or `converted`
     segment, `typed` from `composer.textAsTyped`), `typeOut` → `commit` (in one go, as now), `panel` → the engine's
     window and `panel(shown:)`, `notice` → its notice, `open`/`openAgent`/`openSettings`/`copy` → `SystemActions` with
     `allowForeground`, `readClipboard` → read on the queue after the key → `.clipboard`, `startTimer` → the queue after
     the delay → `.timer`, `platform(.startVoice)` → `.voice(.failed(notOnWindows, id:))`, `keyboardLayout` → nothing.
   - `deliver` enqueues on the connection's queue (the session's thread) and pushes the outputs while it has the focus.
   - The trust gate (§8: an untrusted client, a key not from the foreground) moves from effects to the services and
     outputs it guards: an untrusted session's services refuse to run, search, read the clipboard or send (their
     error is the notice), and its outputs that open or copy are dropped with the notice; a key's are held to the
     foreground the same way.
3. **`EngineHost` becomes the engine's `SessionServices`**: `converter` and `loadSettings` (`EngineSettings.current`),
   `levelOne` (`EngineRime.makeEngine`, `.starting` while it deploys, `.none` without it), `englishDictionary`
   (`RimeService.shared.englishDictionary`: with it the session puts English words among librime's candidates,
   `EnglishWordsEngine`), `learnEnglishWord` (`EnglishWords.learn` into the engine's `config.json`) and `englishTypedOnce` (one for
   all the engine's sessions, as the Mac's: a word is learned the second time, in any field; the engine does all three
   already, on the Composer: `EngineHost.levelOne` and `learn`, by the session's rule, `EnglishWords.learns`, with the
   field's `terminal` its own: a terminal's program or window, PowerShell ISE), `runProgram` and `runPlugin`
   (this program as a child, `--run-js`, `--run-plugin`), `loadExtensions`, `searchFiles` (`SystemActions.search`),
   `runInTerminal`, `continueInAgent` and `launchInTerminal` (`SystemActions.launchInTerminal`), `noteDestination` (a
   folder or Notion; Apple Notes refuses), `addReminder`, `messageSender`, `startAgent`, `listAgents` and
   `recognizeText` refusing with "not on Windows yet", `secureInputActive` false (the field's own is `FieldInfo.secure`),
   `pastesInTerminal` false, `keyTranslator` nil (the DLL sends the dead key's text). Its `startConversion`, `consume`,
   `startScript`, `scriptEnvironment`, `oneLine` and `errorKind` go: they are `SessionTasks`'. Test mode's
   `ScriptedProvider` answers through a `converter` and `runProgram` of its own.
4. **The candidate window** (done; `CandidateWindow.swift`, `PanelIcons.swift`, `CAllInOneIMEPanel`) draws the
   core's `PanelModel` as it is meant, through its flat copy `AioPanelModel`:
   - `input` as its prompt (dimmed), text and caret (`inputPrompt`, `inputText`, `inputCaret` in UTF-16, from the
     caret in characters: `Input.utf16Caret`), the text wrapped, the caret drawn where DirectWrite puts that position
     (`HitTestTextPosition`);
   - `header` as its lines (`headerLines`), each its own;
   - `handoff`: its title, then each choice's shortcut and name as a chip, the chips wrapping;
   - `Status.list`: `AIO_STATUS_LIST`, its items a line each under the hint; an error after "⚠", in its color;
   - a row's `icon` (`PanelIcons`): a built-in as a glyph of Segoe Fluent Icons (Segoe MDL2 Assets' code points, for
     Windows 10) white on a rounded square of its color (the Mac's system colors), a symbol's name mapped where Windows
     has one (else its `fallback`), an emoji drawn in the square's place (Segoe UI Emoji, in the row's text color where
     the font has none of its own), an image read with WIC on a thread of its own (`fallback` until it is in, or when it
     can't be read; looked at again as the panel is drawn 2 s or more later, so a file changed or readable now is drawn
     as it is); a row's `choice` needs nothing there, the click's row index goes to `.pick` as it is;
   - `transcript`: the rows' text wrapped, the panel no taller than half the monitor's work area, the rows scrolled to
     the last one (or the highlighted one above), a rule where they are cut; a row out of sight takes no click;
   - from top to bottom as the model says (the status under the rows), a rule above the footer as the Mac's panel
     has; the footers' symbols come from DirectWrite's font fallback. `chip` stays empty: Translate as You Type is the
     Mac shell's.
   `AllInOneIMEEngine --render-panel DIR` draws `PanelSamples` (each of these) into PNG files, light and dark, at 96
   and 120 DPI, without a window (`aio_panel_render_png`).
5. **Its tests**: the wire goldens (`AllInOneIMEWireTests`) and the engine's (`AllInOneIMEEngineTests`) run on Windows
   against the session; where an output's order changes (a panel shown, then hidden, in one answer), the golden is the
   spec, not the code.
