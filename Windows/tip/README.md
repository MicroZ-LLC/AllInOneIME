# AllInOneIME text service for Windows (TSF TIP), M3

A thin C++20 Text Services Framework text input processor. It loads into every app, keeps a session per text field,
and asks the per-user engine (Swift, a later job) what each key does, over the named pipe of
`Core/docs/wire-protocol-v1.md`. This is the DLL side of that spec. Until there is an engine, a fake one stands in for
the tests.

## Layout

| Path | What |
|---|---|
| `AllInOneTIP.sln`, `AllInOneTIP.vcxproj` | the DLL; the solution also builds the tests |
| `Common.Configuration.props`, `Common.props` | the settings every project shares; they name no platform |
| `build.cmd` | finds MSBuild with vswhere and builds the solution |
| `dllmain.cpp` | the class factory, `DllGetClassObject`/`DllCanUnloadNow`, `DllRegisterServer`/`DllUnregisterServer` |
| `Globals.h`, `Guids.cpp` | the ids (CLSID, profile, display attributes), the languages, the COM-boundary guard |
| `TextService.{h,cpp}` | the TIP: activation, focus and sessions (§4), keys (§5), outputs (§6), pushes (§7), engine loss (§2.5) |
| `EditSession.{h,cpp}` | an `ITfEditSession` running a function, sync with an async fallback |
| `Composition.{h,cpp}` | our composition in one context: set, style, commit, end keeping the text |
| `DisplayAttributes.{h,cpp}` | the raw/draft/converted/target display attributes and their provider objects |
| `Document.{h,cpp}` | a context read into the wire's `FieldInfo` and `FieldContext`; secure and disabled fields |
| `Keys.{h,cpp}` | a key message read into the wire's `key` (§5.1) |
| `PipeClient.{h,cpp}` | the connection: connect and back off, the server check, the reader thread, request/wait, pushes |
| `ProcessInfo.{h,cpp}` | who this process is; where the DLL must stay passive (§2.1, §8); the server check |
| `Log.{h,cpp}` | a diagnostic log, off unless `AIO_TIP_LOG` names a file; types, ids and sizes only, never text |
| `wire/Wire.h`, `wire/WireJson.cpp` | the protocol as plain structs, and their JSON, by hand over nlohmann/json |
| `res/` | the version resource and a placeholder icon |
| `third_party/nlohmann/` | nlohmann/json 3.11.3, the single header, unchanged (MIT, `LICENSE.MIT`) |
| `test/goldens/*.jsonl` | the DLL's own golden transcripts (the engine's `notepad-improve`/`-click` are replayed from `Core`) |
| `test/common/` | `Transcript` (reads goldens, matches frames) and `FakeEngine` (the §2.1 pipe, replays a golden) |
| `test/tiptest/` | drives the registered DLL through real TSF against a golden; `TextStore` is its in-memory document |
| `test/wiretest/` | the wire layer, and `PipeClient` against the fake engine; no TSF |
| `test/fake-engine/` | the fake engine as a program of its own |
| `test/tsfstate/` | shows, and restores, the session's active input method |
| `test/e2edriver/`, `test/e2ehook/` | the end-to-end driver (real engine + real DLL, keys with SendInput, UIA read) and the hook it injects to put the profile on one app, and back |
| `test/run-in-session.sh`, `test/run-tests.sh` | run a test in the user's session; build, register and run them all |
| `test/run-e2e.sh` | the end-to-end harness (M3, M4): see "End to end" below |

## Build

```
build.cmd                 :: Release, x64
build.cmd Debug
build.cmd all             :: Debug and Release
```

