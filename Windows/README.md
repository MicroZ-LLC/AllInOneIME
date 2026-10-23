# AllInOneIME for Windows

The Windows shell of AllInOneIME, on the core in `../Core` (the same Swift package the macOS app is built on). So far:

- The input method's text service (Text Services Framework, C++), in `tip/`, with its own README. It is the DLL side
  of wire protocol v1 (`../Core/docs/wire-protocol-v1.md`).
- `AllInOneIMEEngine`, the per-user engine that the text service talks to over a named pipe, in wire protocol v1. It
  serves the core's `AllInOneIMEWire` server: a Composer for each text field, one serial queue for each client
  connection; and does what the wire doesn't carry (`AllInOneIMEEngineKit`): pinyin through librime, the candidate
  window, the AI requests through the core's providers, the clipboard, opening, terminals (see "What works now").
- `allinoneime-cli`, the command line. It runs level two (translate / polish, the rewrites) with the core's code and
  settings (`config.json` where the core keeps it on Windows, under `%APPDATA%`), and sets them while there is no
  settings window (`set-provider`, `set-key`, see "Settings: a provider and its key"). `wire-replay` replays the
  protocol's goldens over the real pipe.
- The tests of level one's engine, the core's librime binding (`AllInOneIMERime`), on librime's Windows build with
  rime-ice's data (see "Level one: librime and rime-ice").
- AllInOneIME Settings, in `settings/`, with its own README: a C# WinUI 3 app on the engine's pipe that draws the
  settings the engine serves (wire protocol §12, see "Settings over the wire").
- The installer, in `installer/`: an MSI that makes AllInOneIME an input method like any other (see "Installing").

```
Scripts/build-rime-data.sh                    # in Git Bash: librime and rime-ice's data, in ThirdParty (once)
swift build                                   # Swift 6.4 for Windows, with Visual Studio's MSVC and Windows SDK
swift run allinoneime-cli --help
swift test                                    # the pipe's (4), the Rime tests (36), the engine's (111)
```

The engine and the command line link librime (`rime.lib`, `Scripts/fetch-librime.sh`); the engine finds `rime.dll`
and rime-ice's data in `ThirdParty` when built here (in `.build`), and any other copy beside itself only: the installed
one (in the folder the MSI wrote down, `HKLM\Software\AllInOneIME` `InstallDir`, wherever it was installed), or one
copied anywhere.

One of the engine's tests, the system caret's mapping in an app that isn't DPI aware, runs only on a monitor that isn't
at 100% (skipped over SSH, whose desktop is): `tip/test/run-in-session.sh` runs `swift test` in the desktop session.
(Run that way, `swift test` makes `.build\debug` again as the user, a link an elevated shell then won't follow:
`rmdir .build\debug` and build again there.)

The core builds and its tests build here too: `swift build --build-tests` in `../Core`, and `swift test --filter
AllInOneIMEWireTests` runs the protocol's goldens in process.

## What works now (M5–M7)

In every app that loads TSF text services (the classic Win32 ones, and WinUI ones like the Store Notepad), with
**AllInOneIME** picked with Win+Space:

- **English and pinyin (M5).** Typing starts in English, as for a new user on the Mac, and a tap of Shift switches
  between English and 中文 (the "中" / "英" notice shows it). Pinyin is librime with rime-ice's data, as on the Mac: the
  pinyin is the app's composition, the candidates are in the engine's window; Space or a digit picks, `-` / `=` and Page
  Up / Page Down turn the page. The data comes with the installer (`rime-data`); what librime learns is the user's, in
  `%APPDATA%\AllInOneIME\rime`, and it learns nothing typed in a password or a private field (`IS_PASSWORD`, the PINs',
  `IS_PRIVATE`: a browser's private window): there librime never commits a composition with a word picked (it learns as
  it commits), the engine puts the text in (`RimeSession.learns`). librime deploys as the engine starts (under a second
  usually, several the first time in a user folder): until then a field types Latin letters, and gets pinyin once it is
  ready.
- **English words among pinyin's candidates (0.6.6).** As on the Mac (the core's `EnglishWordsEngine` on each field's
  librime session): the settings' words (`englishWords`, which AllInOneIME Settings edits), the jargon list's Latin
  terms and the product words rime-ice lacks come up among librime's candidates as their letters are typed, unless
  rime-ice's own English dictionary (read from the rime-data) has them. Letters put in as typed while typing pinyin
  (Return) are learned the second time, in any field, into `config.json`, by the Mac's rule (`EnglishWords.learns`;
  `learnsEnglishWords` turns it off; written under the settings service's lock, so a save of AllInOneIME Settings' and
  a word learned never write over each other, and the window shows the word at once): never in a password or PIN field nor a private one (the input scopes
  `IS_PASSWORD`, the PINs', `IS_PRIVATE`), in a terminal (the consoles, Windows Terminal, PowerShell ISE, mintty and
  the others the engine knows, Visual Studio's terminal by its window's class), in a remote desktop, a virtual
  machine's window or an SSH client (Remote Desktop Connection, the Remote Desktop app, Windows App, Hyper-V, VMware,
  VirtualBox, Horizon, Citrix, AnyDesk, TeamViewer, RustDesk, Parsec, the VNC viewers, Termius, SecureCRT...), or in an
  app with no AI. The terminals of VS Code, Cursor and the JetBrains IDEs are drawn in the editor's own window and
  can't be told from it (as on the Mac).
