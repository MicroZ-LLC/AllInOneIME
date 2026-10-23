# AllInOneIME wire protocol v1

**Status:** draft for M1–M3. **Scope:** the TSF DLL (C++) ↔ the per-user engine (Swift). Android's JNI layer and `AllInOneIMECAPI` carry the same JSON bodies. The Swift shells (macOS, iOS) call the core directly.

## 1. Conventions

- **Text:** JSON is UTF-8 without a BOM. Field names are camelCase. Integers stay within ±2^53.
- **Offsets:** every offset and length is in **UTF-16 code units**. TSF ACP positions, Android and JavaScript all count this way. The engine converts from Swift `Character`s.
- **Canonical form:** a sender omits any optional field that holds its default (`false`, `[]`, `null`, `0`). A receiver accepts the field either way.
- **Unknown names:** a receiver ignores fields it doesn't know. §9 covers unknown types and ops.
- **Wording:** "DLL" means any client and "engine" means the server.

## 2. Transport (Windows)

### 2.1 Pipe

- **Name:** `\\.\pipe\AllInOneIME-<UserSID>-v1`, for example `…-S-1-5-21-…-1001-v1`. The `-v1` suffix names the *framing* generation. It changes only if §2.2 changes. Message versions are negotiated in `hello`.
- **Creation:** the engine calls `CreateNamedPipeW` with:
  - `PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED`;
  - `FILE_FLAG_FIRST_PIPE_INSTANCE` on the first instance. If that fails, the engine exits, because something else holds the name;
  - `PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_REJECT_REMOTE_CLIENTS`;
  - 64 KiB in and out buffers.
- **Pending instances:** the engine keeps at least 4 instances waiting in `ConnectNamedPipe`. If the DLL gets `ERROR_PIPE_BUSY`, it calls `WaitNamedPipe` for 100 ms and retries.
- **Security descriptor (SDDL):**
  `O:<UserSID>D:P(A;;GA;;;<UserSID>)(A;;GA;;;SY)(A;;GRGW;;;AC)(A;;GRGW;;;S-1-15-2-2)S:(ML;;NW;;;LW)`
  - The user is the owner. The DLL's server check requires the pipe's owner to be the user (below); without `O:` the
    owner is the token's default, which is `Administrators` for an elevated engine, so it is named explicitly.
  - The user and SYSTEM get full access.
  - `ALL APPLICATION PACKAGES` and `ALL RESTRICTED APPLICATION PACKAGES` get read/write, so AppContainer apps can connect.
  - The low mandatory label lets low-integrity processes write.
- **Server check (DLL, before `hello`):** the DLL confirms that it reached the real engine.
  - `GetNamedPipeServerSessionId` must equal the DLL's own session.
  - `GetSecurityInfo(LABEL | OWNER)` on the handle must show the user's SID as owner and a label of medium or higher. A pipe created by a low-integrity squatter fails this check.
  - If either check fails, the DLL disconnects and stays passive.
- **Client check (engine, on connect):**
  - `GetNamedPipeClientSessionId` must equal the engine's session.
  - The engine opens the token of the process from `GetNamedPipeClientProcessId` and checks that its user is the same SID.
  - It records the client's integrity level and AppContainer flag (§8).
- **Processes where the DLL never connects:** SYSTEM, LocalService and NetworkService processes, and any desktop other than `Default` (Winlogon). There it stays passive and passes every key.

### 2.2 Framing and limits

- **One frame:** a u32 little-endian body length, then that many bytes of UTF-8 JSON (one object).
- **One frame per pipe message:** the prefix must equal the message size minus 4. Otherwise it is a `badFrame` error.
- **Why the prefix:** message mode makes it redundant on Windows. It is kept so the same bytes work over byte streams (replay CLI, sockets in tests). Transports that delimit calls themselves (JNI, `aio_send(handle, json, len)`) pass the body without the prefix.
- **Maximum frame size:**
  - DLL → engine: 64 KiB.
  - A settings window → engine, once it has the settings (§12: a trusted client that asked for them in `hello`):
    1 MiB, a list as long as the settings keep (2,000 English words of up to 40 characters) sent with the list the
    window showed (`shown`, §12.4). Its `hello` is within 64 KiB, the limit until then.
  - Engine → DLL: 1 MiB (a long answer committed in one frame).
- **Reading:** the reader grows its buffer on `ERROR_MORE_DATA` up to the maximum. Anything bigger gets `tooLarge` and the connection closes.
- **An answer the engine can't fit** in 1 MiB (a settings document with a huge word list) isn't sent; in its place,
  with the same `id` and `re`, goes `{"type":"error","code":"internal","message":"the answer is over the frame limit (… bytes)"}`,
  so that the client isn't left waiting. The connection goes on. (A push over the limit, which nobody waits for, is
  left out and logged.)

### 2.3 Connections

**One connection per TSF thread** (per text input processor instance):

- It opens in `ActivateEx` (asynchronously, so activation is never blocked) and closes in `Deactivate`.
- **Why not one per process:** TSF objects are apartment-threaded per thread. Each thread then waits on its own requests, and a hung UI thread can't stall another thread's keys. There is no cross-thread routing.
- **Threads:** each connection has one reader thread.
  - The TSF thread writes requests and waits on an event for the matching response.
  - The reader posts pushes to the TSF thread through a message-only window created on that thread.

### 2.4 Handshake

The first frame is `hello`. Its shape, and the shape of `welcome`, never change in any version.

```json
{"v":1,"id":1,"type":"hello","versions":[1],"client":"tip/0.7.0","platform":"win","arch":"x64","pid":4242,"tid":4250,"capabilities":["allowForeground"]}
{"v":1,"id":1,"re":1,"type":"welcome","version":1,"engine":"0.7.0","enginePid":3100,"capabilities":[],"limits":{"contextBefore":32,"selection":10002}}
```

- **Version:** `welcome.version` is the highest version both sides speak. From then on, every frame's `v` equals it.
- **No common version:** the engine replies `{"type":"error","code":"unsupportedVersion","versions":[2,3]}` and closes. The DLL stays passive until a different `enginePid` appears.
- **Capabilities:** optional features each side supports. Section 9 lists the v1 set.
- **Limits:** the engine may raise `contextBefore` (up to 256) and `selection` here.

### 2.5 Keepalive, restart, reconnect

- **Keepalive:** after 15 s with no traffic, while it has a focused session, the DLL sends `ping`. The engine answers `pong`. If no `pong` comes within 2 s, the DLL reconnects. The engine sends no pings; a dead client shows up as `ERROR_BROKEN_PIPE`.
- **Restart notice:** before exiting (update or restart), the engine sends `{"type":"bye","reason":"update","retryMs":500}`.
- **When the engine is lost** (`bye`, a broken pipe, a missing `pong`, or 3 key timeouts in a row), the DLL:
  1. ends every composition, **keeping its text** in the document, so nothing typed is lost;
  2. passes keys through;
  3. reconnects with backoff: 0, 250 ms, 1 s, 2 s, then every 5 s;
  4. after a new `welcome`, re-sends `open` for each live context and `focus` for the focused one.
- **Starting the engine:** on `ERROR_FILE_NOT_FOUND`, a DLL in a medium-integrity, non-AppContainer process starts the engine from the path in `HKLM\Software\AllInOneIME\Engine`. The engine is single-instance through a mutex, `Local\AllInOneIME-Engine-<SID>`. Other DLLs wait for the pipe to appear.
- **Engine watchdog:** if a session queue stalls for more than 2 s, the engine exits so it can be relaunched. The
  settings' work (§12) isn't on a session queue and doesn't count: a slow secret store never stops the engine.

## 3. Envelope and errors

- **Fields every frame carries:**
  - `v`: the protocol version.
  - `id`: a u32. Each side counts its own ids from 1, per connection.
  - `type`.
- **Session frames** also carry `sid`.
- **Responses** carry `re`, the id of the request they answer.
- **Request/response pairs:** these are the only requests. Every other frame is a notification, which gets no reply unless it fails.

| Request | Response |
|---|---|
| `hello` | `welcome` |
| `keyDown` | `result` |
| `keyUp` | `result` |
| `blur` | `result` |
| `endComposition` | `result` |
| `ping` | `pong` |
| `apply` (engine → DLL) | `applied` |
| `settingsGet`, `settingsSet`, `settingsAction` (§12) | `settings` |

- **Error frame:** `{"v":1,"id":9,"re":4,"type":"error","code":"noSession","message":"…"}`. `message` is English text for logs only and never contains user text.
- **Error codes:**