It needs Visual Studio Build Tools 2022 (MSVC v143, the C++ workload) and a Windows 10/11 SDK. MSBuild only, no
CMake: `msbuild AllInOneTIP.sln -p:Configuration=Release -p:Platform=x64` from a Developer shell does the same. Outputs
go to `build\<Platform>\<Configuration>\`. Release links the static CRT, so the DLL loads into apps that don't ship the
VC++ runtime. Warnings are at level 4, and there are none.

**ARM64 or x86 later:** nothing in the props names a platform. Add `Debug|ARM64` and `Release|ARM64` (or `|Win32`)
`ProjectConfiguration` items to each `.vcxproj` and the matching lines to the solution, then `build.cmd Release ARM64`.
`Globals.h` already names the architecture for `hello.arch`.

## Registration

The TIP is a COM in-process server plus a TSF language profile. Registering needs an elevated shell:

```
regsvr32 /s   build\x64\Release\AllInOneTIP.dll     :: register
regsvr32 /u /s build\x64\Release\AllInOneTIP.dll    :: remove
```

`DllRegisterServer` writes, and `DllUnregisterServer` removes:

- `HKCR\CLSID\{DBB94280-C4C2-4C91-816F-79BB471AFE56}`: the DLL's path, `ThreadingModel=Apartment`;
- through `ITfInputProcessorProfileMgr::RegisterProfile`, the profile `{5BD6752B-379B-4ECD-9B1B-0819CBE55171}` named
  **AllInOneIME** for **en-US (0x0409)** and **zh-CN (0x0804)**, with the placeholder icon (resource 101), enabled by
  default (it can be picked in Settings);
- through `ITfCategoryMgr`, the categories **TIP_KEYBOARD**, **TIPCAP_IMMERSIVESUPPORT**, **TIPCAP_SYSTRAYSUPPORT**,
  **TIPCAP_UIELEMENTENABLED**, and **DISPLAYATTRIBUTEPROVIDER** (without it TSF doesn't ask for the display attributes).

Unregistering also removes what TSF keeps of the TIP under `HKLM\SOFTWARE\Microsoft\CTF\TIP\{CLSID}` and the user's
`HKCU\Software\Microsoft\CTF\TIP\{CLSID}` (the enabled flag), all of it this TIP's own. Registering doesn't add the
profile to anyone's keyboard list, and touches no other input method.

**To try it:** install it (`Windows/installer`, see `Windows/README.md`, "Installing"): the MSI registers the installed
DLL and adds it to the user's keyboard list. With a build registered by hand: Settings → Time & language → Language &
region → Chinese (Simplified) (or English (United States)) → Language options → Add a keyboard → AllInOneIME; or
`AllInOneIMESetup add-keyboard` (the installer's helper, `Windows/installer/setup`), which calls `InstallLayoutOrTip` as
the installer does (`remove-keyboard` to take it out). Then switch to it with Win+Space.

With no engine it passes every key through. Apps in an AppContainer load it only if ALL APPLICATION PACKAGES may read it: `run-tests.sh` grants that on the
built DLL (`icacls … /grant *S-1-15-2-1:(RX) *S-1-15-2-2:(RX)`); an installed copy under Program Files has it anyway.

## Tests, and where they can run

`bash test/run-tests.sh` (from an elevated shell, here an administrator's SSH session) builds Debug and Release,
registers the DLL, runs everything, and leaves the DLL registered only if every test passes; otherwise it unregisters
it again.

### Findings: SSH, the session, the foreground, the input settings

- **An OpenSSH session is session 0**, the services' session, with no interactive desktop. TSF isn't there at all:
  `CoCreateInstance(CLSID_TF_ThreadMgr)` fails with `E_FAIL`. The DLL's own guard (§2.1, §8) keeps it passive in session
  0 too, so `wiretest`'s pipe half reports a skip there. The wire half runs anywhere.
- **So the tests run in the logged-on user's session**, as one-shot scheduled tasks: `test/run-in-session.sh <name>
  <exe> [args]` writes a batch file, runs it with `schtasks /Create /SC ONCE /IT /RL LIMITED /RU <user>` and
  `schtasks /Run` (the limited, medium-integrity token an app has), waits for the exit-code file, prints the log and
  deletes the task. The user must be logged on. From an interactive session it just runs the exe.
- **TSF gives the document the focus only through a window that has the Win32 focus.** With `ITfThreadMgr::SetFocus`
  alone (`--focus=tsf`) TSF calls no `OnSetFocus` and `ITfKeystrokeMgr` delivers no key to the TIP. So `tiptest` shows a
  10×10 window, associates it with its document (`AssociateFocus`), gives it the focus, and makes it the foreground
  window so it keeps it (attaching to the foreground thread's input for the call if Windows refuses otherwise).
- **With Windows' default input settings the focused thread follows the session's input method, and the foreground
  thread's input method is the session's** (`SPI_GETTHREADLOCALINPUTSETTINGS` false, "use the same input method for
  every app"). As the test window took the focus, TSF switched its thread back to the session's input method (the TIP
  was deactivated right after `OnSetFocus`); with AllInOneIME active on the foreground thread, every app in the session
  switched to it. (An early run did exactly that: Explorer and other running apps loaded the DLL, and one connected to
  the fake engine. The session was switched back to Microsoft Pinyin with `tsfstate --restore`.) So `tiptest` makes the
  input settings per-thread for its run, in memory only (`SPI_SETTHREADLOCALINPUTSETTINGS` without
  `SPIF_UPDATEINIFILE`), activates the profile for its own thread only, and at the end puts its thread's previous input
  method back, closes its window, and then restores the settings; its watchdog restores them too. `run-tests.sh`
  records the session's input method (`tsfstate`) before the tests and checks it after; if it changed, it restores it.
- **Each test talks to its own pipe**, so the DLLs in the user's other apps never meet a fake engine: the test process
  sets `AIO_TIP_PIPE` to the §2.1 name plus a suffix, and the DLL in that process uses it. The DLL takes only a name that
  extends its real one, never starts the engine for it, and runs the server check as usual.

### `tiptest`: real TSF against a golden

`tiptest <golden.jsonl>` creates its own `ITfThreadMgr`, an in-memory `ITextStoreACP` (`TextStore`, with an
`IS_DEFAULT` or `IS_PASSWORD` input scope and a fixed caret box), checks the profile is registered under its name,
focuses its document (`AssociateFocus` and the Win32 focus), takes the foreground, and activates the AllInOneIME profile
with `ITfInputProcessorProfileMgr::ActivateProfile`: TSF itself loads the registered DLL and calls `ActivateEx`. It then
types the golden's keys through `ITfKeystrokeMgr` (`TestKeyDown`, and `KeyDown` if the TIP eats the key, as an app's
message loop does; the same for key-ups), plays the app by inserting the character of each key the TIP lets through,
moves the focus to another document (the blur) and pops the context (the close). At the end it checks the document's
text and that the fake engine saw exactly the golden's frames, no more.

Options: `--focus=associate` doesn't ask for the foreground (Windows may still give it when nothing holds it),
`--focus=tsf` uses `ITfThreadMgr::SetFocus` only; they show what TSF then doesn't do. `--direct` CoCreates the TIP and
calls its sinks itself, the way TSF would; it is only a fallback for a host where no window can take the foreground,
not the real test.

### `wiretest`

The canonical form of every frame the DLL sends (§1), UTF-16 offsets and surrogate pairs, and what the decoder takes
and refuses: unknown ops and styles (§6, §9), wrong types (`badMessage`), invalid UTF-8, nesting deeper than 16 and
non-objects (`badFrame`), framing. Then, in the interactive session, a real `PipeClient` against the fake engine: the
pipe, the server check, the handshake and a request.

### `fake-engine`

`fake-engine <golden.jsonl> [pipeName]` creates the pipe as §2.1 says (the name, `FILE_FLAG_FIRST_PIPE_INSTANCE`,
message mode, `PIPE_REJECT_REMOTE_CLIENTS`, 64 KiB buffers, the SDDL with `O:<UserSID>` added), runs §2.1's client check
(same session, same user; it notes the client's integrity and trust), sends the `<` lines and matches the `>` lines.
`tiptest` and `wiretest` link the same class. It keeps one pipe instance at a time, not the engine's four. It replays a
golden exactly, so a real app's frames (other ids, contexts and timings) don't match one.

### `tsfstate`

`tsfstate` prints the session's active keyboard input method and whether the input settings are per-thread.
`tsfstate --restore <langid> <clsid> <profile>` makes a profile the session's active one again, as the user switching
to it would; for example, back to Microsoft Pinyin:
`tsfstate --restore 0x0804 {81D4E9C9-1D3B-41BC-9E6C-4B40BF79E35E} {FA550B04-5AD7-411F-A5AC-CA038EC515D7}`.

### Goldens

The line format of §10: `>` a frame the DLL sends, `<` one the engine sends, `#` a comment, `#!` a directive. Bodies
compare as JSON values, key order ignored; `"$any"` matches any value, but the key must be there. Every body carries its
`"v":1` (the spec's text shows it only in the handshake). The host normalizes to `$any` what it can't reproduce and the
spec defines as host-derived: the key time `t`, `hello`'s `pid` and `tid`, and inside a `field`, `app`, `process` and
`layout` (the engine derives app and process itself; the KLID is the test machine's: `00000804` here).

The host's directives (the spec's own, `provider`, `inputLanguage`, `run tasks`, `click …`, are the engine's):

| Directive | Meaning |
|---|---|
| `#! no-engine` | no pipe at all |
| `#! secure` | the field's input scope is `IS_PASSWORD` |
| `#! expect-silence` | after the last line the DLL sends nothing (1.5 s, while the host types) |
| `#! expect-document "<text>"` | the document's text at the end |
| `#! type down\|up vk=N scan=N [char=c] [shift…]` | a key that sends no frame (a secure field's, a non-modifier key-up) |
| `#! double-test` | every key is tested twice before it is handled |
| `#! terminate` | the app ends the composition (`ITfContextOwnerCompositionServices::TerminateComposition`) |
| `#! wait <ms>` | the host runs its message loop for a while |
| `#! reconnect` | the engine drops the connection and takes the DLL's next one |
| `#! scope <n>` | the field's input scope becomes `n` (the DLL notices at its next key) |

The engine's goldens (`Core/Tests/AllInOneIMEWireTests/WireGoldens`) replay here unchanged: a `>`/`<` line without `v` is read as `"v":1` (the spec notes' format), and an `#! expect-document` argument is a JSON string. `run-tests.sh` runs the engine's `notepad-improve` and `notepad-improve-click` straight from there, so both sides are tested against the very same transcripts.

The keys the host types are those of the `>` keyDown/keyUp frames and of `#! type`, in order. After the last line, a
frame the golden doesn't list fails the test.

| Golden | What it checks |
|---|---|
| `notepad-improve` (from `Core`) | §10, the full "improve helo" run: plain keys pass, `@` starts a draft and shows the panel, the caret report, the Shift key-up, the composition grows (shown `improve › helo`), Enter converts, `1` commits "Hello.", blur, close; document "hi Hello." |
| `notepad-improve-click` (from `Core`) | §10's mouse variant: the engine pushes the commit (`apply`), the DLL answers `applied` with the new ctx (§7) |
| `terminated` | the app ends the composition: `endComposition {terminated}`, its commit (the draft as typed, `@i`) replaces the composition's range (§5.5); document "@i" |
| `retest` | each key tested twice: one request per key (§5.4 cache), a key-up ends a key, and TSF's own termination of the composition when the focus moves (then the blur) |
| `secure-field` | an `IS_PASSWORD` field: after the handshake nothing at all, and every key reaches the app (§8) |
| `engine-missing` | no engine: passive, every key passes (§2.5) |
| `timeout-resync` | a key unanswered mid-draft: after 150 ms the composition ends keeping the draft as typed (`@i`), the key passes, the late result is dropped, `endComposition {timeout}` resyncs and the engine's reset removes nothing (§5.4); document "@imx" |
| `reconnect` | the engine goes away mid-draft: the composition ends keeping the draft as typed (`@i`), the DLL reconnects, re-sends `open` and `focus` with a new serial (§2.5); document "@im" |
| `focus-resent` | the field's input scope changes mid-draft: `focus` is re-sent with the new field and the same serial (no blur), the draft goes on, and a push for that serial still applies (§4, §7) |

### Results (this machine, Windows 11 Pro 26200, x64)

Run in the logged-on user's session by scheduled task, with the Release DLL registered, every golden passes through
real TSF dispatch, and the Debug DLL passes them too:

```
wiretest                      PASS  (wire, and the pipe/server check/handshake/request in the session)
tiptest notepad-improve       PASS  26/26 frames, "hi Hello."     (the engine's golden, from Core)
tiptest notepad-improve-click PASS  26/26 frames, "hi Hello."     (the engine's golden, from Core)
tiptest terminated            PASS  11/11 frames, "@i"
tiptest retest                PASS  9/9 frames, "ll@"
tiptest secure-field          PASS  1/1 frames (the handshake), then silence, "hi@"
tiptest engine-missing        PASS  no engine, "hi@"
tiptest timeout-resync        PASS  11/11 frames, "@imx"
tiptest reconnect             PASS  12/12 frames, "@im"
tiptest focus-resent          PASS  10/10 frames, "Hi."
the session's input method    as it was
```

## End to end (M3–M7): the real engine and DLL, into a real edit control and real Notepad

`bash test/run-e2e.sh` runs the whole real stack in the logged-on session (a scheduled task, as the other tests): it
registers the DLL, and the driver (`e2edriver`) starts the real engine in that session (test mode, the scripted
provider, the system clock, so `@improve` streams in real time), activates the AllInOneIME profile, types "hi @improve
helo", Return and `1` with **SendInput**, and reads the result back through **UIA `TextPattern`**. Every key goes in
only while the target window has the foreground; the run stops at once if it ever doesn't, so no key reaches another
window. The engine runs in the session (not over SSH), so it and the DLL pass §2.1's same-session client check.

- **Default (hosted edit):** the driver types into a classic Win32 `EDIT` control in its own window. The DLL loads
  into that process, composes, and commits; the control reads back "hi Hello." Per-key round trips as the DLL times
  them (`QueryPerformanceCounter`) are in `Windows/README.md`.
- **Notepad (`--notepad`, `--probe`):** the only Notepad here is the Store (WinUI 3) app, and it composes: "hi Hello."
  (M4). M3 saw TSF never load the DLL into it because the profile was activated on the window's thread, while
  Notepad's text input (TextInputFramework) runs TSF on threads of its own; the hook now activates it for Notepad's
  process (below). The driver seeds its own temp file and finds, by UIA, the one document whose text is its unique
  marker; it only ever types into that document, never the user's tabs, and closes only its own saved tab. The Notepad
  is usually the user's own, already running: the hook gets the language and the log file from the driver through a
  named mapping (`Local\AllInOneIME-e2e-hook`), not the environment, and the driver reads the connection from the
  engine's log (a DLL an earlier run left loaded there keeps writing to that run's log).
- **`--installed`:** the installed copy (`Windows/installer`): the DLL the MSI registered, so no `regsvr32` before or
  after, and the installed engine; the language is the one the user's list has AllInOneIME under. The driver checks
  which DLL loaded: in its own window it must be the installed one. A Notepad that was running before the install keeps
  the DLL it had loaded (COM doesn't load a class's DLL again in a process) and is only reported.
- **`--plain TEXT`:** the engine as it runs for a user (no test mode, no provider), and TEXT typed and expected back as
  typed.
- **`--pinyin` (M5, M6):** the engine as it runs for a user, on settings of the run's own (English, then Chinese, as a
  new user's): the driver waits for librime to deploy, taps Shift, types "nihao", Space, "nihao", `1`, and expects
  "你好你好". **`--ai` (M7):** "@improve hello", Return, `1`, expecting "Hello there.", the engine's settings naming the
  Claude API at `Windows/Scripts/stub-provider.py`, which the script starts on localhost (never a paid API), with its key
  from the environment (`--no-keychain`: the user's Credential Manager isn't read). Except with the scripted provider,
  the engine gets a librime user folder of the run's own, so what a test types isn't learned in the user's.
- **The candidate window (M6):** for all but `--plain`, the driver finds the engine's window by its class
  (`AllInOneIME.CandidateWindow`) in the engine's process and checks it is up while the candidates or the results are, a
  layered, no-activate, topmost tool window, that the target kept the foreground, and (pinyin) that it went with the
  commit. It captures it as a PNG (the screen under it) into `build/test-logs/e2e-run-<scenario>/shots/`.

**Activating one app only.** A TSF text service has no HKL (activating it leaves the thread on the base US layout, and
it never appears in `GetKeyboardLayoutList`), so it can't be selected from outside with `WM_INPUTLANGCHANGEREQUEST` the
way a keyboard layout can, and `ActivateProfile` acts on the calling thread or, with `TF_IPPMF_FORPROCESS`, on the
calling process. So `e2ehook` is injected into the target's window thread (`SetWindowsHookEx(WH_GETMESSAGE)`) and runs
`ActivateProfile(TF_IPPMF_FORPROCESS)` there: every TSF thread of that one app, never the session. Per-thread input
settings are on for the run (`SPI_SETTHREADLOCALINPUTSETTINGS`, in memory, set and put back by the driver). Before the
driver unhooks, it posts `AllInOneIME-e2e-restore` and the hook puts the app back on the session's input method as the
driver found it, for the process. `run-e2e.sh` checks the session's input method is unchanged afterwards. The DLL stays
loaded in the app (TSF keeps objects of it, so COM never unloads it) until the app exits.

## Diagnostics

Set `AIO_TIP_LOG` to a file (for an app: in its environment) and the DLL appends what it does: activation, focus,
sessions, the connection, timeouts. Never typed text, frame bodies or key codes (§8). A Debug build also writes the
lines to the debugger.

## How the DLL reads the spec

Where the spec is silent, ambiguous or (in one place) can't work as written, the DLL does this; the Swift engine
should agree:

- **The server check (§2.1).** The spec's SDDL labels the pipe *low* (`S:(ML;;NW;;;LW)`), so "a label of medium or
  higher" never holds for the real engine, and a low-integrity squatter's pipe looks the same. The DLL checks that the
  server is in its session, that the pipe's owner is its user, and that the server *process*
  (`GetNamedPipeServerProcessId`) runs as its user at medium integrity or higher, outside an AppContainer. A
  low-integrity or AppContainer client can't open the server process; it checks session and owner only. The owner is
  deterministic only if the SDDL names it: the fake engine adds `O:<UserSID>` (the spec's SDDL leaves it to the token's
  default owner, which is Administrators for an elevated process).
- **Starting the engine (§2.5)** reads the value `Engine` of `HKLM\Software\AllInOneIME`, and doesn't start it while
  `Local\AllInOneIME-Engine-<SID>` exists, nor more than once per 10 s, nor for a test pipe.
- **Keys (§5.4).** The cache key `(wParam, lParam & 0x00FF0000)` alone can't tell a re-test from the next press of the
  same key: an unhandled key gets no `OnKeyDown` to clear it. A key's key-up clears its entry, and an entry stands at
  most 25 ms for an auto-repeat (lParam bit 30) and 500 ms otherwise. `OnTestKeyDown` also eats the key when pushes for
  the session wait to go in before it (§7), so `OnKeyDown` can apply them; `OnKeyDown` then says whether the app gets
  the key.
- **A timeout (§5.4)** doesn't wait for `endComposition {timeout}` (that would take the TSF thread past the budget): its
  result goes in when it comes, or before a later key's outputs if it comes first. Before the key passes, the DLL ends
  its composition keeping the text **as the user typed it** (`composition.typed`, not what the engine showed), so the
  app's key lands after the real text and the engine's reset (which now returns no composition, only `panel shown:false`)
  removes nothing. Same for a lost engine (§2.5): the kept text is the draft as typed.
- **Blur mid-composition (§4, §5.5).** TSF itself terminates the composition (`OnCompositionTerminated`) before it calls
  `OnSetFocus` when the focus moves to another document: the engine sees `endComposition {terminated}` and then `blur`,
  with nothing left to commit.
- **`focus` (§4).** A re-sent `focus` (a new layout or input scope, noticed at the next key) keeps the serial, so pushes
  already sent for that focus still apply; a new focus and a reconnect take a new serial. The serial is incremented
  only when a `focus` is actually sent.
- **Silent contexts (§8).** Besides `IS_PASSWORD`, `IS_NUMERIC_PASSWORD` and the PIN scopes, a context with
  `GUID_COMPARTMENT_KEYBOARD_DISABLED` or `GUID_COMPARTMENT_EMPTYCONTEXT` set (TSF's empty context of a document
  without one) gets no frames at all; nothing goes out for a context until its input scope has been read under a lock;
  a field that turns secure gets a `blur` and then nothing; `TF_TMAE_SECUREMODE` keeps the whole TIP passive.
- **Caret reports (§6)** go only while the panel is shown, also for the edit-session and layout triggers. The engine
  forgets the last caret when the panel hides, so a panel shown again waits for a fresh report rather than drawing where
  the old one was.
- **`applied` (§7)** is sent for a push merged into a key's edit session too, with the ctx right after its outputs.
- **Goldens.** The spec puts the C++ under `Apps/windows/tip/` and the goldens under
  `Core/Tests/AllInOneIMEWireTests/WireGoldens/`; here they are `Windows/tip/` and `Windows/tip/test/goldens/`. A
  replayer must ignore directives it doesn't know (the spec doesn't say), and the spec doesn't say whether `$any`
  matches a missing key (here it doesn't).