- **The candidate window (M6).** The engine's own window, under the caret the DLL reports (above it near the bottom of
  the screen), on that monitor at its DPI, in the apps' light or dark theme: the candidates with their numbers (in a
  row, or one under the other with `"candidateLayout": "vertical"`), the highlight, the command list after "@", level
  two's results as they stream in, a hint, an error, the footer with the keys and a notice beside it; the command list's
  icons (Segoe Fluent Icons on the core's colors, a script extension's emoji or image), a draft's line of input with its
  caret, the header's lines, where an `@question` conversation can go on (chips), what an issue report attaches (a
  list), and a conversation no taller than half the monitor, scrolled to its last answer (`--render-panel` below draws
  each into a PNG). It never takes the
  focus; a click on a row picks it. It hides when the field loses the focus or another app takes the foreground. It is
  drawn, and its notices shown, only for the app in front, and only inside that app's window: a caret the DLL reports in
  a window of another process is ignored, one outside the app's window is cut to it (§8: a background or sandboxed app
  can't put it, with its own text, over another app). Another field's notice never replaces the panel of the field
  being typed in. The app in front is the process whose window is the foreground window, or whose window has the focus
  in it or is inside it: a classic console's conhost.exe (TSF runs there, while the console's window says it is
  cmd.exe's or powershell.exe's: a thread of that conhost made it), a WebView2's msedgewebview2.exe (the new Outlook,
  Teams), a UWP app in ApplicationFrameHost's frame.
- **AI (M7).** `@improve`, `@translate`, `@question`, a custom prompt command, a refine (type, then Shift+Enter) go to
  the provider `config.json` names, through the core's `Converter` and providers, the key from the Credential Manager.
  A new install is on AllInOneIME Cloud, the Mac's default for a new user (`Config.fresh`), which needs a sign-in that
  Windows doesn't have yet: a request then says to sign in or add a key. Set a provider of your own and its key (below)
  and it works: the Claude API, OpenAI or any OpenAI-compatible service (DeepSeek, Ollama...), Gemini (each tested
  against a stand-in for its API), or Bedrock with an AWS profile (`%USERPROFILE%\.aws`; not tried on Windows yet).
- **The other commands.** Ctrl+C copies a result, Ctrl+V pastes the clipboard into a draft; `@open` opens a web address,
  a path, or what it finds by name in the Start menu and on the Desktop, in Documents and Downloads; a link command opens
  its page; `@agent` and a `terminal` command start a console window (below); a custom `run` command runs its program
  through the core's Windows process launcher (a job object); `@js` runs in QuickJS in a child process of the engine, as
  script plugins do; `@py` runs Python if `python3` is on the PATH; `@note` saves to a folder of Markdown files or Notion
  when `config.json` says so. `@settings` opens AllInOneIME Settings.
