# AllInOneIME Settings (Windows)

`AllInOneIMESettings.exe`: the settings window of AllInOneIME for Windows, a C# WinUI 3 app on the engine's pipe (wire
protocol v1 §12, `../../Core/docs/wire-protocol-v1.md`). It knows no setting: the engine sends the settings as a document
(the core's `SettingsService`), in the interface language and for Windows, and the app draws it by kind and sends back
what the user did. Labels, help, which fields show, validation and the window's own words all come from the core.

```
dotnet build AllInOneIMESettings.sln                    # .NET 8 SDK; the Windows App SDK comes from NuGet
dotnet test AllInOneIMESettings.Tests                   # 108 tests, no window, no engine
Scripts/run-e2e.sh                                      # the end-to-end test, in Git Bash, with the user logged on
python Scripts/make-test-documents.py <AllInOneIMEEngine.exe>   # the tests' documents, again (after the core changed)
```

## What it does

- **Connects** to `\\.\pipe\AllInOneIME-<SID>-v1` (message mode, opened for identification only), checks that it is the
  user's engine before anything is sent (§2.1 with the spec notes' fix: the server in this session, the pipe owned by the
  user, the server process the user's at medium integrity or higher), says `hello` with the `settings` capability and
  fetches the document.
- **Starts the engine** when nothing serves the pipe, as the text service does (§2.5): the path in
  `HKLM\Software\AllInOneIME`, value `Engine`, unless its single-instance mutex shows it running or starting; then it waits
  for the pipe (15 s). When it can't (not installed, won't start, doesn't answer), the window says so, in Windows' display
  language, with Try Again.
- **Draws the document:** the sections in a navigation pane, the one picked as a card per field:

  | kind | drawn as |
  |---|---|
  | `toggle` | a switch |
  | `integer` | a number box with its bounds and step |
  | `number` | a slider, its value in words under the label (`status`); an `optional` one with a check box that sends it at all |
  | `text` | a box committed on Enter (Ctrl+Enter for several lines) or when the focus leaves, Escape puts it back; `choices` as a menu of suggestions; `picker` adds the system's folder or file picker |
  | `choice` | a drop-down; a choice shown but `disabled` is greyed |
  | `choices` | check boxes, or, `ordered`, the list in its order with Move up / Move down / Remove and an Add… menu (`minCount`, `maxCount` respected) |
  | `words` | the line its `text` shows, sent as the line (the core splits it: a command line with Windows' rules, a path's backslashes its own) with the line it showed (`shown`) |
  | `secret` | its state (`status`: "✓ Saved · ends in a1b2"), a password box, Save, and Remove… (confirmed) when it has the action |
  | `items` | the list: each entry with its actions (confirmed when they delete) and its own fields (an app's settings, an extension's switch and preferences) when it is opened; the list's `add` when it takes a text (`textActions`: a box, suggestions, the `picker`), a new entry or an edit through the field's `schema` (the custom command editor: texts, a choice, the command line, a number, a switch, the note about programs), the others as buttons; a ring and Cancel on what runs (the library's download, an install) |
  | `info` | its text, selectable, named by its label and its text |
  | `button` | its action, a box for its value when the action takes a text (`textActions`: a Notion link), while it runs (`running`, or sent from here) a progress ring, "Working…" and Cancel (`cancel`), its outcome under the label |
  | any other | its label, help and value, read-only (a later core's kind) |

- **Changes:** one at a time, as the user makes them; the answer's document is drawn (a refused change shows why, at its
  field, and the control goes back to the value). A list (check boxes, an ordered list, words) is sent as the window's
  edit of the list it showed (`shown`, §12.4), so that what another window, `allinoneime-cli` or a sync added or took out
  meanwhile stays so; a scalar's change is its value (the last one wins, as in the Mac's window). `stale` (a command
  line changed elsewhere since it was shown) shows the settings as they are now with why, for the user to make the change
  again; `cancelled` (Cancel, or the same action again) is said as the action's outcome. A newer document updates the
  cards in place where a field is drawn the same way (an action starting or ending on it too), so the focus, a text
  being typed and an open list stay; only a field that changed shape is drawn anew, and the focus goes back to its
  control. A text still being typed is committed when the window closes. While there is no connection every control is
  disabled, for the keyboard too. A value of an unexpected type (a later engine's) is drawn as text, and an answer
  that can't be read is a wire error, never a crash.
- **Keys:** a key, token or password goes once, in its `settingsAction setKey` frame; the box is cleared as it is sent,
  the frame's bytes cleared once written, and nothing logs a value (the requests' `ToString` leaves the key out).
- **Changes made elsewhere** (another window, `allinoneime-cli`, a hand edit of `config.json`, a test that ran):
  `settingsChanged` makes it fetch the document again, once at a time.
- **The engine going away** (an update, a restart): the window says it is connecting again, and does, with the
  protocol's backoff (starting the engine again if it isn't running).
