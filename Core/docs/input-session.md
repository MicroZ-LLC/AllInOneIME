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
command renamed because a built-in has its name now is said once, last, so no notice of the focus takes its place.

## Outputs

| Output | The Mac |
|---|---|
| `commit`, `commitAfterKey`, `replace` | `insertText` (a terminal gets text with line breaks as a paste); after the key; by range |
| `marked` | `setMarkedText`, and its watch for apps that take it on their own |
| `typeOut`, `moveCaret` | typed out like a person (`TypeOut.Typist`), the caret back into a snippet |
| `panel`, `notice`, `noticeElsewhere` | the candidate panel at the caret; a notice on its own; in the field typed in now, else at the pointer |
| `open`, `openAgent`, `openSettings`, `copy` | NSWorkspace, Terminal, the settings window, the pasteboard |
| `readClipboard` | read once the key is answered, never during secure input: `SessionEvent.clipboard` |
| `keyboardLayout` | the input language's layout told to the field |
| `startTimer` | `DispatchQueue.main.asyncAfter`, then `SessionEvent.timer` |
| `platform(.startVoice …)` | dictation (macOS 26's speech recognition), `SessionEvent.voice` as it hears |

## Services

`SessionServices` is what the session asks of the system or has it do: the settings, what is kept between fields and
launches, level one's engine, the language packs, programs, plugins and extensions, script runs, Terminal, notes,
reminders, contacts and messages, the web page, the secret store's keys. Its defaults do nothing and keep nothing; the
Mac fills it in (`SessionServices.mac`), a test with stand-ins (`FakeHost` in `AllInOneIMETestSupport` drives a session
as a shell does; `InputSessionTests` run on every platform).

Still the Mac shell's: Translate as You Type's state shared by every field and its chip (`TranslateModeShared`), the
recording itself, typing out, drawing the panel, the input menu.

## The Windows engine

The engine (on the `0.6.6/windows-engine` branch, not merged here) drives a `Composer` through `AllInOneIMEWire`'s
`ComposerSession` and `EngineHost`, which repeat what the Mac's controller did before the session. To drive an
`InputSession` instead:

1. **Merge the branch** and settle the names it shares with this one: the core now has `PanelModel` and
   `PanelPresenter` (step 6: the engine's `AllInOneIMEEngineKit/PanelModel.swift` and its `PanelBuilder` give way to
   them, its drawing protocol is renamed, say `PanelWindow`), and `FieldInfo` and `FieldContext` (the wire's, in
   `AllInOneIMEWire/WireMessages.swift`, become `WireField` and `WireContext`, or are converted at the edge).
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
   `levelOne` (`EngineRime.makeEngine`, `.starting` while it deploys, `.none` without it), `runProgram` and `runPlugin`
   (this program as a child, `--run-js`, `--run-plugin`), `loadExtensions`, `searchFiles` (`SystemActions.search`),
   `runInTerminal`, `continueInAgent` and `launchInTerminal` (`SystemActions.launchInTerminal`), `noteDestination` (a
   folder or Notion; Apple Notes refuses), `addReminder`, `messageSender`, `startAgent`, `listAgents` and
   `recognizeText` refusing with "not on Windows yet", `secureInputActive` false (the field's own is `FieldInfo.secure`),
   `pastesInTerminal` false, `keyTranslator` nil (the DLL sends the dead key's text). Its `startConversion`, `consume`,
   `startScript`, `scriptEnvironment`, `oneLine` and `errorKind` go: they are `SessionTasks`'. Test mode's
   `ScriptedProvider` answers through a `converter` and `runProgram` of its own.
4. **Its tests**: the wire goldens (`AllInOneIMEWireTests`) and the engine's (`AllInOneIMEEngineTests`) run on Windows
   against the session; where an output's order changes (a panel shown, then hidden, in one answer), the golden is the
   spec, not the code.