| Code | Meaning | Fatal? |
|---|---|---|
| `badFrame` | bad length or invalid UTF-8/JSON | yes: the sender closes |
| `tooLarge` | frame over the limit | yes |
| `unsupportedVersion` | no common version | yes |
| `unknownType` | type not known | no |
| `badMessage` | a required field missing or of the wrong type | no |
| `noSession` | unknown `sid` | no |
| `notFocused` | session not focused | no |
| `limit` | a rate or count exceeded | no |
| `internal` | engine-side failure | no |
| `notAllowed` | the settings (§12) asked for by a client that may not have them | no |

- **The DLL after an error on a key:** if a request it is waiting on returns `error`, it treats the request as `handled:false` with no outputs.

## 4. Sessions

**One session per `ITfContext`.**

- The DLL assigns `sid`, a u32 that is unique for the connection's lifetime. Ids survive reconnects, so opening a session needs no round trip.
- Async pushes name the exact document they target.
- The engine keeps an unfocused session as `FieldInfo` only. It may create the expensive state (Composer, Rime session) when the session first takes focus and drop it after blur.

### Messages

```json
{"type":"open","sid":1,"field":{"app":"win:notepad.exe","process":"notepad.exe","scopes":[0],"layout":"00000409"}}
{"type":"focus","sid":1,"focus":1}
{"type":"blur","sid":1}
{"type":"close","sid":1}
```

### FieldInfo

| Field | Meaning |
|---|---|
| `app` | `win:<exe>`, or `win:<AUMID>` for packaged apps |
| `process` | the process's executable name |
| `secure` | true for `IS_PASSWORD` (31) and the PIN and numeric-password input scopes |
| `readOnly` | from `TF_SD_READONLY` |
| `scopes` | the raw input scopes from `GUID_PROP_INPUTSCOPE` (platform-specific integers) |
| `layout` | the keyboard layout's KLID |

- **App identity:** the Windows engine works out `app` and `process` itself from the client's process id (`QueryFullProcessImageNameW`, `GetApplicationUserModelId`), and the values it derives override the client's. Clients without a process id (Android) report their own.

### When the DLL sends each message

- **`open`:** the first time a context takes focus.
- **`focus`:**
  - Sent on `ITfThreadMgrEventSink::OnSetFocus`.
  - `focus` is a serial number per session that increases with each focus.
  - Re-sent while focused, with a new `field`, when the keyboard layout or input scope changes. Re-sending doesn't blur.
- **`blur`:**
  - Sent before focusing the next context.
  - It is a request: the DLL waits for the answer (within the budget) and applies the result's outputs to the *old* context.
  - Today the core's policy there is `Composer.commitAll`: pending text goes in and running requests are cancelled.
- **`close`:** on `OnPopContext`, `OnUninitDocumentMgr` or `Deactivate`.

### Disconnects

- **The DLL disconnects:** the engine closes all of its sessions and cancels their tasks. It sends no outputs. Background work that isn't tied to a field (background scripts, agents) goes on.
- **The engine disconnects:** see §2.5.

## 5. Keys

### 5.1 `keyDown` and `keyUp`

```json
{"type":"keyDown","sid":1,"t":5000100,
 "key":{"vk":50,"scan":3,"text":"@","textIgnoringModifiers":"@","modifiers":["shift","leftShift"]},
 "ctx":{"sel":[3,3],"before":"hi "}}
```

**`key` fields:**