- **One window per engine:** a second start (the Start menu, `@settings`) brings the first window forward.
- **Looks:** Windows 11's (Mica, cards); light and dark follow Windows, as does the title bar; text scales with Windows'
  text size; every control has its label as its accessible name and its help as its help text (Narrator), and is reached
  with Tab or, in the pane and lists, the arrow keys. A refusal and a new state are said as they show (WinUI's live
  regions are told: LiveRegionChanged); a note is named by its label and its text (the config file's path).

The core's document has, for this window, the words of its own controls (`strings`: "Save", "Move up", "Remove “{name}”?",
"Cancel" …), the per-app settings, the script extensions' folders, switches, preferences and passwords, the custom
command editor (`schema`), the `text` of a list of words, `picker`, `textActions` and `running` (§12.3, §12.5).

## Layout

- `AllInOneIMESettings.Core/`: no WinUI, so that the tests run it as it is.
  - `Wire/`: the frames (`WireFrame`), the pipe (`PipeTransport`) and its server check (`ServerCheck`), the protocol
    client (`SettingsClient`), the window's session with the engine (`SettingsConnection`: the newest document by
    revision, fetching after `settingsChanged`, reconnecting), starting the engine (`EngineConnector`), the names
    (`PipeNames`).
  - `Document/`: the document parsed (`SettingsDocument`, `Field`, `Item`, `Choice`), values kept as JSON.
  - `Presentation/`: what each field is drawn with and which request each user action makes (`FieldPresenter`), the
    window's own words (`WindowText`: the document's, else English; before there is a document, its own few messages in
    the nine languages).
- `AllInOneIMESettings/`: the WinUI 3 app: `MainWindow` (the pane, the connection bar), `SectionPage` (a section's cards,
  updated in place), `FieldCards.cs` and `ItemsCard.cs` (a card per kind, the form editor), `Screenshots`.
- `AllInOneIMESettings.Tests/`: xUnit, with the documents the engine sends (`Documents/`).
- `AllInOneIMESettings.UITests/`: the end-to-end driver (UI Automation, FlaUI).
- `Scripts/`: `run-e2e.sh`, `make-test-documents.py`.

## Shipping: self-contained

The app is published self-contained and unpackaged: .NET 8 and the Windows App SDK 1.8 (its WinUI package) are in its
folder, `Program Files\AllInOneIME\<version>\Settings\` (284 files, 73 MB, trimmed; about 21 MB compressed). That
is what ships most simply in our MSI: its files are files like the engine's, installed and removed with the rest, in the
version's own folder. Framework-dependent would need the .NET Desktop Runtime and the Windows App Runtime (MSIX framework
packages, installed per user by their own installer) before the app could start: a bootstrapper or custom actions that
download or carry them, and a window that fails to start where they are missing or were removed.

`EnableMsixTooling` is on although the app isn't packaged: without it `dotnet publish` leaves out the app's resources
(`AllInOneIMESettings.pri`, with App.xaml's), and the published app crashes at its start.

## Options

A user starts it with none. For tests, not in any help:

```
AllInOneIMESettings.exe [--pipe NAME] [--engine EXE [--engine-args "ARGS"]] [--theme light|dark] [--section ID]
                        [--screenshots DIR] [--size WxH]