- **A console window (`@agent`, `@question`'s hand-off, a `terminal` command)** starts the program itself, in the home
  folder, with no shell in between, so nothing in a prompt is ever run: the program as cmd.exe finds it (on the PATH,
  PATHEXT's extensions added, never the current folder; a relative path is the home folder's), a .exe with its
  arguments quoted for the C runtime, a .bat or .cmd (npm's `claude.cmd`) through cmd.exe with its arguments escaped
  (BatBadBut), and the agent's prompt its last argument (after `--`). A prompt the command line can't carry (over
  32,766 characters, over cmd.exe's 8,191, or with a line break for a batch file) goes in a file in
  `%TEMP%\AllInOneIME` (`agent-prompt-*.txt`), and the agent is told to read it; the file goes once the program has
  ended (held open until then, so nothing deletes it), or, if its console didn't get to delete it, as the engine next
  starts. **The window stays open after the program,** as the Mac's Terminal keeps it: the console is the engine's
  own process (`--run-in-console`), which starts the program in it with the same command line, then says how it
  ended ("[git exited with code 1] Press any key to close this window.", in Chinese when Windows is) and waits for a
  key. It is a window or tab of the default terminal (Windows Terminal, or the classic console), and comes to the
  front: the right to take the foreground the app gave the engine goes on to the console's process, which passes it
  to the window that shows it (conhost's, or Windows Terminal's).
- **Off the keys' way.** Opening and the console windows run on a thread of the engine's own, the clipboard on another
  (each a COM apartment with a message loop), never on a field's queue: a key is answered before they happen (§5.4), a
  path on a share that is offline doesn't stop the engine, and the clipboard never waits on the shell: its thread's
  message-only window owns what the engine copies, and another app's Ctrl+C waits for it to answer.

## Settings: a provider and its key

AllInOneIME Settings (the Start menu, or `@settings`; `settings/`) sets them all. The settings are the core's
`config.json`, in `%APPDATA%\AllInOneIME\config.json` (the same format as the Mac's `~/.config/allinoneime/config.json`;
it can be edited by hand too), and the command line, installed beside the engine, sets the ones that matter first:

```
cd "C:\Program Files\AllInOneIME\0.6.4"
allinoneime-cli set-provider anthropic                 # or openai, gemini, bedrock; [--model ID] [--base-url URL]
allinoneime-cli set-key anthropic                      # asks for the key, and doesn't show it as it is pasted
allinoneime-cli show-config                            # the provider, the model, which keys are saved (their ending)
allinoneime-cli set-input zh,en                        # optional: start in Chinese (the first is the default)
```

- **The key** is read from standard input, never from the command line (where it would stay in the shell's history):
  typed at a console with the echo off, or piped in (`Get-Content key.txt | allinoneime-cli set-key openai`). It is
  kept in the Credential Manager (Windows Credentials, `AllInOneIME/AllInOneIME API key/<provider>`), tied to the host
  of the provider's base URL, as on the Mac: a key is never sent to another host. `remove-key <provider>` takes it out.
  `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` and `GEMINI_API_KEY` in the user's environment are used when there is none.
- **Another service:** `set-provider openai --base-url https://api.deepseek.com/v1 --model deepseek-chat`, then
  `set-key openai`. Plain `http://` only to this PC or the local network (Ollama: `--base-url
  http://127.0.0.1:11434/v1`).
- **Nothing restarts:** the engine reads `config.json` again when it changes, and a key when it was saved again.
- **A file that doesn't parse** is never overwritten by the commands; the engine uses the defaults meanwhile (and logs
  why).


## Settings over the wire

The engine serves the settings to a settings window over its pipe (`../Core/docs/wire-protocol-v1.md` §12): a client
that says `hello` with the capability `settings` (and is trusted: medium integrity, no AppContainer) gets the settings
as a document of sections and fields, in the interface language and for Windows (the Mac's own fields left out), sends
one change at a time (`settingsSet`, checked and saved by the core, `config.json` written key by key), runs the fields'
actions (`settingsAction`: a key saved once and never sent back, Test Connection, the plugin library, a custom command
saved or deleted), and hears of every change (`settingsChanged`, also when `config.json` changed elsewhere: the engine
looks about once a second). The core's `SettingsService` does all of it; the engine only gives it its config file
(`--config`, else `%APPDATA%\AllInOneIME\config.json`) and, with `--no-keychain`, keeps its keys in memory. In test
mode the goldens bring their own (`#! settings`); `settings.jsonl` replays over the pipe as the others do.

- **The interface language:** the engine reads the core's String Catalog (`Localizable.xcstrings` beside it, else the
  checkout's `Core/Resources`; `UIText.useCatalog`), and takes its language from the settings at its start and after
  every change, wherever it was made (`UIText.choice`), else from Windows' own languages: the document, the notices and
  the panel's messages are in any of the nine languages the core has.
- **Fuzzy pinyin** changed in the settings reaches librime as on the Mac (`RimeFuzzy`): the schema's patch in the user
  folder, deployed again once a deployment under way is done, the fields given new sessions.
- **More of the store:** the per-app settings (an app added by its program), the script extensions' folders, switches,
  preferences and passwords, the custom command editor (`schema`), the window's own words (§12.3), what runs and its
  cancel (§12.5).
- **Tests:** an engine on a pipe of its own (`--pipe`) with `--test --config FILE` serves that file's settings, its keys
  in memory: the Settings app's end-to-end test (`settings/Scripts/run-e2e.sh`).

## What's still missing

- **In AllInOneIME Settings:** the sign-in to AllInOneIME Cloud, the language packs (Korean, Hindi: their input isn't
  offered), the Git extension sources.
- **What only macOS has:** Apple Notes (`@note`'s default destination: the text goes on the clipboard instead, and a
  notice says so; a folder or Notion works), Reminders (`@reminder`), Messages (`@imessage`), reading a
  screenshot's text (`@reply` with an image), Claude Code background tasks (`@tasks`, `@agent` in
  the background). Each says "Windows 版还不支持" / "Not available on Windows yet" in the panel or a notice.
- **Not done yet on Windows:** results typed out step by step (they go in at once), the keyboard layout of an input
  language (French's AZERTY), Translate as You Type's chip, the command usage order and the recent questions kept
  between runs, `@open`'s search (a plain walk of a few folders, not an index), UI-less mode (`ITfUIElement`) for
  full-screen games; personal pinyin dictionaries (0.6.7, the Mac's Settings → Input → Chinese: the core's
  `PersonalDictionaryStore` would write librime's files here as it is, but the settings document has no field for
  them and the Settings app no file to pick yet). The command trigger (0.6.7) works as on the Mac.

## Installing (M4)

```
powershell -ExecutionPolicy Bypass -File installer\build.ps1     :: -> installer\build\AllInOneIME-<version>-x64.msi
```

`build.ps1` builds the DLL, the engine, the command line and the installer's helper in Release (librime and rime-ice's
data with `Scripts/build-rime-data.sh` first, in Git Bash, if `ThirdParty` hasn't them) and packages them with WiX
Toolset 5 (`dotnet tool install --global wix --version 5.0.2`, which needs the .NET SDK; the script adds the UI and Util
extensions itself): 77 MB, most of it rime-ice's dictionaries. The version is the app's, from `Resources/Info.plist`.
The package isn't signed yet.

- **Install:** double-click the MSI (one license page, then the UAC prompt), or `msiexec /i AllInOneIME-0.6.4-x64.msi
  /qn` from an elevated shell. Then pick **AllInOneIME** with Win+Space, as any keyboard.
- **Uninstall:** Settings → Apps → Installed apps → AllInOneIME → Uninstall, or `msiexec /x AllInOneIME-0.6.4-x64.msi
  /qn`.

What the MSI does:

- **Files:** `Program Files\AllInOneIME\<version>\`: `AllInOneTIP.dll`, `AllInOneIMEEngine.exe` (made a GUI program,
  so it opens no console at logon), `rime.dll` (librime) and `rime-data\` (rime-ice's schemas and dictionaries, 85
  files, 120 MB) beside it, `allinoneime-cli.exe` (the command line), `AllInOneIMESetup.exe` (the helper), the 20
  DLLs the engine and the command line import from the Swift runtime and the VC++ redistributable, next to them, and
  the interface text's String Catalog (`Localizable.xcstrings`). AllInOneIME Settings in `Settings\`, self-contained
  (.NET and the Windows App SDK in its folder, 284 files), with "AllInOneIME Settings" in the Start menu. A
  version has its own folder, so an app that loaded an older DLL keeps it until it restarts while new apps load the new
  one.
- **Registration:** the DLL's own `DllRegisterServer`, run as SelfReg: the COM server in HKLM, the en-US and zh-CN
  profiles, the categories (`tip/README.md`, "Registration").
- **The user's keyboard list:** `AllInOneIMESetup add-keyboard`, for the user who installs, through `InstallLayoutOrTip`
  (input.dll). It goes under Chinese (Simplified) if that is in their list, else English (US), at the end of that
  language's input methods: never the default input method, never switched to. Windows rewrites `HKCU\Keyboard
  Layout\Preload` from the list as it does so; the helper puts that back as it was. Other users of the PC add it in
  Settings (Time & language → Language & region → the language → Language options → Add a keyboard), or with
  `AllInOneIMESetup add-keyboard`.
- **The engine:** `HKLM\Software\AllInOneIME`, value `Engine`, is its path (the DLL starts it from there when an app
  needs it), and an `AllInOneIME` value under `HKLM\...\CurrentVersion\Run` starts each user's engine at logon, in
  their session. The installer starts it for the installing user right away, never elevated (through Explorer when
  the installer is elevated); not from an SSH session (session 0), where it would only hold the pipe's name.
- **Uninstall:** AllInOneIME out of the user's language list (and TSF's state for it in their HKCU), every engine and
  Settings window run from the installed copy stopped (its folder, wherever it was installed, and `Program
  Files\AllInOneIME`; `AllInOneIMESetup stop-engines --dry-run` says which), but a console window's process, whose
  program (an agent, a terminal command) is left to run and which deletes its prompt's file once it ends (its files go
  at the next restart, as a DLL in use does), and any whose command line can't be read (it may be one),
  `DllUnregisterServer`, the files, the folder and the registry values gone. An upgrade keeps the keyboard in the list.
  `%APPDATA%\AllInOneIME`, the user's data (`config.json`, librime's learned words in `rime\`), is never touched, nor
  the keys in the Credential Manager.
- **A console window open during an upgrade:** its process holds `AllInOneIMEEngine.exe` and the runtime DLLs it
  loaded. An upgrade to another version installs into that version's own folder, so nothing mixes; but a package of
  the same version (a reinstall, an integration build that kept the version) replaces those files only at the next
  restart (`msiexec` then returns 3010, a restart required), while the others (AllInOneIME Settings, `rime-data`, the
  DLL that apps load from now on) are the new package's at once: until the restart the user's engine, started again
  from the same path, is the old one, with the new Settings app and data. Close the console windows (the agent's, a
  terminal command's) before such an upgrade to have it all at once.
- **A DLL in use:** an installed input method's DLL is loaded, as a module or for its icon, by Explorer and every app
  that showed it (in the test: Explorer, Discord, Notepad...). Restart Manager is off (`MSIRESTARTMANAGERCONTROL`), so
  the installer never closes the user's apps: Windows Installer moves the file to `Config.Msi` and deletes it at the
  next restart, and the folder goes at once.

`AllInOneIMESetup status` shows what is registered, where AllInOneIME is in the user's list and which engines run (run it
in a desktop session for TSF's own view; session 0 has no TSF). `remove-keyboard`, `start-engine` and `stop-engines`
are the installer's other steps.

What the installed copy does: "What works now" above.

### Testing the installer

```
bash installer/test/run-install-test.sh     # from an elevated shell (an administrator's SSH session), user logged on
```

It records the user's language list, the default input method, the session's input method, `HKCU\Keyboard Layout` and
everything of AllInOneIME's (`installer/test/snapshot.ps1`), then: a silent install and its checks; an upgrade over it
(a second package of the same version); `tip/test/run-e2e.sh --installed` five times (below); a silent uninstall and
its checks; anything of the record that changed, put back; and, if everything passed, the package installed again for
the user to try. The steps that need the desktop run in the user's session as one-shot scheduled tasks
(`tip/test/run-in-session.sh`).

Run on 2026-10-18 on this PC (Windows 11 Pro 26200, the user's language list Chinese (Simplified) with Microsoft
Pinyin, and English (US) with no keyboard), the M5–M7 package: **57 passed, 0 failed, 1 warning** (M4's: 47, 0, 1).
Run again on 2026-10-19 after the review's fixes (the console window without PowerShell, the system thread, the panel
for the app in front only, librime from beside the installed engine only): **57 passed, 0 failed, 1 warning**, the
same warning. The e2e driver's own window put the session's input method on AllInOneIME as it closed, in that run and
in a `run-e2e.sh --installed` after it; `run-e2e.sh` saw it each time and put Microsoft Pinyin back. Run again on
2026-10-19 after the second review's fixes, with pinyin in a classic console and in a WebView2 and a terminal
command's console window added: **60 passed, 0 failed, 1 warning**, the same warning, the same input method put back
after the two runs in the driver's own window. With the package after the last fix (the console's program started
before its window comes to the front), two runs failed one real-Notepad check each: about 5 s after the driver started,
the session task's own console, handed to Windows Terminal, opened its window and took the foreground, and the driver
stopped typing (its guard). With the task in a classic console (`run-in-session.sh`), the run after: **60 passed, 0
failed, 1 warning**, and the package is installed. The two interrupted runs left their documents open in the user's
Notepad (aio-e2e-22408.txt and aio-e2e-2280.txt, whose files the driver deleted): the driver never closes a tab it can't
prove is its own and in front. The 0.6.4 package from before those fixes, run with `--console
--pinyin` and `--webview2 --pinyin`, typed "你好你好" in both but never showed the candidate window there, and with
`--terminal` the console was gone before it could be read.

Run on 2026-10-20 with the 0.6.6 integration's package (AllInOneIME-0.6.5-x64.msi, the version `Info.plist` has):
first **52 passed, 11 failed**. The user's own input method was AllInOneIME (the 0.6.4 copy installed before), so
uninstalling it first recorded only Windows' fallback, and reinstalling the profile brought theirs back ("the session's
input method is as recorded" failed three times); and with AllInOneIME active in the app in front, its text service
started the user's engine again in the second between `stop-engines` and the driver starting its own, which then
exited ("another engine is running"): every typing check failed before typing anything (each run saved and closed its
own Notepad tab). The test now records the session's input method before taking an installed copy out, and the driver
ends such an engine and starts its own again (one to three tries per run). The run after: **63 passed, 0 failed, 0
warnings**, and the package is installed; `tip/test/run-e2e.sh --installed` after it: PASS. The candidate window's
captures (`installer/build/test-logs/e2e-*-shots/`) show the core's model drawn as the Mac's panel is: the rule above
the footer, the results with "原文", the row of candidates with the "中" notice.

Run again on 2026-10-20 with the package of the second round (English words among pinyin's candidates, Windows' wording
in the settings, a settings window's 1 MiB frames, the review's lows), the English words' check added: **64 passed, 0
failed, 0 warnings**, and the package is installed; `tip/test/run-e2e.sh --installed` after it: PASS, the session's
input method (the user's own, AllInOneIME) the same before and after. The English words' capture shows "frobnicate"
second among the candidates of "frobn", after librime's first.

Run on 2026-10-22 with 0.6.7's package (the 0.6.7 core, the third round's fixes, the command trigger on Windows):
**64 passed, 0 failed, 0 warnings**, and the package is installed; `tip/test/run-e2e.sh --installed` after it: PASS,
the session's input method (AllInOneIME) the same before and after. Two runs before it failed one check each: the
candidate window still up 400 ms after the commit in the driver's console (the switch's "中" notice, 1.5 s, outlived
the candidates, as it should: the driver now lets it go first; 4 of 4 runs in the console after that), and the
session's input method after the e2e runs (Windows brought back the user's own, AllInOneIME, which that run's record,
made after the repair below, didn't have as theirs). The user's own setup had changed since 2026-10-20: AllInOneIME was
their only Chinese input method. The test's first step, taking out the copy installed before for a clean record, took
Chinese (Simplified) out of the language list with it (`remove-keyboard`'s `InstallLayoutOrTip(ILOT_UNINSTALL)` drops
a language left without an input method), and TSF's sort order kept AllInOneIME's entry for it, so the test stopped
there ("something of AllInOneIME's is here already") with the list changed. It was put back by hand: Chinese with
Microsoft Pinyin, as recorded on 2026-10-20, for the test's runs, then AllInOneIME alone again once 0.6.7 was
installed. Not fixed yet: an uninstall that takes the user's only Chinese input method takes the language with it (it
should leave Windows' own there), and the test's first step should keep the list it found before it uninstalls.

- **Install and upgrade:** the files (librime, rime-data, the command line, which runs on the runtime beside it), the
  20 runtime DLLs, the COM server at the installed path, both profiles and the
  5 categories, TSF enumerating both profiles as enabled in the user's session, AllInOneIME in the list under
  zh-Hans-CN after Microsoft Pinyin, the rest of the list, the default input method, `Keyboard Layout` and the session's
  input method all as recorded. The engine, started as at logon: in the user's session, no window, the runtime from its
  own folder.
- **Typing through the installed copy:**
  - in a new process (the driver's EDIT control), the installed DLL loaded by TSF from the registration with the
    installed engine: "hi @improve helo", Return, "1" gives "hi Hello.";
  - in the user's real Notepad, through the installed engine as it runs for a user (no test mode): "Hello world. 123"
    comes out as typed;
  - in real Notepad with the test provider: "hi Hello.";
  - in real Notepad, pinyin through librime (`--pinyin`): a tap of Shift, "nihao", Space, "nihao", "1" give
    "你好你好"; the candidate window up under the caret while the candidates are, a no-activate, topmost tool window,
    Notepad keeping the foreground, gone with the commit;
  - in real Notepad, English words among pinyin's candidates (`--english`, typing starting in Chinese): "frobnicate"
    and Return twice put the letters in as typed and learn the word the second time, into the run's own settings
    file (never the user's), then "frobn" shows it among the candidates, second, and "2" picks it:
    "frobnicatefrobnicatefrobnicate";
  - in real Notepad, a real AI request (`--ai`): "@improve hello", Return, the versions streamed over HTTP from the
    stub provider on localhost in the Claude API's format, "1" gives "Hello there." (the stub saw one request, with the
    right key);
  - in a classic console of the driver's own (`--console`, `conhost.exe cmd.exe`), pinyin at cmd's prompt through
    the DLL in conhost: "AIO>你好你好", the candidate window up while the candidates are;
  - in a WebView2 in a window of the driver's own (`--webview2`), pinyin in the page's field through the DLL in
    msedgewebview2.exe: "你好你好", the candidate window up;
  - a `terminal` command (`--terminal`): its console window (Windows Terminal's) came to the front, showed the
    program's output and "exited with code 3", stayed open after it, and closed on a key written into it;
  - the candidate window captured as PNGs each time (`installer/build/test-logs/e2e-*-shots/`), and looked at: the
    candidates in a row with the first highlighted, the footer in Chinese and the "中" notice, the results with their
    numbers, "原文" beside row 0 and the request's time.
- **The warning:** the user's Notepad (their tabs, unsaved work: not to be closed) had been running since before the
  install, with the DLL of an earlier development run loaded. COM doesn't load a class's DLL again in a process, so
  that Notepad keeps using that one (the same sources) until it restarts; a Notepad started after the install loads
  the installed one, as the new process did.
- **Uninstall:** nothing of AllInOneIME's left (keys in HKLM and HKCU, the Run entry, the ARP entry, the files and the
  folder); the language list, the User Profile keys, `Keyboard Layout`, TSF's order of the user's input methods, the
  default and the session's input method all as recorded; the user's data folder untouched. Nothing needed putting
  back.
- **Not covered without a human:** the dialogs of an interactive install (the license page; the Files in Use list an
  uninstall from Settings may show, where Ignore is the answer).
- **To check by hand (the tests can't; not done yet):** whether a window the engine opens comes up in front when a
  person types. Windows takes the right to set the foreground back at the user's next input, and a person's key comes
  up some 100 ms after it went down, while the e2e driver's keys go down and up together; the tests also never open the
  user's browser or Explorer. In Notepad, with AllInOneIME:
  - `@agent hi`, Return, and a `terminal` command: the console window in front, not flashing in the taskbar, with
    Windows Terminal as the default terminal and with the classic console (Settings → System → For developers →
    Terminal: Windows Console Host); with Windows Terminal opening new tabs in a window already open, that window in
    front on the new tab;
  - with the browser already running, `@open example.com`, Return: the page in front, not behind Notepad; `@settings`:
    the folder of config.json in front (the shell hands both to the program already running and starts nothing; that
    program gets the right first).

## The engine

```
.build\debug\AllInOneIMEEngine.exe [--test [--provider FILE] [--clock manual|system]] [--config FILE] [--no-keychain]
                                    [--rime-data DIR] [--rime-user DIR] [--no-rime] [--no-panel] [--instances N] [--quiet]
                                    [--pipe NAME] [--settings-app FILE]
```

- **The candidate window's drawings:** `AllInOneIMEEngine --render-panel DIR [--dpi N]... [--image FILE]` draws its
  sample panels (`PanelSamples`: candidates in a row and a column, the command list with its icons, a draft, results,
  a conversation, an issue report's list, an error, every icon, a notice) into PNG files in DIR, light and dark, as the
  window draws them but without one (any session): to look at.

- **For the Settings app:** `--settings-app`, the app `@settings` starts (default: `Settings\AllInOneIMESettings.exe`
  beside the engine; without one, the folder of `config.json`); `--pipe NAME`, for tests, an engine on a pipe of its own
  with a single-instance mutex of its own, so that it runs beside the installed one (`@settings` gives the app the same
  pipe); with `--test`, `--config` gives the Settings app that file's settings, their keys in memory, shared with the
  requests (so are `--no-keychain`'s: a key the app saves is the one Test Connection sends).

- **Settings:** `--config FILE` instead of `%APPDATA%\AllInOneIME\config.json`; `--no-keychain`, API keys from the
  environment only (the tests: the user's Credential Manager is neither read nor tied to a stub's address); librime's
  data (`--rime-data`, ignored by any engine but a build, which takes librime and its data from beside itself only) and
  user folder (`--rime-user`: the tests' own, so nothing typed there is learned in the user's); `--no-rime`, Latin
  letters only; `--no-panel`, no candidate window.
- **The plugins** (`%APPDATA%\AllInOneIME\plugins`) are read again only when their folder changed, and in the
  background every 30 s (`PluginCatalog`), not at every focus.
- **Its child processes:** it is also what `@js` code (`--run-js`) and script plugins (`--run-plugin DIR`) run in,
  and the process of each console window it opens (`--run-in-console`). As it starts, it deletes the long prompts'
  files in `%TEMP%\AllInOneIME` that no console holds any more.
- **librime and threads:** each client connection has its own queue, and librime is one per process: every call into
  it goes through one lock (a key is a fraction of a millisecond in it).

- **Pipe:** `\\.\pipe\AllInOneIME-<UserSID>-v1`, with the protocol's SDDL and `FILE_FLAG_FIRST_PIPE_INSTANCE` (§2.1).
  It is in message mode, refuses remote clients, uses overlapped I/O, and keeps at least 4 instances waiting.
- **Single instance:** a second engine for the same user exits (`Local\AllInOneIME-Engine-<SID>`), with exit code 4
  (`EngineExit.anotherEngineRuns`; 1 is any other failure to start).
- **Client check:** a client from another session or another user is refused. Low-integrity and AppContainer
  clients are `untrusted` (§8). Tested with a low-integrity copy of the CLI: it connects, comes out
  `low, untrusted`, and the goldens pass.
- **The foreground (§8):** what runs, opens, reads the clipboard or sends, from a key, and the candidate window and its
  notices need the client's process to be the app in front: the foreground window is its own, or the focus window of
  that window's thread is (`GetGUIThreadInfo`), or a window inside the foreground window is: in ApplicationFrameHost's
  frame (a UWP app's, in an AppContainer), or, for a trusted client only, anywhere (a WebView2's, a browser's). An
  untrusted client's window inside another app's would be one it put there to show its panel over that app; UIPI
  stops that anyway (a low-integrity process's CreateWindowEx with a medium window as the parent, and its SetParent
  into one, fail with error 5: tried on 2026-10-19 in the desktop session). A classic console's window (`ConsoleWindowClass`) says it is its client's (cmd.exe):
  it is System32's conhost.exe's when a thread of that conhost made it (`EnumThreadWindows`), and caret reports in it
  are that conhost's to make, no other's. The right to take the foreground the client gives the engine
  (`allowForeground`) goes on to what shows the window, never to any process (`ASFW_ANY`): to a console's process
  (started suspended until then), which passes it to conhost's or Windows Terminal's window and brings that to the
  front; for `@open`, first to the program already running that the shell may hand the target to (the default
  browser for an address, Explorer for a folder, the file type's program: `AssocQueryStringW`, a process of it with a
  window on the screen), then to the process the shell starts, if it starts one.
- **A client that stops reading:** its writes time out after 500 ms and the connection is dropped (tested: about
  0.6 s), so the engine isn't stalled for every app.
- **Watchdog:** the engine exits when a connection's queue is busy for more than 2 s. Its thread, the main one, runs the
  main queue (the main run loop) between its ticks: what the core posts there (the interface language's observers) runs.
- **bye:** Ctrl+C, logoff and shutdown send `bye` to every client first.
- **`--test`:** a manual clock, level two from a golden's scripted provider, and `x-test` directives
  (`AllInOneIMEWire`'s `TestFrame`) accepted. Clients are taken to own the foreground. `wire-replay` drives it.

## Replaying the goldens over the pipe

```
allinoneime-cli wire-replay [--launch ENGINE.exe] [--pipe NAME] [--cold-starts N] [--repeat N] <file.jsonl>...
```

Against an engine in test mode, either one already running or one started with `--launch`, it does what a DLL does:

1. the server check (§2.1, with the spec notes' fix: the server process's integrity is checked, not the pipe's label);
2. each `>` frame written;
3. `x-test idle`;
4. the frames the engine sent before the idle answer compared with the `<` lines.

It prints each file and the key round trips: from writing a `keyDown` or `keyUp` to reading its `result`, timed
with `QueryPerformanceCounter`. With `--cold-starts N`, it first launches the engine N times and times each launch
until `welcome`. With `--pipe NAME`, the engine's pipe is one of its own (the engine's `--pipe`, given to the engine
`--launch` starts too): a replay beside the engine the user runs, which has the user's pipe.

```
swift build -c release
.build\release\allinoneime-cli wire-replay --launch .build\release\AllInOneIMEEngine.exe ^
    --cold-starts 20 --repeat 50 ..\Core\Tests\AllInOneIMEWireTests\WireGoldens\*.jsonl
```

## Measured (M2)

Measured on 2026-10-18 on a Ryzen 5 5600X (12 threads, 48 GB) running Windows 11 Pro 26200 with Swift 6.4.1.

- **Setup:** the engine in test mode (Latin input, the scripted provider), run over OpenSSH (session 0, high
  integrity).
- **Results:** all 10 goldens passed on every run, 500 of 500 replays in release and 200 of 200 in debug.
- **Load:** the PC was shared. Another job's builds kept the CPU at 50–90%, so the numbers are a little pessimistic
  and the cold starts vary between runs.

| | release | debug |
|---|---|---|
| cold start, launch → pipe open (p50 / p90 / max of 20) | 29.3 / 30.6 / 82.1 ms | 23.7 / 25.0 / 31.1 ms |
| cold start, launch → `welcome` (p50 / p90 / max of 20) | 30.9 / 33.2 / 83.8 ms | 25.5 / 26.8 / 33.4 ms |
| key round trip, p50 | 0.092 ms | 0.175 ms |
| key round trip, p90 | 0.189 ms | 0.398 ms |
| key round trip, p99 | 0.296 ms | 0.601 ms |
| key round trip, max | 0.70 ms | 11.0 ms |
| key round trips measured | 16,400 (50 runs) | 6,560 (20 runs) |
| the engine's first key | 0.49 ms | 0.39 ms |

Notes on the numbers:

- **Budget:** the spec allows 20 ms p99 on the engine's side (§5.4), and the DLL gives up after 150 ms.
- **What the round trip includes:** both ends' JSON, the pipe and the Composer, all of it.
- **The max cold start:** the slowest launch is always the first of a series (a cold file cache).
- **Fresh executables:** while the antivirus was still scanning freshly built executables and another build was
  running, one series measured 151 ms p50.
- **Debug vs release:** the debug engine starting faster than the release one is noise from the load, not a real
  difference.
- **Not measured yet:** the first draw (50 ms), keepalive, and anything with Rime or a model, which need the DLL, the
  panel and a language pack.

## Measured (M3): the real DLL and engine, end to end

Measured on 2026-10-18 on the same PC. `Windows/tip/test/run-e2e.sh` registers the real DLL, starts the real engine in
the logged-on session (`--test`, the scripted `improve-hello` provider, `--clock system` so `@improve` streams in real
time), and the driver types "hi @improve helo", Return and `1` into a focused edit control with **SendInput**, reading
the text back through **UIA `TextPattern`**. This is the whole stack: SendInput → the TSF DLL → the pipe → the engine's
Composer and scripted level two → outputs → the composition and commit in the control → UIA.

- **Result:** the control ends up holding **"hi Hello."**; the pick of version 1 ("Hello.") committed over the draft.
  The session's input method is the same before and after (AllInOneIME is activated for the one thread only).
- **Per-key round trip, as the DLL times it** (`QueryPerformanceCounter`, write of the frame to read of the `result`),
  over the 20 keys of a run:

| | ms |
|---|---|
| key round trip, p50 | 0.37 |
| key round trip, p90 | 0.51 |
| key round trip, max | 1.15 (the Return that starts level two) |
| key round trip, min (a modifier key-up) | 0.12 |

  These are a little higher than M2's in-process replay numbers (p50 0.09 ms): a real key now carries a fresh read of
  the document's selection and context under a TSF lock before the frame goes out, and the edit control's own work is
  in the loop. Still far inside the 20 ms p99 budget and the 150 ms timeout.

- **Notepad:** the driver's target is Notepad (it finds the document by UIA and guards every key on Notepad holding the
  foreground). M3 found that the DLL never loaded into the Store (WinUI) Notepad and took it for an app that can't host
  a text service. M4 found why: its text input runs TSF on threads of its own, not the window's, and the driver had
  activated the profile on the window's thread only. Activated for Notepad's process, the DLL loads there and "hi
  Hello." comes out in real Notepad (see "Testing the installer" above, and `Windows/tip/README.md`, "End to end").

## Level one: librime and rime-ice

The same versions as the macOS shell (the root `Makefile`), downloaded, checked and unpacked into `ThirdParty/`
(git-ignored), in the Mac's layout (`ThirdParty/librime/dist/...`, `ThirdParty/rime-data/`). In Git Bash:

```
Scripts/build-rime-data.sh    # librime (Scripts/fetch-librime.sh), then rime-ice, its dictionaries prebuilt
swift test                    # the Rime tests (Tests/AllInOneIMERimeTests): 30, in 5 s to a minute
```

`Scripts/fetch-librime.sh` alone fetches librime only. Both do nothing when `ThirdParty` already has what they would
make, and both fail when the root `Makefile` pins another version than theirs: the two shells move together.
`ALLINONEIME_THIRDPARTY` (an absolute path), as on the Mac, puts `ThirdParty` elsewhere, a folder several checkouts on
this PC share; `Package.swift` and the tests read it too.

| | Version | Download | Size | SHA-256 |
|---|---|---|---|---|
| librime (BSD-3) | 1.16.1, de4700e, MSVC x64 | [`rime-de4700e-Windows-msvc-x64.7z`](https://github.com/rime/librime/releases/download/1.16.1/rime-de4700e-Windows-msvc-x64.7z) | 7,373,905 | `e17c1bb4acc9934669e7a62003aef3f8b56d0afa89e5d893ed7dbf34546abb6e` |
| rime-ice (GPL-3.0) | 2026.06.30, 6810e89 | [`full.zip`](https://github.com/iDvel/rime-ice/releases/download/2026.06.30/full.zip), saved as `rime-ice-2026.06.30-full.zip` | 16,050,491 | `675d23b070be00e1b800f9a6db033ef98f4493cd5b568ed8aa3b3541769c46ac` |

librime's official Windows build has the same plugins as the macOS one, at the same commits (its `version-info.txt`):
librime-lua 68f9c36 (rime-ice's Lua scripts: the date, the calculator...), librime-octagram dfcc151, librime-predict
920bd41. Unpacked, `ThirdParty/librime` is 55 MB: `dist/lib/rime.dll` (3,727,872 bytes), `rime.lib` (its import
library, 301,656), `rime.pdb` (49,917,952: its symbols), `dist/bin/rime_deployer.exe` and two more tools, and
`dist/include/rime_api.h`, the same headers as the core's `Sources/CRime/include`. `ThirdParty/rime-data` is 126 MB,
76 MB of it the prebuilt dictionaries in `build/` (`rime_ice.table.bin` 60,703,784 bytes, `rime_ice.prism.bin`,
`.reverse.bin`, and those of `melt_eng` and `radical_pinyin`), built in about 20 s.

### Linking

The core has no unsafe flags: its `CRime` names the library (`link "rime"`) and the shell says where it is.
`Package.swift`'s `linksRime` passes `-L ThirdParty/librime/dist/lib` (for `rime.lib`) and delay-loads `rime.dll`
(`/DELAYLOAD:rime.dll`, `delayimp`): Windows doesn't look for it when the program starts, so the program loads it
itself, by its full path (`LoadLibraryExW`), before its first call into librime. The tests do that from `ThirdParty`
(`RimeFixture.loadLibrary`), where on the Mac an rpath to that folder does it; the input method will load it from its
own folder. `rime.dll` has the C++ runtime built in: it needs only `KERNEL32`, `USER32` and `dbghelp`, no Visual C++
redistributable.

### Tests

`Tests/AllInOneIMERimeTests` are the macOS shell's Rime tests (the root's `Tests/AllInOneIMERimeTests`), on Windows:
deployment from the prebuilt data, nihao → 你好, a sentence, punctuation and the ASCII mode, rime-ice's Lua date, the
Composer with the real engine (the action keys, @ commands, English mode, Caps Lock, Shift), a redeploy, fuzzy pinyin
(n ↔ l) and its rules in rime-ice's schema, and the learned words' sync through a shared folder. Added here: paging
(Page Down / Page Up and rime-ice's `=` / `-`), picking a candidate (by its place, its number key, on the second page),
learning (a word picked from the second page comes up front the next time), and `installation.yaml` as librime writes
it on Windows. Before `Scripts/fetch-librime.sh` they don't link, nor do the engine and the command line (no
`rime.lib`: `swift build` needs it too, and so does CI's Windows job); with librime but before
`Scripts/build-rime-data.sh` the engine tests fail, naming the folder, and the schema's is skipped unless
`ALLINONEIME_REQUIRE_RIME_DATA=1`. librime's warnings (glog) go to stderr and fail nothing: `circular dependencies
detected in melt_eng.schema` (`lua/lunar.db` is copied into the user folder as librime starts, since 0.6.7).

## What differs from macOS

- **The package**: a `.7z`, which Git Bash's tar can't read; Windows 11's own `tar.exe` (bsdtar, with LZMA) unpacks it,
  or 7-Zip's `7z` if that is on `PATH`. The plugins are built into `rime.dll`, not `rime-plugins/*.dylib`; there is no
  `rime_table_decompiler`.
- **Line ends**: librime writes its YAML files on Windows with `\r\n` (`installation.yaml`, `build/*.yaml`), which Swift
  takes for one Character: `components(separatedBy: "\n")` doesn't split them there. The core's `RimeSync` (the
  learned words' sync) reads `installation.yaml` by lines that end either way.
- **Paths**: librime takes its folders as UTF-8 (with forward slashes too), but gives them back
  (`get_user_data_sync_dir`, ...) in the ANSI code page; `RimeService.userDataSyncDir` decodes it so.
  `rime_deployer.exe` reads its arguments in the ANSI code page and takes them for UTF-8, so
  `Scripts/build-rime-data.sh` runs it inside `rime-data` with relative paths. All 24 tests pass with the user folder
  and `ThirdParty` under Chinese names (`临时`, `第三方`), as under a Chinese user name; that run started the test runner
  directly, since `swiftc` itself fails when `TMP` is outside ASCII.
- **The prebuilt dictionaries** are nearly portable. Built here, `*.table.bin` and `*.reverse.bin` are byte for byte the
  Mac's (those of the published Chinese pack, zh-pinyin 1.0.0). `rime_ice.prism.bin` and `radical_pinyin.prism.bin`
  differ only in the schema's checksum (a CRC of the compiled schema file, which has the sources' modification times in
  it, and `\r\n` here): two builds on Windows differ the same way. `melt_eng.prism.bin` (its English words) has one
  spelling more here (8,378,264 bytes against 8,377,216), for a reason not found yet. With the Mac's pack as the data
  all 24 tests pass too: librime uses its tables as they are; at the first deployment it builds `rime_ice`'s prism
  (40 KB) in the user folder, as it does `radical_pinyin`'s with either data. Deployment took 0.8 to 1.2 s with the
  pack and 0.3 to 0.8 s with the data built here, on files read before; up to 15 s on files just unpacked or with other
  builds running on the PC. So the Chinese pack the Mac downloads can serve Windows as it is;
  `Scripts/build-rime-data.sh` builds the data here instead, as `make deps` does on the Mac.