| Field | Meaning |
|---|---|
| `vk`, `scan`, `extended` | raw `wParam`; `lParam` bits 16–23; `lParam` bit 24 |
| `text` | `ToUnicodeEx(vk, scan, GetKeyboardState, …, flags 0x4, hkl)`. Flag 0x4 leaves the kernel's dead-key state alone. |
| `textIgnoringModifiers` | the same call with Ctrl and Alt cleared and Shift kept (the Mac's meaning) |
| `isDeadKey` | `ToUnicodeEx` returned < 0; `text` is the accent |
| `isRepeat` | `lParam` bit 30 |
| `modifiers` | the names from `Modifiers`' Codable form, side bits included, read with `GetKeyState` |

- **Key and usage:** the Windows DLL **does not** send `key` or `usage`. The engine computes them with `WindowsKeyCodes`, so the tables live in one place. Other clients send `key` (by `Key` name) and `usage` instead. If a frame has both, the raw values win.
- **Normalizing (engine side):**
  - Apply `markingAltGraph` (right Alt with Ctrl+Alt).
  - Drop side bits on key-downs of non-modifier keys.
  - Drop fake Shifts (`isFakeShift`).
- **Time:** `t` is `GetTickCount64()` in ms at the event. It only has to be consistent within a connection.

**FieldContext (`ctx`):**

| Field | Meaning |
|---|---|
| `sel` | the document selection `[start, end]` in absolute ACP; omitted when unknown |
| `before` | up to `limits.contextBefore` UTF-16 units before the selection start, or before our composition if one exists. The core needs only the last grapheme (`continuesWord`); 32 units covers the longest common clusters. |
| `selText` | sent only for a non-empty selection, capped at `limits.selection` |
| `selTruncated` | true if `selText` was cut off |
| `comp` | the length of our composition as the document has it now; omitted with no composition |

- **What the engine uses `comp` for:** it compares `comp` with what it set. A mismatch means the app took the text, which triggers `appTookMarkedText`.
- **Where `ctx` comes from:** the DLL caches it in `ITfTextEditSink::OnEndEdit` (a read cookie on every edit) and after its own edit sessions. In a secure field the DLL sends **no keys at all**.

### 5.2 Which keys are sent

- **Key-downs:** every key-down.
- **Key-ups:** only those of modifier keys (VK 0x10–0x12, 0x5B, 0x5C, 0xA0–0xA5). These are enough for Shift-tap and Ctrl-tap detection. The engine routes modifier downs and ups to `handleFlagsChanged` (the modifiers after the change), and everything else to `handleKeyDown`.
- **All key-ups:** if `welcome.capabilities` contains `keyUps`, the DLL sends every key-up.

### 5.3 Result

```json
{"type":"result","re":8,"handled":true,"outputs":[…]}
```

- **Applying outputs:** they are applied whether or not the key is handled, before the app sees the key. Example: a commit, then an arrow key passed on.
- **Plain text:** typing that composes nothing returns `handled:false` with no outputs.

### 5.4 TSF semantics: the test key does the work

- **No "would you handle this?" query.** The core's decision depends on its full state, so a separate predicate would duplicate it.
- **`OnTestKeyDown` sends `keyDown` and waits ≤ 150 ms.** Then:
  - It caches the result by `(wParam, lParam & 0x00FF0000)`.
  - It sets `*pfEaten = handled || !outputs.empty()`.
  - A repeated `OnTestKeyDown` for the same pending key reuses the cache.
- **`OnKeyDown`:**
  - Takes the cached result. If there is none (the app called `KeyDown` directly), it sends the key now.
  - Applies the outputs in `RequestEditSession(TF_ES_SYNC | TF_ES_READWRITE)`. If that fails with `TF_E_SYNCHRONOUS`, it falls back to `TF_ES_ASYNCDONTCARE`.
  - Returns `*pfEaten = handled`.
- **`OnTestKeyUp` and `OnKeyUp`:** the same, with `keyUp`.

**Budget:**

- The engine answers keys in under 20 ms (p99) and never does I/O on the key path.
- If 150 ms pass with no answer, the DLL:
  1. passes the key through;
  2. discards the late result when it arrives;
  3. sends `endComposition {sid, reason:"timeout"}` to bring the two sides back in step;
  4. closes the connection after 3 timeouts in a row.

### 5.5 `endComposition`

`{"type":"endComposition","sid":1,"reason":"terminated"}`

- **Reasons:** `"terminated"` comes from `ITfCompositionSink::OnCompositionTerminated`; `"timeout"` comes from §5.4.
- **Applying the result:** the DLL applies the result's outputs with the write cookie it was given. A `commit` there replaces the range the composition covered.
- **Engine side:** `commitAll` for `terminated`. For `timeout`, the engine resets its draft and returns `panel shown:false` with **no** `composition`: the DLL has already ended the composition (keeping the draft as typed) and the app has had the key, so an empty `composition` would only remove text the document should keep. The two sides are back in step.

## 6. Outputs

`outputs` is an ordered array of `{op, …}` objects. They are applied in order, in a single edit session.

| op | Fields | DLL action |
|---|---|---|
| `commit` | `text`, `deleteBefore`, `deleteAfter`, `afterKey` | **R** = our composition range if there is one, else the selection. Extend R by `deleteBefore`/`deleteAfter` units (clamped). Replace R with `text`, end the composition, and put the caret after `text`. With `afterKey: true`, apply in a separate `TF_ES_ASYNC` session, after the app has had the key (the Composer's `commitAfterKey`). |
| `composition` | `text`, `caret`, `segments: [{from,to,style}]`, `typed` | Start the composition if needed, set its text, and set the selection to start + `caret`. Map each segment's `style` to a registered display attribute: `raw`, `draft`, `converted` or `target`. Parts not covered, and unknown styles, are `raw`. Empty `text` removes the text and ends the composition. `typed` (optional) is the draft as the user typed it, present only when that differs from the shown `text` (the Composer shows a command without its "@": "@improve helo" shows `improve › helo`). The DLL keeps `text` while composing; if it ends the composition on its own — a key timeout (§5.4) or a lost engine (§2.5) — it leaves `typed` in the document instead, so the user keeps what they typed, "@" and all. |
| `panel` | `shown` | The engine is or isn't showing UI anchored at the caret. While `shown`, report `caret` (below). |
| `allowForeground` | none | `AllowSetForegroundWindow(enginePid)`, before the engine opens a URL, path or terminal. Only for clients that announced `allowForeground`. |

**Caret reports (DLL → engine notification):**

```json
{"type":"caret","sid":1,"rect":[812,440,9,20],"hwnd":198940}
```

- **`rect`:** `ITfContextView::GetTextExt` of the composition's first character, or of the empty selection when there is no composition.
  - Coordinates are physical screen pixels: convert with `LogicalToPhysicalPointForPerMonitorDPI(hwnd)` for windows that aren't per-monitor aware.
  - On `TS_E_NOLAYOUT`, wait for `OnLayoutChange`.
  - If it fails, send `GetWindowRect(GetWnd)` with `"exact":false`.
- **When to send:**
  - when `panel` becomes shown;
  - after every edit session that changed the rect;
  - on `ITfTextLayoutSink::OnLayoutChange`.
  - At most one report per 16 ms, and only if the rect changed.
- **Engine side:** before its first draw, the engine waits up to 50 ms for a caret report.

**What the engine does itself (never on the wire):**

- drawing candidates and notices (in its own window);
- reading and writing the clipboard;
- opening URLs and paths, terminals and agents, notes, reminders and messages;
- voice, AI, scripts and search;
- **type out:** the engine pushes a series of `apply` frames, one `commit` per step, and fixes typos with `deleteBefore`. Each step waits for the previous `applied`. No `SendInput`.

## 7. Async pushes

```json
{"type":"apply","sid":1,"focus":1,"outputs":[{"op":"commit","text":"Hello."},{"op":"panel","shown":false}]}
{"type":"applied","re":5,"ok":true,"ctx":{"sel":[9,9],"before":"hi Hello."}}
```

**Delivery on the DLL side:**

- The reader thread posts each `apply` to the TSF thread. That thread calls `RequestEditSession(tid, s, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE)` on the session's context.
- After `DoEditSession`, it replies `applied` with the new `ctx`.
- **Refusals:** it replies `ok:false` with a `reason`:
  - `notFocused`: the session isn't focused, or `focus` isn't the current serial;
  - `gone`: the context was popped;
  - `readOnly`;
  - `denied`: `RequestEditSession` failed.

**Ordering:**

- Outputs are applied in the order the engine sent them.
- If an `apply` arrives while a key result is awaited, it is applied first, in the same edit session as the key's outputs.

**Engine rules:**

- The engine pushes `composition` and `commit` only to the focused session, with its current `focus` serial.
- It coalesces queued `composition` pushes per session, so only the latest is sent.
- It drops a connection whose unacknowledged outbound data passes 256 frames or 4 MiB.

**Streaming:**

- **Into the panel:** `@improve` versions stream into the engine's own panel, so nothing crosses the pipe.
- **Into the field:** Translate as You Type and type-out stream as `apply` pushes with `composition`, then one `apply` with `commit`.
- **Esc during a stream:** an ordinary `keyDown`. The engine cancels the task and returns the draft. Later stream updates are dropped in the engine, because the task id no longer matches.
- **Focus moves away during a stream:** that is a `blur` (§4), and its result carries the outputs. No push follows for that focus.

## 8. Security

- **Who may connect:** same user, same session (§2.1). The engine records each connection's trust:
  - **`trusted`:** medium integrity or higher, not in an AppContainer.
  - **`untrusted`:** low integrity or AppContainer.
- **No secrets over the pipe:**
  - API keys, tokens and credentials never travel, with one exception: a key a settings client saves goes once, from
    the client to the engine, and never comes back (§12.8).
  - Secure fields send neither keys nor context.
  - Logs record sizes and types, never payloads.
- **What a malicious low-integrity or AppContainer process could do, and the bound on each:**

| Threat | Bound |
|---|---|
| Forged keys typing `@run …`, `@open`, `@agent` or link commands (sandbox escape, exfiltration) | `untrusted` sessions get only level-one typing (Rime, Hangul, Latin) and AI rewrite/translate of their own text. Everything that runs, opens, searches files, reads the clipboard, recalls history or sends is refused with a notice. For every client, privileged effects also require the client's process to own the foreground window when the key arrives. |
| A fake `app` to pick another app's profile | The engine derives `app` itself (§4). |
| Oversized or malformed frames | Size caps (§2.2). JSON depth ≤ 16. Invalid UTF-8 → `badFrame` and the connection closes. |
| Oversized fields | `text` ≤ 64 units, `before` ≤ 256, `selText` ≤ `limits.selection`, `app` ≤ 256, `scopes` ≤ 32 entries. Anything over → `badMessage`. |
| Floods and exhaustion | ≤ 64 sessions per connection, ≤ 64 connections per process, ≤ 256 in total. ≤ 200 keys/s per connection (over that: `limit`, `handled:false`, no work done). New connections rate-limited per process. |
| Lying in `applied` | It only affects that client's own document. |
| Pipe squatting (a fake engine logging every key) | The DLL's server check (§2.1). |

## 9. Versioning and forward compatibility

- **Minor additions stay in v1:**
  - new optional fields;
  - new types and ops, gated by a capability the receiver announced. The engine never sends an op the client didn't announce beyond the core four, `commit`, `composition` and `panel`.
- **Unknown names:**
  - an unknown op in `outputs` is skipped;
  - an unknown type from the DLL gets `error unknownType`;
  - the DLL silently ignores unknown types from the engine.
- **v1 capabilities:**
  - client: `allowForeground`, `settings` (§12);
  - engine: `keyUps`, `limits.contextBefore`, `limits.selection`, `settings` (§12).
- **v2:** breaking changes only. The client sends `versions:[1,2]`. The engine keeps one decoder and encoder per version, both mapping to the same internal model, and speaks the current version and the one before it: a DLL left in a long-running app after an update still connects.

## 10. Golden transcript (`WireGoldens/notepad-improve.jsonl`)

**Line format:**

- `>` DLL → engine, `<` engine → DLL, `#` comment, `#!` fixture directive.
- The `"v":1` in each body is shown here only in the handshake.
- **Matching:** bodies compare as JSON values, ignoring key order. `"$any"` matches any value.

```
#! provider fixtures/improve-hello.json   (scripted stream: "Hello." / "Hi there." / "Hello!")
#! inputLanguage english
> {"v":1,"id":1,"type":"hello","versions":[1],"client":"$any","platform":"win","arch":"x64","pid":4242,"tid":4250,"capabilities":["allowForeground"]}
< {"v":1,"id":1,"re":1,"type":"welcome","version":1,"engine":"$any","enginePid":"$any","capabilities":[],"limits":{"contextBefore":32,"selection":10002}}
> {"id":2,"type":"open","sid":1,"field":{"app":"win:notepad.exe","process":"notepad.exe","scopes":[0],"layout":"00000409"}}
> {"id":3,"type":"focus","sid":1,"focus":1}
# "hi" and a space: plain English passes through
> {"id":4,"type":"keyDown","sid":1,"t":1000,"key":{"vk":72,"scan":35,"text":"h","textIgnoringModifiers":"h"},"ctx":{"sel":[0,0]}}
< {"id":2,"re":4,"type":"result"}
> {"id":5,"type":"keyDown","sid":1,"t":1120,"key":{"vk":73,"scan":23,"text":"i","textIgnoringModifiers":"i"},"ctx":{"sel":[1,1],"before":"h"}}
< {"id":3,"re":5,"type":"result"}
> {"id":6,"type":"keyDown","sid":1,"t":1250,"key":{"vk":32,"scan":57,"text":" ","textIgnoringModifiers":" "},"ctx":{"sel":[2,2],"before":"hi"}}
< {"id":4,"re":6,"type":"result"}
# Shift+2 types "@" after a space: a draft starts (after a letter, "@" would just be text)
> {"id":7,"type":"keyDown","sid":1,"t":1400,"key":{"vk":16,"scan":42,"modifiers":["shift","leftShift"]},"ctx":{"sel":[3,3],"before":"hi "}}
< {"id":5,"re":7,"type":"result"}
> {"id":8,"type":"keyDown","sid":1,"t":1480,"key":{"vk":50,"scan":3,"text":"@","textIgnoringModifiers":"@","modifiers":["shift","leftShift"]},"ctx":{"sel":[3,3],"before":"hi "}}
< {"id":6,"re":8,"type":"result","handled":true,"outputs":[{"op":"composition","text":"@","caret":1,"segments":[{"from":0,"to":1,"style":"draft"}]},{"op":"panel","shown":true}]}
> {"id":9,"type":"caret","sid":1,"rect":[812,440,9,20],"hwnd":"$any"}
> {"id":10,"type":"keyUp","sid":1,"t":1550,"key":{"vk":16,"scan":42},"ctx":{"sel":[4,4],"before":"hi ","comp":1}}
< {"id":7,"re":10,"type":"result"}
# … "improve hell": ids 11–22 and 8–19, the same shape, the composition growing …
> {"id":23,"type":"keyDown","sid":1,"t":3900,"key":{"vk":79,"scan":24,"text":"o","textIgnoringModifiers":"o"},"ctx":{"sel":[16,16],"before":"hi ","comp":13}}
< {"id":20,"re":23,"type":"result","handled":true,"outputs":[{"op":"composition","text":"@improve hello","caret":14,"segments":[{"from":0,"to":14,"style":"draft"}]}]}
> {"id":24,"type":"keyDown","sid":1,"t":4300,"key":{"vk":13,"scan":28,"text":"\r","textIgnoringModifiers":"\r"},"ctx":{"sel":[17,17],"before":"hi ","comp":14}}
< {"id":21,"re":24,"type":"result","handled":true,"outputs":[{"op":"composition","text":"@improve hello","caret":14,"segments":[{"from":0,"to":14,"style":"converted"}]}]}
#! run tasks        (the three versions stream into the engine's panel: no frames)
> {"id":25,"type":"keyDown","sid":1,"t":6100,"key":{"vk":49,"scan":2,"text":"1","textIgnoringModifiers":"1"},"ctx":{"sel":[17,17],"before":"hi ","comp":14}}
< {"id":22,"re":25,"type":"result","handled":true,"outputs":[{"op":"commit","text":"Hello."},{"op":"panel","shown":false}]}
> {"id":26,"type":"blur","sid":1}
< {"id":23,"re":26,"type":"result"}
> {"id":27,"type":"close","sid":1}
```

**The same pick made with the mouse** (`notepad-improve-click.jsonl`): the engine pushes the commit instead of returning it in a key result.

```
#! click row 0
< {"id":22,"type":"apply","sid":1,"focus":1,"outputs":[{"op":"commit","text":"Hello."},{"op":"panel","shown":false}]}
> {"id":25,"re":22,"type":"applied","ok":true,"ctx":{"sel":[9,9],"before":"hi Hello."}}
```

**Other goldens:**

- `secure-field`
- `esc-mid-stream`
- `blur-mid-stream`
- `terminated`
- `focus-moves`
- `focus-resent`
- `timeout-resync`
- `reconnect`
- `unknown-type`
- `limits`
- `settings` (§12)

## 11. What lives where

### Swift: target `AllInOneIMEWire` in `Core/Package.swift` (all platforms, depends on AllInOneIMECore)

**Files:**

- `WireMessages.swift`: Codable `ClientMessage` and `EngineMessage` enums (with `.unknown(type)` for types not known), `WireKey`, `WireField` (§4's FieldInfo) and `WireContext` (§5.1's FieldContext), named apart from the core's session types, `Output`.
  - Reuses `Key` and `Modifiers`' existing Codable forms.
  - The encoder uses `.sortedKeys` and omits defaults.
- `WireFrame.swift`: the length prefix, the limits and the checks.
- `WireServer.swift`: independent of the transport.
  - API: `receive(_ body: Data, on: ConnectionID) -> [Data]`, plus a `push` closure.
  - It owns the connections, the sessions, trust, the rate limits and one serial queue per connection.
  - Errors are listed in §3.
- `ComposerSession.swift`: the adapter used until `InputSession` (plan step 8) exists.
  - Builds a `KeyEvent(key:usage:…)` from `WindowsKeyCodes`.
  - Sets `readSelection` and `characterBeforeCaret` from `ctx`, `secureInputActive` from `field.secure`, and `appTakesKeysAfterInsert` from a list of terminals.
  - Maps Effects:
    - `updateMarkedText` → `composition` (UTF-16 caret; style `draft`, or `converted` at level two; empty when `draftInPanel`);
    - `commit` / `commitAfterKey` / `replaceSelection` → `commit`;
    - `showPanel` / `hidePanel` → the engine panel plus `panel` (on change only);
    - everything else → a `WireHost` protocol, the engine's equivalent of `perform`.
  - Later `InputSession` replaces it, and `SessionOutput` maps one-to-one.
- **Pipe listener:** `PipeListener` lives in `AllInOneIMEWindows` (Windows only).
- **Golden tests:** `AllInOneIMEWireTests` replays `Core/Tests/AllInOneIMEWireTests/WireGoldens/*.jsonl` with a scripted provider, a manual clock and a task runner that runs until idle after each `>` line.
- **Real pipe (M2):** `allinoneime-cli wire-replay` replays the same files over the real pipe.

### C++: `Apps/windows/tip/`

**Files:**

- `wire/Wire.h`: plain structs (`KeyDown`, `FieldInfo`, `FieldContext`, `Output` as a `std::variant`, `Result`).
- `wire/WireJson.cpp`: `to_json` and `from_json`, written by hand.
- `PipeClient.{h,cpp}`: connect, the server check, the reader thread, request/wait with timeout, the push queue.
- **JSON library:** vendor **nlohmann/json 3.11.3** (single header, MIT) in `third_party/`.
  - A hand-rolled writer is easy, but a correct reader isn't (escapes, surrogates, UTF-8 validation).
  - Use `json::parse(…, nullptr, false)` and checked accessors (`contains` / `is_*`), so bad input never throws on the hot path.
  - Compile with `/EHsc`. Catch at the frame boundary, and never let an exception cross a COM method.
- **Tests:** `tiptest.exe` replays the same goldens.
  - A fake pipe server sends the `<` lines.
  - The test synthesizes each `>` key frame's `vk`, `scan` and `modifiers` through `ITfKeystrokeMgr`.
  - It checks the frames the DLL sends against the `>` lines.


## 12. Settings (v1, capability `settings`)

A settings window (Windows' Settings app, a separate C# WinUI 3 program) reads and changes the settings through the
engine, over the same pipe, framing and handshake. **The core decides everything:** what there is to set, its text (in
the interface language), which fields apply now and on this platform, whether a change is valid, and the rules each
change follows (the same as the Mac's settings window: the core's `SettingsStore`). The client draws the document it is
given and sends back what the user did. It opens no sessions.

### 12.1 Handshake

```json
{"v":1,"id":1,"type":"hello","versions":[1],"client":"settings/0.7.0","platform":"win","arch":"x64","pid":5120,"capabilities":["settings"]}
{"v":1,"id":1,"re":1,"type":"welcome","version":1,"engine":"0.7.0","enginePid":3100,"capabilities":["settings"],"limits":{"contextBefore":32,"selection":10002}}
```

- **Granted** (`settings` in `welcome.capabilities`) when the client asked, is `trusted` (§8: medium integrity or
  higher, not in an AppContainer) and the engine has settings.
- **Not granted:** the settings frames get `error notAllowed` when the client asked, `unknownType` when it didn't (as
  any unknown type, §9). Text services (the DLL) don't ask.

### 12.2 Messages

| Client → engine (request) | Fields | Engine → client |
|---|---|---|
| `settingsGet` | — | `settings` |
| `settingsSet` | `field`, `value`; optional: `revision`, `shown` (§12.4) | `settings` |
| `settingsAction` | `field`, `action`, and as the action takes: `item`, `value`, `key` | `settings` |

| Engine → client (notification) | Fields |
|---|---|
| `settingsChanged` | `revision` |

```json
{"v":1,"id":2,"type":"settingsGet"}
{"v":1,"id":2,"re":2,"type":"settings","revision":1,"document":{…}}
{"v":1,"id":3,"type":"settingsSet","field":"maxTokens","value":1500}
{"v":1,"id":3,"re":3,"type":"settings","revision":2,"document":{…}}
{"v":1,"id":4,"type":"settingsChanged","revision":2}
{"v":1,"id":4,"type":"settingsSet","field":"maxTokens","value":50}
{"v":1,"id":5,"re":4,"type":"settings","revision":2,"problem":{"code":"badValue","field":"maxTokens","message":"Between 200 and 4000"},"document":{…}}
{"v":1,"id":5,"type":"settingsAction","field":"anthropic.key","action":"setKey","key":"sk-ant-…"}
{"v":1,"id":6,"re":5,"type":"settings","revision":3,"document":{…}}
{"v":1,"id":7,"type":"settingsChanged","revision":3}
{"v":1,"id":6,"type":"settingsSet","field":"maxTokens","value":2000,"revision":2}
{"v":1,"id":8,"re":6,"type":"settings","revision":3,"problem":{"code":"stale","field":"maxTokens","message":"The settings changed meanwhile: …"},"document":{…}}
{"v":1,"id":7,"type":"settingsSet","field":"redaction.customWords","value":["Acme","Mine"],"shown":["Acme"]}
{"v":1,"id":9,"re":7,"type":"settings","revision":4,"document":{…"value":["Acme","Elsewhere","Mine"]…}}
{"v":1,"id":10,"type":"settingsChanged","revision":4}
```

**`settings`**, the answer to all three:

| Field | Meaning |
|---|---|
| `revision` | moves with each change of the settings or the keys (u64); the document's. Counted from 1 by each engine process: after a reconnect (a new `welcome`) fetch the document again |
| `document` | the settings as they are now (§12.3): after the change, or as they were when it was refused |
| `problem` | a change or action refused: `{code, field, message}` (§12.4) |
| `message` | what an action that worked says: a test's outcome, "✓ 1.2 s: …" |

- `problem.message` and `message` are interface text for the user, in the interface language. They never repeat the
  value sent. (An `error` frame's `message` stays English for logs, §3.)
- An `error` frame instead of `settings` means the frame itself is wrong: `badMessage` (a field missing, `value`
  missing: null is a value, no value isn't), `notAllowed`, `unknownType`.

### 12.3 The document

```json
{"language":"en","platform":"windows","sections":[
  {"id":"general","title":"General","fields":[
    {"id":"typeOut","kind":"toggle","label":"Type results out","help":"A command's result is typed in …","value":false},
    {"id":"uiLanguage","kind":"choice","label":"Interface language","choices":[{"value":null,"label":"Follow the system"},{"value":"en","label":"English"},{"value":"zh-Hans","label":"简体中文"}]}]},
  {"id":"provider","title":"AI Provider","fields":[
    {"id":"provider","kind":"choice","label":"Provider","value":"anthropic","choices":[{"value":"bedrock","label":"Amazon Bedrock"},{"value":"anthropic","label":"Claude API"},…]},
    {"id":"anthropic.model","kind":"text","label":"Model","placeholder":"claude-haiku-5-5","optional":true,"choices":[{"value":"claude-haiku-5-5","label":"Claude Haiku 5.5","note":"Default: fastest, cheapest"},…]},
    {"id":"anthropic.key","kind":"secret","label":"API key","status":"✓ Saved · ends in a1b2","isSet":true,"actions":["setKey","removeKey"]},
    {"id":"provider.test","kind":"button","label":"Test Connection","actions":["test"]}]},
  …]}
```

- **Document:** `language` (the text's: "zh-Hans", "en", "fr" …: the settings' `uiLanguage`, else the system's, as the
  engine's panel picks it; changed, the answer's document is in the new one already), `platform` (`windows`, `mac`),
  `loadError` (the config file can't be read: every field is `readOnly`, nothing is changed, the file stays as it is),
  `saveError`, `sections`, `strings`.
- **`strings`:** the words of the window's own controls, in the interface language, by name, so that a client has no
  text of its own: `window.title`; the button of each action, `action.<action>` ("action.setKey": "Save",
  "action.cancel": "Cancel"), and `action.<action>.item` where an item's differs from the field's (`action.save.item`:
  "Edit…", `action.save`: "New…"); the question an action that deletes asks first, `confirm.<action>` with `{name}`
  for what it deletes ("Delete “{name}”?"; `confirm.removeItem` for an item's `remove`); `save`, `cancel`, `choose` (a
  `picker`'s), `moveUp`, `moveDown`, `remove`, `add` (an ordered list's), `paste` (an empty secret's box), `working`
  (an action under way, `running`). A client keeps its own words for a name that isn't there (an older engine).
- **Section:** `id`, `title`, `footer` (a note under it), `fields`. Sections without fields are left out.
- **Field:** `id` (what `settingsSet` and `settingsAction` name), `kind`, `label`, and as it has them: `help`, `value`,
  `placeholder` (what an empty text stands for: the default), `choices` (`{value, label, note, disabled}`), `ordered`,
  `minCount`, `maxCount`, `min`, `max`, `step`, `optional`, `readOnly`, `platforms`, `status`, `isSet`, `actions`,
  `items` (`{id, title, detail, value, actions, running, fields}`), `running` (an action that takes a while runs now,
  §12.5), `text`, `multiline` (a text of several lines), `picker` (`file` or `folder`: a path, picked with the system's
  open panel; `jargonFile`, `notes.folder`; on an `items` field, the path its `add` takes: `extensions.folders`),
  `textActions` (its actions that take a text the user types, sent as the action's `value`: `notes.notion`'s `test`
  takes the link, `add` the app or the folder; `placeholder` the box's hint), `schema` (what its items' `value` is,
  below), `when` (in a `schema`).
  - `items[].fields`: an item's own settings (an app's, an extension's switch and preferences), fields as any other:
    set and acted on by their `id`, which is unique in the document.
  - `text` (`words`): the list as the one line the field shows (", " between the words, or a command line); `settingsSet`
    takes such a line as well as the list, and splits it the same way (`shown` too, §12.4). A command line
    (`agentCommand`, a command's `argv`) is written and split by the document's platform's rules: on Windows
    `CommandLineToArgvW`'s (`C:\Tools\run.exe "C:\My Files\a.txt"`: a backslash is itself except before a `"`), on the
    Mac a shell's words (`\` escapes, '…' quotes).
- **`schema`** (`commands.custom`): the fields of a custom command's definition, the `value` its items carry and `save`
  takes, as the Mac's command editor shows them. Each field's `id` is a key of that object, its `kind`, `label`,
  `help`, `placeholder`, `choices`, bounds and `optional` as for any field, its `value` what a new command starts with.
  `when` (`{"type": ["run", "terminal"]}`) says which values other fields of the definition must have for it to apply:
  leave the others out of the `value` sent. An `info` field in it is text to show (the warning about programs). A
  `words` field of it (`argv`) may be sent as the line typed, a command line. A definition is checked when saved
  (§12.5). Send back the keys of the item's `value` the schema doesn't name (`icon`, `color`) as they were: what isn't
  sent isn't kept.
- **Canonical form** (§1): what a field doesn't have is left out, and so is a `value` that is null: no `value` means
  null (a text not set, "follow the system").

| `kind` | `value` | `settingsSet` takes |
|---|---|---|
| `toggle` | bool | a bool |
| `integer` | number | a whole number in `min`…`max`, in steps of `step` from `min` |
| `number` | number, or null when `optional` | a number in `min`…`max`; null when `optional` (`step`: a slider's) |
| `text` | string or null | a string; null when `optional`. `choices`, if any, are suggestions |
| `choice` | one of `choices`' values | one of them, not `disabled` unless it is the value now (null when a choice's value is null) |
| `choices` | an array of `choices`' values | each once, `minCount`…`maxCount` of them; `ordered`: the order matters (the first is the default); a `disabled` one only if the value has it |
| `words` | an array of strings | an array of strings; `ordered`: the order is its meaning (a command's arguments) |
| `secret` | — (never) | — : `status`, `isSet`; changed with `setKey` / `removeKey` |
| `items` | — | — : each item's `actions`, and the field's |
| `info` | text to show | — |
| `button` | — | — : its `actions` (one); `status`: what the last run said |

- **Values outside the choices:** a `choice` or `choices` value the field doesn't offer (another platform's, a later
  version's rewrite style, a translation language only `config.json` names, a thinking level written by hand) is in
  `choices` too, `disabled`, labelled as well as the engine can. It is kept as it is: sent back (in a `choices` list,
  moved), it is taken; left out of a `choices` list, it stays where it was; it is never picked anew. The field can
  always be changed.
- **Which fields apply:** only those that apply *now* are in the document: a provider's own fields while it is the one
  in use, the typing speed while typing out is on, fuzzy pinyin and the English words with Chinese among the input
  languages. After a change, draw the new document: fields come and go.
- **Which platform:** a document is made for the client's platform (the engine's: `windows`). The Mac's own fields
  aren't in Windows' document: `iCloudSync`, `menuBarIcon`, `checkForUpdates`, `voiceInput` (while voice input is
  on: off for now, `Features.voiceInput`, so in neither), `agentPageContext` (Chrome's page). Nor are the Mac's choices: the action keys `optionTap` and `optionSpace`, Apple Notes
  (`notes.destination` `notes`), the providers `apple` (Apple Intelligence) and `hosted` (its sign-in is the Mac's). A
  choice only the other platform has is shown, `disabled`, when it is the value now (Apple Notes, a new user's
  default). Messages (`@imessage`) has no setting. A field's `platforms`, when present, says where it applies. Its
  text is the platform's too: Windows' names its keys (Enter, Ctrl+Space) and places (a terminal window, this PC,
  `cmd /c` for a shell, the Credential Manager), and writes a folder in the home folder from `%USERPROFILE%`
  (`extensions.folders`' placeholder and titles; one typed so is taken, its `%NAME%`s written out). Its paths are
  Windows', whatever the system it is made on: the jargon list's default file `%APPDATA%\AllInOneIME\jargon.txt`
  (`jargonFile`'s placeholder; a `jargonFile` with `%NAME%`s is read with them written out), the config file and the
  error that names it with backslashes (`configFile`, `loadError`).
- **Field ids** (stable; a later version may add fields, and a client draws any it is given):

| Section | Fields |
|---|---|
| `general` | `actionKey`, `typeOut`, `typeOutRate`, `typeOutVaries`, `typeOutMistakes`, `useSelection`, `rememberQuestions`, `uiLanguage`; the Mac's: `menuBarIcon`, `iCloudSync`, `checkForUpdates` |
| `input` | `inputLanguages`, `candidateLayout`, `fuzzyPinyin`, `learnsEnglishWords`, `englishWords`; the Mac's: `voiceInput` (while voice input is on) |
| `writing` | `outputLanguages`, `rewriteStyles`, `improveTranslates`, `jargonFile` |
| `provider` | `provider`; `<p>.model`, `<p>.key`, `<p>.baseURL`, `<p>.effort` for `anthropic`, `gemini`, `openai`; `bedrock.modelId`, `bedrock.awsProfile`, `bedrock.region`; `provider.test` |
| `request` | `maxTokens`, `temperature` (Bedrock), `timeoutSeconds` |
| `privacy` | `redaction.enabled`, `redaction.emails`, `.phones`, `.cards`, `.keys`, `.ips`, `redaction.customWords` |
| `agent` | `agent`, `agentCommand` (a custom agent), `claudeInBackground` (Claude Code); the Mac's: `agentPageContext` |
| `apps` | `apps.profiles`: an item per app with settings of its own (`win:notepad.exe`), its fields `apps.<app>.inputLanguage`, `.ownStyles`, `.rewriteStyles` (with its own styles), `.noAI`; the Mac's: `.typeOut`, `.translateAlways` |
| `plugins` | `plugins.installed`, `plugins.library` |
| `extensions` | `extensions.folders` (an item per folder), `extensions.installed`: an item per bundle (`bundle:<name>`) or script, its fields `extensions.on.<id>` (its switch; a bundle's commands' too, `<bundle>/<command>`) and a bundle's preferences `extensions.preference.<bundle>.<name>` (a password is a `secret`) |
| `search` | `search.key` |
| `notes` | `notes.destination`, `notes.folder`, `notes.notionToken`, `notes.notion` |
| `commands` | `commands.custom` |
| `advanced` | `configFile` |

### 12.4 Changes (`settingsSet`)

- **One at a time:** `field` and `value`. The value is checked against the field (its kind, bounds, choices), then set
  through the core's rules (the first input language is the default, a provider field emptied is unset …), then
  saved: only the keys that changed are written into `config.json`, the rest of the file as it was (keys a later version
  wrote too). Something else may have changed the file meanwhile: it is read again first.
- **Made on what the window showed** (both optional; a client may send either, both, or neither):
  - `revision`: the revision of the document the change was made on. When the settings have changed since (any change:
    another client's, the file's, a key), nothing changes and the answer is `problem.code` `stale`, with the document as
    it is now: draw it, and let the user make the change again. The revision moves with any change, so a client that
    sends it must keep its document current (`settingsChanged`).
  - `shown`, for a list (`words`, `choices`): the list as the window showed it; `value` is then the window's edit of
    it, made on the list as it is now. What the window took out goes, what it added is added, and what was added
    elsewhere meanwhile (another window, `allinoneime-cli`, sync) stays; what was taken out elsewhere stays out.
    `words` follow the Mac's rule (`RedactionSettings.edited`: the words added go at the end); `choices` keep the
    window's order of what it showed, and an item added elsewhere goes back after the one it came after. A `words`
    list whose order is its meaning (`ordered`: `agentCommand`, a command's arguments) isn't merged: changed since it
    was shown, it is `stale`. A `words` field with a line (`text`) may send lines for both, the one it showed and the
    one edited, split as `settingsSet` splits a line. `shown` on any other field is `badValue`.
  - **Neither** (what a client of before sends): `value` is the field's new value, whatever changed since. A list
    then replaces the list as it is, additions made elsewhere since included: send `shown` (or `revision`) to keep them.
- **The English words** (`englishWords`, the user's, the newest first) are a set, by their letters in any case
  (`EnglishWords.edit`): a word the value has that the list lacks is added as the Mac's Add adds it (as the user's),
  and one it lacks is removed, learned or added; a word only spelled another way stays as it was, and the order sent
  says nothing. A word added that isn't one (a Latin letter first, then letters, digits or `- . + & ' _ /`), or that
  hiding sensitive information hides (a key, a card or phone number, an address), is `badValue`: nothing changes.
- **Revisions and restarts:** the revision is the engine process's own count, from 1. After the engine restarts (`bye`,
  a lost pipe) the numbers start again and say nothing about the document a client kept: fetch it again (`settingsGet`)
  before making changes on a revision.
- **Refused:** `problem.code`:

| Code | Meaning |
|---|---|
| `unknownField` | no such field here: not on this platform, or not now (another provider's) |
| `badValue` | not a value the field takes (`message` says why: "Between 200 and 4000") |
| `notChangeable` | not changed this way: read-only, or an action the field doesn't have |
| `configBroken` | the config file can't be read; nothing is changed until it is fixed |
| `failed` | taken, but not done: the file couldn't be written (the settings are then as the file has them, `saveError` says why), the secret store refused, a test failed |
| `cancelled` | an action that takes a while stopped by `cancel`, or by the same action again |
| `stale` | made on a `revision` the settings have moved on from, or on a `shown` list that can't be merged (`ordered` words changed since): nothing changed |

### 12.5 Actions (`settingsAction`)

| `action` | On | Takes | Does |
|---|---|---|---|
| `setKey` | a `secret` | `key` | saves the key, for a provider's base URL as it is now (§12.8); an extension's password, in the same store |
| `removeKey` | a `secret` with it | — | removes the saved key |
| `test` | `provider.test`, `search.key`, `notes.notion` | `value`: the link, for `notes.notion` (none: the page kept) | Test Connection, a web search, the Notion link (found: @note saves there) |
| `browse` | `plugins.library` | — | downloads the library's signed index; the field's `items` are then what it offers |
| `install` | `plugins.library` | `item` (a plugin's name) | installs or updates it |
| `remove` | `plugins.installed` | `item` | removes the plugin |
| `save` | `commands.custom` | `value` (the command's definition, as `config.json` has it and the field's `schema` describes; `argv` may be the command line as typed), `item` (its name before; none for a new one) | saves it with the command editor's rules: a name taken, an empty prompt … are `badValue` |
| `delete` | `commands.custom` | `item` | deletes the command |
| `add` | `apps.profiles`, `extensions.folders` | `value`: the app (its program, "notepad.exe", or its id), the folder's path | an app listed with its own fields (saved once one is set), a folder read for extensions |
| `remove` | `apps.profiles`, `extensions.folders` | `item` | the app's settings, the folder |
| `hide`, `show` | `extensions.folders` | `item` | a folder the Mac found (Spotlight), hidden or shown again |
| `cancel` | a field with `test`, `browse` or `install` (and `item`, an install's plugin) | — | stops what runs there (§12.5, "Takes a while") |

- An action must be in the field's `actions` (or its item's).
- **Done at once:** `setKey`, `removeKey`, `remove`, `save`, `delete`, `add`, `hide`, `show`, `cancel`: the answer comes
  as any other.
- **Takes a while:** `test`, `browse`, `install` (a request to an AI provider, a download): the answer comes when it is
  done, perhaps after other frames; match it by `re`. The connection goes on meanwhile. A failed test is a `problem`
  (`failed`, "✗ …"); a test that passed says so in `message` ("✓ …"). Either is also the field's `status` from then on.
  - **While it runs** the document says so: the field (an install: its item) has `running: true` and `cancel` among
    its `actions`; a test's last outcome is gone from `status` (draw a spinner). The revision moves when it starts and
    when it is done (§12.6).
  - **`cancel`** stops it: answered at once (nothing running any more, done meanwhile: nothing to do), and the request
    it was running for is answered `problem.code` `cancelled`. What a stopped test would have found is never shown; a
    plugin installed before the stop came is installed (the document says so).
  - **The same action again** (same field and item) while one runs replaces it, as the Mac's Test button does: the
    first is answered `cancelled`.

### 12.6 `settingsChanged`

- Sent to every client that has the settings after any change: one it made (after its answer), another client's, a
  key saved or removed, an action that takes a while started, stopped or done (its outcome), the file changed by
  something else (the engine looks about once a second: `allinoneime-cli set-provider`, an editor, sync).
- `revision` is the new one. A client whose document is older sends `settingsGet` (at its own pace: several
  notifications may come for one change it hasn't fetched yet).

### 12.7 Ordering

- Answers and notifications go out in the order the engine made them (the pipe's `answersThroughPush`, Spec notes). A
  `settingsSet`, or an action done at once, is answered before the `settingsChanged` it causes; an action that takes a
  while may come after the `settingsChanged` of its outcome. A client is never told of an older revision after a newer
  one.
- **Where the work is done:** on one settings queue of the engine's, not the connection's: reading and writing
  `config.json`, the Credential Manager, a plugin's folder, the document. The watchdog (§2.5) doesn't count it, and
  the text services' keys never wait for it. Requests from settings clients are worked out one at a time.

### 12.8 Security

- **A key travels once:** `settingsAction setKey`'s `key`, client → engine. It is never in an answer, a document, a
  notification or a log: a document says only whether a key is set (`isSet`), where it is from and its last 4
  characters (`status`: "✓ Saved · ends in a1b2", "✓ From $OPENAI_API_KEY"), as the Mac's window shows it. It is kept
  in the Credential Manager (Windows), tied to the host of the provider's base URL as it is when saved.
- **Only trusted clients** (§12.1). A low-integrity or AppContainer process can't read or change the settings.
- **Trust is the transport's to state.** A connection is `untrusted` unless its transport found otherwise: the pipe
  reads the client's token (§2.1) and says its integrity and AppContainer flag; a transport added later that checks
  nothing (`WirePeer`'s default) gives no client the settings, nor what runs and sends (§8).
- **Logs:** the field and the action's name, never a value.
- **Limits:** `field` and `action` ≤ 256 units (over: `badMessage`); the frame limit (a settings window's 1 MiB,
  §2.2) bounds the rest.

### 12.9 What lives where

- **Core (AllInOneIMECore/Settings):** `SettingsStore` (config.json read and written key by key, the rules, the keys:
  the Mac's `SettingsModel` is a SwiftUI adapter over it), `SettingsService` (the document, `set`, the actions, the
  revision; thread-safe), `SettingsSchema` (the fields), `SettingsDocument` (the JSON).
- **Wire:** the messages in `WireMessages.swift`; `WireServer.settings` (a `SettingsService`; nil: none), its settings
  queue (§12.7), `checkSettings` (the file checked on that queue), and `useTestSettings` (`#! settings`, test mode).
- **Windows engine:** one `SettingsService` over its config file (`--config`, else `%APPDATA%\AllInOneIME\config.json`),
  checked for changes about once a second (`checkSettings`, from the watchdog's loop, which never waits for it). The
  English words it learns are written into that file under the service's lock (`SettingsService.writingFile`), never
  between a change's reading of the file and its writing, and read again at once (the windows are told). Its
  interface text in the nine languages of the core's String Catalog (`Localizable.xcstrings` beside it,
  `UIText.useCatalog`), in the language the settings pick (`UIText.choice`, applied after each change wherever it was
  made), else Windows' own.
- **Settings app (Windows/settings):** AllInOneIMESettings.exe, a C# WinUI 3 client that draws any document it is given.
- **Golden:** `settings.jsonl`, its documents and messages as the engine sends them (its config says English), but for
  what is the engine's own (`"$any"`): the config file's path, the jargon list's default path, the interface languages
  it ships. The document is in the language the settings say (`uiLanguage`, else the system's), whatever the
  engine's process speaks.

---

## Open questions

1. **Adapter or InputSession first?** `InputSession` (plan step 8) doesn't exist yet. Until it does, `ComposerSession` has to copy the gate in `InputController.handleKeyDown` (807–900): secure input, `MarkedTextWatch`, `selectionMoved`, catalog reload. We need to decide what goes into the adapter and what waits for step 8.
2. **Dead keys.** The Mac composes dead keys in the shell (`DeadKeyComposer` plus a `KeyTranslator`). On Windows, the engine would need a `KeyTranslator` built from the reported KLID (`LoadKeyboardLayout` inside the engine). That translator isn't written, so it's unproven.
3. **Alt combinations.** It isn't confirmed whether `WM_SYSKEYDOWN` (Alt combinations, F10) reaches `ITfKeyEventSink`. The Ctrl-tap action key doesn't depend on it, but an `isSystem` field may be needed.
4. **Rime and threads.** Running one serial queue per connection assumes librime is safe to use from several threads at once. If it isn't, everything goes on one engine queue, and a slow session delays every app's keys.
5. **Untrusted-client policy.** The `untrusted` feature set needs a classification for each command (runs, opens, reads, sends), which `Command` doesn't have yet.
6. **Starting the engine from sandboxed apps.** AppContainer and low-integrity clients can't start the engine. That needs a broker (a logon Run key or a scheduled task) in the installer, which isn't written.
7. **Keyboard layout per language.** The Mac's `inputLanguageChanged` switches the keyboard layout. It's unclear whether a TIP can switch its thread's HKL, so there's no output for it in v1.
8. **UI-less mode.** UI-less mode (`ITfUIElement`) needs a `PanelModel` on the wire, behind a capability. That depends on plan step 6.
9. **Timing numbers.** The 150 ms, 20 ms p99, 15 s keepalive and 50 ms first-draw figures all need measuring in M2.

---

## Spec notes

What the Swift side (`AllInOneIMEWire`, the Windows engine) found while building M1 and M2. **Where the text above disagrees with the real Composer, the Composer wins, and the goldens in `Core/Tests/AllInOneIMEWireTests/WireGoldens/` are the reference.** Both sides should read these notes as part of the contract.

### The goldens against §10

`notepad-improve.jsonl` is the §10 transcript in full, with every key. It differs from the sketch in §10:

- **What the composition shows.** The Composer shows a command without its "@": after "@" the composition is `@`, after "@i" it is `i`, and after "@improve " it is `improve › ` (the `›` is one UTF-16 unit). So the draft at Return is `improve › helo` (14 units), not `@improve hello`. `caret` and `comp` count what is shown.
- **"helo", not "hello".** The panel hides a version that only re-punctuates the original or another version. With the input "hello", "Hello." would be hidden and `1` would pick "Hi there.". The golden types "helo" so that `1` is "Hello.", as §10 intends. With the fixture's stream, the rows are 0 "helo", 1 "Hello.", 2 "Hi there.". "Hello!" re-punctuates "Hello." and is hidden too.
- **Rows start at the original.** Row 0 is the text as typed, row 1 the first version. The click golden uses `#! click row 1`, not `row 0`.
- **Output order.** A pick returns `panel shown:false` *before* the `commit` (`[{"op":"panel","shown":false},{"op":"commit","text":"Hello."}]`), in the order of the Composer's effects. Clients must not rely on the order of `panel` relative to text ops.
- **Ids and times.** The engine's ids are its own count. In the full golden, the `1` key is DLL id 24, engine id 21, and `t` values differ from the sketch.

### Golden format (§10)

- **`v`.** The engine sends `v` in every frame. A `<` line without `v` doesn't compare it. A replayer adds `v` to each `>` line that has none.
- **`"$any"` in a `>` line** (`client`, `pid`, `tid`, `hwnd`) marks a value that is the client's own. Replayers leave the field out. In a `<` line it matches any value that is present.
- **Directives.** A `(…)` after two spaces is a comment.
  - `#! provider <file>`: the scripted level-two stream. Each step is `{"after": ms, "versions": […], "final": bool}` or `{"after": ms, "error": "…"}`.
  - `#! inputLanguage <english|chinese|french|korean|hindi>`.
  - `#! advance <ms>`: move the manual clock, running what falls due.
  - `#! run tasks`: run every timer and queued task until none is left.
  - `#! click row <n>`: a click in the engine's panel.
  - `#! keys <text>`: typed in a field the client sends nothing from (the app gets the keys).
  - `#! connect`, `#! disconnect`: a new connection, or the client's end closed.
  - `#! closed`: the engine must have closed the connection.
  - `#! settings <file>`: the engine's settings are the test's own (§12): a config file with that file's text, in a folder of its own, its keys in memory and its plugins in that folder, never the user's.
- **Over a real transport** (`allinoneime-cli wire-replay`, engine started with `--test`), directives travel as `{"v":1,"id":0,"type":"x-test","directive":"…"}`, answered `{"id":0,"re":0,"type":"x-test","ok":true}`. `provider` carries its file's contents in `fixture`, `settings` its file's text in `config`. After each `>` line the replayer sends `x-test idle`: the frames before its answer are that line's. `x-test` is outside both sides' id counts, and an engine not in test mode answers it `unknownType`.

### Behaviour the text leaves open

- **First frame.** Anything but `hello` first gets `badMessage` and the connection closes. A frame whose `v` isn't the agreed version gets `badMessage` and the connection goes on.
- **Errors on notifications** (`open`, `focus`, `caret`, `close`, `applied`) carry `re`, the notification's id. `badFrame` and `tooLarge` carry no `re`: the frame wasn't read.
- **`open` again** for a known `sid` replaces its `field` and is not an error.
- **`focus` re-sent while focused** (§4: a new keyboard layout or input scope, noticed at the next key) keeps the same serial — the DLL increments the serial only for a real new focus or a reconnect — so an `apply` the engine already pushed for that focus still matches and applies. It doesn't blur or commit the draft. The DLL and engine agree on this (`focus-resent`).
- **`focus` without a `blur`** of the previously focused session: the engine blurs that session itself, and its outputs are dropped. The DLL must always send `blur` first (§4).
- **Order on a focus move.** TSF terminates a live composition before it moves the focus, so the DLL sends `endComposition {terminated}` (the draft committed as typed) and *then* `blur`, which finds nothing left to commit (`focus-moves`).
- **Caret reports** are sent only while the panel is shown (§6). The engine forgets the last caret when the panel hides, so a panel shown again waits for a fresh report rather than anchoring at the stale rectangle.
- **A field that turns secure** (`focus` re-sent with `secure:true`) while a draft is pending gets the draft committed as typed, pushed as `apply` (`focus` has no result), with `panel shown:false`. A key from a secure field, if one comes anyway, is `handled:false`, with a notice in the engine and no composition.
- **`blur` and `endComposition terminated`** commit the draft *as typed*, with its "@" (`@improve helo`), not as shown, and hide the panel.
- **`endComposition timeout`** returns `panel shown:false` and **no** `composition` (reconciled with the DLL; the earlier draft said `composition ""`). The DLL ended the composition itself before passing the key, keeping the draft *as typed* (`composition.typed`), so the text is not lost: in `timeout-resync`, "@im" + "p" (the engine shows "im") leaves "@imp" plus the passed-through key. An empty `composition` from the engine would wrongly delete that kept text.
- **A lost engine** (§2.5): the client keeps its composition's text *as typed* (`composition.typed`), not as shown. After a broken pipe during "@imp" the document keeps "@im" (the engine showed "im"), with the "@" (`reconnect`). (The earlier draft kept the shown text, "imp"; the DLL and engine now agree the user's typed text is what survives.)
- **Esc during a stream:** the first Esc cancels and returns the draft (style `draft`) with the panel still shown. A second Esc gives the draft up (`composition ""`, `panel shown:false`).
- **A failed request** (`Composer.fail`) only shows the failure in the engine's panel: no frame. Esc gives the draft back.
- **The `comp` check** (§5.1): when the app took the composition, the key that reveals it is answered `handled:true` and dropped (so ⏎ doesn't send half a sentence). Its outputs come from the Composer's `appTookMarkedText`: `panel shown:false`, and a running request stops. The document's text is left as it is.
- **Held compositions** (§7): while a session's last `apply` is unacknowledged, a push of compositions only is held, and a newer one replaces it. A held push goes out with the next `applied`, or is put in front of the outputs of that session's next `result`.
- **Modifier key-downs** that repeat (`isRepeat`) are dropped. A fake Shift (`isFakeShift`) gets `result` with nothing.
- **Canonical form exceptions:** `composition.text` is always written (empty ends the composition), and so are `panel.shown` and `welcome.capabilities` (`[]`).
- **The key rate** (§8) counts every `keyDown` and `keyUp`, including those refused with `badMessage`. Over 200 in a second they get `error limit` (no work done), which the DLL treats as `handled:false` (§3).
- **The engine's `app` and `process`** (§4) are the executable's file name in lower case (`win:notepad.exe`; Windows names aren't case-sensitive), or `win:<AUMID>` for packaged apps.
- **Untrusted clients** (§8, Open question 5): until `Command` has a classification, the engine refuses for untrusted clients, and for a key from a process that doesn't own the foreground, every effect that runs, opens, searches, reads the clipboard, records, keeps or sends. That includes `@question` and `@agent` (`startCommand`). Typing and AI rewriting and translating (`startConversion`, `startRefine`, `startTranslateMode`) are allowed.
- **Type-out** (§6): `typeOut` is committed in one `commit` for now. The step-by-step `apply` series isn't built.
- **The panel and the foreground** (§6, §8, the Windows engine): the engine draws its panel and notices only while the
  client's process is the app in front: the foreground window is its own, or the focus window of that window's thread
  is, or a window inside the foreground window is (a WebView2's, whose client is msedgewebview2.exe; a UWP app's in its
  frame). A classic console's window says it is its client's (cmd.exe): it is the conhost.exe's that made it, where TSF
  and the DLL run. A caret report places the panel only inside the window its `hwnd` names, if that window is the
  client's process's (with no `hwnd`, the foreground window, if the client is in front), the rectangle cut to that
  window; a report naming another process's window is ignored, and the panel goes where the system caret is. A notice
  for one session never replaces another session's panel.

### Windows transport (§2)

- **§2.1's label check contradicts its SDDL.** The SDDL's `S:(ML;;NW;;;LW)` gives the real engine's pipe a *low* label, so that low-integrity clients can write. A check that the pipe's label is "medium or higher" always fails, and a low-integrity squatter's pipe looks the same. The DLL should check the *server process* instead:
  1. `GetNamedPipeServerProcessId`;
  2. `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)`;
  3. `OpenProcessToken(TOKEN_QUERY)`;
  4. the token's user is the DLL's and its integrity is medium or higher.

  Keep the session check and the owner check: the pipe's owner is the user's SID, which held even for an elevated engine. `allinoneime-cli wire-replay` checks it this way.

  This was tested from a **low-integrity client** (a copy of the CLI labelled low with `icacls /setintegritylevel low`): it connects, the engine marks it `low, untrusted`, the server-process check works (the high-integrity engine's token can be read), and the goldens pass. AppContainer clients aren't tested yet.
- **Order of answers and pushes.** The pipe's reader thread writes a request's answers after `receive` returns, while the connection's queue can push an `apply` from async work in between. The client would then get the push before an older result. The engine therefore sets `answersThroughPush`: answers are written on the queue, in the order the queue made them.
- **A client that doesn't read.** Writes wait at most 500 ms, then the connection is dropped. They happen on the session queue, so a longer wait would let the 2 s watchdog (§2.5) kill the engine for every app. Tested: a client that sends keys and never reads is dropped after about 0.6 s, and the engine serves the next client.
- **Unread data on close.** After a fatal error the engine writes the error, then waits up to 1 s for the client to close its end before it closes its own. It never calls `DisconnectNamedPipe`, which discards unread data. A DLL should close as soon as it has read a fatal error.
- **Relaunch race.** An engine started right after the previous one exited can find the old pipe still there for a moment: the first instance fails with `ERROR_ACCESS_DENIED` although the engine holds the mutex. It retries for 2 s before it exits.
- **Sessions under OpenSSH.** Processes started over OpenSSH run in session 0, at high integrity for an administrator. The engine and its clients still pass the checks: same session, same user.

### Timing (M2, measured)

Measured on a Ryzen 5 5600X running Windows 11, release build, `wire-replay` against `AllInOneIMEEngine --test`. Details are in `Windows/README.md`.

- **Cold start:** about 31 ms (p50) from launch to `welcome`.
- **Key round trip:** p50 0.09 ms, p99 0.30 ms, from the write to the `result` read, Latin input. That is far inside the 20 ms p99 budget and the 150 ms timeout.

Not measured yet: the keepalive and the first draw, which need the DLL and the panel.