```

- `--pipe`: a test engine's pipe (the engine's own `--pipe`). With it, the installed engine is never started: only the
  `--engine` given, with `--engine-args`.
- `--theme`: light or dark instead of Windows' own.
- `--screenshots DIR`: every section drawn into PNG files (the window as it shows, and the whole section, its lists
  open), then the app quits.

## Tests

- **Unit** (`dotnet test AllInOneIMESettings.Tests`): 108.
  - The protocol client against the settings golden (`Core/Tests/AllInOneIMEWireTests/WireGoldens/settings.jsonl`),
    replayed by a stand-in engine: each frame the client sends is the golden's (`shown` and `revision` too), and each
    answer and notification comes back as the golden has it, with the documents the engine really sent for those
    requests. Answers out of order, null sent as a value, a key in its frame and nowhere else, what the window showed
    sent with a change, the engine going away, frames and their limits (a settings window's 1 MiB: 2,000 English
    words of 40 characters with the line shown, escaped as the client escapes them, go in one).
  - The documents the engine sends (`Documents/`, made by `Scripts/make-test-documents.py` from a build of the engine:
    the golden's answers; every kind of field in English, Simplified Chinese, French and Japanese; Notion; a file that
    doesn't parse; Test Connection running against a server that never answers, its cancel and the test's `cancelled`):
    every field drawn with a control and named, every kind there, the text and the confirmations in the interface
    language, a broken file read-only, and each user action's request (a switch, a choice whose value is null, numbers, a
    text, a line of words and lists with what they showed, check boxes, an ordered list, a key, a button with its value
    when it takes one, lists, the command editor from its schema, running and cancelled, stale), values of another type.
  - A command line written as Windows reads it back (`CommandLineToArgvW` itself).
  - The server check against real pipes: one this user's process serves passes, one a low-integrity process made first
    (a squatter, started with this token at S-1-16-4096) is refused before anything is sent.
  - The window's session (revisions, one fetch at a time, reconnecting), starting the engine (none to start, started
    and waited for, already starting, won't start), the options, the names.
- **End to end** (`Scripts/run-e2e.sh`): the driver runs in the user's session (`../tip/test/run-in-session.sh`), starts
  a stand-in provider on localhost (`../Scripts/stub-provider.py`) that takes only a fake key, and the Settings app on a
  pipe of its own with a build's engine to start there in test mode (a config in a temporary folder, keys in memory):
  the app starts it. Then, through UI Automation's patterns only (no key is pressed, no other window is touched): every
  section has a name on each control and each control is reached from the keyboard; a switch, a choice, an ordered list
  (a language added and moved), a check box and a text are changed and checked in `config.json`; with Chinese, the
  English words' switch and line (two words added as the user's, the newest first, one like a key refused with why and
  nothing changed; the longest list the settings keep, 2,000 words of 40 characters with the line shown, taken in
  one frame over a DLL's 64 KiB); a custom command is
  saved through its form (a built-in's name refused first, in the dialog, and announced) and deleted (two dialogs); a second start brings the window forward; with the engine gone and
  its pipe held by something that never says welcome, the window's controls are disabled until it is connected again
  (the engine started anew); a fake key is saved (the
  box cleared; the engine's store has it, its last 4 through the wire; `config.json` doesn't); Test Connection goes to
  the stand-in (one request, with that key) and its outcome shows; against a slow stand-in it shows Working… and Cancel,
  and Cancel stops it (the window says Cancelled, the stand-in sees the request go); a hand edit of `config.json`, another window's change
  and the interface language (French, and back) show; the window closes; the app draws every section, light and dark.
  `APP=` and `ENGINE=` test other builds (the installer's: `../installer/build/stage/`).

  Run on 2026-10-19 on this PC: **57 of 57 passed**, with the debug builds, and with the installer's published app and
  release engine. The report and the screenshots are in `build/e2e/` (`e2e-shots/`: the window as it was on the screen,
  when it was in front; `app-shots/`: each section drawn by the app, light and dark). Looked at: nothing clipped, the
  cards and lists laid out at 1040×760 and 125 %, dark mode, the French window. (In the app's own drawings a check box
  shows a dash whatever its state: RenderTargetBitmap draws its animated glyph so; on the screen it is a check mark.)

  Run on 2026-10-20 on the merged protocol: **67 of 67 passed**, with the debug builds and with the installer's
  published app and release engine (the custom command saved through the schema's editor, the cancel, the disabled
  window while it connects again, the announcements, the note's name: the ten new checks). Two runs before it failed
  on a menu that closed at once: a full-screen game had the foreground, and WinUI closes a flyout when its window loses
  it. The window then came up behind other windows (no capture), so the look is the app's own drawings.

  Run again on 2026-10-20 with the English words (the switch, the line, a refusal, the longest list in one frame) and
  Windows' wording in the document: **75 of 75 passed**, with the debug builds and with the installer's published app
  and release engine; the Input page's capture (`e2e-shots/input-english-words.png`) shows the two fields after fuzzy
  pinyin, and the refusal under the line.

## Not done yet

- The plugin library is tested through the document and the client, not clicked end to end (it needs the network); a
  `stale` answer only through the client (the window's lists send `shown`, which the engine merges, and only an ordered
  command line can be stale).
- AllInOneIME Cloud's sign-in (the Mac's), the language packs (Korean, Hindi), the Git extension sources (the Mac's
  `ExtensionSourcesSettings`), the recent apps' names and icons (the per-app list shows the program's file name).
- The window's own messages before it has a document follow Windows' display language, not the settings' (it can't read
  them yet).
